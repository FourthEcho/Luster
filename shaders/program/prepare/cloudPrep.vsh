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

#include "/lib/atmos/clouds/utility/params.glsl"
flat out CloudsParams cloudsParams;


// ------------
//   Uniforms
// ------------

uniform int worldTime;
uniform int worldDay;

uniform float rainStrength;
uniform float wetness;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int moonPhase;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform float worldAge;
uniform float eyeSkylight;

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

#include "/lib/weather/clouds.glsl"


void main() {
    uv = gl_MultiTexCoord0.xy;

    Weather weather = getWeather();
    cloudsParams = getCloudsParams(weather);


    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}

#ifndef cloudShadows
#error "This program should be disabled if Cloud Shadows are disabled"
#endif
