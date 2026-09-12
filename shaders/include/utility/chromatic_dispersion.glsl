#if !defined INCLUDE_UTILITY_CHROMATIC_DISPERSION
#define INCLUDE_UTILITY_CHROMATIC_DISPERSION

// Radial chromatic dispersion: samples the red and blue channels at a
// slightly different UV than the source color, offset outward/inward along
// the line from the image center, so the effect mimics a real lens
// spreading wavelengths apart under strong defocus (axial/lateral CA).
//
// `coc_radius` should be the local circle-of-confusion radius driving the
// effect - dispersion should only appear where the image is already
// blurred (defocused), not in sharp/in-focus regions, so pass 0 (or don't
// call this) wherever CoC is ~0.
// `strength` is a user-facing multiplier (already includes any UI/settings
// scaling the caller wants, e.g. CHROMATIC_DISPERSION_STRENGTH * 0.1).
// `clamp_max` bounds the sample UV the same way the caller bounds its own
// main sample, so dispersion never reads past the valid render-scaled
// region of the source texture.
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
    vec2 radial_dir = center_offset / max(length(center_offset), 1e-4);
    vec2 spectral_offset = radial_dir * coc_radius * strength;

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
