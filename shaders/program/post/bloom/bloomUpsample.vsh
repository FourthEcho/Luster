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

#define bloomTileScale(i) 0.5 * exp2(-(i))
#define bloomTileOffset(i) \
    vec2(1.0 - exp2(-(i)), float((i) & 1) * (1.0 - 0.5 * exp2(-(i))))

out vec2 uv;

uniform vec2 viewPixelSize;

const float tileScale = bloomTileScale(BLOOM_TILE_INDEX);
const vec2 tileOffset = bloomTileOffset(BLOOM_TILE_INDEX);

void main() {
    uv = gl_MultiTexCoord0.xy;

    vec2 vertexPos = gl_Vertex.xy * tileScale + tileOffset;

    gl_Position = vec4(vertexPos * 2.0 - 1.0, 0.0, 1.0);
}
