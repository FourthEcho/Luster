#if !defined INCLUDE_PROGRAM_GI_ACCUMULATE
#define INCLUDE_PROGRAM_GI_ACCUMULATE

// ============================================================================
//  Temporal accumulate — blend the latest bounce's output with the
//  previous frame's accumulated radiance, gated by pixel age and
//  disocclusion. Optionally updates the variance / mean-luma buffer
//  used by the A-Trous SVGF filter passes.
//
//  Reads:
//    colortex17 — latest bounce output (this frame)
//    colortex18 — previous accumulated radiance (reprojected)
//    colortex5  — TAA history (used as a disocclusion fallback)
//
//  Writes:
//    colortex18 — new accumulated radiance (+ pixel age in alpha)
//    colortex19 — variance + mean luma (only when A_SVGF is on)
// ============================================================================

#include "/include/global.glsl"

// ----------------------------------------------------------------------------
//   Uniforms — MUST be before shared.glsl (which brings space_conversion
//   that references them at global scope).
// ----------------------------------------------------------------------------

uniform sampler2D colortex1;  // gbuffer data 0 (normals, lightmaps)
uniform sampler2D colortex5;  // TAA scene history
uniform sampler2D colortex17; // this frame's bounce output
uniform sampler2D colortex18; // previous accumulated
#ifdef A_SVGF
uniform sampler2D colortex19; // previous variance / mean luma
#endif

uniform sampler2D depthtex1; // fallback combined_depth_tex when no LoD mod

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
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#define TEMPORAL_REPROJECTION

#include "/program/gi/shared.glsl"

layout(location = 0) out vec4 history_out;
#ifdef A_SVGF
layout(location = 1) out vec2 moments_out;
/* RENDERTARGETS: 18,19 */
#else
/* RENDERTARGETS: 18 */
#endif

in vec2 uv;

void main() {
    history_out = vec4(0.0);
#ifdef A_SVGF
    moments_out = vec2(0.0);
#endif

    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 full_texel = gi_full_res_texel();

    float depth = gi_read_depth(full_texel);
    if (depth >= 1.0 || depth < hand_depth) return;

    // Read the latest bounce's output.
    vec3 current = max0(texelFetch(colortex17, texel, 0).rgb);

    // Reconstruct view / scene position for reprojection.
    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    bool hand = depth < hand_depth;
    vec3 prev_uv = gi_reproject(scene_pos, hand);

    // Default to the current sample if we can't reproject cleanly.
    vec3 accumulated = current;
    float age = 1.0;

    // Off-screen / out-of-frustum reproject — fall back to TAA's history
    // so disoccluded pixels get a reasonable color estimate instead of
    // zero. This is the "use TAA history" trick: the same reprojected
    // sample that TAA uses for its color history, we use for our GI
    // history, which means disocclusions in GI and TAA are aligned.
    bool off_screen = clamp01(prev_uv.xy) != prev_uv.xy;

    if (!off_screen) {
        // 4-tap bilinear sample of the previous accumulated radiance,
        // gated by depth to reject disoccluded history.
        ivec2 rep_pixel = ivec2(floor(prev_uv.xy * view_res * gi_render_scale - 0.5));
        vec2 subpix = fract(prev_uv.xy * view_res * gi_render_scale - 0.5 - rep_pixel);

        const ivec2 offsets[4] = ivec2[4](
            ivec2(0, 0),
            ivec2(1, 0),
            ivec2(0, 1),
            ivec2(1, 1)
        );
        float weights[4] = float[4](
            (1.0 - subpix.x) * (1.0 - subpix.y),
            subpix.x         * (1.0 - subpix.y),
            (1.0 - subpix.x) * subpix.y,
            subpix.x         * subpix.y
        );

        vec3 prev_radiance = vec3(0.0);
        float prev_age = 0.0;
        float sum_weight = 0.0;

        for (int i = 0; i < 4; ++i) {
            ivec2 p = rep_pixel + offsets[i];
            if (p.x < 0 || p.y < 0 || p.x >= int(view_res.x * 0.5) || p.y >= int(view_res.y * 0.5))
                continue;
            vec4 h = texelFetch(colortex18, p, 0);
            prev_radiance += h.rgb * weights[i];
            prev_age += h.a * weights[i];
            sum_weight += weights[i];
        }

        if (sum_weight > 1e-3) {
            prev_radiance /= sum_weight;
            prev_age /= sum_weight;

            // EMA blend — alpha goes to ~1/N over N frames, with a small
            // floor so transient noise doesn't get stuck.
            float new_age = min(prev_age + 1.0, float(INDIRECT_LIGHTING_HISTORY));
            float alpha = max(1.0 / new_age, 1.0 / float(INDIRECT_LIGHTING_HISTORY));

            // Firefly clamp — limit the history's per-channel contribution
            // to a multiple of the current sample's luminance so a single
            // bright pixel can't poison the history for many frames.
            float current_luma = dot(current, luminance_weights);
            float prev_luma = dot(prev_radiance, luminance_weights);
            float clamp_limit = max(current_luma * 4.0 + 0.02, current_luma + 0.05);
            prev_radiance = min(prev_radiance, vec3(clamp_limit));

            accumulated = mix(prev_radiance, current, alpha);
            age = new_age;
        } else {
            // Disocclusion — pull from TAA's history as a fallback.
            vec3 taa_history = max0(texture(colortex5, prev_uv.xy).rgb);
            accumulated = mix(current, taa_history * 0.25, 0.5);
            age = 1.0;
        }
    } else {
        // Off-screen reproject — fresh pixel, low age.
        accumulated = current;
        age = 1.0;
    }

    history_out = vec4(max0(accumulated), age);

#ifdef A_SVGF
    // Compute first two moments of the local neighborhood (3x3) for the
    // SVGF filter. The filter uses variance / mean luma to derive the
    // edge-stopping weight in the luma domain.
    vec3 center = max0(texelFetch(colortex17, texel, 0).rgb);
    float center_luma = dot(center, luminance_weights);

    float sum_luma = center_luma;
    float sum_luma_sq = center_luma * center_luma;
    float count = 1.0;

    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;
            ivec2 p = texel + ivec2(x, y);
            if (p.x < 0 || p.y < 0
                || p.x >= int(view_res.x * 0.5)
                || p.y >= int(view_res.y * 0.5)) continue;
            vec3 s = max0(texelFetch(colortex17, p, 0).rgb);
            float l = dot(s, luminance_weights);
            sum_luma += l;
            sum_luma_sq += l * l;
            count += 1.0;
        }
    }

    float mean = sum_luma / count;
    float variance = max0(sum_luma_sq / count - mean * mean);
    moments_out = vec2(variance, mean);
#endif
}

#endif // INCLUDE_PROGRAM_GI_ACCUMULATE
