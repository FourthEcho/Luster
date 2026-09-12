#if !defined INCLUDE_POST_PROCESSING_REINHARD_JODIE
#define INCLUDE_POST_PROCESSING_REINHARD_JODIE

#include "/include/utility/color.glsl"

vec3 tonemap_reinhard_jodie(vec3 rgb) {
    vec3 reinhard = rgb / (rgb + 1.0);
    return mix(rgb / (dot(rgb, luminance_weights) + 1.0), reinhard, reinhard);
}

#endif // INCLUDE_POST_PROCESSING_REINHARD_JODIE
