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

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float frameTime;
uniform float near;
uniform float far;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#define TEMPORAL_REPROJECTION
#include "/lib/util/spaceConversion.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 view_texel = ivec2(gl_FragCoord.xy * taau_render_scale);

    float depth = texelFetch(depthtex0, view_texel, 0).x;

    if (depth < hand_depth) {
        scene_color = texelFetch(colortex0, texel, 0).rgb;
        return;
    }

    vec2 velocity = uv - reproject(vec3(uv, depth)).xy;


    vec2 increment
        = (0.5 * camera_shutter_trail_factor() * motionBlurScale
            / float(motionBlurSamples))
        * velocity;

    // Centered gather: span uv -/+ trail/2 instead of smearing one way
    vec2 pos = uv - increment * (0.5 * float(motionBlurSamples));

    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    for (uint i = 0u; i < motionBlurSamples; ++i, pos += increment) {
        ivec2 tap = ivec2(pos * view_res);
        ivec2 view_tap = ivec2(pos * view_res * taau_render_scale);

        vec3 color = texelFetch(colortex0, tap, 0).rgb;
        float depth = texelFetch(depthtex0, view_tap, 0).x;
        float weight = (clamp01(pos) == pos && depth > hand_depth) ? 1.0 : 0.0;

        color_sum += color * weight;
        weight_sum += weight;
    }

    scene_color = weight_sum > eps ? color_sum * rcp(weight_sum)
                                   : texelFetch(colortex0, texel, 0).rgb;
}
