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

layout(location = 0) out vec3 bloomTile;

/* RENDERTARGETS: 0 */

in vec2 uv;

uniform vec2 viewPixelSize;

const float tileScale = bloomTileScale(BLOOM_TILE_INDEX);
const vec2 tileOffset = bloomTileOffset(BLOOM_TILE_INDEX);

const float srcTileScale = bloomTileScale(BLOOM_TILE_INDEX + 1);
const vec2 srcTileOffset = bloomTileOffset(BLOOM_TILE_INDEX + 1);

uniform sampler2D colortex0;
#define SRC_SAMPLER colortex0

#include "/lib/util/bicubic.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    vec2 padAmount = 3.0 * viewPixelSize * rcp(tileScale);
    vec2 uvSrc = clamp(uv, padAmount, 1.0 - padAmount) * srcTileScale
        + srcTileOffset;

    const float srcWeight = mix(0.25, 0.90, 0.5 * 1.00);
    bloomTile = texelFetch(SRC_SAMPLER, texel, 0).rgb * (1.0 - srcWeight); // Destination tile.
    bloomTile += bloomUpsamplingFilter(SRC_SAMPLER, uvSrc).rgb * srcWeight; // Source tile.
}
