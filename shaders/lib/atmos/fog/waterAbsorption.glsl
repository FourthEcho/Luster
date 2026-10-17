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

vec3 biomeWaterCoeff(vec3 biomeWaterTint) {
    const float densityScale = 0.15;
    const float biomeColorContribution = 0.33;

    const vec3 baseAbsorptionCoeff
        = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
        * rec709ToWorkingColor;
    const vec3 forestAbsorptionCoeff
        = -densityScale * log(vec3(0.1245, 0.1797, 0.7108));

#ifdef biomeWaterColor
    vec3 biomeAbsorptionCoeff = -densityScale * log(biomeWaterTint + eps)
        - forestAbsorptionCoeff;

    return max0(
        baseAbsorptionCoeff
        + biomeAbsorptionCoeff * biomeColorContribution
    );
#else
    return baseAbsorptionCoeff;
#endif
}

#endif // INCLUDE_FOG_WATER_ABSORPTION
