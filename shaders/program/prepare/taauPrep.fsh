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

layout(location = 0) out vec3 minColor;
layout(location = 1) out vec3 maxColor;

/* RENDERTARGETS: 1,2 */

in vec2 uv;

uniform sampler2D colortex0;

#include "/lib/util/color.glsl"


vec3 reinhard(vec3 rgb) { return rgb / (rgb + 1.0); }

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Fetch 3x3 neighborhood
    // a b c
    // d e f
    // g h i
    vec3 a = texelFetch(colortex0, texel + ivec2(-1, 1), 0).rgb;
    vec3 b = texelFetch(colortex0, texel + ivec2(0, 1), 0).rgb;
    vec3 c = texelFetch(colortex0, texel + ivec2(1, 1), 0).rgb;
    vec3 d = texelFetch(colortex0, texel + ivec2(-1, 0), 0).rgb;
    vec3 e = texelFetch(colortex0, texel, 0).rgb;
    vec3 f = texelFetch(colortex0, texel + ivec2(1, 0), 0).rgb;
    vec3 g = texelFetch(colortex0, texel + ivec2(-1, -1), 0).rgb;
    vec3 h = texelFetch(colortex0, texel + ivec2(0, -1), 0).rgb;
    vec3 i = texelFetch(colortex0, texel + ivec2(1, -1), 0).rgb;

    // Convert to YCoCg
    a = rgbToYcocg(reinhard(a));
    b = rgbToYcocg(reinhard(b));
    c = rgbToYcocg(reinhard(c));
    d = rgbToYcocg(reinhard(d));
    e = rgbToYcocg(reinhard(e));
    f = rgbToYcocg(reinhard(f));
    g = rgbToYcocg(reinhard(g));
    h = rgbToYcocg(reinhard(h));
    i = rgbToYcocg(reinhard(i));


    // family; cf. Yang et al., "A Survey of Temporal Antialiasing


    minColor = minOf(b, d, e, f, h);
    minColor += minOf(minColor, a, c, g, i);
    minColor *= 0.5;

    maxColor = maxOf(b, d, e, f, h);
    maxColor += maxOf(maxColor, a, c, g, i);
    maxColor *= 0.5;

    minColor = minColor * 0.5 + 0.5;
    maxColor = maxColor * 0.5 + 0.5;
}
//----------------------------------------------------------------------------//
