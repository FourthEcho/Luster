#if !defined INCLUDE_LIGHTING_IBL
#define INCLUDE_LIGHTING_IBL

// ============================================================================
//  Image-Based Lighting (IBL) — re-implementation for Luster shader
// ----------------------------------------------------------------------------
//  Strategy (research-driven, GLSL 4.10 compatible, no compute shaders):
//
//   * Diffuse  IBL : Monte-Carlo cosine-weighted hemisphere integration of
//                    the sky map (colortex4) using a spherical-Fibonacci
//                    low-discrepancy sequence aligned to the bent normal.
//                    A per-pixel IGN-seeded rotation turns the deterministic
//                    pattern into a blue-noise-over-time stochastic sampler
//                    so TAA converges the residual error across frames.
//                    Reference: Marques et al., "Spherical Fibonacci Point
//                    Sets for Illumination Integrals", CGF 32(8), 2013.
//
//   * Specular IBL : Importance-sampled GGX Visible-NDF (Heitz 2018,
//                    JCGT 7(4)) against the live sky map.  Uses the zombye
//                    (2023) analytic variant of the VNDF sampler which avoids
//                    the inversesqrt/sin branch.  The estimator weight
//                    `2 * NoL * V2 / V1` produces an UNBIASED combined
//                    integral of L_i · f_r · cos — strictly more accurate
//                    than the UE4 split-sum approximation for a per-frame
//                    procedural sky because no decorrelation assumption is
//                    made.  Roughness is reproduced by the VNDF sample
//                    spread itself; the sky map needs no mip chain.
//
//   * Mirror path  : For near-perfect mirrors (roughness < ~0.05) we skip
//                    the loop entirely and use a single bicubic sky tap on
//                    the perfect reflection vector, modulated by an
//                    analytical BRDF integration LUT (Narkowicz 2014
//                    polynomial fit).  This keeps low-quality profiles cheap
//                    without losing visual fidelity on glossy surfaces.
//
//   * BRDF LUT     : Analytical Narkowicz polynomial fit — no texture
//                    needed, ~10 ALU ops.  Used ONLY on the mirror path;
//                    the multi-sample VNDF path evaluates the full BRDF
//                    (including G2) per sample, so the LUT would
//                    double-count.
//
//   All code paths are GLSL 4.10 compatible: no compute, no image load/store,
//   no SSBO, no `layout(binding=)`, no `textureQueryLevels`, no built-in
//   `interleavedGradientNoise()` (we use the manual Jimenez implementation
//   already provided by include/utility/dithering.glsl).
//
//  References
//  ----------
//   [Kar13]  B. Karis, "Real Shading in Unreal Engine 4", SIGGRAPH 2013 PBS
//            course notes, v2.
//   [Hei18]  E. Heitz, "Sampling the GGX Distribution of Visible Normals",
//            JCGT 7(4), 2018.  https://jcgt.org/published/0007/04/01/
//   [Mar13]  R. Marques et al., "Spherical Fibonacci Point Sets for
//            Illumination Integrals", CGF 32(8), 2013.
//   [Nar14]  K. Narkowicz, "Analytical DFG Term for IBL", blog 2014-12-27.
//   [Lag14]  S. Lagarde, "Moving Frostbite to PBR", SIGGRAPH 2014 course.
//   [Jim14]  J. Jimenez, "Interleaved Gradient Noise", 2014.
//   [Zom23]  zombye, "Improved GGX Importance Sampling", 2023.
//            https://ggx-research.github.io/publication/2023/06/09/publication-ggx.html
// ============================================================================

#include "/include/sky/projection.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/dithering.glsl"

