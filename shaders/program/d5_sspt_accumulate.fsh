/*
--------------------------------------------------------------------------------

  program/d5_sspt_accumulate:
  Temporal reconstruction stage of the SSPT chain. Reprojects last frame's
  result onto this frame, blends the fresh trace in with an
  accumulation-length alpha, and raises that alpha whenever the history no
  longer matches — moved camera, changed blocklight, changed world. When no
  usable history exists (first frame, off-screen reprojection, world
  change), luminance moments and a color estimate come from a wide
  normal-weighted patch instead.

  Reads
    colortex17  raw trace: radiance (rgb) + blocklight gate (a)  [from d4]
    colortex18  previous history: radiance (rgb) + frames (a)
    colortex19  filter data: view normal, sqrt normalized depth  [from d4]
    colortex20  previous auxiliary: moments (xy), lightmap (z),
                sqrt normalized distance (w)

  Writes
    colortex17  accumulated radiance + relative sigma (a)
    colortex18  new history: pre-merge radiance (rgb) + frames (a)
    colortex20  new auxiliary

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 sspt_filtered;   // colortex17
layout(location = 1) out vec4 sspt_history;    // colortex18
layout(location = 2) out vec4 sspt_auxiliary;  // colortex20

/* RENDERTARGETS: 17,18,20 */

const bool colortex18Clear = false;
const bool colortex20Clear = false;

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex1;  // gbuffer 0
uniform sampler2D depthtex1;  // combined_depth_tex when no LoD mod is active
uniform sampler2D colortex17; // sspt raw color + blocklight gate
uniform sampler2D colortex18; // sspt history color + frames
uniform sampler2D colortex19; // sspt filter data
uniform sampler2D colortex20; // sspt history auxiliary

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

uniform vec2 view_res;
uniform vec2 taa_offset;

uniform bool world_age_changed;

// ------------
//   Includes
// ------------

#include "/include/lighting/colors/blocklight_color.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

// SSPT buffer scale — mirrors size.buffer.colortex17-20 in
// shaders.properties, driven by indirectResReduction
#if indirectResReduction == 1
const float sspt_render_scale = 1.0;
#elif indirectResReduction == 3
const float sspt_render_scale = 0.333333;
#elif indirectResReduction == 4
const float sspt_render_scale = 0.25;
#else // indirectResReduction == 2
const float sspt_render_scale = 0.5;
#endif

// ------------
//   Helpers
// ------------

// Relative luminance in the pack's working color space (Rec. 2020).
float sspt_luminance(vec3 color) {
    return dot(color, luminance_weights_rec2020);
}

// Active SSPT buffer extent in texels.
vec2 sspt_buffer_size() {
    return view_res * sspt_render_scale;
}

// Keep a texel coordinate inside the SSPT buffers.
ivec2 sspt_clamp_texel(ivec2 texel) {
    return clamp(texel, ivec2(0), ivec2(sspt_buffer_size()) - 1);
}

// Filter data is stored as normal * 0.5 + 0.5 and sqrt(normalized depth);
// the alpha is squared to get linear normalized depth back.
vec4 sspt_filter_data(ivec2 texel) {
    vec4 value = texelFetch(colortex19, texel, 0);
    return vec4(value.rgb * 2.0 - 1.0, sqr(value.a));
}

// Scene-space position of this frame -> screen-space position of last frame.
vec3 sspt_previous_screen_pos(vec3 scene_pos) {
    vec3 previous_scene_pos = scene_pos + (cameraPosition - previousCameraPosition);
    vec3 previous_view_pos = transform(gbufferPreviousModelView, previous_scene_pos);
    return project_and_divide(gbufferPreviousProjection, previous_view_pos) * 0.5 + 0.5;
}

// ------------
//   Spatial estimates
// ------------

// True when two texels sit on different surfaces: the world-space depth
// gap exceeds a threshold that grows with the center's distance, so
// nearby geometry is resolved finely while distant geometry tolerates
// proportionally larger gaps.
bool sspt_surface_gate(float center_depth, float tap_depth) {
    return abs(tap_depth - center_depth) * far
         > max(0.25, 0.05 * center_depth * far);
}

