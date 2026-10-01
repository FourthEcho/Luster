#if !defined INCLUDE_UTILITY_CHROMATIC_DISPERSION
#define INCLUDE_UTILITY_CHROMATIC_DISPERSION

// Radial chromatic dispersion

vec3 apply_chromatic_dispersion(
    sampler2D color_sampler,
    vec2 uv,
    vec3 color,
    float coc_radius,
    float strength,
    vec2 clamp_max,
    float render_scale
) {
    vec2 center_offset = uv - 0.5;
    vec2 chromatic_scale = sign(center_offset) * sqrt(abs(center_offset));
    chromatic_scale *= vec2(1.0, view_pixel_size.x / view_pixel_size.y);

    vec2 spectral_offset = chromatic_scale * coc_radius * strength;

    color.r = textureLod(
        color_sampler,
        clamp(vec2(uv - spectral_offset), vec2(0.0), clamp_max) * render_scale,
        0
    ).r;
    color.b = textureLod(
        color_sampler,
        clamp(vec2(uv + spectral_offset), vec2(0.0), clamp_max) * render_scale,
        0
    ).b;

    return color;
}

#endif // INCLUDE_UTILITY_CHROMATIC_DISPERSION
