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

#if !defined INCLUDE_LIGHT_DIRECT_LIGHT_PCSS
#define INCLUDE_LIGHT_DIRECT_LIGHT_PCSS

// Fade from close shadows (shadow maps) to distant shadows (lightmap or SSRT)
float getShadowDistanceFade(vec3 scenePos, vec3 shadowScreenPos) {
    float effectiveShadowDistance = min(shadowDistance, far);
    return linearStep(
        0.1,
        1.0,
        pow32(
            max(maxOf(abs(shadowScreenPos.xy * 2.0 - 1.0)),
                lengthSquared(scenePos) * rcp(sqr(effectiveShadowDistance)))
        )
    );
}

// Fake, lightmap-based shadows for outside of the shadow range or when shadows
// are disabled
float getLightmapShadows(float skylight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skylight);
}

// Prevents light leaking in caves by cancelling out sunlight in very low
// skylight
float getLightmapLightLeakPrevention(float skylight) {
    return smoothstep(0.0 / 15.0, 2.0 / 15.0, skylight);
}

#if defined shadow && (defined WORLD_OVERWORLD || defined WORLD_END)

#include "/lib/light/direct/distortion.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/random.glsl"

const ivec2[9] blurKernelOffsets3x3 = ivec2[9](
    ivec2(-1, -1),
    ivec2(0, -1),
    ivec2(1, -1),
    ivec2(-1, 0),
    ivec2(0, 0),
    ivec2(1, 0),
    ivec2(-1, 1),
    ivec2(0, 1),
    ivec2(1, 1)
);

const int shadowMapRes = int(float(shadowMapResolution) * MC_SHADOW_QUALITY);
const float shadowMapPixelSize = rcp(float(shadowMapRes));

vec2 blockerSearch(vec3 scenePos, float dither, bool hasSss) {
    int stepCount = hasSss ? sssSteps : shadowVpsQuality;

    vec3 shadowViewPos = transform(shadowModelView, scenePos);
    vec3 shadowClipPos = projectOrtho(shadowProjection, shadowViewPos);
    float refZ = shadowClipPos.z * (shadowDepthScale * 0.5) + 0.5;

    float radius = shadowBlockerSearchRadius * shadowProjection[0].x
        * (0.5 + 0.5 * linearStep(0.2, 0.4, lightDir.y));

    float depthSum = 0.0;
    float weightSum = 0.0;
    float depthSumSss = 0.0;

    for (int i = 0; i < stepCount; ++i) {
        vec2 offset = vogelDiscSample(i, stepCount, dither * tau) * radius;
        vec2 uv = shadowClipPos.xy + offset;
        uv /= getDistortionFactor(uv);
        uv = uv * 0.5 + 0.5;

        if (clamp01(uv) != uv) {
            continue; // out of shadow map: undefined texelFetch
        }

        float depth = texelFetch(shadowtex0, ivec2(uv * shadowMapRes), 0).x;
        float weight = step(depth, refZ);

        depthSum += weight * depth;
        weightSum += weight;
        depthSumSss += max0(refZ - depth);
    }

    float blockerDepth = weightSum == 0.0 ? 0.0 : depthSum / weightSum;
    // Ortho chain: dView = dClip / proj[2].z and dClip = 2 * dRef /
    // shadowDepthScale, hence the factor 2
    float sssDepth = -2.0 * shadowProjectionInverse[2].z * depthSumSss
        * rcp(shadowDepthScale * float(stepCount));

    return vec2(blockerDepth, sssDepth);
}

vec3 shadowBasic(vec3 shadowScreenPos) {
    float shadowVis = texture(shadowtex1, shadowScreenPos);

#ifdef shadowColor
    ivec2 texel = ivec2(shadowScreenPos.xy * shadowMapRes);

    float depth = texelFetch(shadowtex0, texel, 0).x;
    vec3 color = texelFetch(shadowcolor0, texel, 0).rgb * 4.0;
    float weight = step(depth, shadowScreenPos.z);

    vec3 averageColor = vec3(0.0);
    for (int i = 0; i < 9; ++i) {
        averageColor
            += texelFetch(shadowcolor0, texel + blurKernelOffsets3x3[i], 0)
                   .rgb;
    }
    // hide sunlight seams between colored shadow and opaque shadows
    weight *= step(eps, maxOf(averageColor));

    color = color * weight + (1.0 - weight);

    return shadowVis * color;
#else
    return vec3(shadowVis);
#endif
}

