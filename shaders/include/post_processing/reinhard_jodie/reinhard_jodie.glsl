#if !defined POST_REINHARD_JODIE_GLSL
#define POST_REINHARD_JODIE_GLSL

vec3 tonemap_reinhard_jodie(vec3 rgb) {
    rgb = max(rgb, vec3(0.0));
    vec3 reinhard = rgb / (1.0 + rgb);
    float lum = dot(rgb, luminance_weights);
    vec3 reinhard_lum = rgb / (lum + 1.0);
    return clamp(mix(reinhard_lum, reinhard, reinhard), 0.0, 1.0);
}

#endif
