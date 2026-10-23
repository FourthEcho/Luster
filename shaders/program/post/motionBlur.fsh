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

layout(location = 0) out vec3 sceneColor;

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

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

#define TEMPORAL_REPROJECTION
#include "/lib/util/spaceConversion.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 viewTexel = ivec2(gl_FragCoord.xy * taauViewportScale);

    float depth = texelFetch(depthtex0, viewTexel, 0).x;

    if (depth < handDepth) {
        sceneColor = texelFetch(colortex0, texel, 0).rgb;
        return;
    }

    vec2 velocity = uv - reproject(vec3(uv, depth)).xy;


    vec2 increment
        = (0.5 * cameraShutterTrailFactor() * motionBlurScale
            / float(motionBlurSamples))
        * velocity;

    // Centered gather: span uv -/+ trail/2 instead of smearing one way
    vec2 pos = uv - increment * (0.5 * float(motionBlurSamples));

    vec3 colorSum = vec3(0.0);
    float weightSum = 0.0;

    for (uint i = 0u; i < motionBlurSamples; ++i, pos += increment) {
        ivec2 tap = ivec2(pos * viewRes);
        ivec2 viewTap = ivec2(pos * viewRes * taauViewportScale);

        vec3 color = texelFetch(colortex0, tap, 0).rgb;
        float depth = texelFetch(depthtex0, viewTap, 0).x;
        float weight = (clamp01(pos) == pos && depth > handDepth) ? 1.0 : 0.0;

        colorSum += color * weight;
        weightSum += weight;
    }

    sceneColor = weightSum > eps ? colorSum * rcp(weightSum)
                                   : texelFetch(colortex0, texel, 0).rgb;
}
