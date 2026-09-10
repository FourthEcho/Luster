/*
--------------------------------------------------------------------------------

  program/d4_sspt:
  Trace one frame of screen-space path traced emission + colored lighting
  (emission + shadowed sun/moon and handheld bounce from
  include/lighting/sspt/sspt.glsl).
  Raw, noisy output — program/d5_sspt_accumulate and the SVGF filter passes
  (program/d6_sspt_filter, sizes 32/16/8/4/2) denoise it. Runs at half
  resolution in colortex17, with filter gbuffer side-data (view normal +
  sqrt view depth) in colortex19.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 indirect;      // colortex17
layout(location = 1) out vec4 filterData;  // colortex19

/* RENDERTARGETS: 17,19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex6; // ambient occlusion (same resolution)

uniform sampler2D depthtex1; // geometry depth (non-DH path)

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

#define TRACE_DEPTH combined_depth_tex
#define TRACE_PROJ combined_projection_matrix
#define TRACE_PROJ_INV combined_projection_matrix_inverse

#include "/include/misc/lod_mod_support.glsl"
#include "/include/lighting/sspt/sspt.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/space_conversion.glsl"

// ------------
//   Main
// ------------

void main() {
    // This pass renders into the half-res SSPT buffers; gl_FragCoord is in
    // buffer texels while uv spans the whole screen.
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    // initialize outputs before any early return (sky = vec4(0.0),
    // filter gbuffer = (0,0,1)*0.5+0.5 packed + depth 1)
    indirect = vec4(0.0);
    filterData = vec4(0.5, 0.5, 1.0, 1.0);

    if (clamp(gbuffer_texel, ivec2(0), ivec2(view_res) - 1) != gbuffer_texel) {
        return;
    }

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth >= 1.0) {
        return;
    }

    bool is_hand = depth < hand_depth;

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );

    // ---- gbuffer unpack (same packing as d4_deferred_shading) ----

    vec4 gbuffer_data_0 = texelFetch(colortex1, gbuffer_texel, 0);

    vec3 flat_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data_0.z));
    vec3 view_normal = mat3(gbufferModelView) * flat_normal;

    // ---- filter gbuffer side-data ----
    // rgb: view normal * 0.5 + 0.5 (unpacked as rgb * 2 - 1)
    // a:   sqrt(normalized axial linear depth)
    //      (squared back to [0, 1] linear depth on fetch)

    filterData = vec4(
        view_normal * 0.5 + 0.5,
        sqrt(clamp01(-view_pos.z / far))
    );

    // ---- trace ----
    // Hash dithers, consumed as the screenspace-RT march noise by traceIndirect.

    vec2 dither = vec2(
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b,
        texelFetch(noisetex, (ivec2(gl_FragCoord.xy) + 249) & 511, 0).b
    );

    // Emission + sun/moon + handheld bounce.
    vec3 indirect_light = traceIndirect(view_pos, flat_normal, dither, is_hand);

    // ---- blocklight lightmap weight ----
    // pow5(lightmap) * sqr(ao) * ssptLightmapBlend. Consumed by
    // program/d5_sspt_accumulate as the temporally-merged vanilla
    // blocklight fallback.

    vec2 light_levels = unpack_unorm_2x8(gbuffer_data_0.w);

    float ao = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).x;
    if (is_hand) ao = 1.0;

    float lightmap_weight = pow5(light_levels.x) * sqr(ao) * ssptLightmapBlend;

    indirect = vec4(indirect_light, lightmap_weight);
}
