#if !defined INCLUDE_LIGHTING_IBL
#define INCLUDE_LIGHTING_IBL

// Image-Based Lighting for Photon's dynamic sky environment.
//
// The environment is generated every frame, so a traditional offline cubemap
// prefilter is not appropriate here. Instead this implementation combines:
//   * cosine-weighted diffuse integration,
//   * Heitz-style GGX VNDF importance sampling for glossy IBL,
//   * the correct VNDF Monte-Carlo estimator,
//   * roughness-aware Schlick Fresnel,
//   * GGX multiple-scattering energy compensation using the fitted E_m model.
//
// The multiple-scattering model follows Fdez-Agüera (JCGT 2019), while the
// GGX visible-normal sampling follows Heitz's VNDF formulation.

#include "/include/surface/material.glsl"
#include "/include/sky/projection.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

// -----------------------------------------------------------------------------
// Fresnel / masking helpers
// -----------------------------------------------------------------------------

vec3 ibl_fresnel_schlick(float cos_theta, vec3 F0) {
    float f = pow5(1.0 - clamp01(cos_theta));
    return F0 + (1.0 - F0) * f;
}

// UE4/Frostbite-compatible roughness-aware F90 approximation.
vec3 ibl_fresnel_schlick_roughness(float NoV, vec3 F0, float roughness) {
    vec3 F90 = max(vec3(1.0 - roughness), F0);
    float f = pow5(1.0 - clamp01(NoV));
    return F0 + (F90 - F0) * f;
}

float ibl_smith_ggx_g1(float NoV, float alpha) {
    NoV = clamp01(NoV);
    float a2 = sqr(alpha);
    float denom = NoV + sqrt(a2 + (1.0 - a2) * sqr(NoV));
    return (denom > eps) ? (2.0 * NoV / denom) : 0.0;
}

float ibl_geometry_smith(vec3 N, vec3 V, vec3 L, float roughness) {
    float alpha = max(roughness * roughness, 0.001);
    float NoV = max(dot(N, V), 0.0);
    float NoL = max(dot(N, L), 0.0);
    return ibl_smith_ggx_g1(NoV, alpha) * ibl_smith_ggx_g1(NoL, alpha);
}

// -----------------------------------------------------------------------------
// GGX visible-normal sampling (Heitz)
// -----------------------------------------------------------------------------

vec3 ibl_sample_ggx_vndf(vec3 V, float alpha, vec2 sample_uv) {
    // Stretch view vector into the GGX configuration space.
    vec3 Vh = normalize(vec3(alpha * V.x, alpha * V.y, V.z));

    float lensq = dot(Vh.xy, Vh.xy);
    vec3 T1 = lensq > eps
        ? vec3(-Vh.y, Vh.x, 0.0) * inversesqrt(lensq)
        : vec3(1.0, 0.0, 0.0);
    vec3 T2 = cross(Vh, T1);

    // Uniform disk sample with concentric/visibility warping.
    float r = sqrt(clamp01(sample_uv.x));
    float phi = tau * sample_uv.y;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);

    float s = 0.5 * (1.0 + Vh.z);
    t2 = (1.0 - s) * sqrt(max(1.0 - t1 * t1, 0.0)) + s * t2;

    vec3 Nh = T1 * t1
        + T2 * t2
        + Vh * sqrt(max(1.0 - t1 * t1 - t2 * t2, 0.0));

    // Unstretch back to tangent space.
    return normalize(vec3(alpha * Nh.x, alpha * Nh.y, max(Nh.z, 0.0)));
}

// -----------------------------------------------------------------------------
// Dynamic sky environment sampling
// -----------------------------------------------------------------------------

vec3 ibl_sample_sky_map(vec3 world_dir) {
    vec2 sky_uv = project_sky(normalize(world_dir));
    return max0(bicubic_filter(colortex4, sky_uv).rgb);
}

