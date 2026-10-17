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
#include "/lib/atmos/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fogParams;
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
#include "/lib/atmos/fog/overworld/raymarched.glsl"
#endif

#if defined WORLD_END
#include "/lib/atmos/fog/volumetric/end.glsl"
#endif

#include "/lib/atmos/fog/volumetric/water.glsl"
#include "/lib/atmos/fog/volumetric/nether.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/encoding.glsl"
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
