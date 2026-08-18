/*
--------------------------------------------------------------------------------

  Luster Shaders

  program/c20_motion_blur:
  Apply motion blur

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float frameTime;
uniform float near;
uniform float far;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#define TEMPORAL_REPROJECTION
#include "/include/utility/space_conversion.glsl"

#define MOTION_BLUR_SAMPLES 20

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 view_texel = ivec2(gl_FragCoord.xy * taau_render_scale);

    float depth = texelFetch(depthtex0, view_texel, 0).x;

    if (depth < hand_depth) {
        scene_color = texelFetch(colortex0, texel, 0).rgb;
        return;
    }

    // Reconstruct the center pixel view-space depth for temporal rejection.
    // Compare it with each tap to reject incompatible motion history.
    // artefact: taps that sample a fragment belonging to a different
    // (e.g. much closer) surface are rejected instead of being smeared along
    // the velocity vector.
    float center_view_depth = screen_to_view_space_depth(gbufferProjectionInverse, depth);

    vec2 velocity = uv - reproject(vec3(uv, depth)).xy;
    vec2 pos = uv;
    vec2 increment
        = (0.5 * MOTION_BLUR_INTENSITY / float(MOTION_BLUR_SAMPLES)) * velocity;

    // Adaptive rejection threshold: scale the depth tolerance with the
    // fragment's distance from the camera so distant surfaces (which have
    // smaller depth deltas per world unit) are still rejected correctly.
    float depth_tolerance = max(0.5, 0.02 * center_view_depth);

    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    for (uint i = 0u; i < MOTION_BLUR_SAMPLES; ++i, pos += increment) {
        ivec2 tap = ivec2(pos * view_res);
        ivec2 view_tap = ivec2(pos * view_res * taau_render_scale);

        // Reject taps that fall outside the screen
        if (clamp01(pos) != pos) continue;

        float tap_depth = texelFetch(depthtex0, view_tap, 0).x;

        // Reject taps that hit the hand layer
        if (tap_depth < hand_depth) continue;

        // Depth-aware tap rejection: only accept the tap if it lies on the
        // same surface as the centre pixel.  This prevents fast-moving
        // foreground objects from smearing their colour across the
        // background along the velocity vector.
        float tap_view_depth
            = screen_to_view_space_depth(gbufferProjectionInverse, tap_depth);
        float depth_diff = abs(tap_view_depth - center_view_depth);

        // Soft rejection weight instead of a hard binary test: this gives a
        // smoother blend at depth discontinuities and avoids flickering when
        // the motion vector crosses a silhouette edge.
        float weight = exp2(-depth_diff / depth_tolerance);

        vec3 color = texelFetch(colortex0, tap, 0).rgb;
        color_sum += color * weight;
        weight_sum += weight;
    }

    scene_color = color_sum * rcp(max(weight_sum, eps));
}