// Cosine-weighted hemisphere environment irradiance. The estimator is simply
// the mean environment radiance because the cosine PDF cancels the Lambertian
// BRDF's 1/pi factor.
vec3 ibl_sample_diffuse_environment(vec3 normal, int sample_count, vec2 dither) {
    int count = max(sample_count, 1);
    vec3 irradiance = vec3(0.0);

    vec3 a = abs(normal.z) < 0.999
        ? vec3(0.0, 0.0, 1.0)
        : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(a, normal));
    vec3 bitangent = cross(normal, tangent);

    for (int i = 0; i < count; ++i) {
        // Cranley-Patterson rotation keeps samples distributed over time.
        float fi = float(i);
        vec2 u = vec2(
            fract((fi + 0.5) / float(count) + dither.x + fi * 0.754877666),
            fract(fi * golden_ratio + dither.y + fi * 0.569840296)
        );

        float phi = tau * u.y;
        float cos_theta = sqrt(clamp01(u.x));
        float sin_theta = sqrt(max(1.0 - sqr(cos_theta), 0.0));

        vec3 wi = vec3(
            sin_theta * cos(phi),
            sin_theta * sin(phi),
            cos_theta
        );

        vec3 world_dir = normalize(
            tangent * wi.x + bitangent * wi.y + normal * wi.z
        );
        irradiance += ibl_sample_sky_map(world_dir);
    }

    return irradiance / float(count);
}

// -----------------------------------------------------------------------------
// GGX multiple-scattering compensation
// -----------------------------------------------------------------------------

// Directional single-scatter albedo fit from the Enterprise PBR / Kulla-Conty
// family of GGX energy-compensation approximations. The input roughness is the
// perceptual roughness used by Photon.
float ibl_ggx_single_scatter_albedo(float NoV, float roughness) {
    float r = clamp01(roughness);
    float alpha_uv = sqr(r);
    float mu = clamp01(NoV);

    float A = -0.20277
        + alpha_uv * (2.772
        + alpha_uv * (-2.6175 + 0.73343 * alpha_uv));

    float B = 3.09507
        + mu * (-9.11369
        + mu * (15.8884
        + mu * (-13.70343 + 4.51786 * mu)));

    return clamp01(1.0 - 1.4594 * alpha_uv * mu * A * B);
}

float ibl_ggx_average_albedo(float roughness) {
    float alpha_uv = sqr(clamp01(roughness));
    return clamp01(
        1.0 + alpha_uv * (-0.113
        + alpha_uv * (-1.8695
        + alpha_uv * (2.2268 - 0.83397 * alpha_uv)))
    );
}

vec3 ibl_multiple_scatter_ggx(
    vec3 F0,
    float NoV,
    float roughness,
    vec3 irradiance
) {
    float Ess = ibl_ggx_single_scatter_albedo(NoV, roughness);
    float Eavg = ibl_ggx_average_albedo(roughness);
    float Ems = max(1.0 - Ess, 0.0);

    vec3 Favg = F0 + (1.0 - F0) * (1.0 / 21.0);

    // The JCGT real-time formulation uses the single-scatter Fresnel term
    // multiplied by the directional GGX albedo, then redistributes the lost
    // energy through subsequent microfacet bounces.
    vec3 kS = ibl_fresnel_schlick_roughness(NoV, F0, roughness);
    vec3 FssEss = kS * Ess;
    vec3 Fms = FssEss * Favg
        / max(vec3(1.0) - Ems * Favg, vec3(eps));

    return Fms * Ems * irradiance;
}

// Raw diffuse environment irradiance used by indirect-lighting sky misses.
// This is deliberately separate from material IBL so the GI path can replace
// the old SH-skylight input without applying an albedo/BRDF term twice.
vec3 get_ibl_sky_irradiance(
    vec3 normal,
    vec2 dither,
    int sample_count
) {
    return ibl_sample_diffuse_environment(
        normalize(normal),
        max(sample_count, 1),
        dither
    );
}

// -----------------------------------------------------------------------------
// Diffuse IBL
// -----------------------------------------------------------------------------

