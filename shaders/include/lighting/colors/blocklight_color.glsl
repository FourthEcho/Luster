#if !defined INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR

#include "/include/utility/color.glsl"

const vec3 blocklight_color_base
    = from_srgb(vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B)) * BLOCKLIGHT_I;
const float blocklight_scale = 6.0;
const float emission_scale = 40.0 * EMISSION_STRENGTH;

// Backwards-compatible name for code that only wants the base (non-biome-tinted) color
const vec3 blocklight_color = blocklight_color_base;

// Biome-aware blocklight tint. fogColor already carries the current biome's
// tint (grass/foliage/fog hue) as supplied by Minecraft/Iris, so we
// normalize it to preserve blocklight brightness and only borrow its
// hue/chroma.
vec3 get_blocklight_color() {
#ifdef BLOCKLIGHT_BIOME_COLOR
    vec3 biome_tint = srgb_eotf_inv(fogColor) * rec709_to_working_color;
    biome_tint /= max(dot(biome_tint, luminance_weights), eps);

    return mix(
        blocklight_color_base,
        blocklight_color_base * biome_tint,
        BLOCKLIGHT_BIOME_INTENSITY
    );
#else
    return blocklight_color_base;
#endif
}

#endif // INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
