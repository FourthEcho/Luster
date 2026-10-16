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

#if !defined INCLUDE_FOG_OVERWORLD_SANDSTORM
#define INCLUDE_FOG_OVERWORLD_SANDSTORM


#ifdef sandstormLayer
#define SANDSTORM_LAYER_OPTION_ENABLED
#endif
#ifdef sandstormSky
#define SANDSTORM_SKY_OPTION_ENABLED
#endif
#ifdef sandstormMist
#define SANDSTORM_MIST_OPTION_ENABLED
#endif
#ifdef sandstormBounce
#define SANDSTORM_BOUNCE_OPTION_ENABLED
#endif

#include "/lib/util/color.glsl"

#ifdef desertSandstorm


const float sandstorm_scale_height = 1.5e3; // m


const vec3 sandstorm_extinction_coeff
    = vec3(1.15, 0.75, 0.45) * 2.2e-5;

// Effective storm strength: live 0..1 storm amount scaled by the user
// intensity. Zero when the feature is compiled out.
float sandstorm_strength() {
#ifdef desertSandstorm
    return clamp01(desert_sandstorm * desertSandstormIntensity);
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
    if (mu < 0.0) {


        float top = 6371e3 + 4.0 * sandstorm_scale_height;
        float r = 6371e3;
        m = top * inversesqrt(max(top * top - r * r * (1.0 - mu * mu), 1.0));
    }
    return clamp(m, 0.0, 24.0);
}

// Transmittance of the dust layer along a ray with zenith cosine mu,
// scaled by the live storm strength. Identity when disabled.
vec3 sandstorm_transmittance(float mu) {
#if defined desertSandstorm && defined sandstormLayer
    float s = sandstorm_strength();
    if (s <= 1e-5) return vec3(1.0);
    return exp(-sandstorm_extinction_coeff * (sandstorm_airmass(mu) * s));
#else
    return vec3(1.0);
#endif
}

// Warm tint of dust-scattered light, for mist and ambient coupling.
vec3 sandstorm_tint() {
    return gamut_expand(normalize(vec3(1.0, 0.78, 0.55) + 1e-6));
}
#else
float sandstorm_strength() { return 0.0; }
float sandstorm_airmass(float mu) { return 0.0; }
vec3 sandstorm_transmittance(float mu) { return vec3(1.0); }
vec3 sandstorm_tint() { return vec3(1.0); }
#endif

#endif // INCLUDE_FOG_OVERWORLD_SANDSTORM
