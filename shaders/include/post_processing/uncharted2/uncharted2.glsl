#if !defined POST_UNCHARTED2_GLSL
#define POST_UNCHARTED2_GLSL

vec3 tonemap_uncharted2_partial(vec3 x) {
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;
    return ((x * (A * x + C * B) + D * E)
        / (x * (A * x + B) + D * F)) - E / F;
}

vec3 tonemap_uncharted_2(vec3 color) {
    const float exposure_bias = 2.0;
    const float white_point = 11.2;
    vec3 curr = tonemap_uncharted2_partial(max(color, vec3(0.0)) * exposure_bias);
    vec3 white_scale = vec3(1.0) / tonemap_uncharted2_partial(vec3(white_point));
    return clamp(curr * white_scale, 0.0, 1.0);
}

#endif
