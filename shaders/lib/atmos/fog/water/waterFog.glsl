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

#if !defined INCLUDE_FOG_WATER_FOG_VL
#define INCLUDE_FOG_WATER_FOG_VL

#include "/lib/light/distortion.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

const float maxRayLength = 50.0;

mat2x3 raymarchWaterFog(
    vec3 worldStartPos,
    vec3 worldEndPos,
    bool sky,
    float dither
) {
    const uint minStepCount = 16;
    const uint maxStepCount = 25;
    const float stepCountGrowth = 0.5;

    const vec2 causticsDir0 = vec2(cos(0.5), sin(0.5));
    const vec2 causticsDir1 = vec2(cos(3.0), sin(3.0));

    const vec3 absorptionCoeff
        = vec3(
              waterAbsorptionRUnderwater,
              waterAbsorptionGUnderwater,
              waterAbsorptionBUnderwater
          )
        * rec709ToWorkingColor;
    const vec3 scatteringCoeff = vec3(waterScatteringUnderwater);
    const vec3 extinctionCoeff = absorptionCoeff + scatteringCoeff;

    const uint multipleScatteringIterations = 4;

    vec3 worldDir = worldEndPos - worldStartPos;
    float rayLength;
    lengthNormalize(worldDir, worldDir, rayLength);
    if (sky || rayLength > maxRayLength) {
        rayLength = maxRayLength;
    }

    // Adjust step count based on ray length
    uint stepCount
        = uint(float(minStepCount) + stepCountGrowth * rayLength);
    stepCount = min(stepCount, maxStepCount);

    float stepLength = rayLength * rcp(float(stepCount));
    vec3 worldStep = worldDir * stepLength;

    // Jitter ray origin
    vec3 worldPos = worldStartPos + worldDir * stepLength * dither;

    // Space conversions

    vec3 shadowPos = transform(shadowModelView, worldPos - cameraPosition);
    shadowPos = projectOrtho(shadowProjection, shadowPos);

    vec3 shadowStep = mat3(shadowModelView) * worldStep;
    shadowStep = diagonal(shadowProjection).xyz * shadowStep;

    vec2 causticsPos = (mat3(shadowModelView) * mod(worldPos, 512.0)).xy;
    vec2 causticsStep = (mat3(shadowModelView) * worldStep).xy;

    // Calculations moved out of the loop

    float t = frameTimeCounter * 0.25;
    float skylight = eyeSkylight;

    float LoV = dot(worldDir, lightDir);

    vec3 stepTransmittance = exp(-extinctionCoeff * stepLength);

    vec3 scattering = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    for (int i = 0; i < stepCount; ++i,
             worldPos += worldStep,
             shadowPos += shadowStep,
             causticsPos += causticsStep) {
        vec3 shadowScreenPos = distortShadowSpace(shadowPos) * 0.5 + 0.5;

#if defined shadow && (defined WORLD_OVERWORLD || defined WORLD_END)
        ivec2 shadowTexel = ivec2(
            shadowScreenPos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );
        float depth0 = texelFetch(shadowtex0, shadowTexel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadowTexel, 0).x;
        float shadowVis = step(
            float(clamp01(shadowScreenPos) == shadowScreenPos)
                * shadowScreenPos.z,
            depth1
        );

        // Calculate sunlight transmittance through the volume
        float distanceTraveled = abs(depth0 - shadowScreenPos.z)
            * -shadowProjectionInverse[2].z * rcp(shadowDepthScale);

        // Guess the transmittance to sky using trigonometry
        float distanceTraveledSky = distanceTraveled * lightDir.y;
        distanceTraveledSky = clamp(
            distanceTraveledSky,
            0.0,
            15.0 - 15.0 * eyeSkylight + max0(eyeAltitude - worldPos.y)
        );
#else
#define shadowVis 1.0
#define distanceTraveled 0.0
        float distanceTraveledSky
            = 15.0 - 15.0 * eyeSkylight + max0(eyeAltitude - worldPos.y);
#endif

        vec3 lightTransmittance
            = exp(-extinctionCoeff * distanceTraveled) * shadowVis;
        vec3 skyTransmittance = exp(-extinctionCoeff * distanceTraveledSky);

        // Caustics pattern to create underwater light shafts
        float caustics = 0.67
            * texture(noisetex, (causticsPos + causticsDir0 * t) * 0.02).y;
        caustics += 0.33
            * texture(noisetex, (causticsPos + causticsDir1 * t) * 0.04).y;
        caustics = linearStep(0.4, 0.5, caustics) + 0.15;

        float anisotropy = 1.0;
        float scatteringAmount = 1.0;
        for (uint i = 0u; i < multipleScatteringIterations; ++i) {
            float miePhase
                = 0.7 * henyeyGreensteinPhase(LoV, 0.5 * anisotropy)
                + 0.3 * isotropicPhase;

            // Sunlight/moonlight
            scattering += lightColor * caustics * miePhase
                * lightTransmittance * transmittance * scatteringAmount;

            // Skylight
            scattering += ambientColor * isotropicPhase * transmittance
                * scatteringAmount * skyTransmittance;

            anisotropy *= 0.5;
            scatteringAmount *= 0.5;
            lightTransmittance = sqrt(lightTransmittance);
            skyTransmittance = sqrt(skyTransmittance);
        }

        transmittance *= stepTransmittance;
    }

    scattering
        *= (1.0 - stepTransmittance) * scatteringCoeff / extinctionCoeff;
    transmittance = pow(transmittance, vec3(0.75));

    return mat2x3(scattering, transmittance);
}

#ifdef shadowVis
#undef shadowVis
#endif
#ifdef distanceTraveled
#undef distanceTraveled
#endif

#endif // INCLUDE_FOG_WATER_FOG_VL
