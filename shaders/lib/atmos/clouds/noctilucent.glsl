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

#if !defined INCLUDE_ATMOS_CLOUDS_NOCTILUCENT
#define INCLUDE_ATMOS_CLOUDS_NOCTILUCENT

#include "/lib/atmos/clouds/util/common.glsl"

// 5th layer: noctilucent clouds


float cloudsNoctilucentDensity(vec2 coord, vec3 rayDir) {
    coord *= 0.25;

    vec2 curl = curl2D(0.00002 * coord) * 0.5 + curl2D(0.00004 * coord) * 0.25
        + curl2D(0.00008 * coord) * 0.125;

    float density = dampen(texture(noisetex, 0.000001 * coord + 0.02 * curl).y);

    float detailAmplitude = 0.3;
    float detailFrequency = 0.00001;
    float curlStrength = 0.05;

    for (int i = 0; i < 4; ++i) {
        float detail
            = texture(noisetex, coord * detailFrequency + curl * curlStrength)
                  .y;

        density += detail * detailAmplitude;

        detailAmplitude *= 0.5;
        detailFrequency *= 1.5;
        curlStrength *= 4.0;
    }

    float highlight
        = dampen(texture(noisetex, 0.000004 * coord + 0.02 * curl).y);
    highlight
        -= (1.0 - texture(noisetex, 0.000014 * coord + 0.05 * curl).y) * 0.15;

    density += 2.0 * pow8(max0(highlight));

    return sqr(max0(density)) * cloudsParams.noctilucentAmount;
}

vec4 drawNoctilucentClouds(
    vec3 airViewerPos,
    vec3 rayDir,
    vec3 clearSky
) {
    const vec3 color = 0.35 * vec3(1.5, 2.0, 9.0);
    const float phaseG = 0.8;
    const float extinctionCoeff = 0.001;

    float visibility = pulse(sunDir.y, -0.10, 0.1);

    if (visibility < eps || cloudsParams.noctilucentAmount < eps) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    // ---------------
    //   Ray Casting
    // ---------------

    float r = length(airViewerPos);

    vec2 dists
        = intersectSphere(airViewerPos, rayDir, cloudsNoctilucentRadius);
    bool planetIntersected
        = intersectSphere(
              airViewerPos,
              rayDir,
              min(r - 10.0, planetRadius)
          )
              .y
        >= 0.0;

    if (
        dists.y < 0.0 // sphere not intersected
        || planetIntersected
            && r < cloudsNoctilucentRadius // planet blocking clouds
    ) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    float distanceToSphere = (r < cloudsCirrusRadius) ? dists.y : dists.x;
    vec3 spherePos = airViewerPos + rayDir * distanceToSphere;

    // ------------------
    //   Cloud Lighting
    // ------------------

    float density = cloudsNoctilucentDensity(spherePos.xz, rayDir);
    float transmittance = exp(-extinctionCoeff * density);

    float phase = henyeyGreensteinPhase(dot(rayDir, sunDir), phaseG);
    vec3 scattering = visibility * color * density * phase;
    scattering = cloudsAerialPerspective(
        scattering,
        transmittance,
        airViewerPos,
        spherePos,
        rayDir,
        clearSky
    );

    return vec4(scattering, transmittance);
}

#endif // INCLUDE_ATMOS_CLOUDS_NOCTILUCENT
