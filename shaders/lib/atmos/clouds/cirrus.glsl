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

#if !defined INCLUDE_ATMOS_CLOUDS_CIRRUS
#define INCLUDE_ATMOS_CLOUDS_CIRRUS

// 3rd layer: planar cirrus/cirrocumulus clouds

#include "/lib/atmos/clouds/util/common.glsl"

float cirrusDensityProfile(vec2 coord, float altitudeFraction) {
    const float windAngle = cloudsCirrusWindAngle * degree;
    const vec2 windVelocity
        = cloudsCirrusWindSpeed * vec2(cos(windAngle), sin(windAngle));

    coord = coord + cameraPosition.xz * cloudsScale;
    coord = coord + windVelocity * worldAge;

    vec2 curl = curl2D(0.00002 * coord) * 0.5 + curl2D(0.00004 * coord) * 0.25
        + curl2D(0.00008 * coord) * 0.125;

    float heightShaping = 1.0 - abs(1.0 - 2.0 * altitudeFraction);

    // Cirrus

    float densityCirrus = 0.7
            * texture(
                  noisetex,
                  (0.000001 / cloudsCirrusSize) * coord
                      + (0.004 * cloudsCirrusCurlStrength) * curl
            )
                  .x
        + 0.3
            * texture(
                  noisetex,
                  (0.000008 / cloudsCirrusSize) * coord
                      + (0.008 * cloudsCirrusCurlStrength) * curl
            )
                  .x;
    densityCirrus
        = linearStep(0.7 - cloudsParams.cirrusAmount, 1.0, densityCirrus);

    vec2 detailCoord = coord;

    float detailAmplitude = 0.2;
    float detailFrequency = 0.00002;
    float curlStrength = 0.1 * cloudsCirrusCurlStrength;

    for (int i = 0; i < 4; ++i) {
        float detail
            = texture(
                  noisetex,
                  detailCoord * detailFrequency + curl * curlStrength
            )
                  .x;

        densityCirrus -= detail * detailAmplitude;

        detailAmplitude *= 0.6;
        detailFrequency *= 2.0;
        curlStrength *= 4.0;

        detailCoord += 0.3 * windVelocity * worldAge;
    }

    densityCirrus = mix(1.0, 0.75, dayFactor) * cube(max0(densityCirrus))
        * sqr(heightShaping) * cloudsCirrusDensity;

    // Cirrocumulus

    float coverage = texture(
                         noisetex,
                         (0.0000026 / cloudsCirrocumulusSize) * coord + 0.25
    )
                         .w;
    coverage = 5.0
        * linearStep(0.25, 0.9, cloudsParams.cirrocumulusAmount * coverage);

    float densityCirrocumulus
        = dampen(texture(
                     noisetex,
                     (0.000025 * rcp(cloudsCirrocumulusSize)) * coord
                         + (0.033 * cloudsCirrocumulusCurlStrength) * curl
        )
                     .w);
    densityCirrocumulus
        = linearStep(1.0 - coverage, 1.0, densityCirrocumulus);

    vec2 curlCc = curl2D(0.001 * coord);

    densityCirrocumulus
        -= sqr(texture(
                   noisetex,
                   coord * 0.00005
                       + (0.003 * cloudsCirrocumulusCurlStrength) * curlCc
           )
                   .y)
        * (cloudsCirrocumulusDetailStrength * 1.0);
    densityCirrocumulus
        -= sqr(texture(
                   noisetex,
                   coord * 0.0002
                       + (0.007 * cloudsCirrocumulusCurlStrength) * curlCc
           )
                   .y)
        * (cloudsCirrocumulusDetailStrength * 0.5);
    densityCirrocumulus
        -= sqr(texture(
                   noisetex,
                   coord * 0.0008
                       + (0.03 * cloudsCirrocumulusCurlStrength) * curlCc
           )
                   .y)
        * (cloudsCirrocumulusDetailStrength * 0.1);

    densityCirrocumulus = max0(densityCirrocumulus);

    densityCirrocumulus = 0.25 * pow4(max0(densityCirrocumulus))
        * heightShaping * cloudsCirrocumulusDensity;

    return densityCirrus + densityCirrocumulus;
}

float cloudsCirrusOpticalDepth(vec3 rayOrigin, vec3 rayDir, float dither) {
    const uint stepCount = cloudsCirrusLightSteps;
    const float maxRayLength = 1e3;
    const float stepGrowth = 1.5;

    // Assuming rayOrigin is between inner and outer boundary, find distance to
    // closest layer boundary
    vec2 innerSphere = intersectSphere(
        rayOrigin,
        rayDir,
        cloudsCirrusRadius - 0.5 * cloudsCirrusThickness
    );
    vec2 outerSphere = intersectSphere(
        rayOrigin,
        rayDir,
        cloudsCirrusRadius + 0.5 * cloudsCirrusThickness
    );

    float rayLength
        = (innerSphere.y >= 0.0) ? innerSphere.x : outerSphere.y;
    rayLength = min(rayLength, maxRayLength);

    // Find initial step length a so that Σ(ar^i) = rayLength
    float stepCoeff = (stepGrowth - 1.0)
        / (pow(stepGrowth, float(stepCount)) - 1.0) / stepGrowth;
    float stepLength = rayLength * stepCoeff;

    vec3 rayPos = rayOrigin;
    vec4 rayStep = vec4(rayDir, 1.0) * stepLength;

    float opticalDepth = 0.0;

    for (uint i = 0u; i < stepCount; ++i, rayPos += rayStep.xyz) {
        rayStep *= stepGrowth;

        vec3 ditheredPos = rayPos + rayStep.xyz * dither;

        float r = length(ditheredPos);
        float altitudeFraction
            = (r - cloudsCirrusRadius) * rcp(cloudsCirrusThickness) + 0.5;
        if (clamp01(altitudeFraction) != altitudeFraction) {
            continue;
        }

        vec3 spherePos = ditheredPos * (cloudsCirrusRadius / r);

        opticalDepth += cirrusDensityProfile(spherePos.xz, altitudeFraction)
            * rayStep.w;
    }

    return opticalDepth;
}

