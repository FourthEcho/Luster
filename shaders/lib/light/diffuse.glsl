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

#if !defined INCLUDE_LIGHT_DIFFUSE_LIGHT
#define INCLUDE_LIGHT_DIFFUSE_LIGHT

#include "/lib/brdf/hammon.glsl"
#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/weather/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/brdf/material.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"
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

#include "/lib/light/direct/handheld.glsl"



#if !defined WORLD_OVERWORLD
#undef cloudShadows
#endif

const float sssDensity = 14.0;
const float sssScale = 5.0 * sssIntensity;
const float nightVisionScale = 1.5;
#ifdef environmentReflections
const float metalDiffuseAmount
    = 0.0; // Real reflections carry metals, so the fake diffuse is dead
           // weight (and double-lights them next to SSR). Physical: zero.
#else
const float metalDiffuseAmount
    = 0.5; // Legacy SSR fallback for metallic surfaces; retained for
           // compatibility when reflections are off so metals stay visible.
#endif

float getBlocklightFalloff(float blocklight, float skylight, float ao) {
    float falloff = pow8(blocklight) + 0.18 * sqr(blocklight)
        + 0.16 * dampen(blocklight); // Base falloff
    falloff *= mix(
        cube(ao),
        1.0,
        clamp01(falloff)
    ); // Stronger AO further from the light source
    falloff *= mix(
        1.0,
        ao * dampen(abs(cos(2.0 * frameTimeCounter))) * 0.67 + 0.2,
        darknessFactor
    ); // Pulsing blocklight with darkness effect
    falloff *= 1.0 - 0.2 * timeNoon * skylight
        - 0.2 * skylight; // Reduce blocklight intensity in daylight
    falloff += min(
        2.7 * pow12(blocklight),
        0.9
    ); // Strong highlight around the light source, visible even in the daylight
    falloff *= smoothstep(
        0.0,
        0.125,
        blocklight
    ); // Ease transition at edge of lightmap

    return falloff;
}

float getSkylightFalloff(float skylight) {
#if defined WORLD_OVERWORLD
    return sqr(skylight);
#else
    return 1.0;
#endif
}

#ifdef shadowVps
vec3 sssApprox(
    vec3 albedo,
    float sssAmount,
    float sheenAmount,
    float sssDepth,
    float LoV,
    float shadowVis
) {
    // Transmittance-based sss
    if (sssAmount < eps) {
        return vec3(0.0);
    }

    vec3 coeff = albedo * inversesqrt(dot(albedo, luminanceWeights) + eps);
    coeff = 0.75 * clamp01(coeff);
    coeff = (1.0 - coeff) * sssDensity / sssAmount;

    float phase
        = mix(isotropicPhase, henyeyGreensteinPhase(-LoV, 0.7), 0.33);

    vec3 sssLight = sssScale * phase * exp2(-coeff * sssDepth) * dampen(sssAmount)
        * pi;

#ifdef sssSheen
    vec3 sheen = (0.8 * sssSheenIntensity) * rcp(albedo + eps)
        * exp2(-1.0 * coeff * sssDepth) * henyeyGreensteinPhase(-LoV, 0.5)
        * linearStep(-0.8, -0.2, -LoV);
    sssLight += sheen * sheenAmount;
#endif

    return sssLight;
}
#else
vec3 sssApprox(
    vec3 albedo,
    float sssAmount,
    float sheenAmount,
    float sssDepth,
    float LoV,
    float shadowVis
) {


    float sssLight = 0.06 * sssScale * pi;

#ifdef sssSheen
    vec3 sheen = (0.8 * sssSheenIntensity) * rcp(albedo + eps)
        * henyeyGreensteinPhase(-LoV, 0.5)
        * linearStep(-0.8, -0.2, -LoV) * shadowVis;

    return sssLight + sheen * sheenAmount;
#else
    return vec3(sssLight);
#endif
}
#endif

vec3 getBlockLight(
    vec3 scenePos,
    vec3 flatNormal,
    vec2 lightLevels,
    float ao,
    float directionalLight
) {
    vec3 light = vec3(0.0f);

    float blocklightFalloff
        = getBlocklightFalloff(lightLevels.x, lightLevels.y, ao);
    vec3 mcBlocklight = (blocklightFalloff * directionalLight)
        * (blocklightScale * blocklightColor);

#ifdef ssptEnabled
    // Colored blocklight handled by the SSPT chain in


#else
    light += mcBlocklight;
#endif

    light += getHandheldLight(scenePos, ao);

    return light;
}

