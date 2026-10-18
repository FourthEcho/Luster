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

#if !defined INCLUDE_SKY_CLOUDS_CUMULUS
#define INCLUDE_SKY_CLOUDS_CUMULUS

// 1st layer: volumetric cumulus/stratocumulus/stratus clouds

#include "/lib/atmos/sky/clouds/core/common.glsl"
#include "/lib/atmos/sky/clouds/core/coverageMap.glsl"
#include "/lib/util/random.glsl"

// altitudeFraction := 0 at the bottom of the cloud layer and 1 at the top
float cloudsCumulusAltitudeShaping(float density, float altitudeFraction) {
    // Stratus shapes
    if (cloudsParams.l0CumulusStratusBlend > eps) {
        density = mix(
            density,
            clamp01(
                density
                * dampen(
                    clamp01(2.0 * altitudeFraction)
                    * linearStep(0.0, 0.1, altitudeFraction)
                    * linearStep(0.0, 0.6, 1.0 - altitudeFraction)
                )
            ),
            cloudsParams.l0CumulusStratusBlend
        );
    }

    // Carve egg shape
    density -= smoothstep(0.2, 1.0, altitudeFraction)
        * (0.6 - 0.3 * cloudsParams.l0CumulusStratusBlend);

    // Reduce density at the bottom of the cloud
    density *= smoothstep(0.0, 0.2, altitudeFraction);

    return density;
}

float cumulusDensityProfile(vec3 pos) {
    float r = length(pos);

#if defined CLOUDS_USE_LOCAL_COVERAGE_MAP
    // Get local coverage from precomputed coverage map - saves 1 sample and
    // some maths
    vec2 coverageMapUv = projectCloudsCumulusCoverageMap(pos);

    if (r < cloudsCumulusRadius || r > cloudsCumulusTopRadius
        || clamp01(coverageMapUv) != coverageMapUv) {
        return 0.0;
    }

    float density = texture(colortex8, coverageMapUv).z;
#else
    if (r < cloudsCumulusRadius || r > cloudsCumulusTopRadius) {
        return 0.0;
    }

    float density = cloudsCumulusLocalCoverage(pos.xz);
#endif

    // Altitude shaping

    float altitudeFraction
        = (r - cloudsCumulusRadius) * cloudsParams.l0AltitudeScale;

    density = cloudsCumulusAltitudeShaping(density, altitudeFraction);

    if (density < eps) {
        return 0.0;
    }

#if !defined PROGRAM_PREPARE
    const float windAngle = cloudsCumulusWindAngle * degree;
    const vec2 windVelocity
        = cloudsCumulusWindSpeed * vec2(cos(windAngle), sin(windAngle));

    vec3 wind = vec3(windVelocity * worldAge, 0.0).xzy;

    pos.xz += cameraPosition.xz * cloudsScale + wind.xz;

    // 3D curl distortion for natural billowing and variation.
    vec3 curlCoord = (pos + 0.15 * wind) * 0.00065;
    vec3 curl = texture(SAMPLER_CUMULUS_CURL, curlCoord).xyz;
    curl *= 120.0 * (0.35 + 0.65 * smoothstep(0.05, 0.8, altitudeFraction));
    pos += curl;

    // 3D worley noise for detail
    float worley0
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.2 * wind) * 0.0009).x;
    float worley1
        = texture(SAMPLER_WORLEY_SWIRLEY, (pos + 0.4 * wind) * 0.005).x;
#else
    const float worley0 = 0.5;
    const float worley1 = 0.5;
#endif

    float detailFade = 0.20 * smoothstep(0.85, 1.0, 1.0 - altitudeFraction)
        - 0.35 * smoothstep(0.05, 0.5, altitudeFraction) + 0.6;

    density -= cloudsParams.l0DetailWeights.x * sqr(worley0)
        * dampen(clamp01(1.0 - density));
    density -= cloudsParams.l0DetailWeights.y * sqr(worley1)
        * dampen(clamp01(1.0 - density)) * detailFade;

    // Adjust density so that the clouds are wispy at the bottom and hard at the
    // top
    density = max0(density);
    density = lift(
        density,
        mix(cloudsParams.l0EdgeSharpening.x,
            cloudsParams.l0EdgeSharpening.y,
            altitudeFraction)
    );
    density *= 0.1 + 0.9 * smoothstep(0.2, 0.7, altitudeFraction);

    return density;
}

float cloudsCumulusOpticalDepth(
    vec3 rayOrigin,
    vec3 rayDir,
    float dither,
    const uint stepCount
) {
    const float stepGrowth = 2.0;

    float stepLength = 0.1 * cumulusLayerThickness / float(stepCount); // m

    vec3 rayPos = rayOrigin;
    vec4 rayStep = vec4(rayDir, 1.0) * stepLength;

    float opticalDepth = 0.0;

    for (uint i = 0u; i < stepCount; ++i, rayPos += rayStep.xyz) {
        rayStep *= stepGrowth;
        opticalDepth += cumulusDensityProfile(rayPos + rayStep.xyz * dither)
            * rayStep.w;
    }

    return opticalDepth;
}

