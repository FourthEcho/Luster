/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c2_dof
  Calculate depth of field OR distance blur, depending on DOF_MODE.

  - DOF_MODE_OFF            : program disabled (no blur applied)
  - DOF_MODE_DOF            : focus-based depth of field. CoC is derived
                              from |depth - focus|, with focus either set
                              explicitly by DOF_FOCUS or auto-tracked by
                              centerDepthSmooth.
  - DOF_MODE_DISTANCE_BLUR  : far-field blur only. CoC grows linearly with
                              view distance beyond DISTANCE_BLUR_START, and
                              is zero up close. Uses DISTANCE_BLUR_INTENSITY
                              instead of DOF_INTENSITY.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

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

#if DOF_MODE == DOF_MODE_OFF
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

    // ---- Compute the circle of confusion (CoC) radius ----
    // The CoC is a screen-space 2D vector we use to offset each vogel
    // sample. Two regimes:
    //
    //   DOF_MODE_DOF — focus-based: |depth - focus| drives the CoC. Things
    //     at the focus plane stay sharp; things in front or behind blur.
    //     Intensity comes from DOF_INTENSITY.
    //
    //   DOF_MODE_DISTANCE_BLUR — far-field blur: the CoC grows linearly
    //     with view-space distance beyond DISTANCE_BLUR_START. Things up
    //     close stay perfectly sharp. Intensity comes from
    //     DISTANCE_BLUR_INTENSITY. (DOF_FOCUS is ignored in this mode.)
    vec2 CoC;

#if defined DOF
    float focus = DOF_FOCUS < 0.0
        ? centerDepthSmooth
        : view_to_screen_space_depth(gbufferProjection, DOF_FOCUS);
    CoC = min(abs(depth - focus), 0.1)
        * (DOF_INTENSITY * 0.2 / 1.37)
        * vec2(1.0, aspectRatio) * gbufferProjection[1][1];

#elif defined DISTANCE_BLUR
    // Recover view-space distance (magnitudes) from screen depth. We
    // convert depthtex0 (NDC depth) to a view-space distance along the
    // camera's forward axis. This is what we compare against
    // DISTANCE_BLUR_START.
    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(screen_pos, true);
    float view_dist = length(view_pos);

    // No blur up close, then a smooth ramp past DISTANCE_BLUR_START, then
    // capped to 0.1 (in screen-depth units equivalent) so we never
    // sample wildly outside the screen.
    float blur_amount
        = linear_step(DISTANCE_BLUR_START, DISTANCE_BLUR_START + 32.0, view_dist);
    CoC = vec2(blur_amount) * (DISTANCE_BLUR_INTENSITY * 0.2 / 1.37)
        * vec2(1.0, aspectRatio) * gbufferProjection[1][1];
    CoC = min(CoC, vec2(0.1));
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
}

