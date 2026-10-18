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

#ifdef fogSmoothing
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"

float luminance(vec3 c) {
    return dot(c, luminanceWeights);
}

vec3 fogSpatialFilter(
    sampler2D scatteringTex,
    vec2 uv,
    vec2 pixelSize,
    int radius
) {
    vec3 center = texture(scatteringTex, uv).rgb;
    vec3 sum = center;
    float wSum = 1.0;

    // Standard three-sigma rule: sigma sized so the kernel's edge taps carry
    // negligible weight (~1%) rather than being cut off abruptly by the box
    float sigma = max(float(radius), 1.0) / 3.0;
    float invTwoSigmaSq = 0.5 / (sigma * sigma);

    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x == 0 && y == 0) continue;

            vec2 offset = vec2(float(x), float(y));
            vec2 sampleUv = uv + offset * pixelSize;
            if (clamp01(sampleUv) != sampleUv) continue;

            vec3 sampleValue = texture(scatteringTex, sampleUv).rgb;
            float delta = abs(luminance(sampleValue) - luminance(center));

            float spatialWeight = exp(-dot(offset, offset) * invTwoSigmaSq);
            float rangeWeight = exp(-delta * 8.0);
            float weight = spatialWeight * rangeWeight;

            sum += sampleValue * weight;
            wSum += weight;
        }
    }

    return sum / max(wSum, eps);
}
#endif

layout(location = 0) out vec3 fragmentColor;

/* RENDERTARGETS: 0 */

#ifdef bloomyFog
layout(location = 1) out float bloomyFogBlend;

/* RENDERTARGETS: 0,3 */
#endif

in vec2 uv;

flat in vec3 ambientColor;
flat in vec3 lightColor;

#ifdef WORLD_OVERWORLD
#include "/lib/atmos/fog/overworld/params.glsl"
flat in OverworldFogParams fogParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0; // scene color
uniform sampler2D colortex3; // refraction data
uniform sampler2D colortex4; // sky map
uniform sampler2D colortex5; // scene history (used by SSR reflection reprojection)
uniform sampler2D colortex6; // volumetric fog scattering
uniform sampler2D colortex7; // volumetric fog transmittance
uniform sampler2D colortex11; // clouds history
uniform sampler2D colortex12; // clouds data
uniform sampler2D colortex13; // rendered translucent layer

#ifdef DISTANT_HORIZONS
// colortex1 gbuffer fetch for the DH water path below.
uniform sampler2D colortex1;
#endif

#ifdef VOXY
uniform sampler2D colortex16; // distant water gbuffer 0
#endif

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform float frameTimeCounter;
uniform float sunAngle;
uniform float rainStrength;
uniform float desertSandstormWeather;
uniform float wetness;

uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;

uniform int isEyeInWater;
uniform float eyeAltitude;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float eyeSkylight;

uniform float biomeCave;
uniform float biomeMayRain;
uniform float biomeMaySnow;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

// ------------
//   Includes
// ------------

#define SSRT_LOD
#define TEMPORAL_REPROJECTION

#include "/lib/atmos/fog/simpleFog.glsl"
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/sky/clouds/core/constants.glsl"
#include "/lib/util/bicubic.glsl"

const ivec2 cloudShadowRes = ivec2(512);

const float cloudShadowExtent = 256.0 / (cloudsScale / 10.0);

vec2 shadowViewToCloudShadowSpace(vec3 shadowViewPos) {
    vec2 cloudShadowPos = shadowViewPos.xy / cloudShadowExtent;
    cloudShadowPos /= 1.0 + length(cloudShadowPos);
    cloudShadowPos = cloudShadowPos * 0.5 + 0.5;

    return cloudShadowPos;
}

vec2 projectCloudShadowMap(vec3 scenePos) {
    return shadowViewToCloudShadowSpace(
        transform(shadowModelView, scenePos)
    );
}

vec3 unprojectCloudShadowMap(vec2 cloudShadowPos) {
    cloudShadowPos = cloudShadowPos * 2.0 - 1.0;
    cloudShadowPos /= 1.0 - length(cloudShadowPos);

    vec3 shadowViewPos = vec3(cloudShadowPos * cloudShadowExtent, 1.0);

    return transform(shadowModelViewInverse, shadowViewPos);
}

float getCloudShadows(sampler2D cloudShadowMap, vec3 scenePos) {
#ifndef cloudShadows
    return 1.0;
#else
    vec2 cloudShadowPos = projectCloudShadowMap(scenePos)
        * vec2(cloudShadowRes) / vec2(textureSize(cloudShadowMap, 0));

    if (clamp01(cloudShadowPos) != cloudShadowPos) {
        return 1.0;
    }

    // fade out cloud shadows when:
    //  - the fragment is above the cloud layer
    //  - the sun is near the horizon
    float r = planetRadius
        + (scenePos.y + eyeAltitude - 63.0) * cloudsScale;
    float altitudeFraction
        = linearStep(cloudsCumulusRadius, cloudsCumulusTopRadius, r);
    float cloudShadowFade = smoothstep(0.05, 0.15, lightDir.y)
        * clamp01(1.0 - altitudeFraction);

    float cloudShadow = bicubicFilter(cloudShadowMap, cloudShadowPos).x;
    cloudShadow = cloudShadow * cloudShadowFade + (1.0 - cloudShadowFade);

    return cloudShadow * cloudShadowsIntensity
        + (1.0 - cloudShadowsIntensity);
#endif
}

#if defined PROGRAM_PREPARE && defined cloudShadows
#include "/lib/atmos/sky/clouds/altocumulus.glsl"
#include "/lib/atmos/sky/clouds/cirrus.glsl"
#include "/lib/atmos/sky/clouds/cumulus.glsl"
#include "/lib/atmos/sky/clouds/cumulusCongestus.glsl"

