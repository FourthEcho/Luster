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

#if !defined INCLUDE_SKY_CLOUDS_CUMULUS_CONGESTUS
#define INCLUDE_SKY_CLOUDS_CUMULUS_CONGESTUS

// Alternative 1st layer: distant cumulus congestus clouds

#include "/lib/atmos/sky/clouds/core/common.glsl"

const float cloudsCumulusCongestusRadius
    = planetRadius + cloudsCumulusCongestusAltitude;
const float cumulusCongestusLayerThickness
    = cloudsCumulusCongestusAltitude * cloudsCumulusCongestusThickness;
const float cloudsCumulusCongestusTopRadius
    = cloudsCumulusCongestusRadius + cumulusCongestusLayerThickness;
const float cloudsCumulusCongestusDistance = 30000.0;
const float cloudsCumulusCongestusEndDistance = 50000.0;
float cloudsCumulusCongestusExtinctionCoeff = 0.08;
float cloudsCumulusCongestusScatteringCoeff
    = cloudsCumulusCongestusExtinctionCoeff * (1.0 - 0.2 * rainStrength);

// altitudeFraction := 0 at the bottom of the cloud layer and 1 at the top
float cloudsCumulusCongestusAltitudeShaping(
    float density,
    float altitudeFraction
) {
    // Carve egg shape
    density -= sqr(linearStep(0.3, 1.0, altitudeFraction))
        * clamp01(1.0 - 0.2 * cloudsParams.cumulusCongestusBlend);

    // Reduce density at the top and bottom of the cloud
    density *= smoothstep(0.0, 0.1, altitudeFraction);
    density *= smoothstep(0.0, 0.1, 1.0 - altitudeFraction);

    return density;
}

float cloudsCumulusCongestusDensity(vec3 pos) {
    const float windAngle = cloudsCumulusWindAngle * degree;
    const vec2 windVelocity
        = cloudsCumulusWindSpeed * vec2(cos(windAngle), sin(windAngle));

    float r = length(pos);
    if (r < cloudsCumulusCongestusRadius
        || r > cloudsCumulusCongestusTopRadius) {
        return 0.0;
    }

    float altitudeFraction = (r - cloudsCumulusCongestusRadius)
        * rcp(cumulusCongestusLayerThickness);
    float distanceFraction = linearStep(
        cloudsCumulusCongestusDistance,
        cloudsCumulusCongestusEndDistance,
        length(pos.xz)
    );

    pos.xz += cameraPosition.xz * cloudsScale;

    // 2D noise for base shape and coverage
    float noise
        = texture(
              noisetex,
              (0.000003 / cloudsCumulusCongestusSize)
                  * (pos.xz
                     + windVelocity
                         * (worldAge + 50.0 * sqr(altitudeFraction)))
        )
              .w;

    float density = 1.5
        * sqr(linearStep(
            0.75
                - 0.15
                    * clamp01(
                        cloudsParams.cumulusCongestusBlend
                        * cloudsCumulusCongestusCoverage
                    ),
            1.0,
            sqrt(noise)
        ));
    density
        = cloudsCumulusCongestusAltitudeShaping(density, altitudeFraction);
    density *= 4.0 * distanceFraction * (1.0 - distanceFraction);
    density *= linearStep(0.0, 0.3, cloudsParams.cumulusCongestusBlend);

    if (density < eps) {
        return 0.0;
    }

#ifndef PROGRAM_PREPARE
    // Curl noise used to warp the 3D noise into swirling shapes
    vec3 wind = vec3(windVelocity * worldAge, 0.0).xzy;

    // 3D worley noise for detail
    float worley0
        = texture(SAMPLER_WORLEY_SWIRLEY, (pos + 0.2 * wind) * 0.00005).x;
    float worley1
        = texture(SAMPLER_WORLEY_SWIRLEY, (pos + 0.4 * wind) * 0.00023).x;
#else
    const float worley0 = 0.5;

    const float worley1 = 0.5;
#endif

    float detailFade = 0.20 * smoothstep(0.85, 1.0, 1.0 - altitudeFraction)
        - 0.35 * smoothstep(0.05, 0.5, altitudeFraction) + 0.8;

    density -= (7.0 * cloudsCumulusCongestusDetailStrength)
        * sqr(clamp01(1.0 - density)) * cube(worley0) * sqr(altitudeFraction);
    density -= (0.2 * cloudsCumulusCongestusDetailStrength) * sqr(worley1)
        * dampen(clamp01(1.0 - density))
        * dampen(dampen(clamp01(detailFade + 0.5 * sqr(altitudeFraction))));

    // Adjust density so that the clouds are wispy at the bottom and hard at the
    // top
    density = max0(density);
    density = lift(clamp01(density), mix(2.0, 10.0, altitudeFraction));
    density *= sqr(linearStep(0.0, 0.5, altitudeFraction));

    return density;
}

