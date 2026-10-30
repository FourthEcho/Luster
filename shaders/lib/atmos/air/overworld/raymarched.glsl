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

#if !defined INCLUDE_ATMOS_AIR_OVERWORLD_VL
#define INCLUDE_ATMOS_AIR_OVERWORLD_VL

#include "/lib/atmos/air/overworld/constants.glsl"
#include "/lib/util/phaseFunctions.glsl"
// Needed early: the ground mist couples with the ozone and sandstorm media
#include "/lib/atmos/air/overworld/aerosols.glsl"
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/clouds/util/constants.glsl"
#include "/lib/util/bicubic.glsl"

const ivec2 cloudShadowRes = ivec2(512);

const float cloudShadowExtent = 256.0 / (cloudsScale / 10.0);

vec2 shadowViewToCloudShadowSpace(vec3 shadowViewPos) {
    vec2 cloudShadowPos = shadowViewPos.xy / cloudShadowExtent;
    cloudShadowPos /= 1.0 + length(cloudShadowPos);
    cloudShadowPos = cloudShadowPos * 0.5 + 0.5;

    return cloudShadowPos;
}

vec2 projectCloudShadowMap(vec3 scenePos) {
    return shadowViewToCloudShadowSpace(
        transform(shadowModelView, scenePos)
    );
}

vec3 unprojectCloudShadowMap(vec2 cloudShadowPos) {
    cloudShadowPos = cloudShadowPos * 2.0 - 1.0;
    cloudShadowPos /= 1.0 - length(cloudShadowPos);

    vec3 shadowViewPos = vec3(cloudShadowPos * cloudShadowExtent, 1.0);

    return transform(shadowModelViewInverse, shadowViewPos);
}

float getCloudShadows(sampler2D cloudShadowMap, vec3 scenePos) {
#ifndef cloudShadows
    return 1.0;
#else
    vec2 cloudShadowPos = projectCloudShadowMap(scenePos)
        * vec2(cloudShadowRes) / vec2(textureSize(cloudShadowMap, 0));

    if (clamp01(cloudShadowPos) != cloudShadowPos) {
        return 1.0;
    }

    // fade out cloud shadows when:
    //  - the fragment is above the cloud layer
    //  - the sun is near the horizon
    float r = planetRadius
        + (scenePos.y + eyeAltitude - 63.0) * cloudsScale;
    float altitudeFraction
        = linearStep(cloudsCumulusRadius, cloudsCumulusTopRadius, r);
    float cloudShadowFade = smoothstep(0.05, 0.15, lightDir.y)
        * clamp01(1.0 - altitudeFraction);

    float cloudShadow = bicubicFilter(cloudShadowMap, cloudShadowPos).x;
    cloudShadow = cloudShadow * cloudShadowFade + (1.0 - cloudShadowFade);

    return cloudShadow * cloudShadowsIntensity
        + (1.0 - cloudShadowsIntensity);
#endif
}

#if defined PROGRAM_PREPARE && defined cloudShadows
#include "/lib/atmos/clouds/altocumulus.glsl"
#include "/lib/atmos/clouds/cirrus.glsl"
#include "/lib/atmos/clouds/cumulus.glsl"
#include "/lib/atmos/clouds/cumulusCongestus.glsl"

vec2 renderCloudShadowMap(vec2 uv) {
    // Transform position from scene-space to clouds-space
    vec3 rayOrigin = unprojectCloudShadowMap(uv);
    rayOrigin = vec3(rayOrigin.xz, rayOrigin.y + eyeAltitude - 63.0).xzy
            * cloudsScale
        + vec3(0.0, planetRadius, 0.0);

    vec3 pos;
    float t, density, extinctionCoeff;
    float shadowVis = 1.0;
    float shadowCumulusOnly = 1.0;
    float distanceFade;
    float distanceFadeStrength = 0.00000001 * pulse(lightDir.y, -0.01, 0.2);

#ifdef cloudsCumulus
    extinctionCoeff = 0.25 * cloudsParams.l0ExtinctionCoeff;
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsCumulusRadius + 0.25 * cumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * cumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
    shadowCumulusOnly = shadowVis;
#endif

#ifdef cloudsAltocumulus
    extinctionCoeff = mix(0.05, 0.1, dayFactor) * cloudsAltocumulusDensity
        * (1.0 - 0.33 * rainStrength);
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsAltocumulusRadius + 0.5 * altocumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = altocumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * altocumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
#endif

#ifdef cloudsCirrus
    t = intersectSphere(rayOrigin, lightDir, cloudsCirrusRadius).y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cirrusDensityProfile(pos.xz, 0.5);
    shadowVis *= exp(-1.00 * distanceFade * cloudsCirrusExtinctionCoeff
                  * cirrusLayerThickness * rcp(abs(lightDir.y) + eps)
                  * density)
            * 0.5
        + 0.5;
#endif

    return vec2(shadowVis, shadowCumulusOnly);
}
#endif
#endif // INCLUDE_LIGHT_CLOUD_SHADOWS
#endif

