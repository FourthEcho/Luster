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

layout(location = 0) out vec4 indirectCurrent;   // colortex17
layout(location = 1) out vec4 indirectHistory;   // colortex18
layout(location = 2) out vec4 historyGData; // colortex20

/* RENDERTARGETS: 17,18,20 */

const bool colortex18Clear = false;
const bool colortex20Clear = false;

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex1;  // gbuffer 0
uniform sampler2D colortex6;  // selected shader AO (SSAO/GTAO/none)
uniform sampler2D colortex14; // AO history depth for depth-aware AO upscale
uniform sampler2D colortex17; // sspt raw color + geometry-hit flag
uniform sampler2D colortex18; // sspt history color + frames
uniform sampler2D colortex19; // sspt gbuffer data
uniform sampler2D colortex20; // sspt history gdata

uniform sampler2D depthtex1;  // geometry depth (non-DH path)

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform vec2 viewRes;
uniform vec2 taaOffset;

uniform bool worldAgeChanged;

// ------------
//   Includes
// ------------

#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
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

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL
#include "/lib/util/lodMod.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

// Mean of two values.
float avgOf(vec2 v) {
    return (v.x + v.y) * 0.5;
}

float fetchFallbackAo(vec2 uv, float linZ, bool isHand) {
    if (isHand) {
        return 1.0;
    }
#if shaderAo == shaderAoNone
    return 1.0;
#else
    vec2 aoSize = vec2(textureSize(colortex6, 0));
    vec2 aoPos = uv * aoSize - 0.5;
    ivec2 base = ivec2(floor(aoPos));
    vec2 f = fract(aoPos);

    vec4 aoTaps;
    vec4 aoDepths;
    aoTaps.x = texelFetch(colortex6, clamp(base, ivec2(0), ivec2(aoSize) - 1), 0).x;
    aoTaps.y = texelFetch(colortex6, clamp(base + ivec2(1, 0), ivec2(0), ivec2(aoSize) - 1), 0).x;
    aoTaps.z = texelFetch(colortex6, clamp(base + ivec2(0, 1), ivec2(0), ivec2(aoSize) - 1), 0).x;
    aoTaps.w = texelFetch(colortex6, clamp(base + ivec2(1, 1), ivec2(0), ivec2(aoSize) - 1), 0).x;

    aoDepths.x = texelFetch(colortex14, clamp(base, ivec2(0), ivec2(aoSize) - 1), 0).x;
    aoDepths.y = texelFetch(colortex14, clamp(base + ivec2(1, 0), ivec2(0), ivec2(aoSize) - 1), 0).x;
    aoDepths.z = texelFetch(colortex14, clamp(base + ivec2(0, 1), ivec2(0), ivec2(aoSize) - 1), 0).x;
    aoDepths.w = texelFetch(colortex14, clamp(base + ivec2(1, 1), ivec2(0), ivec2(aoSize) - 1), 0).x;

    vec4 w;
    w.x = exp2(-10.0 * abs(screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.x) - linZ));
    w.y = exp2(-10.0 * abs(screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.y) - linZ));
    w.z = exp2(-10.0 * abs(screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.z) - linZ));
    w.w = exp2(-10.0 * abs(screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.w) - linZ));

    w.x *= (1.0 - f.x) * (1.0 - f.y);
    w.y *= f.x * (1.0 - f.y);
    w.z *= (1.0 - f.x) * f.y;
    w.w *= f.x * f.y;

    float wSum = w.x + w.y + w.z + w.w;
    if (wSum <= 1e-6) {
        return clamp01(dot(aoTaps, vec4(0.25)));
    }
    return clamp01(dot(aoTaps, w) / wSum);
#endif
}

/* ------ REPROJECTION ------ */

vec3 reprojectHistory(vec3 sceneSpace) {
    vec3 prevPos = sceneSpace + (cameraPosition - previousCameraPosition);
    prevPos = transform(gbufferPreviousModelView, prevPos);
    prevPos = projectAndDivide(gbufferPreviousProjection, prevPos);
    return prevPos * 0.5 + 0.5;
}

/* ------ EDGE-AWARE SPATIAL FILTERS ------ */

