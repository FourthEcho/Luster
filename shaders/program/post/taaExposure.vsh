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
const float camera_reference_fstops = 3.2;
const float camera_reference_shutter = 60.0; // 1/60 s
const float camera_reference_iso = 100.0;

// Focal length in millimetres from the vertical FOV and the sensor height
// (sensor width shared across axes, height derived from aspect ratio).
float camera_sensor_height_mm(float aspect_ratio) {
    return float(camSensorWidth) / max(aspect_ratio, 1e-4);
}

float camera_focal_length_mm(float projection_11, float aspect_ratio) {
    float sensor_h = camera_sensor_height_mm(aspect_ratio);
    return 0.5 * sensor_h * projection_11;
}

// Thin-lens circle of confusion as a fraction of screen height:
// CoC = (f^2 / N) * |1/S - 1/D|, distances in metres.
float camera_coc_height_fraction(
    float focal_mm,
    float sensor_h,
    float focus_m,
    float dist_m
) {
    float coc_mm = focal_mm * focal_mm / max(camFstops, 1e-4)
        * abs(1.0 / (focus_m * 1000.0) - 1.0 / (dist_m * 1000.0));
    return coc_mm / max(sensor_h, 1e-4);
}

// Shutter trail factor relative to the 60Hz reference capture.
float camera_shutter_trail_factor() {
    return camera_reference_shutter / float(camShutterSpeed);
}

// Closed-triangle exposure factor: t * ISO / N^2, normalized to the
// reference setup, times the EV compensation dial.
float camera_exposure_triangle_factor() {
    float t = camera_shutter_trail_factor();
    float iso = float(camIso) / camera_reference_iso;
    float n = camera_reference_fstops / max(camFstops, 1e-4);
    return t * iso * n * n * exp2(camExposureCompensation);
}

#endif // INCLUDE_CAMERA_CAMERA

out vec2 uv;

flat out float exposure;

#if debugView == debugViewHistogram
flat out vec4[histogramBins / 4] histogram_pdf;
flat out float histogram_selected_bin;
#endif

uniform sampler2D colortex0; // Scene color
uniform sampler2D colortex5; // Scene history

uniform float frameTime;
uniform float screenBrightness;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#include "/lib/util/color.glsl"

#define get_exposure_from_ev_100(ev100) exp2(-(ev100))
#define get_exposure_from_luminance(l) calibration / (l)
#define get_luminance_from_exposure(e) calibration / (e)

const float K = 12.5; // Light-meter calibration constant
const float sensitivity = 100.0; // ISO
const float calibration = K / sensitivity / 1.2;

const float min_luminance
    = get_luminance_from_exposure(get_exposure_from_ev_100(autoExposureMin));
const float max_luminance
    = get_luminance_from_exposure(get_exposure_from_ev_100(autoExposureMax));
const float min_log_luminance = log2(min_luminance);
const float max_log_luminance = log2(max_luminance);

#ifdef manualExposureUseScreenBrightness
float manual_exposure_value
    = mix(min_luminance, max_luminance, screenBrightness);
#else
const float manual_exposure_value = manualExposureValue;
#endif

float get_bin_from_luminance(float luminance) {
    const float bin_count = histogramBins;
    const float rcp_log_luminance_range
        = 1.0 / (max_log_luminance - min_log_luminance);
    const float scaled_min_log_luminance
        = min_log_luminance * rcp_log_luminance_range;

    if (luminance <= min_luminance) {
        return 0.0; // Avoid taking log of 0
    }

    float log_luminance = clamp01(
        log2(luminance) * rcp_log_luminance_range - scaled_min_log_luminance
    );

    return min(bin_count * log_luminance, bin_count - 1.0);
}

float get_luminance_from_bin(int bin) {
    const float log_luminance_range = max_log_luminance - min_log_luminance;

    float log_luminance = bin * rcp(float(histogramBins));

    return exp2(log_luminance * log_luminance_range + min_log_luminance);
}

