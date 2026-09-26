#if !defined INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR

#include "/include/utility/color.glsl"

const float blocklight_scale = 6.0;
// Decoupled from material emission controls on purpose: block light intensity
// is the light field's scale, while the global emission system controls
// emissive surface brightness separately.
const float emission_scale = 40.0;

// Physical torch base: blackbody spectrum at the user temperature,
// normalized to 1.0 at the reference temperature so the default look is
// unchanged and the slider only warms/cools around it. The RGB tint below
// stays as the artistic control on top.
vec3 get_blocklight_temperature_color() {
    const float reference_temperature = 3400.0;
    return blackbody(BLOCKLIGHT_TEMPERATURE)
        / max(blackbody(reference_temperature), vec3(eps));
}

#define blocklight_color \
    (from_display(vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B)) * BLOCKLIGHT_I \
     * get_blocklight_temperature_color())

#endif // INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
