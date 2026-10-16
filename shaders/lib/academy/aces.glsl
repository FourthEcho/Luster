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

#if !defined INCLUDE_ACES_ACES
#define INCLUDE_ACES_ACES

/*
 * Implemented following the reference implementation given by the Academy at
 * https://github.com/ampas/aces-dev (revision 1.3)
 */

#include "/lib/academy/matrices.glsl"
#include "/lib/academy/utility.glsl"


struct SegmentedSplineParamsC5 {
    float slope_low; // log-log slope of low linear extension
    float slope_high; // log-log slope of high linear extension
    vec2 log_min_point; // {log luminance, log luminance} linear extension below
                        // this
    vec2 log_mid_point; // {log luminance, log luminance}
    vec2 log_max_point; // {log luminance, log luminance} linear extension above
                        // this
    float[6] coeff_low; // Coefficients for B-spline between mid point and max
                        // point (units of log luminance)
    float[6] coeff_high; // Coefficients for B-spline between min point and mid
                         // point (units of log luminance)
};

struct SegmentedSplineParamsC9 {
    float slope_low; // log-log slope of low linear extension
    float slope_high; // log-log slope of high linear extension
    vec2 log_min_point; // {log luminance, log luminance} linear extension below
                        // this
    vec2 log_mid_point; // {log luminance, log luminance}
    vec2 log_max_point; // {log luminance, log luminance} linear extension above
                        // this
    float[10] coeff_low; // Coefficients for B-spline between mid point and max
                         // point (units of log luminance)
    float[10] coeff_high; // Coefficients for B-spline between min point and mid
                          // point (units of log luminance)
};

// Textbook monomial to basis-function conversion matrix
const mat3 M = mat3(0.5, -1.0, 0.5, -1.0, 1.0, 0.5, 0.5, 0.0, 0.0);

