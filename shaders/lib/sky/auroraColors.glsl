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

#if !defined INCLUDE_SKY_AURORA_COLORS
#define INCLUDE_SKY_AURORA_COLORS

#include "/lib/util/random.glsl"

// [0] - bottom color
// [1] - top color
mat2x3 get_aurora_colors() {
    const mat2x3[] aurora_colors = mat2x3[](
        mat2x3(
            vec3(0.00, 1.00, 0.25), // green
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(0.00, 1.00, 0.25), // green
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.00, 0.00), // red
            vec3(1.00, 0.50, 0.70) // purple
        ),
        mat2x3(
            vec3(1.00, 0.25, 1.00), // magenta
            vec3(0.25, 0.25, 1.00) // deep blue
        ),
        mat2x3(
            vec3(1.00, 0.50, 1.00), // purple
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.50, 1.00), // purple
            vec3(0.50, 0.70, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.10, 0.00), // red
            vec3(1.00, 1.00, 0.25) // yellow
        ),
        mat2x3(
            vec3(1.00, 1.00, 1.00), // white
            vec3(1.00, 0.00, 0.00) // red
        ),
        mat2x3(
            vec3(1.00, 1.00, 0.00), // yellow
            vec3(0.10, 0.50, 1.00) // blue
        ),
        mat2x3(
            vec3(1.00, 0.25, 1.00), // magenta
            vec3(0.00, 1.00, 0.25) // green
        ),
        mat2x3(
            vec3(1.00, 0.70, 1.00) * 1.2, // pink
            vec3(0.90, 0.30, 0.90) // purple
        ),
        mat2x3(
            vec3(0.00, 1.00, 0.25), // green
            vec3(0.90, 0.30, 0.90) // purple
        ),
        mat2x3(
            vec3(2.00, 0.80, 0.00), // orange
            vec3(1.00, 0.50, 0.00) // orange
        )
    );

    uint day_index = uint(worldDay);
    day_index = lowbias32(day_index) % aurora_colors.length();

    return aurora_colors[day_index];
}

// 0.0 - no aurora
// 1.0 - full aurora
float get_aurora_amount() {
    float night = smoothstep(0.0, 0.2, -sun_dir.y);

#if auroraNormal == auroraNever
    float aurora_normal = 0.0;
#elif auroraNormal == auroraRarely
    float aurora_normal = float(lowbias32(uint(worldDay)) % 5 == 1);
#elif auroraNormal == auroraAlways
    float aurora_normal = 1.0;
#endif

#if auroraSnow == auroraNever
    float aurora_snow = 0.0;
#elif auroraSnow == auroraRarely
    float aurora_snow = float(lowbias32(uint(worldDay)) % 5 == 1);
#elif auroraSnow == auroraAlways
    float aurora_snow = 1.0;
#endif

    return night * mix(aurora_normal, aurora_snow, biome_may_snow);
}

#endif // INCLUDE_SKY_AURORA_COLORS