vec3 get_ibl_diffuse(
    Material material,
    vec3 n,
    vec3 bent_normal,
    float skylight,
    vec2 dither,
    int sample_count
) {
#ifndef IBL
    return vec3(0.0);
#else
    vec3 normal = normalize(mix(n, bent_normal, 0.35));
    vec3 irradiance = ibl_sample_diffuse_environment(
        normal,
        sample_count,
        dither
    ) * skylight;

    vec3 kd = (vec3(1.0) - material.f0) * float(!material.is_metal);
    return irradiance * material.albedo * kd * IBL_DIFFUSE_INTENSITY;
#endif
}

// -----------------------------------------------------------------------------
// Specular IBL
// -----------------------------------------------------------------------------

vec3 get_ibl_specular(
    Material material,
    vec3 n,
    vec3 v,
    vec3 bent_normal,
    float skylight,
    vec2 dither,
    int sample_count
) {
#ifndef IBL
    return vec3(0.0);
#else
    int count = max(sample_count, 1);

    float NoV = max(dot(n, v), 0.0);
    if (NoV <= eps) return vec3(0.0);

    float roughness = clamp01(material.roughness);
    float alpha = max(sqr(roughness), 0.001);

    vec3 F_single = vec3(0.0);

    // Low-discrepancy VNDF Monte Carlo integration. The VNDF PDF cancels the
    // GGX D term, leaving the compact F*G1(L) estimator.
    for (int i = 0; i < count; ++i) {
        float fi = float(i);
        vec2 u = vec2(
            fract((fi + 0.5) / float(count) + dither.x + fi * 0.754877666),
            fract(fi * golden_ratio + dither.y + fi * 0.569840296)
        );

        mat3 tbn = get_tbn_matrix(n);
        vec3 v_local = normalize(transpose(tbn) * v);
        vec3 h_local = ibl_sample_ggx_vndf(v_local, alpha, u);
        vec3 h = normalize(tbn * h_local);
        vec3 l = reflect(-v, h);

        float NoL = max(dot(n, l), 0.0);
        float VoH = max(dot(v, h), 0.0);
        if (NoL <= eps || VoH <= eps) continue;

        vec3 F = ibl_fresnel_schlick(VoH, material.f0);
        float G1L = ibl_smith_ggx_g1(NoL, alpha);

        // Importance-sampled VNDF estimator; the 1/4 factor is folded into
        // the normalization below by accumulating the equivalent reflectance
        // ratio rather than evaluating D*G/(4 NoL NoV) directly.
        F_single += ibl_sample_sky_map(l) * F * G1L;
    }

    vec3 single = F_single / float(count) * skylight;

    // Approximate the environment irradiance used by the multi-bounce term
    // from the same bent normal that protects diffuse lighting from blocked
    // directions.
    vec3 ms_normal = normalize(mix(n, bent_normal, 0.25));
    vec3 diffuse_env = ibl_sample_diffuse_environment(
        ms_normal,
        max(sample_count / 2, 1),
        dither.yx
    ) * skylight;

    vec3 multiple = ibl_multiple_scatter_ggx(
        material.f0,
        NoV,
        roughness,
        diffuse_env
    );

    // Metals use the same energy-preserving microfacet compensation; they do
    // not contribute to the Lambertian diffuse term.
    return max0((single + multiple) * IBL_SPECULAR_INTENSITY);
#endif
}

vec3 get_image_based_lighting(
    Material material,
    vec3 n,
    vec3 v,
    vec3 bent_normal,
    float skylight,
    vec2 dither
) {
#ifdef IBL
    vec3 diffuse = get_ibl_diffuse(
        material,
        n,
        bent_normal,
        skylight,
        dither,
        IBL_DIFFUSE_SAMPLES
    );
    vec3 specular = get_ibl_specular(
        material,
        n,
        v,
        bent_normal,
        skylight,
        dither,
        IBL_SPECULAR_SAMPLES
    );
    return diffuse + specular;
#else
    return vec3(0.0);
#endif
}

#endif // INCLUDE_LIGHTING_IBL
