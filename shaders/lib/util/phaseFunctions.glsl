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

#if !defined INCLUDE_UTILITY_PHASE_FUNCTIONS
#define INCLUDE_UTILITY_PHASE_FUNCTIONS

#include "/lib/util/fastMath.glsl"

const float isotropic_phase = 0.25 / pi;

float henyey_greenstein_phase(float nu, float g) {
    float gg = g * g;

    return (isotropic_phase - isotropic_phase * gg)
        / pow1d5(1.0 + gg - 2.0 * g * nu);
}

float cornette_shanks_phase(float nu, float g) {
    float gg = g * g;

    float p1 = 1.5 * (1.0 - gg) / (2.0 + gg);
    float p2 = (1.0 + nu * nu) / pow1d5((1.0 + gg - 2.0 * g * nu));

    return p1 * p2 * isotropic_phase;
}

// Far closer to an actual aerosol phase function than Henyey-Greenstein or
// Cornette-Shanks
float klein_nishina_phase(float nu, float e) {
    return e / (tau * (e - e * nu + 1.0) * log(2.0 * e + 1.0));
}

float klein_nishina_phase_area(float nu, float e, float radius) {
    float radius_eff = max(radius, eps); // Prevent divide by 0
    float cosr = cos(radius_eff);
    float sinr = sin(radius_eff);
    // shifted cosine with clamp to avoid dark hole
    float mu = nu * cosr + sqrt(max(0.0, 1.0 - nu * nu)) * sinr;
    if (nu > cosr) {
        mu = 1.0; // keep center bright
    }
    return e / (tau * (e - e * mu + 1.0) * log(2.0 * e + 1.0));
}


float nvidia_phase_area(float nu, float g, float a, float radius) {
    float radius_eff = max(radius, eps); // Prevent divide by 0
    float cosr = cos(radius_eff);
    float sinr = sin(radius_eff);
    float mu = nu * cosr + sqrt(max(0.0, 1.0 - nu * nu)) * sinr;
    if (nu > cosr) {
        mu = 1.0; // keep center bright
    }
    float gg = g * g;
    return ((1 - gg) * (1 + a * mu * mu))
        / (pi * pow1d5(1 + gg - (2 * g * mu)) * 4.0
           * (1 + (a * (1 + 2 * gg)) / 3.0));
}


#endif // INCLUDE_UTILITY_PHASE_FUNCTIONS
