#if !defined INCLUDE_SKY_TWILIGHT_WEDGE
#define INCLUDE_SKY_TWILIGHT_WEDGE

// ---------------------------------------------------------------------------
//   Twilight wedge (Belt of Venus)
//
//   Pink arch opposite the sun just after sunset with the dark blue
//   Earth's-shadow band sinking beneath it. Additive background light,
//   applied before the clouds composite so cloud cover occludes it.
//   Gated by the sun sitting just below the horizon, faded by rain.
//   Scaled by TWILIGHT_WEDGE_INTENSITY.
// ---------------------------------------------------------------------------

vec3 draw_twilight_wedge(vec3 ray_dir) {
#ifndef TWILIGHT_WEDGE
    return vec3(0.0);
#else
    if (rainStrength > 0.99) {
        return vec3(0.0);
    }

    // Peaks while the sun is just below the horizon, gone by deep night
    float dusk = pulse(sun_dir.y, -0.03, 0.09);
    if (dusk <= 0.0) {
        return vec3(0.0);
    }

    // Anti-solar direction, lifted slightly: the arch sits above the
    // opposite horizon, not at the exact antisolar point
    vec3 anti_sun = normalize(vec3(-sun_dir.x, 0.0, -sun_dir.z) + vec3(0.0, 0.15, 0.0));
    float align = pow(clamp01(dot(ray_dir, anti_sun)), 3.0);

    // Pink arch peaking a few degrees above the horizon
    float arch = exp(-sqr((ray_dir.y - 0.10) / 0.08));
    vec3 pink = arch * vec3(1.0, 0.45, 0.55);

    // Earth's shadow: cool darkening hugging the horizon below the arch.
    // Subtractive, kept small so it tints rather than clips.
    float shadow_band = exp(-sqr((ray_dir.y - 0.01) / 0.045));
    vec3 shadow = shadow_band * vec3(0.10, 0.14, 0.30);

    return (pink - shadow) * align * dusk
        * (0.05 * TWILIGHT_WEDGE_INTENSITY) * (1.0 - rainStrength);
#endif
}

#endif // INCLUDE_SKY_TWILIGHT_WEDGE
