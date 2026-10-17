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

layout(location = 0) out vec4 indirect;      // colortex17
layout(location = 1) out vec4 filterData;  // colortex19

/* RENDERTARGETS: 17,19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex4; // sky map (skylight bounce sampling)
uniform sampler2D colortex6; // selected AO for SSPT contact-shadow finishing
uniform sampler2D colortex14; // AO history depth for depth-aware AO upscale

uniform sampler2D depthtex1; // geometry depth (non-DH path)

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

#if defined shadow && !defined WORLD_NETHER
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef shadowColor
uniform sampler2D shadowcolor0;
#endif

uniform vec3 sunDir;
uniform vec3 moonDir;
uniform float sunAngle;
uniform float timeSunrise;
uniform float timeSunset;
uniform float moonPhaseBrightness;
#endif

// Shadow matrices stay declared even where no shadow pass runs: the
// cloud-shadow helper chain references them, and unused uniforms are free.
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

#if defined WORLD_OVERWORLD && defined cloudShadows
uniform sampler2D colortex8; // cloud shadow map
#endif

// Declared for the atmosphere/cloud-shadow include chain
uniform float rainStrength;
uniform float desertSandstormWeather;
uniform vec3 lightDir;
uniform float eyeAltitude;
uniform int moonPhase;

// ------------
//   Includes
// ------------

#define TRACE_DEPTH combinedDepthTex
#define TRACE_PROJ combinedProjectionMatrix
#define TRACE_PROJ_INV combinedProjectionMatrixInverse

#include "/lib/misc/lodModSupport.glsl"
#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT


#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#define LUSTER_INCLUDE_HANDHELD_LIGHTING
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHTING_CLOUD_SHADOWS
#define INCLUDE_LIGHTING_CLOUD_SHADOWS

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
#if !defined INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS

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

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHTING)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#define HANDHELD_LIGHTING_COLORS
#if handheldLightingMode == handheldLightingColored
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
#if handheldLightingMode == handheldLightingColored
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

vec3 getHandheldLighting(vec3 scenePos, float ao) {
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

#undef LUSTER_INCLUDE_HANDHELD_LIGHTING
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHTING_CLOUD_SHADOWS
#define INCLUDE_LIGHTING_CLOUD_SHADOWS

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
#if !defined INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS

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

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHTING)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#define HANDHELD_LIGHTING_COLORS
#if handheldLightingMode == handheldLightingColored
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
#if handheldLightingMode == handheldLightingColored
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

vec3 getHandheldLighting(vec3 scenePos, float ao) {
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
#include "/lib/light/distortion.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/material/material.glsl"
#include "/lib/atmos/projection.glsl"


// Resolution bookkeeping


// ----------------------------------------------------------------------------
/* DITHER */
// ----------------------------------------------------------------------------
// (hash22 below is the only dither hash used.)

