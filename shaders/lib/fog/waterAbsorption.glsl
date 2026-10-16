/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#if !defined INCLUDE_FOG_WATER_ABSORPTION
#define INCLUDE_FOG_WATER_ABSORPTION

#include "/lib/util/color.glsl"

vec3 biome_water_coeff(vec3 biome_water_color) {
    const float density_scale = 0.15;
    const float biome_color_contribution = 0.33;

    const vec3 base_absorption_coeff
        = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
        * rec709_to_working_color;
    const vec3 forest_absorption_coeff
        = -density_scale * log(vec3(0.1245, 0.1797, 0.7108));

#ifdef biomeWaterColor
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
