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

#if !defined INCLUDE_FOG_NETHER_FOG_VL
#define INCLUDE_FOG_NETHER_FOG_VL

#include "/lib/light/distortion.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

float netherFogDensity(vec3 worldPos) {
    const float falloffStart = 64.0;
    const float falloffHalfLife = 7.0;

    const float mul = -rcp(falloffHalfLife);
    const float add = -mul * falloffStart;

    float density = exp2(min(worldPos.y * mul + add, 0.0));

    // fade away below the island
    density *= linearStep(0.0, 64.0, worldPos.y);

    return density;
}


vec3 netherWindOffset(vec3 wind, float t) {
    float gustPhase = 2.2 * sin(t * 0.23 + 1.3) + 3.5 * sin(t * 0.071 + 0.5);
    return wind * (3.5 * t + gustPhase);
}

vec3 netherFogEmission(vec3 worldPos) {
    vec3 mainCol;
#ifdef netherUseBiomeColor
    mainCol = srgbEotfInv(clamp(fogColor, 0.0, 1.0)) * rec709ToWorkingColor;
    mainCol /= max(dot(mainCol, luminanceWeights), eps);
    mainCol = mix(vec3(1.0), mainCol, netherS);
#else
    mainCol = gamutExpand(fromDisplay(vec3(netherR, netherG, netherB)));
#endif
    mainCol *= netherI;

    const vec3 altCol = gamutExpand(fromDisplay(vec3(netherR * 0.65, netherG * 0.18, max(netherB * 0.10, 0.002))));
    const vec3 wind0 = vec3(1.0, 0.1, 0.5) * 0.01;
    const vec3 wind1 = vec3(-0.7, -0.1, -0.1) * 0.05;
    const vec3 wind2 = vec3(0.3, 0.05, -0.4) * 0.01;

    float baseNoise = texture(
        colortex0,
        0.02 * worldPos + netherWindOffset(wind0, frameTimeCounter)
    ).x;
    float detailNoise = texture(
        colortex0,
        0.04 * worldPos + netherWindOffset(wind1, frameTimeCounter)
    ).x
            * 0.8
        - 0.4;
    float colorNoise = texture(
        colortex0,
        0.02 * worldPos + 0.2 + netherWindOffset(wind2, frameTimeCounter)
    ).x;

    float density = max0(linearStep(0.6, 0.9, baseNoise) + detailNoise);
    float colorMix = linearStep(0.5, 0.7, colorNoise);

    float viewDist = distance(worldPos, cameraPosition);
    float fadeNear = 1.0 - exp2(-0.1 * viewDist);
    float fadeFar = exp2(-0.05 * viewDist);
    float fadeHeight = exp2(-0.05 * max0(cameraPosition.y - 120.0))
        * linearStep(0.0, 64.0, worldPos.y);

    return mix(mainCol, altCol, colorMix)
        * (density * fadeNear * fadeFar * fadeHeight);
}


#ifdef netherSmoke
vec3 netherSmokeV2Emission(vec3 worldPos, vec3 worldStartPos) {
    vec3 mainCol;
#ifdef netherUseBiomeColor
    mainCol = srgbEotfInv(clamp(fogColor, 0.0, 1.0)) * rec709ToWorkingColor;
    mainCol /= max(dot(mainCol, luminanceWeights), eps);
    mainCol = mix(vec3(1.0), mainCol, netherS);
#else
    mainCol = gamutExpand(fromDisplay(vec3(netherR, netherG, netherB)));
#endif
    mainCol *= netherI;

    // Warm ember color the glow blends toward as smoke gets closer/thicker
    const vec3 emberCol = gamutExpand(fromDisplay(vec3(1.0, 0.35, 0.05)));

    const vec3 wind0 = vec3(1.0, 0.1, 0.5) * 0.01;
    const vec3 wind1 = vec3(-0.7, -0.1, -0.1) * 0.05;


    vec3 warpPos = worldPos * 0.02;
    warpPos += (texture(
        colortex0,
        warpPos * 2.0 + netherWindOffset(wind0, frameTimeCounter)
    ).x * 2.0 - 1.0) * 0.03;
    warpPos += (texture(
        colortex0,
        warpPos * 4.0 + netherWindOffset(wind1, frameTimeCounter)
    ).x * 2.0 - 1.0) * 0.015;

    float baseNoise = texture(
        colortex0,
        warpPos + netherWindOffset(wind0, frameTimeCounter)
    ).x;
    float detailNoise = texture(
        colortex0,
        warpPos * 2.0 + netherWindOffset(wind1, frameTimeCounter)
    ).x * 0.8 - 0.4;

    float heightFade = sqr(1.0 - linearStep(128.0, 256.0, worldPos.y))
        * (exp2(-max0(worldPos.y - 32.0) * 0.02) * 0.6 + 0.4)
        * linearStep(0.0, 64.0, worldPos.y);

    float density = max0(linearStep(0.55, 0.85, baseNoise) + detailNoise) * heightFade;


    float distToCamera = distance(worldPos, worldStartPos);
    float glowProximity = sqrt(clamp01(linearStep(24.0, 4.0, distToCamera)));
    float glow = clamp01((glowProximity * (0.3 + cube(heightFade) * 0.15) - detailNoise) * pi)
        * heightFade;

    float fadeNear = 1.0 - exp2(-0.1 * distToCamera);
    float fadeFar = exp2(-0.05 * distToCamera);

    vec3 col = mix(mainCol, emberCol, glow) * density;
    return col * (fadeNear * fadeFar);
}
#endif

mat2x3 raymarchNetherFog(
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

    vec3 netherColor;
#ifdef netherUseBiomeColor
    netherColor = srgbEotfInv(clamp(fogColor, 0.0, 1.0)) * rec709ToWorkingColor;
    netherColor /= max(dot(netherColor, luminanceWeights), eps);
    netherColor = mix(vec3(1.0), netherColor, netherS);
#else
    netherColor = gamutExpand(fromDisplay(vec3(netherR, netherG, netherB)));
#endif
    const float densityScale = 0.01;
    vec3 absorptionCoeff = exp2(-netherColor) * densityScale;
    const vec3 scatteringCoeff = vec3(1.0) * densityScale;
    vec3 extinctionCoeff = absorptionCoeff + scatteringCoeff;

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


        float billow = mix(
            0.55,
            1.45,
            texture(
                colortex0,
                0.02 * worldPos
                    + netherWindOffset(
                          vec3(0.8, 0.15, 0.4) * 0.01,
                          frameTimeCounter
                      )
            ).x
        );
        float density = netherFogDensity(worldPos) * billow * stepLength;

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

// #ifdef reference so Iris registers the toggle on the settings screen
// (the emission block below selects it through a combined plain "#if").
#ifdef netherFogGlow
#endif
#if defined netherFogGlow || defined endGlow
        // Emission
#ifdef netherSmoke
        scattering
            += 4.0 * netherSmokeV2Emission(worldPos, worldStartPos)
                * stepLength * transmittance * netherSmokeIntensity;
#else
        scattering
            += 4.0 * netherFogEmission(worldPos) * stepLength * transmittance;
#endif
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

#endif // INCLUDE_FOG_NETHER_FOG_VL
