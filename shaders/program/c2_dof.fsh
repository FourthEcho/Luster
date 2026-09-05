/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c2_dof
  Calculate depth of field (focus-based blur).

  - DOF disabled : program disabled (no blur applied)
  - DOF enabled  : focus-based depth of field. CoC is derived
                   from |depth - focus|, with focus either set
                   explicitly by DOF_FOCUS or auto-tracked by
                   centerDepthSmooth.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"
#include "/include/camera/camera.glsl"

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0;

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
uniform vec2 taa_offset;

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"
#include "/include/utility/space_conversion.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

#ifndef DOF
    scene_color = texelFetch(colortex0, texel, 0).rgb;
    return;
#endif

    float depth = texelFetch(depthtex0, texel, 0).x;

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

    // Calculate vogel disk rotation
    float theta = texelFetch(noisetex, texel & 511, 0).b;
    theta = r1(frameCounter, theta);
    theta *= tau;

    // ---- Physical circle of confusion (thin-lens model) ----
    // Focal length from the vertical FOV and sensor height, aperture
    // diameter from the f-stop number: CoC = (f^2 / N) * |1/S - 1/D|.
    // Replaces the old artistic DOF_INTENSITY scaling: wide apertures
    // (f/0.8) give razor-thin focus, narrow ones (f/16) are sharp deep
    // into the scene, exactly like a real lens.
    vec2 CoC;

    float dist_lin = max(
        abs(screen_to_view_space_depth(gbufferProjectionInverse, depth)),
        eps
    );
    float focus_lin = DOF_FOCUS < 0.0
        ? max(
              abs(screen_to_view_space_depth(
                  gbufferProjectionInverse,
                  centerDepthSmooth
              )),
              eps
          )
        : max(abs(DOF_FOCUS), eps);
    float sensor_h = camera_sensor_height_mm(aspectRatio);
    float focal_mm
        = camera_focal_length_mm(gbufferProjection[1][1], aspectRatio);
    float coc = min(
        camera_coc_height_fraction(focal_mm, sensor_h, focus_lin, dist_lin),
        DOF_MAX_RADIUS
    );
    CoC = coc * vec2(1.0, aspectRatio);
#ifdef BLOOM_ANAMORPHIC
    // Anamorphic squeeze: horizontal CoC stretch for oval bokeh
    CoC.x *= BLOOM_ANAMORPHIC_STRETCH;
#endif

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

#ifdef CHROMATIC_DISPERSION
    // Chromatic dispersion: radial spectral fringing scaled by the circle
    // of confusion, so in-focus regions stay clean and only defocused
    // areas fringe like a real camera lens
    {
        float coc_radius = length(CoC);
        vec2 center_offset = uv - 0.5;
        vec2 radial_dir
            = center_offset / max(length(center_offset), 1e-4);
        vec2 spectral_offset
            = radial_dir * coc_radius * (CHROMATIC_DISPERSION_STRENGTH * 0.1);
        vec2 clamp_max = vec2(
            1.0 - 2.0 * view_pixel_size * rcp(taau_render_scale)
        );
        scene_color.r = textureLod(
            colortex0,
            clamp(vec2(uv - spectral_offset), vec2(0.0), clamp_max)
                * taau_render_scale,
            0
        ).r;
        scene_color.b = textureLod(
            colortex0,
            clamp(vec2(uv + spectral_offset), vec2(0.0), clamp_max)
                * taau_render_scale,
            0
        ).b;
    }
#endif
}

