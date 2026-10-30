/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.

    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file
    or here: https://rre36.com/copyright-license

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#if !defined INCLUDE_LIGHT_EMISSION
#define INCLUDE_LIGHT_EMISSION

#include "/lib/brdf/material.glsl"

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

// First item id reserved for handheld emitters (item.properties).
const int firstHandheldEmitterId = 10032;
const int handheldEmitterCount = 48;

vec3 getHandheldEmitterColor(int itemId) {
    int emitterIndex = itemId - firstHandheldEmitterId;

    if (emitterIndex >= 0 && emitterIndex < handheldEmitterCount) {
        return handheldEmitterLightColor[emitterIndex];
    }

    return vec3(0.0);
}

float getEmissionTier(float emissionLuma) {
    if (emissionLuma >= 1.5) return 200.0;
    if (emissionLuma >= 0.75) return 120.0;
    if (emissionLuma >= 0.35) return 80.0;
    if (emissionLuma > 0.0) return 40.0;

    return 0.0;
}

vec3 boostEmitterChroma(vec3 emission, float emissionLuma) {
    float hueLength = length(emission);
    if (hueLength < 1e-6) return vec3(0.0);

    vec3 hue = emission * rcp(hueLength);
    float emitterLum = clamp01(emissionLuma);

    return mix(sqr(hue), hue, sqrt(emitterLum));
}

vec3 computeEmissionRadiance(
    vec3 albedoSrgb,
    uint materialMask,
    vec3 worldPos,
    vec3 flatNormal,
    vec2 lightLevels,
    vec4 specularMap
) {
    vec2 bakeLightLevels = lightLevels;

    Material material = materialFrom(
        albedoSrgb,
        materialMask,
        worldPos,
        flatNormal,
        bakeLightLevels
    );

    // Hardcoded path: tier-scaled, chroma-boosted radiance.
    float emissionLuma = dot(max0(material.emission), luminanceWeights);
    vec3 hardcodedRadiance
        = boostEmitterChroma(material.emission, emissionLuma)
          * getEmissionTier(emissionLuma);

#if ssptEmissionMode != 0
    // LabPBR map path: specular alpha (0-254 = 0-100% emission, 255 = no
    // emission map), tinted by the albedo, shaped by labEmissionCurve.
    vec3 mapRadiance = vec3(0.0);
    float mapLuma = 0.0;
    #if textureFormat == textureFormatLab11 || textureFormat == textureFormatLab12Plus
    float hasEmissionMap = step(specularMap.a, 254.5 / 255.0);
    float emissionValue = specularMap.a * (255.0 / 254.0);
    vec3 mapRaw = material.albedo * emissionValue * hasEmissionMap;

    mapLuma = dot(max0(mapRaw), luminanceWeights);
    mapRadiance = pow(max(mapRaw, vec3(0.0)), vec3(labEmissionCurve)) * 80.0;
    #endif
#endif

#if ssptEmissionMode == 2
    return mapRadiance;
#elif ssptEmissionMode == 1
    // Brighter raw source wins (luminance comparison; the whole vector is
    // kept so hue is preserved instead of mixing channels).
    return mapLuma > emissionLuma ? mapRadiance : hardcodedRadiance;
#else
    return hardcodedRadiance;
#endif
}

#endif // INCLUDE_LIGHT_EMISSION