#if defined(LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS)
// Directional lightmap modulation.
#if !defined INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS

// Based on Ninjamike's implementation in shaderLABS #snippets

vec2 getDirectionalLightmaps(vec3 positionScene, vec3 normal) {
    vec2 lightmapMul = vec2(1.0);

    vec2 lightmapGradient;
    vec3 lightmapDir;
    mat2x3 posGradient = mat2x3(dFdx(positionScene), dFdy(positionScene));

    // Blocklight

    lightmapGradient = vec2(dFdx(lightLevels.x), dFdy(lightLevels.x));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.x = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.x, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.x = mix(
            1.0,
            lightmapMul.x,
            sqr(linearStep(0.03, 0.30, lightLevels.x))
        );
    }

    // Skylight

    lightmapGradient = vec2(dFdx(lightLevels.y), dFdy(lightLevels.y));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.y = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.y, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.y = mix(
            1.0,
            lightmapMul.y,
            sqr(linearStep(0.03, 0.30, lightLevels.y))
        );
    }

    return lightmapMul;
}

#endif // INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS
#endif


#undef LUSTER_INCLUDE_CLOUD_SHADOWS
// ---- Ground mist ----

// Position hashing for the mist volume: lattice value noise keeps the layer
// solid in every direction, where a 2D texture would extrude the pattern
// into vertical curtains when seen edge-on.
float mistHash(vec3 cell) {
    cell = fract(cell * 0.3183099 + vec3(0.11, 0.37, 0.53));
    cell *= 17.0;
    return fract(cell.x * cell.y * cell.z * (cell.x + cell.y + cell.z));
}

float mistValueNoise(vec3 pos) {
    vec3 cell = floor(pos);
    vec3 blend = fract(pos);
    blend = blend * blend * (3.0 - 2.0 * blend); // smooth Hermite falloff

    float n000 = mistHash(cell);
    float n100 = mistHash(cell + vec3(1.0, 0.0, 0.0));
    float n010 = mistHash(cell + vec3(0.0, 1.0, 0.0));
    float n110 = mistHash(cell + vec3(1.0, 1.0, 0.0));
    float n001 = mistHash(cell + vec3(0.0, 0.0, 1.0));
    float n101 = mistHash(cell + vec3(1.0, 0.0, 1.0));
    float n011 = mistHash(cell + vec3(0.0, 1.0, 1.0));
    float n111 = mistHash(cell + vec3(1.0, 1.0, 1.0));

    return mix(
        mix(mix(n000, n100, blend.x), mix(n010, n110, blend.x), blend.y),
        mix(mix(n001, n101, blend.x), mix(n011, n111, blend.x), blend.y),
        blend.z
    );
}

float mistDensityProfile(vec3 worldPos) {
    // Two octaves of drifting value noise, plus a dust octave while a
    // sandstorm rages.
    float drift = frameTimeCounter * 0.006;
    vec3 wind = vec3(drift, 0.0, drift * 0.5);

    float noise = mistValueNoise(worldPos * 0.03 + wind)
        + mistValueNoise(worldPos * 0.06 + wind * pi) * 0.5;

#ifdef desertSandstorm
    if (sandstormStrength() > 0.1) {
        noise += smoothstep(0.0, 1.0,
            mistValueNoise(worldPos * 0.08 + wind * sqrPi)
        ) * 0.3 * sandstormStrength();
    }
#endif

    float altitude = worldPos.y;

    // Exponential falloff above sea level: the falloff multiplier sets how
    // quickly the layer thins with altitude.
    float envelope = exp(
        -max0(altitude - (63.0 + mistSeaLevelBias)) * 0.01 * mistFalloff
    );

    // The noise cuts holes into thin mist, and the layer solidifies as the
    // envelope thickens: the envelope itself sets the noise threshold.
    float density = smoothstep(
        0.4,
        0.7,
        noise * rcp(1.5) - (1.0 - envelope) * 0.5
    );

    // Hard cap: fade out below the ceiling with a wide band.
    density *= sqr(1.0 - linearStep(
        float(mistAltitude) - 15.0,
        float(mistAltitude),
        altitude
    ));

    return density;
}

