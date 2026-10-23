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
#include "/lib/academy/util.glsl"


struct SegmentedSplineParamsC5 {
    float slopeLow; // log-log slope of low linear extension
    float slopeHigh; // log-log slope of high linear extension
    vec2 logMinPoint; // {log luminance, log luminance} linear extension below
                        // this
    vec2 logMidPoint; // {log luminance, log luminance}
    vec2 logMaxPoint; // {log luminance, log luminance} linear extension above
                        // this
    float[6] coeffLow; // Coefficients for B-spline between mid point and max
                        // point (units of log luminance)
    float[6] coeffHigh; // Coefficients for B-spline between min point and mid
                         // point (units of log luminance)
};

struct SegmentedSplineParamsC9 {
    float slopeLow; // log-log slope of low linear extension
    float slopeHigh; // log-log slope of high linear extension
    vec2 logMinPoint; // {log luminance, log luminance} linear extension below
                        // this
    vec2 logMidPoint; // {log luminance, log luminance}
    vec2 logMaxPoint; // {log luminance, log luminance} linear extension above
                        // this
    float[10] coeffLow; // Coefficients for B-spline between mid point and max
                         // point (units of log luminance)
    float[10] coeffHigh; // Coefficients for B-spline between min point and mid
                          // point (units of log luminance)
};

// Textbook monomial to basis-function conversion matrix
const mat3 M = mat3(0.5, -1.0, 0.5, -1.0, 1.0, 0.5, 0.5, 0.0, 0.0);

