/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c2_dof
  Calculate depth of field

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 scene_color;
#ifdef INDIRECT_LIGHTING
layout(location = 1) out vec4 indirect_bounce1;
layout(location = 2) out vec4 indirect_receiver_albedo;
/* RENDERTARGETS: 0,2,3 */
#else
/* RENDERTARGETS: 0 */
#endif

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0;
#ifdef INDIRECT_LIGHTING
uniform sampler2D colortex1; // G-buffer albedo/material data before GI owns colortex2
uniform sampler2D colortex7; // low-resolution view-space irradiance cache
#endif

#if defined INDIRECT_LIGHTING && defined COLORED_LIGHTS
uniform sampler3D light_sampler_a;
uniform sampler3D light_sampler_b;
#endif

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float near, far;

uniform float aspectRatio;
uniform float centerDepthSmooth;

uniform int frameCounter;

uniform vec2 view_pixel_size;
uniform vec2 view_res;
uniform vec2 taa_offset;

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"
#include "/include/utility/space_conversion.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/color.glsl"
#if defined INDIRECT_LIGHTING
#include "/include/lighting/indirect_lighting.glsl"
#endif
#if defined INDIRECT_LIGHTING && defined COLORED_LIGHTS
#include "/include/lighting/lpv/blocklight.glsl"
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    float depth = texelFetch(depthtex0, texel, 0).x;

#ifdef INDIRECT_LIGHTING
    indirect_bounce1 = vec4(0.0);
    indirect_receiver_albedo = vec4(0.0);
    vec3 indirect_contribution = vec3(0.0);
#endif

    vec3 pre_dof_color = texelFetch(colortex0, texel, 0).rgb;

#ifdef INDIRECT_LIGHTING
    if (depth < 0.99999 && depth >= hand_depth) {
        vec3 receiver_view_pos = indirect_reconstruct_view_position(uv, depth);
        vec3 receiver_normal = indirect_reconstruct_normal(uv);
        vec3 base_scene = texelFetch(colortex0, texel, 0).rgb;

        // c2 runs before c3 consumes the G-buffer. Read the packed albedo
        // directly from colortex1 rather than using lit scene color as a proxy.
        // This preserves genuine material-colored diffuse bounce.
        vec4 gbuffer_albedo = texelFetch(colortex1, texel, 0);
        vec2 albedo_rg = unpack_unorm_2x8(gbuffer_albedo.x);
        vec2 albedo_ba = unpack_unorm_2x8(gbuffer_albedo.y);
        vec3 receiver_albedo = clamp(
            vec3(albedo_rg, albedo_ba.x),
            vec3(0.0),
            vec3(1.0)
        );
        receiver_albedo = max(receiver_albedo, vec3(0.02));

        float gather_weight = 0.0;
        vec3 bounce1 = indirect_gather_scene(
            uv,
            receiver_view_pos,
            receiver_normal,
            receiver_albedo,
            view_pixel_size,
            gather_weight
        );

        // The gathered irradiance is already a diffuse quantity. Keep the
        // first bounce deliberately conservative because source radiance is
        // measured from the shaded scene rather than an unlit radiance G-buffer.
        bounce1 *= 0.18 * clamp01(gather_weight);

        float receiver_depth = abs(screen_to_view_space_depth(gbufferProjectionInverse, depth));
        vec3 cache_bounce = indirect_sample_cache(uv, receiver_depth);
        float cache_surface = max0(dot(receiver_normal, normalize(-receiver_view_pos)));
        bounce1 += cache_bounce * indirect_cache_strength * 0.14 * cache_surface * receiver_albedo;

#if defined COLORED_LIGHTS
        vec3 scene_pos = view_to_scene_space(receiver_view_pos);
        vec3 lpv = get_lpv_blocklight(scene_pos, receiver_normal, vec3(0.0), 1.0);
        bounce1 += lpv * INDIRECT_LPV_INTENSITY * 0.18;
#endif

        bounce1 = max(bounce1, vec3(0.0));
        indirect_contribution = bounce1 * INDIRECT_INTENSITY;
        indirect_bounce1 = vec4(bounce1, 1.0);
        indirect_receiver_albedo = vec4(receiver_albedo, 1.0);

        if (INDIRECT_BOUNCE_COUNT >= 1) {
            scene_color = base_scene + indirect_contribution;
        } else {
            scene_color = base_scene;
        }
    }
#endif

#ifdef LOD_MOD_ACTIVE
    float depth_lod = texelFetch(lod_depth_tex, texel, 0).x;

    if (is_lod_terrain(depth, depth_lod)) {
        depth = view_to_screen_space_depth(
            gbufferProjection,
            screen_to_view_space_depth(lod_projection_matrix_inverse, depth_lod)
        );
    }
#endif

    if (depth < hand_depth) {
        scene_color = texelFetch(colortex0, texel, 0).rgb;
        return;
    };

#ifdef DOF
    // Calculate vogel disk rotation
    float theta = texelFetch(noisetex, texel & 511, 0).b;
    theta = r1(frameCounter, theta);
    theta *= tau;

    // Calculate circle of confusion
    float focus = DOF_FOCUS < 0.0
        ? centerDepthSmooth
        : view_to_screen_space_depth(gbufferProjection, DOF_FOCUS);
    vec2 CoC = min(abs(depth - focus), 0.1) * (DOF_INTENSITY * 0.2 / 1.37)
        * vec2(1.0, aspectRatio) * gbufferProjection[1][1];

    scene_color = vec3(0.0);

    for (int i = 0; i < DOF_SAMPLES; ++i) {
        vec2 offset = vogel_disc_sample(i, DOF_SAMPLES, theta);
        scene_color
            += textureLod(
                   colortex0,
                   clamp(
                       vec2(uv + offset * CoC),
                       vec2(0.0),
                       vec2(
                           1.0 - 2.0 * view_pixel_size * rcp(taau_render_scale)
                       )
                   ) * taau_render_scale,
                   0
            )
                   .rgb;
    }

    scene_color *= rcp(DOF_SAMPLES);
#ifdef INDIRECT_LIGHTING
    scene_color += indirect_contribution;
#endif
#else
#ifdef INDIRECT_LIGHTING
    scene_color = pre_dof_color + indirect_contribution;
#else
    scene_color = texelFetch(colortex0, texel, 0).rgb;
#endif
#endif
}
