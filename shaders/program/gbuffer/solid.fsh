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

#ifdef pomSlopeNormals
// Iris requires boolean shader options to be checked with #ifdef/#ifndef.
#define POM_SLOPE_NORMALS_OPTION_ENABLED
#endif
// Legacy singular guard name (pre-rename). Treat it as the plural toggle.
#ifdef POM_SLOPE_NORMAL
#define POM_SLOPE_NORMALS_OPTION_ENABLED
#ifndef pomSlopeNormals
#define pomSlopeNormals
#endif
#endif
#ifdef pomDepthWrite
// Iris requires boolean shader options to be checked with #ifdef/#ifndef.
#define POM_DEPTH_WRITE_OPTION_ENABLED
#endif

layout(
    location = 0
) out vec4 gbufferData0; // albedo, block ID, flat normal, light levels
layout(
    location = 1
) out vec4 gbufferData1; // detailed normal, specular map (optional)

/* RENDERTARGETS: 1 */

#ifdef normalMapping
/* RENDERTARGETS: 1,2 */
#endif

#ifdef specularMapping
/* RENDERTARGETS: 1,2 */
#endif

in vec2 uv;
in vec3 scenePos;
in vec4 tint;

flat in uint materialMask;
flat in mat3 tbn;

#if defined pom
in vec2 atlasTileCoord;
in vec3 tangentPos;
flat in vec2 atlasTileOffset;
flat in vec2 atlasTileScale;
#endif

#ifdef COLORWHEEL
vec2 lightLevels;
float mcAo;
#else
in vec2 lightLevels;
#if defined PROGRAM_GBUFFERS_TERRAIN
in float mcAo;
#endif
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
in vec2 uvLocal;
#endif

#if defined PROGRAM_GBUFFERS_VOXELS
in vec3 blockNormal;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D gtexture;

#if defined normalMapping || defined pom
uniform sampler2D normals;
#endif

#if defined specularMapping
uniform sampler2D specular;
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform vec3 lightDir;

uniform float alphaTestRef = 0.1;

#if defined PROGRAM_GBUFFERS_ENTITIES
uniform int entityId;
uniform vec4 entityColor;
#endif

#if defined PROGRAM_GBUFFERS_PARTICLES
#define NO_NORMAL
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom
#include "/lib/surface/parallax.glsl"
#endif

#ifdef directionalLightmaps
#define LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS

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
#endif // handheldLightMode == handheldLightColored

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

#endif // INCLUDE_LIGHT_HANDHELD_LIGHT
#endif

#undef LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS
#endif
// Change the material mask of some handheld/dropped items to help the hardcoded
// emission

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
uint fixMaterialMask() {
#if defined PROGRAM_GBUFFERS_ENTITIES
    if (entityId != 10100) {
        return materialMask;
    }
    bool isTopFace = tbn[2].y > 0.5;
#else
    bool isTopFace = (mat3(gbufferModelView) * tbn[2]).y > 0.5;
#endif

    // Warped stems
    if (19 <= materialMask && materialMask < 22) {
        bool isLit = !isTopFace
            || any(
                lessThan(vec4(uvLocal, 1.0 - uvLocal), vec4(rcp(16.0) - 1e-3))
            );
        return isLit ? 22u : 0u;
    }

    // Crimson stems
    if (23 <= materialMask && materialMask < 26) {
        bool isLit = !isTopFace
            || any(
                lessThan(vec4(uvLocal, 1.0 - uvLocal), vec4(rcp(16.0) - 1e-3))
            );
        return isLit ? 26u : 0u;
    }

    return materialMask;
}
#endif
#include "/lib/util/encode.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

#if defined PROGRAM_GBUFFERS_VOXELS
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom
#define readTex(x) textureGrad(x, parallaxUv, uvGradient[0], uvGradient[1])
#else
// Plain isotropic sampling with the render-scale LOD bias.
#define readTex(x) texture(x, uv, lodBias)
#endif

