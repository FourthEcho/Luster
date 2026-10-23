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

#if !defined INCLUDE_ATMOS_CLOUDS_CORE_COMMON
#define INCLUDE_ATMOS_CLOUDS_CORE_COMMON

#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/atmos/clouds/util/constants.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/geometry.glsl"
#include "/lib/util/phaseFunctions.glsl"
#include "/lib/util/random.glsl"

uniform float dayFactor;

// ----

struct CloudsResult {
    vec4 scattering; // w = ambient scattering, for lightning flashes
    float transmittance;
    float apparentDistance;
};

const CloudsResult cloudsNotHit = CloudsResult(vec4(0.0), 1.0, 1e5);

// ----

// from https://iquilezles.org/articles/gradientnoise/
vec2 perlinGradient(vec2 coord) {
    vec2 i = floor(coord);
    vec2 f = fract(coord);

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    vec2 g0 = hash2(i + vec2(0.0, 0.0));
    vec2 g1 = hash2(i + vec2(1.0, 0.0));
    vec2 g2 = hash2(i + vec2(0.0, 1.0));
    vec2 g3 = hash2(i + vec2(1.0, 1.0));

    float v0 = dot(g0, f - vec2(0.0, 0.0));
    float v1 = dot(g1, f - vec2(1.0, 0.0));
    float v2 = dot(g2, f - vec2(0.0, 1.0));
    float v3 = dot(g3, f - vec2(1.0, 1.0));

    return vec2(
        g0 + u.x * (g1 - g0) + u.y * (g2 - g0) + u.x * u.y * (g0 - g1 - g2 + g3)
        + // d/dx
        du * (u.yx * (v0 - v1 - v2 + v3) + vec2(v1, v2) - v0) // d/dy
    );
}

vec2 curl2D(vec2 coord) {
    vec2 gradient = perlinGradient(coord);
    return vec2(gradient.y, -gradient.x);
}

float cloudsPhaseSingle(float cosTheta) { // Single scattering phase function
    float forwardsA = kleinNishinaPhase(
        cosTheta,
        2600.0
    ); // this gives a nice glow very close to the sun
    float forwardsB = henyeyGreensteinPhase(cosTheta, 0.8);

    return 0.8
        * max(forwardsA,
              forwardsB) // forwards lobe (max'ing them is completely
                          // nonsensical but it looks nice)
        + 0.2 * henyeyGreensteinPhase(cosTheta, -0.2); // backwards lobe
}

float cloudsPhaseMulti(
    float cosTheta,
    vec3 g
) { // Multiple scattering phase function
    return 0.65 * henyeyGreensteinPhase(cosTheta, g.x) // forwards lobe
        + 0.10 * henyeyGreensteinPhase(cosTheta, g.y) // forwards peak
        + 0.25 * henyeyGreensteinPhase(cosTheta, -g.z); // backwards lobe
}

float cloudsPowderEffect(float density, float cosTheta) {
    float powder = pi * density / (density + 0.15);
    powder = mix(powder, 1.0, 0.8 * sqr(cosTheta * 0.5 + 0.5));

    return powder;
}

vec3 cloudsAerialPerspective(
    vec3 cloudsScattering,
    float cloudsTransmittance,
    vec3 rayOrigin,
    vec3 rayEnd,
    vec3 rayDir,
    vec3 clearSky
) {
    vec3 airTransmittance;

#if cloudsAerialPerspectiveBoost != 0
    rayEnd
        = mix(rayOrigin, rayEnd, float(1 << cloudsAerialPerspectiveBoost));
#endif

    if (lengthSquared(rayOrigin) < lengthSquared(rayEnd)) {
        vec3 trans0 = atmosphereTransmittance(rayOrigin, rayDir);
        vec3 trans1 = atmosphereTransmittance(rayEnd, rayDir);

        airTransmittance = clamp01(trans0 / trans1);
    } else {
        vec3 trans0 = atmosphereTransmittance(rayOrigin, -rayDir);
        vec3 trans1 = atmosphereTransmittance(rayEnd, -rayDir);

        airTransmittance = clamp01(trans1 / trans0);
    }

    // Blend to rain color during rain
    clearSky = mix(
        clearSky,
        skyColor * rcp(tau),
        rainStrength * mix(1.0, 0.9, timeSunrise + timeSunset)
    );
    airTransmittance
        = mix(airTransmittance, vec3(airTransmittance.x), 0.8 * rainStrength);

    return mix(
        (1.0 - cloudsTransmittance) * clearSky,
        cloudsScattering,
        airTransmittance
    );
}

CloudsResult blendLayers(CloudsResult old, CloudsResult new) {
    bool newInFront = new.apparentDistance < old.apparentDistance;

    vec4 scatteringBehind = newInFront ? old.scattering : new.scattering;
    vec4 scatteringInFront = newInFront ? new.scattering : old.scattering;
    float transmittanceInFront
        = newInFront ? new.transmittance : old.transmittance;

    return CloudsResult(
        scatteringInFront + transmittanceInFront * scatteringBehind,
        old.transmittance * new.transmittance,
        min(old.apparentDistance, new.apparentDistance)
    );
}

#endif
