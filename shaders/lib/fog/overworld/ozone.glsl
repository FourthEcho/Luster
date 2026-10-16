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

// ---------------------------------------------------------------------------
//   Ozone absorption layer
// ---------------------------------------------------------------------------

// Planet radius, mirroring atmosphere.glsl so the shell geometry below
// uses the same planet model
const float ozone_planet_radius = 6371e3; // m

// Layer geometry. The density profile is a Gaussian peaking at
// ozoneAltitude with standard deviation ozoneThickness.
const float ozone_layer_altitude = ozoneAltitude * 1e3; // m
const float ozone_layer_width = ozoneThickness * 1e3;   // m


const vec3 ozone_absorption_coefficient
    = vec3(8.304280072e-07, 1.314911970e-06, 5.440679729e-08)
    * vec3(ozoneColorR, ozoneColorG, ozoneColorB) // user tint (Rec. 709)
    * rec709_to_working_color;


// by the user amount. A Gaussian with standard deviation w integrates to

const float sqrt_pi = 1.7724538509;
const float ozone_layer_column = ozoneAmount * ozone_layer_width * sqrt_pi;

// Vertical optical depth spectrum through the whole layer
const vec3 ozone_extinction
    = ozone_absorption_coefficient * ozone_layer_column;


float ozone_shell_airmass(float mu, float r, float h) {
    float top = ozone_planet_radius + h;

    // Guard the discriminant: from inside the shell every outward ray
    // reaches it, so this only protects the mu -> 0, h -> 0 corner
    float b_sq = max(top * top - r * r * (1.0 - mu * mu), 1.0);

    return top * inversesqrt(b_sq);
}


// placed at +/-2 sigma around the peak and weighted by exp(-k^2), so the


float ozone_layer_airmass(float mu, float r) {
    const float w = ozone_layer_width;

    float a0 = ozone_shell_airmass(mu, r, ozone_layer_altitude - 2.0 * w);
    float a1 = ozone_shell_airmass(mu, r, ozone_layer_altitude - 1.0 * w);
    float a2 = ozone_shell_airmass(mu, r, ozone_layer_altitude);
    float a3 = ozone_shell_airmass(mu, r, ozone_layer_altitude + 1.0 * w);
    float a4 = ozone_shell_airmass(mu, r, ozone_layer_altitude + 2.0 * w);

    // Band weights exp(-k^2), normalized so they sum to exactly 1 and the
    // vertical airmass is exactly 1 (k in {-2, -1, 0, 1, 2})
    return 0.0103339 * a0 + 0.2075612 * a1 + 0.5642099 * a2
         + 0.2075612 * a3 + 0.0103339 * a4;
}

// Optical depth spectrum of the layer along a ray leaving radius r with
// zenith cosine mu
vec3 ozone_layer_optical_depth(float mu, float r) {
    return ozone_extinction * ozone_layer_airmass(mu, r);
}

// Transmittance of the layer along a ray leaving radius r with zenith
// cosine mu. Identity when the layer is disabled.
vec3 ozone_layer_transmittance(float mu, float r) {
#ifdef ozoneLayer
    return exp(-ozone_layer_optical_depth(mu, r));
#else
    return vec3(1.0);
#endif
}

// Chapman diffuse-illumination factor: mean slant amplification of
// isotropically incident light relative to the vertical column
const float ozone_diffuse_airmass = 1.9;


vec3 ozone_multiple_scattering(float order) {
#ifdef ozoneLayer
    return exp(-ozone_extinction * (ozone_diffuse_airmass * order));
#else
    return vec3(1.0);
#endif
}

#endif // INCLUDE_FOG_OVERWORLD_OZONE
