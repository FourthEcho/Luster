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

#if defined WORLD_OVERWORLD
flat out vec3 sunColor;
flat out vec3 moonColor;
flat out vec3 skyColor;

flat out float auroraAmount;
flat out mat2x3 auroraColors;

#include "/lib/atmos/sky/clouds/core/parameters.glsl"
flat out CloudsParameters cloudsParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D noisetex;

uniform int worldTime;
uniform int worldDay;
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

uniform float desertSandstormWeather;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0

#if defined WORLD_OVERWORLD
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/atmos/atmosphere.glsl"
#include "/lib/atmos/sky/aurora.glsl"
#include "/lib/weather/clouds.glsl"
#endif

void main() {
    uv = gl_MultiTexCoord0.xy;

#if defined WORLD_OVERWORLD
    sunColor = getSunExposure() * getSunTint();
    moonColor = getMoonExposure() * getMoonTint();

    const vec3 skyDir = normalize(
        vec3(0.0, 1.0, -0.8)
    ); // don't point direcly upwards to avoid the sun halo when the sun path
       // rotation is 0
    skyColor = atmosphereScattering(
        skyDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        /* useKleinNishinaPhase */ false
    );
    skyColor = (tau * 1.13) * skyColor;
    skyColor = mix(skyColor, tau * getWeatherColor(), rainStrength);

    auroraAmount = getAuroraAmount();
    auroraColors = getAuroraColors();

    cloudsParams = getCloudsParameters(getWeather());

    skyColor += auroraAmount * auroraCloudLighting
        * mix(auroraColors[0], auroraColors[1], 0.25);
#endif

    vec2 vertexPos = gl_Vertex.xy * taauViewportScale;
    gl_Position = vec4(vertexPos * 2.0 - 1.0, 0.0, 1.0);
}
