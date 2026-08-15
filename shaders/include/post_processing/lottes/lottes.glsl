#if !defined POST_LOTTES_GLSL
#define POST_LOTTES_GLSL

// Timothy Lottes, GDC 2016: Advanced Techniques and Optimization of HDR Color Pipelines.
vec3 tonemap_lottes(vec3 x) {
    x = max(x, vec3(0.0));
    const vec3 a = vec3(1.6);
    const vec3 d = vec3(0.977);
    const vec3 hdr_max = vec3(8.0);
    const vec3 mid_in = vec3(0.18);
    const vec3 mid_out = vec3(0.267);

    const vec3 b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    const vec3 c = (pow(hdr_max, a * d) * pow(mid_in, a)
                   - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);

    return clamp(pow(x, a) / (pow(x, a * d) * b + c), 0.0, 1.0);
}

#endif
