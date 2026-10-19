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

#if !defined INCLUDE_ATMOS_CLOUDS_ALTOCUMULUS
#define INCLUDE_ATMOS_CLOUDS_ALTOCUMULUS

// 2nd layer: volumetric altocumulus clouds

#include "/lib/atmos/clouds/utility/common.glsl"
#include "/lib/util/random.glsl"

// altitudeFraction := 0 at the bottom of the cloud layer and 1 at the top
float cloudsAltocumulusAltitudeShaping(
    float density,
    float altitudeFraction
) {
    // Carve egg shape
    density -= smoothstep(0.2, 1.0, altitudeFraction) * 0.6;

    // Reduce density at the bottom of the cloud
    density *= smoothstep(0.0, 0.2, altitudeFraction);

    return density;
}

float altocumulusDensityProfile(vec3 pos) {
    const float windAngle = cloudsAltocumulusWindAngle * degree;
    const vec2 windVelocity = cloudsAltocumulusWindSpeed
        * vec2(cos(windAngle), sin(windAngle));

    float r = length(pos);
    if (r < cloudsAltocumulusRadius || r > cloudsAltocumulusTopRadius) {
        return 0.0;
    }

    float dynamicThickness
        = mix(0.5, 1.0, smoothstep(0.4, 0.6, cloudsParams.l1Coverage.y));
    float altitudeFraction = 0.8 * (r - cloudsAltocumulusRadius)
        * rcp(altocumulusLayerThickness * dynamicThickness);

    pos.xz += cameraPosition.xz * cloudsScale + windVelocity * worldAge;

    vec4 noise = vec4(
        // 2D noise for base shape and coverage
        texture(noisetex, (0.000005 / cloudsAltocumulusSize) * pos.xz + 0.01)
            .x, // cloud coverage
        texture(noisetex, (0.000047 / cloudsAltocumulusSize) * pos.xz + 0.3)
            .wx, // cloud shape
        texture(noisetex, (0.0001 / cloudsAltocumulusSize) * pos.xz + 0.6)
            .w // cloud detail
    );

    // altocumulus
    float densityAc = mix(
        cloudsParams.l1Coverage.x,
        cloudsParams.l1Coverage.y,
        dampen(noise.x)
    );
    densityAc = linearStep(sqr(1.0 - densityAc), 1.0, noise.y);
    densityAc -= 1.9 * sqr(1.0 - noise.w) * dampen(clamp01(1.0 - densityAc));
    densityAc
        = cloudsAltocumulusAltitudeShaping(densityAc, altitudeFraction);

    // altostratus

    float densityAs = cubicSmooth(linearStep(
        0.9 - cloudsParams.l1Coverage.x,
        1.0,
        2.0 * noise.x * cloudsParams.l1Coverage.y
    ));
    densityAs
        = 0.5 * densityAs + 1.0 * densityAs * linearStep(0.3, 0.6, noise.y);
    densityAs = 0.5 * densityAs + densityAs * linearStep(0.3, 0.7, noise.z);
    densityAs = densityAs / (densityAs + 1.0);
    densityAs *= dampen(
        clamp01(2.0 * altitudeFraction)
        * linearStep(0.0, 0.1, altitudeFraction)
        * linearStep(0.0, 0.6, 1.0 - altitudeFraction)
    );
    densityAs = clamp01(densityAs);

    float density
        = mix(densityAc, densityAs, cloudsParams.l1CumulusStratusBlend);

    if (density < eps) {
        return 0.0;
    }

#ifndef PROGRAM_PREPARE
    vec3 wind = vec3(windVelocity * worldAge, 0.0).xzy;

    // 3D worley noise for detail
    float worley
        = texture(SAMPLER_WORLEY_SWIRLEY, (pos + 0.2 * wind) * 0.003).x;
#else
    const float worley = 0.5;
#endif

    density -= (0.2 * cloudsAltocumulusDetailStrength) * sqr(worley)
        * dampen(clamp01(1.0 - density))
        * (1.0 - 0.85 * cloudsParams.l1CumulusStratusBlend);

    // Adjust density so that the clouds are wispy at the bottom and hard at the
    // top
    vec2 edgeSharpening = mix(
        vec2(3.0, 14.0),
        vec2(2.0, 7.0),
        cloudsParams.l1CumulusStratusBlend
    );
    density = max0(density);
    density = lift(
        density,
        mix(edgeSharpening.x, edgeSharpening.y, altitudeFraction)
    );
    density *= 0.1 + 0.9 * smoothstep(0.2, 0.7, altitudeFraction);

    return density;
}

