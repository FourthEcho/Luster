#if !defined INCLUDE_POST_PROCESSING_TECH
#define INCLUDE_POST_PROCESSING_TECH

// Tone mapping operator made by Tech for his shader pack Lux
vec3 tonemap_tech(vec3 rgb) {
    vec3 a = rgb * min(vec3(1.0), 1.0 - exp(-1.0 / 0.038 * rgb));
    a = mix(a, rgb, rgb * rgb);
    return a / (a + 0.6);
}

#endif // INCLUDE_POST_PROCESSING_TECH
