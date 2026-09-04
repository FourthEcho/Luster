#if !defined INCLUDE_MISC_RAIN_PUDDLES
#define INCLUDE_MISC_RAIN_PUDDLES

#include "/include/misc/material_masks.glsl"

float get_ripple_height(vec2 coord) {
    const float ripple_frequency = 0.3;
    const float ripple_speed = 0.1;
    const vec2 ripple_dir_0 = vec2(3.0, 4.0) / 5.0;
    const vec2 ripple_dir_1 = vec2(-5.0, -12.0) / 13.0;

    float ripple_noise_1
        = texture(
              noisetex,
              coord * ripple_frequency
                  + frameTimeCounter * ripple_speed * ripple_dir_0
        )
              .y;
    float ripple_noise_2
        = texture(
              noisetex,
              coord * ripple_frequency
                  + frameTimeCounter * ripple_speed * ripple_dir_1
        )
              .y;

    return mix(ripple_noise_1, ripple_noise_2, 0.5);
}

// ---- Rain puddle mode resolution ----
//
// RAIN_PUDDLES_OFF        : no rain puddles anywhere, ever.
// RAIN_PUDDLES_RAIN       : default behaviour. Puddles form only where
//                           the biome can actually rain (gated by
//                           biome_may_rain). Deserts, snowy biomes, nether
//                           and end never see puddles.
// RAIN_PUDDLES_EVERYWHERE : during rain, puddles are consistently placed
//                           on every surface that is exposed to the sky,
//                           regardless of the local biome weather. We still
//                           exclude:
//                             - caves / indoors (no skylight)
//                             - "specific biomes" where water fundamentally
//                               cannot reach — this is encoded as
//                               biome_may_rain < 0 (sentinel for nether /
//                               end / void) and is also implicitly handled
//                               by wetness being 0 in those dimensions.
//                           In other words: EVERYWHERE means "puddles in
//                           every surface block that can see the sky while
//                           it's raining globally", not "puddles in
//                           dimensions where rain doesn't exist".
float get_puddle_weather_factor() {
#if RAIN_PUDDLES_MODE == RAIN_PUDDLES_OFF
    return 0.0;
#elif RAIN_PUDDLES_MODE == RAIN_PUDDLES_EVERYWHERE
    // In EVERYWHERE mode we do NOT scale by biome_may_rain — puddles form
    // in every overworld biome while it's raining. The cave / indoor
    // exclusion is handled by the skylight check in get_puddle_noise, and
    // the nether / end exclusion is handled by the WORLD_OVERWORLD gate
    // in deferred_shading.fsh plus the wetness < 0 sentinel check below.
    return 1.0;
#else
    // Default RAIN mode: respect per-biome "may rain" flag.
    return biome_may_rain;
#endif
}

float get_puddle_noise(vec3 world_pos, vec3 flat_normal, vec2 light_levels) {
    const float puddle_frequency = 0.025;

#if RAIN_PUDDLES_MODE == RAIN_PUDDLES_OFF
    return 0.0;
#else
    float puddle = texture(noisetex, world_pos.xz * puddle_frequency).w;

    float weather_factor = get_puddle_weather_factor();

    // wetness is the global "is it raining right now" curve, smoothed by
    // the host so puddles grow and shrink gradually as rain starts /
    // stops. In EVERYWHERE mode wetness > 0 alone is enough; in RAIN mode
    // weather_factor additionally gates per-biome.
    puddle = linear_step(0.45, 0.55, puddle) * wetness * weather_factor
        * step(0.99, flat_normal.y);

    // ---- Cave / indoor exclusion ----
    // light_levels.x is block light, light_levels.y is sky light. Puddles
    // should only form where the surface can see the sky (high sky light)
    // and where there isn't a strong artificial light source indoors.
    // This handles "water didn't reach there" for caves and overhangs.
    puddle *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    // Apply user-controlled puddle intensity slider. This is the global
    // gain that scales how prominent puddles are, regardless of mode.
    puddle *= RAIN_PUDDLES_INTENSITY;

    return puddle;
#endif
}

