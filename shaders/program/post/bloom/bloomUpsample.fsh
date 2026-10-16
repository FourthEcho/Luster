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

#define bloom_tile_scale(i) 0.5 * exp2(-(i))
#define bloom_tile_offset(i) \
    vec2(1.0 - exp2(-(i)), float((i) & 1) * (1.0 - 0.5 * exp2(-(i))))

layout(location = 0) out vec3 bloom_tile;

/* RENDERTARGETS: 0 */

in vec2 uv;

uniform vec2 view_pixel_size;

const float tile_scale = bloom_tile_scale(BLOOM_TILE_INDEX);
const vec2 tile_offset = bloom_tile_offset(BLOOM_TILE_INDEX);

const float src_tile_scale = bloom_tile_scale(BLOOM_TILE_INDEX + 1);
const vec2 src_tile_offset = bloom_tile_offset(BLOOM_TILE_INDEX + 1);

uniform sampler2D colortex0;
#define SRC_SAMPLER colortex0

#include "/lib/util/bicubic.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    vec2 pad_amount = 3.0 * view_pixel_size * rcp(tile_scale);
    vec2 uv_src = clamp(uv, pad_amount, 1.0 - pad_amount) * src_tile_scale
        + src_tile_offset;

    const float src_weight = mix(0.25, 0.90, 0.5 * 1.00);
    bloom_tile = texelFetch(SRC_SAMPLER, texel, 0).rgb * (1.0 - src_weight); // Destination tile.
    bloom_tile += bloomUpsamplingFilter(SRC_SAMPLER, uv_src).rgb * src_weight; // Source tile.
}