void build_histogram(out float[histogramBins] pdf) {
    // Initialize PDF to 0
    for (int i = 0; i < histogramBins; ++i) {
        pdf[i] = 0.0;
    }

    const ivec2 tiles = ivec2(32, 18);
    const vec2 tile_size = rcp(vec2(tiles));

    float lod = ceil(log2(max_of(view_res * tile_size)));

    // Sample into histogram
    float total_weight = 0.0;
    for (int y = 0; y < tiles.y; ++y) {
        for (int x = 0; x < tiles.x; ++x) {
            vec2 coord = vec2(x, y) * tile_size + (0.5 * tile_size);

            vec3 rgb
                = textureLod(colortex0, coord * taau_render_scale, lod).rgb;
            float luminance = dot(rgb, luminance_weights_ap1);

            float bin = get_bin_from_luminance(luminance);

            uint bin0 = uint(bin);
            uint bin1 = min(bin0 + 1u, uint(histogramBins) - 1u);

            float weight1 = fract(bin);
            float weight0 = 1.0 - weight1;


            vec2 weight_uv = (vec2(x, y) + 0.5) / vec2(tiles);
            float center_weight = (1.0 - sqr(weight_uv.x * 2.0 - 1.0))
                * (1.0 - sqr(weight_uv.y * 2.0 - 1.0));
            center_weight *= center_weight;

            pdf[bin0] += weight0 * center_weight;
            pdf[bin1] += weight1 * center_weight;
            total_weight += center_weight;
        }
    }

    // Normalize PDF by the accumulated weight so CDF percentiles stay exact
    for (int i = 0; i < histogramBins; ++i) {
        pdf[i] /= max(total_weight, eps);
    }
}

float get_percentile_luminance(float[histogramBins] pdf, float target) {
    float cdf = 0.0;

    for (int i = 0; i < histogramBins; ++i) {
        cdf += pdf[i];
        if (cdf > target) {
            return get_luminance_from_bin(i);
        }
    }

    return 0.0; // ??
}


float get_metered_luminance(float[histogramBins] pdf) {
    float luminance_mid = get_percentile_luminance(pdf, histogramTarget);
    float luminance_dark = get_percentile_luminance(pdf, 0.2);
    float luminance_bright = get_percentile_luminance(pdf, 0.8);

    float weight_sum = 1.0 + histogramShadowWeight + histogramHighlightWeight;

    return (luminance_mid + histogramShadowWeight * luminance_dark
            + histogramHighlightWeight * luminance_bright)
        / weight_sum;
}

void main() {
    uv = gl_MultiTexCoord0.xy;

    // Auto exposure

#ifndef autoExposure
    exposure = get_exposure_from_ev_100(manual_exposure_value);
#else


    float previous_exposure = texelFetch(colortex5, ivec2(0), 0).a
        / max(camera_exposure_triangle_factor(), 1e-6);

    float[histogramBins] pdf;
    build_histogram(pdf);

    float luminance = get_metered_luminance(pdf);

    float target_exposure = get_exposure_from_luminance(luminance);


    bool previous_bad = isnan(previous_exposure) || isinf(previous_exposure)
        || previous_exposure <= 0.0;
    bool target_bad = isnan(target_exposure) || isinf(target_exposure)
        || target_exposure <= 0.0;
    if (target_bad) {
        target_exposure = previous_bad
            ? get_exposure_from_ev_100(manual_exposure_value)
            : previous_exposure;
    }
    if (previous_bad) {
        previous_exposure = target_exposure;
    }

    float adjustment_rate = target_exposure < previous_exposure
        ? autoExposureRateDimToBright
        : autoExposureRateBrightToDim;
    float blend_weight = exp(-adjustment_rate * frameTime);

    exposure = mix(target_exposure, previous_exposure, blend_weight);
#endif


    // so scale the final exposure by the camera sensitivity. Applies to


    exposure *= camera_exposure_triangle_factor();

#if defined(autoExposure) \
    && debugView == debugViewHistogram
    for (int i = 0; i < histogramBins; ++i) {
        histogram_pdf[i >> 2][i & 3] = pdf[i];
    }
    histogram_selected_bin = get_bin_from_luminance(luminance);
#endif

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
