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

#if !defined INCLUDE_BRDF_HAMMON
#define INCLUDE_BRDF_HAMMON

#include "/lib/brdf/fresnel.glsl"

float diffuseHammon(vec3 normal, vec3 viewDir, vec3 lightDir, float roughness) {
    float n_dot_l = max0(dot(normal, lightDir));

    if (n_dot_l <= 0.0) return 0.0;

    float n_dot_v = max0(dot(normal, viewDir));
    float l_dot_v = max0(dot(lightDir, viewDir));

    vec3 halfway = normalize(viewDir + lightDir);
    float n_dot_h = max0(dot(normal, halfway));

    float facing = l_dot_v * 0.5 + 0.5;

    float single_rough = facing * (0.9 - 0.4 * facing)
                       * ((0.5 + n_dot_h) * rcp(max(n_dot_h, 0.02)));
    float single_smooth = 1.05 * fresnelSchlickInverse(0.0, n_dot_l)
                        * fresnelSchlickInverse(0.0, max0(n_dot_v));

    float single = clamp01(mix(single_smooth, single_rough, roughness) * rcp_pi);
    float multi = 0.1159 * roughness;

    return clamp01((multi + single) * n_dot_l);
}

// Clamped Hammon diffuse BRDF, normalized by the cosine lobe the ray was
// drawn from. Used as the multibounce path weight.
float brdfWeight(vec3 normal, vec3 incoming, vec3 outgoing) {
    return clamp(
        diffuseHammon(normal, incoming, outgoing, 1.0)
            / clamp01(dot(outgoing, normal) * rcp_pi),
        0.0, half_pi
    );
}

#endif // INCLUDE_BRDF_HAMMON