vec2 renderCloudShadowMap(vec2 uv) {
    // Transform position from scene-space to clouds-space
    vec3 rayOrigin = unprojectCloudShadowMap(uv);
    rayOrigin = vec3(rayOrigin.xz, rayOrigin.y + eyeAltitude - 63.0).xzy
            * cloudsScale
        + vec3(0.0, planetRadius, 0.0);

    vec3 pos;
    float t, density, extinctionCoeff;
    float shadowVis = 1.0;
    float shadowCumulusOnly = 1.0;
    float distanceFade;
    float distanceFadeStrength = 0.00000001 * pulse(lightDir.y, -0.01, 0.2);

#ifdef cloudsCumulus
    extinctionCoeff = 0.25 * cloudsParams.l0ExtinctionCoeff;
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsCumulusRadius + 0.25 * cumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * cumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
    shadowCumulusOnly = shadowVis;
#endif

#ifdef cloudsAltocumulus
    extinctionCoeff = mix(0.05, 0.1, dayFactor) * cloudsAltocumulusDensity
        * (1.0 - 0.33 * rainStrength);
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsAltocumulusRadius + 0.5 * altocumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = altocumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * altocumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
#endif

#ifdef cloudsCirrus
    t = intersectSphere(rayOrigin, lightDir, cloudsCirrusRadius).y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cirrusDensityProfile(pos.xz, 0.5);
    shadowVis *= exp(-1.00 * distanceFade * cloudsCirrusExtinctionCoeff
                  * cirrusLayerThickness * rcp(abs(lightDir.y) + eps)
                  * density)
            * 0.5
        + 0.5;
#endif

    return vec2(shadowVis, shadowCumulusOnly);
}
#endif
#endif // INCLUDE_LIGHTING_CLOUD_SHADOWS
#endif

#if defined(LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS)
// Directional lightmap modulation.
#if !defined INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS

// Based on Ninjamike's implementation in shaderLABS #snippets

vec2 getDirectionalLightmaps(vec3 positionScene, vec3 normal) {
    vec2 lightmapMul = vec2(1.0);

    vec2 lightmapGradient;
    vec3 lightmapDir;
    mat2x3 posGradient = mat2x3(dFdx(positionScene), dFdy(positionScene));

    // Blocklight

    lightmapGradient = vec2(dFdx(lightLevels.x), dFdy(lightLevels.x));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.x = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.x, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.x = mix(
            1.0,
            lightmapMul.x,
            sqr(linearStep(0.03, 0.30, lightLevels.x))
        );
    }

    // Skylight

    lightmapGradient = vec2(dFdx(lightLevels.y), dFdy(lightLevels.y));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.y = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.y, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.y = mix(
            1.0,
            lightmapMul.y,
            sqr(linearStep(0.03, 0.30, lightLevels.y))
        );
    }

    return lightmapMul;
}

#endif // INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#endif

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHT)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHT_HANDHELD_LIGHT
#define INCLUDE_LIGHT_HANDHELD_LIGHT

#define HANDHELD_LIGHT_COLORS
#if handheldLightMode == handheldLightColored
const vec3 handheldEmitterLightColor[48] = vec3[48](
    vec3(1.00, 1.00, 1.00) * 12.0, // Strong white light
    vec3(1.00, 1.00, 1.00) * 6.0, // Medium white light
    vec3(1.00, 1.00, 1.00) * 1.0, // Weak white light
    vec3(1.00, 0.55, 0.27) * 14.0, // Strong golden light
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.57, 0.30) * 6.0, // Weak golden light
    vec3(1.00, 0.18, 0.10) * 5.0, // Redstone components
    vec3(1.00, 0.38, 0.10) * 7.0, // Lava
    vec3(1.00, 0.45, 0.10) * 9.0, // Medium orange light
    vec3(1.00, 0.63, 0.15) * 4.0, // Brewing stand
    vec3(1.00, 0.57, 0.30) * 12.0, // Medium golden light
    vec3(0.45, 0.73, 1.00) * 6.0, // Soul lights
    vec3(0.45, 0.73, 1.00) * 14.0, // Beacon
    vec3(0.75, 1.00, 0.83) * 3.0, // Sculk
    vec3(0.75, 1.00, 0.83) * 1.0, // End portal frame
    vec3(0.60, 0.10, 1.00) * 2.5, // Pink glow
    vec3(0.75, 1.00, 0.50) * 1.0, // Sea pickle
    vec3(1.00, 0.50, 0.25) * 4.0, // Nether plants
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.65, 0.30) * 8.0, // Ochre froglight
    vec3(0.86, 1.00, 0.44) * 8.0, // Verdant froglight
    vec3(0.75, 0.44, 1.00) * 8.0, // Pearlescent froglight
    vec3(0.60, 0.10, 1.00) * 2.0, // Enchanting table
    vec3(0.75, 0.44, 1.00) * 4.0, // Amethyst cluster
    vec3(0.75, 0.44, 1.00) * 4.0, // Calibrated sculk sensor
    vec3(0.75, 1.00, 0.83) * 6.0, // Active sculk sensor
    vec3(1.00, 0.18, 0.10) * 3.3, // Redstone block
    vec3(1.00, 0.50, 0.25) * 3.0, // Open eyeblossom
    vec3(0.85, 1.3, 1.0) * 3.9, // Copper torch and lanterns
    vec3(1.00, 0.57, 0.30) * 8.0, // Copper Bulbs
    vec3(0.60, 0.10, 1.00) * 12.0, // Nether portal
    vec3(0.0), // End portal
    // Colors for modded light sources (block IDs 64-79)
    vec3(1.00, 1.00, 1.00) * 10.0, // 32 - White       (block 64)
    vec3(0.85, 0.85, 0.85) *  9.0, // 33 - Light Gray  (block 65)
    vec3(0.55, 0.55, 0.55) *  8.0, // 34 - Gray        (block 66)
    vec3(0.20, 0.20, 0.22) *  6.0, // 35 - Black       (block 67)
    vec3(0.55, 0.35, 0.20) *  8.0, // 36 - Brown       (block 68)
    vec3(1.00, 0.10, 0.10) * 10.0, // 37 - Red         (block 69)
    vec3(1.00, 0.45, 0.10) * 10.0, // 38 - Orange      (block 70)
    vec3(1.00, 0.95, 0.20) * 10.0, // 39 - Yellow      (block 71)
    vec3(0.55, 1.00, 0.20) * 10.0, // 40 - Lime        (block 72)
    vec3(0.15, 1.00, 0.20) * 10.0, // 41 - Green       (block 73)
    vec3(0.15, 0.95, 1.00) * 10.0, // 42 - Cyan        (block 74)
    vec3(0.45, 0.75, 1.00) * 10.0, // 43 - Light Blue  (block 75)
    vec3(0.15, 0.30, 1.00) * 10.0, // 44 - Blue        (block 76)
    vec3(0.55, 0.15, 1.00) * 10.0, // 45 - Purple      (block 77)
    vec3(1.00, 0.20, 0.90) * 10.0, // 46 - Magenta     (block 78)
    vec3(1.00, 0.55, 0.85) * 10.0  // 47 - Pink        (block 79)
);
#endif // handheldLightingMode == handheldLightingColored

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 getHandheldLightColor(int handItemId, int heldItemLightValue) {
#if handheldLightMode == handheldLightColored
    const int firstEmitterId = 10032;
    const int emitterCount = 48;
    int emitterIndex = handItemId - firstEmitterId;

    if (emitterIndex >= 0 && emitterIndex < emitterCount) {
        return handheldEmitterLightColor[emitterIndex];
    }
#endif

    return (blocklightColor * blocklightScale * rcp(15.0))
        * heldItemLightValue;
}