#if defined PROGRAM_GBUFFERS_BLOCK
vec3 drawEndPortal() {
    const int layerCount = 8; // Number of layers
    const float depthScale = 0.33; // Apparent distance between layers
    const float depthFade = 0.5; // How quickly the layers fade to black
    const float thresh = 0.99; // Threshold for the "stars". Lower values
                                  // mean more stars appear
    const float twinkleSpeed = 0.4; // How fast the stars appear to twinkle
    const float twinkleAmount = 0.04; // How many twinkling stars appear
    const vec3 color0 = pow(vec3(0.80, 0.90, 0.99), vec3(2.2));
    const vec3 color1 = pow(vec3(0.75, 0.40, 0.93), vec3(2.2));
    const vec3 color2 = pow(vec3(0.20, 0.70, 0.90), vec3(2.2));

    vec3 screenPos = vec3(
        gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale),
        gl_FragCoord.z
    );
    vec3 viewPos = screenToViewSpace(screenPos, true);
    vec3 scenePos = viewToSceneSpace(viewPos);

    vec3 worldPos = scenePos + cameraPosition;
    vec3 worldDir = normalize(scenePos - gbufferModelViewInverse[3].xyz);

    // Get tangent-space position/direction without tangent/bitangent

    vec2 tangentPos, tangentDir;
    if (abs(tbn[2].x) > 0.5) {
        tangentPos = worldPos.yz;
        tangentDir = worldDir.yz / abs(worldDir.x + eps);
    } else if (abs(tbn[2].y) > 0.5) {
        tangentPos = worldPos.xz;
        tangentDir = worldDir.xz / abs(worldDir.y + eps);
    } else {
        tangentPos = worldPos.xy;
        tangentDir = worldDir.xy / abs(worldDir.z + eps);
    }

    vec3 result = vec3(0.0);

    for (int i = 0; i < layerCount; ++i) {
        // Random layer offset
        vec2 layerOffset = r2(i) * 512.0;

        // Make layers drift over time
        float angle = i * goldenAngle;
        vec2 drift
            = 0.033 * vec2(cos(angle), sin(angle)) * frameTimeCounter * r1(i);

        // Snap tangentPos to a grid and calculate a seed for the RNG
        ivec2 gridPos = ivec2((tangentPos + drift) * 32.0 + layerOffset);
        uint seed = uint(80000 * gridPos.y + gridPos.x);

        // 4 random numbers for this grid cell
        vec4 random = randNextVec4(seed);

        // Twinkling animation
        float twinkleOffset = tau * random.w;
        random.x *= 1.0
            - twinkleAmount
                * cos(frameTimeCounter * twinkleSpeed + twinkleOffset);

        // Stomp all values below threshold to zero
        float intensity = pow8(linearStep(thresh, 1.0, random.x));

        // Blend between the 3 colors
        vec3 color = mix(color0, color1, random.y);
        color = mix(color, color2, random.z);

        // Fade away with depth
        float fade = exp2(-depthFade * float(i));

        result += color * intensity * exp2(-3.0 * (1.0 - fade) * (1.0 - color))
            * fade;

        // Step along the view ray
        tangentPos
            += tangentDir * depthScale * gbufferProjection[1][1] * rcp(1.37);

        if (random.x > thresh) {
            break;
        }
    }

    result *= 0.8;
    result = sqrt(result);
    result *= sqrt(result);

    return result;
}
#endif

const float lodBias = log2(taauViewportScale);