vec2 cloudsCirrusScattering(
    float density,
    float viewTransmittance,
    float lightOpticalDepth,
    float cosTheta
) {
    vec2 scattering = vec2(0.0);

    float phase = cloudsPhaseSingle(cosTheta);
    vec3 phaseG = vec3(0.6, 0.9, 0.3);

    float powderEffect = 8.0 * (1.0 - exp(-40.0 * density));
    powderEffect = mix(powderEffect, 1.0, pow1d5(cosTheta * 0.5 + 0.5));

    float scatterAmount = cloudsCirrusScatteringCoeff;
    float extinctAmount = cloudsCirrusExtinctionCoeff
        * (1.0
           + 0.5
               * max0(
                   smoothstep(0.0, 0.15, abs(sunDir.y))
                   - smoothstep(0.5, 0.7, cloudsParams.cirrusAmount)
               ));

    for (uint i = 0u; i < 4u; ++i) {
        scattering.x += scatterAmount
            * exp(-extinctAmount * lightOpticalDepth) * phase
            * powderEffect; // direct light
        scattering.y += scatterAmount
            * exp(-0.33 * cloudsCirrusThickness * extinctAmount * density)
            * isotropicPhase; // sky light

        scatterAmount *= 0.5;
        extinctAmount *= 0.25;
        phaseG *= 0.5;

        powderEffect = mix(powderEffect, sqrt(powderEffect), 0.5);

        phase = cloudsPhaseMulti(cosTheta, phaseG);
    }

    float scatteringIntegral
        = (1.0 - viewTransmittance) / cloudsCirrusExtinctionCoeff;
    return scattering * scatteringIntegral;
}

CloudsResult drawCirrusClouds(
    vec3 airViewerPos,
    vec3 rayDir,
    vec3 clearSky,
    float distanceToTerrain,
    float dither
) {
    // Early exit if coverage is 0
    if (cloudsParams.cirrusAmount < eps
        && cloudsParams.cirrocumulusAmount < eps) {
        return cloudsNotHit;
    }

    // ---------------
    //   Ray Casting
    // ---------------

    float r = length(airViewerPos);

    vec2 dists
        = intersectSphere(airViewerPos, rayDir, cloudsCirrusRadius);
    bool planetIntersected
        = intersectSphere(
              airViewerPos,
              rayDir,
              min(r - 10.0, planetRadius)
          )
              .y
        >= 0.0;
    bool terrainIntersected = distanceToTerrain >= 0.0
        && r < cloudsCirrusRadius && distanceToTerrain < dists.y;

    if (dists.y < 0.0 // sphere not intersected
        || planetIntersected
            && r < cloudsCirrusRadius // planet blocking clouds
        || terrainIntersected) {
        return cloudsNotHit;
    }

    float distanceToSphere = (r < cloudsCirrusRadius) ? dists.y : dists.x;
    vec3 spherePos = airViewerPos + rayDir * distanceToSphere;

    // ------------------
    //   Cloud Lighting
    // ------------------

    bool moonlit = sunDir.y < -0.049;
    vec3 lightDir = moonlit ? moonDir : sunDir;
    float cosTheta = dot(rayDir, lightDir);

    float density = cirrusDensityProfile(spherePos.xz, 0.5);
    if (density < eps) {
        return cloudsNotHit;
    }

    float lightOpticalDepth
        = cloudsCirrusOpticalDepth(spherePos, lightDir, dither);
    float viewOpticalDepth = 0.5 * density * cloudsCirrusExtinctionCoeff
        * cloudsCirrusThickness * rcp(abs(rayDir.y) + eps);
    float viewTransmittance = exp(-viewOpticalDepth);

    vec2 scattering = cloudsCirrusScattering(
        density,
        viewTransmittance,
        lightOpticalDepth,
        cosTheta
    );

    // Get main light color for this layer
    float rSq = dot(spherePos, spherePos);
    float rcpR = inversesqrt(rSq);
    float mu = dot(spherePos, lightDir) * rcpR;

    vec3 lightColor
        = sunlightColor * atmosphereTransmittance(spherePos, lightDir);
    lightColor = atmospherePostProcessing(lightColor);
    lightColor *= moonlit ? moonColor : sunColor;

    // Remap the transmittance so that minTransmittance is 0
    vec3 cloudsScattering
        = scattering.x * lightColor + scattering.y * skyColor * 1.41;
    cloudsScattering = cloudsAerialPerspective(
        cloudsScattering,
        viewTransmittance,
        airViewerPos,
        spherePos,
        rayDir,
        clearSky
    );

    return CloudsResult(
        vec4(cloudsScattering, scattering.y),
        viewTransmittance,
        distanceToSphere
    );
}

#endif
