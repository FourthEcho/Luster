#if !defined INCLUDE_SURFACE_SNOW_ACCUMULATION
#define INCLUDE_SURFACE_SNOW_ACCUMULATION

#include "/include/misc/material_masks.glsl"

// ---- Snow accumulation ----
//
// The counterpart to rain puddles for freezing biomes: while rain darkens
// the ground and pools in puddles, snowfall blankets up-facing surfaces in
// white. Rain has wetness, porosity darkening and puddles; snow previously
// had only falling particles with no trace on the ground.
//
// Cover has two drivers:
//   * live snowfall: global precipitation (wetness) gated by biome_may_snow,
//     so snow builds while it snows and fades as it melts;
//   * retained base: snowy biomes keep a broken white cover even between
//     snowfalls (scaled by biome_snowy), so tundra never reads as bare
//     dirt while rain regions do.
// Both are broken up by noise, masked to up-facing sky-visible surfaces
// (skylight gate excludes caves, interiors and overhangs), and applied as
// a material replacement: bright dielectric albedo, high roughness.

const vec3 snow_accumulated_albedo = vec3(0.80, 0.84, 0.90);
const float snow_accumulated_roughness = 0.9;
const float snow_accumulated_f0 = 0.02;

float get_snow_cover_noise(vec3 world_pos, vec3 flat_normal) {
    const float snow_frequency = 0.02;

    float cover = texture(noisetex, world_pos.xz * snow_frequency).x;
    float detail = texture(noisetex, world_pos.xz * snow_frequency * 5.0).z;

    // Two-scale breakup: large drifts plus fine erosion; steeper faces
    // hold less snow even before the slope falloff below
    float snow = linear_step(0.35, 0.65, cover * 0.7 + detail * 0.3);
    snow *= smoothstep(0.35, 0.75, flat_normal.y);

    return snow;
}

bool get_snow_accumulation(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels,
    uint material_mask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness
) {
#ifndef SNOW_ACCUMULATION
    return false;
#endif

    // Lava never accumulates snow; the sentinel also keeps nether/end void
    // safe the same way the puddle path does
    if (material_mask == MATERIAL_LAVA || wetness < 0.0) {
        return false;
    }

    // Live snowfall where the biome can snow, plus a retained base cover
    // in snowy biomes so tundra stays white between snowfalls
    float snowfall = wetness * max0(biome_may_snow);
    float retained = biome_snowy * 0.8;
    float cover_amount = clamp01(snowfall * 1.2 + retained);

    if (cover_amount < eps) {
        return false;
    }

    float snow = get_snow_cover_noise(world_pos, flat_normal) * cover_amount;

    // Sky visibility gate: no snow in caves, indoors or under overhangs
    snow *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    snow *= SNOW_ACCUMULATION_INTENSITY;
    snow = clamp01(snow);

    if (snow < eps) {
        return false;
    }

    // Material replacement: snow is a bright, rough dielectric that
    // rounds over the underlying micro-surface
    albedo = mix(albedo, snow_accumulated_albedo, snow);
    f0 = mix(f0, vec3(snow_accumulated_f0), snow);
    roughness = mix(roughness, snow_accumulated_roughness, snow);
    normal = normalize(mix(normal, flat_normal, snow * 0.35));

    return true;
}

#endif // INCLUDE_SURFACE_SNOW_ACCUMULATION