vec3 shadowPcfFilter(
    vec3 shadowScreenPos,
    vec3 shadowClipPos,
#ifdef shadowColor
    vec3 shadowScreenPosTranslucent,
    vec3 shadowClipPosTranslucent,
#endif
    float penumbraSize,
    float dither
) {
    // penumbraSize > maxFilterRadius: blur
    // penumbraSize < minFilterRadius: anti-alias (blur then sharpen)
    float distortionFactor = getDistortionFactor(shadowClipPos.xy);
    float minFilterRadius = 2.0 * shadowMapPixelSize * distortionFactor;

    float filterRadius = max(penumbraSize, minFilterRadius);
    float filterScale = sqr(filterRadius / minFilterRadius);

    int stepCount
        = int(shadowPcfStepsMin + shadowPcfStepsScale * filterScale);
    stepCount = min(stepCount, shadowPcfStepsMax);

    float shadowVis = 0.0;

    vec3 colorSum = vec3(0.0);
    float weightSum = 0.0;

    // perform first 4 iterations and filter shadow color
    for (int i = 0; i < 4; ++i) {
        vec2 offset
            = vogelDiscSample(i, stepCount, dither * tau) * filterRadius;

        vec2 uv = shadowClipPos.xy + offset;
        uv /= getDistortionFactor(uv);
        uv = uv * 0.5 + 0.5;

        shadowVis += texture(shadowtex1, vec3(uv, shadowScreenPos.z));

#ifdef shadowColor
        // sample shadow color
        uv = shadowClipPosTranslucent.xy + offset;
        uv /= getDistortionFactor(uv);
        uv = uv * 0.5 + 0.5;

        ivec2 texel = ivec2(clamp(uv, vec2(0.0), vec2(1.0)) * shadowMapRes);

        float depth = texelFetch(shadowtex0, texel, 0).x;

        vec3 color = texelFetch(shadowcolor0, texel, 0).rgb;
        color = mix(
            vec3(1.0),
            4.0 * color,
            step(depth, shadowScreenPosTranslucent.z)
        );

        float weight = 1.0;

        colorSum += color * weight;
        weightSum += weight;
#endif
    }

    vec3 color = weightSum > 0.0 ? colorSum * rcp(weightSum) : vec3(1.0);

    // exit early if outside shadow
    if (shadowVis > 4.0 - eps) {
        return color;
    } else if (shadowVis < eps) {
        return vec3(0.0);
    }

    // perform remaining iterations
    for (int i = 4; i < stepCount; ++i) {
        vec2 offset
            = vogelDiscSample(i, stepCount, dither * tau) * filterRadius;

        vec2 uv = shadowClipPos.xy + offset;
        uv /= getDistortionFactor(uv);
        uv = uv * 0.5 + 0.5;

        shadowVis += texture(shadowtex1, vec3(uv, shadowScreenPos.z));
    }

    float rcpSteps = rcp(float(stepCount));

    // sharpening for small penumbra sizes
    float sharpeningThresh
        = 0.4 * max0((minFilterRadius - penumbraSize) / minFilterRadius);
    shadowVis = linearStep(
        sharpeningThresh,
        1.0 - sharpeningThresh,
        shadowVis * rcpSteps
    );

    return shadowVis * color;
}

vec3 getFilteredShadows(
    vec3 scenePos,
    vec3 flatNormal,
    float skylight,
    float cloudShadowMask,
    float sssAmount,
    inout float distanceFade,
    inout float sssDepth
) {
    sssDepth = 0.0;

    float NoL = dot(flatNormal, lightDir);

    vec3 bias = getShadowBias(scenePos, flatNormal, NoL, skylight);

    // Light leaking prevention from Complementary Reimagined, used with
    // permission
    vec3 edgeFactor
        = 0.1 - 0.2 * fract(scenePos + cameraPosition + flatNormal * 0.01);
    edgeFactor -= edgeFactor * skylight;

#ifdef pixelatedShadows
    // Snap position to the nearest block texel
    const float pixelScale = float(pixelatedShadowsRes);
    scenePos = scenePos + cameraPosition;
    scenePos = floor(scenePos * pixelScale + 0.01) * rcp(pixelScale)
        + (0.5 / pixelScale);
    scenePos = scenePos - cameraPosition;
#endif

    vec3 shadowViewPos
        = transform(shadowModelView, scenePos + bias + edgeFactor);
    vec3 shadowClipPos = projectOrtho(shadowProjection, shadowViewPos);
    vec3 shadowScreenPos = distortShadowSpace(shadowClipPos) * 0.5 + 0.5;

    distanceFade = getShadowDistanceFade(scenePos, shadowScreenPos);

    if (distanceFade >= 1.0) {
        return vec3(1.0);
    }

    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);

#ifdef shadowVps
    // Test blockers from the same biased position as the receiver so the
    // reference depth matches the PCF comparison depth
    vec2 blockerSearchResult = blockerSearch(
        scenePos + bias + edgeFactor,
        dither,
        sssAmount > eps
    );

    sssDepth = blockerSearchResult.y;

    if (NoL < 1e-3) {
        return vec3(0.0); // now we can exit early for sss blocks
    }
    if (blockerSearchResult.x < eps) {
        return vec3(1.0); // blocker search empty handed => no occluders
    }

    float penumbraSize = 16.0 * shadowPenumbraScale
        * (shadowScreenPos.z - blockerSearchResult.x)
        / blockerSearchResult.x;
    penumbraSize
        *= 5.0 - 4.0 * cloudShadowMask; // Increase penumbra radius inside cloud
                                      // shadows, nice overcast look
    penumbraSize = min(penumbraSize, shadowBlockerSearchRadius);
    penumbraSize *= shadowProjection[0].x;
#else
    float penumbraSize
        = sqrt(0.5) * shadowMapPixelSize * shadowPenumbraScale;

    // Increase blur radius to approximate subsurface scattering
    penumbraSize *= 1.0 + 7.0 * sssAmount;
#endif

#ifdef shadowColor


    vec3 shadowViewPosTranslucent
        = transform(shadowModelView, scenePos + bias);
    vec3 shadowClipPosTranslucent
        = projectOrtho(shadowProjection, shadowViewPosTranslucent);
    vec3 shadowScreenPosTranslucent
        = distortShadowSpace(shadowClipPosTranslucent) * 0.5 + 0.5;
#endif

#ifdef shadowPcf
    vec3 shadowVis = shadowPcfFilter(
        shadowScreenPos,
        shadowClipPos,
#ifdef shadowColor
        shadowScreenPosTranslucent,
        shadowClipPosTranslucent,
#endif
        penumbraSize,
        dither
    );
#else
    vec3 shadowVis = shadowBasic(shadowScreenPos);
#endif

    return shadowVis;
}
#endif

#endif // INCLUDE_LIGHT_DIRECT_LIGHT_PCSS
