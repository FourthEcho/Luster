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

#if !defined INCLUDE_FOG_OVERWORLD_PARAMETERS
#define INCLUDE_FOG_OVERWORLD_PARAMETERS

struct OverworldFogParameters {
    vec3 rayleigh_scattering_coeff;
    vec3 mie_scattering_coeff;
    vec3 mie_extinction_coeff;
    vec3 mist_scattering_coeff; // tinted by live horizon sky colour
};

#endif // INCLUDE_FOG_OVERWORLD_PARAMETERS
