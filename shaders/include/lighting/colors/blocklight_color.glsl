#if !defined INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR

#include "/include/utility/color.glsl"

const float blocklight_scale = 6.0;
const float emission_scale = 40.0 * EMISSION_STRENGTH;

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
    (from_srgb(vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B)) * BLOCKLIGHT_I \
     * get_blocklight_temperature_color())

#endif // INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
