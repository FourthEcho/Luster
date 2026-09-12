#if !defined INCLUDE_FOG_WATER_ABSORPTION
#define INCLUDE_FOG_WATER_ABSORPTION

// Water absorption coefficients shared by the fog system
// ("/include/fog/simple_fog.glsl") and the shadow pass (which cannot
// include the full fog file). Blends the neutral baseline with the
// per-biome water tint.
//
// Requires: WATER_ABSORPTION_* settings, rec709_to_working_color from
// "/include/utility/color.glsl", eps/max0 from "/include/global.glsl".

#include "/include/utility/color.glsl"

vec3 biome_water_coeff(vec3 biome_water_color) {
    const float density_scale = 0.15;
    const float biome_color_contribution = 0.33;

    const vec3 base_absorption_coeff
        = vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B)
        * rec709_to_working_color;
    const vec3 forest_absorption_coeff
        = -density_scale * log(vec3(0.1245, 0.1797, 0.7108));

#ifdef BIOME_WATER_COLOR
    vec3 biome_absorption_coeff = -density_scale * log(biome_water_color + eps)
        - forest_absorption_coeff;

    return max0(
        base_absorption_coeff
        + biome_absorption_coeff * biome_color_contribution
    );
#else
    return base_absorption_coeff;
#endif
}

#endif // INCLUDE_FOG_WATER_ABSORPTION
