#if !defined POST_TECH_GLSL
#define POST_TECH_GLSL

// Tech/Lux-inspired operator retained as a dedicated implementation module.
vec3 tonemap_tech(vec3 rgb) {
    rgb = max(rgb, vec3(0.0));
    vec3 a = rgb * min(vec3(1.0), 1.0 - exp(-rgb / 0.038));
    a = mix(a, rgb, rgb * rgb);
    return clamp(a / (a + 0.6), 0.0, 1.0);
}

#endif
