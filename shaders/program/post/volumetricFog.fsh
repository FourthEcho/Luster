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

#include "/lib/global.glsl"

layout(location = 0) out vec3 fogTransmittance;
layout(location = 1) out vec3 fogScattering;

/* RENDERTARGETS: 6,7 */

in vec2 uv;

flat in vec3 ambientColor;
flat in vec3 lightColor;

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/overworld/params.glsl"
flat in OverworldFogParams fogParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler3D colortex0; // 3D worley noise
uniform sampler2D colortex1; // gbuffer data
uniform sampler2D colortex4; // sky map (SH projection helper needs it declared)
uniform sampler2D colortex8; // cloud shadow map

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#ifdef shadow
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
#ifdef shadowColor
uniform sampler2D shadowcolor0;
#endif
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 fogColor;

uniform float near;
uniform float far;

uniform float blindness;
uniform float darknessFactor;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float wetness;

uniform float sunAngle;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;

uniform float worldAge;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float eyeSkylight;
uniform float desertSandstormWeather;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

// ------------
//   Includes
// ------------

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/overworld/raymarched.glsl"
#endif

#if defined WORLD_END

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
#endif

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
        // Emission (mandatory)
        scattering
            += 4.0 * netherSmokeV2Emission(worldPos, worldStartPos)
                * stepLength * transmittance;
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
#include "/lib/util/lodMod.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

void main() {
    ivec2 fogTexel = ivec2(gl_FragCoord.xy);
    ivec2 viewTexel
        = ivec2(gl_FragCoord.xy * taauViewportScale * rcp(0.50));

    float depth0 = texelFetch(depthtex0, viewTexel, 0).x;
    float depth1 = texelFetch(depthtex1, viewTexel, 0).x;
    vec4 gbufferData0 = texelFetch(colortex1, viewTexel, 0);

#ifdef LOD_MOD_ACTIVE
    mat4 projectionMatrix, projectionMatrixInverse;
    bool isLod;
    float depthLod = texelFetch(lodDepthTex, viewTexel, 0).x;

    if (depth0 == 1.0) {
        isLod = true;
        depth0 = depthLod;
        depth1 = depthLod;
        projectionMatrix = lodProjectionMatrix;
        projectionMatrixInverse = lodProjectionMatrixInverse;
    } else {
        isLod = false;
        projectionMatrix = gbufferProjection;
        projectionMatrixInverse = gbufferProjectionInverse;
    }
#else
#define isLod false
#define projectionMatrix gbufferProjection
#define projectionMatrixInverse gbufferProjectionInverse
#endif

    float skylight = unpackUnorm2x8(gbufferData0.w).y;

    vec3 viewPos = screenToViewSpace(
        projectionMatrixInverse,
        vec3(uv, depth0),
        true
    );
    vec3 scenePos = viewToSceneSpace(viewPos);
    vec3 worldPos = scenePos + cameraPosition;

    vec3 viewBackPos = screenToViewSpace(vec3(uv, depth1), true);
    vec3 sceneBackPos = viewToSceneSpace(viewBackPos);
    vec3 worldBackPos = sceneBackPos + cameraPosition;


    // Replaces the old white-noise noisetex tap.
    float dither = interleavedGradientNoise(vec2(fogTexel), frameCounter);

    vec3 worldStartPos = gbufferModelViewInverse[3].xyz + cameraPosition;
    vec3 worldEndPos = worldPos;

    // Volumetric lighting

#if defined vl
    switch (isEyeInWater) {
        case 0:
#if defined WORLD_OVERWORLD
            mat2x3 fog = raymarchAirFog(
                worldStartPos,
                worldEndPos,
                depth0 == 1.0,
                skylight,
                dither
            );
#elif defined WORLD_NETHER
            mat2x3 fog = raymarchNetherFog(
                worldStartPos,
                worldEndPos,
                depth0 == 1.0,
                dither
            );
#elif defined WORLD_END
            mat2x3 fog = raymarchEndFog(
                worldStartPos,
                worldEndPos,
                depth0 == 1.0,
                dither
            );
#endif

            fogScattering = fog[0];
            fogTransmittance = fog[1];

            break;

        case 1:
            mat2x3 waterFog = raymarchWaterFog(
                worldStartPos,
                worldEndPos,
                depth0 == 1.0,
                dither
            );

            fogScattering = waterFog[0];
            fogTransmittance = waterFog[1];

            break;

        default:
            fogScattering = vec3(0.0);
            fogTransmittance = vec3(1.0);

            break;

        // Prevent potential game crash due to empty switch statement
        case -1:
            break;
    }
#else
    fogScattering = vec3(0.0);
    fogTransmittance = vec3(1.0);
#endif

}
