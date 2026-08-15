#if !defined POST_AGX_GLSL
#define POST_AGX_GLSL

#include "/include/post_processing/agx/agx_constants.glsl"
#include "/include/utility/color.glsl"

// AgX reference implementation adapted from dmnsgn/glsl-tone-map (MIT),
// which cites Blender/EaryChow/Filament/Three.js implementations.
//
// Luster's linear working space is Rec.2020. AgX's image-formation math is
// evaluated in linear sRGB, so the working-space conversion must happen
// BEFORE the AgX inset/log/curve and be inverted AFTER the AgX display EOTF.
// This avoids gamut-dependent hue errors (especially green/cyan shifts).

vec3 agx_transform(vec3 color, vec3 slope, vec3 offset, vec3 power, float saturation) {
    color = max(color, vec3(0.0));

    // Luster scene-linear selected working space -> AgX linear-sRGB domain.
    color = WORKING_TO_REC709 * color;

    // Input transform (inset).
    color = AGX_INSET * color;
    color = max(color, vec3(1e-10));

    // Log2 encoding.
    color = clamp(log2(color), AGX_MIN_EV, AGX_MAX_EV);
    color = (color - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV);
    color = clamp(color, 0.0, 1.0);

    // AgX sigmoid / tonescale approximation.
    vec3 x2 = color * color;
    vec3 x4 = x2 * x2;
    color = 15.5 * x4 * x2
          - 40.14 * x4 * color
          + 31.96 * x4
          - 6.868 * x2 * color
          + 0.4298 * x2
          + 0.1191 * color
          - 0.00232;

    // Look / ASC CDL.
    color = pow(max(color * slope + offset, vec3(0.0)), power);
    const vec3 lw = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(color, lw);
    color = luma + saturation * (color - luma);

    // Display EOTF / inverse input transform.
    color = AGX_OUTSET * color;
    color = pow(max(color, vec3(0.0)), vec3(2.2));

    // AgX now produces linear display-sRGB. Return to Luster's linear
    // Rec.2020 working space so c19's single output-gamut transform remains
    // the only final display conversion.
    color = REC709_TO_WORKING * color;

    return max(color, vec3(0.0));
}

vec3 tonemap_agx(vec3 color) {
    return agx_transform(color, vec3(1.0), vec3(0.0), vec3(1.0), 1.0);
}

vec3 tonemap_agx_golden(vec3 color) {
    return agx_transform(color, vec3(1.0, 0.9, 0.5), vec3(0.0), vec3(0.8), 1.3);
}

vec3 tonemap_agx_punchy(vec3 color) {
    return agx_transform(color, vec3(1.0), vec3(0.0), vec3(1.35), 1.4);
}

#endif
