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
out vec3 view_pos;

#if MC_VERSION >= 260100
out vec2 uv_mid;
#endif

flat out vec3 tint;
flat out vec3 sun_color;
flat out vec3 moon_color;

#if MC_VERSION >= 260100
attribute vec2 mc_midTexCoord;
#endif

// ------------
//   Uniforms
// ------------

uniform float sunAngle;
uniform float rainStrength;
uniform float desert_sandstorm;
uniform int moonPhase;

uniform vec2 taa_offset;

uniform vec3 sun_dir;
uniform vec3 light_dir;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR

void main() {
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

    uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy
        + gl_TextureMatrix[0][3].xy;
    tint = gl_Color.rgb;

#if MC_VERSION >= 260100
    uv_mid = mat2(gl_TextureMatrix[0]) * mc_midTexCoord
        + gl_TextureMatrix[0][3].xy;
#endif

    view_pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

    vec4 clip_pos = project(gl_ProjectionMatrix, view_pos);

#if defined taa && defined taau
    clip_pos.xy = clip_pos.xy * taau_render_scale
        + clip_pos.w * (taau_render_scale - 1.0);
    clip_pos.xy += taa_offset * clip_pos.w;
#elif defined taa
    clip_pos.xy += taa_offset * clip_pos.w * 0.75;
#endif

    gl_Position = clip_pos;
}
