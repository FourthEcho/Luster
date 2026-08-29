#if !defined INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
#define INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

// H-Basis sky ambient lighting.
//
// Replaces the previous IBL pipeline with a compact 6-coefficient H-Basis
// projection of the live sky map. The sky radiance field is projected once
// per frame in the deferred vertex shader (uniform-sphere sampling) into
// six RGB coefficients. Each fragment then reconstructs the cosine-weighted
// hemisphere irradiance around its bent normal in closed form.
//
// The bent normal is the key advantage over a plain-normal evaluation: in
// occluded areas the bent normal already points away from blockers, so
// evaluating the basis there picks up the correct "average visible sky"
// direction rather than the geometric normal which may stare at a wall.
//
// The bent normal provides the directional response directly. AO is used only
// as visibility weighting by the caller; there is no separate user-facing
// cone-narrowing control.
//
// The H-Basis is independently authored from the public polynomial
// reformulation (Habel et al., "Efficient Irradiance Normal Mapping",
// 2008). It is a 6-element subset of the second-order real spherical
// harmonics with the cross terms (xy, xz, yz) dropped, leaving only the
// rotation-symmetric polynomial lobes:
//
//   H_0(d) = 1
//   H_1(d) = d.x        H_2(d) = d.y        H_3(d) = d.z
//   H_4(d) = (3 * d.y^2 - 1) / 2
//   H_5(d) = (d.x^2 - d.z^2) / 2
//
// with y as the world-up axis. Cosine-weighted hemisphere irradiance
// around a unit normal n is reconstructed in closed form as:
//
//   E(n) = pi * h_0
//        + (pi / 2) * (h_1 * n.x + h_2 * n.y + h_3 * n.z)
//        + (pi / 8) * h_4 * (3 * n.y^2 - 1)
//        + (pi / 8) * h_5 * (n.x^2 - n.z^2)
//
// The pi prefactors are the closed-form integrals of each polynomial lobe
// against (d . n) over the upper hemisphere around n:
//
//   integral_hemisphere(n) (d . n) d_omega                          = pi
//   integral_hemisphere(n) d_i (d . n) d_omega  (i in {x, y, z})     = (pi / 2) * n_i
//   integral_hemisphere(n) (3 * d_y^2 - 1) (d . n) d_omega           = (pi / 4) * (3 * n_y^2 - 1)
//   integral_hemisphere(n) (d_x^2 - d_z^2) (d . n) d_omega           = (pi / 4) * (n_x^2 - n_z^2)
//
// This makes both the projection (a simple weighted sum) and the
// evaluation (a polynomial in n) independent of any external
// precomputation, so the system stays in lock-step with the dynamic sky
// map without needing an offline cubemap prefilter or per-fragment
// hemisphere sampling.

#include "/include/surface/material.glsl"
#include "/include/sky/projection.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

// Number of sky samples used by the per-frame projection. 512 keeps the
// vertex shader projection cheap (only 3 vertices run it per frame) while
// being dense enough to suppress per-frame variance once temporal
// accumulation is applied via the per-frame jitter.
#ifndef H_BASIS_SKY_SAMPLES
  #define H_BASIS_SKY_SAMPLES SH_SKYLIGHT_QUALITY
#endif

// ---------------------------------------------------------------------------
//   Projection
// ---------------------------------------------------------------------------

// Projects the live sky map into 6 RGB H-Basis coefficients. Intended to
// be called once per frame from a fullscreen-triangle vertex shader; the
// returned array is `flat`-qualified to the fragment stage by the caller.
//
// Sampling is a low-discrepancy spherical sequence (Hammersley-style with a
// golden-ratio offset) plus a per-frame jitter so that residual variance
// averages out over time when temporal reprojection is enabled.
void project_sky_h_basis(out vec3 h_out[6]) {
    for (int i = 0; i < 6; ++i) h_out[i] = vec3(0.0);

    const int N = H_BASIS_SKY_SAMPLES;

    // Per-frame jitter (Halton-style 1D rotation + hashed y offset). The
    // jitter is small enough to never bias the projection but large enough
    // to decorrelate samples across frames so temporal accumulation cleans
    // up residual variance.
    vec2 jitter = vec2(
        r1(frameCounter, 0.5),
        hash1(vec3(float(frameCounter & 31), 0.25, 0.75))
    );

    for (int i = 0; i < N; ++i) {
        // Low-discrepancy spherical sample via Hammersley sequence with
        // per-frame jitter.
        vec2 u = vec2(
            fract((float(i) + 0.5) / float(N) + jitter.x),
            fract(float(i) * (1.0 / phi1) + jitter.y)
        );

        // Uniform sphere mapping: u.x = cos(theta) uniform on [-1, 1],
        // u.y = azimuthal angle uniform on [0, 1). This gives a uniform
        // sphere distribution (PDF = 1 / (4 pi)) so the Monte-Carlo
        // estimator is simply the sample average times the sphere area.
        float phi = tau * u.y;
        float cos_theta = 2.0 * u.x - 1.0;
        float sin_theta = sqrt(max(1.0 - sqr(cos_theta), 0.0));

        vec3 d = vec3(
            sin_theta * cos(phi),
            cos_theta,
            sin_theta * sin(phi)
        );

        // Plain bilinear sample is plenty here: we are averaging
        // hundreds of directions into 6 coefficients, and the implicit-bias
        // texture() overload bicubic_filter relies on isn't available in
        // vertex shaders anyway.
        vec3 radiance = max0(texture(colortex4, project_sky(d)).rgb);

        h_out[0] += radiance;
        h_out[1] += radiance * d.x;
        h_out[2] += radiance * d.y;
        h_out[3] += radiance * d.z;
        h_out[4] += radiance * (3.0 * d.y * d.y - 1.0) * 0.5;
        h_out[5] += radiance * (d.x * d.x - d.z * d.z) * 0.5;
    }

    // Monte-Carlo: h_i = (1 / N) * sum. The 4 pi sphere-area factor is
    // folded into the evaluation's pi prefactors so the projection stays
    // as a plain sample average.
    float inv_n = 1.0 / float(N);
    for (int i = 0; i < 6; ++i) h_out[i] *= inv_n;
}

