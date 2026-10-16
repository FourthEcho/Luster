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

float f0_to_ior(float f0) {
    float sqrt_f0 = sqrt(f0) * 0.99999;
    return (1.0 + sqrt_f0) / (1.0 - sqrt_f0);
}

vec3 fresnel_schlick(float cos_theta, vec3 f0) {
    float f = pow5(1.0 - cos_theta);
    return f + f0 * (1.0 - f);
}

float fresnelSchlickInverse(float f0, float VoH) {
    return 1.0 - clamp01(f0 + (1.0 - f0) * pow5(1.0 - VoH));
}

vec3 fresnel_dielectric_n(float cos_theta, float n) {
    float g_sq = sqr(n) + sqr(cos_theta) - 1.0;

    if (g_sq < 0.0) {
        return vec3(1.0); // Imaginary g => TIR
    }

    float g = sqrt(g_sq);
    float a = g - cos_theta;
    float b = g + cos_theta;

    return vec3(
        0.5 * sqr(a / b)
        * (1.0 + sqr((b * cos_theta - 1.0) / (a * cos_theta + 1.0)))
    );
}

vec3 fresnel_dielectric(float cos_theta, float f0) {
    float n = f0_to_ior(f0);
    return fresnel_dielectric_n(cos_theta, n);
}


vec3 fresnel_conductor(float cos_theta, vec3 n, vec3 k) {
    float cos2 = cos_theta * cos_theta;
    vec3 nk2 = n * n + k * k;
    vec3 two_n_cos = 2.0 * n * cos_theta;

    vec3 rs_num = nk2 - two_n_cos + cos2;
    vec3 rs_den = nk2 + two_n_cos + cos2;

    vec3 rp_num = nk2 * cos2 - two_n_cos + 1.0;
    vec3 rp_den = nk2 * cos2 + two_n_cos + 1.0;

    return clamp01(0.5 * (rs_num / rs_den + rp_num / rp_den));
}

// Modified by Jessie to correctly account for fresnel
#endif // INCLUDE_BRDF_FRESNEL
