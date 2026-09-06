/*
--------------------------------------------------------------------------------

  program/d6_sspt_filter:
  One a-trous wavelet iteration over the accumulated SSPT radiance,
  following the SVGF schedule (Schied et al. 2017, "Spatiotemporal
  Variance-Guided Filtering"): wide, cheap hops first, narrow detail passes
  last. Instantiated five times per frame with SVGF_SIZE = 32 / 16 / 8 / 4 / 2.

  Edge stopping runs on the filter data (view normal, sqrt normalized
  depth) and on relative luminance, with the luminance tolerance driven by
  the local variance estimate and by how long the pixel has been
  accumulating (colortex18.a) — young pixels get a gentler filter while
  their statistics are still weak.

  Reads
    colortex17  accumulated radiance (rgb) + relative sigma (a)
    colortex18  history frames (a)
    colortex19  filter data: view normal, sqrt normalized depth

  Writes colortex17 with the filtered radiance and filtered sigma.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#ifndef SVGF_SIZE
#define SVGF_SIZE 4
#endif

layout(location = 0) out vec4 sspt_filtered; // colortex17

/* RENDERTARGETS: 17 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex17; // sspt color + sigma
uniform sampler2D colortex18; // sspt history frames
uniform sampler2D colortex19; // sspt filter data
uniform sampler2D depthtex1;  // combined_depth_tex when no LoD mod is active

uniform float far;

uniform vec2 view_res;

// ------------
//   Includes
// ------------

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"

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

// Filter data is stored as normal * 0.5 + 0.5 and sqrt(normalized depth);
// the alpha is squared to get linear normalized depth back.
vec4 sspt_filter_data(ivec2 texel) {
    vec4 value = texelFetch(colortex19, texel, 0);
    return vec4(value.rgb * 2.0 - 1.0, sqr(value.a));
}

// 3x3 binomial gaussian over the variance channel — a cheap estimate of
// how noisy this neighborhood currently is.
const float variance_kernel[4] = float[4](0.25, 0.125, 0.125, 0.0625);

// Binomial-weighted variance average around a texel, returned as a
// standard deviation. Seeded with the center's own variance so isolated
// pixels still produce a usable estimate.
float sspt_local_sigma(ivec2 texel, float center_variance) {
    float variance = center_variance * variance_kernel[0];

    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 tap_texel = clamp(
                texel + ivec2(x, y), ivec2(0), ivec2(sspt_buffer_size()) - 1
            );
            variance += texelFetch(colortex17, tap_texel, 0).a
                      * variance_kernel[abs(y) * 2 + abs(x)];
        }
    }

    return sqrt(max(variance, 1e-8));
}

// ------------
//   A-trous iteration
// ------------

// One à-trous wavelet iteration over the accumulated radiance, following
// the SVGF reconstruction schedule (Schied et al. 2017): taps hop
// step_size texels apart, wide hops first, narrow detail passes last.
// Each tap is weighted by three edge-stopping terms — normal agreement,
// depth similarity and luminance similarity — with the luminance
// tolerance driven by the local variance estimate and by how long the
// pixel has been accumulating: freshly reset pixels have weak statistics,
// so their filters lean on geometry until the moments settle.
vec4 sspt_atrous_iteration(ivec2 texel, const int step_size) {
    vec4 center_data = sspt_filter_data(texel);
    vec4 center_color = texelFetch(colortex17, texel, 0);
    float center_luminance = sspt_luminance(center_color.rgb);

    float pixel_age = texelFetch(colortex18, texel, 0).a;

    // Exponential trust curves over the pixel's accumulation age, with
    // three time constants so luminance, variance and normal behaviour
    // each relax at their own pace.
    float trust_luma   = 1.0 - exp(-pixel_age * 0.05);
    float trust_sigma  = 1.0 - exp(-pixel_age * 0.10);
    float trust_normal = 1.0 - exp(-pixel_age * 0.20);

    // Relative-luminance floor: dark pixels must not produce enormous
    // relative differences out of tiny absolute noise.
    float luminance_floor = mix(0.12, 0.02, trust_luma);
    // Variance multiplier: young pixels discount their own (unreliable)
    // variance estimate, mature pixels lean on it.
    float variance_scale = mix(3.0, 0.5, trust_sigma);
    float normal_power = (2.0 + 4.0 * trust_normal) * SVGF_NORMALEXP;

    // Depth tolerance grows linearly with distance: the same normalized
    // depth error is many world units far away and almost none up close.
    float depth_tolerance = 1.0 + 2.0 * center_data.w;

    // Inverse luminance sigma. The additive prior keeps the filter alive
    // on young pixels whose variance has not settled yet.
    float luma_confidence = rcp(
        variance_scale * SVGF_STRICTNESS * depth_tolerance
            * sspt_local_sigma(texel, center_color.a)
        + (2.0 * exp(-0.05 * pixel_age) + 0.2) * depth_tolerance
    );

    vec4 filtered = center_color;
    float weight_sum = 1.0;

    const int radius = SVGF_RAD;
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x == 0 && y == 0) continue;

            ivec2 tap_texel = texel + ivec2(x, y) * step_size;

            if (any(lessThan(tap_texel, ivec2(0)))) continue;
            if (any(greaterThanEqual(tap_texel, ivec2(sspt_buffer_size())))) continue;

            vec4 tap_data = sspt_filter_data(tap_texel);
            vec4 tap_color = texelFetch(colortex17, tap_texel, 0);
            float tap_luminance = sspt_luminance(tap_color.rgb);

            // Coarse passes cover more ground per hop, so they tolerate
            // proportionally larger depth gaps.
            float depth_term = exp(
                -abs(center_data.w - tap_data.w)
                    * rcp(0.5 * sqrt(float(step_size)))
            );

            float luma_ratio = abs(tap_luminance - center_luminance)
                             * rcp(max(center_luminance, luminance_floor));
            float luma_term = exp(-luma_ratio * luma_confidence);

            float weight = pow(max0(dot(center_data.xyz, tap_data.xyz)), normal_power)
                         * depth_term
                         * luma_term;

            // The sigma channel rides along with squared weights so it
            // stays a variance after normalization (Schied et al. 2017).
            filtered += tap_color * weight * vec4(1.0, 1.0, 1.0, weight);
            weight_sum += weight;
        }
    }

    return filtered / vec4(weight_sum, weight_sum, weight_sum, sqr(weight_sum));
}

// ------------
//   Main
// ------------

// One filtered output texel: an à-trous iteration where the SSPT chain is
// active, the untouched input everywhere else (sky pixels, or the whole
// buffer when the filter is disabled via shaders.properties).
void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth < 1.0) {
#ifdef SVGF_FILTER
        sspt_filtered = sspt_atrous_iteration(texel, SVGF_SIZE);
#else
        // Filtering disabled: forward the accumulated result untouched.
        // (shaders.properties skips these passes via
        // program.*deferred6-10.enabled = SVGF_FILTER; this path only
        // exists as a safety net.)
        sspt_filtered = texelFetch(colortex17, texel, 0);
#endif
    } else {
        sspt_filtered = texelFetch(colortex17, texel, 0);
    }
}
