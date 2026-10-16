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

layout(location = 0) out vec4 frag_color;

/* RENDERTARGETS: 13 */

in vec2 uv;

flat in vec4 tint;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int moonPhase;
uniform int frameCounter;

uniform vec3 sun_dir;

uniform float desert_sandstorm;
uniform float rainStrength;

uniform vec2 taa_offset;
uniform vec2 view_pixel_size;

uniform float biome_may_snow;

#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/util/encoding.glsl"

const uint rain_flag = 253u;
const uint snow_flag = 254u;

void main() {
#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    vec4 base_color = texture(gtexture, uv);
    if (base_color.a < 0.1) {
        discard;
    }

    bool is_rain = (abs(base_color.r - base_color.b) > eps);

    frag_color = is_rain
        ? vec4(get_rain_color(), 0.25 * base_color.a) * tint
        : vec4(get_snow_color(), 0.75 * base_color.a) * tint;
    frag_color.rgb *= frag_color.a;
}
