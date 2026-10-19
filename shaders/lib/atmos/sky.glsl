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

#if !defined INCLUDE_ATMOS_SKY
#define INCLUDE_ATMOS_SKY

#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"

#if defined WORLD_OVERWORLD || defined WORLD_END
#if !defined INCLUDE_ATMOS_SKY_STARS
#define INCLUDE_ATMOS_SKY_STARS

// Stars based on https://www.shadertoy.com/view/Md2SR3

vec3 unstableStarField(vec2 coord, float starThresh) {
    const float minTemp = 4500.0;
    const float maxTemp = 8500.0;

    vec4 noise = hash4(coord);

    float star = linearStep(starThresh, 1.0, noise.x);
    star = pow16(star) * starsIntensity;

    float temp = mix(minTemp, maxTemp, noise.y);
    vec3 color = blackbody(temp);

    const float twinkleSpeed = 2.0;
    float twinkleAmount = noise.z;
    float twinkleOffset = tau * noise.w;
    star *= 1.0
        - twinkleAmount
            * cos(frameTimeCounter * twinkleSpeed + twinkleOffset);

    return star * color;
}

// Stabilizes the star field by sampling at the four neighboring integer
// coordinates and interpolating
vec3 stableStarField(vec2 coord, float starThresh) {
    coord = abs(coord) + 33.3 * step(0.0, coord);
    vec2 i, f = modf(coord, i);

    f.x = cubicSmooth(f.x);
    f.y = cubicSmooth(f.y);

    return unstableStarField(i + vec2(0.0, 0.0), starThresh) * (1.0 - f.x)
        * (1.0 - f.y)
        + unstableStarField(i + vec2(1.0, 0.0), starThresh) * f.x
        * (1.0 - f.y)
        + unstableStarField(i + vec2(0.0, 1.0), starThresh) * f.y
        * (1.0 - f.x)
        + unstableStarField(i + vec2(1.0, 1.0), starThresh) * f.x * f.y;
}

vec3 drawStars(vec3 rayDir, float galaxyLuminance) {
    // Adjust star threshold so that brightest stars appear first
#if defined WORLD_OVERWORLD
    float starThresh = 1.0
        - 0.05 * starsCoverage * smoothstep(-0.2, 0.05, -sunDir.y)
        - 0.5 * cube(galaxyLuminance);
#else
    float starThresh = 1.0 - 0.008 * starsCoverage;
#endif

    // Project ray direction onto the plane
    vec2 coord = rayDir.xy * rcp(abs(rayDir.z) + length(rayDir.xy))
        + 41.21 * sign(rayDir.z);
    coord *= 600.0;

    return stableStarField(coord, starThresh);
}

#endif // INCLUDE_ATMOS_SKY_STARS

#endif

//----------------------------------------------------------------------------//
#if defined WORLD_OVERWORLD

#include "/lib/brdf/fresnel.glsl"
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
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
#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/atmos/projection.glsl"

#if !defined INCLUDE_ATMOS_SKY_RAINBOW
#define INCLUDE_ATMOS_SKY_RAINBOW

#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"

// Colours of the rainbow, specified in CIE LAB
const vec3[] rainbowColorsLab = vec3[](
    // Black (padding)
    vec3(0.0, 0.0, 0.0),
    // Red
    vec3(1.9204079259259252, 8.615652850435307, 3.034993236839206),
    // Orange
    vec3(5.150595481481478, 2.0166722671075, 7.751801674224828),
    // Yellow
    vec3(8.374896406590196, -4.55693490912186, 12.458460748771072),
    // Green
    vec3(6.460375111111109, -13.197961166655613, 9.433616874771245),
    // Blue
    vec3(2.5902924592592598, 0.6233705627450292, -9.638464531481834),
    // Indigo
    vec3(0.6521799259259282, 4.582758912741708, -12.47089864973529),
    // Violet
    vec3(2.57258785185185, 13.19841176317703, -9.435757721780169),
    // Black (padding)
    vec3(0.0, 0.0, 0.0)
);

const float firstRainbowMiddleAngle = 42.0 * degree;
const float firstRainbowThickness = 4.0 * degree;
const float secondRainbowMiddleAngle = 47.0 * degree;
const float secondRainbowThickness = 3.0 * degree;
const float rainbowStartDistance = 500.0;
const float rainbowEndDistance = 600.0;

vec3 drawSingleRainbow(float viewAngle, float startAngle, float endAngle) {
    float rainbowProgress
        = linearStepUnclamped(startAngle, endAngle, viewAngle);

    if (clamp01(rainbowProgress) != rainbowProgress) {
        return vec3(0.0);
    }

    float i,
        f = modf(
            rainbowProgress * float(rainbowColorsLab.length() - 1) - 0.5,
            i
        );

    vec3 rainbowColorLab
        = mix(rainbowColorsLab[int(i)], rainbowColorsLab[int(i + 1)], f);
    vec3 rainbowColor = max0(labToXyz(rainbowColorLab) * xyzToWorkingColor);
    float rainbowIntensity
        = rainbowProgress - rainbowProgress * dampen(rainbowProgress);

    return rainbowColor * rainbowIntensity;
}