float segmented_spline_c5_fwd(float x) {
    // RRT parameters
    const SegmentedSplineParamsC5 params = SegmentedSplineParamsC5(
        0.0, // slope_low
        0.0, // slope_high
        log(vec2(0.18 * exp2(-15.0), 0.0001)) * rcp(log(10.0)), // log_min_point
        log(vec2(0.18, 4.8)) * rcp(log(10.0)), // log_mid_point
        log(vec2(0.18 * exp2(18.0), 1000.0)) * rcp(log(10.0)), // log_max_point
        // coeff_low
        float[6](
            -4.0000000000,
            -4.0000000000,
            -3.1573765773,
            -0.4852499958,
            1.8477324706,
            1.8477324706
        ),
        // coeff_high
        float[6](
            -0.7185482425,
            2.0810307172,
            3.6681241237,
            4.0000000000,
            4.0000000000,
            4.0000000000
        )
    );

    // Check for negatives or zero before taking the log. If negative or zero,
    // set to 1e-6
    float log_x = log10(max(x, eps));
    float log_y;

    if (log_x <= params.log_min_point.x) {
        log_y = log_x * params.slope_low
            + (params.log_min_point.y
               - params.slope_low * params.log_min_point.x);
    } else if (
        log_x > params.log_min_point.x && log_x < params.log_mid_point.x
    ) {
        float knot_coord = 3.0 * (log_x - params.log_min_point.x)
            / (params.log_mid_point.x - params.log_min_point.x);
        uint i = uint(knot_coord);
        float f = fract(knot_coord);

        vec3 cf = vec3(
            params.coeff_low[i],
            params.coeff_low[i + 1],
            params.coeff_low[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        log_y = dot(monomials, M * cf);
    } else if (
        log_x >= params.log_mid_point.x && log_x <= params.log_max_point.x
    ) {
        float knot_coord = 3.0 * (log_x - params.log_mid_point.x)
            / (params.log_max_point.x - params.log_mid_point.x);
        uint i = uint(knot_coord);
        float f = fract(knot_coord);

        vec3 cf = vec3(
            params.coeff_high[i],
            params.coeff_high[i + 1],
            params.coeff_high[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        log_y = dot(monomials, M * cf);
    } else {
        log_y = log_x * params.slope_high
            + (params.log_max_point.y
               - params.slope_high * params.log_max_point.x);
    }

    return pow(10.0, log_y);
}

float segmented_spline_c9_fwd(float x) {
    // 48nit ODT parameters
    const SegmentedSplineParamsC9 params = SegmentedSplineParamsC9(
        0.0, // slope_low
        0.04, // slope_high
        // ODT min/max/mid points precomputed using a small C++ program
        // This avoids 3 unnecessary SegmentedSplineC5 calls per fragment
        vec2(-2.5406231880, -1.6989699602),
        vec2(0.6812411547, 0.6812412143),
        vec2(3.0024764538, 1.6812412739),
        // coeff_low
        float[10](
            -1.6989700043,
            -1.6989700043,
            -1.4779000000,
            -1.2291000000,
            -0.8648000000,
            -0.4480000000,
            0.0051800000,
            0.4511080334,
            0.9113744414,
            0.9113744414
        ),
        // coeff_high
        float[10](
            0.5154386965,
            0.8470437783,
            1.1358000000,
            1.3802000000,
            1.5197000000,
            1.5985000000,
            1.6467000000,
            1.6746091357,
            1.6878733390,
            1.6878733390
        )
    );

    // Check for negatives or zero before taking the log. If negative or zero,
    // set to 1e-6
    float log_x = log10(max(x, eps));
    float log_y;

    if (log_x <= params.log_min_point.x) {
        log_y = log_x * params.slope_low
            + (params.log_min_point.y
               - params.slope_low * params.log_min_point.x);
    } else if (
        (log_x > params.log_min_point.x) && (log_x < params.log_mid_point.x)
    ) {
        float knot_coord = 7.0 * (log_x - params.log_min_point.x)
            / (params.log_mid_point.x - params.log_min_point.x);
        uint i = uint(knot_coord);
        float f = fract(knot_coord);

        vec3 cf = vec3(
            params.coeff_low[i],
            params.coeff_low[i + 1],
            params.coeff_low[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        log_y = dot(monomials, M * cf);
    } else if (
        (log_x >= params.log_mid_point.x) && (log_x <= params.log_max_point.x)
    ) {
        float knot_coord = 7.0 * (log_x - params.log_mid_point.x)
            / (params.log_max_point.x - params.log_mid_point.x);
        uint i = uint(knot_coord);
        float f = fract(knot_coord);

        vec3 cf = vec3(
            params.coeff_high[i],
            params.coeff_high[i + 1],
            params.coeff_high[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        log_y = dot(monomials, M * cf);
    } else {
        log_y = log_x * params.slope_high
            + (params.log_max_point.y
               - params.slope_high * params.log_max_point.x);
    }

    return pow(10.0, log_y);
}

// Constants (RRT fine controls come from ACADEMY_RRT_* in "/settings.glsl";
// each default reproduces the value below it)

const float rrt_glow_gain = academyRrtGlow; // default: 0.10 (ref: 0.05)
const float rrt_glow_mid = 0.08; // default: 0.08

const float rrt_red_scale = 1.0; // default: 0.82
const float rrt_red_pivot = 0.03; // default: 0.03
const float rrt_red_hue = 0.0; // default: 0.0
const float rrt_red_width = 135.0; // default: 135.0

const float rrt_sat_factor = academyRrtSat; // default: 0.96
const float odt_sat_factor = academyOdtSat; // default: 1.00 (ref: 0.93)

const float rrt_gamma_curve = 0.96 * academyRrtGamma; // default gain: 1.00

const float cinema_white = 48.0; // default: 48.0
const float cinema_black = 0.02; // default: 10^log_10(0.02)

// "Glow module" functions

float glow_fwd(float yc_in, float glow_gain_in, const float glow_mid) {
    float glow_gain_out;

    if (yc_in <= 2.0 / 3.0 * glow_mid) {
        glow_gain_out = glow_gain_in;
    } else if (yc_in >= 2.0 * glow_mid) {
        glow_gain_out = 0.0;
    } else {
        glow_gain_out = glow_gain_in * (glow_mid / yc_in - 0.5);
    }

    return glow_gain_out;
}

// Sigmoid function in the range 0 to 1 spanning -2 to +2
float sigmoid_shaper(float x) {
    float t = max0(1.0 - abs(0.5 * x));
    float y = 1.0 + sign(x) * (1.0 - t * t);

    return float(0.5) * y;
}

// "Red modifier" functions

float cubic_basis_shaper_fit(float x, const float width) {
    float radius = 0.5 * width;
    return abs(x) < radius ? sqr(cubic_smooth(1.0 - abs(x) / radius)) : 0.0;
}

float center_hue(float hue, float center_h) {
    float hue_centered = hue - center_h;

    if (hue_centered < -180.0) {
        return hue_centered + 360.0;
    } else if (hue_centered > 180.0) {
        return hue_centered - 360.0;
    } else {
        return hue_centered;
    }
}

vec3 rrt_sweeteners(vec3 aces) {
    // Glow module
    float saturation = rgb_to_saturation(aces);
    float yc_in = rgb_to_yc(aces);
    float s = sigmoid_shaper(5.0 * saturation - 2.0);
    float added_glow = 1.0 + glow_fwd(yc_in, rrt_glow_gain * s, rrt_glow_mid);

    aces *= added_glow;

    // Red modifier
    float hue = rgb_to_hue(aces);
    float centered_hue = center_hue(hue, rrt_red_hue);
    float hue_weight = cubic_basis_shaper_fit(centered_hue, rrt_red_width);

    aces.r = aces.r
        + hue_weight * saturation * (rrt_red_pivot - aces.r)
            * (1.0 - rrt_red_scale * 1.00);

    // ACES to RGB rendering space
    vec3 rgb_pre = max0(aces) * ap0_to_ap1;

    // Global desaturation
    float luminance = dot(rgb_pre, luminance_weights_ap1);
    rgb_pre = mix(vec3(luminance), rgb_pre, rrt_sat_factor);

    // Added gamma adjustment before the RRT
    rgb_pre = pow(rgb_pre, vec3(rrt_gamma_curve));

    return rgb_pre;
}

/*
 * Reference Rendering Transform (RRT)
 *
 * Modifications:
 * Changed input and output color space to ACEScg to avoid 2 unnecessary mat3
 * transformations
 */
vec3 aces_rrt(vec3 aces) {
    // Apply RRT sweeteners
    vec3 rgb_pre = rrt_sweeteners(aces);

    // Apply the tonescale independently in rendering-space RGB
    vec3 rgb_post;
    rgb_post.r = segmented_spline_c5_fwd(rgb_pre.r);
    rgb_post.g = segmented_spline_c5_fwd(rgb_pre.g);
    rgb_post.b = segmented_spline_c5_fwd(rgb_pre.b);

    return rgb_post;
}

// Gamma adjustment to compensate for dim surround
vec3 dark_surround_to_dim_surround(vec3 linear_c_v) {
    const float dim_surround_gamma = 0.9811; // default: 0.9811

    vec3 XYZ = linear_c_v * ap1_to_xyz;
    vec3 xy_y = XYZ_to_xy_y(XYZ);

    xy_y.z = max0(xy_y.z);
    xy_y.z = pow(xy_y.z, dim_surround_gamma);

    return xy_y_to_XYZ(xy_y) * xyz_to_ap1;
}

/*
 * Output Device Transform - Rec709
 *
 * Summary:
 * This transform is intended for mapping OCES onto a Rec.709 broadcast monitor
 * that is calibrated to a D65 white point at 100 cd/m^2. The assumed observer
 * adapted white is D65, and the viewing environment is a dim surround.
 *
 * Modifications:
 * Changed input and output color spaces to ACEScg to avoid 3 unnecessary mat3
 * transformations The s_r_g_b transfer function is applied later in the
 * pipeline
 */
vec3 aces_odt(vec3 rgb_pre) {
    // Apply the tonescale independently in rendering-space RGB
    vec3 rgb_post;
    rgb_post.r = segmented_spline_c9_fwd(rgb_pre.r);
    rgb_post.g = segmented_spline_c9_fwd(rgb_pre.g);
    rgb_post.b = segmented_spline_c9_fwd(rgb_pre.b);

    // Scale luminance to linear code value
    vec3 linear_c_v = y_to_lin_c_v(rgb_post, cinema_white, cinema_black);

    // Apply gamma adjustment to compensate for dim surround
    linear_c_v = dark_surround_to_dim_surround(linear_c_v);

    // Apply desaturation to compensate for luminance difference
    float luminance = dot(linear_c_v, luminance_weights_ap1);
    linear_c_v = mix(vec3(luminance), linear_c_v, odt_sat_factor);

    return linear_c_v;
}

/*
 * RRT + ODT fit by Stephen Hill
 * https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
 */
vec3 rrt_and_odt_fit(vec3 rgb) {
    vec3 a = rgb * (rgb + 0.0245786) - 0.000090537;
    vec3 b = rgb * (0.983729 * rgb + 0.4329510) + 0.238081;

    return a / b;
}


// Luster Academy Color controls. These are only reached by ACES tonemap operators.
vec3 academy_color_controls(vec3 color) {
    color *= exp2(0.0);

    // Stable contrast around middle grey in the post-ODT linear domain.
    const float pivot = 0.18;
    color = exp2((log2(max(color, vec3(1e-6))) - log2(pivot))
        * 1.00 + log2(pivot));

    // Saturation + optional colorfulness shaping (post-ODT working space).
    float luma = dot(color, luminance_weights);
    float sat = max(1.00 + 0.00 * (1.0 - clamp(luma, 0.0, 1.0)), 0.0);
    color = mix(vec3(luma), color, sat);

    // Soft highlight compression. Neutral at zero.
    float highlight = smoothstep(0.45, 1.0, clamp(luma, 0.0, 1.0));
    float roll = max(0.00, 0.0) * highlight;
    color /= 1.0 + roll * max(color - vec3(pivot), vec3(0.0));

    // Controlled toe lift, preserving the neutral result at zero.
    float shadowVis = 1.0 - smoothstep(0.0, 0.24, clamp(luma, 0.0, 1.0));
    float toe = max(0.00, 0.0) * shadowVis;
    color += toe * vec3(0.045) * (1.0 - color);

    return clamp(color, vec3(0.0), vec3(1.0));
}

#endif // INCLUDE_ACES_ACES
