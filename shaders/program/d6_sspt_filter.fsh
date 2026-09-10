/*
--------------------------------------------------------------------------------

  program/d6_sspt_filter:
  One a-trous SVGF filter iteration for the SSPT emission. Instantiated five
  times per frame with SVGF_SIZE = 32 / 16 / 8 / 4 / 2.
  Reads:

    colortex17  accumulated color (rgb) + sigma (a) — from d5, then from the
                previous filter iteration
    colortex19  filter gbuffer data (view normal + sqrt normalized depth)
    colortex18  history frames (pixel age)

  Writes colortex17 (denoised color + smoothed sigma).

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

// Iris/OptiFine only register a #define as a toggleable boolean GUI option if
// it's checked at least once in GLSL source via #ifdef/#ifndef/#if defined.
// SVGF_FILTER was previously only ever referenced in shaders.properties
// (program.*.enabled = SVGF_FILTER), which does NOT count for GUI detection,
// so the "Filtering" toggle on the SSPT Filter screen never rendered. This
// pass is already only compiled when SVGF_FILTER is defined, so the check
// below is a no-op at runtime but satisfies Iris' option scanner.
#ifdef SVGF_FILTER
#endif

#ifndef SVGF_SIZE
#define SVGF_SIZE 4
#endif

layout(location = 0) out vec4 filtered; // colortex17

/* RENDERTARGETS: 17 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex17; // sspt color + sigma
uniform sampler2D colortex18; // sspt history frames
uniform sampler2D colortex19; // sspt gbuffer data

uniform sampler2D depthtex1;  // geometry depth (non-DH path, via combined_depth_tex)

uniform vec2 view_res;

// ------------
//   Includes
// ------------

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"

// Half-res SSPT buffer bookkeeping (matches size.buffer.colortex17-20)
const float bufferScale = 0.5;

// Relative luminance in the pack's working color space (Rec. 2020).
float getLuma(vec3 c) {
    return dot(c, luminance_weights_rec2020);
}

vec2 bufferSize() {
    return view_res * bufferScale;
}

ivec2 clampTexel(ivec2 texel) {
    return clamp(texel, ivec2(0), ivec2(bufferSize()) - 1);
}

/* ------ ATROUS SVGF ------ */

vec4 fetchGbuffer(ivec2 texel) {
    vec4 val = texelFetch(colortex19, texel, 0);
    return vec4(val.rgb * 2.0 - 1.0, sqr(val.a));
}

// 3x3 gaussian-weighted sigma estimate over the
// color buffer's variance channel (.a)
const float gaussKernel[4] = float[4](
    1.0 / 4.0, 1.0 / 8.0,
    1.0 / 8.0, 1.0 / 16.0
);

float computeSigmaL(ivec2 texel, float center) {
    float sum = center * gaussKernel[0];

    const int r = 1;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            if (x != 0 || y != 0) {
                ivec2 tap = clampTexel(texel + ivec2(x, y));
                float variance = texelFetch(colortex17, tap, 0).a;
                float w = gaussKernel[abs(y) * 2 + abs(x)];
                sum += variance * w;
            }
        }
    }

    return sqrt(max(sum, 1e-8));
}

vec4 atrousSVGF(ivec2 texel, const int size) {
    vec4 center_data = fetchGbuffer(texel);

    vec4 center_color = texelFetch(colortex17, texel, 0);
    float center_luma = getLuma(center_color.rgb);

    // Pixel age drives how aggressively the filter converges.
    float frames = texelFetch(colortex18, texel, 0).a;

    float sigma_bias = (4.0 / max(frames, 1.0)) + 0.25;
    float max_delta = mix(half_pi, tau, clamp01(frames / 32.0));
    float offset = mix(0.04 / (0.5 * SVGF_RAD), 0.03, clamp01(frames / 32.0));
    float sigma_mul = mix(2.718281828459045, 0.41, clamp01(frames / 16.0));

    float sigma_dist_mul = 2.0 - (1.0 / (1.0 + center_data.a / 64.0));

    float sigma_l = 1.0 / (
        sigma_mul * SVGF_STRICTNESS * sigma_dist_mul
            * computeSigmaL(texel, center_color.a)
        + sigma_bias * sigma_dist_mul
    );

    float normal_exp = mix(2.0, 8.0, clamp01(frames / 8.0)) * SVGF_NORMALEXP;

    vec4 total = center_color;
    float total_weight = 1.0;

    const int r = SVGF_RAD;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            ivec2 p = texel + ivec2(x, y) * size;

            if (x == 0 && y == 0) continue;

            bool valid = all(greaterThanEqual(p, ivec2(0)))
                      && all(lessThan(p, ivec2(bufferSize())));

            if (!valid) continue;

            vec4 current_data = fetchGbuffer(p);

            vec4 current_color = texelFetch(colortex17, p, 0);
            float current_luma = getLuma(current_color.rgb);

            float w = 1.0;

            float dist_lum = abs(center_luma - current_luma);
                dist_lum = sqr(dist_lum) / max(center_luma, offset);
                dist_lum = clamp(dist_lum, 0.0, max_delta);

            float dist_depth = abs(center_data.a - current_data.a) * 4.0;

                w *= pow(max0(dot(center_data.xyz, current_data.xyz)), normal_exp);
                w *= exp(-dist_depth / sqrt(float(size)) - sqrt(dist_lum * sigma_l));

            // accumulate stuff
            total += current_color * w * vec4(1.0, 1.0, 1.0, w);

            total_weight += w;
        }
    }

    // compensate for total sampling weight
    total /= vec4(total_weight, total_weight, total_weight, sqr(total_weight));

    return total;
}

// ------------
//   Main
// ------------

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth < 1.0) {
        filtered = atrousSVGF(texel, SVGF_SIZE);
    } else {
        filtered = texelFetch(colortex17, texel, 0);
    }
}
