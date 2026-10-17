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

const float minLuminance
    = getLuminanceFromExposure(getExposureFromEv100(autoExposureMin));
const float maxLuminance
    = getLuminanceFromExposure(getExposureFromEv100(autoExposureMax));
const float minLogLuminance = log2(minLuminance);
const float maxLogLuminance = log2(maxLuminance);

#ifdef manualExposureUseScreenBrightness
float manualExposureTarget
    = mix(minLuminance, maxLuminance, screenBrightness);
#else
const float manualExposureTarget = manualExposureValue;
#endif

float getBinFromLuminance(float luminance) {
    const float binCount = histogramBins;
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

    return min(binCount * logLuminance, binCount - 1.0);
}

float getLuminanceFromBin(int bin) {
    const float logLuminanceRange = maxLogLuminance - minLogLuminance;

    float logLuminance = bin * rcp(float(histogramBins));

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

float getPercentileLuminance(float[histogramBins] pdf, float target) {
    float cdf = 0.0;

    for (int i = 0; i < histogramBins; ++i) {
        cdf += pdf[i];
        if (cdf > target) {
            return getLuminanceFromBin(i);
        }
    }

    return 0.0; // ??
}


float getMeteredLuminance(float[histogramBins] pdf) {
    float luminanceMid = getPercentileLuminance(pdf, histogramTarget);
    float luminanceDark = getPercentileLuminance(pdf, 0.2);
    float luminanceBright = getPercentileLuminance(pdf, 0.8);

    float weightSum = 1.0 + histogramShadowWeight + histogramHighlightWeight;

    return (luminanceMid + histogramShadowWeight * luminanceDark
            + histogramHighlightWeight * luminanceBright)
        / weightSum;
}

void main() {
    uv = gl_MultiTexCoord0.xy;

    // Auto exposure

#ifndef autoExposure
    exposure = getExposureFromEv100(manualExposureTarget);
#else


    float previousExposure = texelFetch(colortex5, ivec2(0), 0).a
        / max(cameraExposureTriangleFactor(), 1e-6);

    float[histogramBins] pdf;
    buildHistogram(pdf);

    float luminance = getMeteredLuminance(pdf);

    // Sigmoid highlight rolloff into the rails: linear cal/lum through
    // the mid-tones with a soft knee at both ends instead of a hard
    // clamp snap. Bounds come from our EV Min/Max histogram rails, so
    // the sliders stay the single source of truth for calibration.
    float minAllowedExposure = calibration / maxLuminance;
    float maxAllowedExposure = calibration / minLuminance;
    float sigmoidA = maxLuminance;
    float sigmoidB = max(maxLuminance - minLuminance, 1e-6);
    float targetExposure = calibration
        / (sigmoidA - sigmoidB * exp(-luminance / sigmoidB));


    bool previousBad = isnan(previousExposure) || isinf(previousExposure)
        || previousExposure <= 0.0;
    bool targetBad = isnan(targetExposure) || isinf(targetExposure)
        || targetExposure <= 0.0;
    if (targetBad) {
        targetExposure = previousBad
            ? getExposureFromEv100(manualExposureTarget)
            : previousExposure;
    }
    if (previousBad) {
        previousExposure = targetExposure;
    }

    // Hard rails from the EV Min/Max sliders: neither a spike frame nor
    // a stale history texel can push exposure outside calibration.
    // Ordered defensively since the sliders can be set inverted.
    float railLo = min(minAllowedExposure, maxAllowedExposure);
    float railHi = max(minAllowedExposure, maxAllowedExposure);
    targetExposure = clamp(targetExposure, railLo, railHi);
    previousExposure = clamp(previousExposure, railLo, railHi);

    float adjustmentRate = targetExposure < previousExposure
        ? autoExposureRateDimToBright
        : autoExposureRateBrightToDim;
    float blendWeight = exp(-adjustmentRate * frameTime);

    exposure = mix(targetExposure, previousExposure, blendWeight);
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
