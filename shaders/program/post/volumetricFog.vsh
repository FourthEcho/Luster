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
#include "/lib/atmos/air/overworld/params.glsl"
flat out OverworldFogParams fogParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex4; // Sky map and lighting color palette

uniform float rainStrength;
uniform float sunAngle;

uniform int worldTime;
uniform int worldDay;

uniform vec3 sunDir;

uniform float wetness;

uniform float eyeSkylight;

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

uniform float worldAge;
uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float desertSandstormWeather;

#if defined WORLD_OVERWORLD
#include "/lib/atmos/projection.glsl"
#include "/lib/weather/fog.glsl"
#endif

void main() {
    uv = gl_MultiTexCoord0.xy;

    lightColor = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    ambientColor = texelFetch(colortex4, ivec2(191, 1), 0).rgb;

#if defined WORLD_OVERWORLD
    fogParams = getFogParams(getWeather());
#endif

    vec2 vertexPos = gl_Vertex.xy;
    gl_Position = vec4(vertexPos * 2.0 - 1.0, 0.0, 1.0);
}
