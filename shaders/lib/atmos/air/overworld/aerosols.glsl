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

#if !defined INCLUDE_ATMOS_AIR_OVERWORLD_OZONE
#define INCLUDE_ATMOS_AIR_OVERWORLD_OZONE

#ifdef ozoneLayer
#define OZONE_SKY_OPTION_ENABLED
#endif
#ifdef ozoneLayer
#define OZONE_FOG_OPTION_ENABLED
#endif
#ifdef ozoneLayer
#define OZONE_MIST_OPTION_ENABLED
#endif
#ifdef ozoneLayer
#define OZONE_PLANET_BOUNCE_OPTION_ENABLED
#endif

#include "/lib/util/color.glsl"

const float ozonePlanetRadius = 6371e3; // m

const float ozoneLayerAltitude = ozoneAltitude * 1e3; // m
const float ozoneLayerWidth = ozoneThickness * 1e3;   // m


const vec3 ozoneAbsorptionCoef
    = vec3(8.304280072e-07, 1.314911970e-06, 5.440679729e-08)
    * vec3(ozoneColorR, ozoneColorG, ozoneColorB) // user tint (Rec. 709)
    * rec709ToWorkingColor;

const float sqrtPi = 1.7724538509;
const float ozoneLayerColumn = ozoneAmount * ozoneLayerWidth * sqrtPi;

const vec3 ozoneExtinction
    = ozoneAbsorptionCoef * ozoneLayerColumn;

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

// Ozone removes green much faster than red and blue. The view path towards
// the horizon is the longest one, so applying the full extinction there
// strips the green out of the pale horizon haze and turns it violet. Keep
// only a fraction of that chromatic shift: the ozone still dims and cools
// the sky, but the horizon stays neutral (warm towards the sun at
// sunrise/sunset, blue at noon).
const float ozoneViewChroma = 0.25;

vec3 ozoneLayerViewTransmittance(float mu, float r) {
    vec3 transmittance = ozoneLayerTransmittance(mu, r);
    float luminance = dot(transmittance, luminanceWeights);
    return mix(vec3(luminance), transmittance, ozoneViewChroma);
}

#endif // INCLUDE_ATMOS_AIR_OVERWORLD_OZONE

#if !defined INCLUDE_ATMOS_AIR_OVERWORLD_SANDBORMDSTORM
#define INCLUDE_ATMOS_AIR_OVERWORLD_SANDBORMDSTORM


#ifdef desertSandstorm
#define SANDSTORM_LAYER_OPTION_ENABLED
#endif
#ifdef desertSandstorm
#define SANDSTORM_SKY_OPTION_ENABLED
#endif
#ifdef desertSandstorm
#define SANDSTORM_MIST_OPTION_ENABLED
#endif
#ifdef desertSandstorm
#define SANDSTORM_BOUNCE_OPTION_ENABLED
#endif

#include "/lib/util/color.glsl"

#ifdef desertSandstorm


const float sandstormScaleHeight = 1.5e3; // m


const vec3 sandstormExtinctionCoeff
    = vec3(1.15, 0.75, 0.45) * 2.2e-5;

float sandstormStrength() {
#ifdef desertSandstorm
    return clamp01(desertSandstormWeather * desertSandstormIntensity);
#else
    return 0.0;
#endif
}

float sandstormAirmass(float mu) {
    float x = sandstormScaleHeight / 6371e3;
    float c = sqrt(1.5707963 / max(x, 1e-9));
    float m = c / ((c - 1.0) * mu + 1.0);
    if (mu < 0.0) {


        float top = 6371e3 + 4.0 * sandstormScaleHeight;
        float r = 6371e3;
        m = top * inversesqrt(max(top * top - r * r * (1.0 - mu * mu), 1.0));
    }
    return clamp(m, 0.0, 24.0);
}

vec3 sandstormTransmittance(float mu) {
#ifdef desertSandstorm
    float s = sandstormStrength();
    if (s <= 1e-5) return vec3(1.0);
    return exp(-sandstormExtinctionCoeff * (sandstormAirmass(mu) * s));
#else
    return vec3(1.0);
#endif
}

// Warm tint of dust-scattered light, for mist and ambient coupling.
vec3 sandstormTint() {
    return gamutExpand(normalize(vec3(1.0, 0.78, 0.55) + 1e-6));
}
#else
float sandstormStrength() { return 0.0; }
float sandstormAirmass(float mu) { return 0.0; }
vec3 sandstormTransmittance(float mu) { return vec3(1.0); }
vec3 sandstormTint() { return vec3(1.0); }
#endif

#endif // INCLUDE_ATMOS_AIR_OVERWORLD_SANDBORMDSTORM
