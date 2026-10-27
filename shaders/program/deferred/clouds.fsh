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

// Declared before the atmosphere/sandstorm include so desertSandstorm can use it.
uniform float desertSandstormWeather;

layout(location = 0) out vec4 clouds;
layout(location = 1) out vec2 cloudsData;

/* RENDERTARGETS: 9,10 */

in vec2 uv;

#if defined WORLD_OVERWORLD
flat in vec3 sunColor;
flat in vec3 moonColor;
flat in vec3 skyColor;

flat in float auroraAmount;
flat in mat2x3 auroraColors;

#include "/lib/atmos/clouds/util/params.glsl"
flat in CloudsParams cloudsParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D colortex6; // 3D bubbly worley noise
#define SAMPLER_WORLEY_BUBBLY colortex6
uniform sampler3D colortex7; // 3D swirley worley noise
#define SAMPLER_WORLEY_SWIRLEY colortex7
uniform sampler3D cumulusCurl;
#define SAMPLER_CUMULUS_CURL cumulusCurl

uniform sampler2D colortex8; // cloud shadow map

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D depthtex1;

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float wetness;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float worldAge;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float biomeCave;
uniform float biomeTemperate;
uniform float biomeArid;
uniform float biomeSnowy;
uniform float biomeTaiga;
uniform float biomeJungle;
uniform float biomeSwamp;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeTemperature;
uniform float biomeHumidity;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0

// Baked once per frame by deferred0 (sky map) into colortex21; every
// consumer of atmosphereTransmittance from this pass onward uses it.
#define ATMOSPHERE_TRANSMITTANCE_LUT colortex21
#define MIE_PHASE_CLAMP

#ifdef cloudsCumulusPrecomputeLocalCoverage
#define CLOUDS_USE_LOCAL_COVERAGE_MAP
#endif

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/atmos/aurora.glsl"
#include "/lib/atmos/clouds/util/pipeline.glsl"
// Checkerboard offset tables are used unconditionally by main; keep this
// outside the crepuscular-rays guard below.
#include "/lib/util/bicubic.glsl"

#if defined crepRays && !defined blockyClouds

#if !defined INCLUDE_ATMOS_SKY_CREPUSCULAR_RAYS
#define INCLUDE_ATMOS_SKY_CREPUSCULAR_RAYS

#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/clouds/util/constants.glsl"
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
#include "/lib/atmos/clouds/altocumulus.glsl"
#include "/lib/atmos/clouds/cirrus.glsl"
#include "/lib/atmos/clouds/cumulus.glsl"
#include "/lib/atmos/clouds/cumulusCongestus.glsl"

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
#endif // INCLUDE_LIGHT_CLOUD_SHADOWS
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

#endif // INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS
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
#endif // handheldLightMode == handheldLightColored

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

#endif // INCLUDE_LIGHT_HANDHELD_LIGHT
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS
#include "/lib/util/lodMod.glsl"
#include "/lib/atmos/clouds/util/common.glsl"

