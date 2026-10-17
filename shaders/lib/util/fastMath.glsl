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

#if !defined INCLUDE_UTILITY_FAST_MATH
#define INCLUDE_UTILITY_FAST_MATH

// -----------------------
//   Trig approximations
// -----------------------

// Faster alternative to acos
// Source:
// https://seblagarde.wordpress.com/2014/12/01/inverse-trigonometric-functions-gpu-optimization-for-amd-gcn-architecture/#more-3316


float fastAcos(float x) {
    const float C0 = 1.57018;
    const float C1 = -0.201877;
    const float C2 = 0.0464619;

    float res = (C2 * abs(x) + C1) * abs(x) + C0; // p(x)
    res *= sqrt(1.0 - abs(x));

    return x >= 0 ? res : pi - res; // Undo range reduction
}

vec2 fastAcos(vec2 v) { return vec2(fastAcos(v.x), fastAcos(v.y)); }

// -------------------
//   Power functions
// -------------------

float pow4(float x) { return sqr(sqr(x)); }

float pow5(float x) { return pow4(x) * x; }

float pow8(float x) { return sqr(pow4(x)); }

float pow12(float x) { return cube(pow4(x)); }

float pow16(float x) {
    x *= x;
    x *= x;
    x *= x;
    x *= x;
    return x;
}

float pow32(float x) {
    x *= x;
    x *= x;
    x *= x;
    x *= x;
    x *= x;
    return x;
}

float pow1d5(float x) { return x * sqrt(x); }

// ---------------------------
//   Vector helper functions
// ---------------------------

float rcpLength(vec2 v) { return inversesqrt(dot(v, v)); }

float rcpLength(vec3 v) { return inversesqrt(dot(v, v)); }

// Computes the length of a vector and normalizes it using one inversesqrt
void lengthNormalize(vec2 v, out vec2 normalized, out float len) {
    float lenSq = lengthSquared(v);
    if (lenSq < eps) {
        normalized = vec2(0.0);
        len = 0.0;
        return;
    }
    float rcpLen = inversesqrt(lenSq);
    len = lenSq * rcpLen;
    normalized = rcpLen * v;
}

void lengthNormalize(vec3 v, out vec3 normalized, out float len) {
    float lenSq = lengthSquared(v);
    if (lenSq < eps) {
        normalized = vec3(0.0);
        len = 0.0;
        return;
    }
    float rcpLen = inversesqrt(lenSq);
    len = lenSq * rcpLen;
    normalized = rcpLen * v;
}

vec2 clampLength(vec2 v, float minLen, float maxLen) {
    float len;
    vec2 normalized;
    lengthNormalize(v, normalized, len);

    return normalized * clamp(len, minLen, maxLen);
}

vec3 clampLength(vec3 v, float minLen, float maxLen) {
    float len;
    vec3 normalized;
    lengthNormalize(v, normalized, len);

    return normalized * clamp(len, minLen, maxLen);
}

// Compute the length of a vector, knowing its direction
// I don't know if this is really faster
float lengthKnowingDirection(vec3 v, vec3 vNorm) {
    if (vNorm.x != 0.0) {
        return abs(v.x / vNorm.x);
    } else if (vNorm.y != 0.0) {
        return abs(v.y / vNorm.y);
    } else {
        return abs(v.z / vNorm.z);
    }
}

// ------------------------
//   f16 helper functions
// ------------------------

#define rcpF16(x) (f16(1.0) / (x))
#define clamp01F16(x) clamp(x, f16(0.0), f16(1.0))
#define max0F16(x) max(x, f16(0.0))
#define min1F16(x) min(x, f16(1.0))

#endif // INCLUDE_UTILITY_FAST_MATH
