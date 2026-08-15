#if !defined POST_HEJL_2015_GLSL
#define POST_HEJL_2015_GLSL

// Jim Hejl, 2015. Linear-light output with white-point correction.
vec3 tonemap_hejl_2015(vec3 rgb) {
    const float white_point = 5.0;
    vec4 vh = vec4(max(rgb, vec3(0.0)), white_point);
    vec4 va = 1.425 * vh + 0.05;
    vec4 vf = ((vh * va + 0.004) / (vh * (va + 0.55) + 0.0491)) - 0.0821;
    return max(vf.rgb / max(vf.www, vec3(1e-6)), vec3(0.0));
}

#endif
