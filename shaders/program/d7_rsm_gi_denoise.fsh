/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge (Luster fork)

  program/d7_rsm_gi_denoise:
  RSM GI — one depth/normal-aware bilateral blur pass over the temporally
  accumulated GI, then ambient occlusion is folded in. The result (and the
  receiver depth, for the bilateral upsample in c1) goes back into
  colortex17. A single pass is enough here: temporal accumulation does most
  of the denoising, and the old A-Trous SVGF chain is deliberately not
  rebuilt.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#ifdef RSM_GI_DENOISING
#endif

#if defined RSM_GI && defined SHADOW && defined WORLD_OVERWORLD

layout(location = 0) out vec4 rsm_gi_filtered; // rgb = denoised GI, a = depth

/* RENDERTARGETS: 17 */

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex1; // gbuffer 0 (flat normal)
uniform sampler2D colortex6; // ambient occlusion (quarter res at this point)
uniform sampler2D colortex18; // temporally accumulated GI + depth
uniform sampler2D colortex17; // raw GI + depth (used when temporal accumulation is disabled)

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float near;
uniform float far;

uniform vec2 view_res;
uniform vec2 taa_offset;

// ------------
//   Includes
// ------------

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/space_conversion.glsl"

const float rsm_gi_render_scale = 0.25;

const float depth_rejection_strength = 10.0;
const float normal_rejection_power = 16.0;

// Tent-shaped spatial kernel, written arithmetically (no array indexing —
// some Apple GL drivers dislike dynamically indexed const arrays)
float spatial_kernel_weight(ivec2 offset) {
    return (offset.x == 0 ? 1.0 : 0.5) * (offset.y == 0 ? 1.0 : 0.5);
}

vec3 get_flat_normal(ivec2 view_texel) {
    vec4 gbuffer_data = texelFetch(
        colortex1,
        clamp(view_texel, ivec2(0), ivec2(view_res) - ivec2(1)),
        0
    );
    return decode_unit_vector(unpack_unorm_2x8(gbuffer_data.z));
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    vec4 center =
#ifdef RSM_GI_TEMPORAL_ACCUMULATION
        texelFetch(colortex18, texel, 0);
#else
        texelFetch(colortex17, texel, 0);
#endif
    float depth = center.a;

    ivec2 view_texel = ivec2(
        gl_FragCoord.xy * (taau_render_scale / rsm_gi_render_scale)
    );
    vec3 flat_normal = get_flat_normal(view_texel);

    float lin_z = screen_to_view_space_depth(gbufferProjectionInverse, depth);

    ivec2 gi_buffer_max = ivec2(view_res * rsm_gi_render_scale) - ivec2(1);

    // One bilateral 3x3 pass. The loop is fully static — no data-dependent
    // branches (Apple's GL-on-Metal translation dislikes divergence).
    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            ivec2 tap_texel = clamp(texel + ivec2(x, y), ivec2(0), gi_buffer_max);

            vec4 tap =
#ifdef RSM_GI_TEMPORAL_ACCUMULATION
                texelFetch(colortex18, tap_texel, 0);
#else
                texelFetch(colortex17, tap_texel, 0);
#endif

            float tap_lin_z
                = screen_to_view_space_depth(gbufferProjectionInverse, tap.a);

            float depth_weight = exp2(
                -depth_rejection_strength * abs(tap_lin_z - lin_z)
            );

            vec3 tap_normal = get_flat_normal(
                ivec2(vec2(tap_texel) * (taau_render_scale / rsm_gi_render_scale))
            );
            float normal_weight = pow(
                clamp01(dot(tap_normal, flat_normal)),
                normal_rejection_power
            );

            float weight = spatial_kernel_weight(ivec2(x, y))
                * depth_weight * normal_weight;

            color_sum += tap.rgb * weight;
            weight_sum += weight;
        }
    }

    vec3 gi = weight_sum > eps ? color_sum * rcp(weight_sum) : center.rgb;

    // Fold ambient occlusion in (the same convention the removed screen-space
    // GI used; albedo/pi is applied at the composite in c1_blend_layers).
    // The AO buffer runs at half res = twice this buffer's resolution.
    float ao = texelFetch(
        colortex6,
        clamp(
            ivec2(gl_FragCoord.xy * 2.0),
            ivec2(0),
            ivec2(view_res * 0.5) - ivec2(1)
        ),
        0
    ).x;

    rsm_gi_filtered = vec4(gi * ao, depth);
}

#endif
