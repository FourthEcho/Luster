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

#if !defined INCLUDE_ATMOS_AIR_OVERWORLD_VL
#define INCLUDE_ATMOS_AIR_OVERWORLD_VL

#include "/lib/atmos/air/overworld/constants.glsl"
#include "/lib/util/phaseFunctions.glsl"
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
// ---- Mist mode sentinels (also defined in settings.glsl for Iris) ----
#ifndef mistModeOff
#define mistModeOff      0
#define mistModeBasic    1
#define mistModeAdvanced 2
#endif

#if mistMode != mistModeOff


// The noise texture is 2D, so a plain XZ lookup extrudes the mist pattern
// along Y: seen edge-on at the horizon the mist breaks up into vertical
// curtains. Blending two height-shifted slices of the noise into a
// pseudo-3D field keeps the layer soft in every direction instead.
float mistNoise(vec3 worldPos, float scale, vec2 wind) {
    float slice = worldPos.y * 0.2;
    float base = floor(slice);
    float blend = fract(slice);

    // Offset between the slices is irrational-ish so the repetition of the
    // noise texture does not line up from one slice to the next.
    vec2 sliceOffset = vec2(0.21, 0.34);

    float n0 = texture(noisetex, worldPos.xz * scale + sliceOffset * base + wind).w;
    float n1 = texture(
        noisetex,
        worldPos.xz * scale + sliceOffset * (base + 1.0) + wind
    ).w;

    return mix(n0, n1, blend);
}

float mistDensityProfile(vec3 worldPos) {
    // Slow horizontal drift — two independent directions for each octave
    vec2 wind0 = vec2(frameTimeCounter * 0.004,  frameTimeCounter * 0.0025);
    vec2 wind1 = vec2(frameTimeCounter * 0.0068, frameTimeCounter * 0.0041);

    float n0 = mistNoise(worldPos, 0.008, wind0);
    float n1 = mistNoise(worldPos, 0.022, wind1);
    float noise = n0 * 0.7 + n1 * 0.3;

    float altitude = worldPos.y;

    // Exponential falloff above sea level, hard cap at mistAltitude.
    // wetness thickens the layer — after rain, evaporation raises mist density.
    float altAboveSea = altitude - (63.0 + mistSeaLevelBias);
    float envelope = exp2(-max0(altAboveSea) * mistFalloffRate);
    envelope *= sqr(1.0 - linearStep(
        float(mistAltitude) - 12.0,
        float(mistAltitude),
        altitude
    ));
    envelope *= 1.0 + 0.4 * wetness;

    // The Mist Density slider lives in fogParams.mistScatteringCoeff, which
    // carries both scattering and extinction. Applying it here as well made
    // the slider act squared.
    return linearStep(0.35, 0.75, noise) * envelope;
}

// Density-varying phase function.


float mistPhase(float cosTheta, float localDensity) {
    // Thin mist scatters more forward, thick mist is closer to isotropic.
    float g = mix(0.75, 0.40, clamp01(localDensity * 4.0));
    return 0.8 * henyeyGreensteinPhase(cosTheta, g)
         + 0.2 * henyeyGreensteinPhase(cosTheta, -0.1);
}

#if mistMode == mistModeAdvanced


// Optical depth from a mist sample toward the light, in real units (profile
// density times metres times the mist extinction coefficient), so it can feed
// a transmittance directly. The ray runs the distance the light needs to leave
// the layer (long at a low sun, short at noon), capped, in steps of at least
// mistShadowStepLength; samples sit at the middle of each step.
float mistShadowOd(vec3 worldPos, float localDensity, float extinction) {
    if (localDensity < 0.01) return 0.0;

    const int steps = mistShadowSteps;

    float toTop = max(float(mistAltitude) - worldPos.y, 0.0);
    float pathLength = clamp(toTop / max(lightDir.y, 0.1), 0.0, 800.0);
    float stepSize = max(mistShadowStepLength, pathLength / float(steps));

    float od = 0.0;

    for (int i = 0; i < steps; ++i) {
        vec3 pos = worldPos + lightDir * (stepSize * (float(i) + 0.5));
        if (pos.y > float(mistAltitude)) break;
        od += mistDensityProfile(pos);
    }

    return od * stepSize * extinction;
}
#endif // mistModeAdvanced

#endif // mistMode != mistModeOff
#include "/lib/light/distortion.glsl"
#include "/lib/util/lodMod.glsl"
#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

vec2 airFogDensity(vec3 worldPos) {
    const vec2 mul = -rcp(airFogFalloffHalfLife);
    const vec2 add = -mul * airFogFalloffStart;

    vec2 density = exp2(min(worldPos.y * mul + add, 0.0));

    // fade away below sea level
    density *= linearStep(airFogVolumeBottom, 63.0, worldPos.y);

#ifdef airFogCloudyNoise
    const vec3 wind = 0.0003 * vec3(1.0, 0.0, 0.7);

    float noise
        = texture(noisetex, 0.001 * worldPos.xz + wind.xz * frameTimeCounter)
              .w;

    density.y *= 4.0 * sqr(noise);
#endif

    return density * (0.5 * overworldFogIntensity);
}

