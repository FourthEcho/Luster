/*
--------------------------------------------------------------------------------

  Luster Shader by FourthEcho

  program/c23_capture:
  Rebuild the screen-space sphere capture used for off-screen reflections.

  Renders a 1024x512 equirectangular panorama around the camera into
  colortex21 (linear scene color + raw depth flag) and colortex22
  (camera-relative scene position + age). Directions visible on screen are
  refreshed from the current frame; off-screen directions keep the previous
  frame with camera-translation compensation, so the panorama accumulates
  over time. Buffers are never cleared, which is what makes the temporal
  accumulation work. Runs only while REFLECTION_CAPTURE is enabled.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#ifdef REFLECTION_CAPTURE
// Iris requires boolean shader options to be checked with #ifdef/#ifndef.
#define REFLECTION_CAPTURE_OPTION_ENABLED
#endif

layout(location = 0) out vec4 capture_color;
layout(location = 1) out vec4 capture_pos;

/* RENDERTARGETS: 21,22 */

in vec2 uv;

uniform sampler2D colortex5; // TAA scene history (linear HDR, current frame)
// Previous capture color/position (temporal persistence) are declared in
// include/lighting/reflection_capture.glsl, included below.
uniform sampler2D depthtex0; // full depth buffer (real depth in composite)

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec2 taa_offset;

uniform float near;
uniform float far;

#include "/include/utility/space_conversion.glsl"
#include "/include/lighting/reflection_capture.glsl"

void main() {
    // Start from last frame; the buffers are never cleared, so this is what
    // accumulates off-screen content over time.
    capture_color = texture(colortex21, uv);
    capture_pos = texture(colortex22, uv);

    if (any(isnan(capture_color.rgb)) || any(isnan(capture_pos.rgb))) {
        capture_color = vec4(0.0, 0.0, 0.0, 1.0);
        capture_pos = vec4(0.0);
    }

#ifdef REFLECTION_CAPTURE
    vec3 capture_dir = project_capture_direction(uv);
    vec3 view_dir = mat3(gbufferModelView) * capture_dir;

    // Project the ray to the screen. Any point along the ray maps to the
    // same uv, so projecting the unit direction is sufficient.
    bool on_screen = false;
    vec3 screen_pos = vec3(0.0);
    if (view_dir.z < 0.0) {
        screen_pos = view_to_screen_space(
            gbufferProjection,
            view_dir,
            false
        );

        const vec2 inset = reflection_capture_rcp * 2.0;
        on_screen = clamp(screen_pos.xy, inset, 1.0 - inset) == screen_pos.xy;
    }

    if (on_screen) {
        float depth = texture(depthtex0, screen_pos.xy).x;

        if (depth < 1.0) {
            // TAA history alpha counts accumulated frames; require at
            // least one so unconverged (fresh-buffer) history never
            // poisons the capture with black. Otherwise keep the previous
            // accumulation for this texel.
            vec4 history = texture(colortex5, screen_pos.xy);
            if (history.a > 0.5 && !any(isnan(history.rgb))) {
                capture_color = vec4(history.rgb, depth);

                vec3 view_pos = screen_to_view_space(
                    vec3(screen_pos.xy, depth),
                    false
                );
                vec3 scene_pos = view_to_scene_space(view_pos);
                if (any(isnan(scene_pos))) {
                    capture_color = vec4(0.0, 0.0, 0.0, 1.0);
                    capture_pos = vec4(capture_dir * far, 0.0);
                } else {
                    capture_pos = vec4(
                        clamp(scene_pos, vec3(-65000.0), vec3(65000.0)),
                        0.0
                    );
                }
            }
        } else {
            // Sky: nothing to store, mark explicitly as no-data.
            capture_color = vec4(0.0, 0.0, 0.0, 1.0);
            capture_pos = vec4(capture_dir * far, 0.0);
        }
    } else {
        // Off-screen direction (or behind the camera): compensate camera
        // translation from the previous frame. Content now at uv came from
        // uv - shift, where shift is how far the stored surface moved in
        // capture space.
        vec3 camera_delta = cameraPosition - previousCameraPosition;
        float distance_traveled = length(camera_delta);

        if (distance_traveled < 1e-2) {
            capture_pos.a = min(capture_pos.a + 1.0, 255.0);
        } else {
            vec3 stored_pos = capture_pos.rgb;
            vec3 moved_pos = stored_pos + camera_delta;

            vec2 shift = unproject_capture_direction(moved_pos)
                - unproject_capture_direction(stored_pos);
            vec2 fetch_uv = fract(uv - shift);

            vec4 prev_color = texture(colortex21, fetch_uv);
            vec4 prev_pos = texture(colortex22, fetch_uv);

            bool prev_valid = prev_color.a < 1.0 - 1e-4
                && !any(isnan(prev_color.rgb))
                && !any(isnan(prev_pos.rgb));
            bool still_valid = prev_valid
                && distance_traveled <= 24.0
                && length(shift) <= 0.16
                && length(moved_pos) <= far;

            if (still_valid) {
                capture_color = vec4(prev_color.rgb, prev_color.a);
                capture_pos = vec4(
                    clamp(moved_pos, vec3(-65000.0), vec3(65000.0)),
                    min(prev_pos.a + 1.0, 255.0)
                );
            } else {
                capture_color = vec4(0.0, 0.0, 0.0, 1.0);
                capture_pos = vec4(capture_dir * far, 0.0);
            }
        }
    }

    // Stomp anything invalid to the explicit no-data marker so the read
    // side only ever sees valid captures or clean sky fallbacks.
    if (capture_color.a >= 1.0 - 1e-4 || capture_color.a <= 0.0
        || any(isnan(capture_color.rgb)) || any(isnan(capture_pos.rgb))) {
        capture_color = vec4(0.0, 0.0, 0.0, 1.0);
        capture_pos = vec4(capture_dir * far, 0.0);
    }
    capture_color.rgb = clamp(capture_color.rgb, vec3(0.0), vec3(65000.0));
    capture_pos.xyz
        = clamp(capture_pos.xyz, vec3(-65000.0), vec3(65000.0));
#else
    // Pass is disabled via program toggle as well; this is only a fallback
    // so a stray run can never inject garbage.
    capture_color = vec4(0.0, 0.0, 0.0, 1.0);
    capture_pos = vec4(0.0);
#endif
}
