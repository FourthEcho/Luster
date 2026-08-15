#ifndef INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#include "/include/lighting/colors/lighting_colors.glsl"

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

// Optional material-based override for the colored mode, set by the deferred
// pass when the held item has a labPBR/OldPBR emissive map (see
// program/d4_deferred_shading.fsh). Defaults to no override.
#ifndef HANDHELD_LIGHTING_MATERIAL_COLOR
#define HANDHELD_LIGHTING_MATERIAL_COLOR vec3(0.0)
#endif

vec3 get_handheld_light_color(int held_item_id, int held_item_light_value) {
#if HANDHELD_LIGHTING_MODE == HANDHELD_LIGHTING_NORMAL
    // Warm vanilla blocklight color scaled by the item's light level
    return (get_blocklight_color_raw() * blocklight_scale * rcp(15.0))
        * held_item_light_value;
#elif HANDHELD_LIGHTING_MODE == HANDHELD_LIGHTING_COLORED
    // Per-emissive-block color and brightness from lighting_colors.glsl,
    // falling back to the vanilla blocklight color for unmapped items
    vec3 color = get_lighting_color(held_item_id);
    float brightness = get_lighting_brightness(held_item_id);

    if (brightness > 0.0) {
        return color * brightness * blocklight_scale;
    } else {
        return (get_blocklight_color_raw() * blocklight_scale * rcp(15.0))
            * held_item_light_value;
    }
#else
    return vec3(0.0);
#endif
}

float get_handheld_light_falloff(vec3 scene_pos, float ao) {
    float falloff = lift(rcp(dot(scene_pos, scene_pos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * HANDHELD_LIGHTING_INTENSITY;
}

vec3 get_handheld_lighting(vec3 scene_pos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scene_pos += relativeEyePosition;
#endif

    vec3 light_color = max(
        get_handheld_light_color(heldItemId, heldBlockLightValue),
        get_handheld_light_color(heldItemId2, heldBlockLightValue2)
    );

#if HANDHELD_LIGHTING_MODE == HANDHELD_LIGHTING_COLORED
    // The held item's own labPBR/OldPBR emission takes priority over the
    // built-in mapping when the material map contains an emissive value
    light_color = mix(
        light_color,
        HANDHELD_LIGHTING_MATERIAL_COLOR,
        smoothstep(0.0, 0.02, max_of(HANDHELD_LIGHTING_MATERIAL_COLOR))
    );
#endif

    float falloff = get_handheld_light_falloff(scene_pos, ao);

    return light_color * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