mat2x3 raymarchAirFog(
    vec3 worldStartPos,
    vec3 worldEndPos,
    bool sky,
    float skylight,
    float dither
) {
    vec3 worldDir = worldEndPos - worldStartPos;

    float lengthSq = lengthSquared(worldDir);
    float norm = inversesqrt(lengthSq);
    float rayLength = lengthSq * norm;
    worldDir *= norm;

    vec3 shadowStartPos
        = transform(shadowModelView, worldStartPos - cameraPosition);
    shadowStartPos = projectOrtho(shadowProjection, shadowStartPos);

    vec3 shadowDir = mat3(shadowModelView) * worldDir;
    shadowDir = diagonal(shadowProjection).xyz * shadowDir;

    float distanceToLowerPlane
        = (airFogVolumeBottom - eyeAltitude) / worldDir.y;
    float distanceToUpperPlane
        = (airFogVolumeTop - eyeAltitude) / worldDir.y;
    float distanceToVolumeStart, distanceToVolumeEnd;

    if (eyeAltitude < airFogVolumeBottom) {
        // Below volume
        distanceToVolumeStart = distanceToLowerPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? -1.0 : distanceToUpperPlane;
    } else if (eyeAltitude < airFogVolumeTop) {
        // Inside volume
        distanceToVolumeStart = 0.0;
        distanceToVolumeEnd = worldDir.y < 0.0
            ? distanceToLowerPlane
            : distanceToUpperPlane;
    } else {
        // Above volume
        distanceToVolumeStart = distanceToUpperPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? distanceToLowerPlane : -1.0;
    }

#ifdef LOD_MOD_ACTIVE
    float fogEnd = float(lodRenderDistance);
#else
    float fogEnd = far;
#endif

    if (distanceToVolumeEnd < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    rayLength = sky ? distanceToVolumeEnd : rayLength;
    rayLength = clamp(rayLength - distanceToVolumeStart, 0.0, fogEnd);

    uint stepCount = uint(
        float(airFogMinStepCount) + airFogStepCountGrowth * rayLength
    );
    stepCount = min(stepCount, airFogMaxStepCount);

    float stepLength = rayLength * rcp(float(stepCount));

    vec3 worldStep = worldDir * stepLength;
    vec3 worldPos = worldStartPos
        + worldDir * (distanceToVolumeStart + stepLength * dither);

    vec3 shadowStep = shadowDir * stepLength;
    vec3 shadowPos = shadowStartPos
        + shadowDir * (distanceToVolumeStart + stepLength * dither);

    vec3 transmittance = vec3(1.0);

    mat2x3 lightSun = mat2x3(0.0); // Rayleigh, mie
    mat2x3 lightSky = mat2x3(0.0); // Rayleigh, mie

    // The mist is a medium of its own: its scattering already carries the
    // mist coefficient, so it must not be scaled by the Mie coefficient the
    // way the fog's Mie medium is.
    vec3 mistSunLight = vec3(0.0);
    vec3 mistSkyLight = vec3(0.0);

    for (int i = 0; i < stepCount;
         ++i, worldPos += worldStep, shadowPos += shadowStep) {
        vec3 shadowScreenPos = distortShadowSpace(shadowPos) * 0.5 + 0.5;

#if defined shadow && !defined PROGRAM_DEFERRED0
        ivec2 shadowTexel = ivec2(
            shadowScreenPos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );

// Boolean options register in Iris only when checked via #ifdef/#ifndef,
// but the mixed-type switch below needs a combined plain "#if defined" to
// select vec3 vs float shadow visibility. This empty check keeps the
// toggle discoverable on the settings screen.
#ifdef airFogColoredLightShafts
#endif
#if defined airFogColoredLightShafts && defined shadowColor
        float depth0 = texelFetch(shadowtex0, shadowTexel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadowTexel, 0).x;
        vec3 color
            = clamp01(texelFetch(shadowcolor0, shadowTexel, 0).rgb * 4.0);
        float colorWeight
            = step(depth0, shadowScreenPos.z) * step(eps, maxOf(color));

        color = color * colorWeight + (1.0 - colorWeight);
        color = mix(vec3(1.0), color, airFogColoredLightShaftsIntensity);

        vec3 shadowVis = step(shadowScreenPos.z, depth1) * color;
        shadowVis = (clamp01(shadowScreenPos) == shadowScreenPos)
            ? shadowVis
            : vec3(1.0);
        // Scalar sun visibility for mist below: float(vec3 > 0.0) is
        // illegal GLSL, so reduce explicitly (this branch is rgb).
        float shadowBinary = step(eps, maxOf(shadowVis));
#else
        float depth1 = texelFetch(shadowtex1, shadowTexel, 0).x;
        float shadowVis = step(
            float(clamp01(shadowScreenPos) == shadowScreenPos)
                * shadowScreenPos.z,
            depth1
        );
        float shadowBinary = shadowVis;
#endif
#else
#define shadowVis 1.0
#define shadowBinary 1.0
#endif

        vec2 density = airFogDensity(worldPos) * stepLength;

        vec3 stepOpticalDepth
            = fogParams.rayleighScatteringCoeff * density.x
            + fogParams.mieExtinctionCoeff * density.y;

#if mistMode != mistModeOff
        float mistD = mistDensityProfile(worldPos) * stepLength;
        stepOpticalDepth += fogParams.mistScatteringCoeff * mistD;
#endif

        vec3 stepTransmittance = exp(-stepOpticalDepth);
        vec3 stepTransmittedFraction
            = (1.0 - stepTransmittance) / max(stepOpticalDepth, eps);

        vec3 visibleScattering = stepTransmittedFraction * transmittance;

        lightSun[0] += visibleScattering * density.x * shadowVis;
        lightSun[1] += visibleScattering * density.y * shadowVis;
        lightSky[0] += visibleScattering * density.x;
        lightSky[1] += visibleScattering * density.y;

#if mistMode != mistModeOff
        if (mistD > 1e-5) {
            float LoV = dot(worldDir, lightDir);

#if mistMode == mistModeAdvanced
            float mistOd = mistShadowOd(
                worldPos,
                mistD / stepLength,
                dot(fogParams.mistScatteringCoeff, vec3(1.0 / 3.0))
            );
            // Power-law self-extinction (multiple-scattering tail of
            // Beer-Lambert) keeps dense mist from glowing through itself
            float mistSunShadow = pow(1.0 + 0.7 * mistOd, -1.0 / 0.7) * shadowBinary;
            float mistPhaseVal  = mistPhase(LoV, mistD / stepLength);
#else
            float mistSunShadow = shadowBinary;
            float mistPhaseVal  = mistPhase(LoV, mistD / stepLength);
#endif

            vec3 mistScatter = mistD * visibleScattering;
            mistSunLight += mistScatter * mistPhaseVal * mistSunShadow;
            mistSkyLight += mistScatter * isotropicPhase;
        }
#endif

        transmittance *= stepTransmittance;
    }


    vec3 midWorldPos = worldStartPos
        + worldDir * (distanceToVolumeStart + rayLength * 0.5);
    float cloudShadowMid
        = getCloudShadows(colortex8, midWorldPos - cameraPosition);
    lightSun *= cloudShadowMid;

    lightSun[0] *= fogParams.rayleighScatteringCoeff;
    lightSun[1] *= fogParams.mieScatteringCoeff;
    lightSky[0] *= fogParams.rayleighScatteringCoeff;
    lightSky[1] *= fogParams.mieScatteringCoeff;

    mistSunLight *= fogParams.mistScatteringCoeff * cloudShadowMid;
    mistSkyLight *= fogParams.mistScatteringCoeff;

    if (!sky) {
        // Skylight falloff
        lightSky[0] *= max(skylight, eyeSkylight);
        lightSky[1] *= max(skylight, eyeSkylight);
        mistSkyLight *= max(skylight, eyeSkylight);
    }

    float LoV = dot(worldDir, lightDir);
    float miePhase = 0.7 * henyeyGreensteinPhase(LoV, fogMieAnisotropy)
        + 0.3 * henyeyGreensteinPhase(LoV, -0.2);

    /*
    // Single scattering
    vec3 scattering  = lightColor * (lightSun * vec2(isotropicPhase,
    miePhase)); scattering += ambientColor * (lightSky *
    vec2(isotropicPhase));
    /*/
    // Multiple scattering
    vec3 scattering = vec3(0.0);
    float scatterAmount = 1.0;
    float anisotropy = 1.0;

#if defined PROGRAM_DEFERRED0
    vec3 ambientColor = ambientColorFog;
#endif

    scattering += 2.0 * (lightSky * vec2(isotropicPhase) + mistSkyLight)
        * ambientColor;

    for (int i = 0; i < 4; ++i) {
        float miePhase = 0.7 * henyeyGreensteinPhase(LoV, fogMieAnisotropy * anisotropy)
            + 0.3 * henyeyGreensteinPhase(LoV, -0.2 * anisotropy);

        vec3 orderLight = lightColor;
#ifdef ozoneLayer


        orderLight *= ozoneMultipleScattering(float(i));
#endif

        scattering += scatterAmount
            * (lightSun * vec2(isotropicPhase, miePhase) + mistSunLight)
            * orderLight
            * (1.0 - 0.9 * rainStrength);

        scatterAmount *= 0.5;
        anisotropy *= 0.7;
    }
    //*/

    scattering *= clamp01(1.0 - blindness - darknessFactor);

    // Artifically brighten fog in the early morning and evening (looks nice)
    float eveningGlow
        = 0.75 * linearStep(0.05, 1.0, exp(-300.0 * sqr(sunDir.y + 0.02)));
    scattering += scattering * eveningGlow;

    return mat2x3(scattering, transmittance);
}

#ifdef shadowVis
#undef shadowVis
#endif

#endif // INCLUDE_ATMOS_AIR_OVERWORLD_VL
