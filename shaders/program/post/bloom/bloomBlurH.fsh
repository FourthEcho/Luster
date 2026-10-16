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

layout(location = 0) out vec3 bloom_tiles;

/* RENDERTARGETS: 0 */

in vec2 uv;

uniform sampler2D colortex0;

uniform vec2 view_res;

const float[5] binomial_weights_9
    = float[5](0.2734375, 0.21875, 0.109375, 0.03125, 0.00390625);

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Calculate the bounds of the tile containing the fragment

    int tile_index = int(-log2(1.0 - uv.x));

    float tile_scale = bloom_tile_scale(tile_index);
    vec2 tile_offset = bloom_tile_offset(tile_index);

    ivec2 bounds_min = ivec2(view_res * tile_offset);
    ivec2 bounds_max = ivec2(view_res * (tile_offset + tile_scale));

    // Discard fragments that aren't part of a bloom tile

    if (clamp(texel.y, bounds_min.y, bounds_max.y) != texel.y
        || tile_index > 5) {
        discard;
        return;
    }

    // Horizontal 9-tap gaussian blur

    bloom_tiles = vec3(0.0);
    float weight_sum = 0.0;

    for (int i = -4; i <= 4; ++i) {
        float sample_x = float(texel.x) + float(i) * bloomSpread;
        if (sample_x < float(bounds_min.x + 2)
            || sample_x > float(bounds_max.x - 2)) {
            continue;
        }

        int sample_x0 = int(floor(sample_x));
        int sample_x1 = sample_x0 + 1;
        float sample_t = fract(sample_x);
        float weight = binomial_weights_9[abs(i)];
        vec3 sample_color = mix(
            texelFetch(colortex0, ivec2(sample_x0, texel.y), 0).rgb,
            texelFetch(colortex0, ivec2(sample_x1, texel.y), 0).rgb,
            sample_t
        );
        bloom_tiles += sample_color * weight;
        weight_sum += weight;
    }

    bloom_tiles /= weight_sum;
}