vec3 drawRainbows(
    vec3 fragmentColor,
    vec3 directionWorld,
    float viewDistance
) {
#ifndef rainbows
    return fragmentColor;
#endif

    if (rainbowAmount < eps) {
        return fragmentColor;
    }

    float rainbowAngle
        = fastAcos(clamp(-dot(directionWorld, lightDir), -1.0, 1.0));

    vec3 firstRainbow = drawSingleRainbow(
        rainbowAngle,
        firstRainbowMiddleAngle + firstRainbowThickness * 0.5,
        firstRainbowMiddleAngle - firstRainbowThickness * 0.5
    );

    vec3 secondRainbow = drawSingleRainbow(
        rainbowAngle,
        secondRainbowMiddleAngle - secondRainbowThickness * 0.5,
        secondRainbowMiddleAngle + secondRainbowThickness * 0.5
    );

    vec3 transmittanceApprox
        = mix(vec3(1.0, 0.75, 0.5), vec3(1.0), dampen(max0(directionWorld.y)));

    vec3 rainbowColor = lightColor * (0.1 * rainbowsIntensity)
        * (3.0 * firstRainbow + 0.5 * secondRainbow)
        * sqr(transmittanceApprox);
    float rainbowFade = rainbowAmount
        * smoothstep(rainbowStartDistance,
                     rainbowEndDistance,
                     viewDistance)
        * smoothstep(0.0, 0.05, directionWorld.y);
    ;

    return fragmentColor + rainbowColor * rainbowFade;
}

#endif // INCLUDE_ATMOS_SKY_RAINBOW
#include "/lib/util/geometry.glsl"

#if defined PROGRAM_DEFERRED0
#include "/lib/atmos/clouds/utility/pipeline.glsl"

#if defined crepuscularRays && !defined blockyClouds

#if !defined INCLUDE_ATMOS_SKY_CREPUSCULAR_RAYS
#define INCLUDE_ATMOS_SKY_CREPUSCULAR_RAYS

#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/clouds/utility/constants.glsl"
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
#include "/lib/util/lodMod.glsl"
#include "/lib/atmos/clouds/utility/common.glsl"

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

const float sunLuminance = rcp(
    coneAngleToSolidAngle(sunAngularSizeRad)
); // luminance of sun disk
const float moonLuminance = 10.0; // luminance of moon disk

vec3 drawSun(vec3 rayDir) {
    float nu = dot(rayDir, sunDir);

    // Limb darkening model from
    // http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
    const vec3 alpha = vec3(0.429, 0.522, 0.614);
    float centerToEdge = max0(sunAngularSizeRad - fastAcos(clamp(nu, -1.0, 1.0)));
    vec3 limbDarkening
        = pow(vec3(1.0 - sqr(1.0 - centerToEdge)), 0.5 * alpha);

    return sunLuminance * sunColor * step(0.0, centerToEdge)
        * limbDarkening;
}

