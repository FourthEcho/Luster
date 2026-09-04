#if !defined INCLUDE_COLOR_GRADING
#define INCLUDE_COLOR_GRADING

// Professional-style grading pipeline for Luster.
// Stage A: scene-linear controls before tone mapping.
// Stage B: display-linear perceptual controls after tone mapping.

vec3 color_grade_lift_gamma_gain(vec3 rgb) {
    // Log-domain-friendly lift, then power/gain. Defaults are mathematically neutral.
    vec3 lift = vec3(GRADE_LIFT_R, GRADE_LIFT_G, GRADE_LIFT_B);
    vec3 gamma = vec3(max(GRADE_GAMMA_R, 0.05), max(GRADE_GAMMA_G, 0.05), max(GRADE_GAMMA_B, 0.05));
    vec3 gain = vec3(GRADE_GAIN_R, GRADE_GAIN_G, GRADE_GAIN_B);

    rgb = max(rgb + lift, vec3(0.0));
    rgb = pow(rgb, rcp(gamma));
    return max(rgb * gain, vec3(0.0));
}

vec3 color_grade_input(vec3 rgb, mat3 white_balance_matrix) {
    float brightness = max(GRADE_BRIGHTNESS, 0.0);
    float contrast = max(GRADE_CONTRAST, 0.0);
    float pivot = max(GRADE_PIVOT, 1e-4);

    rgb = max(rgb, vec3(0.0));
    rgb *= brightness;

    // Symmetric contrast around a scene-linear pivot, performed in log space so exposure stops stay natural.
    rgb = log2(rgb + 1e-6);
    float log_pivot = log2(pivot);
    rgb = exp2((rgb - log_pivot) * contrast + log_pivot);
    rgb = max(rgb - 1e-6, vec3(0.0));

    // White balance in chromaticity space. A Bradford matrix is calculated in the vertex shader.
    rgb = max(rgb * white_balance_matrix, vec3(0.0));

    // Lift / gamma / gain (ASC-style three-way control).
    rgb = color_grade_lift_gamma_gain(rgb);
    return max(rgb, vec3(0.0));
}

// sRGB-like display-linear -> OKLab.
vec3 grade_rgb_to_oklab(vec3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    vec3 lms = vec3(l, m, s);
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return vec3(
        0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
        1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
        0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z
    );
}

vec3 grade_oklab_to_rgb(vec3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    vec3 lms = vec3(l, m, s);
    lms = lms * lms * lms;
    return max(vec3(
        4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
       -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
       -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z
    ), vec3(0.0));
}

vec2 grade_rotate(vec2 v, float radians_angle) {
    float s = sin(radians_angle), c = cos(radians_angle);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec2 grade_hue_vector(float degrees, float saturation) {
    float h = radians(degrees);
    return vec2(cos(h), sin(h)) * saturation;
}

vec3 color_grade_output(vec3 rgb) {
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));

    vec3 lab = grade_rgb_to_oklab(rgb);
    float chroma = length(lab.yz);

    // Global saturation + vibrance: vibrance preferentially boosts low-chroma colors.
    float vibrance_mask = 1.0 - clamp(chroma * 3.5, 0.0, 1.0);
    float sat_mul = max(GRADE_SATURATION + GRADE_VIBRANCE * vibrance_mask, 0.0);
    lab.yz *= sat_mul;

    // Gentle perceptual contrast with a stable pivot around middle gray.
    lab.x = clamp((lab.x - GRADE_OKLAB_PIVOT) * GRADE_OKLAB_CONTRAST + GRADE_OKLAB_PIVOT, 0.0, 1.0);

    // Split-tone masks use the perceptual lightness channel.
    float shadows = 1.0 - smoothstep(GRADE_SHADOW_LOW, GRADE_SHADOW_HIGH, lab.x);
    float highlights = smoothstep(GRADE_HIGHLIGHT_LOW, GRADE_HIGHLIGHT_HIGH, lab.x);
    float mids = clamp(1.0 - shadows - highlights, 0.0, 1.0);

    // Three-way hue rotation while preserving existing chroma magnitude.
    if (chroma > 1e-6) {
        float shadow_w = shadows * GRADE_SHADOW_STRENGTH;
        float mid_w = mids * GRADE_MID_STRENGTH;
        float highlight_w = highlights * GRADE_HIGHLIGHT_STRENGTH;
        vec2 ab = lab.yz;
        ab = grade_rotate(ab, radians(GRADE_SHADOW_HUE) * shadow_w);
        ab = grade_rotate(ab, radians(GRADE_MID_HUE) * mid_w);
        ab = grade_rotate(ab, radians(GRADE_HIGHLIGHT_HUE) * highlight_w);
        lab.yz = ab;
    }

    // Add controlled chroma bias for classic split toning.
    float tint_scale = sqrt(max(lab.x, 0.0));
    lab.yz += grade_hue_vector(GRADE_SHADOW_TINT_HUE, GRADE_SHADOW_TINT_SAT * shadows) * tint_scale;
    lab.yz += grade_hue_vector(GRADE_HIGHLIGHT_TINT_HUE, GRADE_HIGHLIGHT_TINT_SAT * highlights) * tint_scale;

    // Convert the perceptual pass back to RGB, then apply selective HSL accents.
    vec3 perceptual_rgb = grade_oklab_to_rgb(lab);
    vec3 hsl = rgb_to_hsl(perceptual_rgb);
    float orange = isolate_hue(hsl, 30.0, 20.0);
    float teal = isolate_hue(hsl, 210.0, 20.0);
    float green = isolate_hue(hsl, 90.0, 44.0);
    hsl.y = clamp(hsl.y * (1.0 + GRADE_ORANGE_SAT_BOOST * orange), 0.0, 1.0);
    hsl.y = clamp(hsl.y * (1.0 + GRADE_TEAL_SAT_BOOST * teal), 0.0, 1.0);
    hsl.y = clamp(hsl.y * (1.0 + GRADE_GREEN_SAT_BOOST * green), 0.0, 1.0);
    hsl.x = fract(hsl.x + (GRADE_GREEN_HUE_SHIFT / 360.0) * green);
    vec3 selective_rgb = hsl_to_rgb(hsl);
    rgb = mix(perceptual_rgb, selective_rgb, clamp(GRADE_SELECTIVE_BLEND, 0.0, 1.0));

    // Black/white point control, applied last to avoid fighting the tonemapper.
    rgb = max((rgb - GRADE_BLACK_POINT) / max(1.0 - GRADE_BLACK_POINT - GRADE_WHITE_POINT, 1e-4), vec3(0.0));
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));
    return rgb;
}

#endif
