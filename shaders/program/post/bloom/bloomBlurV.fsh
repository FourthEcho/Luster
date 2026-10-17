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

layout(location = 0) out vec3 bloomTiles;

/* RENDERTARGETS: 0 */

in vec2 uv;

uniform sampler2D colortex0;

uniform vec2 viewRes;

const float[5] binomialWeights9
    = float[5](0.2734375, 0.21875, 0.109375, 0.03125, 0.00390625);

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Calculate the bounds of the tile containing the fragment

    float a = -log2(1.0 - uv.x);
    int tileIndex = int(a);

    float tileScale = bloomTileScale(tileIndex);
    vec2 tileOffset = bloomTileOffset(tileIndex);

    ivec2 boundsMin = ivec2(viewRes * tileOffset);
    ivec2 boundsMax = ivec2(viewRes * (tileOffset + tileScale));

    // Apply padding around bloom tiles

    if (clamp(texel.y, boundsMin.y, boundsMax.y) != texel.y
        || tileIndex > 5) {
        // Get index of closest tile
        int closestTile = (uv.y < 0.66)
            ? int(0.5 * a + 0.25) * 2
            : int(0.5 * a - 0.25) * 2 + 1;

        // Get bounds of closest tile
        float closestScale = bloomTileScale(closestTile);
        vec2 closestOffset = bloomTileOffset(closestTile);
        ivec2 closestBoundsMin = ivec2(viewRes * closestOffset + 1);
        ivec2 closestBoundsMax
            = ivec2(viewRes * (closestOffset + closestScale) - 1);

        // Clamp to closest tile
        bloomTiles = texelFetch(
                          colortex0,
                          clamp(texel, closestBoundsMin, closestBoundsMax),
                          0
        )
                          .rgb;

        return;
    }

    // Vertical 9-tap gaussian blur

    bloomTiles = vec3(0.0);
    float weightSum = 0.0;

    for (int i = -4; i <= 4; ++i) {
        float sampleY = float(texel.y) + float(i) * bloomSpread;
        if (sampleY < float(boundsMin.y + 2)
            || sampleY > float(boundsMax.y - 2)) {
            continue;
        }

        int sampleY0 = int(floor(sampleY));
        int sampleY1 = sampleY0 + 1;
        float sampleT = fract(sampleY);
        float weight = binomialWeights9[abs(i)];
        vec3 sampleColor = mix(
            texelFetch(colortex0, ivec2(texel.x, sampleY0), 0).rgb,
            texelFetch(colortex0, ivec2(texel.x, sampleY1), 0).rgb,
            sampleT
        );
        bloomTiles += sampleColor * weight;
        weightSum += weight;
    }

    bloomTiles /= weightSum;
}
