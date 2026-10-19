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

#if !defined INCLUDE_ATMOS_AIR_OVERWORLD_CONSTANTS
#define INCLUDE_ATMOS_AIR_OVERWORLD_CONSTANTS

const uint airFogMinStepCount = 8;
const uint airFogMaxStepCount = 25;
const float airFogStepCountGrowth = 0.1;
const float airFogVolumeTop = 320.0;
const float airFogVolumeBottom = 63.0 - 24.0;
const vec2 airFogFalloffStart
    = vec2(airFogRayleighFalloffStart, airFogMieFalloffStart)
    + 63.0;
const vec2 airFogFalloffHalfLife
    = vec2(airFogRayleighFalloffHalfLife, airFogMieFalloffHalfLife);

// ---- Mist constants ----


const float mistBaseScatterCoeff = 8e-3;

#endif // INCLUDE_ATMOS_AIR_OVERWORLD_CONSTANTS
