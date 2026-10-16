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

layout(location = 0) out vec3 frag_color;

/* RENDERTARGETS: 0 */

in vec2 uv;
in vec3 view_pos;

#if MC_VERSION >= 260100
in vec2 uv_mid;
#endif

flat in vec3 tint;
flat in vec3 sun_color;
flat in vec3 moon_color;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int moonPhase;
uniform int renderStage;

uniform vec3 view_sun_dir;

uniform float desert_sandstorm;
uniform float rainStrength;

#include "/lib/sky/atmosphere.glsl"
#include "/lib/util/color.glsl"

const float vanilla_sun_luminance = 10.0;
const float moon_luminance = 10.0;

void main() {
    vec2 new_uv = uv;
    vec2 offset;

    if (renderStage == MC_RENDER_STAGE_CUSTOM_SKY) {
        frag_color = vec3(0.0);
    } else if (dot(view_pos, view_sun_dir) > 0.0) {
        // Sun

        // NB: not using renderStage to distinguish sun and moon because it's
        // broken in Iris for Minecraft 1.21.4

        // Cut out the sun itself (discard the halo around it)
        if (max_of(abs(offset)) > 0.25) {
            discard;
        }
        offset = uv * 2.0 - 1.0;

#ifdef vanillaSun
        frag_color = texture(gtexture, new_uv).rgb;
        frag_color = srgb_eotf_inv(frag_color) * rec709_to_working_color;
        frag_color *= dot(frag_color, luminance_weights)
            * (sunlight_color * vanilla_sun_luminance) * sun_color;
#else
        frag_color = vec3(0.0);
#endif
    } else {
        // Moon
#ifdef vanillaMoon
        frag_color
            = texture(gtexture, new_uv).rgb * vec3(moonR, moonG, moonB);

        frag_color = srgb_eotf_inv(frag_color) * rec709_to_working_color;
        frag_color *= sunlight_color * moon_luminance;
#else
        frag_color = vec3(0.0);
#endif
    }
}
