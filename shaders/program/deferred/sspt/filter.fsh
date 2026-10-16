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


#ifdef svgfFilter
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

uniform sampler2D depthtex1; // vanilla geometry depth

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

uniform vec2 view_res;

// ------------
//   Includes
// ------------

#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL

// Shared bookkeeping for the SSPT temporal passes (d5 accumulate + SVGF
// filter): target-sized buffer helpers and the packed-gbuffer fetch.

#include "/lib/util/color.glsl"

// SSPT buffer bookkeeping uses the actual allocated target size for every reduction setting.

// Relative luminance in the pack's working color space (Rec. 2020).
float getLuma(vec3 c) {
    return dot(c, luminance_weights);
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

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL
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
    vec4 center_data = fetchGbuffer(texel);

    vec4 center_color = texelFetch(colortex17, texel, 0);
    float center_luma = getLuma(center_color.rgb);

    // Pixel age drives how aggressively the filter converges.
    float frames = texelFetch(colortex18, texel, 0).a;

    float sigma_bias = (4.0 / max(frames, 1.0)) + 0.25;
    float max_delta = mix(half_pi, tau, clamp01(frames / 32.0));
    float offset = mix(0.04 / (0.5 * svgfRad), 0.03, clamp01(frames / 32.0));
    float sigma_mul = mix(2.718281828459045, 0.41, clamp01(frames / 16.0));

    float sigma_dist_mul = 2.0 - (1.0 / (1.0 + center_data.a / 64.0));

    float sigma_l = 1.0 / (
        sigma_mul * svgfStrictness * sigma_dist_mul
            * computeSigmaL(texel, center_color.a)
        + sigma_bias * sigma_dist_mul
    );

    float normal_exp = mix(2.0, 8.0, clamp01(frames / 8.0)) * svgfNormalexp;

    vec4 total = center_color;
    float total_weight = 1.0;

    const int r = svgfRad;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            ivec2 p = texel + ivec2(x, y) * size;

            if (x == 0 && y == 0) continue;

            bool valid = all(greaterThanEqual(p, ivec2(0)))
                      && all(lessThan(p, ivec2(bufferSize())));

            if (!valid) continue;

            vec4 current_data = fetchGbuffer(p);

            vec4 current_color = texelFetch(colortex17, p, 0);
            float current_luma = getLuma(current_color.rgb);

            float w = 1.0;

            float dist_lum = abs(center_luma - current_luma);
                dist_lum = sqr(dist_lum) / max(center_luma, offset);
                dist_lum = clamp(dist_lum, 0.0, max_delta);

            float dist_depth = abs(center_data.a - current_data.a) * 4.0;

                w *= pow(max0(dot(center_data.xyz, current_data.xyz)), normal_exp);
                w *= exp(-dist_depth / sqrt(float(size)) - sqrt(dist_lum * sigma_l));

            // accumulate stuff
            total += current_color * w * vec4(1.0, 1.0, 1.0, w);

            total_weight += w;
        }
    }

    // compensate for total sampling weight
    total /= vec4(total_weight, total_weight, total_weight, sqr(total_weight));

    return total;
}

// ------------
//   Main
// ------------

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    float depth = texelFetch(SSPT_FILTER_DEPTH_TEX, gbuffer_texel, 0).x;

    if (depth < 1.0) {
        filtered = atrousSVGF(texel, SVGF_SIZE);
    } else {
        filtered = texelFetch(colortex17, texel, 0);
    }
}