#define HASHSCALE3 vec3(0.1031, 0.1030, 0.0973)
vec2 hash22(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ----------------------------------------------------------------------------
/* COSINE HEMISPHERE SAMPLING */
// ----------------------------------------------------------------------------

vec3 genUnitVector(vec2 p) {
    p.x *= tau; p.y = p.y * 2.0 - 1.0;
    return vec3(cos(p.x) * sqrt(1.0 - p.y * p.y),
                sin(p.x) * sqrt(1.0 - p.y * p.y),
                p.y);
}

// Lambertian BRDF sampling without a tangent frame (Malley's method).

// http://www.amietia.com/lambertnotangent.html
vec3 cosineVector(vec3 vector, vec2 xy) {
    vec3 sampleLobe = vector + genUnitVector(xy);
    float lenSq = dot(sampleLobe, sampleLobe);
    return lenSq > 0.0 ? sampleLobe * inversesqrt(lenSq) : vector;
}

// ----------------------------------------------------------------------------
/* SCREENSPACE RAYTRACER */


vec3 rayHit(vec3 screenPos) {
    float depthSample = texelFetch(
        TRACE_DEPTH,
        ivec2(screenPos.xy * viewRes * taauViewportScale),
        0
    ).x;

    if (depthSample >= screenPos.z) return vec3(1.1); // no occlusion yet

    float hitViewDepth = screenToViewSpaceDepth(TRACE_PROJ_INV, depthSample);
    float rayViewDepth = screenToViewSpaceDepth(TRACE_PROJ_INV, screenPos.z);

    float dist = abs(hitViewDepth - rayViewDepth) / max(abs(rayViewDepth), 1e-6);

    return dist <= 0.1 ? vec3(screenPos.xy, depthSample) : vec3(1.1);
}

#ifdef ssptFullRangeRT
//  Works fully in screenspace. Potentially every pixel can be hit. Needs a
//  lot more iterations for results of similar quality.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint maxSteps = 16;

    float rayLength = ((position.z + direction.z * far * sqrt(3.0)) > -sqrt(3.0) * near)
                      ? (-sqrt(3.0) * near - position.z) / direction.z : far * sqrt(3.0);

    vec3 screenPosition = viewToScreenSpace(TRACE_PROJ, position, true);
    vec3 endPosition = position + direction * rayLength;
    vec3 endScreenPosition = viewToScreenSpace(TRACE_PROJ, endPosition, true);

    vec3 screenDirection = normalize(endScreenPosition - screenPosition);
        screenDirection.xy = normalize(screenDirection.xy);

    vec3 maxLength = (step(0.0, screenDirection) - screenPosition) / screenDirection;
    float stepMult = minOf(maxLength);
    vec3 screenVector = screenDirection * stepMult / float(maxSteps);

    vec3 screenPos = screenPosition
        + screenDirection * maxOf(viewPixelSize * pi);

    if (clamp01(screenPos.xy) == screenPos.xy) {
        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;
    }

        screenPos += screenVector * noise;

    for (uint i = 0; i < maxSteps; ++i) {
        if (clamp01(screenPos.xy) != screenPos.xy) break;

        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;

        screenPos += screenVector;
    }

    return vec3(1.1);
}
#else
//  Short range variant (default). Traces a bounded view-space
//  distance and rescales the step vector so the ray ends on-screen.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint maxSteps = 10;
    const float stepSize = tau / float(maxSteps);

    vec3 stepVector = direction * stepSize;

    vec3 endPosition = position + stepVector * float(maxSteps);
    vec3 endScreenPosition = viewToScreenSpace(TRACE_PROJ, endPosition, true);

    vec2 maxPosXy = max(abs(endScreenPosition.xy * 2.0 - 1.0), vec2(1.0));
    float stepMult = minOf(rcp(maxPosXy));
        stepVector *= stepMult;

    // closest texel iteration
    vec3 samplePos = position;

        samplePos += stepVector / 6.0;
    vec3 screenPos = viewToScreenSpace(TRACE_PROJ, samplePos, true);

    if (clamp01(screenPos.xy) == screenPos.xy) {
        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;
    }

        samplePos += stepVector * noise;

    for (uint i = 0; i < maxSteps; ++i) {
        vec3 screenPos = viewToScreenSpace(TRACE_PROJ, samplePos, true);
            samplePos += stepVector;
        if (clamp01(screenPos.xy) != screenPos.xy) break;

        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;
    }

    return vec3(1.1);
}
#endif

// ----------------------------------------------------------------------------
/* HIT SURFACE DATA — Luster-main gbuffer unpack (kept for the bounce path) */


struct HitData {
    vec3 albedo;
    vec3 sceneNormal;
    vec2 lightLevels;
    uint mask;
};

HitData unpackHit(vec4 gbufferData) {
    HitData hit;

    hit.albedo = vec3(
        unpackUnorm2x8(gbufferData.x),
        unpackUnorm2x8(gbufferData.y).x
    );
    hit.mask = uint(255.0 * unpackUnorm2x8(gbufferData.y).y);
    hit.sceneNormal = decodeUnitVector(unpackUnorm2x8(gbufferData.z));
    hit.lightLevels = unpackUnorm2x8(gbufferData.w);

    return hit;
}

// ----------------------------------------------------------------------------
/* HIT SURFACE EMISSION — material path */


