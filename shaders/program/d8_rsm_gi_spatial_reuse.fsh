/*
--------------------------------------------------------------------------------

  Luster RSM GI — Binary-kernel spatial reuse

  The four spatial_reuse*.bin files are loaded as RGBA16F 5x5 custom textures.
  Each binary stores one reuse kernel plus per-stage rejection parameters in
  its center texel. All four reuse stages are executed in one quarter-res
  shader pass, with colortex17 as the source and colortex21 as the output.

  This replaces the old four deferred reuse passes while keeping the runtime
  GI state in ordinary render targets for OpenGL 4.1 / Mac compatibility.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

// Declare uniforms before space_conversion.glsl because that include
// defines helper functions which reference these uniforms directly.
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float near;
uniform float far;
uniform vec2 view_res;
uniform vec2 taa_offset;

#include "/include/utility/encoding.glsl"
#include "/include/utility/space_conversion.glsl"

#ifdef RSM_GI_SPATIAL_REUSE
#endif

#if defined RSM_GI && defined RSM_GI_SPATIAL_REUSE && defined SHADOW && defined WORLD_OVERWORLD

layout(location = 0) out vec4 spatial_reuse_result; // rgb = reused GI, a = receiver depth
/* RENDERTARGETS: 21 */

in vec2 uv;

uniform sampler2D colortex17;
uniform sampler2D colortex1;

// The four .bin files are real binary textures loaded by shaders.properties.
uniform sampler2D spatial_reuse0;
uniform sampler2D spatial_reuse1;
uniform sampler2D spatial_reuse2;
uniform sampler2D spatial_reuse3;

const float rsm_gi_render_scale = 0.25;

vec3 get_flat_normal(ivec2 view_texel) {
    vec4 g = texelFetch(
        colortex1,
        clamp(view_texel, ivec2(0), ivec2(view_res) - ivec2(1)),
        0
    );
    return decode_unit_vector(unpack_unorm_2x8(g.z));
}

float gi_luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float reuse_weight(
    vec4 center,
    vec4 tap,
    vec3 center_normal,
    vec3 tap_normal,
    float kernel,
    float depth_sigma,
    float normal_power,
    float luma_sigma,
    ivec2 offset
) {
    if (kernel <= 0.00001 || tap.a >= 1.0) return 0.0;

    float center_z = screen_to_view_space_depth(
        gbufferProjectionInverse,
        center.a
    );
    float tap_z = screen_to_view_space_depth(
        gbufferProjectionInverse,
        tap.a
    );

    float depth_scale = max(abs(center_z), 0.5);
    float depth_weight = exp2(
        -depth_sigma * abs(center_z - tap_z) / depth_scale
    );

    float normal_dot = clamp01(dot(center_normal, tap_normal));
    float normal_weight = pow(normal_dot, max(normal_power, 1.0));

    float center_luma = gi_luma(center.rgb);
    float tap_luma = gi_luma(tap.rgb);
    float ratio = (tap_luma + 0.001) / (center_luma + 0.001);
    float luminance_weight = exp2(
        -luma_sigma * abs(log2(max(ratio, 0.001)))
    );

    float radius = length(vec2(offset));
    float distance_weight = 1.0 / (1.0 + radius * 0.55);

    return kernel * depth_weight * normal_weight * luminance_weight * distance_weight;
}

vec4 do_reuse_round(
    sampler2D kernel_tex,
    vec4 center_io,
    vec3 center_normal,
    ivec2 texel,
    ivec2 gi_buffer_max,
    float blend_factor
) {
    vec4 stage_params = texelFetch(kernel_tex, ivec2(2, 2), 0);
    float depth_sigma = max(stage_params.g, 0.1);
    float normal_power = max(stage_params.b, 1.0);
    float luma_sigma = max(stage_params.a, 0.05);

    vec3 stage_sum = center_io.rgb;
    float stage_weight = 1.0;

    for (int sy = 0; sy < 5; ++sy) {
        for (int sx = 0; sx < 5; ++sx) {
            ivec2 off = ivec2(sx - 2, sy - 2);
            ivec2 tap_texel = clamp(texel + off, ivec2(0), gi_buffer_max);
            vec4 tap = texelFetch(colortex17, tap_texel, 0);
            vec4 kp = texelFetch(kernel_tex, ivec2(sx, sy), 0);

            ivec2 tap_view_texel = ivec2(
                vec2(tap_texel) * (taau_render_scale / rsm_gi_render_scale)
            );
            vec3 tap_normal = get_flat_normal(tap_view_texel);

            float w = reuse_weight(
                center_io,
                tap,
                center_normal,
                tap_normal,
                kp.r,
                depth_sigma,
                normal_power,
                luma_sigma,
                off
            );

            stage_sum += tap.rgb * w;
            stage_weight += w;
        }
    }

    vec3 stage_result = stage_sum / max(stage_weight, eps);
    vec3 lo = center_io.rgb * 0.25;
    vec3 hi = center_io.rgb * 4.0 + vec3(0.001);
    stage_result = clamp(stage_result, lo, hi);

    center_io.rgb = mix(
        center_io.rgb,
        stage_result,
        clamp(blend_factor, 0.0, 1.0)
    );

    return center_io;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gi_buffer_max = ivec2(view_res * rsm_gi_render_scale) - ivec2(1);
    texel = clamp(texel, ivec2(0), gi_buffer_max);

    vec4 center = texelFetch(colortex17, texel, 0);

    if (center.a >= 1.0) {
        spatial_reuse_result = center;
        return;
    }

    ivec2 view_texel = ivec2(
        vec2(texel) * (taau_render_scale / rsm_gi_render_scale)
    );
    vec3 center_normal = get_flat_normal(view_texel);

    // Four binary reuse kernels, executed sequentially in one shader pass.
    vec4 reused = center;

    reused = do_reuse_round(spatial_reuse0, reused, center_normal, texel, gi_buffer_max, 1.00);
    reused = do_reuse_round(spatial_reuse1, reused, center_normal, texel, gi_buffer_max, 0.90);
    reused = do_reuse_round(spatial_reuse2, reused, center_normal, texel, gi_buffer_max, 0.82);
    reused = do_reuse_round(spatial_reuse3, reused, center_normal, texel, gi_buffer_max, 0.75);

    spatial_reuse_result = reused;
}

#endif
