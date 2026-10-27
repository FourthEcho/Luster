/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#include "/lib/global.glsl"

// This pass only runs when the SVGF filter is enabled (see program.*.enabled in
// shaders.properties), but Iris only registers a boolean option as a settings toggle if
// it is #ifdef-checked in shader code at least once.
#ifdef svgfFilter
#define SVGF_FILTER_ACTIVE 1
#endif

#ifndef SVGF_SIZE
#define SVGF_SIZE 4
#endif

layout(location = 0) out vec4 filtered; // colortex17

/* RENDERTARGETS: 17 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex17; // sspt color + sigma
uniform sampler2D colortex18; // sspt history frames
uniform sampler2D colortex19; // sspt gbuffer data

// Required on the non-DH path: SSPT_FILTER_DEPTH_TEX expands to depthtex1.
uniform sampler2D depthtex1;

// SVGF pass only needs combined depth; avoid full LoD include because Voxy's
// patched deferred programs don't expose required projection uniforms.
#if defined DISTANT_HORIZONS || defined VOXY
#ifndef LUSTER_COLORTEX15_DECLARED
#define LUSTER_COLORTEX15_DECLARED
uniform sampler2D colortex15; // merged vanilla + LoD/Voxy depth
#endif
#define SSPT_FILTER_DEPTH_TEX colortex15
#else
#define SSPT_FILTER_DEPTH_TEX depthtex1
#endif

uniform vec2 viewRes;

// ------------
//   Includes
// ------------

#if !defined INCLUDE_LIGHT_INDIRECT_LIGHT_TEMPORAL
#define INCLUDE_LIGHT_INDIRECT_LIGHT_TEMPORAL

// Shared bookkeeping for the SSPT temporal passes (d5 accumulate + SVGF
// filter): target-sized buffer helpers and the packed-gbuffer fetch.

#include "/lib/util/color.glsl"

// SSPT buffer bookkeeping uses the actual allocated target size for every reduction setting.

// Relative luminance in the pack's working color space (Rec. 2020).
float getLuma(vec3 c) {
    return dot(c, luminanceWeights);
}

vec2 bufferSize() {
    return vec2(textureSize(colortex17, 0));
}

ivec2 clampTexel(ivec2 texel) {
    return clamp(texel, ivec2(0), ivec2(bufferSize()) - 1);
}

vec4 fetchGbuffer(ivec2 texel) {
    vec4 val = texelFetch(colortex19, texel, 0);
    return vec4(val.rgb * 2.0 - 1.0, sqr(val.a));
}

#endif // INCLUDE_LIGHT_INDIRECT_LIGHT_TEMPORAL
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"

/* ------ ATROUS SVGF ------ */

// 3x3 gaussian-weighted sigma estimate over the
// color buffer's variance channel (.a)
const float gaussKernel[4] = float[4](
    1.0 / 4.0, 1.0 / 8.0,
    1.0 / 8.0, 1.0 / 16.0
);

float computeSigmaL(ivec2 texel, float center) {
    float sum = center * gaussKernel[0];

    const int r = 1;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            if (x != 0 || y != 0) {
                ivec2 tap = clampTexel(texel + ivec2(x, y));
                float variance = texelFetch(colortex17, tap, 0).a;
                float w = gaussKernel[abs(y) * 2 + abs(x)];
                sum += variance * w;
            }
        }
    }

    return sqrt(max(sum, 1e-8));
}

vec4 atrousSVGF(ivec2 texel, const int size) {
    vec4 centerData = fetchGbuffer(texel);

    vec4 centerColor = texelFetch(colortex17, texel, 0);
    float centerLuma = getLuma(centerColor.rgb);

    // Pixel age drives how aggressively the filter converges.
    float frames = texelFetch(colortex18, texel, 0).a;

    float sigmaBias = (4.0 / max(frames, 1.0)) + 0.25;
    float maxDelta = mix(halfPi, tau, clamp01(frames / 32.0));
    float offset = mix(0.04 / (0.5 * svgfRad), 0.03, clamp01(frames / 32.0));
    float sigmaMul = mix(2.718281828459045, 0.41, clamp01(frames / 16.0));

    float sigmaDistMul = 2.0 - (1.0 / (1.0 + centerData.a / 64.0));

    float sigmaL = 1.0 / (
        sigmaMul * svgfStrictness * sigmaDistMul
            * computeSigmaL(texel, centerColor.a)
        + sigmaBias * sigmaDistMul
    );

    float normalExp = mix(2.0, 8.0, clamp01(frames / 8.0)) * svgfNormalexp;

    vec4 total = centerColor;
    float totalWeight = 1.0;

    const int r = svgfRad;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            ivec2 p = texel + ivec2(x, y) * size;

            if (x == 0 && y == 0) continue;

            bool valid = all(greaterThanEqual(p, ivec2(0)))
                      && all(lessThan(p, ivec2(bufferSize())));

            if (!valid) continue;

            vec4 currentData = fetchGbuffer(p);

            vec4 currentColor = texelFetch(colortex17, p, 0);
            float currentLuma = getLuma(currentColor.rgb);

            float w = 1.0;

            float distLum = abs(centerLuma - currentLuma);
                distLum = sqr(distLum) / max(centerLuma, offset);
                distLum = clamp(distLum, 0.0, maxDelta);

            float distDepth = abs(centerData.a - currentData.a) * 4.0;

                w *= pow(max0(dot(centerData.xyz, currentData.xyz)), normalExp);
                w *= exp(-distDepth / sqrt(float(size)) - sqrt(distLum * sigmaL));

            // accumulate stuff
            total += currentColor * w * vec4(1.0, 1.0, 1.0, w);

            totalWeight += w;
        }
    }

    // compensate for total sampling weight
    total /= vec4(totalWeight, totalWeight, totalWeight, sqr(totalWeight));

    return total;
}

// ------------
//   Main
// ------------

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbufferTexel = ivec2(uv * viewRes * taauViewportScale);

    float depth = texelFetch(SSPT_FILTER_DEPTH_TEX, gbufferTexel, 0).x;

    if (depth < 1.0) {
        filtered = atrousSVGF(texel, SVGF_SIZE);
    } else {
        filtered = texelFetch(colortex17, texel, 0);
    }
}
