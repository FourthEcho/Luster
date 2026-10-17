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

#if !defined INCLUDE_UTILITY_DITHERING
#define INCLUDE_UTILITY_DITHERING

float bayer2(vec2 a) {
    a = floor(a);
    return fract(dot(a, vec2(0.5, 0.75)));
}

// Ordered Bayer cascade: each level adds the coarse pattern plus the fine
// pattern weighted so the sum stays in [0, 1) with mean ~= 0.5
float bayer4(vec2 a) { return bayer2(0.5 * a) + 0.25 * bayer2(a); }

float bayer8(vec2 a) { return bayer4(0.5 * a) + 0.0625 * bayer2(a); }

float bayer16(vec2 a) { return bayer8(0.5 * a) + 0.015625 * bayer2(a); }

float interleavedGradientNoise(vec2 pos) {
    return fract(52.9829189 * fract(0.06711056 * pos.x + (0.00583715 * pos.y)));
}

float interleavedGradientNoise(vec2 pos, int t) {
    return interleavedGradientNoise(pos + 5.588238 * (t & 63));
}

float dither8bit(float x, float pattern) {
    const vec2 mulAdd = vec2(1.0, -0.5) / 255.0;
    return clamp01(x + (pattern * mulAdd.x + mulAdd.y));
}

vec2 dither8bit(vec2 x, float pattern) {
    const vec2 mulAdd = vec2(1.0, -0.5) / 255.0;
    return clamp01(x + (pattern * mulAdd.x + mulAdd.y));
}

vec3 dither8bit(vec3 rgb, float pattern) {
    const vec2 mulAdd = vec2(1.0, -0.5) / 255.0;
    return clamp01(rgb + (pattern * mulAdd.x + mulAdd.y));
}

#endif // INCLUDE_UTILITY_DITHERING