vec2 cloudsCumulusScattering(
    float density,
    float lightOpticalDepth,
    float skyOpticalDepth,
    float groundOpticalDepth,
    float stepTransmittance,
    float cosTheta,
    float bouncedLight
) {
    vec2 scattering = vec2(0.0);

    float scatterAmount = cloudsParams.l0ScatteringCoeff;
    float extinctAmount = cloudsParams.l0ExtinctionCoeff;

    float scatteringIntegralTimesDensity
        = (1.0 - stepTransmittance) / cloudsParams.l0ExtinctionCoeff;

    float powderEffect = cloudsPowderEffect(
        density + density * cloudsParams.l0CumulusStratusBlend,
        cosTheta
    );
    float scatteringFalloff = 0.55
        * mix(lift(clamp01(cloudsParams.l0ScatteringCoeff / 0.1), 0.33),
              1.0,
              cosTheta * 0.5 + 0.5);

    float phase = cloudsPhaseSingle(cosTheta);
    vec3 phaseG = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + lightOpticalDepth));

    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatterAmount
            * exp(-extinctAmount * lightOpticalDepth) * phase
            * (1.0 - 0.5 * cloudsParams.l0Shadow);
        scattering.x += scatterAmount
            * exp(-extinctAmount * groundOpticalDepth) * isotropicPhase
            * bouncedLight;
        scattering.x += scatterAmount
            * exp(-extinctAmount * skyOpticalDepth) * isotropicPhase
            * cloudsParams.l0Shadow
            * 0.5; // fake bounced lighting from the layer above
        scattering.y += scatterAmount
            * exp(-extinctAmount * skyOpticalDepth) * isotropicPhase;

        scatterAmount *= scatteringFalloff * powderEffect;
        extinctAmount *= 0.4;
        phaseG *= 0.8;

        powderEffect = mix(powderEffect, sqrt(powderEffect), 0.5);

        phase = cloudsPhaseMulti(cosTheta, phaseG);
    }

    return scattering * scatteringIntegralTimesDensity;
}

CloudsResult drawCumulusClouds(
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
    const uint primaryStepsHorizon = cloudsCumulusPrimaryStepsH / 2;
    const uint primaryStepsZenith = cloudsCumulusPrimaryStepsZ / 2;
#else
    const uint primaryStepsHorizon = cloudsCumulusPrimaryStepsH;
    const uint primaryStepsZenith = cloudsCumulusPrimaryStepsZ;
#endif
    const uint lightSteps = cloudsCumulusLightSteps;
    const uint ambientSteps = cloudsCumulusAmbientSteps;
    const float maxRayLength = 2e4;
    const float minTransmittance = 0.075;
    const float planetAlbedo = 0.4;
    const vec3 skyDir = vec3(0.0, 1.0, 0.0);

    // Early exit if coverage is 0
    if (cloudsParams.l0Coverage.y < eps) {
        return cloudsNotHit;
    }

    uint primarySteps = uint(
        mix(primaryStepsHorizon, primaryStepsZenith, abs(rayDir.y))
    );

    float r = length(airViewerPos);

    vec2 dists = intersectSphericalShell(
        airViewerPos,
        rayDir,
        cloudsCumulusRadius,
        cloudsCumulusTopRadius
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
        && r < cloudsCumulusRadius && distanceToTerrain < dists.x;

    if (
        dists.y < 0.0 // volume not intersected
        || planetIntersected
            && r < cloudsCumulusRadius // planet blocking clouds
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

        float altitudeFraction = (length(rayPos) - cloudsCumulusRadius)
            * rcp(cumulusLayerThickness);

        float density = cumulusDensityProfile(rayPos);

        if (density < eps) {
            continue;
        }

        // Fade away in the distance to hide the max ray length cutoff
        float distanceToSample = distance(rayOrigin, rayPos);
        density
            *= smoothstep(1.0, 0.95, distanceToSample * rcp(maxRayLength));

#if defined CLOUDS_USE_LOCAL_COVERAGE_MAP
        // Fade away at the edges of the local coverage map
        density *= smoothstep(
            1.0,
            0.9,
            length(rayPos.xz) * rcp(0.5 * cloudsCumulusCoverageMapScale)
        );
#endif

        float stepOpticalDepth
            = density * cloudsParams.l0ExtinctionCoeff * stepLength;
        float stepTransmittance = exp(-stepOpticalDepth);

#if defined PROGRAM_DEFERRED0
        vec2 hash = vec2(0.0);
#else
        vec2 hash = hash2(fract(rayPos)); // used to dither the light rays
#endif

        float lightOpticalDepth = cloudsCumulusOpticalDepth(
            rayPos,
            lightDir,
            hash.x,
            lightSteps
        );
        float skyOpticalDepth = cloudsCumulusOpticalDepth(
            rayPos,
            skyDir,
            hash.y,
            ambientSteps
        );
        // guess optical depth to the ground using altitude fraction and density
        // from this sample
        float groundOpticalDepth
            = mix(density, 1.0, clamp01(altitudeFraction * 2.0 - 1.0))
            * altitudeFraction * cumulusLayerThickness;

        scattering
            += cloudsCumulusScattering(
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