// Kubelka-Munk-style wet-porosity albedo darkening.
//
// When a porous surface absorbs water, the water film fills the air pockets
// between particles and dramatically increases the path length for light
// bouncing inside the surface layer. The Kubelka-Munk two-flux model gives
// a saturating-absorption formula for the effective reflectance of a thin
// absorbing layer over a substrate:
//
//   R_wet = (1 - k) * R_dry / (1 - k * R_dry)
//
// where k is the fraction of light that is absorbed per internal bounce
// (proportional to porosity). This is applied per-channel so chromatic
// darkening is preserved (wet red clay darkens differently from wet sand).
//
// Additional refinements over a plain Kappa-style scalar version:
//   - Per-channel application preserves hue shift (wet surfaces desaturate
//     slightly toward their absorption colour).
//   - k is modulated by sqrt(albedo) so already-dark surfaces (low albedo)
//     darken less in absolute terms — they have less reflectance to lose.
//   - The whole effect is weighted by wetness * porosity so it fades
//     smoothly as rain starts and stops.
vec3 apply_wet_porosity_darkening(vec3 albedo, float porosity, float wetness_factor) {
#ifndef POROSITY
    return albedo;
#else
    // Maximum absorbed fraction per internal bounce, scaled by porosity.
    // 0.7 matches Kappa's empirical coefficient; sqrt(albedo) makes the
    // effect self-limiting on already-dark surfaces.
    vec3 k = 0.7 * porosity * sqrt(albedo);

    // KM saturating-absorption: R_wet = (1-k)*R / (1 - k*R)
    vec3 wet_albedo = (1.0 - k) * albedo / max(vec3(1e-4), 1.0 - k * albedo);

    return mix(albedo, wet_albedo, wetness_factor * porosity);
#endif
}

bool get_rain_puddles(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels,
    float porosity,
    uint material_mask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness,
    inout float ssr_multiplier
) {
#ifndef RAIN_PUDDLES
    return false;
#endif

#if RAIN_PUDDLES_MODE == RAIN_PUDDLES_OFF
    return false;
#else
    const float puddle_f0 = 0.02;
    const float puddle_roughness = 0.002;
    const float puddle_darkening_factor = 0.33;
    const float puddle_darkening_factor_porous = 0.67;

    // Skip leaves entirely — puddles on leaves look wrong since the
    // canopy should be shedding water, not pooling it.
    if (material_mask == MATERIAL_LEAVES) {
        return false;
    }

    // In EVERYWHERE mode we ignore biome_may_rain entirely; only the
    // global wetness (is it raining anywhere in the overworld?) matters.
    // The wetness < 0 guard is a defensive check against malformed
    // uniforms (nether / end / void where wetness is set to a negative
    // sentinel to mark "water cannot reach here").
    //
    // In RAIN mode we additionally require biome_may_rain > 0 so that
    // deserts and snowy biomes stay dry even while it's raining globally.
#if RAIN_PUDDLES_MODE == RAIN_PUDDLES_EVERYWHERE
    if (wetness < 0.0) {
        return false;
    }
#else
    if (wetness < 0.0 || biome_may_rain < 0.0) {
        return false;
    }
#endif

    float puddle = get_puddle_noise(world_pos, flat_normal, light_levels);

    if (puddle < eps) {
        return false;
    }

    // Puddle darkening
    // Porous surfaces absorb water and darken more strongly than
    // non-porous ones. Puddles themselves also shrink on porous surfaces
    // because the water seeps in instead of pooling on top.
    albedo *= 1.0 - puddle_darkening_factor_porous * porosity * puddle;
    puddle *= 1.0 - porosity;
    albedo *= 1.0 - puddle_darkening_factor * puddle;

    // Replace material with puddle material
    f0 = max(f0, mix(f0, vec3(puddle_f0), puddle));
    roughness = puddle_roughness;
    ssr_multiplier = max(ssr_multiplier, puddle);

    // Ripple animation
    const float h = 0.1;
    float ripple0 = get_ripple_height(world_pos.xz);
    float ripple1 = get_ripple_height(world_pos.xz + vec2(h, 0.0));
    float ripple2 = get_ripple_height(world_pos.xz + vec2(0.0, h));

    vec3 ripple_normal = vec3(ripple1 - ripple0, ripple2 - ripple0, h);
    ripple_normal.xy
        *= 0.05
        * smoothstep(
               0.0,
               0.1,
               abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
        );
    ripple_normal = normalize(ripple_normal);
    ripple_normal = ripple_normal.xzy; // convert to world space

    normal = mix(normal, flat_normal, puddle);
    normal = mix(normal, ripple_normal, puddle * rainStrength);
    normal = normalize_safe(normal);

    return true;
#endif
}

#endif // INCLUDE_MISC_RAIN_PUDDLES
