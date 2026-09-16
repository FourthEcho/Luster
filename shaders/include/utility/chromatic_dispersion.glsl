#if !defined INCLUDE_UTILITY_CHROMATIC_DISPERSION
#define INCLUDE_UTILITY_CHROMATIC_DISPERSION

// Radial chromatic dispersion, ported from Complementary Reimagined's
// WB_CHROMATIC (program/composite3.glsl): the red and blue channels are
// sampled at a slightly different UV than the source color, offset along
// the line from the image center, so the effect mimics a real lens
// spreading wavelengths apart under defocus (axial/lateral CA).
//
// Complementary's construction, kept here:
//   - sqrt falloff: offset = sign(d) * sqrt(abs(d)) per axis, so the image
//     center stays clean and fringing grows toward the edges (unlike a
//     normalized radial direction, which fringes uniformly everywhere).
//   - aspect correction: the y axis is scaled by H/W so the fringing is
//     circular on screen instead of elliptical in UV space.
// Complementary additionally scales by 15/viewDims (pixel-constant width
// tuned to their CoC units, which run O(1) and up). Luster's coc_radius is
// a screen-height fraction O(0.01), so that factor is folded out here and
// the caller-facing strength keeps its existing meaning.
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
//
// Requires from the including program:
//   - view_pixel_size uniform (for the H/W aspect correction)
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
