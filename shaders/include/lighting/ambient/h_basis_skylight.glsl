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
//        + (2 * pi / 3) * (h_1 * n.x + h_2 * n.y + h_3 * n.z)
//        + (pi / 8) * h_4 * (3 * n.y^2 - 1)
//        + (pi / 8) * h_5 * (n.x^2 - n.z^2)
//
// The pi prefactors are the closed-form integrals of each polynomial lobe
// against (d . n) over the upper hemisphere around n:
//
//   integral_hemisphere(n) (d . n) d_omega                          = pi
//   integral_hemisphere(n) d_i (d . n) d_omega  (i in {x, y, z})     = (2 * pi / 3) * n_i
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
// The sampling pattern is deliberately deterministic. The projection is
// recomputed every frame from the live sky map, but changing the sample
// coordinates with frameCounter would inject Monte-Carlo noise directly into
// the lighting result because there is no temporal accumulation of these
// coefficients before they reach the deferred fragment shader. Stable sample
// locations therefore prevent the SH term from making shadows and ambient
// lighting flash from frame to frame.
void project_sky_h_basis(out vec3 h_out[6]) {
    for (int i = 0; i < 6; ++i) h_out[i] = vec3(0.0);

    const int N = H_BASIS_SKY_SAMPLES;

    for (int i = 0; i < N; ++i) {
        // Fixed low-discrepancy spherical sequence. Do not add per-frame
        // jitter here: the coefficients are consumed immediately as a
        // flat per-frame lighting state, so temporal noise would become
        // visible as flickering illumination/shadows.
        vec2 u = vec2(
            (float(i) + 0.5) / float(N),
            fract(float(i) * (1.0 / phi1))
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

vec3 evaluate_h_basis_irradiance(vec3 h_in[6], vec3 normal) {
    vec3 n = normalize(normal);

    vec3 result = h_in[0] * pi;

    result += (2.0 * pi / 3.0) * (h_in[1] * n.x + h_in[2] * n.y + h_in[3] * n.z);

    result += (pi * 0.125) * h_in[4] * (3.0 * n.y * n.y - 1.0);

    result += (pi * 0.125) * h_in[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

// ---------------------------------------------------------------------------
//   Material-aware wrapper
// ---------------------------------------------------------------------------

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
    vec3 effective_normal = normalize(bent_normal);

    vec3 irradiance = evaluate_h_basis_irradiance(h_in, effective_normal);

    vec3 baseline = h_in[0] * pi;

    irradiance = max0(irradiance - baseline * 0.80)
        * skylight
        * intensity;

    vec3 kd = (vec3(1.0) - material.f0) * float(!material.is_metal);
    return irradiance * material.albedo * kd;
#endif
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
