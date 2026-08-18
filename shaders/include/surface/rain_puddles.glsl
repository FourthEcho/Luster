#if !defined INCLUDE_MISC_RAIN_PUDDLES
#define INCLUDE_MISC_RAIN_PUDDLES

#include "/include/misc/material_masks.glsl"

float get_puddle_noise(vec3 world_pos, vec3 flat_normal, vec2 light_levels) {
    const float puddle_frequency = 0.025;

    float puddle = texture(noisetex, world_pos.xz * puddle_frequency).w;
    puddle = linear_step(0.45, 0.55, puddle) * step(0.99, flat_normal.y);

    // "Everywhere" mode forms puddles on all applicable surfaces regardless of
    // rain
#if RAIN_PUDDLES_MODE == RAIN_PUDDLES_MODE_EVERYWHERE
    // Puddles do not depend on weather in this mode
#else
    puddle *= wetness * biome_may_rain;
#endif

    // Prevent puddles from appearing indoors
    puddle *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    return puddle * RAIN_PUDDLES_INTENSITY;
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
#if RAIN_PUDDLES_MODE == RAIN_PUDDLES_MODE_OFF
    return false;
#endif

    const float puddle_f0 = 0.02;
    const float puddle_roughness = 0.002;
    const float puddle_darkening_factor = 0.33;
    const float puddle_darkening_factor_porous = 0.67;

    if (material_mask == MATERIAL_LEAVES) {
        return false;
    }

#if RAIN_PUDDLES_MODE != RAIN_PUDDLES_MODE_EVERYWHERE
    if (wetness < 0.0 || biome_may_rain < 0.0) {
        return false;
    }
#endif

    float puddle = get_puddle_noise(world_pos, flat_normal, light_levels);

    if (puddle < eps) {
        return false;
    }

    // Puddle darkening
    albedo *= 1.0 - puddle_darkening_factor_porous * porosity * puddle;
    puddle *= 1.0 - porosity;
    albedo *= 1.0 - puddle_darkening_factor * puddle;

    // Replace material with puddle material
    f0 = max(f0, mix(f0, vec3(puddle_f0), puddle));
    roughness = puddle_roughness;
    ssr_multiplier = max(ssr_multiplier, puddle);

    normal = mix(normal, flat_normal, puddle);
    normal = normalize_safe(normal);

    return true;
}

#endif // INCLUDE_MISC_RAIN_PUDDLES
