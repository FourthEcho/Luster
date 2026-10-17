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

#if !defined INCLUDE_FOG_END_FOG_VL
#define INCLUDE_FOG_END_FOG_VL

#include "/lib/light/distortion.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

float endFogDensity(vec3 worldPos) {
    const float falloffStart = 64.0;
    const float falloffHalfLife = 7.0;

    const float mul = -rcp(falloffHalfLife);
    const float add = -mul * falloffStart;

    float density = exp2(min(worldPos.y * mul + add, 0.0));

    // fade away below the island
    density *= linearStep(0.0, 64.0, worldPos.y);

    return density;
}

vec3 endFogEmission(vec3 worldPos) {
    const vec3 mainCol
        = gamutExpand(fromDisplay(vec3(endAmbientR, endAmbientG, endAmbientB)))
        * endAmbientI;
    const vec3 altCol = gamutExpand(0.5 * vec3(0.25, 1.0, 0.5));
    const vec3 wind0 = vec3(1.0, 0.1, 0.5) * 0.01;
    const vec3 wind1 = vec3(-0.7, -0.1, -0.1) * 0.05;

    float baseNoise
        = texture(colortex0, 0.02 * worldPos + wind0 * frameTimeCounter).x;
    float detailNose
        = texture(colortex0, 0.04 * worldPos + wind1 * frameTimeCounter).x
            * 0.8
        - 0.4;
    float colorNoise = texture(colortex0, 0.02 * worldPos + 0.2).x;

    float density = max0(linearStep(0.6, 0.9, baseNoise) + detailNose);
    float colorMix = linearStep(0.5, 0.7, colorNoise);

    float viewDist = distance(worldPos, cameraPosition);
    float fadeNear = 1.0 - exp2(-0.1 * viewDist);
    float fadeFar = exp2(-0.05 * viewDist);
    float fadeHeight = exp2(-0.05 * (max0(cameraPosition.y - 120.0)))
        * linearStep(0.0, 64.0, worldPos.y);

    return mix(mainCol, altCol, colorMix)
        * (density * fadeNear * fadeFar * fadeHeight);
}

mat2x3 raymarchEndFog(
    vec3 worldStartPos,
    vec3 worldEndPos,
    bool sky,
    float dither
) {
    const uint minStepCount = 16;
    const uint maxStepCount = 25;
    const float volumeTop = 256.0;
    const float volumeBottom = 0.0;
    const float stepCountGrowth = 0.5;

    const vec3 endColor
        = gamutExpand(fromDisplay(vec3(endAmbientR, endAmbientG, endAmbientB)));
    const float densityScale = 0.01;
    const vec3 absorptionCoeff = exp2(-endColor) * densityScale;
    const vec3 scatteringCoeff = vec3(1.0) * densityScale;
    const vec3 extinctionCoeff = absorptionCoeff + scatteringCoeff;

    const uint multipleScatteringIterations = 4;

    vec3 worldDir = worldEndPos - worldStartPos;
    float rayLength;
    lengthNormalize(worldDir, worldDir, rayLength);

    float distanceToLowerPlane = (volumeBottom - eyeAltitude) / worldDir.y;
    float distanceToUpperPlane = (volumeTop - eyeAltitude) / worldDir.y;
    float distanceToVolumeStart, distanceToVolumeEnd;

    if (eyeAltitude < volumeBottom) {
        // Below volume
        distanceToVolumeStart = distanceToLowerPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? -1.0 : distanceToUpperPlane;
    } else if (eyeAltitude < volumeTop) {
        // Inside volume
        distanceToVolumeStart = 0.0;
        distanceToVolumeEnd = worldDir.y < 0.0
            ? distanceToLowerPlane
            : distanceToUpperPlane;
    } else {
        // Above volume
        distanceToVolumeStart = distanceToUpperPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? distanceToUpperPlane : -1.0;
    }

    if (distanceToVolumeEnd < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    rayLength = sky ? distanceToVolumeEnd : rayLength;
    rayLength = clamp(rayLength - distanceToVolumeStart, 0.0, far);

    // Adjust step count based on ray length
    uint stepCount
        = uint(float(minStepCount) + stepCountGrowth * rayLength);
    stepCount = min(stepCount, maxStepCount);

    float stepLength = rayLength * rcp(float(stepCount));
    vec3 worldStep = worldDir * stepLength;

    // Jitter ray origin
    vec3 worldPos = worldStartPos
        + worldDir * (distanceToVolumeStart + stepLength * dither);

    // Space conversions

    vec3 shadowPos = transform(shadowModelView, worldPos - cameraPosition);
    shadowPos = projectOrtho(shadowProjection, shadowPos);

    vec3 shadowStep = mat3(shadowModelView) * worldStep;
    shadowStep = diagonal(shadowProjection).xyz * shadowStep;

    // Calculations moved out of the loop

    float LoV = dot(worldDir, lightDir);

    vec3 scattering = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    for (int i = 0; i < stepCount;
         ++i, worldPos += worldStep, shadowPos += shadowStep) {
        vec3 shadowScreenPos = distortShadowSpace(shadowPos) * 0.5 + 0.5;

#ifdef shadow
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
#else
#define shadowVis 1.0
#endif

        float density = endFogDensity(worldPos) * stepLength;

        vec3 stepOpticalDepth = extinctionCoeff * density;
        vec3 stepTransmittance = exp(-stepOpticalDepth);
        vec3 stepTransmittedFraction
            = (1.0 - stepTransmittance) / max(stepOpticalDepth, eps);

        vec3 visibleScattering = stepTransmittedFraction * transmittance;

        float anisotropy = 1.0;
        float scatteringAmount = 1.0;
        for (uint i = 0u; i < multipleScatteringIterations; ++i) {
            float miePhase
                = 0.7 * henyeyGreensteinPhase(LoV, 0.5 * anisotropy)
                + 0.3 * isotropicPhase;

            // Sunlight
            scattering += density * lightColor * miePhase * shadowVis
                * visibleScattering * scatteringAmount;

            // Ambient light
            scattering += density * ambientColor * isotropicPhase
                * visibleScattering * scatteringAmount;

            anisotropy *= 0.5;
            scatteringAmount *= 0.5;
        }

#ifdef endGlow
        // Emission
        scattering
            += 4.0 * endFogEmission(worldPos) * stepLength * transmittance * 1.00;
#endif

        transmittance *= stepTransmittance;
    }

    scattering *= scatteringCoeff;
    transmittance = pow(transmittance, vec3(0.75));

    return mat2x3(scattering, transmittance);
}

#ifdef shadowVis
#undef shadowVis
#endif

#endif // INCLUDE_FOG_END_FOG_VL
