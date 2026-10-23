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

#if !defined INCLUDE_VERTEX_DISPLACEMENT
#define INCLUDE_VERTEX_DISPLACEMENT

#if !defined PROGRAM_GBUFFERS_TERRAIN \
    && !( \
        defined PROGRAM_SHADOW_FALLBACK || defined PROGRAM_SHADOW_SOLID \
        || defined PROGRAM_SHADOW_CUTOUT \
    )
#undef wavingPlants
#undef wavingLeaves
#endif

#if !defined PROGRAM_GBUFFERS_WATER \
    && !(defined PROGRAM_SHADOW_FALLBACK || defined PROGRAM_SHADOW_WATER)
#undef waterDisplacement
#endif


#if defined wavingPlants || defined wavingLeaves
#include "/lib/weather/core.glsl"
#endif

uniform vec3 eyePosition;

#ifdef waterDisplacement
float gerstnerWave(
    vec2 coord,
    vec2 waveDir,
    float t,
    float noise,
    float wavelength
) {
    // Gerstner wave function from Belmu in #snippets, modified
    const float g = 9.8;

    float k = tau / wavelength;
    float w = sqrt(g * k);

    float x = w * t - k * (dot(waveDir, coord) + noise);

    return sqr(sin(x) * 0.5 + 0.5);
}

float getWaterDisplacement(vec3 worldPos, float skylight) {
    const float waveFrequency = 0.3 * waterWaveFrequency;
    const float waveSpeed = 0.37 * waterWaveSpeedStill;
    const float waveAngle = 30.0 * degree;
    const float wavelength = 1.0;
    const vec2 waveDir = vec2(cos(waveAngle), sin(waveAngle));

    float wave = gerstnerWave(
        worldPos.xy * waveFrequency,
        waveDir,
        frameTimeCounter * waveSpeed,
        0.0,
        wavelength
    );
    wave = (wave * 0.05 - 0.025) * (skylight * 0.9 + 0.1);

#ifdef LOD_MOD_ACTIVE
    // Attenuate displacement towards the edge of the render distance, to
    // prevent seam between vanilla and LoD terrain
    float fade = cubicLength(worldPos.xz - cameraPosition.xz) / far;

    wave *= exp2(-8.0 * cube(fade));
    ;
#endif

    return wave;
}
#endif

#if defined wavingPlants || defined wavingLeaves
vec3 getWindDisplacement(
    vec3 worldPos,
    float windSpeed,
    float windStrength,
    bool isTallPlantTopVertex
) {
    const float windAngle = 30.0 * degree;
    const vec2 windDir = vec2(cos(windAngle), sin(windAngle));

#if defined WORLD_OVERWORLD
    // Adjust wind strength based on weather windiness
    float windiness = weatherWind();
    windStrength *= 0.5 + windiness;
#endif

    float t = windSpeed * frameTimeCounter;

    float gustAmount
        = texture(noisetex, 0.05 * (worldPos.xz + windDir * t)).y;
    gustAmount *= gustAmount;

    vec3 gust = vec3(windDir * gustAmount, 0.1 * gustAmount).xzy;

    worldPos = 32.0 * worldPos + 3.0 * t
        + vec3(0.0, goldenAngle, 2.0 * goldenAngle);
    vec3 wobble = sin(worldPos) + 0.5 * sin(2.0 * worldPos)
        + 0.25 * sin(4.0 * worldPos);

    if (isTallPlantTopVertex) {
        gust *= 2.0;
        wobble *= 0.5;
    }

    return windStrength * (gust + 0.1 * wobble);
}
#endif

vec3 animateVertex(
    vec3 worldPos,
    bool isTopVertex,
    float skylight,
    uint materialMask
) {
    float windSpeed = 0.3;
    float windStrength = sqr(skylight) * (0.25 + 0.66 * rainStrength);

    // Displace plants close to the player
    vec3 toPlayer = eyePosition - worldPos;
    vec3 playerDisplacement
        = vec3(
              -6.0 * toPlayer.xz
                  * exp2(-length(toPlayer * vec3(6.0, 2.0, 6.0))),
              0.0
        )
              .xzy;

    switch (materialMask) {
#ifdef waterDisplacement
        case MATERIAL_WATER:
            worldPos.y += getWaterDisplacement(worldPos, skylight);
            return worldPos;
#endif

#ifdef wavingPlants
        case MATERIAL_SMALL_PLANTS:
        case MATERIAL_OPEN_EYEBLOSSOM:
            return worldPos
                + (getWindDisplacement(
                       worldPos,
                       windSpeed,
                       windStrength,
                       false
                   )
                   + playerDisplacement)
                * float(isTopVertex);

        case MATERIAL_TALL_PLANTS_LOWER:
            return worldPos
                + (getWindDisplacement(
                       worldPos,
                       windSpeed,
                       windStrength,
                       false
                   )
                   + playerDisplacement)
                * float(isTopVertex);

        case MATERIAL_TALL_PLANTS_UPPER:
            return worldPos
                + (getWindDisplacement(
                       worldPos,
                       windSpeed,
                       windStrength,
                       isTopVertex
                   )
                   + playerDisplacement);
#endif

#ifdef wavingLeaves
        case MATERIAL_LEAVES:
            return worldPos
                + getWindDisplacement(
                       worldPos,
                       windSpeed,
                       windStrength * 0.5,
                       false
                );
#endif

        default:
            return worldPos;
    }
}

#endif // INCLUDE_VERTEX_DISPLACEMENT
