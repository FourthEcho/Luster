#if !defined INCLUDE_POST_PROCESSING_HEJL_BURGESS
#define INCLUDE_POST_PROCESSING_HEJL_BURGESS

#include "/include/utility/color.glsl"

// Filmic tonemapping operator made by Jim Hejl and Richard Burgess-Dawson
// ("Filmic Tonemapping for Real-time Rendering", SIGGRAPH 2010 course).
// Modified by Tech to not lose color information below 0.004 (replaces the
// reference max(0, x - 0.004) toe cut with a soft toe).
vec3 tonemap_hejl_burgess(vec3 rgb) {
    rgb = rgb * min(vec3(1.0), 1.0 - 0.8 * exp(rcp(-0.004) * rgb));
    rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return srgb_eotf_inv(rgb); // Revert built-in sRGB conversion
}

#endif // INCLUDE_POST_PROCESSING_HEJL_BURGESS