float getHandheldLightFalloff(vec3 scenePos, float ao) {
    float falloff = lift(rcp(dot(scenePos, scenePos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * 1.00;
}

vec3 getHandheldLight(vec3 scenePos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scenePos += relativeEyePosition;
#endif

    vec3 lightColor = max(
        getHandheldLightColor(heldItemId, heldBlockLightValue),
        getHandheldLightColor(heldItemId2, heldBlockLightValue2)
    );

    float falloff = getHandheldLightFalloff(scenePos, ao);

    return lightColor * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS

// Cloud shadow map for the analytic-fog gates below (p0 renders it
// unconditionally, so this is valid in every config, mods or not).
uniform sampler2D colortex8;
#if !defined INCLUDE_MISC_LIGHTNING_FLASH
#define INCLUDE_MISC_LIGHTNING_FLASH

#ifdef lightningFlash
uniform float lightningFlashIris;
#define LIGHTNING_FLASH_UNIFORM lightningFlashIris
#else
#define LIGHTNING_FLASH_UNIFORM 0.0
#endif

const float lightningFlashIntensity = 4.0;

#endif // INCLUDE_MISC_LIGHTNING_FLASH
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/sampling.glsl"
#include "/lib/util/spaceConversion.glsl"

// Inlined from /lib/misc/refraction.glsl (single consumer: applyRefraction
// below). Decodes the packed tangent-space refraction normal written by the
// translucent gbuffer pass.
vec2 refractionNormalFrom(vec4 refractionData) {
    return vec2(
        unsplit2x8(refractionData.xy) * 2.0 - 1.0,
        unsplit2x8(refractionData.zw) * 2.0 - 1.0
    );
}

float refractionAmount(float viewDistance, float layerDist, bool eyeUnderwater) {
    float thicknessScale = rcp(max(viewDistance, 1.0)) * min(layerDist, 8.0);
    float distanceFalloffRate = eyeUnderwater ? 1.0 : 0.1;
    float distanceFalloff = rcp(1.0 + pow(max(viewDistance, 0.0), 0.8) * distanceFalloffRate);
    return thicknessScale * distanceFalloff * (0.1 * refractionIntensity);
}

// Rejects the offset (falls back to the un-refracted uv) if the refracted
// sample would land in front of the translucent surface itself.
vec2 rejectIfInFront(vec2 refractedUv, vec2 uv, float frontDepth) {
    float depthRefracted = texture(depthtex1, refractedUv).x;
    return mix(refractedUv, uv, float(depthRefracted < frontDepth));
}

vec3 applyRefraction(
    vec2 uv,
    vec4 refractionData,
    bool isTranslucent,
    float viewDistance,
    float layerDist,
    float frontDepth,
    bool eyeUnderwater,
    out vec2 refractedUvOut
) {
    vec2 refractedUv = uv;
    refractedUvOut = uv;

#if refraction != refractionOff
    if (isTranslucent && refractionData != vec4(0.0)) {
        vec2 normalTangent = refractionNormalFrom(refractionData);
        float amount = refractionAmount(viewDistance, layerDist, eyeUnderwater);

        refractedUv = rejectIfInFront(uv + normalTangent * amount, uv, frontDepth);
        refractedUvOut = refractedUv;

        vec2 dispersion = clamp(normalTangent, -0.2, 0.2) * 5.0
            * (0.035 * dispersionIntensity);

        vec2 uvR = rejectIfInFront(uv + (normalTangent + dispersion) * amount, uv, frontDepth);
        vec2 uvB = rejectIfInFront(uv + (normalTangent - dispersion) * amount, uv, frontDepth);

        vec3 fragmentColor;
        fragmentColor.r = texture(colortex0, uvR * taauViewportScale).r;
        fragmentColor.g = texture(colortex0, refractedUv * taauViewportScale).g;
        fragmentColor.b = texture(colortex0, uvB * taauViewportScale).b;
        return fragmentColor;
    }
#endif

    return texture(colortex0, refractedUv * taauViewportScale).rgb;
}

#ifdef WORLD_OVERWORLD
#include "/lib/atmos/fog/overworld/analytic.glsl"
#include "/lib/atmos/sky/clouds/core/sampling.glsl"

#ifdef LOD_MOD_ACTIVE
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/sky/clouds/core/constants.glsl"
#include "/lib/util/bicubic.glsl"

const ivec2 cloudShadowRes = ivec2(512);

const float cloudShadowExtent = 256.0 / (cloudsScale / 10.0);

vec2 shadowViewToCloudShadowSpace(vec3 shadowViewPos) {
    vec2 cloudShadowPos = shadowViewPos.xy / cloudShadowExtent;
    cloudShadowPos /= 1.0 + length(cloudShadowPos);
    cloudShadowPos = cloudShadowPos * 0.5 + 0.5;

    return cloudShadowPos;
}

vec2 projectCloudShadowMap(vec3 scenePos) {
    return shadowViewToCloudShadowSpace(
        transform(shadowModelView, scenePos)
    );
}

vec3 unprojectCloudShadowMap(vec2 cloudShadowPos) {
    cloudShadowPos = cloudShadowPos * 2.0 - 1.0;
    cloudShadowPos /= 1.0 - length(cloudShadowPos);

    vec3 shadowViewPos = vec3(cloudShadowPos * cloudShadowExtent, 1.0);

    return transform(shadowModelViewInverse, shadowViewPos);
}

float getCloudShadows(sampler2D cloudShadowMap, vec3 scenePos) {
#ifndef cloudShadows
    return 1.0;
#else
    vec2 cloudShadowPos = projectCloudShadowMap(scenePos)
        * vec2(cloudShadowRes) / vec2(textureSize(cloudShadowMap, 0));

    if (clamp01(cloudShadowPos) != cloudShadowPos) {
        return 1.0;
    }

    // fade out cloud shadows when:
    //  - the fragment is above the cloud layer
    //  - the sun is near the horizon
    float r = planetRadius
        + (scenePos.y + eyeAltitude - 63.0) * cloudsScale;
    float altitudeFraction
        = linearStep(cloudsCumulusRadius, cloudsCumulusTopRadius, r);
    float cloudShadowFade = smoothstep(0.05, 0.15, lightDir.y)
        * clamp01(1.0 - altitudeFraction);

    float cloudShadow = bicubicFilter(cloudShadowMap, cloudShadowPos).x;
    cloudShadow = cloudShadow * cloudShadowFade + (1.0 - cloudShadowFade);

    return cloudShadow * cloudShadowsIntensity
        + (1.0 - cloudShadowsIntensity);
#endif
}

#if defined PROGRAM_PREPARE && defined cloudShadows
#include "/lib/atmos/sky/clouds/altocumulus.glsl"
#include "/lib/atmos/sky/clouds/cirrus.glsl"
#include "/lib/atmos/sky/clouds/cumulus.glsl"
#include "/lib/atmos/sky/clouds/cumulusCongestus.glsl"

vec2 renderCloudShadowMap(vec2 uv) {
    // Transform position from scene-space to clouds-space
    vec3 rayOrigin = unprojectCloudShadowMap(uv);
    rayOrigin = vec3(rayOrigin.xz, rayOrigin.y + eyeAltitude - 63.0).xzy
            * cloudsScale
        + vec3(0.0, planetRadius, 0.0);

    vec3 pos;
    float t, density, extinctionCoeff;
    float shadowVis = 1.0;
    float shadowCumulusOnly = 1.0;
    float distanceFade;
    float distanceFadeStrength = 0.00000001 * pulse(lightDir.y, -0.01, 0.2);

#ifdef cloudsCumulus
    extinctionCoeff = 0.25 * cloudsParams.l0ExtinctionCoeff;
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsCumulusRadius + 0.25 * cumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * cumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
    shadowCumulusOnly = shadowVis;
#endif

#ifdef cloudsAltocumulus
    extinctionCoeff = mix(0.05, 0.1, dayFactor) * cloudsAltocumulusDensity
        * (1.0 - 0.33 * rainStrength);
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsAltocumulusRadius + 0.5 * altocumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = altocumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * altocumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
#endif

#ifdef cloudsCirrus
    t = intersectSphere(rayOrigin, lightDir, cloudsCirrusRadius).y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cirrusDensityProfile(pos.xz, 0.5);
    shadowVis *= exp(-1.00 * distanceFade * cloudsCirrusExtinctionCoeff
                  * cirrusLayerThickness * rcp(abs(lightDir.y) + eps)
                  * density)
            * 0.5
        + 0.5;
#endif

    return vec2(shadowVis, shadowCumulusOnly);
}
#endif
#endif // INCLUDE_LIGHTING_CLOUD_SHADOWS
#endif

#if defined(LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS)
// Directional lightmap modulation.
#if !defined INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS

// Based on Ninjamike's implementation in shaderLABS #snippets

vec2 getDirectionalLightmaps(vec3 positionScene, vec3 normal) {
    vec2 lightmapMul = vec2(1.0);

    vec2 lightmapGradient;
    vec3 lightmapDir;
    mat2x3 posGradient = mat2x3(dFdx(positionScene), dFdy(positionScene));

    // Blocklight

    lightmapGradient = vec2(dFdx(lightLevels.x), dFdy(lightLevels.x));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.x = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.x, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.x = mix(
            1.0,
            lightmapMul.x,
            sqr(linearStep(0.03, 0.30, lightLevels.x))
        );
    }

    // Skylight

    lightmapGradient = vec2(dFdx(lightLevels.y), dFdy(lightLevels.y));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.y = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.y, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.y = mix(
            1.0,
            lightmapMul.y,
            sqr(linearStep(0.03, 0.30, lightLevels.y))
        );
    }

    return lightmapMul;
}

#endif // INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#endif

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHT)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHT_HANDHELD_LIGHT
#define INCLUDE_LIGHT_HANDHELD_LIGHT

#define HANDHELD_LIGHT_COLORS
#if handheldLightMode == handheldLightColored
const vec3 handheldEmitterLightColor[48] = vec3[48](
    vec3(1.00, 1.00, 1.00) * 12.0, // Strong white light
    vec3(1.00, 1.00, 1.00) * 6.0, // Medium white light
    vec3(1.00, 1.00, 1.00) * 1.0, // Weak white light
    vec3(1.00, 0.55, 0.27) * 14.0, // Strong golden light
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.57, 0.30) * 6.0, // Weak golden light
    vec3(1.00, 0.18, 0.10) * 5.0, // Redstone components
    vec3(1.00, 0.38, 0.10) * 7.0, // Lava
    vec3(1.00, 0.45, 0.10) * 9.0, // Medium orange light
    vec3(1.00, 0.63, 0.15) * 4.0, // Brewing stand
    vec3(1.00, 0.57, 0.30) * 12.0, // Medium golden light
    vec3(0.45, 0.73, 1.00) * 6.0, // Soul lights
    vec3(0.45, 0.73, 1.00) * 14.0, // Beacon
    vec3(0.75, 1.00, 0.83) * 3.0, // Sculk
    vec3(0.75, 1.00, 0.83) * 1.0, // End portal frame
    vec3(0.60, 0.10, 1.00) * 2.5, // Pink glow
    vec3(0.75, 1.00, 0.50) * 1.0, // Sea pickle
    vec3(1.00, 0.50, 0.25) * 4.0, // Nether plants
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.65, 0.30) * 8.0, // Ochre froglight
    vec3(0.86, 1.00, 0.44) * 8.0, // Verdant froglight
    vec3(0.75, 0.44, 1.00) * 8.0, // Pearlescent froglight
    vec3(0.60, 0.10, 1.00) * 2.0, // Enchanting table
    vec3(0.75, 0.44, 1.00) * 4.0, // Amethyst cluster
    vec3(0.75, 0.44, 1.00) * 4.0, // Calibrated sculk sensor
    vec3(0.75, 1.00, 0.83) * 6.0, // Active sculk sensor
    vec3(1.00, 0.18, 0.10) * 3.3, // Redstone block
    vec3(1.00, 0.50, 0.25) * 3.0, // Open eyeblossom
    vec3(0.85, 1.3, 1.0) * 3.9, // Copper torch and lanterns
    vec3(1.00, 0.57, 0.30) * 8.0, // Copper Bulbs
    vec3(0.60, 0.10, 1.00) * 12.0, // Nether portal
    vec3(0.0), // End portal
    // Colors for modded light sources (block IDs 64-79)
    vec3(1.00, 1.00, 1.00) * 10.0, // 32 - White       (block 64)
    vec3(0.85, 0.85, 0.85) *  9.0, // 33 - Light Gray  (block 65)
    vec3(0.55, 0.55, 0.55) *  8.0, // 34 - Gray        (block 66)
    vec3(0.20, 0.20, 0.22) *  6.0, // 35 - Black       (block 67)
    vec3(0.55, 0.35, 0.20) *  8.0, // 36 - Brown       (block 68)
    vec3(1.00, 0.10, 0.10) * 10.0, // 37 - Red         (block 69)
    vec3(1.00, 0.45, 0.10) * 10.0, // 38 - Orange      (block 70)
    vec3(1.00, 0.95, 0.20) * 10.0, // 39 - Yellow      (block 71)
    vec3(0.55, 1.00, 0.20) * 10.0, // 40 - Lime        (block 72)
    vec3(0.15, 1.00, 0.20) * 10.0, // 41 - Green       (block 73)
    vec3(0.15, 0.95, 1.00) * 10.0, // 42 - Cyan        (block 74)
    vec3(0.45, 0.75, 1.00) * 10.0, // 43 - Light Blue  (block 75)
    vec3(0.15, 0.30, 1.00) * 10.0, // 44 - Blue        (block 76)
    vec3(0.55, 0.15, 1.00) * 10.0, // 45 - Purple      (block 77)
    vec3(1.00, 0.20, 0.90) * 10.0, // 46 - Magenta     (block 78)
    vec3(1.00, 0.55, 0.85) * 10.0  // 47 - Pink        (block 79)
);
#endif // handheldLightingMode == handheldLightingColored

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 getHandheldLightColor(int handItemId, int heldItemLightValue) {
#if handheldLightMode == handheldLightColored
    const int firstEmitterId = 10032;
    const int emitterCount = 48;
    int emitterIndex = handItemId - firstEmitterId;

    if (emitterIndex >= 0 && emitterIndex < emitterCount) {
        return handheldEmitterLightColor[emitterIndex];
    }
#endif

    return (blocklightColor * blocklightScale * rcp(15.0))
        * heldItemLightValue;
}