float cloudsCumulusCongestusOpticalDepth(
    vec3 rayOrigin,
    vec3 rayDir,
    float dither,
    const uint stepCount
) {
    const float stepGrowth = 2.0;

    float stepLength
        = 0.1 * cumulusCongestusLayerThickness / float(stepCount); // m

    vec3 rayPos = rayOrigin;
    vec4 rayStep = vec4(rayDir, 1.0) * stepLength;

    float opticalDepth = 0.0;

    for (uint i = 0u; i < stepCount; ++i, rayPos += rayStep.xyz) {
        rayStep *= stepGrowth;
        opticalDepth
            += cloudsCumulusCongestusDensity(rayPos + rayStep.xyz * dither)
            * rayStep.w;
    }

    return opticalDepth;
}

vec2 cloudsCumulusCongestusScattering(
    float density,
    float lightOpticalDepth,
    float skyOpticalDepth,
    float groundOpticalDepth,
    float stepTransmittance,
    float cosTheta,
    float bouncedLight
) {
    vec2 scattering = vec2(0.0);

    float scatterAmount = cloudsCumulusCongestusScatteringCoeff;
    float extinctAmount = cloudsCumulusCongestusExtinctionCoeff;

    float scatteringIntegralTimesDensity = (1.0 - stepTransmittance)
        / cloudsCumulusCongestusExtinctionCoeff;

    float powderEffect = cloudsPowderEffect(2.0 * density, cosTheta);

    float phase = cloudsPhaseSingle(cosTheta);
    vec3 phaseG = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + lightOpticalDepth));

    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatterAmount
            * exp(-extinctAmount * lightOpticalDepth * 0.33) * phase;
        scattering.x += scatterAmount
            * exp(-extinctAmount * groundOpticalDepth * 0.33)
            * isotropicPhase * bouncedLight;
        scattering.y += scatterAmount
            * exp(-extinctAmount * skyOpticalDepth * 0.33) * isotropicPhase;

        scatterAmount *= 0.55
            * mix(lift(
                      clamp01(cloudsCumulusCongestusScatteringCoeff / 0.1),
                      0.33
                  ),
                  1.0,
                  cosTheta * 0.5 + 0.5)
            * powderEffect;
        extinctAmount *= 0.4;
        phaseG *= 0.5;

        powderEffect = mix(powderEffect, sqrt(powderEffect), 0.5);

        phase = cloudsPhaseMulti(cosTheta, phaseG);
    }

    return scattering * scatteringIntegralTimesDensity;
}

