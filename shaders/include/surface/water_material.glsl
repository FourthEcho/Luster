#if !defined INCLUDE_SURFACE_WATER_MATERIAL
#define INCLUDE_SURFACE_WATER_MATERIAL

// Water surface color and underwater absorption.
//
// Requires from the including program:
//   - Material / water_material from "/include/surface/material.glsl"
//   - biome_water_coeff / water_fog_simple from "/include/fog/simple_fog.glsl"
//   - uv + tint varyings/uniforms, light_levels, ambient_color, light_color,
//     isEyeInWater, and the read_tex_anisotropic_or_plain(samp, texcoord)
//     macro defined before this include (see gbuffers_all_translucent.fsh)
//   - WATER_TEXTURE_*, WATER_EDGE_HIGHLIGHT_*, BIOME_WATER_COLOR_INTENSITY
//     settings from "/settings.glsl".

#include "/include/surface/material.glsl"
#include "/include/fog/simple_fog.glsl"
#include "/include/utility/color.glsl"

#if defined PROGRAM_GBUFFERS_WATER
Material get_water_material(
    vec3 direction_world,
    vec3 normal,
    float layer_dist,
    out float alpha
) {
    Material material = water_material;
    alpha = 0.01;

    // Water texture

#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT \
    || WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    vec4 base_color = read_tex_anisotropic_or_plain(gtexture, uv);
    // WATER_TEXTURE_INTENSITY scales the contribution of the vanilla water
    // texture (the bright "noise" pattern on the surface). At 0 the texture
    // is invisible; at 1 it matches the previous default brightness.
    float texture_highlight = dampen(
        0.5 * sqr(linear_step(0.63, 1.0, base_color.r)) + 0.03 * base_color.r
    ) * WATER_TEXTURE_INTENSITY;
#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    texture_highlight *= 1.0 - cube(linear_step(0.0, 0.5, light_levels.y));
#endif

    material.albedo
        = clamp01(0.5 * exp(-2.0 * water_absorption_coeff) * texture_highlight);
    material.roughness += 0.3 * texture_highlight;
    alpha += texture_highlight;
#elif WATER_TEXTURE == WATER_TEXTURE_VANILLA
    vec4 base_color = read_tex_anisotropic_or_plain(gtexture, uv) * tint;
    material.albedo = srgb_eotf_inv(base_color.rgb * base_color.a)
        * rec709_to_working_color;
    alpha = base_color.a;
#endif

    // Water edge highlight

#ifdef WATER_EDGE_HIGHLIGHT
    float dist = layer_dist * max(abs(direction_world.y), eps);

#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT \
    || WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    float edge_highlight
        = cube(max0(1.0 - 2.0 * dist)) * (1.0 + 8.0 * texture_highlight);
#else
    float edge_highlight = cube(max0(1.0 - 2.0 * dist));
#endif
    edge_highlight *= WATER_EDGE_HIGHLIGHT_INTENSITY * max0(normal.y)
        * (1.0 - 0.5 * sqr(light_levels.y));
    ;

    material.albedo += 0.1 * edge_highlight
        / mix(1.0,
              max(dot(ambient_color, luminance_weights_rec2020), 0.5),
              light_levels.y);
    material.albedo = clamp01(material.albedo);
    alpha += edge_highlight;
#endif

    return material;
}

vec4 water_absorption_approx(
    vec4 color,
    float sss_depth,
    float layer_dist,
    float LoV,
    float NoV,
    float cloud_shadows
) {
    // BIOME_WATER_COLOR_INTENSITY scales how strongly the per-biome water
    // tint (swamp brown, moat blue, etc.) drives the underwater absorption
    // coefficients. At 0 the absorption falls back to a neutral grey
    // baseline; at 1 it matches the previous behaviour (full biome tint).
    // We blend the biome tint toward neutral grey (0.5) by the inverse of
    // the slider — this preserves luminance while letting the slider dial
    // the colour saturation up or down without affecting overall density.
    vec3 biome_water_color = srgb_eotf_inv(tint.rgb) * rec709_to_working_color;
    biome_water_color = mix(
        vec3(dot(biome_water_color, luminance_weights_rec2020)),
        biome_water_color,
        BIOME_WATER_COLOR_INTENSITY
    );
    vec3 absorption_coeff = biome_water_coeff(biome_water_color);
    float dist = layer_dist * float(isEyeInWater != 1 || NoV >= 0.0);

    mat2x3 water_fog = water_fog_simple(
        light_color * cloud_shadows,
        ambient_color,
        absorption_coeff,
        light_levels,
        dist,
        -LoV,
        sss_depth
    );

    float brightness_control = 1.0 - exp(-0.33 * layer_dist);
    brightness_control *= max(light_levels.x, light_levels.y);

    return vec4(
        color.rgb
            + water_fog[0] * (1.0 + 6.0 * sqr(water_fog[1]))
                * brightness_control,
        1.0 - water_fog[1].x
    );
}
#endif

#endif // INCLUDE_SURFACE_WATER_MATERIAL
