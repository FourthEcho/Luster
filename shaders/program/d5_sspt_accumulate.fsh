/*
--------------------------------------------------------------------------------

  program/d5_sspt_accumulate:
  Temporal accumulation for the SSPT emission. Reprojects the previous
  frame's history, validates it with depth rejection, blends with a
  variance-aware alpha, and estimates the first frame's moments
  with 5x5 / 7x7 edge-aware spatial filters when the history is
  unusable. Writes:

    colortex17  accumulated color (rgb) + temporal sigma (a)
    colortex18  history color (rgb) + accumulated frames (a)
    colortex20  history gdata: variance moments (xy), lightmap (z),
                sqrt(normalized distance) (w)

  World changes are detected via the world_age_changed uniform.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 indirectCurrent;   // colortex17
layout(location = 1) out vec4 indirectHistory;   // colortex18
layout(location = 2) out vec4 historyGData; // colortex20

/* RENDERTARGETS: 17,18,20 */

const bool colortex18Clear = false;
const bool colortex20Clear = false;

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex1;  // gbuffer 0
uniform sampler2D colortex17; // sspt raw color + lightmap weight
uniform sampler2D colortex18; // sspt history color + frames
uniform sampler2D colortex19; // sspt gbuffer data
uniform sampler2D colortex20; // sspt history gdata

uniform sampler2D depthtex1;  // geometry depth (non-DH path)

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
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

// Half-res SSPT buffer bookkeeping (matches size.buffer.colortex17-20)
const float bufferScale = 0.5;

// Relative luminance in the pack's working color space (Rec. 2020).
float getLuma(vec3 c) {
    return dot(c, luminance_weights_rec2020);
}

// Mean of two values.
float avgOf(vec2 v) {
    return (v.x + v.y) * 0.5;
}

vec2 bufferSize() {
    return view_res * bufferScale;
}

ivec2 clampTexel(ivec2 texel) {
    return clamp(texel, ivec2(0), ivec2(bufferSize()) - 1);
}

/* ------ REPROJECTION ------ */

vec3 reprojectHistory(vec3 scene_space) {
    vec3 prev_pos = scene_space + (cameraPosition - previousCameraPosition);
    prev_pos = transform(gbufferPreviousModelView, prev_pos);
    prev_pos = project_and_divide(gbufferPreviousProjection, prev_pos);
    return prev_pos * 0.5 + 0.5;
}

/* ------ EDGE-AWARE SPATIAL FILTERS ------ */

vec4 fetchGbuffer(ivec2 texel) {
    vec4 val = texelFetch(colortex19, texel, 0);
    return vec4(val.rgb * 2.0 - 1.0, sqr(val.a));
}

vec3 spatialColor(ivec2 texel) {
    // 5x5 gather, normal + depth + luma weighted.
    vec3 total_color = texelFetch(colortex17, texel, 0).rgb;
    float sum_weight = 1.0;
    float luma_center = getLuma(total_color);

    vec4 gbuffer = fetchGbuffer(texel);

    const int r = 2;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 tap = clampTexel(texel + ivec2(x, y));

            vec4 gb = fetchGbuffer(tap);

            float depth_delta = distance(gb.w, gbuffer.w) * far;

            if (depth_delta < 2.0) {
                vec3 current_color = texelFetch(colortex17, tap, 0).rgb;

                float lum = getLuma(current_color);

                float dist_lum = abs(luma_center - lum);
                    dist_lum = sqr(dist_lum) / max(luma_center, 0.027);
                    dist_lum = clamp(dist_lum, 0.0, pi);

                float weight = pow(max0(dot(gbuffer.xyz, gb.xyz)), 8.0)
                             * exp(-depth_delta - sqrt(dist_lum) * rcp_pi);

                total_color += current_color * weight;
                sum_weight += weight;
            }
        }
    }

    return total_color / sum_weight;
}

vec3 spatialColor7x7(ivec2 texel, inout vec2 variance, out float max_lum) {
    // 7x7 gather, normal + depth weighted; also builds variance moments.
    vec3 total_color = texelFetch(colortex17, texel, 0).rgb;
    float sum_weight = 1.0;
    float luma_center = getLuma(total_color);

        max_lum = luma_center;

    vec4 gbuffer = fetchGbuffer(texel);

    const int r = 3;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 tap = clampTexel(texel + ivec2(x, y));

            vec4 gb = fetchGbuffer(tap);

            float depth_delta = distance(gb.w, gbuffer.w) * far;

            if (depth_delta < 2.0) {
                vec3 current_color = texelFetch(colortex17, tap, 0).rgb;

                float weight = pow(max0(dot(gbuffer.xyz, gb.xyz)), 2.0);
                float current_luma = getLuma(current_color);

                max_lum = max(max_lum, current_luma);

                total_color += current_color * weight;
                variance += vec2(current_luma * weight, sqr(current_luma) * sqr(weight));
                sum_weight += weight;
            }
        }
    }

    total_color /= sum_weight;
    variance /= vec2(sum_weight, sqr(sum_weight));

    max_lum = clamp(max_lum, 0.0, 2.71) * rcp_pi;

    return total_color;
}