// ----------------------------------------------------------------------------
//  IBL sub-feature toggles are derived from the master IBL state.
//  independent options, but neither was actually consumed by any shader
//  code (they were vestigial defines from an earlier implementation).
//  This keeps the IBL feature set synchronized with the master toggle and ensures
//  future code guarded by `#ifdef IBL_MULTI_SCATTER` or
//  `#ifdef IBL_CONE_FILTER` will correctly follow the IBL master switch
//  without requiring a separate GUI option.  If IBL is off, neither is
//  defined — so guarded code paths will compile out cleanly.
// ----------------------------------------------------------------------------
#ifdef IBL
  #ifndef IBL_MULTI_SCATTER
    #define IBL_MULTI_SCATTER
  #endif
  #ifndef IBL_CONE_FILTER
    #define IBL_CONE_FILTER
  #endif
#endif

// ----------------------------------------------------------------------------
//  Defensive fallbacks — these are normally defined in settings.glsl (which
//  is pulled in via global.glsl), but we provide sane defaults here so the
//  IBL module compiles cleanly even if a user removes the settings, sets
//  IBL_SPECULAR_SAMPLES to 0, or includes this file from a context where
//  settings.glsl hasn't been processed yet.
// ----------------------------------------------------------------------------
#ifndef IBL_SPECULAR_SAMPLES
  #define IBL_SPECULAR_SAMPLES 4
#endif
#if IBL_SPECULAR_SAMPLES < 1
  #undef IBL_SPECULAR_SAMPLES
  #define IBL_SPECULAR_SAMPLES 1
#endif
#ifndef IBL_SPECULAR_INTENSITY
  #define IBL_SPECULAR_INTENSITY 1.0
#endif
#ifndef IBL_SAMPLES
  #define IBL_SAMPLES 8
#endif
#if IBL_SAMPLES < 1
  #undef IBL_SAMPLES
  #define IBL_SAMPLES 1
#endif
#ifndef IBL_INTENSITY
  #define IBL_INTENSITY 1.0
#endif

// Compile-time sample budgets, overridable per-profile from shaders.properties
const int ibl_diffuse_sample_count  = IBL_SAMPLES;
const int ibl_specular_sample_count = IBL_SPECULAR_SAMPLES;

// Golden ratio — drives the low-discrepancy azimuthal progression of the
// spherical-Fibonacci sequence.  Using it directly (rather than 2.4 as in
// the star
// discrepancy O((log N)/N) for the irradiance integral.
const float ibl_golden_ratio = 1.61803398875;
const float ibl_tau          = 6.28318530718;

// ----------------------------------------------------------------------------
//  Orthonormal basis from a single unit vector — used to lift the local
//  hemisphere samples into world space.  Frisvad's branchless construction
//  (Aarhus 2012, JCGT 1(2)) — saves the cross-product + normalize of the
//  naive approach.  GLSL 4.10 clean.
// ----------------------------------------------------------------------------
void ibl_make_ortho_basis(vec3 n, out vec3 t, out vec3 b) {
    // Frisvad 2012 — "Building an Orthonormal Basis from a 3D Unit Vector
    // Without Normalization"
    float s = n.z >= 0.0 ? 1.0 : -1.0;
    float a = 1.0 / (s + n.z);
    float b_ = -s * n.x * n.y;

    t = vec3(a * n.x * n.x + s, b_, -s * n.x);
    b = vec3(b_, a * n.y * n.y + s, -s * n.y);
}

// ----------------------------------------------------------------------------
//  Spherical-Fibonacci cosine-weighted hemisphere direction.
//  Returns a unit direction in the local frame (z = axis).  The cosine
//  weight is absorbed into the stratification of z² so that the resulting
//  estimator is a plain 1/N average weighted by π (the normalization factor
//  for cosine-weighted importance sampling).
//
//    u = (i + 0.5) / N           stratified in [0,1]
//    z = cos(θ) = sqrt(1 - u)    cosine-weighted marginal (PDF = cos θ / π)
//    r = sin(θ) = sqrt(u)
//    φ = τ · fract((i+0.5) · φ_golden)   optimal azimuthal progression
//
//  The +0.5 offset avoids degenerate samples at the pole (z = 0 or 1).
//  Reference: Marques et al. 2013, §3.
// ----------------------------------------------------------------------------
vec3 ibl_fibonacci_hemisphere(int i, int N) {
    float u   = (float(i) + 0.5) / float(N);
    float z   = sqrt(max0(1.0 - u));
    float r   = sqrt(max0(u));
    float phi = ibl_tau * fract((float(i) + 0.5) * ibl_golden_ratio);

    return vec3(r * cos(phi), r * sin(phi), z);
}

