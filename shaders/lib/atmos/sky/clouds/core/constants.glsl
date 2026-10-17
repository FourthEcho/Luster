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

#if !defined INCLUDE_SKY_CLOUDS_CONSTANTS
#define INCLUDE_SKY_CLOUDS_CONSTANTS

#include "/lib/atmos/atmosphere.glsl"

const float cloudsCumulusRadius = planetRadius + cloudsCumulusAltitude;
const float cumulusLayerThickness
    = cloudsCumulusAltitude * cloudsCumulusThickness;
const float cloudsCumulusTopRadius
    = cloudsCumulusRadius + cumulusLayerThickness;

const float cloudsAltocumulusRadius
    = planetRadius + cloudsAltocumulusAltitude;
const float altocumulusLayerThickness
    = cloudsAltocumulusAltitude * cloudsAltocumulusThickness;
const float cloudsAltocumulusTopRadius
    = cloudsAltocumulusRadius + altocumulusLayerThickness;

const float cloudsCirrusRadius = planetRadius + cloudsCirrusAltitude;
const float cirrusLayerThickness
    = cloudsCirrusAltitude * cloudsAltocumulusThickness;
const float cloudsCirrusTopRadius
    = cloudsCirrusRadius + cirrusLayerThickness;
const float cloudsCirrusExtinctionCoeff = 0.15;
const float cloudsCirrusScatteringCoeff = cloudsCirrusExtinctionCoeff;

const float cloudsNoctilucentAltitude = 80000.0;
const float cloudsNoctilucentRadius
    = planetRadius + cloudsNoctilucentAltitude;

#endif // INCLUDE_SKY_CLOUDS_CONSTANTS
