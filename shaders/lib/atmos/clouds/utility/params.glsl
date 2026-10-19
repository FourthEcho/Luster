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

#if !defined INCLUDE_ATMOS_CLOUDS_CORE_PARAMS
#define INCLUDE_ATMOS_CLOUDS_CORE_PARAMS

struct CloudsParams {
    // Cumulus congestus
    float cumulusCongestusBlend; // replaces layer 0
    // Volumetric layer 0
    vec2 l0Coverage;
    vec2 l0DetailWeights;
    vec2 l0EdgeSharpening;
    float l0AltitudeScale;
    float l0CumulusStratusBlend;
    float l0ExtinctionCoeff; // also applies for Cu Con
    float l0ScatteringCoeff; // also applies for Cu Con
    float l0Shadow;
    // Volumetric layer 1
    vec2 l1Coverage;
    float l1CumulusStratusBlend;
    float l1Shadow;
    // Planar clouds
    float cirrusAmount;
    float cirrocumulusAmount;
    float noctilucentAmount;
    // Other
    float crepuscularRaysAmount;
};

#endif // INCLUDE_ATMOS_CLOUDS_CORE_PARAMS