vec4 drawCrepuscularRays(
    sampler2D cloudShadowMap,
    vec3 rayDirectionWorld,
    bool isTerrain,
    float dither
) {
    const uint stepCountHorizon = crepRaysStepsHorizon;
    const uint stepCountZenith = crepRaysStepsZenith;
    const float maxRayLength = 4096.0 / (cloudsScale / 10.0);
    // Volume extends indefinitely into the planet (no ground cutoff —
    // the unclipped path was the only one in use anyway)
    const float volumeInnerRadius = 1.0;
    const float volumeOuterRadius
        = cloudsCumulusRadius + cumulusLayerThickness * 0.5;
    vec3 extinctionCoeff = crepRaysIntensity * dampen(cloudsParams.crepuscularRaysAmount)
        * (50.0 * airRayleighCoef + 400.0 * airMieCoef)
        * (cloudsScale / 10.0);

    const float undergroundLightFadeDistance = 100.0;

    uint stepCount = uint(
        mix(stepCountHorizon,
            stepCountZenith,
            dampen(abs(rayDirectionWorld.y)))
    );

    // Calculate ray start and ray end

    float r = planetRadius + eyeAltitude * cloudsScale;
    vec2 dists = intersectSphericalShell(
                     rayDirectionWorld.y,
                     r,
                     volumeInnerRadius,
                     volumeOuterRadius
                 )
        * rcp(cloudsScale);
    bool planetIntersected
        = intersectSphere(
              rayDirectionWorld.y,
              r,
              min(r - 10.0, planetRadius)
          )
              .y
        >= 0.0;

    if (
        dists.y < 0.0 // volume not intersected
                      //|| planetIntersected && r < cloudsCumulusRadius //
                      // planet blocking clouds
        || isTerrain // terrain blocking clouds
    ) {
        return vec4(vec3(0.0), 1.0);
    }

    float rayLength = clamp(dists.y - dists.x, 0.0, maxRayLength);
    float stepLength = rayLength * rcp(float(stepCount));

    // Transform to shadow view space

    vec3 rayDirectionShadow = mat3(shadowModelView) * rayDirectionWorld;
    vec3 rayOriginShadow
        = shadowModelView[3].xyz + rayDirectionShadow * dists.x;
    vec3 rayStepShadow = rayDirectionShadow * stepLength;

    vec3 rayOriginWorld
        = vec3(0.0, planetRadius, 0.0) + rayDirectionWorld * dists.x;
    vec3 rayStepPlanet = rayDirectionWorld * stepLength;

    // Raymarching loop

    vec3 scatteringCoeff = extinctionCoeff;
    vec3 stepOpticalDepth = extinctionCoeff * stepLength;
    vec3 stepTransmittance = exp(-stepOpticalDepth);

    vec3 scattering = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    for (uint i = 0u; i < stepCount; ++i) {
        vec3 rayPositionPlanet
            = rayOriginWorld + rayStepPlanet * (float(i) + dither);
        vec3 rayPositionShadow
            = rayOriginShadow + rayStepShadow * (float(i) + dither);

        float d = stepLength * (float(i) + dither);


        vec2 shadowUv
            = shadowViewToCloudShadowSpace(rayPositionShadow);
        vec2 shadowTexel = 1.5 / vec2(textureSize(cloudShadowMap, 0));
        float tapAngle = (dither + float(i) * 0.618034) * 6.2831853;
        vec2 tapX = vec2(cos(tapAngle), sin(tapAngle)) * shadowTexel;
        vec2 tapY = vec2(-tapX.y, tapX.x) * shadowTexel;
        vec2 shadowTaps = texture(cloudShadowMap, shadowUv + tapX).xy
            + texture(cloudShadowMap, shadowUv - tapX).xy
            + texture(cloudShadowMap, shadowUv + tapY).xy
            + texture(cloudShadowMap, shadowUv - tapY).xy;
        float cloudShadow = dot(shadowTaps, vec2(0.125));
        float a = linearStep(
            sqr(planetRadius - undergroundLightFadeDistance),
            sqr(planetRadius),
            lengthSquared(rayPositionPlanet)
        );
        float b = 1.0 - exp2(-0.002 * d);


        scattering += sqr(cloudShadow) * transmittance * a * b;
        transmittance *= stepTransmittance;
    }

    // Lighting

    vec3 lightColor
        = sunlightColor * atmosphereTransmittance(lightDir.y, planetRadius);
    lightColor = atmospherePostProcessing(lightColor);
    lightColor *= sunAngle > 0.5 ? moonColor : sunColor;

    float sunsetFactor = pulse(lightDir.y, -0.01, 0.1);
    vec3 stepTransmittedFraction
        = (1.0 - stepTransmittance) / max(stepOpticalDepth, eps);

    float LoV = dot(rayDirectionWorld, lightDir);

    float forwards = henyeyGreensteinPhase(LoV, 0.5);

    float phase = mix(0.5, 1.5, timeSunrise + timeSunset)
            * forwards // forwards lobe (max'ing them is completely nonsensical
                       // but it looks nice)
        + 0.5 * henyeyGreensteinPhase(LoV, -0.2); // backwards lobe

    scattering *= scatteringCoeff * stepTransmittedFraction * lightColor
        * stepLength * cloudsParams.crepuscularRaysAmount;
    scattering *= (6.0 * 1.00) * phase;
    transmittance
        = mix(vec3(1.0), transmittance, cloudsParams.crepuscularRaysAmount);

    // Return the volume transmittance so callers attenuate the background
    // behind the shafts instead of only adding light (energy gain)
    return vec4(scattering, clamp01(dot(transmittance, vec3(1.0 / 3.0))));
}