vec3 spatialColor(ivec2 texel) {
    // 5x5 gather, normal + depth + luma weighted.
    vec3 totalColor = texelFetch(colortex17, texel, 0).rgb;
    float sumWeight = 1.0;
    float lumaCenter = getLuma(totalColor);

    vec4 gbuffer = fetchGbuffer(texel);

    const int r = 2;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 tap = clampTexel(texel + ivec2(x, y));

            vec4 gb = fetchGbuffer(tap);

            float depthDelta = distance(gb.w, gbuffer.w) * far;

            if (depthDelta < 2.0) {
                vec3 currentColor = texelFetch(colortex17, tap, 0).rgb;

                float lum = getLuma(currentColor);

                float distLum = abs(lumaCenter - lum);
                    distLum = sqr(distLum) / max(lumaCenter, 0.027);
                    distLum = clamp(distLum, 0.0, pi);

                float weight = pow(max0(dot(gbuffer.xyz, gb.xyz)), 8.0)
                             * exp(-depthDelta - sqrt(distLum) * rcpPi);

                totalColor += currentColor * weight;
                sumWeight += weight;
            }
        }
    }

    return totalColor / sumWeight;
}

vec3 spatialColor7x7(ivec2 texel, inout vec2 variance, out float maxLum) {
    // 7x7 gather, normal + depth weighted; also builds variance moments.
    vec3 totalColor = texelFetch(colortex17, texel, 0).rgb;
    float sumWeight = 1.0;
    float lumaCenter = getLuma(totalColor);

        maxLum = lumaCenter;

    vec4 gbuffer = fetchGbuffer(texel);

    const int r = 3;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 tap = clampTexel(texel + ivec2(x, y));

            vec4 gb = fetchGbuffer(tap);

            float depthDelta = distance(gb.w, gbuffer.w) * far;

            if (depthDelta < 2.0) {
                vec3 currentColor = texelFetch(colortex17, tap, 0).rgb;

                float weight = pow(max0(dot(gbuffer.xyz, gb.xyz)), 2.0);
                float currentLuma = getLuma(currentColor);

                maxLum = max(maxLum, currentLuma);

                totalColor += currentColor * weight;
                variance += vec2(currentLuma * weight, sqr(currentLuma) * sqr(weight));
                sumWeight += weight;
            }
        }
    }

    totalColor /= sumWeight;
    variance /= vec2(sumWeight, sqr(sumWeight));

    maxLum = clamp(maxLum, 0.0, 2.71) * rcpPi;

    return totalColor;
}

