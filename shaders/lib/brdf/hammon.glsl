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
    float nDotL = max0(dot(normal, lightDir));

    if (nDotL <= 0.0) return 0.0;

    float nDotV = max0(dot(normal, viewDir));
    float lDotV = max0(dot(lightDir, viewDir));

    vec3 halfway = normalize(viewDir + lightDir);
    float nDotH = max0(dot(normal, halfway));

    float facing = lDotV * 0.5 + 0.5;

    float singleRough = facing * (0.9 - 0.4 * facing)
                       * ((0.5 + nDotH) * rcp(max(nDotH, 0.02)));
    float singleSmooth = 1.05 * fresnelSchlickInverse(0.0, nDotL)
                        * fresnelSchlickInverse(0.0, max0(nDotV));

    float single = clamp01(mix(singleSmooth, singleRough, roughness) * rcpPi);
    float multi = 0.1159 * roughness;

    return clamp01((multi + single) * nDotL);
}

// Clamped Hammon diffuse BRDF, normalized by the cosine lobe the ray was
// drawn from. Used as the multibounce path weight.
float brdfWeight(vec3 normal, vec3 incoming, vec3 outgoing) {
    return clamp(
        diffuseHammon(normal, incoming, outgoing, 1.0)
            / clamp01(dot(outgoing, normal) * rcpPi),
        0.0, halfPi
    );
}

#endif // INCLUDE_BRDF_HAMMON
