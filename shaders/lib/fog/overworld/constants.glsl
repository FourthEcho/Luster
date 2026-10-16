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

#if !defined INCLUDE_FOG_OVERWORLD_CONSTANTS
#define INCLUDE_FOG_OVERWORLD_CONSTANTS

const uint air_fog_min_step_count = 8;
const uint air_fog_max_step_count = 25;
const float air_fog_step_count_growth = 0.1;
const float air_fog_volume_top = 320.0;
const float air_fog_volume_bottom = 63.0 - 24.0;
const vec2 air_fog_falloff_start
    = vec2(airFogRayleighFalloffStart, airFogMieFalloffStart)
    + 63.0;
const vec2 air_fog_falloff_half_life
    = vec2(airFogRayleighFalloffHalfLife, airFogMieFalloffHalfLife);

// ---- Mist constants ----


const float mist_base_scatter_coeff = 8e-3;

#endif // INCLUDE_FOG_OVERWORLD_CONSTANTS