// Bilateral estimate of this frame's raw trace, feeding the temporal
// blend. 5x5 binomial-gaussian footprint; taps are dropped across depth
// discontinuities and weighted by normal agreement and a Huber-style
// relative luminance response.
vec3 sspt_prefiltered_trace(ivec2 texel) {
    vec4 center_data = sspt_filter_data(texel);
    vec3 center_color = texelFetch(colortex17, texel, 0).rgb;
    float center_luminance = sspt_luminance(center_color);

    // Separable binomial weights: outer product of (1, 4, 6, 4, 1) / 16,
    // indexed by |offset| along each axis.
    const float binomial[3] = float[3](0.375, 0.25, 0.0625);

    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    const int radius = 2;
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            ivec2 tap_texel = sspt_clamp_texel(texel + ivec2(x, y));
            vec4 tap_data = sspt_filter_data(tap_texel);

            if (sspt_surface_gate(center_data.w, tap_data.w)) continue;

            vec3 tap_color = texelFetch(colortex17, tap_texel, 0).rgb;
            float tap_luminance = sspt_luminance(tap_color);

            float footprint = binomial[abs(x)] * binomial[abs(y)];
            float normal_agreement
                = pow(max0(dot(center_data.xyz, tap_data.xyz)), 4.0);

            // Huber-style response: linear in the relative luminance
            // difference, clipped so lone fireflies cannot dominate.
            float luma_ratio = abs(tap_luminance - center_luminance)
                             * rcp(max(center_luminance, 1e-3));
            float luma_weight = exp(-min(luma_ratio, 4.0));

            float weight = footprint * normal_agreement * luma_weight;

            color_sum += tap_color * weight;
            weight_sum += weight;
        }
    }

    return color_sum / max(weight_sum, 1e-6);
}

// First and second luminance moments plus a color estimate, used whenever
// temporal history is unavailable — the moments seed the variance the SVGF
// passes rely on. Sampled on a sparse stride-2 grid over a 7x7 footprint:
// moments tolerate noisy estimates, so a quarter of the taps buy the same
// statistics for a quarter of the cost.
vec3 sspt_patch_moments(ivec2 texel, out vec2 moments, out float sigma) {
    vec4 center_data = sspt_filter_data(texel);
    vec3 center_color = texelFetch(colortex17, texel, 0).rgb;

    vec3 color_sum = center_color;
    float weight_sum = 1.0;

    float luminance_mean = sspt_luminance(center_color);
    float luminance_sq_mean = sqr(luminance_mean);

    for (int y = -3; y <= 3; y += 2) {
        for (int x = -3; x <= 3; x += 2) {
            ivec2 tap_texel = sspt_clamp_texel(texel + ivec2(x, y));
            vec4 tap_data = sspt_filter_data(tap_texel);

            if (sspt_surface_gate(center_data.w, tap_data.w)) continue;

            vec3 tap_color = texelFetch(colortex17, tap_texel, 0).rgb;
            float tap_luminance = sspt_luminance(tap_color);

            float weight = pow(max0(dot(center_data.xyz, tap_data.xyz)), 3.0);

            color_sum += tap_color * weight;
            weight_sum += weight;

            luminance_mean += tap_luminance * weight;
            luminance_sq_mean += sqr(tap_luminance) * weight;
        }
    }

    luminance_mean *= rcp(weight_sum);
    luminance_sq_mean *= rcp(weight_sum);

    moments = clamp01(vec2(luminance_mean, luminance_sq_mean));
    sigma = sqrt(max0(luminance_sq_mean - sqr(luminance_mean)))
          * rcp(max(luminance_mean, eps)) * 2.0;

    return color_sum * rcp(weight_sum);
}

