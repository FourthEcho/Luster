#if !defined POST_OZIUS_GLSL
#define POST_OZIUS_GLSL

// Zombye's Ozius operator, maintained as its own module.
vec3 tonemap_ozius(vec3 rgb) {
    const vec3 a = vec3(0.46);
    const vec3 b = vec3(0.60);

    rgb = max(rgb * 1.6, vec3(0.0));
    vec3 cr = mix(vec3(dot(rgb, luminance_weights_ap1)), rgb, 0.5) + 1.0;

    rgb = pow(rgb / (1.0 + rgb), a);
    return clamp(pow(rgb * rgb * (-2.0 * rgb + 3.0), cr / b), 0.0, 1.0);
}

#endif
