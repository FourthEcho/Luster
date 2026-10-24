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

out vec2 uv;

flat out vec3 ambientColor;
flat out vec3 lightColor;

#if defined WORLD_OVERWORLD
flat out vec3 sunColor;
flat out vec3 moonColor;

#include "/lib/atmos/air/overworld/params.glsl"
flat out OverworldFogParams fogParams;


flat out float rainbowAmount;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D depthtex0; // Atmosphere scattering LUT

uniform sampler2D colortex4; // Sky map and lighting colors

uniform int worldTime;
uniform int worldDay;
uniform int moonPhase;
uniform float sunAngle;
uniform float rainStrength;
uniform float wetness;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform float biomeCave;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeSnowy;
uniform float biomeTemperate;
uniform float biomeArid;
uniform float biomeTaiga;
uniform float biomeJungle;
uniform float biomeSwamp;
uniform float biomeTemperature;
uniform float biomeHumidity;
uniform float desertSandstormWeather;

uniform float worldAge;
uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define WEATHER_AURORA

#if defined WORLD_OVERWORLD
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/atmos/projection.glsl"
#include "/lib/weather/fog.glsl"
#include "/lib/weather/rainbow.glsl"
#endif

#include "/lib/util/bicubic.glsl"
#include "/lib/util/random.glsl"
void main() {
    uv = gl_MultiTexCoord0.xy;

    lightColor = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    // Flat average stays for sky/blocky-cloud consumers in this unit;
    // diffuse skylight uses the directional H-basis instead.
    ambientColor = texelFetch(colortex4, ivec2(191, 1), 0).rgb;

#if defined WORLD_OVERWORLD
    Weather weather = getWeather();

    sunColor = getSunExposure() * getSunTint();
    moonColor = getMoonExposure() * getMoonTint();
#ifdef moonPhaseNightAtmosphere
    moonColor = applyMoonPhaseInfluence(
        moonColor,
        moonPhaseNightAtmosphereIntensity * moonPhaseInfluenceIntensity,
        1.00,
        1.00
    );
#endif
    fogParams = getFogParams(weather);


    rainbowAmount = getRainbowAmount(weather);
#endif

    vec2 vertexPos = gl_Vertex.xy * taauViewportScale;
    gl_Position = vec4(vertexPos * 2.0 - 1.0, 0.0, 1.0);
}