void main() {
#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);
    if (clamp01(coord) != coord) {
        discard;
        return;
    }
#endif

    bool parallaxShadow = false;
    float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
    // pom relief state shared by slope normals and depth write. Stays zero
    // when the march is skipped so both effects fade out together.
    float pomRelief = 0.0;
    float pomSlopeFade = 0.0;

#ifndef PROGRAM_GBUFFERS_VOXELS
#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom
    float viewDistance = length(tangentPos);

    bool hasPom
        = viewDistance < pomDistance; // Only calculate pom for close terrain
    hasPom = hasPom
        && materialMask
            != MATERIAL_LAVA; // Do not calculate pom for water or lava

    vec3 tangentDir = -normalize(tangentPos);
    mat2 uvGradient = mat2(dFdx(uv), dFdy(uv));

    vec2 parallaxUv;

    if (hasPom) {
        float pomDepthNorm;
        vec3 shadowTracePos;

        parallaxUv = getParallaxUv(
            tangentDir,
            uvGradient,
            viewDistance,
            dither,
            shadowTracePos,
            pomDepthNorm
        );

        pomRelief = getPomWorldRelief(pomDepthNorm, viewDistance);
        pomSlopeFade = getPomReliefScale(viewDistance);
#ifdef pomShadow
        if (dot(tbn[2], lightDir) >= eps) {
            parallaxShadow = getParallaxShadow(
                shadowTracePos,
                uvGradient,
                viewDistance,
                dither
            );
        } else {
            parallaxShadow = false;
        }
#endif
    } else {
        parallaxUv = uv;
        parallaxShadow = false;
    }
#endif

    //--//

    vec4 baseColor;
#if defined COLORWHEEL
    baseColor = readTex(gtexture);
    vec4 overlayColor;

    clrwl_computeFragment(
        baseColor,
        baseColor,
        lightLevels,
        mcAo,
        overlayColor
    );
    lightLevels = clamp((lightLevels - 1.0 / 32.0) * 32.0 / 30.0, 0.0, 1.0);
#else
    baseColor = readTex(gtexture) * tint;

#if defined IRIS_INLINE_GLINT
    if (mc_hasGlint()) {
        baseColor.rgb += sqr(mc_sampleGlint());
    }
#endif
#endif

#ifdef normalMapping
    vec3 normalMap = readTex(normals).xyz;
#endif
#ifdef specularMapping
    vec4 specularMap = readTex(specular);
#endif
#else
    vec3 screenPos = vec3(
        gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale),
        gl_FragCoord.z
    );

    vec3 viewPos = screenToViewSpace(screenPos, true);
    vec3 scenePos = viewToSceneSpace(viewPos);

    vec3 worldPos = scenePos + cameraPosition;
    vec3 worldDir = normalize(scenePos - gbufferModelViewInverse[3].xyz);

    RayJob ray = RayJob(
        worldPos - worldOffset - 0.001f * blockNormal, // Ray origin
        worldDir, // Ray direction
        vec3(0),
        vec3(0),
        vec3(0),
        false
    );

    rayConstraint = ivec3(ray.origin);
    traceRay(ray);

    if (!ray.resultHit) {
        discard;
    }
    if (ray.resultNormal == vec3(0.0)) {
        ray.resultNormal = blockNormal;
    }

    scenePos = ray.resultPosition + worldOffset - cameraPosition;
    viewPos = sceneToViewSpace(scenePos);
    screenPos = viewToScreenSpace(gbufferProjection, viewPos, true);

    gl_FragDepth = screenPos.z;

    vec4 baseColor = vec4(ray.resultColor, 1.0f);
    vec3 phNormal = ray.resultNormal;

#if defined specularMapping
    vec4 specularMap = vec4(0.0f);
#endif
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES
    if (materialMask == MATERIAL_LIGHTNING_BOLT) {
        baseColor = vec4(1.0);
    }
    if (baseColor.a < alphaTestRef && materialMask != MATERIAL_BOAT) {
        discard;
        return;
    } // Save transparent quad in boats, which masks out water
#elif !defined PROGRAM_GBUFFERS_TERRAIN_SOLID
    if (baseColor.a < alphaTestRef) {
        discard;
        return;
    }
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined vanillaAo
#if shaderAo != shaderAoNone
    const float vanillaAoStrength = 0.9 * 1.00;
    const float mcAoLift = clamp(0.5 * (1-((1-1.00)*0.5)) + vanillaAoLift, 0.0, 1.0);
#else
    const float vanillaAoStrength = 1.0 * 1.00;
    const float mcAoLift = clamp(vanillaAoLift, 0.0, 1.0);
#endif

    baseColor.rgb *= lift(mcAo, mcAoLift) * vanillaAoStrength
        + (1.0 - vanillaAoStrength);
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES
    baseColor.rgb = mix(baseColor.rgb, entityColor.rgb, entityColor.a);
#endif

#if defined COLORWHEEL
    baseColor.rgb = mix(baseColor.rgb, overlayColor.rgb, overlayColor.a);
#endif

#if defined PROGRAM_GBUFFERS_BLOCK
    // parallax end portal
    if (materialMask == MATERIAL_END_PORTAL) {
        baseColor.rgb = drawEndPortal();
    }
#endif

#if defined PROGRAM_GBUFFERS_BEACONBEAM
    // Discard the translucent edge part of the beam
    if (baseColor.a < 0.5) {
        discard;
    }
#endif

    vec2 adjustedLightLevels = lightLevels;

#if defined normalMapping && !defined PROGRAM_GBUFFERS_VOXELS
    vec3 normal;
    float materialAo;
// #ifdef references so Iris registers both toggles on the settings screen
// (the selection below uses a combined plain "#if defined").
#ifdef pomSlopeNormalsOnly
#endif
#ifdef pomSlopeNormalOnly
#endif
#if defined pomSlopeNormalsOnly || defined pomSlopeNormalOnly
    normal = vec3(0.0, 0.0, 1.0);
    materialAo = 1.0;
