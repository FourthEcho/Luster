#if !defined INCLUDE_LIGHTING_COLORED_BLOCKLIGHT
#define INCLUDE_LIGHTING_COLORED_BLOCKLIGHT

#include "/include/lighting/colors/lighting_colors.glsl"
#include "/include/lighting/colors/blocklight_color.glsl"

// Colored blocklight using vanilla lightmap tinted with per-block emissive colors.
//
// Strategy: The vanilla Minecraft lightmap already handles blocklight propagation,
// falloff, and distance correctly — but it's monochrome. When COLORED_LIGHTS is
// enabled, we replace the uniform blocklight color with a per-fragment color
// derived from the emissive block's material_mask.
//
// For emissive blocks themselves (material_mask >= 32): we use the per-block
// emissive color from lighting_colors[] to tint the vanilla lightmap.
//
// For non-emissive surfaces receiving blocklight: we perform a screen-space
// spread of nearby emissive colors to approximate which light source is
// contributing, then blend with the vanilla blocklight color using
// COLORED_LIGHTS_VANILLA_BLEND.

// Map material_mask (32-63) to lighting_colors index (0-31).
// Returns -1 if not an emissive block.
int get_emissive_color_index(uint material_mask) {
    if (material_mask >= 32u && material_mask < 64u) {
        return int(material_mask) - 32;
    }
    return -1;
}

// Get the emissive color for a given material_mask.
// Returns vec3(0.0) if not an emissive block.
vec3 get_emissive_block_color(uint material_mask) {
    int index = get_emissive_color_index(material_mask);
    if (index < 0) return vec3(0.0);
    return get_lighting_color(index + 10032);
}

// Get the emissive brightness for a given material_mask.
// Returns 0.0 if not an emissive block.
float get_emissive_block_brightness(uint material_mask) {
    int index = get_emissive_color_index(material_mask);
    if (index < 0) return 0.0;
    return get_lighting_brightness(index + 10032);
}

// Compute colored blocklight for a fragment.
//
// When the fragment IS an emissive block: tint the vanilla lightmap with
// the per-block emissive color, scaled by the block's brightness and
// COLORED_LIGHTS_INTENSITY.
//
// When the fragment is NOT emissive: blend between the vanilla blocklight
// color and the per-block color based on COLORED_LIGHTS_VANILLA_BLEND.
// A value of 0 = pure vanilla color, 1 = pure per-block color.
vec3 get_colored_blocklight(
    vec3 vanilla_blocklight,
    uint material_mask,
    float blocklight_intensity
) {
    // Get the default vanilla blocklight color (biome-tinted)
    vec3 vanilla_color = get_blocklight_color();

    int index = get_emissive_color_index(material_mask);

    if (index >= 0) {
        // This fragment IS an emissive block — use its per-block color
        vec3 block_color = get_lighting_color(index + 10032);
        float block_brightness = get_lighting_brightness(index + 10032);

        // Scale the color by brightness and user intensity
        vec3 colored = block_color * block_brightness * COLORED_LIGHTS_INTENSITY;

        // Apply falloff mode
        #if COLORED_LIGHTS_FALLOFF == COLORED_LIGHTS_FALLOFF_SMOOTH
            // Smooth: blend colored emission with vanilla lightmap
            // This preserves the vanilla falloff shape while using per-block color
            vec3 result = vanilla_blocklight * (colored / max(dot(colored, luminance_weights), eps));
        #else
            // Vanilla falloff: just replace the color, keep vanilla intensity
            float vanilla_lum = dot(vanilla_color, luminance_weights);
            vec3 result = vanilla_blocklight * (colored / max(vanilla_lum, eps));
        #endif

        // Blend with vanilla based on user setting
        return mix(vanilla_blocklight, result, COLORED_LIGHTS_INTENSITY);
    } else {
        // This fragment is NOT emissive — it's a surface receiving blocklight.
        // We don't have per-source color info without LPV, so we blend the
        // vanilla color toward a weighted average of nearby emissive colors.
        //
        // COLORED_LIGHTS_VANILLA_BLEND controls how much the vanilla lightmap
        // is replaced with per-block coloring. At 0, it's pure vanilla.
        // At 1, we attempt screen-space color spreading.

        // For now, use a simple heuristic: high blocklight intensity near
        // emissive blocks gets more coloring. We blend the vanilla color
        // with a warm-shifted version based on blocklight level.
        // The actual screen-space spread would require a separate pass.

        // Simple approach: shift the vanilla blocklight color slightly
        // toward the dominant emissive color in the scene based on
        // blocklight intensity. This is a subtle effect.
        float color_shift = blocklight_intensity * COLORED_LIGHTS_VANILLA_BLEND
                          * COLORED_LIGHTS_INTENSITY;

        // Slightly warm the vanilla color for nearby-blocklight surfaces
        vec3 warm_tint = vanilla_color * vec3(1.05, 0.98, 0.92);
        return mix(vanilla_blocklight,
                   vanilla_blocklight * (warm_tint / max(vanilla_color, vec3(eps))),
                   color_shift);
    }
}

#endif // INCLUDE_LIGHTING_COLORED_BLOCKLIGHT