float cloudsAltocumulusOpticalDepth(
    vec3 rayOrigin,
    vec3 rayDir,
    float dither,
    const uint stepCount
) {
    const float stepGrowth = 2.0;

    float stepLength = (0.25 + 0.25 * (timeSunrise + timeSunset))
        * altocumulusLayerThickness / float(stepCount); // m

    vec3 rayPos = rayOrigin;
    vec4 rayStep = vec4(rayDir, 1.0) * stepLength;

    float opticalDepth = 0.0;

    for (uint i = 0u; i < stepCount; ++i, rayPos += rayStep.xyz) {
        rayStep *= stepGrowth;
        opticalDepth
            += altocumulusDensityProfile(rayPos + rayStep.xyz * dither)
            * rayStep.w;
    }

    return opticalDepth;
}

vec2 cloudsAltocumulusScattering(
    float density,
    float lightOpticalDepth,
    float skyOpticalDepth,
    float groundOpticalDepth,
    float extinctionCoeff,
    float scatteringCoeff,
    float stepTransmittance,
    float cosTheta,
    float bouncedLight
) {
    vec2 scattering = vec2(0.0);

    float scatterAmount = scatteringCoeff;
    float extinctAmount = extinctionCoeff;

    float scatteringIntegralTimesDensity
        = (1.0 - stepTransmittance) / extinctionCoeff;

    float powderEffect = cloudsPowderEffect(
        density * (1.5 + 3.5 * cloudsParams.l1CumulusStratusBlend),
        cosTheta
    );

    float phase = cloudsPhaseSingle(cosTheta);
    vec3 phaseG = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + lightOpticalDepth));

    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatterAmount
            * exp(-extinctAmount * lightOpticalDepth) * phase;
        scattering.x += scatterAmount
            * exp(-extinctAmount * groundOpticalDepth) * isotropicPhase
            * bouncedLight;
        scattering.y += scatterAmount
            * exp(-extinctAmount * skyOpticalDepth) * isotropicPhase;

        scatterAmount *= 0.5
            * mix(lift(clamp01(scatteringCoeff / 0.05), 0.33),
                  1.0,
                  cosTheta * 0.5 + 0.5)
            * powderEffect;
        extinctAmount *= 0.45;
        phaseG *= 0.7;

        powderEffect = mix(powderEffect, sqrt(powderEffect), 0.5);

        phase = cloudsPhaseMulti(cosTheta, phaseG);
    }

    return scattering * scatteringIntegralTimesDensity;
}

