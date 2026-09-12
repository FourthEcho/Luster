#if !defined INCLUDE_POST_PROCESSING_LOTTES
#define INCLUDE_POST_PROCESSING_LOTTES

// Timothy Lottes 2016, "Advanced Techniques and Optimization of HDR Color
// Pipelines" https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
vec3 tonemap_lottes(vec3 rgb) {
    const vec3 a = vec3(1.5); // Contrast
    const vec3 d = vec3(0.91); // Shoulder contrast
    const vec3 hdr_max = vec3(8.0); // White point
    const vec3 mid_in = vec3(0.26); // Fixed midpoint x
    const vec3 mid_out = vec3(0.32); // Fixed midput y

    const vec3 b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    const vec3 c = (pow(hdr_max, a * d) * pow(mid_in, a)
                    - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);

    return pow(rgb, a) / (pow(rgb, a * d) * b + c);
}

#endif // INCLUDE_POST_PROCESSING_LOTTES
