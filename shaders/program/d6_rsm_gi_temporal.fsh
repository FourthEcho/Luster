/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge (Luster fork)

  program/d6_rsm_gi_temporal:
  RSM GI — reproject and EMA-blend the raw gather against last frame's
  result (persistent quarter-res history in colortex18/19, flipped here).
  Depth + offcenter rejection follows the same scheme as the AO pass.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#if defined RSM_GI && defined SHADOW && defined WORLD_OVERWORLD

layout(
    location = 0
) out vec4 rsm_gi_accum; // rgb = accumulated irradiance, a = depth
layout(location = 1) out vec2 rsm_gi_history_data; // 1 - depth, pixel age

/* RENDERTARGETS: 18,19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex1; // gbuffer 0 (flat normal)
uniform sampler2D colortex17; // raw gather from d5
uniform sampler2D colortex18; // accumulated history
uniform sampler2D colortex19; // history data (depth, pixel age)

uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec2 view_res;
uniform vec2 taa_offset;

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

const float rsm_gi_render_scale = 0.25;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    vec4 current = texelFetch(colortex17, texel, 0);
    float depth = current.a;

    // Sky: no history, and nothing to accumulate
    if (depth == 1.0) {
        rsm_gi_accum = vec4(0.0, 0.0, 0.0, 1.0);
        rsm_gi_history_data = vec2(0.0);
        return;
    }

    // Receiver position

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    vec3 previous_screen_pos = reproject_scene_space(scene_pos, false, false);

    // Receiver normal, for the depth rejection weight

    ivec2 view_texel = ivec2(
        gl_FragCoord.xy * (taau_render_scale / rsm_gi_render_scale)
    );
    vec4 gbuffer_data = texelFetch(
        colortex1,
        clamp(view_texel, ivec2(0), ivec2(view_res) - ivec2(1)),
        0
    );
    vec3 world_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data.z));
    vec3 view_normal = mat3(gbufferModelView) * world_normal;

    if (clamp01(previous_screen_pos.xy) == previous_screen_pos.xy) {
        vec4 history = max0(
            catmull_rom_filter_fast(colortex18, previous_screen_pos.xy, 0.65)
        );
        vec2 history_data = max0(texture(colortex19, previous_screen_pos.xy).xy);

        float history_depth = 1.0 - history_data.x;
        float pixel_age = min(history_data.y, float(RSM_GI_HISTORY));

        // Depth rejection
        float view_norm = rcp_length(view_pos);
        float NoV = abs(dot(view_normal, view_pos)) * view_norm;
        float z0 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            depth
        );
        float z1 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            history_depth
        );
        float depth_weight = exp2(-abs(z0 - z1) * 16.0 * NoV * view_norm);

        // Offcenter rejection (from Jessie, originally by Zombye) — reduces
        // blur in motion
        vec2 pixel_offset = 1.0
            - abs(2.0
                      * fract(
                          view_res * rsm_gi_render_scale
                          * previous_screen_pos.xy
                      )
                  - 1.0);
        float offcenter_rejection = sqrt(pixel_offset.x * pixel_offset.y) * 0.25
            + (1.0 - 0.25);

        pixel_age
            *= depth_weight * offcenter_rejection * float(history_depth != 1.0);

        // Blend with history
        float history_weight = pixel_age / (pixel_age + 1.0);

        vec3 gi = mix(current.rgb, history.rgb, history_weight);

        rsm_gi_accum = vec4(gi, depth);
        rsm_gi_history_data = vec2(1.0 - depth, pixel_age + 1.0);
    } else {
        rsm_gi_accum = vec4(current.rgb, depth);
        rsm_gi_history_data = vec2(1.0 - depth, 1.0);
    }

    // Don't let hand pixels leave usable history behind
    if (depth < hand_depth) {
        rsm_gi_history_data.x = 1.0;
    }
}

#endif