// ------------
//   Main
// ------------

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    historyGData = vec4(1.0); // .w = 1 -> sqr(1) never matches currentDistance
    indirectHistory = vec4(0.0);
    indirectCurrent = vec4(texelFetch(colortex17, texel, 0).rgb, 0.0);

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth >= 1.0) return;

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    float current_distance = clamp01(length(scene_pos) / far);

    vec3 reprojection = reprojectHistory(scene_pos);

    bool offscreen = clamp01(reprojection.xy) != reprojection.xy;

    // History texel + subpixel weights, 4-tap bilinear.
    ivec2 rep_texel = ivec2(floor(reprojection.xy * bufferSize() - vec2(0.5)));
    vec2 subpix = fract(reprojection.xy * bufferSize() - vec2(0.5) - rep_texel);

    const ivec2 offset[4] = ivec2[4](
        ivec2(0, 0),
        ivec2(1, 0),
        ivec2(0, 1),
        ivec2(1, 1)
    );

    float weight[4] = float[4](
        (1.0 - subpix.x) * (1.0 - subpix.y),
        subpix.x         * (1.0 - subpix.y),
        (1.0 - subpix.x) * subpix.y,
        subpix.x         * subpix.y
    );

    vec2 lightmap_source = unpack_unorm_2x8(
        texelFetch(colortex1, gbuffer_texel, 0).w
    );

    float lightmap = pow5(lightmap_source.x);

    vec3 rt_light = vec3(0.0);
    float samples = 0.0;
    float variance = 0.0;
    vec2 variance_data = vec2(0.0);

    // d4_sspt's lightmap blocklight weight (.a), read
    // before this pass overwrites colortex17
    float raw_lightmap_weight = texelFetch(colortex17, texel, 0).a;

    if (offscreen || world_age_changed) {
        // Offscreen / world-change path: spatial estimate only.
        rt_light = spatialColor7x7(texel, variance_data, variance);
        samples = 1.0;
    } else {
        vec4 previous_light = vec4(0.0); // rgb + frames
        vec3 previous_aux = vec3(0.0);   // variance moments + lightmap

        float sum_weight = 0.0;

        // Camera-motion depth rejection tolerance.
        vec3 camera_movement
            = mat3(gbufferModelView) * (cameraPosition - previousCameraPosition);

        // Sample history with depth rejection.
        for (int i = 0; i < 4; ++i) {
            ivec2 history_texel = rep_texel + offset[i];

            if (clampTexel(history_texel) != history_texel) continue;

            vec4 history_g = texelFetch(colortex20, history_texel, 0);

            float depth_delta = distance(sqr(history_g.w), current_distance)
                              - abs(camera_movement.z / far);
            bool depth_rejection = (depth_delta / max(current_distance, 1e-6)) < 0.1;

            if (depth_rejection) {
                previous_light += max0(texelFetch(colortex18, history_texel, 0)) * weight[i];
                previous_aux += history_g.xyz * weight[i];
                sum_weight += weight[i];
            }
        }

        if (sum_weight > 1e-3) {
            previous_light /= sum_weight;
            previous_aux /= sum_weight;

            // Accumulation alpha schedule.
            float frames = min(previous_light.a + 1.0, maxFrames);
            float alpha_color = max(0.01 * minAccumMult, 1.0 / frames);
            float alpha_variance = max(0.02 * minAccumMult, 1.0 / frames);

            // Adaptive rejection from the lightmap delta.
            float adapt_delta = sqr(
                max0(abs(lightmap - previous_aux.z) - (1.0 / 1024.0))
                    / (avgOf(vec2(lightmap, previous_aux.z)) + 5e-3)
            );

            float rejection = 1.0 / (1.0 + adapt_delta);
                rejection = clamp01(1.0 - rejection);
                rejection = clamp01(0.71 * rejection * ADAPT_STRENGTH);

            alpha_color = max(rejection, alpha_color);
            alpha_variance = max(rejection, alpha_variance);

            vec3 current_light = spatialColor(texel);

            float current_luma = getLuma(current_light);
            vec2 current_variance = vec2(current_luma, sqr(current_luma));
                variance_data = mix(previous_aux.xy, current_variance, alpha_variance);

            rt_light = mix(previous_light.rgb, current_light, alpha_color);
            variance = sqrt(max0(variance_data.y - sqr(variance_data.x)))
                     / max(variance_data.x, 1e-8);
                variance *= max(1.0 + rejection * sqrt(2.0), 4.0 / frames);
            samples = frames;

            lightmap = mix(previous_aux.z, lightmap, max(0.2, 1.0 / frames));
        } else {
            rt_light = spatialColor7x7(texel, variance_data, variance);
            samples = 1.0;
        }
    }

    // Merge the lightmap blocklight fallback into the accumulated color.
    // The .a weight comes from d4_sspt (pow5 lightmap * ao^2 *
    // ssptLightmapBlend).
    vec3 current = rt_light + raw_lightmap_weight * blocklight_color * rcp(tau);

    indirectCurrent = vec4(current, variance);
    indirectHistory = vec4(rt_light, samples);
    historyGData = vec4(
        clamp01(variance_data),
        lightmap,
        sqrt(current_distance)
    );
}
