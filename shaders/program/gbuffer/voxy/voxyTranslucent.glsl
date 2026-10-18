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

#include "/lib/atmos/fog/overworld/params.glsl"
#include "/lib/global.glsl"

#ifdef shadow
#undef shadow
#endif

#ifdef handheldLight
#undef handheldLight
#endif

#ifdef shadowSsrt
#undef shadowSsrt
#endif

uniform float desertSandstormWeather;

// simpleFog needs fogColor, Voxy patch doesn't expose it by default
uniform vec3 fogColor;
uniform sampler2D depthtex1;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 sunDir;
uniform vec3 lightDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float near;
uniform float far;
uniform float eyeAltitude;
uniform float eyeSkylight;
uniform float rainStrength;
uniform float blindness;
uniform float darknessFactor;
uniform float timeNoon;
uniform float nightVision;
uniform float sunAngle;

uniform int isEyeInWater;
uniform int moonPhase;
uniform int frameCounter;

// Declared for material/water.glsl / material/rain.glsl, which sample noise
// and animate by frame in every TU that includes them.
uniform sampler2D noisetex;
uniform float frameTimeCounter;

// Declared for the cave-fog path, which scales density by biomeCave in
// every TU that includes it.
uniform float biomeCave;

vec3 ambientColor;
vec3 lightColor;

#ifdef WORLD_OVERWORLD
// Unused
OverworldFogParams fogParams;
#endif

#define TEMPORAL_REPROJECTION

#include "/lib/atmos/fog/simpleFog.glsl"
#include "/lib/brdf/common.glsl"
#include "/lib/light/pcss.glsl"
#include "/lib/brdf/specular.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/material/material.glsl"
#include "/lib/material/water.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

#ifdef cloudShadows
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/sky/clouds/core/constants.glsl"
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
#include "/lib/atmos/sky/clouds/altocumulus.glsl"
#include "/lib/atmos/sky/clouds/cirrus.glsl"
#include "/lib/atmos/sky/clouds/cumulus.glsl"
#include "/lib/atmos/sky/clouds/cumulusCongestus.glsl"

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
#endif // INCLUDE_LIGHTING_CLOUD_SHADOWS
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

#endif // INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#endif

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHT)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHT_HANDHELD_LIGHT
#define INCLUDE_LIGHT_HANDHELD_LIGHT

