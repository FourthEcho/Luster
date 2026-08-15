#if !defined POST_REINHARD_GLSL
#define POST_REINHARD_GLSL

vec3 tonemap_reinhard(vec3 rgb) {
    rgb = max(rgb, vec3(0.0));
    return rgb / (1.0 + rgb);
}

#endif
