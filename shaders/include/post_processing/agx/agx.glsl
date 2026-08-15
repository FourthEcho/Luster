#if !defined POST_AGX_GLSL
#define POST_AGX_GLSL

#include "/include/post_processing/agx/agx_constants.glsl"
#include "/include/utility/color.glsl"

const mat3 LINEAR_REC2020_TO_LINEAR_SRGB_AGX = mat3(
    1.6605, -0.1246, -0.0182,
    -0.5876, 1.1329, -0.1006,
    -0.0728, -0.0083, 1.1187
);

// AgX display transform, adapted for Luster's Rec.2020 linear working space.
// Source basis: dmnsgn/glsl-tone-map (MIT), with the same matrices/polynomial
// used by Blender/Filament-derived implementations.
vec3 agx_transform(vec3 color, vec3 slope, vec3 offset, vec3 power, float saturation) {
    color = max(color, vec3(0.0));

    // AgX working transform. The dmnsgn reference starts in linear sRGB and
    // converts to Rec.2020 first; Luster already stores the scene in Rec.2020.
    color = AGX_INSET * color;
    color = max(color, vec3(1e-10));

    color = clamp(log2(color), AGX_MIN_EV, AGX_MAX_EV);
    color = (color - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV);
    color = clamp(color, 0.0, 1.0);

    vec3 x2 = color * color;
    vec3 x4 = x2 * x2;
    color = 15.5 * x4 * x2
          - 40.14 * x4 * color
          + 31.96 * x4
          - 6.868 * x2 * color
          + 0.4298 * x2
          + 0.1191 * color
          - 0.00232;

    // AgX look transform. Neutral defaults reproduce the standard AgX look.
    color = pow(max(color * slope + offset, vec3(0.0)), power);
    float luma = dot(color, luminance_weights_rec709);
    color = luma + saturation * (color - luma);

    color = AGX_OUTSET * color;
    color = pow(max(color, vec3(0.0)), vec3(2.2));

    // Return to Luster's Rec.2020 linear working space so the common display
    // conversion in c19_color_grading.fsh remains the single output transform.
    color = LINEAR_REC2020_TO_LINEAR_SRGB_AGX * color;
    color = rec709_to_rec2020 * color;

    return clamp(color, 0.0, 1.0);
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
