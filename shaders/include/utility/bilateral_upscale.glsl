#if !defined INCLUDE_UTILITY_BILATERAL_UPSCALE
#define INCLUDE_UTILITY_BILATERAL_UPSCALE

#include "/include/utility/space_conversion.glsl"

// Generic depth-aware bilinear upscale for buffers computed at a fraction
// of full resolution (AO, SSPT, or any other screen-space effect that's
// too expensive to run every pixel every frame) and later composited back
// at full res.
//
// Split into sample/resolve so callers can fetch the four low-res texels
// early (latency hiding) and combine them later once the full-res
// fragment's own depth is available, matching how the original inline AO
// upscale in d4_deferred_shading.fsh was structured.
//
// Uses plain `out` parameters rather than a struct-of-arrays return value -
// Apple's OpenGL 4.1 GLSL compiler is unreliable with structs containing
// arrays passed/returned by value, so this stays as flat scalars/vectors
// to match the macOS GL4.1 hard constraint the rest of the pack targets.
//
// `depth_sampler` is expected to store `1.0 - linear_depth` per texel (the
// same convention the AO history buffer uses), matched against the full-res
// fragment's linear depth to reject texels that spilled across a depth
// discontinuity (the usual cause of upscale haloing/ghosting on edges).

// `base_texel` is the low-res texel at the floor of the current fragment's
// position in low-res texel space (i.e. ivec2(frag_pos_in_low_res)).
void bilateral_upscale_sample(
    sampler2D data_sampler,
    sampler2D depth_sampler,
    ivec2 base_texel,
    out vec4 data00,
    out vec4 data10,
    out vec4 data01,
    out vec4 data11,
    out float depth00,
    out float depth10,
    out float depth01,
    out float depth11
) {
    ivec2 p10 = base_texel + ivec2(1, 0);
    ivec2 p01 = base_texel + ivec2(0, 1);
    ivec2 p11 = base_texel + ivec2(1, 1);

    data00 = texelFetch(data_sampler, base_texel, 0);
    data10 = texelFetch(data_sampler, p10, 0);
    data01 = texelFetch(data_sampler, p01, 0);
    data11 = texelFetch(data_sampler, p11, 0);

    depth00 = texelFetch(depth_sampler, base_texel, 0).x;
    depth10 = texelFetch(depth_sampler, p10, 0).x;
    depth01 = texelFetch(depth_sampler, p01, 0).x;
    depth11 = texelFetch(depth_sampler, p11, 0).x;
}

// `f` is fract(frag_pos_in_low_res) - the bilinear interpolation weight
// within the 2x2 texel block that was sampled above.
// `current_lin_z` is the full-res fragment's own linear-space depth.
// `depth_weight_scale` controls how aggressively mismatched depths are
// rejected (higher = stricter falloff, matches the exp2(-scale * ...) term).
vec4 bilateral_upscale_resolve(
    vec4 data00,
    vec4 data10,
    vec4 data01,
    vec4 data11,
    float depth00,
    float depth10,
    float depth01,
    float depth11,
    vec2 f,
    mat4 projection_matrix_inverse,
    float current_lin_z,
    float depth_weight_scale
) {
#define depth_weight(reversed_depth) \
    exp2( \
        -depth_weight_scale \
        * abs( \
            screen_to_view_space_depth( \
                projection_matrix_inverse, \
                1.0 - reversed_depth \
            ) \
            - current_lin_z \
        ) \
    )
    float w00 = depth_weight(depth00) * (1.0 - f.x) * (1.0 - f.y);
    float w10 = depth_weight(depth10) * (f.x - f.x * f.y);
    float w01 = depth_weight(depth01) * (f.y - f.x * f.y);
    float w11 = depth_weight(depth11) * (f.x * f.y);
#undef depth_weight

    float weight_sum = w00 + w10 + w01 + w11;

    if (abs(weight_sum) > eps) {
        return (data00 * w00 + data10 * w10 + data01 * w01 + data11 * w11)
            * rcp(weight_sum);
    }

    return data00;
}

#endif // INCLUDE_UTILITY_BILATERAL_UPSCALE