vec3 hitEmission(vec4 hitData0, ivec2 hitTexel, vec3 hitViewPos) {
    vec3 hitAlbedo = vec3(
        unpackUnorm2x8(hitData0.x),
        unpackUnorm2x8(hitData0.y).x
    );
    uint hitMask = uint(255.0 * unpackUnorm2x8(hitData0.y).y);
    vec3 hitSceneNormal = decodeUnitVector(unpackUnorm2x8(hitData0.z));
    vec2 hitLightLevels = unpackUnorm2x8(hitData0.w);

    // world position for position-dependent hardcoded emission
    vec3 hitWorldPos = viewToSceneSpace(hitViewPos) + cameraPosition;

    Material hitMaterial = materialFrom(
        hitAlbedo,
        hitMask,
        hitWorldPos,
        hitSceneNormal,
        hitLightLevels
    );

    // Raw hardcoded source (populated by materialFrom() only when
    // hardcodedEmission is on; otherwise zero).
    vec3 hardcodedRaw = hitMaterial.emission;

#if ssptEmissionMode != 0
    // Raw resource-pack map source (same channel decoding as
    // decodeEmission()'s map path, pre-curve).
    vec4 hitSpecularMap = texelFetch(colortex2, hitTexel, 0);
    vec4 ssptMap = vec4(
        unpackUnorm2x8(hitSpecularMap.z),
        unpackUnorm2x8(hitSpecularMap.w)
    );
    vec3 mapRaw;
    #if textureFormat == textureFormatLab
    float hasEmissionMap = step(ssptMap.a, 254.5 / 255.0);
    float emissionValue = (ssptMap.a * 255.0 - 1.0) / 254.0;
    // Exclusive: unmapped texels emit nothing (no hardcoded fallback).
    mapRaw = hitMaterial.albedo * emissionValue * hasEmissionMap;
    #else
    float hasEmissionMap = step(0.5 / 255.0, ssptMap.b);
    // Exclusive: unmapped texels emit nothing (no hardcoded fallback).
    mapRaw = hitMaterial.albedo * ssptMap.b * hasEmissionMap;
    #endif
#endif

    // SSPT-only source selection. Direct lighting is untouched.
    #if ssptEmissionMode == 2
    vec3 emissionRaw = mapRaw;
    #elif ssptEmissionMode == 1
    // Brighter source wins (luminance comparison, whole vector kept so
    // hue is preserved instead of mixing channels).
    float hardcodedLuma = dot(max0(hardcodedRaw), luminanceWeights);
    float mapLuma = dot(max0(mapRaw), luminanceWeights);
    vec3 emissionRaw = mapLuma > hardcodedLuma ? mapRaw : hardcodedRaw;
    #else
    vec3 emissionRaw = hardcodedRaw;
    #endif

    // Same global shaping as the primary pass so bounced and directly
    // viewed emitters agree on response.
    hitMaterial.emission = pow(
        max(emissionRaw, vec3(0.0)),
        vec3(globalEmissionCurve)
    ) * globalEmissionIntensity;


    return hitMaterial.emission * hitMaterial.albedo
        * emissionScale * ssptIntensity;
}

// ----------------------------------------------------------------------------
/* HIT DIRECT LIGHT — sun/moon + handheld bounce */

//  Shadowed sun/moon light at the traced hit, tinted by the hit albedo (one


//  falloff/color of the primary pass. Skylight stays out (owned by the
//  traced sky / bent-cone ambient, never by the bounce itself).


#if defined shadow && !defined WORLD_NETHER
#define DIRECT_SUN_BOUNCE 1
#endif
#ifdef handheldLighting
#define DIRECT_HANDHELD_BOUNCE 1
#endif


#define DIRECT_SKY_BOUNCE 1

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE


#ifdef DIRECT_SUN_BOUNCE
vec3 sunRadiance() {
    float blueHour = linearStep(0.05, 1.0, exp(-190.0 * sqr(sunDir.y + 0.09604)));
    float exposure = 7.0 * sunI
                   * (1.0 + 0.5 * (timeSunset + timeSunrise) + 40.0 * blueHour);

    vec3 tint = mix(
        vec3(1.0),
        vec3(1.05, 0.84, 0.93) * 1.2,
        sqr(pulse(sunDir.y, 0.17, 0.40))
    );
    tint *= mix(vec3(1.0), vec3(0.95, 0.80, 1.0), blueHour);

    vec3 userTint = mix(
        fromDisplay(vec3(sunNr, sunNg, sunNb)),
        fromDisplay(vec3(sunMr, sunMg, sunMb)),
        timeSunrise
    );
    userTint = mix(userTint, fromDisplay(vec3(sunEr, sunEg, sunEb)), timeSunset);

    return exposure * tint * userTint;
}

// Moon radiance. Moon-phase albedo influence is intentionally not applied:
// the bounce uses the raw moon color.
vec3 moonRadiance() {
    float nightBoost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sunDir.y, 0.1)));
    float exposure = 0.66 * moonI * moonPhaseBrightness * nightBoost;
    return exposure * fromDisplay(vec3(moonR, moonG, moonB));
}
#endif // DIRECT_SUN_BOUNCE

