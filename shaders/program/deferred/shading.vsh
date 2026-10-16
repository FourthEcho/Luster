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
#ifdef hBasisSkylight
flat out vec3 h_sky[6];
#endif

#if defined WORLD_OVERWORLD
flat out vec3 sun_color;
flat out vec3 moon_color;

#include "/lib/fog/overworld/parameters.glsl"
flat out OverworldFogParameters fog_params;


flat out float rainbow_amount;
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

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform float biome_cave;
uniform float biome_may_rain;
uniform float biome_may_snow;
uniform float biome_snowy;
uniform float biome_temperate;
uniform float biome_arid;
uniform float biome_taiga;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_temperature;
uniform float biome_humidity;
uniform float desert_sandstorm;

uniform float world_age;
uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

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
#include "/lib/sky/atmosphere.glsl"
#include "/lib/sky/projection.glsl"
#include "/lib/weather/fog.glsl"
#include "/lib/weather/rainbow.glsl"
#endif

#include "/lib/util/bicubic.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/sampling.glsl"
#if !defined INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
#define INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

// H-basis directional sky ambient.

#include "/lib/sky/projection.glsl"

void project_sky_h_basis(out vec3 h[6]) {
    for (int i = 0; i < 6; ++i) {
        h[i] = vec3(0.0);
    }

    for (int i = 0; i < hBasisSkySamples; ++i) {
        // Uniform-sphere low-discrepancy sequence (deterministic by design).
        vec2 u = vec2(
            (float(i) + 0.5) / float(hBasisSkySamples),
            fract(float(i) * 0.61803398875)
        );

        float phi = tau * u.y;
        float cos_theta = 2.0 * u.x - 1.0;
        float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
        vec3 d = vec3(
            sin_theta * cos(phi), cos_theta, sin_theta * sin(phi)
        );

        vec3 radiance = max0(texture(colortex4, project_sky(d)).rgb);

        h[0] += radiance;
        h[1] += radiance * d.x;
        h[2] += radiance * d.y;
        h[3] += radiance * d.z;
        h[4] += radiance * (1.5 * d.y * d.y - 0.5);
        h[5] += radiance * (d.x * d.x - d.z * d.z) * 0.5;
    }

    float inv_n = 1.0 / float(hBasisSkySamples);
    for (int i = 0; i < 6; ++i) {
        h[i] *= inv_n;
    }
}

vec3 evaluate_h_basis_irradiance(vec3 h[6], vec3 normal) {
    vec3 n = normalize(normal);

    vec3 result = h[0] * pi;
    result += (2.0 * pi / 3.0) * (h[1] * n.x + h[2] * n.y + h[3] * n.z);
    result += (pi * 0.125) * h[4] * (3.0 * n.y * n.y - 1.0);
    result += (pi * 0.125) * h[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

void main() {
    uv = gl_MultiTexCoord0.xy;

    light_color = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    // Flat average stays for sky/blocky-cloud consumers in this unit;
    // diffuse skylight uses the directional H-basis instead.
    ambient_color = texelFetch(colortex4, ivec2(191, 1), 0).rgb;
#ifdef hBasisSkylight
    project_sky_h_basis(h_sky);
#endif

#if defined WORLD_OVERWORLD
    Weather weather = get_weather();

    sun_color = get_sun_exposure() * get_sun_tint();
    moon_color = get_moon_exposure() * get_moon_tint();
#ifdef moonPhaseNightAtmosphere
    moon_color = apply_moon_phase_influence(
        moon_color,
        moonPhaseNightAtmosphereIntensity * moonPhaseInfluenceIntensity,
        1.00,
        1.00
    );
#endif
    fog_params = get_fog_parameters(weather);


    rainbow_amount = get_rainbow_amount(weather);
#endif

    vec2 vertex_pos = gl_Vertex.xy * taau_render_scale;
    gl_Position = vec4(vertex_pos * 2.0 - 1.0, 0.0, 1.0);
}
