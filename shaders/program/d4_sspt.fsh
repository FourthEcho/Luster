/*
--------------------------------------------------------------------------------

  program/d4_sspt:
  Trace stage of the SSPT chain. Fires screen-space path traced rays per
  pixel and gathers material emission plus one bounce of colored sun/moon
  light (see include/lighting/sspt/sspt.glsl). The output is deliberately
  noisy — program/d5_sspt_accumulate and the a-trous filter passes
  (program/d6_sspt_filter, sizes 32/16/8/4/2) reconstruct a stable image
  from it.

  Renders at the indirect-light resolution into colortex17 (radiance +
  vanilla blocklight gate) and colortex19 (filter data: view normal,
  sqrt normalized depth).

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 sspt_indirect;     // colortex17
layout(location = 1) out vec4 sspt_filter_data;  // colortex19

/* RENDERTARGETS: 17,19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex6; // ambient occlusion (same resolution)
uniform sampler2D depthtex1; // combined_depth_tex when no LoD mod is active

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#if defined SHADOW && !defined WORLD_NETHER
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef SHADOW_COLOR
uniform sampler2D shadowcolor0;
#endif

uniform vec3 sun_dir;
uniform vec3 moon_dir;
uniform float sunAngle;
uniform float time_sunrise;
uniform float time_sunset;
uniform float moon_phase_brightness;
#endif

// Shadow matrices stay declared even where no shadow pass runs: the
// cloud-shadow helper chain references them, and unused uniforms are free.
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
uniform sampler2D colortex8; // cloud shadow map
#endif

// Declared for the atmosphere/cloud-shadow include chain
uniform float rainStrength;
uniform float desert_sandstorm;
uniform vec3 light_dir;
uniform float eyeAltitude;
uniform int moonPhase;

// ------------
//   Includes
// ------------

#define SSPT_DEPTH_SAMPLER combined_depth_tex
#define SSPT_PROJECTION_MATRIX combined_projection_matrix
#define SSPT_PROJECTION_MATRIX_INVERSE combined_projection_matrix_inverse

#include "/include/misc/lod_mod_support.glsl"
#include "/include/lighting/sspt/sspt.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/space_conversion.glsl"

// ------------
//   Main
// ------------

void main() {
    // This pass renders into the reduced-resolution SSPT buffers:
    // gl_FragCoord counts buffer texels, uv still spans the whole screen.
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    // Defaults for sky pixels: no radiance, filter data pointing straight
    // up at maximum depth.
    sspt_indirect = vec4(0.0);
    sspt_filter_data = vec4(0.5, 0.5, 1.0, 1.0);

    if (clamp(gbuffer_texel, ivec2(0), ivec2(view_res) - 1) != gbuffer_texel) return;

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth >= 1.0) return;

    bool is_hand = depth < hand_depth;

    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        vec3(uv, depth),
        true
    );

    // ---- filter data ----
    // rgb: view-space flat normal, remapped to [0, 1] (the filter passes
    //      reverse this before weighting taps)
    // a:   square root of the normalized axial view depth; squaring it
    //      recovers a linear depth in [0, 1]

    vec4 gbuffer_data_0 = texelFetch(colortex1, gbuffer_texel, 0);

    vec3 flat_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data_0.z));
    vec3 view_normal = mat3(gbufferModelView) * flat_normal;

    sspt_filter_data = vec4(view_normal * 0.5 + 0.5, sqrt(clamp01(-view_pos.z / far)));

    // ---- trace ----

    // Bluenoise dither for the ray march start, rotated per frame so the
    // march pattern does not repeat under the accumulator.
    float march_jitter = fract(
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b
      + hash1(vec3(gl_FragCoord.xy, float(frameCounter)))
    );

    vec3 indirect_light = sspt_gather_light(view_pos, flat_normal, march_jitter, is_hand);

    // ---- vanilla blocklight gate ----
    // .a carries how much of the accumulated vanilla blocklight fallback
    // this pixel earns: blocklight from the lightmap, weighted by AO and
    // the user's blend amount. d5_sspt_accumulate merges it into the
    // temporal result, so close-range blocklight stays solid even where
    // screen-space tracing has no geometry to bounce from.

    vec2 light_levels = unpack_unorm_2x8(gbuffer_data_0.w);

    float ao = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).x;
    if (is_hand) ao = 1.0;

    float blocklight_gate = pow4(light_levels.x) * sqr(ao) * ssptLightmapBlend;

    sspt_indirect = vec4(indirect_light, blocklight_gate);
}
