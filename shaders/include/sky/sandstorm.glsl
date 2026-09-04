#if !defined INCLUDE_SKY_SANDSTORM
#define INCLUDE_SKY_SANDSTORM

#include "/include/utility/color.glsl"

// ---------------------------------------------------------------------------
//   Desert sandstorm sky coupling
//
//   The fog side of sandstorms already exists: weather/fog.glsl adds a warm
//   dust density/extinction to the air-fog Mie terms while the storm is
//   active (DESERT_SANDSTORM). But the sky, sunlight, ambient and mist never
//   heard about it — the sun disk stayed white, the zenith stayed blue and
//   the sky-map ambient only mixed toward the storm colour with rain, so a
//   sandstorm looked like brown fog under a clear sky.
//
//   This file is the sky side, mirroring the structure of sky/ozone.glsl:
//   a small analytic dust layer applied differentially on top of the
//   precomputed scattering LUT and inside the analytic transmittance, so
//   every system that asks the atmosphere for light (sunlight, moonlight,
//   sky scattering, planet bounce, mist, sky-map ambient) sees the same
//   warm filtering.
//
//   Integration points, each gated by its own setting:
//    * atmosphere_transmittance() — dust airmass added to the analytic
//      fallback path (DESERT_SANDSTORM + SANDSTORM_LAYER)
//    * atmosphere_scattering() — first-order differential absorption on
//      the precomputed sky LUT along the view and sun/moon light paths
//      (DESERT_SANDSTORM + SANDSTORM_SKY)
//    * sky view path — the pre-LUT celestial background (stars/galaxy/
//      sun disk) is attenuated along the view ray (SANDSTORM_SKY)
//    * mist — the mist tint blends toward the dust spectrum while the
//      storm is active (DESERT_SANDSTORM + SANDSTORM_MIST)
//    * planet bounce — bounced light is re-filtered through the dust on
//      its way back up (DESERT_SANDSTORM + SANDSTORM_BOUNCE)
//
//   Live storm amount comes from the `desert_sandstorm` uniform (0..1),
//   declared by each program — this file deliberately declares no uniforms,
//   following the convention of weather/fog.glsl and atmosphere.glsl.
// ---------------------------------------------------------------------------

#ifdef DESERT_SANDSTORM
// Low dust layer: well-mixed below ~2km, so a ground-level exponential
// with a 1.5km scale height. Grazing rays accumulate much more dust than
// the zenith, which is what turns the whole sky milky-orange.
const float sandstorm_scale_height = 1.5e3; // m

// Warm dust spectrum: absorbs blue, transmits red-orange. Kept modest so
// intensity 1.0 reads as "dusty noon", not "Mars" — the user slider scales
// it from there.
const vec3 sandstorm_extinction_coeff
    = vec3(1.15, 0.75, 0.45) * 2.2e-5;

// Effective storm strength: live 0..1 storm amount scaled by the user
// intensity. Zero when the feature is compiled out.
float sandstorm_strength() {
#ifdef DESERT_SANDSTORM
    return clamp01(desert_sandstorm * DESERT_SANDSTORM_INTENSITY);
#else
    return 0.0;
#endif
}

// Relative airmass of the low exponential dust layer (Chapman-style,
// clamped so the exact horizon saturates instead of diverging).
float sandstorm_airmass(float mu) {
    float x = sandstorm_scale_height / 6371e3;
    float c = sqrt(1.5707963 / max(x, 1e-9));
    float m = c / ((c - 1.0) * mu + 1.0);
    return clamp(m, 0.0, 24.0);
}

// Transmittance of the dust layer along a ray with zenith cosine mu,
// scaled by the live storm strength. Identity when disabled.
vec3 sandstorm_transmittance(float mu) {
#if defined DESERT_SANDSTORM && defined SANDSTORM_LAYER
    float s = sandstorm_strength();
    if (s <= 1e-5) return vec3(1.0);
    return exp(-sandstorm_extinction_coeff * (sandstorm_airmass(mu) * s));
#else
    return vec3(1.0);
#endif
}

// Warm tint of dust-scattered light, for mist and ambient coupling.
vec3 sandstorm_tint() {
    return normalize(vec3(1.0, 0.78, 0.55) + 1e-6);
}
#else
float sandstorm_strength() { return 0.0; }
float sandstorm_airmass(float mu) { return 0.0; }
vec3 sandstorm_transmittance(float mu) { return vec3(1.0); }
vec3 sandstorm_tint() { return vec3(1.0); }
#endif

#endif // INCLUDE_SKY_SANDSTORM
