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

#include "/lib/sky/atmosphere.glsl"

const float clouds_cumulus_radius = planet_radius + cloudsCumulusAltitude;
const float clouds_cumulus_thickness
    = cloudsCumulusAltitude * cloudsCumulusThickness;
const float clouds_cumulus_top_radius
    = clouds_cumulus_radius + clouds_cumulus_thickness;

const float clouds_altocumulus_radius
    = planet_radius + cloudsAltocumulusAltitude;
const float clouds_altocumulus_thickness
    = cloudsAltocumulusAltitude * cloudsAltocumulusThickness;
const float clouds_altocumulus_top_radius
    = clouds_altocumulus_radius + clouds_altocumulus_thickness;

const float clouds_cirrus_radius = planet_radius + cloudsCirrusAltitude;
const float clouds_cirrus_thickness
    = cloudsCirrusAltitude * cloudsAltocumulusThickness;
const float clouds_cirrus_top_radius
    = clouds_cirrus_radius + clouds_cirrus_thickness;
const float clouds_cirrus_extinction_coeff = 0.15;
const float clouds_cirrus_scattering_coeff = clouds_cirrus_extinction_coeff;

const float clouds_noctilucent_altitude = 80000.0;
const float clouds_noctilucent_radius
    = planet_radius + clouds_noctilucent_altitude;

#endif // INCLUDE_SKY_CLOUDS_CONSTANTS
