#if !defined INCLUDE_POST_PROCESSING_HEJL_2015
#define INCLUDE_POST_PROCESSING_HEJL_2015

// Hejl 2015 filmic, after Jim Hejl's reference ("ToneMapFilmic_Hejl2015").
// GLSL port follows https://github.com/dmnsgn/shaders-tone-map (MIT, see
// LICENSE.md), including its guard: the curve goes negative just above
// black, so max() keeps black at black on the input side.
// White point stays at the pack's established 5.0 tuning.
vec3 tonemap_hejl_2015(vec3 rgb) {
    const float white_point = 5.0;

    vec4 vh = vec4(rgb, white_point);
    vec4 va = (1.425 * vh) + 0.05; // eval filmic curve
    vec4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;

    return max(vec3(0.0), vf.rgb / vf.www); // white point correction
}

#endif // INCLUDE_POST_PROCESSING_HEJL_2015
