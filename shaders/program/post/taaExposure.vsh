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
#if !defined INCLUDE_CAMERA_CAMERA
#define INCLUDE_CAMERA_CAMERA

// Reference setup: every triangle factor is normalized to these, so the
// shipped defaults reproduce the pre-physical look exactly.
const float cameraReferenceFstops = 3.2;
const float cameraReferenceShutter = 60.0; // 1/60 s
const float cameraReferenceIso = 100.0;

// Focal length in millimetres from the vertical FOV and the sensor height
// (sensor width shared across axes, height derived from aspect ratio).
float cameraSensorHeightMm(float frameAspect) {
    return float(camSensorWidth) / max(frameAspect, 1e-4);
}

float cameraFocalLengthMm(float projection11, float frameAspect) {
    float sensorH = cameraSensorHeightMm(frameAspect);
    return 0.5 * sensorH * projection11;
}

// Thin-lens circle of confusion as a fraction of screen height:
// CoC = (f^2 / N) * |1/S - 1/D|, distances in metres.
float cameraCocHeightFraction(
    float focalMm,
    float sensorH,
    float focusM,
    float distM
) {
    float cocMm = focalMm * focalMm / max(camFstops, 1e-4)
        * abs(1.0 / (focusM * 1000.0) - 1.0 / (distM * 1000.0));
    return cocMm / max(sensorH, 1e-4);
}

// Shutter trail factor relative to the 60Hz reference capture.
float cameraShutterTrailFactor() {
    return cameraReferenceShutter / float(camShutterSpeed);
}

// Closed-triangle exposure factor: t * ISO / N^2, normalized to the
// reference setup, times the EV compensation dial.
float cameraExposureTriangleFactor() {
    float t = cameraShutterTrailFactor();
    float iso = float(camIso) / cameraReferenceIso;
    float n = cameraReferenceFstops / max(camFstops, 1e-4);
    return t * iso * n * n * exp2(camExposureCompensation);
}

#endif // INCLUDE_CAMERA_CAMERA

out vec2 uv;

flat out float exposure;

#if debugView == debugViewHistogram
flat out vec4[histogramBins / 4] histogramPdf;
flat out float histogramSelectedBin;
#endif

uniform sampler2D colortex0; // Scene color
uniform sampler2D colortex5; // Scene history

uniform float frameTime;
uniform float screenBrightness;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

#include "/lib/util/color.glsl"

#define getExposureFromEv100(ev100) exp2(-(ev100))
#define getExposureFromLuminance(l) calibration / (l)
#define getLuminanceFromExposure(e) calibration / (e)

const float K = 12.5; // Light-meter calibration constant
const float sensitivity = 100.0; // ISO
const float calibration = K / sensitivity / 1.2;

// The EV Min/Max sliders are rails on the *output* exposure. The meter itself
// looks at a window padded beyond them, so the percentiles keep resolving real
// scene luminance when the scene is outside the rails instead of piling up in
// the end bins. Ordered defensively since the sliders can be set inverted.
const float meterPaddingEv = 4.0;
const float railMinEv = min(autoExposureMin, autoExposureMax);
const float railMaxEv = max(autoExposureMin, autoExposureMax);

const float minLuminance = getLuminanceFromExposure(
    getExposureFromEv100(railMinEv - meterPaddingEv)
);
const float maxLuminance = getLuminanceFromExposure(
    getExposureFromEv100(railMaxEv + meterPaddingEv)
);
const float minLogLuminance = log2(minLuminance);
const float maxLogLuminance = log2(maxLuminance);

#ifdef manualExposureUseScreenBrightness
float manualExposureTarget
    = mix(minLuminance, maxLuminance, screenBrightness);
#else
const float manualExposureTarget = manualExposureValue;
#endif

float getBinFromLuminance(float luminance) {
    const float binSpan = histogramBins - 1.0;
    const float rcpLogLuminanceRange
        = 1.0 / (maxLogLuminance - minLogLuminance);
    const float scaledMinLogLuminance
        = minLogLuminance * rcpLogLuminanceRange;

    if (luminance <= minLuminance) {
        return 0.0; // Avoid taking log of 0
    }

    float logLuminance = clamp01(
        log2(luminance) * rcpLogLuminanceRange - scaledMinLogLuminance
    );

    return binSpan * logLuminance;
}

// Inverse of getBinFromLuminance, continuous so percentiles can land between
// bins.
float getLuminanceFromBin(float bin) {
    const float binSpan = histogramBins - 1.0;
    const float logLuminanceRange = maxLogLuminance - minLogLuminance;

    float logLuminance = clamp(bin, 0.0, binSpan) * rcp(binSpan);

    return exp2(logLuminance * logLuminanceRange + minLogLuminance);
}

