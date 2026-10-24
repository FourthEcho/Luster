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



vec3 reinhard(vec3 rgb) {
    rgb.r = (isnan(rgb.r) || isinf(rgb.r)) ? 0.0 : rgb.r;
    rgb.g = (isnan(rgb.g) || isinf(rgb.g)) ? 0.0 : rgb.g;
    rgb.b = (isnan(rgb.b) || isinf(rgb.b)) ? 0.0 : rgb.b;
    rgb = max(rgb, vec3(0.0));
    return rgb / (rgb + 1.0);
}

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

    // Build conservative RGB bounds in Reinhard-compressed space. Storing
    // RGB bounds lets the resolve clamp both Catmull-Rom ringing and the
    // reconstructed temporal history without extra full-resolution samples.
    a = reinhard(a);
    b = reinhard(b);
    c = reinhard(c);
    d = reinhard(d);
    e = reinhard(e);
    f = reinhard(f);
    g = reinhard(g);
    h = reinhard(h);
    i = reinhard(i);

    // Use the full neighborhood extrema. These bounds also constrain the
    // current Catmull-Rom reconstruction, so they must include every source
    // sample and only suppress filter ringing beyond the actual 3x3 range.
    minColor = min(minOf(b, d, e, f, h), min(min(a, c), min(g, i)));
    maxColor = max(maxOf(b, d, e, f, h), max(max(a, c), max(g, i)));
}
//----------------------------------------------------------------------------//
