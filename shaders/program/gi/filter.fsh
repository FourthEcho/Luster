#if !defined INCLUDE_PROGRAM_GI_FILTER
#define INCLUDE_PROGRAM_GI_FILTER

// ============================================================================
//  A-Trous SVGF filter — edge-stopping cross-bilateral filter that
//  denoises the accumulated GI. Each pass widens the kernel footprint
//  (SVGF_SIZE = 8, 4, 2 by default) so 3 passes cover an effective
//  17-pixel neighborhood at quarter res.
//
//  Reads:
//    colortex18 — accumulated radiance + pixel age (alpha)
//    colortex1  — gbuffer normals (for the normal edge weight)
//    colortex2  — gbuffer depth (for the depth edge weight)
//    colortex19 — variance + mean luma (for the luma edge weight)
//
//  Writes:
//    colortex18 — filtered radiance (alpha preserved)
// ============================================================================

#include "/include/global.glsl"

// ----------------------------------------------------------------------------
//   Uniforms — MUST be before shared.glsl (which brings space_conversion
//   that references them at global scope).
// ----------------------------------------------------------------------------

#ifndef SVGF_SIZE
#define SVGF_SIZE 4
#endif

uniform sampler2D colortex1;  // gbuffer 0 (normals)
uniform sampler2D colortex2;  // gbuffer 1 (linear depth packed)
uniform sampler2D colortex18; // accumulated radiance + pixel age
uniform sampler2D colortex19; // variance + mean luma

uniform sampler2D depthtex1; // fallback combined_depth_tex when no LoD mod

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;
uniform int frameCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#include "/program/gi/shared.glsl"

layout(location = 0) out vec4 filtered_out;

/* RENDERTARGETS: 18 */

in vec2 uv;

// Decode a packed normal from colortex1 (octahedral in .z, .w via pack2x8).
vec3 filter_read_normal(ivec2 texel) {
    vec4 g = texelFetch(colortex1, texel, 0);
    vec2 packed = unpack_unorm_2x8(g.z);
    return decode_unit_vector(packed);
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 full_texel = gi_full_res_texel();

    vec4 center = texelFetch(colortex18, texel, 0);
    if (center.a <= 0.0) {
        // Sky / hand pixel — pass through untouched.
        filtered_out = center;
        return;
    }

    vec3 center_normal = filter_read_normal(full_texel);
    float center_depth = gi_read_depth(full_texel);
    float center_luma = dot(center.rgb, luminance_weights);

    vec2 moments = texelFetch(colortex19, texel, 0).xy;
    float center_variance = moments.x;
    float center_mean = moments.y;

    // Sigma for the luma weight, derived from local variance and pixel
    // age — older pixels have lower variance and are weighted more
    // aggressively toward their (converged) center value.
    float age = max(center.a, 1.0);
    float sigma_l = 1.0 / (A_SVGF_STRICTNESS
                           * (1.0 / (1.0 + center_variance * 8.0))
                           * max(center_mean, 0.05)
                           + 0.25);
    float max_delta = mix(half_pi, tau, clamp01(age / 32.0));
    // A_SVGF_PASSES scales per-pass filter aggressiveness to compensate
    // for pass counts beyond the 3 program slots we actually run. Default
    // 3 maps to 1.0x (no extra strength). Higher values (4-5) push the
    // normal exponent up so each pass rejects more aggressively, giving
    // an effective "more passes" feel within the existing pipeline.
    float svgf_pass_strength = clamp(A_SVGF_PASSES / 3.0, 0.5, 2.0);
    float normal_exp = mix(2.0, 8.0, clamp01(age / 8.0)) * svgf_pass_strength;

    // A_SVGF_RADIUS scales the kernel stride. Default 4 maps to 1.0x
    // (preserves original SVGF_SIZE behaviour); higher values produce a
    // wider effective filter footprint per pass.
    float svgf_radius_scale = float(A_SVGF_RADIUS) / 4.0;

    vec3 total = center.rgb;
    float total_weight = 1.0;

    // 5x5 A-Trous kernel — the SVGF_SIZE stride makes the effective radius
    // grow with each pass. We skip the four corners to keep the tap count
    // at 21 instead of 25, which is a meaningful perf win on Apple GPUs.
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            if (x == 0 && y == 0) continue;
            if (abs(x) == 2 && abs(y) == 2) continue;  // skip corners

            ivec2 p = texel + ivec2(vec2(x, y) * float(SVGF_SIZE) * svgf_radius_scale);
            if (p.x < 0 || p.y < 0
                || p.x >= int(view_res.x * 0.5)
                || p.y >= int(view_res.y * 0.5)) continue;

            vec4 neighbor = texelFetch(colortex18, p, 0);
            if (neighbor.a <= 0.0) continue;  // sky/hand tap

            ivec2 p_full = ivec2(p * (taau_render_scale / gi_render_scale));
            if (p_full.x < 0 || p_full.y < 0
                || p_full.x >= int(view_res.x)
                || p_full.y >= int(view_res.y)) continue;

            vec3 n_normal = filter_read_normal(p_full);
            float n_depth = texelFetch(combined_depth_tex, p_full, 0).x;
            float n_luma = dot(neighbor.rgb, luminance_weights);

            // Normal weight — surfaces facing different directions should
            // not share GI; e.g. a wall facing left shouldn't bleed its
            // bounce into the floor.
            float w_n = pow(max0(dot(center_normal, n_normal)), normal_exp);

            // Depth weight — exponential falloff so depth discontinuities
            // (silhouette edges) get rejected cleanly.
            float depth_diff = abs(center_depth - n_depth);
            float w_d = exp(-depth_diff * 64.0);

            // Luma weight — reject taps whose radiance is far from the
            // center's. This is the actual "SVGF" part: it removes
            // fireflies and high-frequency noise without blurring real
            // lighting boundaries.
            float luma_diff = abs(center_luma - n_luma);
            luma_diff = sqr(luma_diff) / max(center_luma, 0.05);
            luma_diff = clamp(luma_diff, 0.0, max_delta);
            float w_l = exp(-sqrt(luma_diff) * sigma_l);

            float w = w_n * w_d * w_l;
            if (w <= 1e-4) continue;

            total += neighbor.rgb * w;
            total_weight += w;
        }
    }

    filtered_out = vec4(total / max(total_weight, eps), center.a);
}

#endif // INCLUDE_PROGRAM_GI_FILTER
