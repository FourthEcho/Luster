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

#if !defined INCLUDE_SKY_AURORA
#define INCLUDE_SKY_AURORA

#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/geometry.glsl"
#include "/lib/util/phaseFunctions.glsl"
#include "/lib/util/random.glsl"

float auroraShape(vec3 pos, float altitudeFraction) {
    const vec2 wind0 = 0.005 * vec2(0.7, 0.1);
    const vec2 wind1 = 0.008 * vec2(-0.1, -0.7);
    const float frequency = 0.00003 * auroraFrequency;

    float heightFade = cube(1.0 - altitudeFraction)
        * linearStep(0.0, 0.025, altitudeFraction);

    float worley0
        = texture(noisetex, pos.xz * frequency + wind0 * frameTimeCounter).y;
    float worley1
        = texture(noisetex, pos.xz * frequency + wind1 * frameTimeCounter).y;

    return linearStep(1.0, 2.0, worley0 + worley1) * heightFade;
}

vec3 auroraColor(vec3 pos, float altitudeFraction) {
    return mix(
        auroraColors[0],
        auroraColors[1],
        clamp01(dampen(altitudeFraction))
    );
}

vec3 drawAurora(vec3 rayDir, float dither) {
    const uint stepCount = 64u;
    const float rcpSteps = rcp(float(stepCount));
    const float volumeBottom = 1000.0;
    const float volumeTop = 3000.0;
    const float volumeRadius = 20000.0;

    if (auroraAmount < 0.01) {
        return vec3(0.0);
    }

    // Calculate distance to enter and exit the volume

    float rcpDirY = rcp(rayDir.y);
    float distanceToLowerPlane = volumeBottom * rcpDirY;
    float distanceToUpperPlane = volumeTop * rcpDirY;
    float distanceToCylinder = volumeRadius * rcpLength(rayDir.xz);

    float distanceToVolumeStart = distanceToLowerPlane;
    float distanceToVolumeEnd
        = min(distanceToCylinder, distanceToUpperPlane);

    // Make sure that the volume is intersected
    if (distanceToVolumeStart > distanceToVolumeEnd) {
        return vec3(0.0);
    }

    // Raymarching setup

    float rayLength = max0(distanceToVolumeEnd - distanceToVolumeStart);
    float stepLength = rayLength * rcpSteps;

    vec3 rayPos = rayDir * (distanceToVolumeStart + stepLength * dither);
    vec3 rayStep = rayDir * stepLength;

    vec3 emission = vec3(0.0);

    // Raymarching loop

    for (uint i = 0u; i < stepCount; ++i, rayPos += rayStep) {
        float altitudeFraction
            = linearStep(volumeBottom, volumeTop, rayPos.y);
        float shape = auroraShape(rayPos, altitudeFraction);
        vec3 color = auroraColor(rayPos, altitudeFraction);

        float d = length(rayPos.xz);
        float distanceFade
            = (1.0 - cube(d * rcp(volumeRadius))) * (1.0 - exp2(-0.001 * d));

        emission += color * (shape * distanceFade * stepLength);
    }

    return (0.001 * auroraBrightness) * emission * auroraAmount;
}

// [0] - bottom color
// [1] - top color
mat2x3 getAuroraColors() {
    const mat2x3[] auroraColors = mat2x3[](
        mat2x3(
            vec3(0.00, 1.00, 0.25), // green
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(0.00, 1.00, 0.25), // green
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.00, 0.00), // red
            vec3(1.00, 0.50, 0.70) // purple
        ),
        mat2x3(
            vec3(1.00, 0.25, 1.00), // magenta
            vec3(0.25, 0.25, 1.00) // deep blue
        ),
        mat2x3(
            vec3(1.00, 0.50, 1.00), // purple
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.50, 1.00), // purple
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.10, 0.00), // red
            vec3(1.00, 1.00, 0.25) // yellow
        ),
        mat2x3(
            vec3(1.00, 1.00, 1.00), // white
            vec3(1.00, 0.00, 0.00) // red
        ),
        mat2x3(
            vec3(1.00, 1.00, 0.00), // yellow
            vec3(0.10, 0.50, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.25, 1.00), // magenta
            vec3(0.00, 1.00, 0.25) // green
        ),
        mat2x3(
            vec3(1.00, 0.70, 1.00) * 1.2, // pink
            vec3(0.90, 0.30, 0.90) // purple
        ),
        mat2x3(
            vec3(0.00, 1.00, 0.25), // green
            vec3(0.90, 0.30, 0.90) // purple
        ),
        mat2x3(
            vec3(2.00, 0.80, 0.00), // orange
            vec3(1.00, 0.50, 0.00) // orange
        )
    );

    uint dayIndex = uint(worldDay);
    dayIndex = lowbias32(dayIndex) % auroraColors.length();

    return auroraColors[dayIndex];
}

// 0.0 - no aurora
// 1.0 - full aurora
float getAuroraAmount() {
    float night = smoothstep(0.0, 0.2, -sunDir.y);

#if auroraNormal == auroraNever
    float auroraNormalFactor = 0.0;
#elif auroraNormal == auroraRarely
    float auroraNormalFactor = float(lowbias32(uint(worldDay)) % 5 == 1);
#elif auroraNormal == auroraAlways
    float auroraNormalFactor = 1.0;
#endif

#if auroraSnow == auroraNever
    float auroraSnowFactor = 0.0;
#elif auroraSnow == auroraRarely
    float auroraSnowFactor = float(lowbias32(uint(worldDay)) % 5 == 1);
#elif auroraSnow == auroraAlways
    float auroraSnowFactor = 1.0;
#endif

    return night * mix(auroraNormalFactor, auroraSnowFactor, biomeMaySnow);
}

#endif // INCLUDE_SKY_AURORA