CloudsResult drawAltocumulusClouds(
    vec3 airViewerPos,
    vec3 rayDir,
    vec3 clearSky,
    float distanceToTerrain,
    float dither
) {
    // ---------------------
    //   Raymarching Setup
    // ---------------------

#if defined PROGRAM_DEFERRED0
    const uint primaryStepsHorizon = cloudsAltocumulusPrimaryStepsH / 2;
    const uint primaryStepsZenith = cloudsAltocumulusPrimaryStepsZ / 2;
#else
    const uint primaryStepsHorizon = cloudsAltocumulusPrimaryStepsH;
    const uint primaryStepsZenith = cloudsAltocumulusPrimaryStepsZ;
#endif
    const uint lightSteps = cloudsAltocumulusLightSteps;
    const uint ambientSteps = cloudsAltocumulusAmbientSteps;
    const float maxRayLength = 2e4;
    const float minTransmittance = 0.075;
    const float planetAlbedo = 0.4;
    const vec3 skyDir = vec3(0.0, 1.0, 0.0);

    // Early exit if coverage is 0
    if (cloudsParams.l1Coverage.y < eps) {
        return cloudsNotHit;
    }

    uint primarySteps = uint(
        mix(primaryStepsHorizon, primaryStepsZenith, abs(rayDir.y))
    );

    float r = length(airViewerPos);

    vec2 dists = intersectSphericalShell(
        airViewerPos,
        rayDir,
        cloudsAltocumulusRadius,
        cloudsAltocumulusTopRadius
    );
    bool planetIntersected
        = intersectSphere(
              airViewerPos,
              rayDir,
              min(r - 10.0, planetRadius)
          )
              .y
        >= 0.0;
    bool terrainIntersected = distanceToTerrain >= 0.0
        && r < cloudsAltocumulusRadius && distanceToTerrain < dists.x;

    if (
        dists.y < 0.0 // volume not intersected
        || planetIntersected
            && r < cloudsAltocumulusRadius // planet blocking clouds
        || terrainIntersected // terrain blocking clouds
    ) {
        return cloudsNotHit;
    }

    float rayLength
        = (distanceToTerrain >= 0.0) ? distanceToTerrain : dists.y;
    rayLength = clamp(rayLength - dists.x, 0.0, maxRayLength);
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

    float highCoverage = linearStep(0.5, 0.6, cloudsParams.l1Coverage.x);

    float extinctionCoeff = mix(0.08, 0.16, dayFactor)
        * cloudsAltocumulusDensity
        * (2.0 - 1.0 * cloudsParams.l1CumulusStratusBlend);
    float scatteringCoeff = extinctionCoeff * mix(1.00, 0.75, rainStrength);

    bool moonlit = sunDir.y < -0.045;
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

        float altitudeFraction = (length(rayPos) - cloudsAltocumulusRadius)
            * rcp(altocumulusLayerThickness);

        float density = altocumulusDensityProfile(rayPos);

        if (density < eps) {
            continue;
        }

        // fade away in the distance to hide the cutoff
        float distanceToSample = distance(rayOrigin, rayPos);
        float distanceFade
            = smoothstep(0.95, 1.0, distanceToSample * rcp(maxRayLength));

        density *= 1.0 - distanceFade;

        float stepOpticalDepth = density * extinctionCoeff * stepLength;
        float stepTransmittance = exp(-stepOpticalDepth);

#if defined PROGRAM_DEFERRED0
        vec2 hash = vec2(0.0);
#else
        vec2 hash = hash2(fract(rayPos)); // used to dither the light rays
#endif

        float lightOpticalDepth = cloudsAltocumulusOpticalDepth(
            rayPos,
            lightDir,
            hash.x,
            lightSteps
        );
        float skyOpticalDepth = cloudsAltocumulusOpticalDepth(
            rayPos,
            skyDir,
            hash.y,
            ambientSteps
        );
        float groundOpticalDepth
            = mix(density, 1.0, clamp01(altitudeFraction * 2.0 - 1.0))
            * altitudeFraction
            * altocumulusLayerThickness; // guess optical depth to the ground
                                            // using altitude fraction and
                                            // density from this sample

        scattering
            += cloudsAltocumulusScattering(
                   density,
                   lightOpticalDepth,
                   skyOpticalDepth,
                   groundOpticalDepth,
                   extinctionCoeff,
                   scatteringCoeff,
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
    lightColor *= 1.0 + 0.4 * highCoverage * dampen(timeNoon);

    // Remap the transmittance so that minTransmittance is 0
    float cloudsTransmittance
        = linearStep(minTransmittance, 1.0, transmittance);

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