// ------------
//   Main
// ------------

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    // .w = 1 marks "no history": a squared depth of 1 can never match a
    // normalized scene distance below 1, so stale texels fail validation.
    sspt_auxiliary = vec4(1.0);
    sspt_history = vec4(0.0);
    sspt_filtered = vec4(texelFetch(colortex17, texel, 0).rgb, 0.0);

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth >= 1.0) return;

    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        vec3(uv, depth),
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    float scene_distance = clamp01(length(scene_pos) / far);

    vec3 reprojection = sspt_previous_screen_pos(scene_pos);
    bool history_offscreen = clamp01(reprojection.xy) != reprojection.xy;

    // The blocklight gate d4 wrote, read before this pass overwrites
    // colortex17.
    float blocklight_gate = texelFetch(colortex17, texel, 0).a;

    // Current lightmap blocklight — the quantity the invalidation test
    // watches, since a torch placed or removed last frame changes it sharply.
    vec2 light_levels = unpack_unorm_2x8(texelFetch(colortex1, gbuffer_texel, 0).w);
    float blocklight = pow4(light_levels.x);

    vec3 accumulated_light;
    float accumulated_frames;
    float sigma;
    vec2 moments = vec2(0.0);
    float history_blocklight = blocklight;

    if (history_offscreen || world_age_changed) {
        accumulated_light = sspt_patch_moments(texel, moments, sigma);
        accumulated_frames = 1.0;
    } else {
        // 4-tap bilinear history fetch around the reprojection.
        vec2 history_pos = reprojection.xy * sspt_buffer_size() - 0.5;
        ivec2 history_texel = ivec2(floor(history_pos));
        vec2 subpixel = fract(history_pos);

        const ivec2 tap_offsets[4] = ivec2[4](
            ivec2(0, 0),
            ivec2(1, 0),
            ivec2(0, 1),
            ivec2(1, 1)
        );

        float tap_weights[4] = float[4](
            (1.0 - subpixel.x) * (1.0 - subpixel.y),
            subpixel.x         * (1.0 - subpixel.y),
            (1.0 - subpixel.x) * subpixel.y,
            subpixel.x         * subpixel.y
        );

        vec4 history_color = vec4(0.0);
        vec3 history_aux = vec3(0.0);
        float weight_sum = 0.0;

        // Camera translation along the view axis shifts every depth at
        // once; grant the history that much slack before rejecting it.
        vec3 camera_motion_view
            = mat3(gbufferModelView) * (cameraPosition - previousCameraPosition);
        float depth_slack = abs(camera_motion_view.z) * rcp(far);

        for (int i = 0; i < 4; ++i) {
            ivec2 tap_texel = history_texel + tap_offsets[i];

            if (sspt_clamp_texel(tap_texel) != tap_texel) continue;

            vec4 tap_aux = texelFetch(colortex20, tap_texel, 0);

            // Stored depth is sqrt-ed; square it to compare against the
            // current normalized distance.
            float depth_error = abs(sqr(tap_aux.w) - scene_distance);

            if (depth_error <= depth_slack + 0.15 * scene_distance) {
                history_color += max0(texelFetch(colortex18, tap_texel, 0)) * tap_weights[i];
                history_aux += tap_aux.xyz * tap_weights[i];
                weight_sum += tap_weights[i];
            }
        }

        if (weight_sum > 1e-3) {
            history_color /= weight_sum;
            history_aux /= weight_sum;

            accumulated_frames = min(history_color.a + 1.0, maxFrames);

            // Temporal blend factors: the fresh trace enters at 1/frames
            // with a small floor scaled by the user's responsiveness boost.
            // Moments update twice as fast as color — the variance
            // guidance can only be trusted once the statistics converge.
            float alpha_color = max(rcp(accumulated_frames), 0.005 * minAccumMult);
            float alpha_moments = 2.0 * alpha_color;

            // Raise the alpha when the lightmap changed: blocklight jumps
            // are instantly visible and must not smear over many frames.
            // The delta is normalized by the brighter of the two levels, so
            // quantization wiggle stays negligible while a torch appearing
            // or disappearing saturates the term.
            float blocklight_delta = sqr(
                abs(blocklight - history_aux.z)
                    * rcp(max(max(blocklight, history_aux.z), 0.05))
            );
            float invalidation = clamp01(ADAPT_STRENGTH * blocklight_delta);

            alpha_color = max(alpha_color, invalidation);
            alpha_moments = max(alpha_moments, invalidation);

            vec3 current_light = sspt_prefiltered_trace(texel);
            float current_luminance = sspt_luminance(current_light);

            moments = mix(
                history_aux.xy,
                vec2(current_luminance, sqr(current_luminance)),
                alpha_moments
            );

            accumulated_light = mix(history_color.rgb, current_light, alpha_color);

            // Relative sigma from the blended moments, inflated while the
            // history is untrustworthy (or young), so the filter leans on
            // geometry rather than statistics.
            sigma = sqrt(max0(moments.y - sqr(moments.x)))
                  * rcp(max(moments.x, 1e-8));
            sigma *= 1.0 + invalidation + rcp(sqrt(accumulated_frames));

            history_blocklight = mix(
                history_aux.z, blocklight, max(0.2, 1.0 / accumulated_frames)
            );
        } else {
            accumulated_light = sspt_patch_moments(texel, moments, sigma);
            accumulated_frames = 1.0;
        }
    }

    // Merge the vanilla blocklight fallback into the displayed result only:
    // the history keeps the pure trace, so the gate can follow the lightmap
    // without poisoning the accumulation.
    vec3 merged_light = accumulated_light + blocklight_gate * blocklight_color * rcp(tau);

    sspt_filtered = vec4(merged_light, sigma);
    sspt_history = vec4(accumulated_light, accumulated_frames);
    sspt_auxiliary = vec4(clamp01(moments), history_blocklight, sqrt(scene_distance));
}