#define HANDHELD_LIGHT_COLORS
#if handheldLightMode == handheldLightColored
const vec3 handheldEmitterLightColor[48] = vec3[48](
    vec3(1.00, 1.00, 1.00) * 12.0, // Strong white light
    vec3(1.00, 1.00, 1.00) * 6.0, // Medium white light
    vec3(1.00, 1.00, 1.00) * 1.0, // Weak white light
    vec3(1.00, 0.55, 0.27) * 14.0, // Strong golden light
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.57, 0.30) * 6.0, // Weak golden light
    vec3(1.00, 0.18, 0.10) * 5.0, // Redstone components
    vec3(1.00, 0.38, 0.10) * 7.0, // Lava
    vec3(1.00, 0.45, 0.10) * 9.0, // Medium orange light
    vec3(1.00, 0.63, 0.15) * 4.0, // Brewing stand
    vec3(1.00, 0.57, 0.30) * 12.0, // Medium golden light
    vec3(0.45, 0.73, 1.00) * 6.0, // Soul lights
    vec3(0.45, 0.73, 1.00) * 14.0, // Beacon
    vec3(0.75, 1.00, 0.83) * 3.0, // Sculk
    vec3(0.75, 1.00, 0.83) * 1.0, // End portal frame
    vec3(0.60, 0.10, 1.00) * 2.5, // Pink glow
    vec3(0.75, 1.00, 0.50) * 1.0, // Sea pickle
    vec3(1.00, 0.50, 0.25) * 4.0, // Nether plants
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.65, 0.30) * 8.0, // Ochre froglight
    vec3(0.86, 1.00, 0.44) * 8.0, // Verdant froglight
    vec3(0.75, 0.44, 1.00) * 8.0, // Pearlescent froglight
    vec3(0.60, 0.10, 1.00) * 2.0, // Enchanting table
    vec3(0.75, 0.44, 1.00) * 4.0, // Amethyst cluster
    vec3(0.75, 0.44, 1.00) * 4.0, // Calibrated sculk sensor
    vec3(0.75, 1.00, 0.83) * 6.0, // Active sculk sensor
    vec3(1.00, 0.18, 0.10) * 3.3, // Redstone block
    vec3(1.00, 0.50, 0.25) * 3.0, // Open eyeblossom
    vec3(0.85, 1.3, 1.0) * 3.9, // Copper torch and lanterns
    vec3(1.00, 0.57, 0.30) * 8.0, // Copper Bulbs
    vec3(0.60, 0.10, 1.00) * 12.0, // Nether portal
    vec3(0.0), // End portal
    // Colors for modded light sources (block IDs 64-79)
    vec3(1.00, 1.00, 1.00) * 10.0, // 32 - White       (block 64)
    vec3(0.85, 0.85, 0.85) *  9.0, // 33 - Light Gray  (block 65)
    vec3(0.55, 0.55, 0.55) *  8.0, // 34 - Gray        (block 66)
    vec3(0.20, 0.20, 0.22) *  6.0, // 35 - Black       (block 67)
    vec3(0.55, 0.35, 0.20) *  8.0, // 36 - Brown       (block 68)
    vec3(1.00, 0.10, 0.10) * 10.0, // 37 - Red         (block 69)
    vec3(1.00, 0.45, 0.10) * 10.0, // 38 - Orange      (block 70)
    vec3(1.00, 0.95, 0.20) * 10.0, // 39 - Yellow      (block 71)
    vec3(0.55, 1.00, 0.20) * 10.0, // 40 - Lime        (block 72)
    vec3(0.15, 1.00, 0.20) * 10.0, // 41 - Green       (block 73)
    vec3(0.15, 0.95, 1.00) * 10.0, // 42 - Cyan        (block 74)
    vec3(0.45, 0.75, 1.00) * 10.0, // 43 - Light Blue  (block 75)
    vec3(0.15, 0.30, 1.00) * 10.0, // 44 - Blue        (block 76)
    vec3(0.55, 0.15, 1.00) * 10.0, // 45 - Purple      (block 77)
    vec3(1.00, 0.20, 0.90) * 10.0, // 46 - Magenta     (block 78)
    vec3(1.00, 0.55, 0.85) * 10.0  // 47 - Pink        (block 79)
);
#endif // handheldLightingMode == handheldLightingColored

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 getHandheldLightColor(int handItemId, int heldItemLightValue) {
#if handheldLightMode == handheldLightColored
    const int firstEmitterId = 10032;
    const int emitterCount = 48;
    int emitterIndex = handItemId - firstEmitterId;

    if (emitterIndex >= 0 && emitterIndex < emitterCount) {
        return handheldEmitterLightColor[emitterIndex];
    }
#endif

    return (blocklightColor * blocklightScale * rcp(15.0))
        * heldItemLightValue;
}

