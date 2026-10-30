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

// The cloud parameter include reaches the atmosphere/sandstorm code before
// any later program-local uniform declarations, so declare this first.
uniform float desertSandstormWeather;

/* RENDERTARGETS: 8 */
layout(location = 0) out vec3 fragmentColor;

in vec2 uv;


#include "/lib/atmos/clouds/util/params.glsl"
flat in CloudsParams cloudsParams;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float blindness;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float worldAge;
uniform float eyeSkylight;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float biomeCave;
uniform float biomeMaySnow;

const vec3 sunColor = vec3(0.0);
const vec3 moonColor = vec3(0.0);
const vec3 skyColor = vec3(0.0);


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
#include "/lib/util/lodMod.glsl"
#include "/lib/atmos/clouds/util/coverageMap.glsl"

void main() {
    // Cloud shadow map

#ifdef cloudShadows
#ifndef blockyClouds
    fragmentColor.xy = renderCloudShadowMap(uv);
#else
    fragmentColor.xy = vec2(1.0);
#endif
#endif

    // Cumulus coverage map

#ifdef cloudsCumulusPrecomputeLocalCoverage
    fragmentColor.z = renderCloudsCumulusCoverageMap(uv);
#endif
}
