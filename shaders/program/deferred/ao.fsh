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

layout(
    location = 0
) out vec4 ambient; // ao, ambient sss, octahedrally encoded bent normal
layout(location = 1) out vec2 ambientHistoryData; // depth, pixel age

/* RENDERTARGETS: 6,14 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex6; // ambient lighting data
uniform sampler2D colortex14; // ambient lighting history data

uniform sampler2D depthtex1;

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

uniform int frameCounter;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION
#include "/lib/util/lodMod.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
// Spherical linear interpolation of two unit vectors
vec3 slerp(vec3 v0, vec3 v1, float t) {
    float cosTheta = clamp(dot(v0, v1), -1.0, 1.0);
    if (cosTheta > 0.999) {
        return v0;
    }

    float theta = fastAcos(cosTheta);
    float rcpSinTheta = rcp(max(sin(theta), 1e-4));

    float w0 = rcpSinTheta * sin((1.0 - t) * theta);
    float w1 = rcpSinTheta * sin(t * theta);

    return v0 * w0 + v1 * w1;
}
#include "/lib/util/spaceConversion.glsl"

#if shaderAo == shaderAoSsao
#if !defined INCLUDE_LIGHT_INDIRECT_LIGHT_SSAO
#define INCLUDE_LIGHT_INDIRECT_LIGHT_SSAO

#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

vec2 getDssaoSampleOffset(float radiusStep) {
    float angle = fract(radiusStep * 8.0) * pi;
    return vec2(cos(angle), sin(angle)) * radiusStep;
}

float computeDssao(
    vec3 positionScreen,
    vec3 sceneNormal,
    vec2 dither
) {
    const float maxOcclusionDistance = tau;
    const float antiBleedExponent = 0.71;

    float currentDepth = screenToViewSpaceDepth(
        combinedProjectionMatrixInverse,
        positionScreen.z
    );

    float orientationScale = 0.75
        + abs(1.0 - clamp(dot(normalize(sceneNormal), vec3(0.0, 1.0, 0.0)), -1.0, 1.0)) * 0.5;
    float radius = max(ssaoRadius, 0.25) * orientationScale;

    float fovScale = abs(combinedProjectionMatrix[1][1]) / 1.37;
    float aspectInverse = viewRes.y / max(viewRes.x, 1.0);
    vec2 screenScale = radius * vec2(aspectInverse, 1.0)
        * fovScale / max(currentDepth, 5.0);

    int sampleCount = max(ssaoSteps, 1);
    float sampleStep = 1.2 / float(sampleCount);
    float radiusStep = sampleStep * (1.0 + dither.x);
    float depthScale = 0.7 / max(radius, 1e-3);
    vec2 texelHalf = 0.5 / vec2(textureSize(combinedDepthTex, 0));
    vec2 uvMin = texelHalf;
    vec2 uvMax = vec2(1.0) - texelHalf;

    float visibility = 0.0;

    for (int i = 0; i < sampleCount; ++i) {
        vec2 offset = getDssaoSampleOffset(radiusStep) * screenScale;
        vec2 sampleUvA = clamp(positionScreen.xy + offset, uvMin, uvMax);
        vec2 sampleUvB = clamp(positionScreen.xy - offset, uvMin, uvMax);

        float sampleDepthA = texture(combinedDepthTex, sampleUvA).x;
        float sampleDepthB = texture(combinedDepthTex, sampleUvB).x;
        float linearDepthA = screenToViewSpaceDepth(
            combinedProjectionMatrixInverse,
            sampleDepthA
        );
        float linearDepthB = screenToViewSpaceDepth(
            combinedProjectionMatrixInverse,
            sampleDepthB
        );

        float sampleDeltaA = (currentDepth - linearDepthA) * depthScale;
        float sampleDeltaB = (currentDepth - linearDepthB) * depthScale;

        float antiBleedA = 1.0 - rcp(
            1.0 + max0(abs(linearDepthA - currentDepth) - maxOcclusionDistance)
                * antiBleedExponent
        );
        float antiBleedB = 1.0 - rcp(
            1.0 + max0(abs(linearDepthB - currentDepth) - maxOcclusionDistance)
                * antiBleedExponent
        );

        float angle = mix(clamp01(0.5 - sampleDeltaA), 0.5, antiBleedA);
        float distanceTerm = mix(clamp01(0.25 * sampleDeltaA - 1.0), 0.5, antiBleedA);
        angle += mix(clamp01(0.5 - sampleDeltaB), 0.5, antiBleedB);
        distanceTerm += mix(clamp01(0.25 * sampleDeltaB - 1.0), 0.5, antiBleedB);

        visibility += clamp01(angle + distanceTerm);
        radiusStep += sampleStep;
    }

    return clamp01(visibility / float(sampleCount));
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSAO
#endif

#if shaderAo == shaderAoGtao
#if !defined INCLUDE_LIGHT_INDIRECT_LIGHT_GTAO
#define INCLUDE_LIGHT_INDIRECT_LIGHT_GTAO

#include "/lib/util/lodMod.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

float integrateArc(vec2 h, float n, float cosN) {
    vec2 tmp = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n);
    return 0.25 * (tmp.x + tmp.y);
}

float computeMaximumHorizonAngle(
    vec3 viewSliceDir,
    vec3 viewerDir,
    vec3 screenPos,
    vec3 viewPos,
    float radius,
    float dither,
    bool isLod
) {
    float stepSize = (gtaoRadius * rcp(float(gtaoHorizonSteps))) * radius;

    float maxCosTheta = -1.0;

    vec2 rayStep
        = (viewToScreenSpace(
               viewPos + viewSliceDir * stepSize,
               true,
               isLod
           )
           - screenPos)
              .xy;
    vec2 rayPos = screenPos.xy
        + rayStep * (dither + maxOf(viewPixelSize) * rcpLength(rayStep));

    for (int i = 0; i < gtaoHorizonSteps; ++i, rayPos += rayStep) {
        ivec2 texel
            = ivec2(clamp01(rayPos) * viewRes * taauViewportScale + 0.5);
        float depth = texelFetch(combinedDepthTex, texel, 0).x;

        if (depth == 1.0 || depth < handDepth || depth == screenPos.z) {
            continue;
        }

        vec3 offset = screenToViewSpace(
                          combinedProjectionMatrixInverse,
                          vec3(rayPos, depth),
                          true
                      )
            - viewPos;

        float lenSq = lengthSquared(offset);

        // Self-sample: zero offset would make inversesqrt diverge
        if (lenSq < eps) {
            continue;
        }

        float norm = inversesqrt(lenSq);

        float distanceFalloff = linearStep(
            gtaoFalloffStart * gtaoRadius,
            gtaoRadius,
            lenSq * norm * rcp(radius)
        );

        float cosTheta = dot(viewerDir, offset) * norm;
        cosTheta = mix(cosTheta, -1.0, distanceFalloff);

        maxCosTheta = max(cosTheta, maxCosTheta);
    }

    return fastAcos(clamp(maxCosTheta, -1.0, 1.0));
}

vec2 computeGtao(
    vec3 screenPos,
    vec3 viewPos,
    vec3 viewNormal,
    vec2 dither,
    bool isLod,
    float surfaceAlbedo,
    out vec3 bentNormal
) {
    float ao = 0.0;
    float ambientSss = 0.0;
    bentNormal = vec3(0.0);

    // Construct local working space. Looking straight up/down makes the
    // up-cross degenerate, so fall back to +X like getTbnMatrix does.
    vec3 viewerDir = normalize(-viewPos);
    vec3 viewerRight = abs(viewerDir.y) > 1.0 - 1e-4
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), viewerDir));
    vec3 viewerUp = cross(viewerDir, viewerRight);
    mat3 localToView = mat3(viewerRight, viewerUp, viewerDir);

    // Reduce AO radius very close up, makes some screen-space artifacts less
    // obvious
    float aoRadius = max(
        0.25 + 0.75 * smoothstep(0.0, 81.0, lengthSquared(viewPos)),
        0.5
    );

    // Increase AO radius for LoD terrain (looks nice)
#ifdef LOD_MOD_ACTIVE
    if (isLod) {
        aoRadius *= 3.0;
    }
#endif

    for (int i = 0; i < gtaoSlices; ++i) {
        float sliceAngle = (i + dither.x) * (pi / float(gtaoSlices));

        vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0);
        vec3 viewSliceDir = localToView * sliceDir;

        vec3 orthoDir = sliceDir - dot(sliceDir, viewerDir) * viewerDir;
        vec3 axis = cross(sliceDir, viewerDir);
        vec3 projectedNormal = viewNormal - axis * dot(viewNormal, axis);

        float lenSq = dot(projectedNormal, projectedNormal);
        float norm = inversesqrt(lenSq);

        float sgnGamma = sign(dot(orthoDir, projectedNormal));
        float cosGamma = clamp01(dot(projectedNormal, viewerDir) * norm);
        float gamma = sgnGamma * fastAcos(cosGamma);

        vec2 maxHorizonAngles;
        maxHorizonAngles.x = computeMaximumHorizonAngle(
            -viewSliceDir,
            viewerDir,
            screenPos,
            viewPos,
            aoRadius,
            dither.y,
            isLod
        );
        maxHorizonAngles.y = computeMaximumHorizonAngle(
            viewSliceDir,
            viewerDir,
            screenPos,
            viewPos,
            aoRadius,
            dither.y,
            isLod
        );

        ambientSss += max0(maxHorizonAngles.y - halfPi) * rcpPi;

        maxHorizonAngles = gamma
            + clamp(vec2(-1.0, 1.0) * maxHorizonAngles - gamma,
                    -halfPi,
                    halfPi);
        ao += integrateArc(maxHorizonAngles, gamma, cosGamma) * lenSq
            * norm;

        float bentAngle = dot(maxHorizonAngles, vec2(0.5));
        bentNormal
            += viewerDir * cos(bentAngle) + orthoDir * sin(bentAngle);
    }


    // approximation (Jimenez et al., "Practical Realtime Strategies for


    float albedo = mix(
        0.0,
        clamp(surfaceAlbedo, 0.02, 0.9),
        gtaoMultibounceIntensity
    );

    ao *= rcp(float(gtaoSlices));
    ambientSss *= rcp(float(gtaoSlices));
    ao /= albedo * ao + (1.0 - albedo);

    bentNormal = normalize(normalize(bentNormal) - 0.5 * viewerDir);

    return clamp01(vec2(ao, ambientSss));
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_GTAO
#endif

const float aoRenderScale = 0.5;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 viewTexel
        = ivec2(gl_FragCoord.xy * (taauViewportScale / aoRenderScale));

    if (clamp(viewTexel, ivec2(0), ivec2(viewRes)) != viewTexel) {
        return;
    }

    float depth = texelFetch(combinedDepthTex, viewTexel, 0).x;

#ifndef normalMapping
    vec4 gbufferData = texelFetch(colortex1, viewTexel, 0);
    vec4 gbufferData0 = gbufferData;
#else
    vec4 gbufferData = texelFetch(colortex2, viewTexel, 0);
    vec4 gbufferData0 = texelFetch(colortex1, viewTexel, 0);
#endif
    vec2 dither = vec2(
        texelFetch(noisetex, texel & 511, 0).b,
        texelFetch(noisetex, (texel + 249) & 511, 0).b
    );

    // Distant Horizons support

#ifdef LOD_MOD_ACTIVE
    float depthMc = texelFetch(depthtex1, viewTexel, 0).x;
    float depthLod = texelFetch(lodDepthTexShading, viewTexel, 0).x;
    bool isLod = isLodTerrain(depthMc, depthLod);
#else
#define depthMc depth
    const bool isLod = false;
#endif

    bool isHand;
    fixHandDepth(depthMc, isHand);

    vec3 screenPos = vec3(uv, depth);
    vec3 viewPos = screenToViewSpace(
        combinedProjectionMatrixInverse,
        screenPos,
        true
    );
    vec3 scenePos = viewToSceneSpace(viewPos);

    vec3 previousScreenPos
        = reprojectSceneSpace(scenePos, isHand, false);

    if (depth == 1.0) {
        ambient = vec4(1.0, 0.0, 0.0, 0.0);
        ambientHistoryData = vec2(0.0);
        return;
    }

#ifdef normalMapping
    vec3 worldNormal = decodeUnitVector(gbufferData.xy);

#ifdef LOD_MOD_ACTIVE
    if (isLod) {
        vec4 gbufferData0 = texelFetch(colortex1, viewTexel, 0);
        worldNormal = decodeUnitVector(unpackUnorm2x8(gbufferData0.z));
    }
#endif
#else
    vec3 worldNormal = decodeUnitVector(unpackUnorm2x8(gbufferData.z));
#endif

    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;

    dither = r2(frameCounter, dither);


    // approximation used by the merged GTAO implementation — cheap luminance

    vec3 surfaceAlbedoSrgb = vec3(
        unpackUnorm2x8(gbufferData0.x),
        unpackUnorm2x8(gbufferData0.y).x
    );
    float surfaceAlbedo
        = dot(srgbEotfInv(surfaceAlbedoSrgb), luminanceWeightsRec709);

    // Calculate AO

    vec2 ao;
    vec3 bentNormal;

#if shaderAo == shaderAoNone
    ao = vec2(1.0, 0.0);
    bentNormal = viewNormal;
#elif shaderAo == shaderAoSsao
    ao.x = computeDssao(screenPos, worldNormal, dither);
    ao.y = 0.0;
    bentNormal = viewNormal;
#elif shaderAo == shaderAoGtao
    ao = computeGtao(
        screenPos,
        viewPos,
        viewNormal,
        dither,
        isLod,
        surfaceAlbedo,
        bentNormal
    );
#endif

    // Temporal accumulation

    const float maxAccumFrames = 10.0;
    const float depthRejectionStrength = 16.0;
    const float offcenterRejectionStrength = 0.25;

    vec4 history = max0(
        catmullRomFilterFast(colortex6, previousScreenPos.xy, 0.65)
    );
    vec2 historyData = max0(texture(colortex14, previousScreenPos.xy).xy);

    if (clamp01(previousScreenPos.xy) == previousScreenPos.xy) {
        // Unpack history data
        float historyDepth = 1.0 - historyData.x;
        float pixelAge = min(historyData.y, maxAccumFrames);

        vec3 historyBentNormal;
        historyBentNormal.xy = history.zw * 2.0 - 1.0;
        historyBentNormal.z = sqrt(
            clamp01(1.0 - dot(historyBentNormal.xy, historyBentNormal.xy))
        );

        // Reproject bent normal
        historyBentNormal
            = historyBentNormal * mat3(gbufferPreviousModelView);
        historyBentNormal = mat3(gbufferModelView) * historyBentNormal;

        // Depth rejection
        float viewNorm = rcpLength(viewPos);
        float NoV = abs(dot(viewNormal, viewPos))
            * viewNorm; // NoV / sqrt(length(viewPos))
        float z0 = screenToViewSpaceDepth(
            combinedProjectionMatrixInverse,
            depth
        );
        float z1 = screenToViewSpaceDepth(
            combinedProjectionMatrixInverse,
            historyDepth
        );
        float depthWeight
            = exp2(-abs(z0 - z1) * depthRejectionStrength * NoV * viewNorm);

        // Offcenter rejection from Jessie, which is originally by Zombye
        // Reduces blur in motion
        vec2 pixelOffset = 1.0
            - abs(2.0
                      * fract(
                          viewRes * aoRenderScale * previousScreenPos.xy
                      )
                  - 1.0);
        float offcenterRejection = sqrt(pixelOffset.x * pixelOffset.y)
                * offcenterRejectionStrength
            + (1.0 - offcenterRejectionStrength);

        pixelAge
            *= depthWeight * offcenterRejection * float(historyDepth != 1.0);

        // Blend with history
        float historyWeight = pixelAge / (pixelAge + 1.0);

        ao = mix(ao, history.xy, historyWeight);
        bentNormal = slerp(bentNormal, historyBentNormal, historyWeight);

        ambient = vec4(ao, bentNormal.xy * 0.5 + 0.5);
        ambientHistoryData = vec2(1.0 - depth, pixelAge + 1.0);
    } else {
        ambient = vec4(ao, bentNormal.xy * 0.5 + 0.5);
        ambientHistoryData = vec2(0.0);
    }

    if (isHand) {
        ambientHistoryData.x = 1.0;
    }
}
