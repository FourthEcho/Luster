#if !defined INCLUDE_POST_PROCESSING_ACES_FIT
#define INCLUDE_POST_PROCESSING_ACES_FIT

#include "/include/post_processing/aces/aces.glsl"
#include "/include/utility/color.glsl"

// ACES RRT and ODT approximation
vec3 tonemap_aces_fit(vec3 rgb) {
    rgb *= 1.6 * exp2(ACADEMY_RRT_EXPOSURE); // Match the exposure to the RRT

    rgb = rgb * rec2020_to_ap0;

    rgb = rrt_sweeteners(rgb);
    rgb = rrt_and_odt_fit(rgb);

    // Global desaturation
    vec3 grayscale = vec3(dot(rgb, luminance_weights));
    rgb = mix(grayscale, rgb, odt_sat_factor);

    return academy_color_controls(rgb * ap1_to_rec2020);
}

#endif // INCLUDE_POST_PROCESSING_ACES_FIT
