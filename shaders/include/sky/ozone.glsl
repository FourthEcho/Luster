#if !defined INCLUDE_SKY_OZONE
#define INCLUDE_SKY_OZONE

#include "/include/utility/color.glsl"

// ---------------------------------------------------------------------------
//   Ozone absorption layer
//
//   A user-tunable stratospheric absorption shell that integrates into the
//   rest of the atmosphere model. Real ozone absorbs in the visible
//   Chappuis bands (400-650nm, broad peak near 575-600nm): it is almost
//   transparent in blue, moderately absorbing in green and red, and most
//   of the column sits in a layer peaking around 20-30km altitude. The
//   effect is subtle at noon but decisive at dawn and dusk, where
//   horizon-grazing light paths amplify the absorption and ozone is
//   responsible for the deep-blue zenith and the warm horizon light of
//   twilight.
//
//   Because the precomputed scattering LUT already bakes in a baseline
//   ozone profile, this layer acts as the adjustable part of the model:
//   it is applied analytically on top of the LUT and inside the analytic
//   transmittance, so every system that asks the atmosphere for light
//   (sunlight, moonlight, cloud lighting, crepuscular rays, planet
//   bounce, air fog, mist) sees the same spectral filtering.
//
//   Integration points, each gated by its own setting:
//    * atmosphere_transmittance() — a dedicated ozone airmass replaces the
//      old "approximate ozone with the Rayleigh airmass" treatment
//      (OZONE_LAYER)
//    * atmosphere_scattering() — first-order differential absorption on
//      the precomputed sky LUT along the view and sun/moon light paths
//      (OZONE_SKY)
//    * air fog — a dedicated ozone-aware multiple-scattering
//      approximation: each scatter order is attenuated for its extra
//      quasi-diffuse passes through the layer (OZONE_FOG)
//    * mist — the mist tint picks up the ozone-filtered twilight
//      spectrum (OZONE_MIST)
//    * planet bounce — diffusely bounced light is filtered through the
//      layer again on its way back up (OZONE_PLANET_BOUNCE)
//
//   This file is deliberately self-contained (no uniforms, no dependency
//   on atmosphere.glsl) so vertex-stage fog parameter setup can use it
//   too.
// ---------------------------------------------------------------------------

// Planet radius, mirroring atmosphere.glsl so the shell geometry below
// uses the same planet model
const float ozone_planet_radius = 6371e3; // m

// Layer geometry. The density profile is a Gaussian peaking at
// OZONE_ALTITUDE with standard deviation OZONE_THICKNESS.
const float ozone_layer_altitude = OZONE_ALTITUDE * 1e3; // m
const float ozone_layer_width = OZONE_THICKNESS * 1e3;   // m

// Chappuis-band absorption coefficients (per metre at unit layer
// density), mirroring atmosphere.glsl's air_ozone_coefficient so the
// layer's spectrum matches the rest of the atmosphere model. Rec. 709
// primaries transformed to the working color space.
const vec3 ozone_absorption_coefficient
    = vec3(8.304280072e-07, 1.314911970e-06, 5.440679729e-08)
    * rec709_to_rec2020;

// Vertical column of the Gaussian layer in unit-density metres, scaled
// by the user amount. A Gaussian with standard deviation w integrates to
// sqrt(pi) * w.
const float sqrt_pi = 1.7724538509;
const float ozone_layer_column = OZONE_AMOUNT * ozone_layer_width * sqrt_pi;

// Vertical optical depth spectrum through the whole layer
const vec3 ozone_extinction
    = ozone_absorption_coefficient * ozone_layer_column;

// Relative airmass of a thin spherical shell at altitude h for a ray
// leaving radius r with zenith cosine mu:
//
//     m = (R + h) / sqrt((R + h)^2 - r^2 * (1 - mu^2))
//
// This is the classic layered-shell curvature factor used for
// stratospheric airmasses in twilight photometry: it reduces to the
// plane-parallel 1/mu for a ground-level shell and saturates at a finite
// stratospheric maximum for horizon-grazing rays instead of diverging
// (~11x the vertical column for the default layer at the exact horizon).
float ozone_shell_airmass(float mu, float r, float h) {
    float top = ozone_planet_radius + h;

    // Guard the discriminant: from inside the shell every outward ray
    // reaches it, so this only protects the mu -> 0, h -> 0 corner
    float b_sq = max(top * top - r * r * (1.0 - mu * mu), 1.0);

    return top * inversesqrt(b_sq);
}

// Density-weighted airmass of the whole Gaussian ozone layer, in units
// of the vertical column. The layer is integrated in five sub-bands
// placed at +/-2 sigma around the peak and weighted by exp(-k^2), so the
// atmosphere curvature is handled explicitly per band rather than
// through a flat 1/mu approximation.
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
#ifdef OZONE_LAYER
    return exp(-ozone_layer_optical_depth(mu, r));
#else
    return vec3(1.0);
#endif
}

// ---------------------------------------------------------------------------
//   Ozone-aware multiple scattering
//
//   Light illuminating the i-th scatter order has bounced i times inside
//   the atmosphere. Each of those bounces adds roughly one more
//   quasi-diffuse pass through the ozone layer, and diffusely incident
//   light accumulates ~1.9x the vertical column of a constituent — the
//   classical Chapman diffuse-illumination factor used for actinic flux.
//   The per-order attenuation is therefore
//
//     exp(-ozone_extinction * 1.9 * order)
//
//   which grows with the order count and is strongest in green and red
//   where the Chappuis bands absorb, so twilight fog and sky lose their
//   green content and shift toward blue. This is the dedicated multiple
//   scattering treatment of the ozone layer: the plain energy-decay loop
//   used before could not reproduce this spectral behaviour.
// ---------------------------------------------------------------------------

// Chapman diffuse-illumination factor: mean slant amplification of
// isotropically incident light relative to the vertical column
const float ozone_diffuse_airmass = 1.9;

// Per-order attenuation factor for ozone-aware multiple scattering.
// `order` is 0 for direct (single) scattering, 1 for the second-order
// term, and so on. Identity when the layer is disabled.
vec3 ozone_multiple_scattering(float order) {
#ifdef OZONE_LAYER
    return exp(-ozone_extinction * (ozone_diffuse_airmass * order));
#else
    return vec3(1.0);
#endif
}

#endif // INCLUDE_SKY_OZONE
