#if !defined INCLUDE_SKY_AIRGLOW
#define INCLUDE_SKY_AIRGLOW

// ---------------------------------------------------------------------------
//   Night airglow
//
//   Faint 557.7nm oxygen emission hugging the horizon on clear nights.
//   Additive background light, applied after the ground proxy and before
//   the clouds composite so cloud cover occludes it. Faded by rain and by
//   the sun being up. Scaled by AIRGLOW_INTENSITY.
// ---------------------------------------------------------------------------

vec3 draw_airglow(vec3 ray_dir) {
#ifndef AIRGLOW
    return vec3(0.0);
#else
    if (rainStrength > 0.99) {
        return vec3(0.0);
    }

    float night = 1.0 - smoothstep(-0.12, 0.02, sun_dir.y);
    if (night <= 0.0) {
        return vec3(0.0);
    }

    // Emission band peaking just above the horizon, soft falloff both ways
    float band = exp(-sqr((ray_dir.y - 0.02) / 0.06));

    // 557.7nm oxygen green, slightly desaturated toward teal
    vec3 tint = vec3(0.35, 1.0, 0.6);

    return band * night * tint
        * (0.03 * AIRGLOW_INTENSITY) * (1.0 - rainStrength);
#endif
}

#endif // INCLUDE_SKY_AIRGLOW
