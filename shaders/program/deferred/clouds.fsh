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

// Declared before the atmosphere/sandstorm include so desertSandstorm can use it.
uniform float desertSandstormWeather;

layout(location = 0) out vec4 clouds;
layout(location = 1) out vec2 cloudsData;

/* RENDERTARGETS: 9,10 */

in vec2 uv;

#if defined WORLD_OVERWORLD
flat in vec3 sunColor;
flat in vec3 moonColor;
flat in vec3 skyColor;

flat in float auroraAmount;
flat in mat2x3 auroraColors;

#include "/lib/atmos/sky/clouds/core/parameters.glsl"
flat in CloudsParameters cloudsParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D colortex6; // 3D bubbly worley noise
#define SAMPLER_WORLEY_BUBBLY colortex6
uniform sampler3D colortex7; // 3D swirley worley noise
#define SAMPLER_WORLEY_SWIRLEY colortex7
uniform sampler3D cumulusCurl;
#define SAMPLER_CUMULUS_CURL cumulusCurl

uniform sampler2D colortex8; // cloud shadow map

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D depthtex1;

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

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
uniform float wetness;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float worldAge;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float biomeCave;
uniform float biomeTemperate;
uniform float biomeArid;
uniform float biomeSnowy;
uniform float biomeTaiga;
uniform float biomeJungle;
uniform float biomeSwamp;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeTemperature;
uniform float biomeHumidity;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define MIE_PHASE_CLAMP

#ifdef cloudsCumulusPrecomputeLocalCoverage
#define CLOUDS_USE_LOCAL_COVERAGE_MAP
#endif

#if defined WORLD_OVERWORLD
#include "/lib/atmos/atmosphere.glsl"
#include "/lib/atmos/sky/aurora.glsl"
#include "/lib/atmos/sky/clouds/pipeline.glsl"

#if defined crepuscularRays && !defined blockyClouds
#include "/lib/atmos/crepuscularRays.glsl"
#endif
#endif

#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/checkerboard.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

const int checkerboardArea
    = cloudsTemporalUpscaling * cloudsTemporalUpscaling;

float depthMax4x4(sampler2D depthSampler, float scale) {
    vec4 depthSamples0 = textureGather(
        depthSampler,
        uv * scale + vec2(2.0 * viewPixelSize.x, 2.0 * viewPixelSize.y)
    );
    vec4 depthSamples1 = textureGather(
        depthSampler,
        uv * scale + vec2(-2.0 * viewPixelSize.x, 2.0 * viewPixelSize.y)
    );
    vec4 depthSamples2 = textureGather(
        depthSampler,
        uv * scale + vec2(2.0 * viewPixelSize.x, -2.0 * viewPixelSize.y)
    );
    vec4 depthSamples3 = textureGather(
        depthSampler,
        uv * scale + vec2(-2.0 * viewPixelSize.x, -2.0 * viewPixelSize.y)
    );

    return max(
        max(maxOf(depthSamples0), maxOf(depthSamples1)),
        max(maxOf(depthSamples2), maxOf(depthSamples3))
    );
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    clouds = vec4(0.0, 0.0, 0.0, 1.0);

#if defined WORLD_OVERWORLD
    ivec2 checkerboardPos = cloudsTemporalUpscaling * texel
        + cloudsCheckerboardOffsets[frameCounter % checkerboardArea];

    vec2 newUv = vec2(checkerboardPos) / vec2(viewRes)
        * rcp(float(taauViewportScale));

    // Get maximum depth from area covered by this fragment
    float depthMax = depthMax4x4(depthtex1, taauViewportScale);

    vec3 screenPos = vec3(newUv, depthMax);
    vec3 viewPos = screenToViewSpace(screenPos, false);

    // LoD terrain support
#ifdef LOD_MOD_ACTIVE
    float depthLod
        = depthMax4x4(lodDepthTexShading, lodDepthTexScale);
    bool isLod = isLodTerrain(depthMax, depthLod);

    if (isLod) {
        screenPos = vec3(newUv, depthLod);
        viewPos = screenToViewSpace(screenPos, false, true);
    }
#else
    const bool isLod = false;
#endif

    vec3 rayOrigin
        = vec3(
              0.0,
              cloudsScale * (eyeAltitude - 63.0) + planetRadius,
              0.0
          )
        + cloudsScale * gbufferModelViewInverse[3].xyz;
    vec3 rayDir = mat3(gbufferModelViewInverse) * normalize(viewPos);

    float distanceToTerrain = (depthMax == 1.0 && !isLod)
        ? -1.0
        : length(viewPos) * cloudsScale;

    vec3 clearSky = atmosphereScattering(
        rayDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        /* useKleinNishinaPhase */ false
    );

    float dither = texelFetch(noisetex, ivec2(checkerboardPos & 511), 0).b;
    dither = r1(frameCounter / checkerboardArea, dither);

#ifndef blockyClouds
    CloudsResult result = drawClouds(
        rayOrigin,
        rayDir,
        clearSky,
        distanceToTerrain,
        dither
    );

    clouds.xyz = result.scattering.xyz;
    clouds.w = result.transmittance;
    cloudsData.x = result.apparentDistance * rcp(cloudsScale);
    cloudsData.y = result.scattering.w;
#else
    clouds = vec4(0.0, 0.0, 0.0, 1.0);
    cloudsData.x = 1e6;
    cloudsData.y = 0.0;
#endif

    // Crepuscular rays

#if defined crepuscularRays && !defined blockyClouds
    vec4 crepuscularRaysSample = drawCrepuscularRays(
        colortex8,
        rayDir,
        distanceToTerrain > 0.0,
        dither
    );
    clouds *= crepuscularRaysSample.w;
    clouds.rgb += crepuscularRaysSample.xyz;
#endif

    // Aurora

    clouds.xyz += drawAurora(rayDir, dither) * clouds.w;
#endif
}
