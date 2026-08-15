#if !defined POST_HEJL_BURGESS_GLSL
#define POST_HEJL_BURGESS_GLSL

// Hejl/Burgess-Dawson polynomial approximation of the Duiker filmic curve.
// Kept in linear output space; display transfer is applied later by Luster.
vec3 tonemap_hejl_burgess(vec3 rgb) {
    vec3 x = max(rgb - 0.004, vec3(0.0));
    return clamp((x * (6.2 * x + 0.5))
               / (x * (6.2 * x + 1.7) + 0.06), 0.0, 1.0);
}

#endif