CloudsResult drawCumulusCongestusClouds(
    vec3 airViewerPos,
    vec3 rayDir,
    vec3 clearSky,
    float distanceToTerrain,
    float dither
) {
    // ---------------------
    //   Raymarching Setup
    // ---------------------

    const uint primarySteps = cloudsCumulusCongestusPrimarySteps;
    const uint lightingSteps = cloudsCumulusCongestusLightingSteps;
    const uint ambientSteps = cloudsCumulusCongestusAmbientSteps;

    const float minTransmittance = 0.075;

    const float planetAlbedo = 0.4;
    const vec3 skyDir = vec3(0.0, 1.0, 0.0);

    vec2 sphereDists = intersectSphericalShell(
        airViewerPos,
        rayDir,
        cloudsCumulusCongestusRadius,
        cloudsCumulusCongestusTopRadius
    );
    vec2 cylinderDists = intersectCylindricalShell(
        airViewerPos,
        rayDir,
        cloudsCumulusCongestusDistance,
        cloudsCumulusCongestusEndDistance
    );
    vec2 dists = vec2(
        max(sphereDists.x, cylinderDists.x),
        min(sphereDists.y, cylinderDists.y)
    );

    bool planetIntersected
        = intersectSphere(
              airViewerPos,
              rayDir,
              min(length(airViewerPos) - 10.0, planetRadius)
          )
              .y
        >= 0.0;

    if (dists.y < 0.0
        || planetIntersected
            && length(airViewerPos) < cloudsCumulusCongestusRadius
        || distanceToTerrain > 0.0) {
        return cloudsNotHit;
    }

    float rayLength = dists.y - dists.x;
    float stepLength = rayLength * rcp(float(primarySteps));

    vec3 rayStep = rayDir * stepLength;

    vec3 rayOrigin
        = airViewerPos + rayDir * (dists.x + stepLength * dither);

    vec2 scattering = vec2(0.0); // x: direct light, y: skylight
    float transmittance = 1.0;

    float distanceSum = 0.0;
    float distanceWeightSum = 0.0;

    // ------------------
    //   Lighting Setup
    // ------------------

    bool moonlit = sunDir.y < -0.04;
    vec3 lightDir = moonlit ? moonDir : sunDir;
    float cosTheta = dot(rayDir, lightDir);
    float bouncedLight = planetAlbedo * lightDir.y * rcpPi;

    // --------------------
    //   Raymarching Loop
    // --------------------

    for (uint i = 0u; i < primarySteps; ++i) {
        if (transmittance < minTransmittance) {
            break;
        }

        vec3 rayPos = rayOrigin + rayStep * i;

        float altitudeFraction
            = (length(rayPos) - cloudsCumulusCongestusRadius)
            * rcp(cumulusCongestusLayerThickness);

        float density = cloudsCumulusCongestusDensity(rayPos);

        if (density < eps) {
            continue;
        }

        float distanceToSample = distance(rayOrigin, rayPos);

        float stepOpticalDepth
            = density * cloudsCumulusCongestusExtinctionCoeff * stepLength;
        float stepTransmittance = exp(-stepOpticalDepth);

#if defined PROGRAM_DEFERRED0
        vec2 hash = vec2(0.0);
#else
        vec2 hash = hash2(fract(rayPos)); // used to dither the light rays
#endif

        float lightOpticalDepth = cloudsCumulusCongestusOpticalDepth(
            rayPos,
            lightDir,
            hash.x,
            lightingSteps
        );
        float skyOpticalDepth = cloudsCumulusCongestusOpticalDepth(
            rayPos,
            skyDir,
            hash.y,
            ambientSteps
        );
        float groundOpticalDepth
            = mix(density, 1.0, clamp01(altitudeFraction * 2.0 - 1.0))
            * altitudeFraction
            * cumulusCongestusLayerThickness; // guess optical depth to the
                                                  // ground using altitude
                                                  // fraction and density from
                                                  // this sample

        scattering
            += cloudsCumulusCongestusScattering(
                   density,
                   lightOpticalDepth,
                   skyOpticalDepth,
                   groundOpticalDepth,
                   stepTransmittance,
                   cosTheta,
                   bouncedLight
               )
            * transmittance;

        transmittance *= stepTransmittance;

        // Update distance to cloud
        distanceSum += distanceToSample * density;
        distanceWeightSum += density;
    }

    // Get main light color for this layer
    vec3 lightColor
        = sunlightColor * atmosphereTransmittance(rayOrigin, lightDir);
    lightColor = atmospherePostProcessing(lightColor);
    lightColor *= moonlit ? moonColor : sunColor;

    // Remap the transmittance so that minTransmittance is 0
    float cloudsTransmittance
        = linearStep(minTransmittance, 1.0, transmittance);

    // Aerial perspective
    vec3 cloudsScattering
        = scattering.x * lightColor + scattering.y * skyColor;
    cloudsScattering = cloudsAerialPerspective(
        cloudsScattering,
        cloudsTransmittance,
        airViewerPos,
        rayOrigin,
        rayDir,
        clearSky
    );

    // Fade away at the horizon
    float horizonFade = mix(
        dampen(linearStep(0.0, 0.08, rayDir.y)),
        1.0,
        smoothstep(
            sqr(cloudsCumulusCongestusRadius),
            sqr(cloudsCumulusCongestusRadius
                + 0.1 * cumulusCongestusLayerThickness),
            lengthSquared(airViewerPos)
        )
    );
    cloudsScattering = mix(
        clearSky * (1.0 - cloudsTransmittance),
        cloudsScattering,
        horizonFade
    );

    float apparentDistance = (distanceWeightSum == 0.0)
        ? 1e6
        : (distanceSum / distanceWeightSum)
            + distance(airViewerPos, rayOrigin);

    return CloudsResult(
        vec4(cloudsScattering, scattering.y),
        cloudsTransmittance,
        apparentDistance
    );
}

#endif