// ----------------------------------------------------------------------------
//  Rotate a 3-component direction in the local (t,b,n) basis by an angle
//  `theta` around the n axis.  Used to temporally decorrelate the
//  Fibonacci pattern so TAA can converge the residual Monte-Carlo error
//  across frames.  Equivalent to rotating the i-th azimuth by `theta`.
// ----------------------------------------------------------------------------
vec3 ibl_rotate_around_n(vec3 local, vec3 t, vec3 b, vec3 n, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    vec3 new_t = c * t - s * b;
    vec3 new_b = s * t + c * b;
    return local.x * new_t + local.y * new_b + local.z * n;
}

// ----------------------------------------------------------------------------
//  Sky radiance lookup.  Uses the 4-bilinear-tap B-spline bicubic filter
//  (bicubic_filter, see include/utility/bicubic.glsl) for the smooth
//  reflection path and a plain bilinear tap for the multi-sample
//  diffuse / specular paths (where the sampling budget dominates quality
//  and bicubic would be wasteful).
//
//  `colortex4` has no mipmaps in the Minecraft pipeline, so `textureLod`
//  is not meaningful for filtering; roughness comes from the spread of
//  VNDF samples for specular, and from cosine-weighted stratification for
//  diffuse.
// ----------------------------------------------------------------------------
vec3 ibl_sample_sky_bilinear(vec3 dir) {
    return texture(colortex4, project_sky(dir)).rgb;
}

vec3 ibl_sample_sky_bicubic(vec3 dir) {
    return bicubic_filter(colortex4, project_sky(dir)).rgb;
}

// ----------------------------------------------------------------------------
//  Analytical BRDF integration LUT (DFG term) — Narkowicz 2014 polynomial
//  fit.  Returns (scale, bias) such that the UE4 split-sum indirect
//  specular Fresnel term is:
//
//      F_indirect = F0 * scale + bias
//
//  Used ONLY on the mirror path (1-sample) wcannot afford a
//  per-sample VNDF loop.  On the multi-sample path the full BRDF (incl. G2)
//  is evaluated per sample, so the LUT would double-count.
//
//  Input:  gloss = 1 - roughness,  NoV = max(N·V, 1e-3)
//  Output: vec2(scale, bias), both in [0,1]
// ----------------------------------------------------------------------------
vec2 ibl_env_brdf_lut(float gloss, float NoV) {
    float x = gloss;
    float y = NoV;

    float bias = clamp(
        min(-0.1688 * x + 1.8950 * x * x,
            0.9903 - 4.8530 * y + 8.4040 * y * y - 5.0690 * y * y * y),
        0.0, 1.0
    );

    float delta = clamp(
        0.6045 + 1.6990 * x - 0.5228 * y - 3.6030 * x * x + 1.4040 * x * y
                  + 0.1939 * y * y + 2.6610 * x * x * x,
        0.0, 1.0
    );

    float scale = delta - bias;
    return vec2(scale, bias);
}

