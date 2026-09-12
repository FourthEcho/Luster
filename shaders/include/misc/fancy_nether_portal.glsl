#if !defined INCLUDE_MISC_FANCY_NETHER_PORTAL
#define INCLUDE_MISC_FANCY_NETHER_PORTAL

// Parallax nether portal effect inspired by Complementary Reimagined Shaders by
// EminGT Thanks to Emin for letting me use his idea!
//
// Requires from the including program (water-program variant only):
//   - gtexture sampler, frameCounter uniform
//   - position_tangent, atlas_tile_coord, atlas_tile_offset, atlas_tile_scale
//     varyings (declared when PROGRAM_GBUFFERS_WATER is defined)
//   - interleaved_gradient_noise from "/include/utility/dithering.glsl"
//     (usually already included transitively)
//   - NETHER_PORTAL_INTENSITY setting.
// When PROGRAM_GBUFFERS_WATER is not defined a stub returning vec4(0.0) is
// declared instead so non-water translucent programs still compile.

#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"

#if defined PROGRAM_GBUFFERS_WATER
vec2 get_uv_from_local_coord(vec2 local_coord) {
    return atlas_tile_offset + atlas_tile_scale * fract(local_coord);
}

vec4 draw_nether_portal(vec3 direction_world, float layer_dist) {
    const int step_count = 20;
    const float parallax_depth = 0.2;
        const float density_threshold = 0.6;
    const float depth_step = rcp(float(step_count));

    float dither = interleaved_gradient_noise(gl_FragCoord.xy, frameCounter);

    vec3 direction_tangent = -normalize(position_tangent);
    mat2 uv_gradient = mat2(dFdx(uv), dFdy(uv));

    vec3 ray_step
        = vec3(
              direction_tangent.xy * rcp(-direction_tangent.z) * parallax_depth,
              1.0
          )
        * depth_step;
    vec3 pos = vec3(atlas_tile_coord + ray_step.xy * dither, 0.0);

    vec4 result = vec4(0.0);

    for (uint i = 0; i < step_count; ++i) {
        vec4 col = textureGrad(
            gtexture,
            get_uv_from_local_coord(pos.xy),
            uv_gradient[0],
            uv_gradient[1]
        );

        float density = dot(col.rgb, luminance_weights_rec709);
        density = linear_step(0.0, density_threshold, density);
        density = max(density, 0.23);
        density *= 1.0 - depth_step * (i + dither);

        result += col * density;

        pos += ray_step;
    }

    // Edge highlight
    float dist = layer_dist * max_of(abs(direction_world));
    float edge_highlight = cube(max0(1.0 - 2.0 * dist));
    result *= 1.0 + 2.0 * edge_highlight;

    return clamp01(result * NETHER_PORTAL_INTENSITY * depth_step);
}

#else
vec4 draw_nether_portal(vec3 direction_world, float layer_dist) {
    return vec4(0.0);
}
#endif

#endif // INCLUDE_MISC_FANCY_NETHER_PORTAL
