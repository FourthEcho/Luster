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

vec3 fresnel_lazanyi_2019(float cos_theta, vec3 f0, vec3 f82) {
    vec3 a = 17.6513846 * (f0 - f82) + 8.16666667 * (1.0 - f0);
    float m = pow5(1.0 - cos_theta);
    return clamp01(f0 + (1.0 - f0) * m - a * cos_theta * (m - m * cos_theta));
}

// Modified by Jessie to correctly account for fresnel
vec3 diffuse_hammon(
    vec3 albedo,
    float roughness,
    float f0,
    float NoL,
    float NoV,
    float NoH,
    float LoV
) {
    if (NoL <= 0.0) {
        return vec3(0.0);
    }

    float facing = 0.5 * LoV + 0.5;

    float fresnel_nl = fresnel_dielectric(max(NoL, 1e-2), f0).x;
    float fresnel_nv = fresnel_dielectric(max(NoV, 1e-2), f0).x;
    float energy_conservation_factor
        = 1.0 - (4.0 * sqrt(f0) + 5.0 * f0 * f0) * (1.0 / 9.0);

    float single_rough
        = max0(facing) * (-0.2 * facing + 0.45) * (1.0 / NoH + 2.0);
    float single_smooth
        = (1.0 - fresnel_nl) * (1.0 - fresnel_nv) / energy_conservation_factor;

    float single = mix(single_smooth, single_rough, roughness) * rcp_pi;
    float multi = 0.1159 * roughness;

    return albedo * multi + single;
}

// ---------------------------------------------------------------------------
//   Kulla-Conty multi-bounce GGX energy compensation
//
//   Reference: "Revisiting Physically Based Shading at Imageworks"
//   (Kulla & Conty, SIGGRAPH 2017)
//
//   Single-scatter GGX loses energy at high roughness because light that
//   bounces between microfacets multiple times is not modeled by the
//   single-scatter BRDF. The Kulla-Conty residual term f_ms approximates
//   this missing multi-bounce energy and is added to the specular result.
//
//   Key quantities:
//     E(μ_o)   = directional albedo (single-scatter reflectance for a given
//                view angle and roughness). Approximated below with a
//                closed-form fit (Heitz 2014 / Frosch 2017).
//     E_avg    = hemispherical albedo (cosine-weighted average of E over the
//                hemisphere). Approximated as 1 - α/2 for GGX.
//
//   The residual BRDF:
//     f_ms = (1 - E(μ_o)) * (1 - E_avg) / (π * (1 - E_avg * E(μ_o)))
//
//   When tinted by F0 (for metals / colored Fresnel), the canonical form is:
//     f_ms_colored = f_ms * F_avg
//   where F_avg is the hemispherical-directional Fresnel:
//     F_avg = F0 + (1 - F0) / 21
//
//   We return f_ms_colored * NoL so the caller can add it directly to the
//   single-scatter GGX specular highlight (d * v * NoL * F).
// ---------------------------------------------------------------------------

// Directional albedo E(μo) for a GGX BRDF — closed-form approximation.
// NoV is clamped to [eps, 1] to avoid singularities at grazing angles.
// Returns a value in [0, 1] representing the fraction of incoming light
// that gets reflected by a single bounce of the GGX microfacet BRDF.
float directional_albedo_ggx(float NoV, float alpha) {
    NoV = max(NoV, 1e-3);
    // Frosch 2017 fit: piecewise approximation with <1% error across the
    // full roughness range. We use a slightly simplified form that matches
    // the Filament implementation.
    float a = 1.0 - 0.5 * alpha / (alpha + 0.33);
    float b = 0.25 + 0.5 * alpha;
    float E_o = a + (1.0 - a) * pow5(1.0 - NoV) * b;
    return clamp01(E_o);
}

// Hemispherical albedo E_avg (cosine-weighted average of E(μo) over the
// hemisphere). For GGX this is approximately 1 - α/2 for the dielectric case.
float hemispherical_albedo_ggx(float alpha) {
    return clamp01(1.0 - 0.5 * alpha);
}

// Kulla-Conty residual BRDF (multi-bounce), already multiplied by NoL so the
// caller can add it directly to the single-scatter GGX specular term.
//
//   roughness : material roughness (sqrt of alpha squared)
//   NoL       : dot(normal, light_dir), clamped to [0, 1] by the caller
//   NoV       : dot(normal, view_dir), clamped to [eps, 1]
//   fresnel   : Fresnel term F(LoH) computed for the same light/view dirs
//               as the single-scatter highlight — used to tint the multi-
//               scatter the same way the single-scatter is tinted.
vec3 kulla_conty_residual(float NoL, float NoV, float roughness, vec3 fresnel) {
    // GGX alpha is roughness²; clamp to avoid divide-by-zero on perfect mirrors.
    float alpha = max(roughness * roughness, 1e-3);

    float E_o   = directional_albedo_ggx(NoV, alpha);
    float E_avg = hemispherical_albedo_ggx(alpha);

    // Residual BRDF: (1-E_o)(1-E_avg) / (π (1 - E_avg E_o))
    float denom = max(1.0 - E_avg * E_o, 1e-4);
    float f_ms  = (1.0 - E_o) * (1.0 - E_avg) / (pi * denom);

    // Tint multi-scatter by F_avg (hemispherical Fresnel) so colored metals
    // and dielectrics get the right residual color. F_avg = F0 + (1-F0)/21.
    vec3 F_avg = fresnel + (vec3(1.0) - fresnel) * rcp(21.0);

    return f_ms * F_avg * NoL;
}

#endif // INCLUDE_LIGHTING_BSDF