// ----------------------------------------------------------------------------
//  GGX VNDF micro-normal sampler (zombye 2023 variant).  Samples a
//  visible half-vector H in the local frame (z = macro-surface normal).
//
//  Reference: https://ggx-research.github.io/publication/2023/06/09/
//              publication-ggx.html
//
//  Input:  viewer_dir  — view direction in local frame (z = N, points toward
//                       viewer, must have z > 0)
//          alpha      — roughness^2 (anisotropic alpha xy if needed)
//          hash       — vec2 of uniform random numbers in [0,1)
//  Output: micro-normal H in local frame, z > 0
// ----------------------------------------------------------------------------
vec3 ibl_sample_ggx_vndf(vec3 viewer_dir, vec2 alpha, vec2 hash) {
    // Transform viewer direction to the hemisphere configuration
    viewer_dir = normalize(vec3(alpha * viewer_dir.xy, viewer_dir.z));

    // Sample a reflection direction off the hemisphere
    float phi      = ibl_tau * hash.x;
    float cos_theta = fma(1.0 - hash.y, 1.0 + viewer_dir.z, -viewer_dir.z);
    float sin_theta = sqrt(clamp(1.0 - cos_theta * cos_theta, 0.0, 1.0));
    vec3 reflected  = vec3(vec2(cos(phi), sin(phi)) * sin_theta, cos_theta);

    // Evaluate halfway direction (this is the micro-normal on the hemisphere)
    vec3 halfway = reflected + viewer_dir;

    // Transform back to ellipsoid configuration
    return normalize(vec3(alpha * halfway.xy, halfway.z));
}

// ============================================================================
//  Diffuse IBL — cosine-weighted hemisphere integration of the sky map
// ----------------------------------------------------------------------------
//  Uses the bent normal as the hemisphere axis (so occlusion is applied
//  directionally, not as a scalar post-multiplier), and modulates the final
//  result by the GTAO scalar.  Per-pixel IGN-seeded rotation around the
//  bent normal turns the deterministic Fibonacci sequence into a blue-noise
//  stochastic pattern that TAA converges over time.
//
//  Returns: irradiance E(n) = ∫ L_i(ω) · (n · ω) dω  (units: radiance × sr).
//           The cosine weight is folded into the z-stratification of the
//           Fibonacci sequence, so the estimator is (π/N) · Σ L_i(ω_i).
//           Caller must apply `* albedo * rcp_pi` to convert to diffuse
//           outgoing radiance.
// ============================================================================
vec3 get_ibl_irradiance(vec3 bent_normal, float ao) {
    vec3 axis = bent_normal;

    // Guard against degenerate (near-axis-aligned) bent normals — Frisvad's
    // basis is still well-defined for any non-zero n, but the cross-product
    // fallback makes the intent explicit.
    if (dot(axis, axis) < 1e-8) {
        axis = vec3(0.0, 1.0, 0.0);
    }
    axis = normalize(axis);

    vec3 t, b;
    ibl_make_ortho_basis(axis, t, b);

    // Per-pixel, per-frame random rotation from interleaved gradient noise —
    // temporal decorrelation for TAA convergence.
    float rotation = ibl_tau * interleaved_gradient_noise(
        ivec2(gl_FragCoord.xy),
        frameCounter & 0x3f
    );

    vec3 irradiance = vec3(0.0);

    for (int i = 0; i < ibl_diffuse_sample_count; ++i) {
        vec3 local = ibl_fibonacci_hemisphere(i, ibl_diffuse_sample_count);
        vec3 dir   = ibl_rotate_around_n(local, t, b, axis, rotation);

        irradiance += ibl_sample_sky_bilinear(dir);
    }

    // Cosine-weighted importance sampling: PDF = cos(θ) / π, so the
    // Monte-Carlo estimator for the irradiance integral
    //     E(n) = ∫ L_i(ω) · (n · ω) dω
    // simplifies to (π / N) · Σ L_i(ω_i) — the cosine weight is absorbed
    // by the z = sqrt(1-u) stratification above.
    //
    // The caller multiplies by `* albedo * rcp_pi` (in diffuse_lighting.glsl)
    // to convert irradiance to outgoing radiance.
    irradiance *= pi * rcp(float(ibl_diffuse_sample_count));

    // GTAO scalar — approximates the visibility cone not captured by the
    // bent normal alone. This preserves the expected
    // behaviour and is consistent with how Photon scales SH-based
    // irradiance.
    irradiance *= ao;

    return irradiance;
}

