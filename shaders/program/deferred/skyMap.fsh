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

layout(location = 0) out vec3 skyMap;

/* RENDERTARGETS: 4 */

in vec2 uv;

flat in vec3 ambientColor;
flat in vec3 lightColor;

#if defined WORLD_OVERWORLD
flat in vec3 sunColor;
flat in vec3 moonColor;
flat in vec3 skyColor;

flat in float auroraAmount;
flat in mat2x3 auroraColors;

flat in float rainbowAmount;

#include "/lib/atmos/sky/clouds/core/parameters.glsl"
flat in CloudsParameters cloudsParams;

#include "/lib/atmos/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fogParams;
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

#if defined WORLD_OVERWORLD && defined galaxy
uniform sampler2D colortex13;
#define galaxySampler colortex13
#endif

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D depthtex1;

uniform sampler2D colortex8; // cloud shadow map

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
uniform float desertSandstormWeather;
uniform float blindness;
uniform float darknessFactor;

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

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0

#ifdef cloudsCumulusPrecomputeLocalCoverage
#define CLOUDS_USE_LOCAL_COVERAGE_MAP
#endif

#if defined WORLD_OVERWORLD
#include "/lib/atmos/fog/overworld/analytic.glsl"
#include "/lib/atmos/sky/aurora.glsl"
#endif

#include "/lib/atmos/projection.glsl"
#include "/lib/atmos/sky/sky.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    if (texel.x == skyMapRes.x) { // Store lighting colors
        skyMap = vec3(0.0);
        switch (texel.y) {
            case 0:
                skyMap = lightColor;
                break;

            case 1:
                skyMap = ambientColor;
                break;
        }
    } else { // Draw sky map
        vec3 rayDir = unprojectSky(uv);

        skyMap = drawSky(rayDir);

#if defined WORLD_OVERWORLD
        // Apply analytic fog over sky
        mat2x3 fog = airFogAnalytic(
            cameraPosition,
            cameraPosition + rayDir,
            true,
            eyeSkylight,
            1.0
        );
        skyMap = skyMap * fog[1] + fog[0];
#endif
    }
}