#endif // INCLUDE_ATMOS_SKY_CREPUSCULAR_RAYS
#endif
#endif

#include "/lib/util/lodMod.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

const int checkerboardArea
    = cloudsTemporalUpscaling * cloudsTemporalUpscaling;

float depthMax4x4(sampler2D depthSampler, float scale) {
    vec4 depthSamples0 = textureGather(
        depthSampler,
        uv * scale + vec2(2.0 * viewPixelSize.x, 2.0 * viewPixelSize.y)
    );
    vec4 depthSamples1 = textureGather(
        depthSampler,
        uv * scale + vec2(-2.0 * viewPixelSize.x, 2.0 * viewPixelSize.y)
    );
    vec4 depthSamples2 = textureGather(
        depthSampler,
        uv * scale + vec2(2.0 * viewPixelSize.x, -2.0 * viewPixelSize.y)
    );
    vec4 depthSamples3 = textureGather(
        depthSampler,
        uv * scale + vec2(-2.0 * viewPixelSize.x, -2.0 * viewPixelSize.y)
    );

    return max(
        max(maxOf(depthSamples0), maxOf(depthSamples1)),
        max(maxOf(depthSamples2), maxOf(depthSamples3))
    );
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    clouds = vec4(0.0, 0.0, 0.0, 1.0);

#if defined WORLD_OVERWORLD
    ivec2 checkerboardPos = cloudsTemporalUpscaling * texel
        + cloudsCheckerboardOffsets[frameCounter % checkerboardArea];

    vec2 newUv = vec2(checkerboardPos) / vec2(viewRes)
        * rcp(float(taauViewportScale));

    // Get maximum depth from area covered by this fragment
    float depthMax = depthMax4x4(depthtex1, taauViewportScale);

    vec3 screenPos = vec3(newUv, depthMax);
    vec3 viewPos = screenToViewSpace(screenPos, false);

    // LoD terrain support
#ifdef LOD_MOD_ACTIVE
    float depthLod
        = depthMax4x4(lodDepthTexShading, lodDepthTexScale);
    bool isLod = isLodTerrain(depthMax, depthLod);

    if (isLod) {
        screenPos = vec3(newUv, depthLod);
        viewPos = screenToViewSpace(screenPos, false, true);
    }
#else
    const bool isLod = false;
#endif

    vec3 rayOrigin
        = vec3(
              0.0,
              cloudsScale * (eyeAltitude - 63.0) + planetRadius,
              0.0
          )
        + cloudsScale * gbufferModelViewInverse[3].xyz;
    vec3 rayDir = mat3(gbufferModelViewInverse) * normalize(viewPos);

    float distanceToTerrain = (depthMax == 1.0 && !isLod)
        ? -1.0
        : length(viewPos) * cloudsScale;

    vec3 clearSky = atmosphereScattering(
        rayDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        /* useKleinNishinaPhase */ false
    );

    float dither = texelFetch(noisetex, ivec2(checkerboardPos & 511), 0).b;
    dither = r1(frameCounter / checkerboardArea, dither);

#ifndef blockyClouds
    CloudsResult result = drawClouds(
        rayOrigin,
        rayDir,
        clearSky,
        distanceToTerrain,
        dither
    );

    clouds.xyz = result.scattering.xyz;
    clouds.w = result.transmittance;
    cloudsData.x = result.apparentDistance * rcp(cloudsScale);
    cloudsData.y = result.scattering.w;
#else
    clouds = vec4(0.0, 0.0, 0.0, 1.0);
    cloudsData.x = 1e6;
    cloudsData.y = 0.0;
#endif

    // Crepuscular rays

#if defined crepRays && !defined blockyClouds
    vec4 crepuscularRaysSample = drawCrepuscularRays(
        colortex8,
        rayDir,
        distanceToTerrain > 0.0,
        dither
    );
    clouds *= crepuscularRaysSample.w;
    clouds.rgb += crepuscularRaysSample.xyz;
#endif

    // Aurora

    clouds.xyz += drawAurora(rayDir, dither) * clouds.w;
#endif
}
