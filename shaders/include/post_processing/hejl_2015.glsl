#if !defined INCLUDE_POST_PROCESSING_HEJL_2015
#define INCLUDE_POST_PROCESSING_HEJL_2015

vec3 tonemap_hejl_2015(vec3 rgb) {
    const float white_point = 5.0;

    vec4 vh = vec4(rgb, white_point);
    vec4 va = (1.425 * vh) + 0.05; // eval filmic curve
    vec4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;

    return vf.rgb / vf.www; // white point correction
}

#endif // INCLUDE_POST_PROCESSING_HEJL_2015
