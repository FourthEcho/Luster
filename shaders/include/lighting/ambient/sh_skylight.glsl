#if !defined INCLUDE_LIGHTING_AMBIENT_SH_SKYLIGHT
#define INCLUDE_LIGHTING_AMBIENT_SH_SKYLIGHT

// Second-order spherical-harmonics sky ambient lighting (9 coefficients).
//
// Replaces the old 6-coefficient H-Basis subset with the FULL second-order
// basis including the cross terms (xy, yz, xz), so directional sky detail
// the subset blurred away survives. The live sky map is projected once per
// frame in the deferred vertex shader (uniform-sphere sampling) into nine
// RGB coefficients, passed flat to the fragment stage, and evaluated in
// closed form around the bent normal:
//
//   Y00     = 0.282095
//   Y1x/y/z = 0.488603 * (x/y/z)
//   Y20     = 0.315392 * (3y^2 - 1)
//   Y2xy/yz/xz = 1.092548 * (xy/yz/xz)
//   Y2xxzz  = 0.546274 * (x^2 - z^2)
//
// with y as the world-up axis. Cosine-weighted hemisphere irradiance is
// reconstructed with the Ramamoorthi convolution factors (A0 = pi,
// A1 = 2pi/3, A2 = pi/4). Application follows Photon: the result mixes
// with the flat up-ambient by skylight^2, then takes intensity, AO and
// the skylight falloff — the bent normal + AO carry the directional
// response, so occluded areas sample the visible sky, not the wall.

// material.glsl pulls in fragment-only uniforms (cameraPosition, ...), and only
// the Material-aware wrapper needs it, so vertex stages (which just project
// the sky) must not include it.
#if !defined vsh
#include "/include/surface/material.glsl"
#endif
#include "/include/sky/projection.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

#ifndef SH_SKYLIGHT_SAMPLES
  #define SH_SKYLIGHT_SAMPLES SH_SKYLIGHT_QUALITY
#endif

// ---------------------------------------------------------------------------
//   Projection
// ---------------------------------------------------------------------------

// Projects the live sky map into 9 RGB SH coefficients. Intended to be
// called once per frame from a fullscreen-triangle vertex shader; the
// returned array is `flat`-qualified to the fragment stage by the caller.
//
// The sampling pattern is deliberately deterministic (see the old H-Basis
// note): the coefficients are consumed immediately as flat per-frame
// lighting state, so per-frame jitter would read as flickering
// illumination. Stable locations keep it still.
void project_sky_sh(out vec3 sh[9]) {
    for (int i = 0; i < 9; ++i) sh[i] = vec3(0.0);

    const int N = SH_SKYLIGHT_SAMPLES;

    for (int i = 0; i < N; ++i) {
        // Fixed low-discrepancy spherical sequence: uniform sphere
        // distribution (PDF = 1 / (4 pi)), so the estimator is the sample
        // average times the sphere area (folded into the evaluation).
        vec2 u = vec2(
            (float(i) + 0.5) / float(N),
            fract(float(i) * (1.0 / phi1))
        );

        float phi = tau * u.y;
        float cos_theta = 2.0 * u.x - 1.0;
        float sin_theta = sqrt(max(1.0 - sqr(cos_theta), 0.0));

        vec3 d = vec3(
            sin_theta * cos(phi),
            cos_theta,
            sin_theta * sin(phi)
        );

        // Plain bilinear sample is plenty: hundreds of directions average
        // into 9 coefficients, and implicit-bias texture() is unavailable
        // in vertex shaders anyway.
        vec3 radiance = max0(texture(colortex4, project_sky(d)).rgb);

        float x = d.x;
        float y = d.y;
        float z = d.z;

        sh[0] += radiance * 0.282095;
        sh[1] += radiance * (0.488603 * x);
        sh[2] += radiance * (0.488603 * y);
        sh[3] += radiance * (0.488603 * z);
        sh[4] += radiance * (1.092548 * x * y);
        sh[5] += radiance * (1.092548 * y * z);
        sh[6] += radiance * (1.092548 * x * z);
        sh[7] += radiance * (0.315392 * (3.0 * y * y - 1.0));
        sh[8] += radiance * (0.546274 * (x * x - z * z));
    }

    // Monte-Carlo estimator with the 4 pi sphere area: c = (4 pi / N) sum.
    // (The L0 branch needs its Y00 factor like every other band; dropping
    // it while also dropping 4 pi only cancels for uniform skies.)
    float mc_scale = 4.0 * pi * rcp(float(N));
    for (int i = 0; i < 9; ++i) sh[i] *= mc_scale;
}

// ---------------------------------------------------------------------------
//   Evaluation
// ---------------------------------------------------------------------------

vec3 evaluate_sh_irradiance(vec3 sh[9], vec3 normal) {
    vec3 n = normalize(normal);

    float x = n.x;
    float y = n.y;
    float z = n.z;

    vec3 result = sh[0] * (pi * 0.282095);

    result += (2.0 * pi / 3.0) * 0.488603
        * (sh[1] * x + sh[2] * y + sh[3] * z);

    result += (pi * 0.25)
        * (0.315392 * sh[7] * (3.0 * y * y - 1.0)
           + 1.092548 * (sh[4] * x * y + sh[5] * y * z + sh[6] * x * z)
           + 0.546274 * sh[8] * (x * x - z * z));

    return max0(result);
}

// ---------------------------------------------------------------------------
//   Material-aware wrapper
// ---------------------------------------------------------------------------

#if !defined vsh
vec3 get_sh_skylight(
    Material material,
    vec3 bent_normal,
    float skylight,
    float ao,
    float intensity,
    vec3 up_ambient,
    vec3 sh[9]
) {
#ifndef SH_SKYLIGHT
    return vec3(0.0);
#else
    vec3 n = normalize_safe(bent_normal);

    vec3 irradiance = evaluate_sh_irradiance(sh, n);

    // Photon application: cross-fade flat up-ambient against the
    // directional evaluation by skylight^2, then intensity, AO and the
    // skylight falloff. No baked-base subtraction hacks: the baked base
    // yields wherever this term is active (see get_sky_lighting).
    float sky01 = clamp01(skylight);
#if defined WORLD_OVERWORLD
    float falloff = sqr(sky01); // mirrors get_skylight_falloff()
#else
    const float falloff = 1.0;
#endif
    vec3 sky = mix(up_ambient, irradiance, sqr(sky01));

    vec3 kd = (vec3(1.0) - material.f0) * float(!material.is_metal);
    return sky * intensity * ao * falloff * material.albedo * kd;
#endif
}
#endif // !vsh

// Fog ambient from the SH projection along a world-space ray direction.
// The evaluation returns true irradiance (pi x mean for uniform skies),
// while the legacy ambient_color convention this replaces is radiance
// scaled by TAU x 1.13 — so divide by pi to land in the same units and
// keep uniform skies rendering identically, with directionality added.
vec3 fog_skylight(vec3 sh[9], vec3 ray_dir) {
    vec3 dir = ray_dir * inversesqrt(max(dot(ray_dir, ray_dir), eps));
    return (tau * 1.13 / pi) * evaluate_sh_irradiance(sh, dir);
}

#endif // INCLUDE_LIGHTING_AMBIENT_SH_SKYLIGHT
