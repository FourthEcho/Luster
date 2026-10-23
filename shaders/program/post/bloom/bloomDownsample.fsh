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

#if BLOOM_TILE_INDEX == 0
// Initial tile reads taa output directly
const float srcTileScale = 1.0;
const vec2 srcTileOffset = vec2(0.0);
uniform sampler2D colortex5;
#define SRC_SAMPLER colortex5
#else
// Subsequent tiles read from colortex0
const float srcTileScale = bloomTileScale(BLOOM_TILE_INDEX - 1);
const vec2 srcTileOffset = bloomTileOffset(BLOOM_TILE_INDEX - 1);
uniform sampler2D colortex0;
#define SRC_SAMPLER colortex0
#endif

// Reference: "Next Generation Post-Processing in Call of Duty Advanced Warfare".

void main() {
    vec2 padAmount = 3.0 * viewPixelSize * rcp(srcTileScale);
    vec2 uvSrc = clamp(uv, padAmount, 1.0 - padAmount) * srcTileScale
        + srcTileOffset;


    bloomTile
        = textureLod(SRC_SAMPLER, uvSrc + vec2(0.0, 0.0) * viewPixelSize, 0)
              .rgb
        * 0.125;

    bloomTile
        += textureLod(SRC_SAMPLER, uvSrc + vec2(1.0, 1.0) * viewPixelSize, 0)
               .rgb
        * 0.125;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(-1.0, 1.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.125;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(1.0, -1.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.125;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(-1.0, -1.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.125;

    bloomTile
        += textureLod(SRC_SAMPLER, uvSrc + vec2(2.0, 0.0) * viewPixelSize, 0)
               .rgb
        * 0.0625;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(-2.0, 0.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.0625;
    bloomTile
        += textureLod(SRC_SAMPLER, uvSrc + vec2(0.0, 2.0) * viewPixelSize, 0)
               .rgb
        * 0.0625;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(0.0, -2.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.0625;

    bloomTile
        += textureLod(SRC_SAMPLER, uvSrc + vec2(2.0, 2.0) * viewPixelSize, 0)
               .rgb
        * 0.03125;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(-2.0, 2.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.03125;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(2.0, -2.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.03125;
    bloomTile += textureLod(
                      SRC_SAMPLER,
                      uvSrc + vec2(-2.0, -2.0) * viewPixelSize,
                      0
                  )
                      .rgb
        * 0.03125;
}
