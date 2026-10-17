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

layout(location = 0) out vec3 fragColor;

/* RENDERTARGETS: 0 */

in vec2 uv;
in vec3 viewPos;

#if MC_VERSION >= 260100
in vec2 uvMid;
#endif

flat in vec3 tint;
flat in vec3 sunColor;
flat in vec3 moonColor;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int moonPhase;
uniform int renderStage;

uniform vec3 viewSunDir;

uniform float desertSandstormWeather;
uniform float rainStrength;

#include "/lib/atmos/atmosphere.glsl"
#include "/lib/util/color.glsl"

const float vanillaSunLuminance = 10.0;
const float moonLuminance = 10.0;

void main() {
    vec2 newUv = uv;
    vec2 offset;

    if (renderStage == MC_RENDER_STAGE_CUSTOM_SKY) {
        fragColor = vec3(0.0);
    } else if (dot(viewPos, viewSunDir) > 0.0) {
        // Sun

        // NB: not using renderStage to distinguish sun and moon because it's
        // broken in Iris for Minecraft 1.21.4

        // Cut out the sun itself (discard the halo around it)
        if (maxOf(abs(offset)) > 0.25) {
            discard;
        }
        offset = uv * 2.0 - 1.0;

#ifdef vanillaSun
        fragColor = texture(gtexture, newUv).rgb;
        fragColor = srgbEotfInv(fragColor) * rec709ToWorkingColor;
        fragColor *= dot(fragColor, luminanceWeights)
            * (sunlightColor * vanillaSunLuminance) * sunColor;
#else
        fragColor = vec3(0.0);
#endif
    } else {
        // Moon
#ifdef vanillaMoon
        fragColor
            = texture(gtexture, newUv).rgb * vec3(moonR, moonG, moonB);

        fragColor = srgbEotfInv(fragColor) * rec709ToWorkingColor;
        fragColor *= sunlightColor * moonLuminance;
#else
        fragColor = vec3(0.0);
#endif
    }
}
