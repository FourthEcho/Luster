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

flat out vec3 ambient_color;
flat out vec3 light_color;

#if defined WORLD_OVERWORLD
flat out vec3 sun_color;
flat out vec3 moon_color;
flat out vec3 sky_color;

flat out float aurora_amount;
flat out mat2x3 aurora_colors;

flat out float rainbow_amount;

#include "/lib/sky/clouds/parameters.glsl"
flat out CloudsParameters clouds_params;

#include "/lib/fog/overworld/parameters.glsl"
flat out OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D depthtex0; // atmospheric scattering LUT

uniform float blindness;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float wetness;

uniform int worldTime;
uniform int worldDay;
uniform int moonPhase;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;

uniform vec3 fogColor;

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
#include "/lib/sky/auroraColors.glsl"
#include "/lib/weather/clouds.glsl"
#include "/lib/weather/fog.glsl"
#include "/lib/weather/rainbow.glsl"
#endif
// Dimension-specific light and ambient colors (inlined; single consumer)
#include "/lib/util/color.glsl"

#if defined WORLD_NETHER
vec3 get_light_color() { return vec3(0.0); }

vec3 get_ambient_color() {
#ifdef netherUseBiomeColor
    vec3 nether_color = srgb_eotf_inv(fogColor) * rec709_to_working_color;
    nether_color /= max(dot(nether_color, luminance_weights), eps);
    nether_color = mix(vec3(1.0), nether_color, netherS);
    nether_color *= 0.05 * netherI;
#else
    vec3 nether_color
        = from_display(vec3(netherR, netherG, netherB)) * 0.1 * netherI;
#endif

    return nether_color;
}
#elif defined WORLD_END
vec3 get_light_color() {
    return from_display(vec3(endLightR, endLightG, endLightB)) * endLightI;
}

vec3 get_ambient_color() {
    return from_display(vec3(endAmbientR, endAmbientG, endAmbientB))
        * endAmbientI;
}
#endif
#if defined WORLD_OVERWORLD
vec3 get_ambient_color() {
    sun_color = get_sun_exposure() * get_sun_tint();
    moon_color = get_moon_exposure() * get_moon_tint();

    const vec3 sky_dir = normalize(
        vec3(0.0, 1.0, -0.8)
    ); // don't point direcly upwards to avoid the sun halo when the sun path
       // rotation is 0
    sky_color = atmosphere_scattering(
        sky_dir,
        sun_color,
        sun_dir,
        moon_color,
        moon_dir,
        false
    );
    sky_color = tau * sky_color * 1.13;
#ifdef desertSandstorm


    sky_color = mix(
        sky_color,
        tau * get_weather_color(),
        clamp01(rainStrength + desert_sandstorm)
    );
#else
    sky_color = mix(sky_color, tau * get_weather_color(), rainStrength);
#endif

    return sky_color;
}
#endif

void main() {
    uv = gl_MultiTexCoord0.xy;

    light_color = get_light_color();
    ambient_color = get_ambient_color();

#if defined WORLD_OVERWORLD
    aurora_amount = get_aurora_amount();
    aurora_colors = get_aurora_colors();

    Weather weather = get_weather();
    rainbow_amount = get_rainbow_amount(weather);
    clouds_params = get_clouds_parameters(weather);
    fog_params = get_fog_parameters(weather);


    vec3 aurora_lighting
        = mix(aurora_colors[0], aurora_colors[1], 0.25) * aurora_amount;
    sky_color += auroraCloudLighting * aurora_lighting;
    ambient_color += auroraGroundLighting * aurora_lighting;
#endif

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