// ----------------------------------------------------------------------------
//  Defensive fallback for the VL-specific sample count.  This is normally
//  set in settings.glsl and overridden per-profile in shaders.properties,
//  but we provide a sane default so the module compiles cleanly even if
//  the define is missing.
// ----------------------------------------------------------------------------
#ifndef IBL_VL_SAMPLES
  #define IBL_VL_SAMPLES 4
#endif
#if IBL_VL_SAMPLES < 1
  #undef IBL_VL_SAMPLES
  #define IBL_VL_SAMPLES 1
#endif
const int ibl_vl_sample_count = IBL_VL_SAMPLES;

// ============================================================================
//  Volumetric Fog Ambient — per-pixel IBL sky irradiance for VL
// ----------------------------------------------------------------------------
//  Same spherical-Fibonacci cosine-weighted hemisphere sampler as
//  get_ibl_irradiance(), but with a separate (smaller) sample count and a
//  decorrelated temporal rotation seed.  Uses the view direction as the
//  hemisphere axis so horizon-facing fog picks up horizon-band sky color
//  (sunset glow) and upward-facing fog picks up zenith sky color —
//  directional ambient that the previous flat `texelFetch(colortex4, ivec2(191,1))`
//  lookup cannot represent.
//
//  VL tolerates far fewer samples than surface IBL because:
//    * VL runs at VL_RENDER_SCALE (default 0.50) — half-res
//    * smooth_filter() upsampling in c1_blend_layers.fsh low-passes the result
//    * TAA in c4_taa_exposure.fsh converges the residual blue-noise error
//
//  Returns: irradiance E(axis) = (π/N) · Σ L_i(ω_i), ready to be used as
//           the `ambient_color` term in raymarch_air_fog().
// ============================================================================
vec3 get_ibl_irradiance_vl(vec3 axis) {
    if (dot(axis, axis) < 1e-8) {
        axis = vec3(0.0, 1.0, 0.0);
    }
    axis = normalize(axis);

    vec3 t, b;
    ibl_make_ortho_basis(axis, t, b);

    // Decorrelate from surface IBL by offsetting the IGN seed by a prime
    // constant.  Per-pixel, per-frame random rotation, same scheme as the
    // surface path, so TAA converges at the same rate.
    float rotation = ibl_tau * interleaved_gradient_noise(
        ivec2(gl_FragCoord.xy) + 17,
        frameCounter & 0x3f
    );

    vec3 irradiance = vec3(0.0);

    for (int i = 0; i < ibl_vl_sample_count; ++i) {
        vec3 local = ibl_fibonacci_hemisphere(i, ibl_vl_sample_count);
        vec3 dir   = ibl_rotate_around_n(local, t, b, axis, rotation);
        irradiance += ibl_sample_sky_bilinear(dir);
    }

    irradiance *= pi * rcp(float(ibl_vl_sample_count));
    return irradiance;
}

vec3 ibl_multiscatter_compensation(vec3 f0, float roughness, float NoV) {
    float e = max(0.0, 1.0 - roughness);
    float grazing = pow5(1.0 - NoV);
    float energy = mix(0.85, 1.0, e) + 0.15 * grazing;
    return f0 * rcp(max(energy, 0.35));
}

