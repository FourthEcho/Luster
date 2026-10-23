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

layout(location = 0) out vec4 aoHistory;

/* RENDERTARGETS: 6 */

uniform sampler2D colortex6;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    aoHistory = texelFetch(colortex6, texel, 0);
}
