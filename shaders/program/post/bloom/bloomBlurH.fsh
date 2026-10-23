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

    int tileIndex = int(-log2(1.0 - uv.x));

    float tileScale = bloomTileScale(tileIndex);
    vec2 tileOffset = bloomTileOffset(tileIndex);

    ivec2 boundsMin = ivec2(viewRes * tileOffset);
    ivec2 boundsMax = ivec2(viewRes * (tileOffset + tileScale));

    // Discard fragments that aren't part of a bloom tile

    if (clamp(texel.y, boundsMin.y, boundsMax.y) != texel.y
        || tileIndex > 5) {
        discard;
        return;
    }

    // Horizontal 9-tap gaussian blur

    bloomTiles = vec3(0.0);
    float weightSum = 0.0;

    for (int i = -4; i <= 4; ++i) {
        float sampleX = float(texel.x) + float(i) * bloomSpread;
        if (sampleX < float(boundsMin.x + 2)
            || sampleX > float(boundsMax.x - 2)) {
            continue;
        }

        int sampleX0 = int(floor(sampleX));
        int sampleX1 = sampleX0 + 1;
        float sampleT = fract(sampleX);
        float weight = binomialWeights9[abs(i)];
        vec3 sampleColor = mix(
            texelFetch(colortex0, ivec2(sampleX0, texel.y), 0).rgb,
            texelFetch(colortex0, ivec2(sampleX1, texel.y), 0).rgb,
            sampleT
        );
        bloomTiles += sampleColor * weight;
        weightSum += weight;
    }

    bloomTiles /= weightSum;
}
