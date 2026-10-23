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

#if !defined INCLUDE_ATMOS_CLOUDS_CORE_SAMPLING
#define INCLUDE_ATMOS_CLOUDS_CORE_SAMPLING

// Sample filtered clouds
vec4 readCloudsAndAurora(vec2 uv, out float apparentDistance) {
#if defined WORLD_OVERWORLD
    // Soften clouds for new pixels
    float pixelAge
        = texelFetch(colortex12, ivec2(uv * viewRes * taauViewportScale), 0).y;
    float ld = 2.0 * dampen(max0(1.0 - 0.1 * pixelAge));

    apparentDistance
        = minOf(textureGather(colortex12, uv * taauViewportScale, 0));
    vec4 result = textureLod(colortex11, uv * taauViewportScale, ld);

    if (LIGHTNING_FLASH_UNIFORM > 0.01) {
        float ambientScattering
            = texture(colortex12, uv * taauViewportScale).z;
        result.xyz += LIGHTNING_FLASH_UNIFORM * lightningFlashIntensity
            * ambientScattering;
    }

    result.xyz *= clamp01(1.0 - blindness - darknessFactor);

    return result;
#else
    return vec4(0.0, 0.0, 0.0, 1.0);
#endif
}

#endif // INCLUDE_ATMOS_CLOUDS_CORE_SAMPLING
