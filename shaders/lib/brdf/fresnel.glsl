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

#if !defined INCLUDE_BRDF_FRESNEL
#define INCLUDE_BRDF_FRESNEL

#include "/lib/util/fastMath.glsl"

float f0ToIor(float f0) {
    float sqrtF0 = sqrt(f0) * 0.99999;
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

vec3 fresnelSchlick(float cosTheta, vec3 f0) {
    float f = pow5(1.0 - cosTheta);
    return f + f0 * (1.0 - f);
}

float fresnelSchlickInverse(float f0, float VoH) {
    return 1.0 - clamp01(f0 + (1.0 - f0) * pow5(1.0 - VoH));
}

vec3 fresnelDielectricN(float cosTheta, float n) {
    float gSq = sqr(n) + sqr(cosTheta) - 1.0;

    if (gSq < 0.0) {
        return vec3(1.0); // Imaginary g => TIR
    }

    float g = sqrt(gSq);
    float a = g - cosTheta;
    float b = g + cosTheta;

    return vec3(
        0.5 * sqr(a / b)
        * (1.0 + sqr((b * cosTheta - 1.0) / (a * cosTheta + 1.0)))
    );
}

vec3 fresnelDielectric(float cosTheta, float f0) {
    float n = f0ToIor(f0);
    return fresnelDielectricN(cosTheta, n);
}


vec3 fresnelConductor(float cosTheta, vec3 n, vec3 k) {
    float cos2 = cosTheta * cosTheta;
    vec3 nk2 = n * n + k * k;
    vec3 twoNCos = 2.0 * n * cosTheta;

    vec3 rsNum = nk2 - twoNCos + cos2;
    vec3 rsDen = nk2 + twoNCos + cos2;

    vec3 rpNum = nk2 * cos2 - twoNCos + 1.0;
    vec3 rpDen = nk2 * cos2 + twoNCos + 1.0;

    return clamp01(0.5 * (rsNum / rsDen + rpNum / rpDen));
}

// Modified by Jessie to correctly account for fresnel
#endif // INCLUDE_BRDF_FRESNEL
