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

#include "/lib/sky/clouds/parameters.glsl"
flat out CloudsParameters clouds_params;


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

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform float world_age;
uniform float eye_skylight;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float biome_cave;
uniform float biome_temperate;
uniform float biome_arid;
uniform float biome_snowy;
uniform float biome_taiga;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_may_rain;
uniform float biome_may_snow;
uniform float biome_temperature;
uniform float biome_humidity;

uniform float desert_sandstorm;

#include "/lib/weather/clouds.glsl"


void main() {
    uv = gl_MultiTexCoord0.xy;

    Weather weather = get_weather();
    clouds_params = get_clouds_parameters(weather);


    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}

#ifndef cloudShadows
#error "This program should be disabled if Cloud Shadows are disabled"
#endif
