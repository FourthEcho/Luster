#if !defined INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR

#include "/include/utility/color.glsl"

// Vanilla GL uniform — Minecraft's per-biome fog color.
uniform vec3 fogColor;

vec3 get_blocklight_color_base() {
    return from_native(vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B)) * BLOCKLIGHT_I;
}
const float blocklight_scale = 6.0;
const float emission_scale = 40.0 * EMISSION_STRENGTH;

// Biome-tinted blocklight.
//
// Torch/lantern color is shifted toward the current biome's fog hue, taken
// from Minecraft's `fogColor` uniform (no new GUI, no extra config). This
// makes blocklight feel warmer in deserts, cooler in snowy biomes, greener
// in swamps/jungles, etc.
//
//  - tint strength = 0.35 (kept subtle so user-chosen BLOCKLIGHT_RGB still
//    dominates)
//  - luminance is preserved while hue and chroma are shifted, keeping
//    the perceived intensity of blocklight is preserved
vec3 get_blocklight_color() {
    // Decode the biome fog color into linear rec709, then convert to the
    // working color space (Rec2020 linear) used by the lighting pipeline.
    vec3 biome_tint_linear = srgb_eotf_inv(fogColor) * rec709_to_working_color;

    // Base user color in working space.
    vec3 base = get_blocklight_color_base();

    // Luminance-preserving tint: pull the result toward the biome color in
    // hue/chroma space, but keep the original luminance.
    float base_lum   = dot(base,          luminance_weights);
    float biome_lum  = dot(biome_tint_linear, luminance_weights);

    // Avoid divide-by-zero on near-black biome colors.
    vec3 biome_normalized = (biome_lum > eps)
        ? biome_tint_linear * (base_lum / biome_lum)
        : base;

    // 0.35 tint strength — the user-chosen BLOCKLIGHT_RGB still dominates.
    vec3 tinted = mix(base, biome_normalized, 0.35);

    // Final luminance should equal base_lum; clamp for safety.
    float final_lum = dot(tinted, luminance_weights);
    if (final_lum > eps) {
        tinted *= base_lum / final_lum;
    }

    return tinted;
}

// Backwards-compatible name for code that only wants the base color
// Apple GLSL is sensitive to global function-call initializers; keep this as a macro accessor.
#define blocklight_color (get_blocklight_color_base())

#endif // INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
