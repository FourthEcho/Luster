#if !defined INCLUDE_POST_PROCESSING_REINHARD_JODIE
#define INCLUDE_POST_PROCESSING_REINHARD_JODIE

#include "/include/utility/color.glsl"

// Reinhard driven by luminance, then blended per channel by the per-channel
// result, so saturated colors keep their hue. After Jodie's formulation,
// see https://64.github.io/tonemapping/#reinhard-jodie
// (luminance weights follow this pack's Rec. 2020 working space).

vec3 tonemap_reinhard_jodie(vec3 rgb) {
    vec3 reinhard = rgb / (rgb + 1.0);
    return mix(rgb / (dot(rgb, luminance_weights) + 1.0), reinhard, reinhard);
}

#endif // INCLUDE_POST_PROCESSING_REINHARD_JODIE
