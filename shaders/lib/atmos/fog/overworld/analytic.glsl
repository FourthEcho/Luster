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

#if !defined INCLUDE_FOG_AIR_FOG_ANALYTIC
#define INCLUDE_FOG_AIR_FOG_ANALYTIC

#include "/lib/atmos/fog/overworld/constants.glsl"
#include "/lib/lodMod.glsl"
#include "/lib/atmos/atmosphere.glsl"
#include "/lib/util/phaseFunctions.glsl"

vec2 airFogAnalyticAirmass(
    vec3 rayOriginWorld,
    vec3 rayDirectionWorld,
    float rayLength
) {
    // Integral of density function with respect to t

    const vec2 mul = -rcp(airFogFalloffHalfLife);
    const vec2 add = -mul * airFogFalloffStart;

    vec2 a = rayOriginWorld.y * mul + add;
    vec2 p1 = exp2(rayLength * rayDirectionWorld.y * mul + a);
    vec2 p2 = exp2(a);

    // Horizontal rays: the closed form is 0/0 (NaN). Use the limit
    // d -> 0 of (exp2(L*d*m + a) - exp2(a)) / (ln2*m*d) = L * exp2(a).
    if (abs(rayDirectionWorld.y) < 1e-4) {
        return clamp(rayLength * exp2(a), 0.0, rayLength)
            * (0.5 * overworldFogIntensity);
    }

    return clamp(
               (p1 - p2) * rcp(log(2.0) * mul * rayDirectionWorld.y),
               0.0,
               rayLength
           )
        * (0.5 * overworldFogIntensity);
}

mat2x3 airFogAnalytic(
    vec3 rayOriginWorld,
    vec3 rayEndWorld,
    bool sky,
    float skylight,
    float shadowVis,
    vec3 fogAmbient
) {
#ifdef LOD_MOD_ACTIVE
    float fogEnd = float(lodRenderDistance);
#else
    float fogEnd = far;
#endif

    vec3 rayDirectionWorld;
    float rayLength;
    lengthNormalize(
        rayEndWorld - rayOriginWorld,
        rayDirectionWorld,
        rayLength
    );
    rayLength = sky ? fogEnd : rayLength;

    vec2 airmass = airFogAnalyticAirmass(
        rayOriginWorld,
        rayDirectionWorld,
        rayLength
    );
    vec3 opticalDepth = fogParams.rayleighScatteringCoeff * airmass.x
        + fogParams.mieExtinctionCoeff * airmass.y;
    vec3 transmittance = exp(-opticalDepth);
    vec3 scatteringIntegral = (1.0 - transmittance) / max(opticalDepth, eps);

    vec3 rayleighScattering = scatteringIntegral * airmass.x
        * fogParams.rayleighScatteringCoeff;
    vec3 mieScattering
        = scatteringIntegral * airmass.y * fogParams.mieScatteringCoeff;

    float LoV = dot(rayDirectionWorld, lightDir);
    float miePhase = 0.7 * henyeyGreensteinPhase(LoV, fogMieAnisotropy)
        + 0.3 * henyeyGreensteinPhase(LoV, -0.2);

    /*
    // Single scattering
    vec3 scattering  = lightColor * (lightSun * vec2(isotropicPhase,
    miePhase)); scattering += ambientColor * (lightSky *
    vec2(isotropicPhase));
    /*/
    // Multiple scattering
    vec3 scattering = vec3(0.0);
    float scatterAmount = 1.0;
    float anisotropy = 1.0;

    scattering += 2.0 * (rayleighScattering + mieScattering) * isotropicPhase
        * fogAmbient;

    for (int i = 0; i < 4; ++i) {
        float miePhase = 0.7 * henyeyGreensteinPhase(LoV, fogMieAnisotropy * anisotropy)
            + 0.3 * henyeyGreensteinPhase(LoV, -0.2 * anisotropy);

        vec3 orderLight = lightColor;
#if defined ozoneLayer && defined ozoneFog


        orderLight *= ozoneMultipleScattering(float(i));
#endif

        scattering += scatterAmount
            * (rayleighScattering * isotropicPhase
               + mieScattering * miePhase)
            * orderLight * (1.0 - 0.9 * rainStrength) * shadowVis;

        scatterAmount *= 0.5;
        anisotropy *= 0.7;
    }
    //*/

    scattering *= max(skylight, eyeSkylight);
    scattering *= clamp01(1.0 - blindness - darknessFactor);

    // Artifically brighten fog in the early morning and evening (looks nice)
    float eveningGlow
        = 0.75 * linearStep(0.05, 1.0, exp(-300.0 * sqr(sunDir.y + 0.02)));
    scattering += scattering * eveningGlow;

    return mat2x3(max0(scattering), max0(transmittance));
}

// Flat-ambient overload: same march with the global ambient color.
// Used everywhere (sky-map gen, DH water, SSR-hit fog, blend layers).
mat2x3 airFogAnalytic(
    vec3 rayOriginWorld,
    vec3 rayEndWorld,
    bool sky,
    float skylight,
    float shadowVis
) {
    return airFogAnalytic(
        rayOriginWorld,
        rayEndWorld,
        sky,
        skylight,
        shadowVis,
        ambientColor
    );
}

#endif // INCLUDE_FOG_AIR_FOG_ANALYTIC