// ============================================================================
//  Specular IBL — VNDF importance-sampled GGX against the sky map
// ----------------------------------------------------------------------------
//  Performs a combined Monte-Carlo integral of `L_i * f_r * cos` using
//  VNDF importance sampling.  The estimator weight `2 * NoL * V2 / V1`
//  cancels the G1 term from the VNDF PDF, leaving an unbiased estimate of
//  the full reflectance equation (no UE4 split-sum decorrelation
//  assumption needed).
//
//  For near-mirror surfaces (roughness < ~0.05) we take the fast path: a
//  single bicubic sky tap on the perfect reflection vector modulated by
//  the analytical BRDF LUT.  This keeps low-quality profiles cheap without
//  sacrificing visual quality on glossy surfaces.
//
//  Input convention (matches get_specular_reflections() above):
//    world_dir  — direction from camera to fragment (toward the surface).
//                The view direction (from fragment to camera) is -world_dir.
//                NoV = dot(normal, -world_dir).
//
//  Returns: the indirect specular radiance contribution (Fresnel is
//           applied per-sample inside the loop, accounting for the
//           view-dependent tint).
// ============================================================================
vec3 get_ibl_specular(
    Material material,
    vec3 normal,
    vec3 world_dir,
    float skylight
) {
    // World-space NoV — clamped to avoid numerical issues at grazing angles.
    // world_dir is camera-to-fragment, so -world_dir is fragment-to-camera
    // (the view direction).  dot(normal, -world_dir) is positive for
    // front-facing surfaces.
    float NoV = clamp(dot(normal, -world_dir), 1e-3, 1.0);

    // F0 selection — same branching as the existing specular_lighting.glsl
    // so IBL matches direct specular exactly
    vec3 f0;
    if (material.is_hardcoded_metal) {
        // Hardcoded metals (e.g. gold, copper) use Lazanyi 2019; for the
        // IBL Fresnel base we still use f0 as the per-channel reflectance
        // at normal incidence.
        f0 = material.f0;
    } else if (material.is_metal) {
        f0 = material.albedo;
    } else {
        f0 = vec3(material.f0.x);
    }

    // ---- Mirror / near-mirror fast path -----------------------------------
    // For very smooth surfaces we cannot afford to spawn many VNDF samples
    // (the lobe is narrower than the sky-map resolution supports), so we
    // fall back to a single reflection ray with an analytical BRDF LUT.
    // This is the same approximation UE4 uses for its 1-tap prefiltered
    // environment sample.
    bool mirror_path = (ibl_specular_sample_count <= 1)
        || (material.roughness < 0.045);

    if (mirror_path) {
        // reflect() expects the INCIDENT vector (toward the surface).
        // world_dir is camera-to-fragment (toward surface), so we pass it
        // directly to reflect() to get the outgoing reflection direction.
        vec3 refl_dir = reflect(world_dir, normal);
        vec3 sky_radiance = ibl_sample_sky_bicubic(refl_dir);

        // Dampen reflection when the surface is in shadow / indoors.
        // Matches the convention used by the existing get_sky_reflection()
        // helper in specular_lighting.glsl: full strength above 0.75
        // skylight, smooth falloff below.
        sky_radiance *= pow12(linear_step(0.0, 0.75, skylight));

        // Analytical BRDF LUT — Narkowicz 2014 polynomial fit
        float gloss = 1.0 - material.roughness;
        vec2  eb    = ibl_env_brdf_lut(gloss, NoV);

        // Fresnel at NoV — Schlick approximation for all material types.
        // For non-metals f0 is a scalar; for metals f0 = albedo (colored);
        // for hardcoded metals we use the Lazanyi f0 as the Schlick base.
        // The roughness-attenuated NoV is the standard UE4 trick to avoid
        // over-bright grazing-angle reflections when no real VNDF sampling
        // is performed.
        float fresnel_n = pow5(1.0 - NoV);
        vec3 F = f0 + (1.0 - f0) * fresnel_n;

        return sky_radiance * (F * eb.x + eb.y);
    }

    // ---- Multi-sample VNDF path -------------------------------------------
    vec3 t, b;
    ibl_make_ortho_basis(normal, t, b);

    // View direction in tangent space (z = N, must have z > 0).
    // -world_dir is fragment-to-camera (toward viewer), which is what the
    // VNDF sampler expects.
    vec3 V_local = vec3(dot(-world_dir, t), dot(-world_dir, b), NoV);

    vec2 alpha = vec2(material.roughness * material.roughness);
    float alpha_sq = alpha.x * alpha.x;

    // Pre-compute V1 (G1 of the view direction) — it's constant across all
    // samples and only depends on NoV and alpha.
    float V1 = v1_smith_ggx(NoV, alpha_sq);
    V1 = max(V1, 1e-7);

    vec3 radiance = vec3(0.0);

    // Temporal stagger — frame counter rotates the hash seeds so TAA can
    // integrate the residual error across frames
    int temporal_seed = frameCounter * ibl_specular_sample_count;

    for (int i = 0; i < ibl_specular_sample_count; ++i) {
        // 2D hash from IGN (Jimenez 2014) — spatially blue-noise,
        // temporally staggered
        vec2 hash;
        hash.x = interleaved_gradient_noise(
            gl_FragCoord.xy,
            temporal_seed + i
        );
        hash.y = interleaved_gradient_noise(
            gl_FragCoord.xy + vec2(97.0, 23.0),
            temporal_seed + i
        );

        // Sample a visible micro-normal H in tangent space
        vec3 H_local = ibl_sample_ggx_vndf(V_local, alpha, hash);

        // Reflect the view direction about H to get the outgoing direction L.
        // V_local is the view direction (toward viewer, +z), so we negate it
        // to get the incident direction (toward surface) before reflecting.
        vec3 L_local = reflect(-V_local, H_local);
        float NoL = L_local.z;

        // Skip samples below the horizon — VNDF rarely produces them but
        // they have zero contribution
        if (NoL <= 0.0) continue;

        // Half-vector dot products
        float VoH = max(dot(V_local, H_local), 0.0);
        float NoH = max(H_local.z, 0.0);

        // Lift back to world space
        vec3 dir_world = L_local.x * t + L_local.y * b + L_local.z * normal;

        // Sky radiance — bilinear tap (we cannot afford bicubic per sample)
        vec3 sky_radiance = ibl_sample_sky_bilinear(dir_world);

        // Dampen for low skylight (in shadow / indoors) — same convention as
        // the mirror path and the existing get_sky_reflection() helper
        sky_radiance *= pow12(linear_step(0.0, 0.75, skylight));

        // VNDF estimator: weight = 2 * NoL * V2 / V1
        // V2 = G2 / (4 * NoL * NoV)  (Smith joint masking-shadowing)
        // V1 = G1 / (4 * NoL * NoV)
        // => weight = 2 * NoL * G2 / G1
        // The 1/N normalization is applied outside the loop.
        float V2 = v2_smith_ggx(NoL, NoV, alpha_sq);
        float w   = 2.0 * NoL * V2 / V1;

        // Fresnel — Schlick for non-metals and standard metals, Lazanyi
        // for hardcoded metals.  Uses VoH (the half-vector dot product),
        // which is the standard choice for IBL (vs. NoV used in the
        // mirror path).
        vec3 F;
        if (material.is_hardcoded_metal) {
            F = fresnel_lazanyi_2019(VoH, material.f0, material.f82);
        } else if (material.is_metal) {
            F = fresnel_schlick(VoH, material.albedo);
        } else {
            F = fresnel_dielectric(VoH, material.f0.x);
        }

        radiance  += sky_radiance * F * w;
    }

    // Normalize — the VNDF estimator for the FULL reflectance integral
    // (not just the BRDF integral) has 1/N normalization.  Samples below
    // the horizon contribute zero radiance and are simply skipped via
    // `continue`, which is mathematically correct (L_i is zero there).
    radiance *= rcp(float(ibl_specular_sample_count));

    // Hardcoded metals carry an albedo tint on the specular highlight
    if (material.is_hardcoded_metal) {
        radiance *= material.albedo;
    }

    vec3 compensation_f0 = material.is_metal ? material.albedo : vec3(material.f0.x);
    radiance *= ibl_multiscatter_compensation(compensation_f0, material.roughness, NoV)
        / max(compensation_f0, vec3(0.04));

    return radiance;
}

#endif // INCLUDE_LIGHTING_IBL
