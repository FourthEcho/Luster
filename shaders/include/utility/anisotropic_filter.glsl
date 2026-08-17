#if !defined INCLUDE_ANISOTROPIC_FILTER
#define INCLUDE_ANISOTROPIC_FILTER

vec4 luster_texture_grad_anisotropic(
    sampler2D tex,
    vec2 coord,
    vec2 dx,
    vec2 dy
) {
#if ANISOTROPIC_FILTERING <= 0
    return textureGrad(tex, coord, dx, dy);
#else
#if defined LUSTER_HAS_GL_ANISOTROPIC && defined TEXTURE_FILTERING
    // When Iris/Sodium selected hardware anisotropic filtering, let the
    // driver perform the anisotropic reconstruction using its sampler state.
    if (textureFilteringMode == 2) {
        return texture(tex, coord);
    }
#endif
    vec2 tex_size = vec2(textureSize(tex, 0));
    vec2 dx_tex = dx * tex_size;
    vec2 dy_tex = dy * tex_size;

    float len_x = length(dx_tex);
    float len_y = length(dy_tex);
    float major_len = max(len_x, len_y);
    float minor_len = max(min(len_x, len_y), 1e-5);
    vec2 major = len_x >= len_y ? dx : dy;

    float requested = float(ANISOTROPIC_FILTERING);
    float ratio = clamp(major_len / minor_len, 1.0, requested);
    int taps = int(ceil(ratio));

    vec4 sum = vec4(0.0);
    for (int i = 0; i < ANISOTROPIC_FILTERING; ++i) {
        if (i >= taps) break;
        float t = ((float(i) + 0.5) / float(taps) - 0.5) * ratio;
        sum += textureGrad(tex, coord + major * t, dx, dy);
    }

    return sum / float(taps);
#endif
}

vec4 luster_texture_anisotropic(
    sampler2D tex,
    vec2 coord,
    vec2 dx,
    vec2 dy,
    float lod_bias
) {
    float lod_scale = exp2(lod_bias);
    return luster_texture_grad_anisotropic(
        tex,
        coord,
        dx * lod_scale,
        dy * lod_scale
    );
}

#endif