// The mist lobe, recomputed for every multiple-scattering order: the aniso-
// tropy narrows by half each order so the deeper bounces stay open and
// diffuse instead of piling up in the forward peak.
float mistOrderPhase(float cosTheta, float orderScale) {
    float g = fogMieAnisotropy * orderScale * mistMieAnisotropy;

    return mix(
        cornetteShanksPhase(cosTheta, g),
        henyeyGreensteinPhase(cosTheta, -g * rcpPi),
        mistMieAnisotropy * 0.25
    );
}

#ifdef fogMistAdvanced
// Phase shaped by the optical depth crossed toward the sun: mist the sun
// light has passed through cheapens the forward glow, reading as true
// multiple scattering.
float mistDepthPhase(float cosTheta, float opticalDepth) {
    return mix(
        cornetteShanksPhase(cosTheta, pow(fogMieAnisotropy, 1.0 + opticalDepth)),
        henyeyGreensteinPhase(cosTheta, -fogMieAnisotropy * rcpPi),
        0.19
    );
}

// Optical depth of the mist between a sample and the sun: fixed-length steps
// along the light direction, skipped once the ray climbs above the ceiling
// or below the world.
float mistLightOd(vec3 worldPos) {
    const float stepSize = 12.0;
    float od = 0.0;

    vec3 pos = worldPos;
    for (int i = 0; i < mistLightingSteps; ++i) {
        if (pos.y > float(mistAltitude) || pos.y < 0.0) {
            pos += lightDir * stepSize;
            continue;
        }

        float density = mistDensityProfile(pos);
        if (density > 0.0) od += density * stepSize;

        pos += lightDir * stepSize;
    }

    return od;
}
#endif // fogMistAdvanced
#include "/lib/light/direct/distortion.glsl"
#include "/lib/util/lodMod.glsl"
#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

vec2 airFogDensity(vec3 worldPos) {
    const vec2 mul = -rcp(airFogFalloffHalfLife);
    const vec2 add = -mul * airFogFalloffStart;

    vec2 density = exp2(min(worldPos.y * mul + add, 0.0));

    // fade away below sea level
    density *= linearStep(airFogVolumeBottom, 63.0, worldPos.y);

#ifdef airFogCloudyNoise
    const vec3 wind = 0.0003 * vec3(1.0, 0.0, 0.7);

    float noise
        = texture(noisetex, 0.001 * worldPos.xz + wind.xz * frameTimeCounter)
              .w;

    density.y *= 4.0 * sqr(noise);
#endif

    return density * (0.5 * overworldFogIntensity);
}

