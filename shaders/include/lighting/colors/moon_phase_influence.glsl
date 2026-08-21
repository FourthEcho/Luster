#if !defined INCLUDE_LIGHTING_COLORS_MOON_PHASE_INFLUENCE
#define INCLUDE_LIGHTING_COLORS_MOON_PHASE_INFLUENCE

#include "/include/utility/color.glsl"

// Moon Phase Influence helpers -------
// Mirrors the moon_phase_brightness curve from shaders.properties
// (full moon = brightest, new moon = dimmest), for use directly in GLSL.
// Requires `uniform int moonPhase;` to be declared in the including file.
float get_moon_phase_curve() {
    if (moonPhase == 0) return 1.0;
    else if (moonPhase == 1) return 0.875;
    else if (moonPhase == 2) return 0.75;
    else if (moonPhase == 3) return 0.625;
    else if (moonPhase == 4) return 0.5;
    else if (moonPhase == 5) return 0.75;
    else if (moonPhase == 6) return 0.875;
    else return 1.0;
}

// Applies phase-driven brightness (intensity/contrast) and saturation
// shaping to a moonlit color. `intensity` blends between the neutral
// (no influence) and full-phase-driven result. `contrast` pushes the
// phase curve away from/towards its midpoint. `saturation` desaturates
// or boosts saturation of the result based on the same curve.
vec3 apply_moon_phase_influence(
    vec3 color,
    float intensity,
    float contrast,
    float saturation
) {
    float phase = get_moon_phase_curve();
    phase = clamp01(0.5 + (phase - 0.5) * contrast);

    float brightness_mul = mix(1.0, phase, clamp01(intensity));
    color *= brightness_mul;

    float sat_mul = mix(1.0, phase, clamp01(saturation));
    float lum = dot(color, luminance_weights_rec2020);
    color = mix(vec3(lum), color, sat_mul);

    return color;
}

#endif
