/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#include "/lib/global.glsl"

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
uniform sampler2D colortex6;  // selected shader AO (SSAO/GTAO/none)
uniform sampler2D colortex14; // AO history depth for depth-aware AO upscale
uniform sampler2D colortex17; // sspt raw color + geometry-hit flag
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

#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL

// Shared bookkeeping for the SSPT temporal passes (d5 accumulate + SVGF
// filter): target-sized buffer helpers and the packed-gbuffer fetch.

#include "/lib/util/color.glsl"

// SSPT buffer bookkeeping uses the actual allocated target size for every reduction setting.

// Relative luminance in the pack's working color space (Rec. 2020).
float getLuma(vec3 c) {
    return dot(c, luminance_weights);
}

vec2 bufferSize() {
    return vec2(textureSize(colortex17, 0));
}

ivec2 clampTexel(ivec2 texel) {
    return clamp(texel, ivec2(0), ivec2(bufferSize()) - 1);
}

vec4 fetchGbuffer(ivec2 texel) {
    vec4 val = texelFetch(colortex19, texel, 0);
    return vec4(val.rgb * 2.0 - 1.0, sqr(val.a));
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_TEMPORAL
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

// Mean of two values.
float avgOf(vec2 v) {
    return (v.x + v.y) * 0.5;
}

// Depth-aware 2x2 upscale of the quarter-res AO buffer for the lightmap
// fallback finishing. Mirrors the shading-pass bilateral resolve (10.0 depth
// scale) so DSSAO and DGTAO finish without bleeding across discontinuities
// at any indirectResReduction. Returns 1.0 for hands and shaderAoNone.
float fetch_fallback_ao(vec2 uv, float lin_z, bool is_hand) {
    if (is_hand) {
        return 1.0;
    }
#if shaderAo == shaderAoNone
    return 1.0;
#else
    vec2 ao_size = vec2(textureSize(colortex6, 0));
    vec2 ao_pos = uv * ao_size - 0.5;
    ivec2 base = ivec2(floor(ao_pos));
    vec2 f = fract(ao_pos);

    vec4 ao_taps;
    vec4 ao_depths;
    ao_taps.x = texelFetch(colortex6, clamp(base, ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_taps.y = texelFetch(colortex6, clamp(base + ivec2(1, 0), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_taps.z = texelFetch(colortex6, clamp(base + ivec2(0, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_taps.w = texelFetch(colortex6, clamp(base + ivec2(1, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;

    ao_depths.x = texelFetch(colortex14, clamp(base, ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_depths.y = texelFetch(colortex14, clamp(base + ivec2(1, 0), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_depths.z = texelFetch(colortex14, clamp(base + ivec2(0, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_depths.w = texelFetch(colortex14, clamp(base + ivec2(1, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;

    vec4 w;
    w.x = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.x) - lin_z));
    w.y = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.y) - lin_z));
    w.z = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.z) - lin_z));
    w.w = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.w) - lin_z));

    w.x *= (1.0 - f.x) * (1.0 - f.y);
    w.y *= f.x * (1.0 - f.y);
    w.z *= (1.0 - f.x) * f.y;
    w.w *= f.x * f.y;

    float w_sum = w.x + w.y + w.z + w.w;
    if (w_sum <= 1e-6) {
        return clamp01(dot(ao_taps, vec4(0.25)));
    }
    return clamp01(dot(ao_taps, w) / w_sum);
#endif
}

/* ------ REPROJECTION ------ */

vec3 reprojectHistory(vec3 scene_space) {
    vec3 prev_pos = scene_space + (cameraPosition - previousCameraPosition);
    prev_pos = transform(gbufferPreviousModelView, prev_pos);
    prev_pos = project_and_divide(gbufferPreviousProjection, prev_pos);
    return prev_pos * 0.5 + 0.5;
}

/* ------ EDGE-AWARE SPATIAL FILTERS ------ */

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

    // Depth-aware finishing for the fallback: same scalar visibility as the
    // trace pass for both DSSAO and DGTAO, hands excluded.
    float lin_z = screen_to_view_space_depth(
        combined_projection_matrix_inverse,
        depth
    );
    bool is_hand = depth < hand_depth;
    float ao = fetch_fallback_ao(uv, lin_z, is_hand);

    vec3 rt_light = vec3(0.0);
    float samples = 0.0;
    float variance = 0.0;
    vec2 variance_data = vec2(0.0);


    // The trace pass finishes bounced radiance with AO while preserving
    // emission. Apply AO here only to the lightmap fallback when the ray
    // paths miss all geometry. With shaderAoNone, ao is 1.0 by construction.
    float sspt_geometry_hit = texelFetch(colortex17, texel, 0).a;
    float miss_ao = mix(ao, 1.0, sspt_geometry_hit);
    float raw_lightmap_weight = lightmap * sqr(miss_ao) * ssptLightmapBlend;

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
            float alpha_color = max(0.01 * 1.0, 1.0 / frames);
            float alpha_variance = max(0.02 * 1.0, 1.0 / frames);

            // Adaptive rejection from the lightmap delta.
            float adapt_delta = sqr(
                max0(abs(lightmap - previous_aux.z) - (1.0 / 1024.0))
                    / (avgOf(vec2(lightmap, previous_aux.z)) + 5e-3)
            );

            float rejection = 1.0 / (1.0 + adapt_delta);
                rejection = clamp01(1.0 - rejection);
                rejection = clamp01(0.71 * rejection * 1.0);

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

    // Merge the blocklight fallback after AO-finished traced contributions.
    vec3 current = rt_light + raw_lightmap_weight * blocklight_color * rcp(tau);

    indirectCurrent = vec4(current, variance);
    indirectHistory = vec4(rt_light, samples);
    historyGData = vec4(
        clamp01(variance_data),
        lightmap,
        sqrt(current_distance)
    );
}