// ------------
//   Main
// ------------

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbufferTexel = ivec2(uv * viewRes * taauViewportScale);

    historyGData = vec4(1.0); // .w = 1 -> sqr(1) never matches currentDistance
    indirectHistory = vec4(0.0);
    indirectCurrent = vec4(texelFetch(colortex17, texel, 0).rgb, 0.0);

    float depth = texelFetch(combinedDepthTex, gbufferTexel, 0).x;

    if (depth >= 1.0) return;

    vec3 screenPos = vec3(uv, depth);
    vec3 viewPos = screenToViewSpace(
        combinedProjectionMatrixInverse,
        screenPos,
        true
    );
    vec3 scenePos = viewToSceneSpace(viewPos);

    float currentDistance = clamp01(length(scenePos) / far);

    vec3 reprojection = reprojectHistory(scenePos);

    bool offscreen = clamp01(reprojection.xy) != reprojection.xy;

    // History texel + subpixel weights, 4-tap bilinear.
    ivec2 repTexel = ivec2(floor(reprojection.xy * bufferSize() - vec2(0.5)));
    vec2 subpix = fract(reprojection.xy * bufferSize() - vec2(0.5) - repTexel);

    const ivec2 offset[4] = ivec2[4](
        ivec2(0, 0),
        ivec2(1, 0),
        ivec2(0, 1),
        ivec2(1, 1)
    );

    float weight[4] = float[4](
        (1.0 - subpix.x) * (1.0 - subpix.y),
        subpix.x         * (1.0 - subpix.y),
        (1.0 - subpix.x) * subpix.y,
        subpix.x         * subpix.y
    );

    vec2 lightmapSource = unpackUnorm2x8(
        texelFetch(colortex1, gbufferTexel, 0).w
    );

    float lightmap = pow5(lightmapSource.x);

    // Depth-aware finishing for the fallback: same scalar visibility as the
    // trace pass for both DSSAO and DGTAO, hands excluded.
    float linZ = screenToViewSpaceDepth(
        combinedProjectionMatrixInverse,
        depth
    );
    bool isHand = depth < handDepth;
    float ao = fetchFallbackAo(uv, linZ, isHand);

    vec3 rtLight = vec3(0.0);
    float samples = 0.0;
    float variance = 0.0;
    vec2 varianceData = vec2(0.0);


    // The trace pass finishes bounced radiance with AO while preserving
    // emission. Apply AO here only to the lightmap fallback when the ray
    // paths miss all geometry. With shaderAoNone, ao is 1.0 by construction.
    float ssptGeometryHit = texelFetch(colortex17, texel, 0).a;
    float missAo = mix(ao, 1.0, ssptGeometryHit);
    float rawLightmapWeight = lightmap * sqr(missAo) * ssptLightmapBlend;

    if (offscreen || worldAgeChanged) {
        // Offscreen / world-change path: spatial estimate only.
        rtLight = spatialColor7x7(texel, varianceData, variance);
        samples = 1.0;
    } else {
        vec4 previousLight = vec4(0.0); // rgb + frames
        vec3 previousAux = vec3(0.0);   // variance moments + lightmap

        float sumWeight = 0.0;

        // Camera-motion depth rejection tolerance.
        vec3 cameraMovement
            = mat3(gbufferModelView) * (cameraPosition - previousCameraPosition);

        // Sample history with depth rejection.
        for (int i = 0; i < 4; ++i) {
            ivec2 historyTexel = repTexel + offset[i];

            if (clampTexel(historyTexel) != historyTexel) continue;

            vec4 historyG = texelFetch(colortex20, historyTexel, 0);

            float depthDelta = distance(sqr(historyG.w), currentDistance)
                              - abs(cameraMovement.z / far);
            bool depthRejection = (depthDelta / max(currentDistance, 1e-6)) < 0.1;

            if (depthRejection) {
                previousLight += max0(texelFetch(colortex18, historyTexel, 0)) * weight[i];
                previousAux += historyG.xyz * weight[i];
                sumWeight += weight[i];
            }
        }

        if (sumWeight > 1e-3) {
            previousLight /= sumWeight;
            previousAux /= sumWeight;

            // Accumulation alpha schedule.
            float frames = min(previousLight.a + 1.0, maxFrames);
            float alphaColor = max(0.01 * 1.0, 1.0 / frames);
            float alphaVariance = max(0.02 * 1.0, 1.0 / frames);

            // Adaptive rejection from the lightmap delta.
            float adaptDelta = sqr(
                max0(abs(lightmap - previousAux.z) - (1.0 / 1024.0))
                    / (avgOf(vec2(lightmap, previousAux.z)) + 5e-3)
            );

            float rejection = 1.0 / (1.0 + adaptDelta);
                rejection = clamp01(1.0 - rejection);
                rejection = clamp01(0.71 * rejection * 1.0);

            alphaColor = max(rejection, alphaColor);
            alphaVariance = max(rejection, alphaVariance);

            vec3 currentLight = spatialColor(texel);

            float currentLuma = getLuma(currentLight);
            vec2 currentVariance = vec2(currentLuma, sqr(currentLuma));
                varianceData = mix(previousAux.xy, currentVariance, alphaVariance);

            rtLight = mix(previousLight.rgb, currentLight, alphaColor);
            variance = sqrt(max0(varianceData.y - sqr(varianceData.x)))
                     / max(varianceData.x, 1e-8);
                variance *= max(1.0 + rejection * sqrt(2.0), 4.0 / frames);
            samples = frames;

            lightmap = mix(previousAux.z, lightmap, max(0.2, 1.0 / frames));
        } else {
            rtLight = spatialColor7x7(texel, varianceData, variance);
            samples = 1.0;
        }
    }

    // Merge the blocklight fallback after AO-finished traced contributions.
    vec3 current = rtLight + rawLightmapWeight * blocklightColor * rcp(tau);

    indirectCurrent = vec4(current, variance);
    indirectHistory = vec4(rtLight, samples);
    historyGData = vec4(
        clamp01(varianceData),
        lightmap,
        sqrt(currentDistance)
    );
}
