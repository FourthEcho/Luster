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

#if !defined INCLUDE_UTILITY_SAMPLING
#define INCLUDE_UTILITY_SAMPLING

vec2 vogelDiscSample(int stepIndex, int stepCount, float rotation) {
    const float goldenAngle = 2.4;

    float r = sqrt(stepIndex + 0.5) / sqrt(float(stepCount));
    float theta = stepIndex * goldenAngle + rotation;

    return r * vec2(cos(theta), sin(theta));
}

vec3 uniformSphereSample(vec2 hash) {
    hash.x *= tau;
    hash.y = 2.0 * hash.y - 1.0;
    return vec3(
        vec2(sin(hash.x), cos(hash.x)) * sqrt(1.0 - hash.y * hash.y),
        hash.y
    );
}

// Smootherstep-filtered texture lookup.
// https://iquilezles.org/www/articles/texture/texture.htm
vec4 smoothFilter(sampler2D sampler, vec2 coord) {
    vec2 res = vec2(textureSize(sampler, 0));

    coord = coord * res + 0.5;

    vec2 i, f = modf(coord, i);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    coord = i + f;

    coord = (coord - 0.5) / res;
    return texture(sampler, coord);
}

// https://amietia.com/lambertnotangent.html
#endif // INCLUDE_UTILITY_SAMPLING