vec4 drawMoon(vec3 rayDir) {
    const vec3 litColor
        = vec3(moonR, moonG <= 0.03 ? 0.0 : moonG - 0.03, moonB);
    const vec3 glowColor
        = vec3(moonR <= 0.05 ? 0.0 : moonR - 0.05, moonG, moonB);

    // Cut out the moon disc.
    float MoV = dot(rayDir, moonDir);
    if (MoV < cos(moonAngularSizeRad)) {
        return vec4(0.0);
    }

    // Find distance from center to edge.
    float dist = clamp01(fastAcos(clamp(MoV, -1.0, 1.0)) / moonAngularSizeRad);

    // Transform the coordinate space such that z is parallel to moonDir
    vec3 tangent = abs(moonDir.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
    vec3 bitangent = normalize(cross(tangent, moonDir));
    mat3 tbn = mat3(tangent, bitangent, moonDir);

    // Vector from ray dir to moon dir.
    vec2 offset = ((rayDir - moonDir) * tbn).xy;
    offset = fract(offset + 0.5);

    vec3 noise = texture(noisetex, 2.0 * offset).xyz;
    float moonTexture
        = pow1d5(noise.x) * 0.75 + 0.6 * cube(noise.y) - 0.1 * noise.z;

    // Find the distance to the moon if it were 1 unit away, and its normal.
    float moonDist
        = intersectSphere(-moonDir, rayDir, moonAngularSizeRad).x;
    vec3 moonNormal = normalize(rayDir * moonDist - moonDir);

    // Get light direction which orbits around moon. Anchored to the fixed
    // moon frame so the phase terminator does not swim with the view ray.
    float lightAngle = 0.125 * tau * float(moonPhase);
    vec3 leftDir = abs(moonDir.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
    vec3 lightDir = cos(lightAngle) * -moonDir + sin(lightAngle) * leftDir;
    float moonShadow = dampen(max0(dot(moonNormal, lightDir)));

    float edgeGlow = sqr(sqr(sqr(dist)));

    vec3 color = max(moonShadow * litColor * (1.0 + 4.0 * edgeGlow),
                     0.5 * glowColor * (0.1 + 0.1 * edgeGlow))
        * (0.2 + 0.8 * moonTexture);
    color = moonLuminance * sqr(color);
    return vec4(color, 1.0);
}

#ifdef galaxy
vec3 drawGalaxy(vec3 rayDir, out float galaxyLuminance) {
    const vec3 galaxyTint = vec3(0.75, 0.66, 1.0) * galaxyIntensity;

    float galaxyBrightness = 0.05 + 1.0 * linearStep(-0.1, 0.25, -sunDir.y);

    float lon = atan(rayDir.x, rayDir.z);
    float lat = fastAcos(clamp(-rayDir.y, -1.0, 1.0));

    vec3 galaxyColor
        = texture(galaxySampler, vec2(lon * rcp(tau) + 0.5, lat * rcp(pi)))
              .rgb;

    galaxyColor = srgbEotfInv(galaxyColor) * rec709ToWorkingColor;

    galaxyColor *= galaxyBrightness * galaxyTint;

    galaxyLuminance = dot(galaxyColor, luminanceWeights);

    galaxyColor = mix(vec3(galaxyLuminance), galaxyColor, 2.0);

    return max0(galaxyColor);
}
#endif

vec3 drawSky(
    vec3 rayDir,
    vec3 atmosphere,
    vec4 cloudsAndAurora,
    float cloudsApparentDistance
) {
    vec3 sky = vec3(0.0);

#if defined shadow
    // Trick to make stars rotate with sun and moon
    mat3 rot = (sunAngle < 0.5)
        ? mat3(shadowModelViewInverse)
        : mat3(
              -shadowModelViewInverse[0].xyz,
              shadowModelViewInverse[1].xyz,
              -shadowModelViewInverse[2].xyz
          );

    vec3 celestialDir = rayDir * rot;
#else
    vec3 celestialDir = rayDir;
#endif

    // Galaxy

#ifdef galaxy
    float galaxyLuminance;
    sky += drawGalaxy(celestialDir, galaxyLuminance);
#else
    const float galaxyLuminance = 0.0;
#endif

    // Sun, moon stars

#if defined PROGRAM_DEFERRED11
    vec3 skytexturedOutput
        = texelFetch(colortex0, ivec2(gl_FragCoord.xy), 0).rgb;
    sky += skytexturedOutput;

#ifdef stars
    // Stars
    float starsVisibility
        = clamp01(1.0 - dot(skytexturedOutput, vec3(0.33) * 256.0));
    sky += drawStars(celestialDir, galaxyLuminance) * starsVisibility;
#endif

#ifndef vanillaSun
    // Shader sun
    sky += drawSun(rayDir);
#endif

#ifndef vanillaMoon
    // Shader moon
    vec4 moon = drawMoon(rayDir);
    sky *= 1.0 - moon.a;
    sky += moon.rgb;
#endif
#endif

    // Atmosphere

    sky *= atmosphereTransmittance(rayDir.y, planetRadius)
        * (1.0 - rainStrength);
#if defined desertSandstorm && defined sandstormSky


    sky *= sandstormTransmittance(rayDir.y);
#endif
    sky += atmosphere;

    // Clouds, aurora, crepuscular rays

    sky *= cloudsAndAurora.a; // Transmittance
    sky += cloudsAndAurora.rgb; // Scattering

    // Rainbow

    sky = drawRainbows(
        sky,
        rayDir,
        mix(cloudsApparentDistance,
            1e6,
            linearStep(1.0, 0.95, cloudsAndAurora.w))
    );

    // Cave sky fix

#if !defined PROGRAM_DEFERRED0
    // Fade lower part of sky into cave fog color when underground so that the
    // sky isn't visible beyond the render distance
    float undergroundSkyFade
        = biomeCave * smoothstep(-0.1, 0.1, 0.4 - rayDir.y);
    sky = mix(sky, vec3(0.0), undergroundSkyFade);
#endif

    return sky;
}

#if defined PROGRAM_DEFERRED0
vec4 getCloudsAndAurora(
    vec3 rayDir,
    vec3 clearSky,
    out float cloudsApparentDistance
) {
    cloudsApparentDistance = 1e6;

    ivec2 texel = ivec2(gl_FragCoord.xy);
    texel.x = texel.x % (skyMapRes.x - 4);

    float dither = interleavedGradientNoise(vec2(texel));

    // Clouds

#ifndef blockyClouds
    const vec3 airViewerPos = vec3(0.0, planetRadius, 0.0);
    CloudsResult result
        = drawClouds(airViewerPos, rayDir, clearSky, -1.0, dither);

    // Lightning flash
    result.scattering.rgb += LIGHTNING_FLASH_UNIFORM * lightningFlashIntensity
        * result.scattering.a;
#else
    CloudsResult result = cloudsNotHit;
#endif

    cloudsApparentDistance = result.apparentDistance;

    // Aurora

    vec3 aurora = drawAurora(rayDir, dither);

    vec4 cloudsAndAurora = vec4(
        result.scattering.xyz + aurora * result.transmittance,
        result.transmittance
    );

    // Crepuscular rays (sky-map ambient path only)

#if defined crepuscularRays && !defined blockyClouds
    vec4 crepuscularRaysSample
        = drawCrepuscularRays(colortex8, rayDir, false, dither);
    cloudsAndAurora *= crepuscularRaysSample.w;
    cloudsAndAurora.rgb += crepuscularRaysSample.xyz;
#endif

    return cloudsAndAurora;
}

vec3 drawSky(vec3 rayDir) {
    vec3 atmosphere = atmosphereScattering(
        rayDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        true
    );
    float cloudsApparentDistance;
    vec4 cloudsAndAurora
        = getCloudsAndAurora(rayDir, atmosphere, cloudsApparentDistance);
    return drawSky(
        rayDir,
        atmosphere,
        cloudsAndAurora,
        cloudsApparentDistance
    );
}
#endif

//----------------------------------------------------------------------------//
#elif defined WORLD_NETHER

vec3 drawSky(vec3 rayDir) { return ambientColor; }

//----------------------------------------------------------------------------//
#elif defined WORLD_END

#include "/lib/atmos/air/atmosphere.glsl"

const float sunSolidAngle = coneAngleToSolidAngle(sunAngularSizeRad);
const vec3 endSunColor = vec3(1.0, 0.5, 0.25);

vec3 drawSun(vec3 rayDir) {
    float nu = dot(rayDir, sunDir);
    float r = fastAcos(clamp(nu, -1.0, 1.0));

    // Sun disk

    const vec3 alpha = vec3(0.6, 0.5, 0.4);
    float centerToEdge = max0(sunAngularSizeRad - r);
    vec3 limbDarkening
        = pow(vec3(1.0 - sqr(1.0 - centerToEdge)), 0.5 * alpha);
    vec3 sunDisk = limbDarkening * vec3(r < sunAngularSizeRad);

    // Solar flare effect

    // Transform the coordinate space such that z is parallel to sunDir
    vec3 tangent = sunDir.y == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), sunDir));
    vec3 bitangent = normalize(cross(tangent, sunDir));
    mat3 rot = mat3(tangent, bitangent, sunDir);

    // Vector from ray dir to sun dir
    vec2 q = ((rayDir - sunDir) * rot).xy;

    float theta = fract(
        linearStep(-pi, pi, atan(q.y, q.x)) + 0.015 * frameTimeCounter
        - 0.33 * r
    );

    float flare
        = texture(noisetex, vec2(theta, r - 0.025 * frameTimeCounter)).x;
    flare = pow5(flare) * exp(-25.0 * (r - sunAngularSizeRad));
    flare = r < sunAngularSizeRad ? 0.0 : flare;

    return endSunColor * rcp(sunSolidAngle) * max0(sunDisk + 0.1 * flare);
}

vec3 drawSky(vec3 rayDir) {
    // Sky gradient

    float upGradient
        = linearStep(0.0, 0.4, rayDir.y) + linearStep(0.1, 0.8, -rayDir.y);
    vec3 sky = ambientColor * mix(0.1, 0.04, upGradient);
    float miePhase = cornetteShanksPhase(dot(rayDir, sunDir), 0.6);
    sky += 0.1 * (ambientColor + 0.5 * endSunColor) * miePhase;

#if defined PROGRAM_DEFERRED11
    // Sun

#ifdef endSunEffect
    // Fixed End sun disk brightness


    sky += drawSun(rayDir) * 1.00;
#endif

    // Stars

    vec3 starsFade
        = exp2(-0.1 * max0(1.0 - rayDir.y) / max(ambientColor, eps))
        * linearStep(-0.2, 0.0, rayDir.y);
    sky += drawStars(rayDir, 0.0).xzy * starsFade;
#endif

    return sky;
}

#endif

#endif // INCLUDE_ATMOS_SKY