void buildHistogram(out float[histogramBins] pdf) {
    // Initialize PDF to 0
    for (int i = 0; i < histogramBins; ++i) {
        pdf[i] = 0.0;
    }

    const ivec2 tiles = ivec2(32, 18);
    const vec2 tileSize = rcp(vec2(tiles));

    float lod = ceil(log2(maxOf(viewRes * tileSize)));

    // Sample into histogram
    float totalWeight = 0.0;
    for (int y = 0; y < tiles.y; ++y) {
        for (int x = 0; x < tiles.x; ++x) {
            vec2 coord = vec2(x, y) * tileSize + (0.5 * tileSize);

            vec3 rgb
                = textureLod(colortex0, coord * taauViewportScale, lod).rgb;
            float luminance = dot(rgb, luminanceWeightsAp1);

            float bin = getBinFromLuminance(luminance);

            uint bin0 = uint(bin);
            uint bin1 = min(bin0 + 1u, uint(histogramBins) - 1u);

            float weight1 = fract(bin);
            float weight0 = 1.0 - weight1;


            vec2 weightUv = (vec2(x, y) + 0.5) / vec2(tiles);
            float centerWeight = (1.0 - sqr(weightUv.x * 2.0 - 1.0))
                * (1.0 - sqr(weightUv.y * 2.0 - 1.0));
            centerWeight *= centerWeight;

            pdf[bin0] += weight0 * centerWeight;
            pdf[bin1] += weight1 * centerWeight;
            totalWeight += centerWeight;
        }
    }

    // Normalize PDF by the accumulated weight so CDF percentiles stay exact
    for (int i = 0; i < histogramBins; ++i) {
        pdf[i] /= max(totalWeight, eps);
    }
}

// Luminance at a CDF target. The crossing is interpolated inside the bin that
// holds it, so metered luminance is continuous instead of stepping bin by bin.
float getPercentileLuminance(float[histogramBins] pdf, float target) {
    float cdf = 0.0;

    for (int i = 0; i < histogramBins; ++i) {
        float next = cdf + pdf[i];

        if (next > target) {
            // Mass is splatted into two neighbouring bins by a linear tent, so
            // a bin's mass is centred on its index.
            float t = clamp01((target - cdf) / max(pdf[i], 1e-6));
            return getLuminanceFromBin(float(i) - 0.5 + t);
        }

        cdf = next;
    }

    return maxLuminance;
}

// Three-population meter, combined as a weighted geometric mean. Luminance is
// perceived (and a camera responds) logarithmically, so a log-domain blend
// weighs a stop of shadow against a stop of highlight, instead of letting one
// very bright percentile outvote the rest of the frame.
float getMeteredLuminance(float[histogramBins] pdf) {
    float luminanceMid
        = max(getPercentileLuminance(pdf, histogramTarget), minLuminance);
    float luminanceDark = max(getPercentileLuminance(pdf, 0.2), minLuminance);
    float luminanceBright
        = max(getPercentileLuminance(pdf, 0.8), minLuminance);

    float weightSum = 1.0 + histogramShadowWeight + histogramHighlightWeight;

    float meteredLog = (log2(luminanceMid)
                        + histogramShadowWeight * log2(luminanceDark)
                        + histogramHighlightWeight * log2(luminanceBright))
        / weightSum;

    return exp2(meteredLog);
}

// Polynomial smooth min/max: C1 knees instead of a hard clamp snap.
float smoothMaxEv(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * k * 0.25;
}

float smoothMinEv(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float softClampEv(float ev, float lo, float hi) {
    float knee = max(min(0.30, 0.5 * (hi - lo)), 1e-4);
    return smoothMinEv(smoothMaxEv(ev, lo, knee), hi, knee);
}

void main() {
    uv = gl_MultiTexCoord0.xy;

    // Auto exposure

#ifndef autoExposure
    #ifdef manualExposureUseScreenBrightness
    exposure = getExposureFromLuminance(manualExposureTarget);
    #else
    exposure = getExposureFromEv100(manualExposureTarget);
    #endif
#else
    // Physically based reflected-light meter, adapted in log space.
    float previousExposure = texelFetch(colortex5, ivec2(0), 0).a
        / max(cameraExposureTriangleFactor(), 1e-6);

    float[histogramBins] pdf;
    buildHistogram(pdf);

    float luminance = getMeteredLuminance(pdf);

    // Rails on the output exposure, in stops of exposure (exposure = 2^ev).
    float railLoEv = -railMaxEv;
    float railHiEv = -railMinEv;

    bool previousBad = isnan(previousExposure) || isinf(previousExposure)
        || previousExposure <= 0.0;

    // ISO 2720 reflected-light metering: exposure = K / (S * L). Between the
    // rails exposure tracks the metered luminance exactly, there is no
    // compressive curve in the middle of the range.
    float targetEv = log2(calibration / max(luminance, eps));

    bool targetBad = isnan(targetEv) || isinf(targetEv);
    if (targetBad) {
        targetEv = previousBad ? -manualExposureTarget : log2(previousExposure);
    }

    float previousEv = previousBad ? targetEv : log2(previousExposure);

    // Soft knee into the rails, then hard rails: neither a spike frame nor a
    // stale history texel can push exposure outside calibration.
    targetEv = softClampEv(targetEv, railLoEv, railHiEv);
    targetEv = clamp(targetEv, railLoEv, railHiEv);
    previousEv = clamp(previousEv, railLoEv, railHiEv);

    // The eye (and a camera's AE servo) adapts roughly linearly in stops per
    // second, so the exponential approach runs on EV, not on the linear gain.
    // Linear blending made a one-stop step brighten and darken at visibly
    // different speeds and overshot large jumps.
    float adjustmentRate = targetEv < previousEv
        ? autoExposureRateDimToBright
        : autoExposureRateBrightToDim;
    float blendWeight = exp(-adjustmentRate * frameTime);

    exposure = exp2(mix(targetEv, previousEv, blendWeight));
#endif


    // so scale the final exposure by the camera sensitivity. Applies to


    exposure *= cameraExposureTriangleFactor();

#if defined(autoExposure) \
    && debugView == debugViewHistogram
    for (int i = 0; i < histogramBins; ++i) {
        histogramPdf[i >> 2][i & 3] = pdf[i];
    }
    histogramSelectedBin = getBinFromLuminance(luminance);
#endif

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