// ---------------------------------------------------------------------------
//   Evaluation
// ---------------------------------------------------------------------------

// Reconstructs the cosine-weighted hemisphere irradiance around `normal`
// from the projected H-Basis coefficients. Closed-form polynomial
// evaluation; no extra texture fetches per fragment.
vec3 evaluate_h_basis_irradiance(vec3 h_in[6], vec3 normal) {
    vec3 n = normalize(normal);

    // Constant lobe.
    vec3 result = h_in[0] * pi;

    // Linear lobes (d_x, d_y, d_z).
    result += (pi * 0.5) * (h_in[1] * n.x + h_in[2] * n.y + h_in[3] * n.z);

    // Quadratic y-dominant lobe (3 y^2 - 1) / 2 with the matching
    // cosine-weighted hemisphere integral (pi / 4) * (3 n_y^2 - 1).
    // The factor 0.5 from H_4 is folded with the (pi / 4) into (pi / 8).
    result += (pi * 0.125) * h_in[4] * (3.0 * n.y * n.y - 1.0);

    // Quadratic anisotropic lobe (d_x^2 - d_z^2) / 2 with the matching
    // (pi / 4) * (n_x^2 - n_z^2) cosine-weighted integral.
    result += (pi * 0.125) * h_in[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

// ---------------------------------------------------------------------------
//   Material-aware wrapper
// ---------------------------------------------------------------------------

// Final sky-ambient contribution for a deferred fragment. Mirrors the
// material wrapping the old IBL diffuse path used (kd * albedo for
// dielectrics, no contribution for metals) so existing tuning continues
// to apply.
//
// `ao`             : ambient occlusion factor in [0, 1]
// `skylight`       : per-pixel skylight visibility (typically
//                    `clamp01(light_levels.y)`)
// `intensity`      : user-facing SH_SKYLIGHT_INTENSITY brightness slider
vec3 get_h_basis_skylight(
    Material material,
    vec3 normal,
    vec3 bent_normal,
    float ao,
    float skylight,
    float intensity,
    vec3 h_in[6]
) {
#ifndef SH_SKYLIGHT
    return vec3(0.0);
#else
    // Always evaluate against the bent normal so the compact H-Basis
    // representation follows the actual visible-sky direction. AO remains
    // a visibility factor below rather than changing the cone shape.
    vec3 effective_normal = normalize(mix(normal, bent_normal, clamp01(ao)));

    vec3 irradiance = evaluate_h_basis_irradiance(h_in, effective_normal);

    // The renderer already has a baseline baked skylight contribution in
    // get_sky_lighting(). Only add the directional variation from the live
    // sky map here; adding the full irradiance would double-count uniform
    // sky illumination and wash the scene out.
    vec3 baseline = h_in[0] * pi;

    // Keep a small portion of the isotropic sky energy so the feature remains
    // visibly contributive, while preventing the full sky term from being
    // stacked on top of the renderer's existing baked skylight. The remaining
    // directional component still responds to the actual sky distribution.
    irradiance = max0(irradiance - baseline * 0.80)
        * skylight
        * intensity;

    // Wrap with the material's diffuse response: dielectrics use the
    // (1 - F0) albedo-modulated Lambertian factor, metals contribute
    // nothing to the diffuse ambient (their F0 is already handled by the
    // specular reflection path).
    vec3 kd = (vec3(1.0) - material.f0) * float(!material.is_metal);
    return irradiance * material.albedo * kd;
#endif
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
