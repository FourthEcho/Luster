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

#if !defined INCLUDE_SKY_PROJECTION
#define INCLUDE_SKY_PROJECTION

#include "/lib/util/fastMath.glsl"

// Sky map projection from https://sebh.github.io/publications/egsr2020.pdf

const ivec2 skyMapRes = ivec2(191, 108);
const vec2 skyMapPixelSize = rcp(vec2(skyMapRes));

vec2 projectSky(vec3 direction) {
    vec2 projectedDir = normalize(direction.xz);

    float azimuthAngle = pi + atan(projectedDir.x, -projectedDir.y);
    float altitudeAngle = halfPi - fastAcos(direction.y);

    vec2 coord;
    coord.x = azimuthAngle * (1.0 / tau);
    coord.y = 0.5
        + 0.5 * sign(altitudeAngle)
            * sqrt(2.0 * rcpPi * abs(altitudeAngle)); // Section 5.3

    // Padding
    const float padAmount = 2.0;
    const float mul = 1.0 - 2.0 * padAmount * skyMapPixelSize.x;
    const float add = padAmount * skyMapPixelSize.x;
    coord.x = coord.x * mul + add;

    coord.x *= 191.0 / 192.0;

    return coord;
}

vec3 unprojectSky(vec2 coord) {
    coord.x *= 192.0 / 191.0;

    // Padding
    const float padAmount = 2.0;
    const float mul = rcp(1.0 - 2.0 * padAmount * skyMapPixelSize.x);
    const float add = (padAmount * skyMapPixelSize.x) * -mul;
    coord.x = fract(coord.x * mul + add);

    // Non-linear mapping of altitude angle (See section 5.3 of the paper)
    coord.y = (coord.y < 0.5) ? -sqr(1.0 - 2.0 * coord.y)
                              : sqr(2.0 * coord.y - 1.0);

    float azimuthAngle = coord.x * tau - pi;
    float altitudeAngle = coord.y * halfPi;

    float altitudeCos = cos(altitudeAngle);
    float altitudeSin = sin(altitudeAngle);
    float azimuthCos = cos(azimuthAngle);
    float azimuthSin = sin(azimuthAngle);

    return vec3(
        altitudeCos * azimuthSin,
        altitudeSin,
        -altitudeCos * azimuthCos
    );
}

#endif // INCLUDE_SKY_PROJECTION
