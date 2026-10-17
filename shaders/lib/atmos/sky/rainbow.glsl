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

#if !defined INCLUDE_SKY_RAINBOW
#define INCLUDE_SKY_RAINBOW

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

#endif // INCLUDE_SKY_RAINBOW
