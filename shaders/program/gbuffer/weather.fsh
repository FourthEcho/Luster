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

layout(location = 0) out vec4 fragColor;

/* RENDERTARGETS: 13 */

in vec2 uv;

flat in vec4 tint;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int moonPhase;
uniform int frameCounter;

uniform vec3 sunDir;

uniform float desertSandstormWeather;
uniform float rainStrength;

uniform vec2 taaOffset;
uniform vec2 viewPixelSize;

uniform float biomeMaySnow;

#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/weather/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/util/encode.glsl"

const uint rainFlag = 253u;
const uint snowFlag = 254u;

void main() {
#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    vec4 baseColor = texture(gtexture, uv);
    if (baseColor.a < 0.1) {
        discard;
    }

    bool isRain = (abs(baseColor.r - baseColor.b) > eps);

    fragColor = isRain
        ? vec4(getRainColor(), 0.25 * baseColor.a) * tint
        : vec4(getSnowColor(), 0.75 * baseColor.a) * tint;
    fragColor.rgb *= fragColor.a;
}
