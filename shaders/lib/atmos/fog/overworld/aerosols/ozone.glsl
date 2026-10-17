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

#if !defined INCLUDE_FOG_OVERWORLD_OZONE
#define INCLUDE_FOG_OVERWORLD_OZONE

#ifdef ozoneSky
#define OZONE_SKY_OPTION_ENABLED
#endif
#ifdef ozoneFog
#define OZONE_FOG_OPTION_ENABLED
#endif
#ifdef ozoneMist
#define OZONE_MIST_OPTION_ENABLED
#endif
#ifdef ozonePlanetBounce
#define OZONE_PLANET_BOUNCE_OPTION_ENABLED
#endif

#include "/lib/util/color.glsl"

const float ozonePlanetRadius = 6371e3; // m

const float ozoneLayerAltitude = ozoneAltitude * 1e3; // m
const float ozoneLayerWidth = ozoneThickness * 1e3;   // m


const vec3 ozoneAbsorptionCoefficient
    = vec3(8.304280072e-07, 1.314911970e-06, 5.440679729e-08)
    * vec3(ozoneColorR, ozoneColorG, ozoneColorB) // user tint (Rec. 709)
    * rec709ToWorkingColor;

const float sqrtPi = 1.7724538509;
const float ozoneLayerColumn = ozoneAmount * ozoneLayerWidth * sqrtPi;

const vec3 ozoneExtinction
    = ozoneAbsorptionCoefficient * ozoneLayerColumn;

float ozoneShellAirmass(float mu, float r, float h) {
    float top = ozonePlanetRadius + h;

    // Guard the discriminant: from inside the shell every outward ray
    // reaches it, so this only protects the mu -> 0, h -> 0 corner
    float bSq = max(top * top - r * r * (1.0 - mu * mu), 1.0);

    return top * inversesqrt(bSq);
}

float ozoneLayerAirmass(float mu, float r) {
    const float w = ozoneLayerWidth;

    float a0 = ozoneShellAirmass(mu, r, ozoneLayerAltitude - 2.0 * w);
    float a1 = ozoneShellAirmass(mu, r, ozoneLayerAltitude - 1.0 * w);
    float a2 = ozoneShellAirmass(mu, r, ozoneLayerAltitude);
    float a3 = ozoneShellAirmass(mu, r, ozoneLayerAltitude + 1.0 * w);
    float a4 = ozoneShellAirmass(mu, r, ozoneLayerAltitude + 2.0 * w);

    return 0.0103339 * a0 + 0.2075612 * a1 + 0.5642099 * a2
         + 0.2075612 * a3 + 0.0103339 * a4;
}

vec3 ozoneLayerOpticalDepth(float mu, float r) {
    return ozoneExtinction * ozoneLayerAirmass(mu, r);
}

vec3 ozoneLayerTransmittance(float mu, float r) {
#ifdef ozoneLayer
    return exp(-ozoneLayerOpticalDepth(mu, r));
#else
    return vec3(1.0);
#endif
}

const float ozoneDiffuseAirmass = 1.9;

vec3 ozoneMultipleScattering(float order) {
#ifdef ozoneLayer
    return exp(-ozoneExtinction * (ozoneDiffuseAirmass * order));
#else
    return vec3(1.0);
#endif
}

#endif // INCLUDE_FOG_OVERWORLD_OZONE
