#if !defined INCLUDE_MISC_TONEMAP_OPERATORS
#define INCLUDE_MISC_TONEMAP_OPERATORS

// ACES stays on the existing Academy-quality implementation.
#include "/include/post_processing/aces/aces.glsl"
#include "/include/utility/color.glsl"

// Independent operator modules.
#include "/include/post_processing/agx/agx.glsl"
#include "/include/post_processing/hejl_2015/hejl_2015.glsl"
#include "/include/post_processing/hejl_burgess/hejl_burgess.glsl"
#include "/include/post_processing/lottes/lottes.glsl"
#include "/include/post_processing/uncharted2/uncharted2.glsl"
#include "/include/post_processing/tech/tech.glsl"
#include "/include/post_processing/ozius/ozius.glsl"
#include "/include/post_processing/reinhard/reinhard.glsl"
#include "/include/post_processing/reinhard_jodie/reinhard_jodie.glsl"

// ACES RRT and ODT
vec3 tonemap_aces_full(vec3 rgb) {
    rgb *= 1.6;
    rgb = rgb * rec2020_to_ap0;
    rgb = aces_rrt(rgb);
    rgb = aces_odt(rgb);
    return rgb * ap1_to_rec2020;
}

// ACES RRT and ODT approximation
vec3 tonemap_aces_fit(vec3 rgb) {
    rgb *= 1.6;
    rgb = rgb * rec2020_to_ap0;
    rgb = rrt_sweeteners(rgb);
    rgb = rrt_and_odt_fit(rgb);
    vec3 grayscale = vec3(dot(rgb, luminance_weights));
    rgb = mix(grayscale, rgb, odt_sat_factor);
    return rgb * ap1_to_rec2020;
}

#endif