vec3 hitDirectLight(HitData hit, vec3 hitViewPos) {
    vec3 hitScenePos = viewToSceneSpace(hitViewPos);
    vec3 sunMoonDirect = vec3(0.0);
    vec3 indirectDirect = vec3(0.0);

#ifdef DIRECT_SUN_BOUNCE


    vec3 lightDirWorld = sunAngle < 0.5 ? sunDir : moonDir;

    float NoL = dot(hit.sceneNormal, lightDirWorld);
    if (NoL > 0.0) {
        vec3 bias = getShadowBias(hitScenePos, hit.sceneNormal, NoL, hit.lightLevels.y);
        vec3 shadowViewPos = transform(shadowModelView, hitScenePos + bias);
        vec3 shadowClipPos = projectOrtho(shadowProjection, shadowViewPos);
        vec3 shadowCoords = distortShadowSpace(shadowClipPos) * 0.5 + 0.5;

        bool outsideShadowMap = any(lessThan(shadowCoords, vec3(0.0)))
                               || any(greaterThan(shadowCoords, vec3(1.0)));

        float visibility = outsideShadowMap ? 1.0 : texture(shadowtex1, shadowCoords);
        if (visibility > 0.0) {
            vec3 radiance = sunAngle < 0.5 ? sunRadiance() : moonRadiance();
            sunMoonDirect = radiance * (visibility * NoL);

#ifdef shadowColor
            if (!outsideShadowMap) {
                // Sunlight passing through stained glass picks up the glass tint.
                ivec2 shadowTexel = ivec2(shadowCoords.xy * vec2(textureSize(shadowtex0, 0)));
                float blockerDepth = texelFetch(shadowtex0, shadowTexel, 0).x;
                vec3 transmission = texelFetch(shadowcolor0, shadowTexel, 0).rgb;
                sunMoonDirect *= mix(vec3(1.0), 4.0 * transmission, step(blockerDepth, shadowCoords.z));
            }
#endif

#if defined WORLD_OVERWORLD && defined cloudShadows
            sunMoonDirect *= getCloudShadows(colortex8, hitScenePos);
#endif
        }
    }
#endif // DIRECT_SUN_BOUNCE

#ifdef DIRECT_SKY_BOUNCE


    vec3 skyRadiance = texture(colortex4, projectSky(hit.sceneNormal)).rgb;
    indirectDirect += skyRadiance * hit.lightLevels.y;
#endif // DIRECT_SKY_BOUNCE

#ifdef DIRECT_HANDHELD_BOUNCE


    indirectDirect += getHandheldLighting(hitScenePos, 1.0);
#endif


    return hit.albedo * (sunMoonDirect + indirectDirect * ssptIntensity);
}

#endif // defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE

// ----------------------------------------------------------------------------
/* HAMMON DIFFUSE BRDF (Kappa-style lib; includes fresnelSchlickInverse) */
// ----------------------------------------------------------------------------

#include "/lib/brdf/hammon.glsl"


// INDIRECT TRACER


//  and is tinted by the hit albedo inside hitDirectLight. Multibounce


