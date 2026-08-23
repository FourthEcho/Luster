/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge (Luster fork)

  program/d5_rsm_gi_gather:
  RSM GI — gather virtual point lights from the sun shadow map at quarter
  resolution. Every texel of shadowtex0 is treated as a VPL whose albedo
  and world normal were captured into shadowcolor1 by the shadow pass.
  Output: raw (noisy) irradiance + receiver depth, quarter res.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#if defined RSM_GI && defined SHADOW && defined WORLD_OVERWORLD

layout(location = 0) out vec4 rsm_gi_raw; // rgb = raw irradiance, a = depth

/* RENDERTARGETS: 17 */

in vec2 uv;

flat in vec3 light_color;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0 (flat normal, skylight)
uniform sampler2D depthtex1;

uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec3 light_dir;

uniform vec2 view_res;
uniform vec2 taa_offset;

// ------------
//   Includes
// ------------

#include "/include/misc/lod_mod_support.glsl"
#include "/include/lighting/rsm_gi.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

const float rsm_gi_render_scale = 0.25;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 view_texel = ivec2(
        gl_FragCoord.xy * (taau_render_scale / rsm_gi_render_scale)
    );

    if (clamp(view_texel, ivec2(0), ivec2(view_res)) != view_texel) {
        rsm_gi_raw = vec4(0.0);
        return;
    }

    float depth = texelFetch(combined_depth_tex, view_texel, 0).x;

    // Distant Horizons support

#ifdef LOD_MOD_ACTIVE
    float depth_mc = texelFetch(depthtex1, view_texel, 0).x;
    float depth_lod = texelFetch(lod_depth_tex_shading, view_texel, 0).x;
    bool is_lod = is_lod_terrain(depth_mc, depth_lod);
#else
#define depth_mc depth
    const bool is_lod = false;
#endif

    bool is_hand;
    fix_hand_depth(depth_mc, is_hand);

    // Sky, hand and LoD terrain get no bounce lighting. The stored depth
    // still lets the temporal and upsample passes reject/match them.
    if (depth == 1.0 || is_hand || is_lod) {
        rsm_gi_raw = vec4(0.0, 0.0, 0.0, depth);
        return;
    }

    vec4 gbuffer_data = texelFetch(colortex1, view_texel, 0);

    float dither = texelFetch(noisetex, texel & 511, 0).b;
    dither = r1(frameCounter, dither);

    // Receiver position

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    // Unpack receiver data: flat normal and skylight

    mat4x2 data = mat4x2(
        unpack_unorm_2x8(gbuffer_data.x),
        unpack_unorm_2x8(gbuffer_data.y),
        unpack_unorm_2x8(gbuffer_data.z),
        unpack_unorm_2x8(gbuffer_data.w)
    );

    vec3 flat_normal = decode_unit_vector(data[2]);
    float skylight = data[3].y;

    rsm_gi_raw = vec4(
        rsm_gi_gather(scene_pos, flat_normal, skylight, light_color, dither),
        depth
    );
}

#endif