float getHandheldLightFalloff(vec3 scenePos, float ao) {
    float falloff = lift(rcp(dot(scenePos, scenePos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * 1.00;
}

vec3 getHandheldLight(vec3 scenePos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scenePos += relativeEyePosition;
#endif

    vec3 lightColor = max(
        getHandheldLightColor(heldItemId, heldBlockLightValue),
        getHandheldLightColor(heldItemId2, heldBlockLightValue2)
    );

    float falloff = getHandheldLightFalloff(scenePos, ao);

    return lightColor * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS
#endif

layout(location = 0) out vec4 fragmentColor;
layout(
    location = 1
) out vec4 gbufferData; // albedo, block ID, flat normal, light levels

/*
struct VoxyFragmentParameters {
    vec4 sampledColour;
    vec2 tile;
    vec2 uv;
    uint face;
    uint modelId;
    vec2 lightMap;
    vec4 tinting;
    uint customId; // Same as iris's modelId
};
*/

Material getWaterMaterial(
    vec4 sampledColor,
    vec4 tint,
    vec3 dirWorld,
    vec3 normal,
    vec2 lightLevels,
    float layerDist,
    out float alpha
) {
    Material material = waterMaterial;
    alpha = 0.01;

    // Water texture

#if waterTexture == waterTextureHighlight \
    || waterTexture == waterTextureHighlightUnderground
    float textureHighlight = dampen(
        0.5 * sqr(linearStep(0.63, 1.0, sampledColor.r))
        + 0.03 * sampledColor.r
    );
#if waterTexture == waterTextureHighlightUnderground
    textureHighlight *= 1.0 - cube(linearStep(0.0, 0.5, lightLevels.y));
#endif

    sampledColor *= tint;
    material.albedo
        = clamp01(0.5 * exp(-2.0 * waterAbsorptionCoeff) * textureHighlight);
    material.roughness += 0.3 * textureHighlight;
    alpha += textureHighlight;
#elif waterTexture == waterTextureVanilla
    sampledColor *= tint;
    material.albedo = srgbEotfInv(sampledColor.rgb * sampledColor.a)
        * rec709ToWorkingColor;
    alpha = sampledColor.a;
#endif

    // Water edge highlight

#ifdef waterEdgeHighlight
    float dist = layerDist * max(abs(dirWorld.y), eps);

#if waterTexture == waterTextureHighlight \
    || waterTexture == waterTextureHighlightUnderground
    float edgeHighlightAmount
        = cube(max0(1.0 - 2.0 * dist)) * (1.0 + 8.0 * textureHighlight);
#else
    float edgeHighlightAmount = cube(max0(1.0 - 2.0 * dist));
#endif
    edgeHighlightAmount *= waterEdgeHighlightIntensity * max0(normal.y)
        * (1.0 - 0.5 * sqr(lightLevels.y));
    ;

    material.albedo += 0.1 * edgeHighlightAmount
        / mix(1.0,
              max(dot(ambientColor, luminanceWeights), 0.5),
              lightLevels.y);
    material.albedo = clamp01(material.albedo);
    alpha += edgeHighlightAmount;
#endif

    return material;
}

void voxy_emitFragment(VoxyFragmentParams params) {
    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);


    float vanillaOpaqueDepth
        = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).x;
    if (vanillaOpaqueDepth < gl_FragCoord.z
        && vanillaOpaqueDepth < 1.0) {
        discard;
    }

    // Get the depth of the solid layer behind this fragment (used for edge
    // highlight effect)

    float lodDepthBehind
        = texelFetch(vxDepthTexOpaque, ivec2(gl_FragCoord.xy), 0).x;


    lightColor = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    ambientColor = texelFetch(colortex4, ivec2(191, 1), 0).rgb;

    // Get base properties

    vec4 baseColor = params.sampledColour * params.tinting;

    // from Cortex
    vec3 normal = vec3(
                      uint((params.face >> 1) == 2),
                      uint((params.face >> 1) == 0),
                      uint((params.face >> 1) == 1)
                  )
        * (float(int(params.face) & 1) * 2.0 - 1.0);


    ambientColor *= clamp01(params.lightMap.y);

    uint materialMask = max(params.customId - 10000u, 0u);

    // Get position

    vec3 posScreen = vec3(coord, gl_FragCoord.z);
    vec3 posView = screenToViewSpace(vxProjInv, posScreen, true);
    vec3 posScene = viewToSceneSpace(posView);

    vec3 dirWorld = normalize(posScene - gbufferModelViewInverse[3].xyz);

    // Get distance to the solid layer behind this fragment

    vec3 backPosView
        = screenToViewSpace(vxProjInv, vec3(coord, lodDepthBehind), true);
    float layerDist = distance(posView, backPosView);

    // Get material

    Material material;
    float alpha = 0.0;

    if (materialMask == MATERIAL_WATER) {
        material = getWaterMaterial(
            params.sampledColour,
            params.tinting,
            dirWorld,
            normal,
            params.lightMap,
            layerDist,
            alpha
        );
    } else {
        vec2 unused = params.lightMap;
        material = materialFrom(
            baseColor.rgb,
            materialMask,
            posScene + cameraPosition,
            normal,
            unused
        );
        alpha = baseColor.a;
    }

    // Encode water data

    if (materialMask == MATERIAL_WATER) {
        gbufferData.x = packUnorm2x8(params.tinting.rg);
        gbufferData.y = packUnorm2x8(params.tinting.b, alpha);
        gbufferData.z = packUnorm2x8(encodeUnitVector(normal));
        gbufferData.w = packUnorm2x8(params.lightMap);
    } else {
        gbufferData = vec4(0.0);
    }

    // Early exit if albedo is zero

    if (maxOf(material.albedo * alpha) < eps) {
        fragmentColor = vec4(0.0);
        return;
    }

    // Forward shading

    float NoL = dot(normal, lightDir);
    float NoV = clamp01(dot(normal, -dirWorld));
    float LoV = dot(lightDir, -dirWorld);
    float halfwayNorm = inversesqrt(2.0 * LoV + 2.0);
    float NoH = (NoL + NoV) * halfwayNorm;
    float LoH = LoV * halfwayNorm + halfwayNorm;

    vec3 shadows = vec3(pow8(params.lightMap.y)); // Fake shadow
#define sssDepth 0.0
#define shadowDistanceFade 0.0

#ifdef cloudShadows
    float cloudShadowMask = getCloudShadows(colortex8, posScene);
    shadows *= cloudShadowMask;
#endif

    fragmentColor.rgb = getDiffuseLight(
        material,
        posScene,
        normal,
        normal,
        shadows,
        params.lightMap,
        1.0, // AO
        0.0, // Ambient sss
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
    fragmentColor.a = alpha;

    // Apply fog

    vec4 fog = commonFog(length(posScene), false, posScene);
    fragmentColor.rgb = fragmentColor.rgb * fog.a + fog.rgb;
}