vec3 getSkyLight(
    Material material,
    vec2 lightLevels,
    float ao,
    float ambientSss,
    float directionalLight,
    vec3 skyIrradiance
) {
    vec3 light = vec3(0.0);

#if defined WORLD_NETHER
    // Nether keeps the caller-provided sky irradiance as its only ambient
    // contribution here.
    vec3 skylight = skyIrradiance * ao * indirectLightScale;
    vec3 skylightUp = skylight;

    skylight = mix(skylight, 0.5 * skylightUp * ao, material.sssAmount);
    skylight += ambientSss * skylightUp * material.sssAmount * 2.0;

    skylight = 16.0 * directionalLight
        * mix(skylight, vec3(dot(skylight, luminanceWeights)), 0.5);

    light += skylight * getSkylightFalloff(lightLevels.y);
#else


    vec3 skylightBase = skyIrradiance * ao * indirectLightScale;
    // sss translucency wrap always references the live ambient, so leaves
    // keep their glow in every mode.
    vec3 skylight = skylightBase;
    vec3 skylightUp = skyIrradiance * ao * indirectLightScale;

    skylight = mix(skylight, 0.5 * skylightUp * ao, material.sssAmount);
    skylight += ambientSss * skylightUp * material.sssAmount * 2.0;

    light += skylight * getSkylightFalloff(lightLevels.y);
#endif

    return light;
}

vec3 getDiffuseLight(
    Material material,
    vec3 scenePos,
    vec3 normal,
    vec3 flatNormal,
    vec3 shadows,
    vec2 lightLevels,
    float ao,
    float ambientSss,
    float sssDepth,
#ifdef cloudShadows
    float cloudShadowMask,
#endif
    float shadowDistanceFade,
    float NoL,
    float NoV,
    float NoH,
    float LoV,
    vec3 skyIrradiance
) {
#if defined PROGRAM_GBUFFERS_WATER
    // Small optimization, don't calculate diffuse lighting when albedo is 0 (eg
    // water)
    if (maxOf(material.albedo) < eps) {
        return vec3(0.0);
    }
#endif

    vec3 light = vec3(0.0);


    float directionalLight = 1.0;

    float indirectAo = ao;

    // Negative sss depth => sss blocked by occluder (SSRT sss)
    bool sssBlocked = sssDepth < 0.0 || lightLevels.y < 0.1;
    sssDepth = max0(sssDepth);

#if defined WORLD_OVERWORLD || defined WORLD_END

    // Sunlight/moonlight

#if defined shadow || defined shadowSsrt
    vec3 diffuse = vec3(
        lift(max0(NoL), 0.25 * rcp(shadingStrength))
        * (1.0 - 0.5 * material.sssAmount)
    );


#ifdef ssptEnabled
    const vec3 bounced = vec3(0.0);
#else
    vec3 bounced = vec3(0.0);
    bounced = 0.033 * (1.0 - shadows)
        * (1.0 - 0.1 * max0(normal.y))
        * pow1d5(ao + eps)
        * pow4(lightLevels.y);
#endif

    vec3 sssLight = sssApprox(
                   material.albedo,
                   material.sssAmount,
                   material.sheenAmount,
                   mix(sssDepth, 0.0, shadowDistanceFade),
                   LoV,
                   shadows.x
               )
        * float(!sssBlocked);

    // Adjust sss outside of shadow distance
    sssLight *= mix(
        1.0,
        (ao + pi * ambientSss) * (clamp01(NoL) * 0.8 + 0.2),
        clamp01(shadowDistanceFade)
    );

#ifdef aoInSunlight
    diffuse *= sqr(ao);
#endif

#ifdef shadowVps
    // Add sss and diffuse
    light += diffuse * shadows + bounced + sssLight;
#else
    // Blend sss and diffuse
    light += mix(diffuse, sssLight, material.sssAmount) * shadows + bounced;
#endif
#else


    // the shadow-enabled path above. We now scale it by sssIntensity


    vec3 sssLight = vec3(0.08 * sssScale * pi);
#ifdef sssSheen
    sssLight += 0.5 * sssSheenIntensity * material.sheenAmount
        * rcp(material.albedo + eps)
        * henyeyGreensteinPhase(-LoV, 0.5)
        * linearStep(-0.8, -0.2, -LoV);
#endif

    vec3 diffuse
        = vec3(lift(max0(NoL), 0.5 * rcp(shadingStrength)) * 0.6 + 0.4)
        * (shadows * 0.8 + 0.2);
    diffuse = diffuse + max0(sssLight * lift(material.sssAmount, 5.0));
    diffuse *= ao * pow4(lightLevels.y) * (dampen(lightDir.y) * 0.5 + 0.5);

    light += diffuse;
#endif

    light *= lightColor;

#ifdef cloudShadows
    light *= cloudShadowMask;
#endif
#endif

#ifndef ssptEnabled
    light += getSkyLight(
        material,
        lightLevels,
        indirectAo,
        ambientSss,
        directionalLight,
        skyIrradiance
    );
#endif

    // Blocklight

    light += getBlockLight(
        scenePos,
        flatNormal,
        lightLevels,
        indirectAo,
        directionalLight
    );

    light += material.emission * emissionScale;

#if defined WORLD_OVERWORLD


    light += 0.15 * caveLightI * directionalLight * indirectAo
        * (1.0 - lightLevels.y * lightLevels.y)
        * (1.0 - 0.7 * darknessFactor);
    light += nightVision * nightVisionScale * directionalLight * indirectAo;
#endif

    return max0(light) * material.albedo * rcpPi
        * mix(1.0, metalDiffuseAmount, float(material.isMetal));
}

#endif // INCLUDE_LIGHT_DIFFUSE_LIGHT
