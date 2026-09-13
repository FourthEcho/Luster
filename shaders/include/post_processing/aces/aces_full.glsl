#if !defined INCLUDE_POST_PROCESSING_ACES_FULL
#define INCLUDE_POST_PROCESSING_ACES_FULL

#include "/include/post_processing/aces/aces.glsl"
#include "/include/utility/color.glsl"

// ACES RRT and ODT
vec3 tonemap_aces_full(vec3 rgb) {
    rgb *= 1.6 * exp2(ACADEMY_RRT_EXPOSURE); // Match the exposure to the RRT

    rgb = rgb * rec2020_to_ap0;

    rgb = aces_rrt(rgb);
    rgb = aces_odt(rgb);

    return academy_color_controls(rgb * ap1_to_rec2020);
}

#endif // INCLUDE_POST_PROCESSING_ACES_FULL