float segmentedSplineC5Fwd(float x) {
    // RRT parameters
    const SegmentedSplineParamsC5 params = SegmentedSplineParamsC5(
        0.0, // slopeLow
        0.0, // slopeHigh
        log(vec2(0.18 * exp2(-15.0), 0.0001)) * rcp(log(10.0)), // logMinPoint
        log(vec2(0.18, 4.8)) * rcp(log(10.0)), // logMidPoint
        log(vec2(0.18 * exp2(18.0), 1000.0)) * rcp(log(10.0)), // logMaxPoint
        // coeffLow
        float[6](
            -4.0000000000,
            -4.0000000000,
            -3.1573765773,
            -0.4852499958,
            1.8477324706,
            1.8477324706
        ),
        // coeffHigh
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
    float logX = log10(max(x, eps));
    float logY;

    if (logX <= params.logMinPoint.x) {
        logY = logX * params.slopeLow
            + (params.logMinPoint.y
               - params.slopeLow * params.logMinPoint.x);
    } else if (
        logX > params.logMinPoint.x && logX < params.logMidPoint.x
    ) {
        float knotCoord = 3.0 * (logX - params.logMinPoint.x)
            / (params.logMidPoint.x - params.logMinPoint.x);
        uint i = uint(knotCoord);
        float f = fract(knotCoord);

        vec3 cf = vec3(
            params.coeffLow[i],
            params.coeffLow[i + 1],
            params.coeffLow[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        logY = dot(monomials, M * cf);
    } else if (
        logX >= params.logMidPoint.x && logX <= params.logMaxPoint.x
    ) {
        float knotCoord = 3.0 * (logX - params.logMidPoint.x)
            / (params.logMaxPoint.x - params.logMidPoint.x);
        uint i = uint(knotCoord);
        float f = fract(knotCoord);

        vec3 cf = vec3(
            params.coeffHigh[i],
            params.coeffHigh[i + 1],
            params.coeffHigh[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        logY = dot(monomials, M * cf);
    } else {
        logY = logX * params.slopeHigh
            + (params.logMaxPoint.y
               - params.slopeHigh * params.logMaxPoint.x);
    }

    return pow(10.0, logY);
}

float segmentedSplineC9Fwd(float x) {
    // 48nit ODT parameters
    const SegmentedSplineParamsC9 params = SegmentedSplineParamsC9(
        0.0, // slopeLow
        0.04, // slopeHigh
        // ODT min/max/mid points precomputed using a small C++ program
        // This avoids 3 unnecessary SegmentedSplineC5 calls per fragment
        vec2(-2.5406231880, -1.6989699602),
        vec2(0.6812411547, 0.6812412143),
        vec2(3.0024764538, 1.6812412739),
        // coeffLow
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
        // coeffHigh
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
    float logX = log10(max(x, eps));
    float logY;

    if (logX <= params.logMinPoint.x) {
        logY = logX * params.slopeLow
            + (params.logMinPoint.y
               - params.slopeLow * params.logMinPoint.x);
    } else if (
        (logX > params.logMinPoint.x) && (logX < params.logMidPoint.x)
    ) {
        float knotCoord = 7.0 * (logX - params.logMinPoint.x)
            / (params.logMidPoint.x - params.logMinPoint.x);
        uint i = uint(knotCoord);
        float f = fract(knotCoord);

        vec3 cf = vec3(
            params.coeffLow[i],
            params.coeffLow[i + 1],
            params.coeffLow[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        logY = dot(monomials, M * cf);
    } else if (
        (logX >= params.logMidPoint.x) && (logX <= params.logMaxPoint.x)
    ) {
        float knotCoord = 7.0 * (logX - params.logMidPoint.x)
            / (params.logMaxPoint.x - params.logMidPoint.x);
        uint i = uint(knotCoord);
        float f = fract(knotCoord);

        vec3 cf = vec3(
            params.coeffHigh[i],
            params.coeffHigh[i + 1],
            params.coeffHigh[i + 2]
        );

        vec3 monomials = vec3(f * f, f, 1.0);

        logY = dot(monomials, M * cf);
    } else {
        logY = logX * params.slopeHigh
            + (params.logMaxPoint.y
               - params.slopeHigh * params.logMaxPoint.x);
    }

    return pow(10.0, logY);
}

// Constants (RRT fine controls come from ACADEMY_RRT_* in "/settings.glsl";
// each default reproduces the value below it)

const float rrtGlowGain = academyRrtGlow; // default: 0.10 (ref: 0.05)
const float rrtGlowMid = 0.08; // default: 0.08

const float rrtRedScale = 1.0; // default: 0.82
const float rrtRedPivot = 0.03; // default: 0.03
const float rrtRedHue = 0.0; // default: 0.0
const float rrtRedWidth = 135.0; // default: 135.0

const float rrtSatFactor = academyRrtSat; // default: 0.96
const float odtSatFactor = academyOdtSat; // default: 1.00 (ref: 0.93)

const float rrtGammaCurve = 0.96 * academyRrtGamma; // default gain: 1.00

const float cinemaWhite = 48.0; // default: 48.0
const float cinemaBlack = 0.02; // default: 10^log10(0.02)

// "Glow module" functions

float glowFwd(float ycIn, float glowGainIn, const float glowMid) {
    float glowGainOut;

    if (ycIn <= 2.0 / 3.0 * glowMid) {
        glowGainOut = glowGainIn;
    } else if (ycIn >= 2.0 * glowMid) {
        glowGainOut = 0.0;
    } else {
        glowGainOut = glowGainIn * (glowMid / ycIn - 0.5);
    }

    return glowGainOut;
}

// Sigmoid function in the range 0 to 1 spanning -2 to +2
float sigmoidShaper(float x) {
    float t = max0(1.0 - abs(0.5 * x));
    float y = 1.0 + sign(x) * (1.0 - t * t);

    return float(0.5) * y;
}

// "Red modifier" functions

float cubicBasisShaperFit(float x, const float width) {
    float radius = 0.5 * width;
    return abs(x) < radius ? sqr(cubicSmooth(1.0 - abs(x) / radius)) : 0.0;
}

float centerHue(float hue, float centerH) {
    float hueCentered = hue - centerH;

    if (hueCentered < -180.0) {
        return hueCentered + 360.0;
    } else if (hueCentered > 180.0) {
        return hueCentered - 360.0;
    } else {
        return hueCentered;
    }
}

vec3 rrtSweeteners(vec3 aces) {
    // Glow module
    float saturation = rgbToSaturation(aces);
    float ycIn = rgbToYc(aces);
    float s = sigmoidShaper(5.0 * saturation - 2.0);
    float addedGlow = 1.0 + glowFwd(ycIn, rrtGlowGain * s, rrtGlowMid);

    aces *= addedGlow;

    // Red modifier
    float hue = rgbToHue(aces);
    float centeredHue = centerHue(hue, rrtRedHue);
    float hueWeight = cubicBasisShaperFit(centeredHue, rrtRedWidth);

    aces.r = aces.r
        + hueWeight * saturation * (rrtRedPivot - aces.r)
            * (1.0 - rrtRedScale * 1.00);

    // ACES to RGB rendering space
    vec3 rgbPre = max0(aces) * ap0ToAp1;

    // Global desaturation
    float luminance = dot(rgbPre, luminanceWeightsAp1);
    rgbPre = mix(vec3(luminance), rgbPre, rrtSatFactor);

    // Added gamma adjustment before the RRT
    rgbPre = pow(rgbPre, vec3(rrtGammaCurve));

    return rgbPre;
}

/*
 * Reference Rendering Transform (RRT)
 *
 * Modifications:
 * Changed input and output color space to ACEScg to avoid 2 unnecessary mat3
 * transformations
 */
vec3 acesRrt(vec3 aces) {
    // Apply RRT sweeteners
    vec3 rgbPre = rrtSweeteners(aces);

    // Apply the tonescale independently in rendering-space RGB
    vec3 rgbPost;
    rgbPost.r = segmentedSplineC5Fwd(rgbPre.r);
    rgbPost.g = segmentedSplineC5Fwd(rgbPre.g);
    rgbPost.b = segmentedSplineC5Fwd(rgbPre.b);

    return rgbPost;
}

// Gamma adjustment to compensate for dim surround
vec3 darkSurroundToDimSurround(vec3 linearCV) {
    const float dimSurroundGamma = 0.9811; // default: 0.9811

    vec3 XYZ = linearCV * ap1ToXyz;
    vec3 xyY = XYZ_to_xy_y(XYZ);

    xyY.z = max0(xyY.z);
    xyY.z = pow(xyY.z, dimSurroundGamma);

    return xy_y_to_XYZ(xyY) * xyzToAp1;
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
 * transformations The sRGB transfer function is applied later in the
 * pipeline
 */
vec3 acesOdt(vec3 rgbPre) {
    // Apply the tonescale independently in rendering-space RGB
    vec3 rgbPost;
    rgbPost.r = segmentedSplineC9Fwd(rgbPre.r);
    rgbPost.g = segmentedSplineC9Fwd(rgbPre.g);
    rgbPost.b = segmentedSplineC9Fwd(rgbPre.b);

    // Scale luminance to linear code value
    vec3 linearCV = yToLinCV(rgbPost, cinemaWhite, cinemaBlack);

    // Apply gamma adjustment to compensate for dim surround
    linearCV = darkSurroundToDimSurround(linearCV);

    // Apply desaturation to compensate for luminance difference
    float luminance = dot(linearCV, luminanceWeightsAp1);
    linearCV = mix(vec3(luminance), linearCV, odtSatFactor);

    return linearCV;
}

/*
 * RRT + ODT fit by Stephen Hill
 * https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
 */
vec3 rrtAndOdtFit(vec3 rgb) {
    vec3 a = rgb * (rgb + 0.0245786) - 0.000090537;
    vec3 b = rgb * (0.983729 * rgb + 0.4329510) + 0.238081;

    return a / b;
}


// Luster Academy Color controls. These are only reached by ACES tonemap operators.
vec3 academyColorControls(vec3 color) {
    color *= exp2(0.0);

    // Stable contrast around middle grey in the post-ODT linear domain.
    const float pivot = 0.18;
    color = exp2((log2(max(color, vec3(1e-6))) - log2(pivot))
        * 1.00 + log2(pivot));

    // Saturation + optional colorfulness shaping (post-ODT working space).
    float luma = dot(color, luminanceWeights);
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