mat2x3 raymarchAirFog(
    vec3 worldStartPos,
    vec3 worldEndPos,
    bool sky,
    float skylight,
    float dither
) {
    vec3 worldDir = worldEndPos - worldStartPos;

    float lengthSq = lengthSquared(worldDir);
    float norm = inversesqrt(lengthSq);
    float rayLength = lengthSq * norm;
    worldDir *= norm;

    vec3 shadowStartPos
        = transform(shadowModelView, worldStartPos - cameraPosition);
    shadowStartPos = projectOrtho(shadowProjection, shadowStartPos);

    vec3 shadowDir = mat3(shadowModelView) * worldDir;
    shadowDir = diagonal(shadowProjection).xyz * shadowDir;

    float distanceToLowerPlane
        = (airFogVolumeBottom - eyeAltitude) / worldDir.y;
    float distanceToUpperPlane
        = (airFogVolumeTop - eyeAltitude) / worldDir.y;
    float distanceToVolumeStart, distanceToVolumeEnd;

    if (eyeAltitude < airFogVolumeBottom) {
        // Below volume
        distanceToVolumeStart = distanceToLowerPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? -1.0 : distanceToUpperPlane;
    } else if (eyeAltitude < airFogVolumeTop) {
        // Inside volume
        distanceToVolumeStart = 0.0;
        distanceToVolumeEnd = worldDir.y < 0.0
            ? distanceToLowerPlane
            : distanceToUpperPlane;
    } else {
        // Above volume
        distanceToVolumeStart = distanceToUpperPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? distanceToLowerPlane : -1.0;
    }

#ifdef LOD_MOD_ACTIVE
    float fogEnd = float(lodRenderDistance);
#else
    float fogEnd = far;
#endif

    if (distanceToVolumeEnd < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    rayLength = sky ? distanceToVolumeEnd : rayLength;
    rayLength = clamp(rayLength - distanceToVolumeStart, 0.0, fogEnd);

    uint stepCount = uint(
        float(airFogMinStepCount) + airFogStepCountGrowth * rayLength
    );
    stepCount = min(stepCount, airFogMaxStepCount);

    float stepLength = rayLength * rcp(float(stepCount));

    vec3 worldStep = worldDir * stepLength;
    vec3 worldPos = worldStartPos
        + worldDir * (distanceToVolumeStart + stepLength * dither);

    vec3 shadowStep = shadowDir * stepLength;
    vec3 shadowPos = shadowStartPos
        + shadowDir * (distanceToVolumeStart + stepLength * dither);

    vec3 transmittance = vec3(1.0);

    mat2x3 lightSun = mat2x3(0.0); // Rayleigh, mie
    mat2x3 lightSky = mat2x3(0.0); // Rayleigh, mie

    // The mist is a medium of its own: its scattering already carries the
    // mist coefficient, so it must not be scaled by the Mie coefficient the
    // way the fog's Mie medium is.
    vec3 mistSunLight = vec3(0.0);
    vec3 mistSkyLight = vec3(0.0);

    for (int i = 0; i < stepCount;
         ++i, worldPos += worldStep, shadowPos += shadowStep) {
        vec3 shadowScreenPos = distortShadowSpace(shadowPos) * 0.5 + 0.5;

#if defined shadow && !defined PROGRAM_DEFERRED0
        ivec2 shadowTexel = ivec2(
            shadowScreenPos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );

// Boolean options register in Iris only when checked via #ifdef/#ifndef,
// but the mixed-type switch below needs a combined plain "#if defined" to
// select vec3 vs float shadow visibility. This empty check keeps the
// toggle discoverable on the settings screen.
#ifdef airFogColoredLightShafts
#endif
#if defined airFogColoredLightShafts && defined shadowColor
        float depth0 = texelFetch(shadowtex0, shadowTexel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadowTexel, 0).x;
        vec3 color
            = clamp01(texelFetch(shadowcolor0, shadowTexel, 0).rgb * 4.0);
        float colorWeight
            = step(depth0, shadowScreenPos.z) * step(eps, maxOf(color));

        color = color * colorWeight + (1.0 - colorWeight);
        color = mix(vec3(1.0), color, airFogColoredLightShaftsIntensity);

        vec3 shadowVis = step(shadowScreenPos.z, depth1) * color;
        shadowVis = (clamp01(shadowScreenPos) == shadowScreenPos)
            ? shadowVis
            : vec3(1.0);
        // Scalar sun visibility for mist below: float(vec3 > 0.0) is
        // illegal GLSL, so reduce explicitly (this branch is rgb).
        float shadowBinary = step(eps, maxOf(shadowVis));
#else
        float depth1 = texelFetch(shadowtex1, shadowTexel, 0).x;
        float shadowVis = step(
            float(clamp01(shadowScreenPos) == shadowScreenPos)
                * shadowScreenPos.z,
            depth1
        );
        float shadowBinary = shadowVis;
#endif
#else
#define shadowVis 1.0
#define shadowBinary 1.0
#endif

        vec2 density = airFogDensity(worldPos) * stepLength;

        vec3 stepOpticalDepth
            = fogParams.rayleighScatteringCoeff * density.x
            + fogParams.mieExtinctionCoeff * density.y;

        // Mist is a medium of its own: only march the noise when the medium
        // exists at all, its coefficient carries the total density.
        float mistD = 0.0;
        if (maxOf(fogParams.mistScatteringCoeff) > 1e-5) {
            mistD = mistDensityProfile(worldPos) * stepLength;
            stepOpticalDepth += fogParams.mistScatteringCoeff * mistD;
        }

        vec3 stepTransmittance = exp(-stepOpticalDepth);
        vec3 stepTransmittedFraction
            = (1.0 - stepTransmittance) / max(stepOpticalDepth, eps);

        vec3 visibleScattering = stepTransmittedFraction * transmittance;

        lightSun[0] += visibleScattering * density.x * shadowVis;
        lightSun[1] += visibleScattering * density.y * shadowVis;
        lightSky[0] += visibleScattering * density.x;
        lightSky[1] += visibleScattering * density.y;

        if (mistD > 1e-5) {
            vec3 mistScatter = mistD * visibleScattering;

#ifdef fogMistAdvanced
            // Optical depth of the mist between this sample and the sun.
            // It dims the remaining sunlight and reshapes the forward glow.
            float mistOd = mistLightOd(worldPos)
                * dot(fogParams.mistScatteringCoeff, vec3(1.0 / 3.0));
            // Power-law self-extinction: dense mist softly extinguishes its
            // own sunlight instead of going black
            float mistSunShadow
                = pow(1.0 + 0.7 * mistOd, -1.0 / 0.7) * shadowBinary;

            mistSunLight += mistScatter * mistSunShadow
                * mistDepthPhase(dot(worldDir, lightDir), mistOd);
#else
            // The phase depends on the order: applied below
            mistSunLight += mistScatter * shadowBinary;
#endif
            mistSkyLight += mistScatter * isotropicPhase;
        }

        transmittance *= stepTransmittance;
    }


    vec3 midWorldPos = worldStartPos
        + worldDir * (distanceToVolumeStart + rayLength * 0.5);
    float cloudShadowMid
        = getCloudShadows(colortex8, midWorldPos - cameraPosition);
    lightSun *= cloudShadowMid;

    lightSun[0] *= fogParams.rayleighScatteringCoeff;
    lightSun[1] *= fogParams.mieScatteringCoeff;
    lightSky[0] *= fogParams.rayleighScatteringCoeff;
    lightSky[1] *= fogParams.mieScatteringCoeff;

    mistSunLight *= fogParams.mistScatteringCoeff * cloudShadowMid;
    mistSkyLight *= fogParams.mistScatteringCoeff;

    if (!sky) {
        // Skylight falloff
        lightSky[0] *= max(skylight, eyeSkylight);
        lightSky[1] *= max(skylight, eyeSkylight);
        mistSkyLight *= max(skylight, eyeSkylight);
    }

    float LoV = dot(worldDir, lightDir);
    float miePhase = 0.7 * henyeyGreensteinPhase(LoV, fogMieAnisotropy)
        + 0.3 * henyeyGreensteinPhase(LoV, -0.2);

    // Multiple scattering
    vec3 scattering = vec3(0.0);
    float scatterAmount = 1.0;
    float anisotropy = 1.0;
    float mistNarrowing = 1.0;

#if defined PROGRAM_DEFERRED0
    vec3 ambientColor = ambientColorFog;
#endif

    scattering += 2.0 * (lightSky * vec2(isotropicPhase) + mistSkyLight)
        * ambientColor;

    for (int i = 0; i < 4; ++i) {
        float miePhase = 0.7 * henyeyGreensteinPhase(LoV, fogMieAnisotropy * anisotropy)
            + 0.3 * henyeyGreensteinPhase(LoV, -0.2 * anisotropy);

        vec3 orderLight = lightColor;
#ifdef ozoneLayer


        orderLight *= ozoneMultipleScattering(float(i));
#endif

#ifndef fogMistAdvanced
        // The mist lobe narrows each order along with the fog's
        float mistPhaseVal = mistOrderPhase(LoV, mistNarrowing);
#else
        // Advanced shapes the mist phase per step instead
        float mistPhaseVal = 1.0;
#endif

        scattering += scatterAmount
            * (lightSun * vec2(isotropicPhase, miePhase)
               + mistSunLight * mistPhaseVal)
            * orderLight
            * (1.0 - 0.9 * rainStrength);

        scatterAmount *= 0.5;
        anisotropy *= 0.7;
        mistNarrowing *= 0.5;
    }

    scattering *= clamp01(1.0 - blindness - darknessFactor);

    // Artifically brighten fog in the early morning and evening (looks nice)
    float eveningGlow
        = 0.75 * linearStep(0.05, 1.0, exp(-300.0 * sqr(sunDir.y + 0.02)));
    scattering += scattering * eveningGlow;

    return mat2x3(scattering, transmittance);
}

#ifdef shadowVis
#undef shadowVis
#endif

#endif // INCLUDE_ATMOS_AIR_OVERWORLD_VL