vec3 traceIndirect(
    vec3 viewPos,
    vec3 sceneNormal,
    vec2 dither,
    bool hand,
    float contactAo,
    out bool geometryHit
) {
    vec3 viewNormal = mat3(gbufferModelView) * sceneNormal;

    vec3 emission = vec3(0.0);
    geometryHit = false;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    vec3 bounce = vec3(0.0);
    // Candidate count for bounce normalization: bounce averages over
    // candidates like emission does, not over hits.
    float bounceSamples = 0.0;
#endif

    // R2-sequence constants: 1/rho and 1/rho^2 (plastic constant)
    const float a1 = 1.0 / 1.3247179572447460;
    const float a2 = a1 * a1;

    #if ssptBounces <= 1

    /* ------ SINGLE BOUNCE ------ */
    //  Every candidate is a cosine-lobe ray, stratified over pixel +
    //  frame + candidate index so temporal accumulation blends them.

    vec2 quasirandomCurr = 0.5 + fract(vec2(a1, a2) * float(frameCounter) + 0.5);

    vec2 noiseCurr = hash22(gl_FragCoord.xy + float(frameCounter));

    for (uint i = 0; i < ssptSPP; ++i) {
        ++quasirandomCurr;
        noiseCurr += hash22(
            vec2(gl_FragCoord.xy + vec2(cos(quasirandomCurr.x), sin(quasirandomCurr.y)))
        );

        vec2 vectorXy = fract(sqrt(2.0) * quasirandomCurr + noiseCurr);


        bounceSamples += 1.0;

        vec3 rayDirection = cosineVector(sceneNormal, vectorXy);
            rayDirection = normalize(mat3(gbufferModelView) * rayDirection);

        if (dot(viewNormal, rayDirection) < 0.0) rayDirection = -rayDirection;

        float brdf = brdfWeight(viewNormal, -normalize(viewPos), rayDirection);

        vec3 hitPosition = screenspaceRT(viewPos, rayDirection, dither.y);

        if (hitPosition.z < 1.0) {
            geometryHit = true;
            ivec2 hitTexel = ivec2(hitPosition.xy * viewRes * taauViewportScale);
            vec4 hitData0 = texelFetch(colortex1, hitTexel, 0);

            vec3 hitViewPos = screenToViewSpace(TRACE_PROJ_INV, hitPosition, true);

            // Cubic emission distance falloff.
            float emissionFalloff = 1.0 - linearStep(
                ssptEmissionDistance * rcpPi,
                ssptEmissionDistance,
                distance(hitViewPos, viewPos)
            );
                emissionFalloff = cube(emissionFalloff);

            emission += hitEmission(hitData0, hitTexel, hitViewPos)
                      * emissionFalloff * brdf;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
            // Direct-light bounce: no distance falloff, BRDF-weighted.
            // (Counted per cosine candidate above, not per hit.)
            bounce += hitDirectLight(unpackHit(hitData0), hitViewPos) * brdf;
#endif
        }
    }

    #else

    /* ------ MULTIBOUNCE (ssptBounces > 1) ------ */


    //  Sky escapes end the chain.

    for (uint i = 0; i < ssptSPP; ++i) {
        int frameCounterNew = frameCounter + int(i) * 31;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
        // Multibounce samples are all cosine-lobe: count every sample so
        // the shared normalization below reproduces the old average.
        bounceSamples += 1.0;
#endif

        vec2 quasirandomCurr = 0.5 + fract(vec2(a1, a2) * float(frameCounterNew) + 0.5);

        vec2 noiseCurr = hash22(gl_FragCoord.xy + float(frameCounterNew));

        vec3 contribution = vec3(1.0);

        vec3 rayDirection = -normalize(viewPos);

        vec3 hitNormal = viewNormal;
        vec3 hitNormalScene = sceneNormal;

        for (uint n = 0; n < ssptBounces; ++n) {
            ++quasirandomCurr;
            noiseCurr += hash22(
                vec2(gl_FragCoord.xy + vec2(cos(quasirandomCurr.x), sin(quasirandomCurr.y)))
            );

            vec2 vectorXy = fract(sqrt(2.0) * quasirandomCurr + noiseCurr);

            vec3 oldDirection = rayDirection;

                rayDirection = cosineVector(hitNormalScene, vectorXy);
                rayDirection = normalize(mat3(gbufferModelView) * rayDirection);

            if (dot(hitNormal, rayDirection) < 0.0) rayDirection = -rayDirection;

            vec3 hitPosition = screenspaceRT(viewPos, rayDirection, dither.y);

            float brdf = brdfWeight(hitNormal, -oldDirection, rayDirection);
                contribution *= brdf;

            if (hitPosition.z < 1.0) {
                geometryHit = true;
                ivec2 hitTexel = ivec2(hitPosition.xy * viewRes * taauViewportScale);
                vec4 hitData0 = texelFetch(colortex1, hitTexel, 0);

                vec3 hitAlbedo = vec3(
                    unpackUnorm2x8(hitData0.x),
                    unpackUnorm2x8(hitData0.y).x
                );
                hitNormalScene = decodeUnitVector(unpackUnorm2x8(hitData0.z));
                hitNormal = mat3(gbufferModelView) * hitNormalScene;

                vec3 hitViewPos = screenToViewSpace(TRACE_PROJ_INV, hitPosition, true);

                float emissionFalloff = 1.0 - linearStep(
                    ssptEmissionDistance * rcpPi,
                    ssptEmissionDistance,
                    distance(hitViewPos, viewPos)
                );
                    emissionFalloff = cube(emissionFalloff);

                emission += hitEmission(hitData0, hitTexel, hitViewPos)
                          * emissionFalloff * contribution;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
                // Direct-light bounce on every path vertex.
                bounce += hitDirectLight(unpackHit(hitData0), hitViewPos)
                        * contribution;
#endif

                contribution *= hitAlbedo; // colored bleed into deeper bounces
            } else {
                // miss: sky escape contributes no emission; stop the chain
                break;
            }
        }
    }

    #endif

    emission /= float(ssptSPP);


    float emissionLuma = dot(max0(emission), luminanceWeights);
    emission *= rcp(1.0 + emissionLuma * rcp(8.0));
    float compressedLuma = dot(max0(emission), luminanceWeights);
    emission = mix(vec3(compressedLuma), emission, 1.4);

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    // Bounce averages over candidates, matching emission's normalization.
    if (bounceSamples > 0.5) bounce /= bounceSamples;
    // Finish traced bounced lighting with the selected screen-space AO.
    // Keep material emission unoccluded so emitters do not lose radiance.
    bounce *= clamp01(contactAo);
#endif

    emission *= float(!hand); // hand geometry gets no emission or sky
    // (hand keeps its direct-light bounce)


#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    return emission + bounce;
#else
    return emission;
#endif
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT
#include "/lib/util/encoding.glsl"
#include "/lib/util/spaceConversion.glsl"

// Depth-aware 2x2 upscale of the quarter-res AO buffer (colortex6.x with
// colortex14 depth weights, same 10.0 scale as the shading pass bilateral
// resolve). Works at any SSPT buffer resolution set by indirectResReduction
// and for both DSSAO (scalar) and DGTAO (scalar visibility; bent normal stays
// in the shading pass for directional sky). Bilinear texture() would bleed AO
// across depth discontinuities and leak/halo the bounce finishing.
float fetchSsptContactAo(vec2 uv, float linZ) {
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

// ------------
//   Main
// ------------

void main() {
    // This pass renders at the selected SSPT buffer resolution; gl_FragCoord is
    // in buffer texels while uv spans the whole screen.
    ivec2 gbufferTexel = ivec2(uv * viewRes * taauViewportScale);

    // initialize outputs before any early return (sky = vec4(0.0),
    // filter gbuffer = (0,0,1)*0.5+0.5 packed + depth 1)
    indirect = vec4(0.0);
    filterData = vec4(0.5, 0.5, 1.0, 1.0);

    if (clamp(gbufferTexel, ivec2(0), ivec2(viewRes) - 1) != gbufferTexel) {
        return;
    }

    float depth = texelFetch(combinedDepthTex, gbufferTexel, 0).x;

    if (depth >= 1.0) {
        return;
    }

    bool isHand = depth < handDepth;

    vec3 screenPos = vec3(uv, depth);
    vec3 viewPos = screenToViewSpace(
        combinedProjectionMatrixInverse,
        screenPos,
        true
    );

    // ---- gbuffer unpack (same packing as d4DeferredShading) ----

    vec4 gbufferData0 = texelFetch(colortex1, gbufferTexel, 0);

    vec3 flatNormal = decodeUnitVector(unpackUnorm2x8(gbufferData0.z));
    vec3 viewNormal = mat3(gbufferModelView) * flatNormal;

    // ---- filter gbuffer side-data ----


    filterData = vec4(
        viewNormal * 0.5 + 0.5,
        sqrt(clamp01(-viewPos.z / far))
    );

    // ---- trace ----
    // Hash dithers, consumed as the screenspace-RT march noise by traceIndirect.

    vec2 dither = vec2(
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b,
        texelFetch(noisetex, (ivec2(gl_FragCoord.xy) + 249) & 511, 0).b
    );

    // Emission + sun/moon + handheld bounce.


    // AO is already temporally stabilized by deferred3. Its selected scalar
    // visibility is applied to traced bounce lighting, not to emission.
    // DSSAO and DGTAO share this scalar finishing path; DGTAO's bent normal
    // additionally steers directional sky in the shading pass.
    float linZ = screenToViewSpaceDepth(
        combinedProjectionMatrixInverse,
        depth
    );
    float contactAo = isHand ? 1.0 : fetchSsptContactAo(uv, linZ);

    bool geometryHit;
    vec3 indirectLight = traceIndirect(
        viewPos,
        flatNormal,
        dither,
        isHand,
        contactAo,
        geometryHit
    );


    indirect = vec4(indirectLight, float(geometryHit));
}
