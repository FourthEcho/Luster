#if !defined INCLUDE_LIGHTING_BSDF
#define INCLUDE_LIGHTING_BSDF

#include "/include/utility/fast_math.glsl"

float f0_to_ior(float f0) {
    float sqrt_f0 = sqrt(f0) * 0.99999;
    return (1.0 + sqrt_f0) / (1.0 - sqrt_f0);
}

// https://www.gdcvault.com/play/1024478/PBR-Diffuse-Lighting-for-GGX
float distribution_ggx(float NoH_sq, float alpha_sq) {
    return alpha_sq / (pi * sqr(1.0 - NoH_sq + NoH_sq * alpha_sq));
}

float v1_smith_ggx(float cos_theta, float alpha_sq) {
    return 1.0
        / (cos_theta
           + sqrt((-cos_theta * alpha_sq + cos_theta) * cos_theta + alpha_sq));
}

float v2_smith_ggx(float NoL, float NoV, float alpha_sq) {
    float ggx_l = NoV * sqrt((-NoL * alpha_sq + NoL) * NoL + alpha_sq);
    float ggx_v = NoL * sqrt((-NoV * alpha_sq + NoV) * NoV + alpha_sq);
    return 0.5 / (ggx_l + ggx_v);
}

vec3 fresnel_schlick(float cos_theta, vec3 f0) {
    float f = pow5(1.0 - cos_theta);
    return f + f0 * (1.0 - f);
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

// Full complex-IOR conductor Fresnel from measured optical constants.
// n = real part (stored in material.f0), k = extinction coeff (material.f82).
// Derived from the exact Fresnel equations for a conductor:
//   Rs = ((n²+k²) - 2n·cosθ + cos²θ) / ((n²+k²) + 2n·cosθ + cos²θ)
//   Rp = ((n²+k²)·cos²θ - 2n·cosθ + 1) / ((n²+k²)·cos²θ + 2n·cosθ + 1)
//   R  = 0.5 * (Rs + Rp)
// Applied per-channel so the full spectral colour of each metal is preserved.
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
#endif // INCLUDE_LIGHTING_BSDF
