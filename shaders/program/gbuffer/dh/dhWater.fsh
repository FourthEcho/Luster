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

layout(location = 0) out vec4 fragmentColor;
layout(
    location = 1
) out vec4 gbufferData; // albedo, block ID, flat normal, light levels
#ifdef ssptEnabled
layout(
    location = 2
) out vec4 emissionRadiance; // zeroed: water never emits
#endif

/* RENDERTARGETS: 0,1 */

#ifdef ssptEnabled
/* RENDERTARGETS: 0,1,22 */
#endif

in vec2 lightLevels;
in vec3 scenePos;
in vec3 normal;
in vec4 tint;

flat in uint isWater;
flat in vec3 lightColor;
flat in vec3 ambientColor;

#if defined PROGRAM_GBUFFERS_WATER
in vec2 atlasTileCoord;
in vec3 tangentPos;
flat in vec2 atlasTileOffset;
flat in vec2 atlasTileScale;
#endif

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/overworld/params.glsl"
flat in OverworldFogParams fogParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex4; // Sky map, lighting colors (needed by lib/brdf/specular.glsl sky reflections)
uniform sampler2D colortex5; // scene history (used by SSR reflection reprojection)
uniform sampler2D colortex7; // fog scattering history (used by SSR reflection reprojection)


#ifdef cloudShadows
uniform sampler2D colortex8; // Cloud shadow map
#endif

uniform sampler2D depthtex0;

#ifdef shadow
#ifdef WORLD_OVERWORLD
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;
#endif

#ifdef WORLD_END
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;
#endif
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform float frameTimeCounter;
uniform float sunAngle;
uniform float rainStrength;
uniform float desertSandstormWeather;
uniform float wetness;

uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;

uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;
uniform float eyeAltitude;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float eyeSkylight;

uniform float biomeCave;
uniform float biomeMayRain;
uniform float biomeMaySnow;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

#if defined PROGRAM_GBUFFERS_ENTITIES_TRANSLUCENT
uniform vec4 entityColor;
#endif

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION

#ifdef shadowColor
#undef shadowColor
#endif

#if defined PROGRAM_GBUFFERS_TEXTURED \
    || defined PROGRAM_GBUFFERS_PARTICLES_TRANSLUCENT
#define NO_NORMAL
#endif


#include "/lib/atmos/air/simple.glsl"
#include "/lib/light/diffuse.glsl"
#include "/lib/light/direct/pcss.glsl"
#include "/lib/brdf/specular.glsl"
#include "/lib/util/lodMod.glsl"
#include "/lib/brdf/material.glsl"
#include "/lib/surface/water.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

#ifdef cloudShadows
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
#include "/lib/util/random.glsl"

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
#endif

void main() {
    // Clip to taau viewport

    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);

#if defined taa && defined taau
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    // Overdraw fade

    float dhFadeStartDistance
        = max0(far - dhOverdrawDistance - dhOverdrawFadeLength);
    float dhFadeEndDistance = max0(far - dhOverdrawDistance);
    float viewDistance = length(scenePos);

    float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
    float fade = smoothstep(
        dhFadeStartDistance,
        dhFadeEndDistance,
        viewDistance
    );

    if (dither > fade) {
        discard;
        return;
    }

    // Encode gbuffer data

    gbufferData.x = packUnorm2x8(tint.rg);
    gbufferData.y
        = packUnorm2x8(tint.b, clamp01(((isWater == 1) ? rcp(255.0) : 0.0)));
    gbufferData.z = packUnorm2x8(encodeUnitVector(normal));
    gbufferData.w = packUnorm2x8(dither8bit(lightLevels, 0.5));

#ifdef ssptEnabled
    // This pass overwrites colortex1 but never emits; zero the bake so
    // SSPT hits on DH water cannot read stale emission from the geometry
    // behind it.
    emissionRadiance = vec4(0.0);
#endif

    if (isWater == 1.0) {
        fragmentColor = vec4(0.0);
        return;
    }

    // Space conversions

    float backDepthMc = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
    float backDepthDh = texelFetch(dhDepthTex1, ivec2(gl_FragCoord.xy), 0).x;
    bool backIsDhTerrain = isLodTerrain(backDepthMc, backDepthDh);

    // Prevent water behind terrain from rendering on top of it
    float dhDepthLinear
        = screenToViewSpaceDepth(dhProjectionInverse, gl_FragCoord.z);
    float mcDepthLinear
        = screenToViewSpaceDepth(gbufferProjectionInverse, backDepthMc);

    if (mcDepthLinear < dhDepthLinear && backDepthMc != 1.0) {
        discard;
        return;
    }

    vec3 worldPos = scenePos + cameraPosition;
    vec3 worldDir = normalize(scenePos - gbufferModelViewInverse[3].xyz);

    vec3 viewBackPos = backIsDhTerrain
        ? screenToViewSpace(vec3(coord, backDepthDh), true, true)
        : screenToViewSpace(vec3(coord, backDepthMc), true, false);
    vec3 sceneBackPos = viewToSceneSpace(viewBackPos);

    float layerDist = length(
        scenePos - sceneBackPos
    ); // distance to solid layer along view ray

    // Get material and normal

    Material material;
    fragmentColor = tint;

    vec2 adjustedLightLevels = lightLevels;
    material = materialFrom(
        fragmentColor.rgb,
        0u,
        worldPos,
        normal,
        adjustedLightLevels
    );

    // Shadows

#ifndef NO_NORMAL
    float NoL = dot(normal, lightDir);
#else
    float NoL = 1.0;
#endif
    float NoV = clamp01(dot(normal, -worldDir));
    float LoV = dot(lightDir, -worldDir);
    float halfwayNorm = inversesqrt(2.0 * LoV + 2.0);
    float NoH = (NoL + NoV) * halfwayNorm;
    float LoH = LoV * halfwayNorm + halfwayNorm;

    vec3 shadows = vec3(pow8(lightLevels.y));
#define sssDepth 0.0
#define shadowDistanceFade 0.0

#ifdef cloudShadows
    float cloudShadowMask = getCloudShadows(colortex8, scenePos);
    shadows *= cloudShadowMask;
#endif

    fragmentColor.rgb = getDiffuseLight(
        material,
        scenePos,
        normal,
        normal,
        shadows,
        lightLevels,
        1.0,
        0.0,
        sssDepth,
#ifdef cloudShadows
        cloudShadowMask,
#endif
        shadowDistanceFade,
        NoL,
        NoV,
        NoH,
        LoV,
        ambientColor
    );

    // Apply fog

    vec4 fog = commonFog(length(scenePos), false, scenePos);
    fragmentColor.rgb = fragmentColor.rgb * fog.a + fog.rgb;

    fragmentColor.a *= borderFogFactor(scenePos, worldDir);
}