float getHandheldLightFalloff(vec3 scenePos, float ao) {
    float falloff = lift(rcp(dot(scenePos, scenePos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * 1.00;
}

vec3 getHandheldLight(vec3 scenePos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scenePos += relativeEyePosition;
#endif

    vec3 lightColor = max(
        getHandheldLightColor(heldItemId, heldBlockLightValue),
        getHandheldLightColor(heldItemId2, heldBlockLightValue2)
    );

    float falloff = getHandheldLightFalloff(scenePos, ao);

    return lightColor * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS
#endif
#endif

#ifdef LOD_MOD_ACTIVE
#if !defined INCLUDE_MISC_DISTANT_WATER
#define INCLUDE_MISC_DISTANT_WATER

#include "/lib/brdf/specular.glsl"
#if !defined INCLUDE_POST_PURKINJE_SHIFT
#define INCLUDE_POST_PURKINJE_SHIFT

// Purkinje effect: mesopic shift toward rod (scotopic) peak sensitivity.
// https://en.wikipedia.org/wiki/Purkinje_effect
vec3 purkinjeShiftTransform(vec3 rgb, vec2 lightLevels) {
#if !(defined purkinjeShift && defined WORLD_OVERWORLD)
    return rgb;
#else
    float purkinjeIntensity = 0.05 * purkinjeShiftIntensity;
    purkinjeIntensity = purkinjeIntensity
        - purkinjeIntensity * smoothstep(-0.12, -0.06, sunDir.y)
            * lightLevels.y; // No purkinje shift in daylight
    purkinjeIntensity *= clamp01(
        1.0 - lightLevels.x
    ); // Reduce purkinje intensity in blocklight
    purkinjeIntensity *= clamp01(
        0.3 + 0.7 * cube(max(lightLevels.y, eyeSkylight))
    ); // Reduce purkinje intensity underground

    if (purkinjeIntensity < eps) {
        return rgb;
    }

    const vec3 purkinjeTint = vec3(
        purkinjeShiftR,
        purkinjeShiftG,
        purkinjeShiftB
    ) * rec709ToWorkingColor;
    const vec3 rodResponse
        = vec3(7.15e-5, 4.81e-1, 3.28e-1) * rec709ToWorkingColor;

    vec3 xyz = rgb * workingToXyzColor;

    vec3 scotopicLuminance
        = xyz * (1.33 * (1.0 + (xyz.y + xyz.z) / xyz.x) - 1.68);

    float purkinje = dot(rodResponse, scotopicLuminance * xyzToWorkingColor);

    rgb = mix(
        rgb,
        purkinje * purkinjeTint,
        exp2(-rcp(purkinjeIntensity) * purkinje)
    );

    return max0(rgb);
#endif
}

#endif // INCLUDE_POST_PURKINJE_SHIFT
#include "/lib/material/water.glsl"

vec4 drawDistantWater(
    vec3 positionScreen,
    vec3 positionView,
    vec3 positionWorld,
    vec3 directionWorld,
    vec3 flatNormal,
    vec3 tint,
    vec2 lightLevels,
    float viewDistance,
    float layerDistance
) {
    vec4 waterColor = vec4(0.0);

    // Use hardcoded TBN matrix pointing upwards that is the same for LoD water
    // and regular water
    const mat3 tbn
        = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0));

    // Common fog

    float fogVisibility = commonFog(viewDistance, false, positionWorld - cameraPosition).a;

    // Cloud shadows

#if defined WORLD_OVERWORLD && defined cloudShadows
    float cloudShadowMask
        = getCloudShadows(colortex8, positionWorld - cameraPosition);
#else
    const float cloudShadowMask = 1.0;
#endif

    // Water absorption approx (must match gbuffers_water)

#ifdef DISTANT_HORIZONS
    tint.rgb *= 1.45;
#endif

    vec3 biomeWaterTint = srgbEotfInv(tint.rgb) * rec709ToWorkingColor;
    vec3 absorptionCoeff = biomeWaterCoeff(biomeWaterTint);

    mat2x3 waterFog = waterFogSimple(
        lightColor * cloudShadowMask,
        ambientColor,
        absorptionCoeff,
        lightLevels,
        layerDistance,
        dot(lightDir, directionWorld),
        0.0
    );

    float brightnessControl = 1.0 - exp(-0.33 * layerDistance);
    brightnessControl
        = (1.0 - lightLevels.y) + brightnessControl * lightLevels.y;

    waterColor.rgb = waterFog[0] * (1.0 + 6.0 * sqr(waterFog[1]))
        * brightnessControl * fogVisibility;
    waterColor.a = 1.0 - waterFog[1].x;

    // Get water wave normal

    // Account for 1/8 height difference between water and terrain
    vec3 waterSurfacePos = positionWorld - vec3(0.0, rcp(8.0), 0.0);

    vec3 normal = flatNormal;

#ifdef waterWaves
    if (flatNormal.y > eps) {
        vec2 coord = -(waterSurfacePos * tbn).xy;
        normal = tbn
            * getWaterNormal(
                     waterSurfacePos,
                     flatNormal,
                     coord,
                     vec2(0.0),
                     lightLevels.y,
                     false
            );
    }
#endif

    // Specular highlight

#if (defined WORLD_OVERWORLD || defined WORLD_END)
    float NoL = dot(normal, lightDir);
    float NoV = clamp01(dot(normal, -directionWorld));
    float LoV = dot(lightDir, -directionWorld);
    float halfwayNorm = inversesqrt(2.0 * LoV + 2.0);
    float NoH = (NoL + NoV) * halfwayNorm;
    float LoH = LoV * halfwayNorm + halfwayNorm;

    waterColor.rgb
        += getSpecularHighlight(waterMaterial, NoL, NoV, NoH, LoV, LoH)
        * lightColor * cloudShadowMask * fogVisibility;
#endif

    // Specular reflections

#if defined environmentReflections || defined skyReflections
    mat3 newTbn = getTbnMatrix(normal);
    waterColor.rgb
        += getSpecularReflections(
               waterMaterial,
               newTbn,
               positionScreen,
               positionView,
               positionWorld,
               normal,
               flatNormal,
               directionWorld,
               directionWorld * newTbn,
               lightLevels.y,
               true
           )
        * fogVisibility;
#endif

    // Purkinje shift

    waterColor.rgb = purkinjeShiftTransform(waterColor.rgb, lightLevels);

    return waterColor;
}

#endif // INCLUDE_MISC_DISTANT_WATER
#endif
#include "/lib/atmos/projection.glsl"

vec3 blendLayersWithFog(
    vec3 backgroundColor,
    vec4 translucentColor,
    vec3 frontPositionWorld,
    vec3 backPositionWorld,
    bool isTranslucent,
    bool isSky,
    bool frontIsHand,
    bool backIsHand
) {
    if (backIsHand) {
        return backgroundColor * (1.0 - translucentColor.a)
            + translucentColor.rgb;
    }

    // Apply analytic fog behind translucents

#if defined WORLD_OVERWORLD
    if (isTranslucent) {
        // Directional sky ambient along the segment: horizon warmth vs
        // zenith blue instead of the flat average.
        vec3 backDir;
        float backLen;
        lengthNormalize(
            backPositionWorld - frontPositionWorld,
            backDir,
            backLen
        );
        vec3 fogAmbientBack = textureLod(
            colortex4, projectSky(backDir), 0.0
        ).rgb;
        mat2x3 analyticFog = airFogAnalytic(
            frontPositionWorld,
            backPositionWorld,
            isSky,
            eyeSkylight,
            1.0,
            fogAmbientBack
        );


        vec3 midScene = 0.5 * (frontPositionWorld + backPositionWorld)
            - cameraPosition;
        analyticFog[0] *= getCloudShadows(colortex8, midScene);

        backgroundColor = backgroundColor * analyticFog[1] + analyticFog[0];
    }
#endif

    return backgroundColor * (1.0 - translucentColor.a)
        + translucentColor.rgb;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Sample textures

    float frontDepth = texelFetch(depthtex0, texel, 0).x;
    float backDepth = texelFetch(depthtex1, texel, 0).x;

    vec4 refractionData = texelFetch(colortex3, texel, 0);
    vec4 translucentColor = texelFetch(colortex13, texel, 0);

#if defined vl
    vec3 fogTransmittance = smoothFilter(colortex6, uv).rgb;
    vec3 fogScattering = smoothFilter(colortex7, uv).rgb;
#ifdef fogSmoothing
    // Denoise the fog buffers themselves. Do not use scene/taa history as a
    // substitute for volumetric radiance.
    fogTransmittance = fogSpatialFilter(
        colortex6, uv, vec2(viewPixelSize.x, viewPixelSize.y),
        max(fogSmoothingRadius, 1)
    );
    fogScattering = fogSpatialFilter(
        colortex7, uv, vec2(viewPixelSize.x, viewPixelSize.y),
        max(fogSmoothingRadius, 1)
    );
#endif
#endif

    // LoD mod support

#ifdef LOD_MOD_ACTIVE
    float frontDepthLod = texelFetch(lodDepthTex, texel, 0).x;
    float backDepthLod = texelFetch(lodDepthTexSolid, texel, 0).x;

    bool frontIsLodTerrain = isLodTerrain(frontDepth, frontDepthLod);
    bool backIsLodTerrain = isLodTerrain(backDepth, backDepthLod);

    bool isTranslucentLod = frontDepthLod != backDepthLod;
#else
#define frontDepthLod frontDepth
#define backDepthLod backDepth
#define frontIsLodTerrain false
#define backIsLodTerrain false
#define isTranslucentLod false
#endif

    bool isTranslucent = frontDepth != backDepth;
    bool isSky = backDepth == 1.0 && backDepthLod == 1.0;

    // Space conversions

    bool frontIsHand;
    bool backIsHand;
    fixHandDepth(frontDepth, frontIsHand);
    fixHandDepth(backDepth, backIsHand);

    vec3 frontPositionScreen
        = vec3(uv, frontIsLodTerrain ? frontDepthLod : frontDepth);
    vec3 frontPositionView = screenToViewSpace(
        frontPositionScreen,
        true,
        frontIsLodTerrain
    );
    vec3 frontPositionScene = viewToSceneSpace(frontPositionView);
    vec3 frontPositionWorld = frontPositionScene + cameraPosition;

    vec3 backPositionScreen
        = vec3(uv, backIsLodTerrain ? backDepthLod : backDepth);
    vec3 backPositionView
        = screenToViewSpace(backPositionScreen, true, backIsLodTerrain);
    vec3 backPositionWorld
        = viewToSceneSpace(backPositionView) + cameraPosition;

    vec3 directionWorld;
    float viewDistance;
    lengthNormalize(
        frontPositionScene - gbufferModelViewInverse[3].xyz,
        directionWorld,
        viewDistance
    );

    // Refraction

    float layerDist = abs(viewDistance - length(backPositionView));
    vec2 refractedUv;

    fragmentColor = applyRefraction(
        uv,
        refractionData,
        isTranslucent,
        viewDistance,
        layerDist,
        frontDepth,
        isEyeInWater == 1,
        refractedUv
    );


    vec3 originalColor = fragmentColor;

    // Draw LoD water

#if defined LOD_MOD_ACTIVE
    if (frontDepthLod != backDepthLod) {
        // if there is a layer of LoD water behind the translucent layer, these
        // will store the position of that layer
        vec3 lodPositionScreen = frontPositionScreen;
        vec3 lodPositionView = frontPositionView;
        vec3 lodPositionWorld = frontPositionWorld;

        // detect whether translucent LoD terrain may be behind the translucent
        // layer
        float zMc
            = screenToViewSpaceDepth(gbufferProjectionInverse, frontDepth);
        float zLod = screenToViewSpaceDepth(
            lodProjectionMatrixInverse,
            frontDepthLod
        );

        const float errorMargin = 1.0;
        bool lodBehindTranslucent
            = zLod > zMc + errorMargin && backDepth == 1.0;

        if (frontIsLodTerrain || lodBehindTranslucent) {
            if (lodBehindTranslucent) {
                lodPositionScreen = vec3(uv, frontDepthLod);
                lodPositionView = screenToViewSpace(
                    lodProjectionMatrixInverse,
                    lodPositionScreen,
                    true
                );
                lodPositionWorld
                    = viewToSceneSpace(lodPositionView) + cameraPosition;
            }

            // Unpack gbuffer data

#ifdef VOXY
            vec4 gbufferData = texelFetch(colortex16, texel, 0);
            bool isWater = minOf(gbufferData) > eps;
#else
            vec4 gbufferData = texelFetch(colortex1, texel, 0);
#endif

            mat4x2 data = mat4x2(
                unpackUnorm2x8(gbufferData.x),
                unpackUnorm2x8(gbufferData.y),
                unpackUnorm2x8(gbufferData.z),
                unpackUnorm2x8(gbufferData.w)
            );

            vec3 tint = vec3(data[0], data[1].x);
            vec3 flatNormal = decodeUnitVector(data[2]);
            vec2 lightLevels = data[3];

#ifdef DISTANT_HORIZONS
            uint materialMask = uint(255.0 * data[1].y);
            bool isWater = materialMask == MATERIAL_WATER;
#else
            float waterAlpha = data[1].y;
#endif

            if (isWater) { // Water
                vec4 waterColor = drawDistantWater(
                    lodPositionScreen,
                    lodPositionView,
                    lodPositionWorld,
                    directionWorld,
                    flatNormal,
                    tint,
                    lightLevels,
                    lengthKnowingDirection(
                        cameraPosition - lodPositionWorld,
                        directionWorld
                    ),
                    lengthKnowingDirection(
                        lodPositionWorld - backPositionWorld,
                        directionWorld
                    )
                );

#ifdef VOXY
                // Account for darkening by alpha of water surface
                // waterColor *= 8.0;
#endif

                fragmentColor
                    = fragmentColor * (1.0 - waterColor.a) + waterColor.rgb;
            }

            backPositionWorld = lodBehindTranslucent
                ? lodPositionWorld
                : backPositionWorld;
        }
    }
#endif

    // Blend layers

    fragmentColor = blendLayersWithFog(
        fragmentColor,
        translucentColor,
        frontPositionWorld,
        backPositionWorld,
        isTranslucent,
        isSky,
        frontIsHand,
        backIsHand
    );

    // Border fog

#ifdef borderFog
    fragmentColor = mix(
        originalColor,
        fragmentColor,
        borderFogFactor(frontPositionScene, directionWorld)
    );
#endif

    // Blend clouds in front of translucents

#if defined WORLD_OVERWORLD
    float cloudsApparentDistance;
    vec4 cloudsAndAurora
        = readCloudsAndAurora(refractedUv, cloudsApparentDistance);

    if (isTranslucent || isTranslucentLod) {
        if (cloudsApparentDistance < viewDistance) {
            fragmentColor
                = fragmentColor * cloudsAndAurora.w + cloudsAndAurora.xyz;
        }
    }
#endif

    // Blend fog

#if defined vl
    // Volumetric fog

    fragmentColor = fragmentColor * fogTransmittance + fogScattering;

#ifdef bloomyFog
    bloomyFogBlend
        = clamp01(dot(fogTransmittance, vec3(luminanceWeights)));
    bloomyFogBlend = isEyeInWater == 1 ? sqrt(bloomyFogBlend) : bloomyFogBlend;
#endif
#endif

#if !defined vl
    // Analytic fog

    if (isEyeInWater == 1) {
        // Underwater fog
        float LoV = dot(directionWorld, lightDir);

        mat2x3 analyticFog = waterFogSimple(
            lightColor,
            ambientColor,
            waterAbsorptionCoeff,
            vec2(0.0, eyeSkylight),
            viewDistance,
            LoV,
            15.0 * eyeSkylight
        );

        fragmentColor *= analyticFog[1];
        fragmentColor += analyticFog[0];

#ifdef bloomyFog
        bloomyFogBlend = sqrt(clamp01(dot(analyticFog[1], vec3(0.33))));
#endif
    } else {
#if defined WORLD_OVERWORLD
        // Overworld fog. Directional sky ambient along the view ray
        // instead of the flat average.
        vec3 fogAmbientFront = textureLod(
            colortex4, projectSky(directionWorld), 0.0
        ).rgb;
        mat2x3 analyticFog = airFogAnalytic(
            cameraPosition,
            frontPositionWorld,
            isSky,
            eyeSkylight,
            1.0,
            fogAmbientFront
        );

        // Same cloud gate as above, at this segment's midpoint.
        vec3 midSceneMain
            = 0.5 * (frontPositionWorld - cameraPosition);
        analyticFog[0] *= getCloudShadows(colortex8, midSceneMain);

        fragmentColor *= analyticFog[1];
        fragmentColor += analyticFog[0];

#ifdef bloomyFog
        // NOTE: fogTransmittance only exists under vl above; use the
        // analytic transmittance computed just above in this branch.
        bloomyFogBlend
            = clamp01(dot(analyticFog[1], vec3(luminanceWeights)));
        bloomyFogBlend = isEyeInWater == 1 ? sqrt(bloomyFogBlend) : bloomyFogBlend;
#endif
#else
#ifdef bloomyFog
        bloomyFogBlend = 1.0;
#endif
#endif
    }
#endif

#ifdef bloomyFog
#if defined WORLD_NETHER
    bloomyFogBlend
        = sphericalFog(
              viewDistance,
              0.0,
              0.0025 * netherFogDensity(frontPositionWorld)
          ) * 0.33
        + 0.67;
#elif defined WORLD_END
    bloomyFogBlend = bloomyFogBlend * 0.5 + 0.5;
#endif
#endif
}