#else
    decodeNormalMap(normalMap, normal, materialAo);
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom \
    && defined pomSlopeNormals && info > 0


    if (hasPom && pomSlopeFade > 1e-4) {
        normal = normalize(
            normal
            + getPomSlopeNormal(
                getLocalCoordFromUv(parallaxUv),
                uvGradient
            )
                * pomSlopeFade
        );
    }
#endif

    normal = tbn * normal;

#ifdef textureAo


    // occlude the lightmap. Off by default.
    adjustedLightLevels *= mix(0.7, 1.0, clamp01(materialAo));
#endif

#ifdef directionalLightmaps
    adjustedLightLevels *= getDirectionalLightmaps(scenePos, normal);
#endif
#elif defined PROGRAM_GBUFFERS_TERRAIN && defined pom \
    && defined pomSlopeNormals && info > 0


    vec3 normal = tbn[2];
    if (hasPom && pomSlopeFade > 1e-4) {
        normal = tbn * normalize(
            vec3(0.0, 0.0, 1.0)
            + getPomSlopeNormal(
                getLocalCoordFromUv(parallaxUv),
                uvGradient
            )
                * pomSlopeFade
        );
    }
#endif

#if defined PROGRAM_GBUFFERS_VOXELS
#define flatNormal phNormal
#define detailedNormal phNormal
#elif defined NO_NORMAL
    // No normal vector => make one from screen-space partial derivatives
    vec3 particleNormal = normalize(cross(dFdx(scenePos), dFdy(scenePos)));
#define flatNormal particleNormal
#define detailedNormal particleNormal
#else
#define flatNormal tbn[2]
#define detailedNormal normal
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
    uint newMaterialMask = fixMaterialMask();
#define materialMask newMaterialMask
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom && defined pomDepthWrite
    // pom depth write: recess the fragment into the surface by the raymarched


    gl_FragDepth = gl_FragCoord.z;
    if (hasPom && pomRelief > 1e-5) {


        float pomCosTheta = max(abs(tangentDir.z), 0.15);
        float pomRayDist = pomRelief * rcp(pomCosTheta);
        vec3 pomDisplacedScene
            = scenePos * (1.0 + pomRayDist * rcp(max(length(scenePos), 1e-3)));
        vec3 pomDisplacedView = sceneToViewSpace(pomDisplacedScene);
        vec3 pomDisplacedScreen = viewToScreenSpace(
            gbufferProjection,
            pomDisplacedView,
            true
        );
        float pomDepthZ = pomDisplacedScreen.z;
        // Only accept finite results, never pull the surface toward the
        // camera, and stay strictly inside the depth range (>= 1.0 = sky).
        if (pomDepthZ == pomDepthZ) {
            gl_FragDepth = clamp(
                max(pomDepthZ, gl_FragCoord.z),
                0.0,
                0.999999
            );
        }
    }
#endif

    gbufferData0.x = packUnorm2x8(baseColor.rg);
    gbufferData0.y = packUnorm2x8(
        baseColor.b,
        clamp01(float(materialMask) * rcp(255.0))
    );
    gbufferData0.z = packUnorm2x8(encodeUnitVector(flatNormal));
    gbufferData0.w
        = packUnorm2x8(dither8bit(adjustedLightLevels, dither));

#ifdef normalMapping
    gbufferData1.xy = encodeUnitVector(detailedNormal);
#endif

#ifdef specularMapping
#if defined pom && defined pomShadow
    // Pack parallax shadow in alpha component of specular map
    // Specular map alpha >= 0.5 => parallax shadow
    specularMap.a *= step(specularMap.a, 0.999);
    specularMap.a
        = clamp01(specularMap.a * 0.5 + 0.5 * float(parallaxShadow));
#endif

    gbufferData1.z = packUnorm2x8(specularMap.xy);
    gbufferData1.w = packUnorm2x8(specularMap.zw);
#else
#if defined pom && defined pomShadow
    gbufferData1.z = float(parallaxShadow);
#endif
#endif

#if defined PROGRAM_GBUFFERS_PARTICLES
    // Kill the little rain splash particles
    if (baseColor.r < 0.29 && baseColor.g < 0.45 && baseColor.b > 0.75) {
        discard;
    }
#endif
}
