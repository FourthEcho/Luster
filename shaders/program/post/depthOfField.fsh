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

const float cameraReferenceFstops = 3.2;
const float cameraReferenceShutter = 60.0; // 1/60 s
const float cameraReferenceIso = 100.0;

float cameraSensorHeightMm(float frameAspect) {
    return float(camSensorWidth) / max(frameAspect, 1e-4);
}

float cameraFocalLengthMm(float projection11, float frameAspect) {
    float sensorH = cameraSensorHeightMm(frameAspect);
    return 0.5 * sensorH * projection11;
}

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

uniform sampler2D noisetex;

uniform sampler2D colortex0;

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float near, far;

uniform float aspectRatio;
uniform float centerDepthSmooth;

uniform int frameCounter;

uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

#include "/lib/lodMod.glsl"
// Radial chromatic dispersion

vec3 applyChromaticDispersion(
    sampler2D colorSampler,
    vec2 uv,
    vec3 color,
    float cocRadius,
    float strength,
    vec2 clampMax,
    float renderScale
) {
    vec2 centerOffset = uv - 0.5;
    vec2 chromaticScale = sign(centerOffset) * sqrt(abs(centerOffset));
    chromaticScale *= vec2(1.0, viewPixelSize.x / viewPixelSize.y);

    vec2 spectralOffset = chromaticScale * cocRadius * strength;

    color.r = textureLod(
        colorSampler,
        clamp(vec2(uv - spectralOffset), vec2(0.0), clampMax) * renderScale,
        0
    ).r;
    color.b = textureLod(
        colorSampler,
        clamp(vec2(uv + spectralOffset), vec2(0.0), clampMax) * renderScale,
        0
    ).b;

    return color;
}
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

#ifndef dof
    sceneColor = texelFetch(colortex0, texel, 0).rgb;
    return;
#endif

    float depth = texelFetch(depthtex0, texel, 0).x;

#ifdef LOD_MOD_ACTIVE
    float depthLod = texelFetch(lodDepthTex, texel, 0).x;

    if (isLodTerrain(depth, depthLod)) {
        depth = viewToScreenSpaceDepth(
            gbufferProjection,
            screenToViewSpaceDepth(lodProjectionMatrixInverse, depthLod)
        );
    }
#endif

    if (depth < handDepth) {
        sceneColor = texelFetch(colortex0, texel, 0).rgb;
        return;
    };

    // Calculate vogel disk rotation
    float theta = texelFetch(noisetex, texel & 511, 0).b;
    theta = r1(frameCounter, theta);
    theta *= tau;


    vec2 CoC;

    float distLin = max(
        abs(screenToViewSpaceDepth(gbufferProjectionInverse, depth)),
        eps
    );
    float focusLin = dofFocus < 0.0
        ? max(
              abs(screenToViewSpaceDepth(
                  gbufferProjectionInverse,
                  centerDepthSmooth
              )),
              eps
          )
        : max(abs(dofFocus), eps);
    float sensorH = cameraSensorHeightMm(aspectRatio);
    float focalMm
        = cameraFocalLengthMm(gbufferProjection[1][1], aspectRatio);
    float coc = min(
        cameraCocHeightFraction(focalMm, sensorH, focusLin, distLin),
        dofMaxRadius
    );
    // coc is a fraction of screen height: for circular bokeh in UV space
    // the horizontal radius must be divided by the aspect ratio
    CoC = coc * vec2(rcp(aspectRatio), 1.0);

    sceneColor = vec3(0.0);

    for (int i = 0; i < dofSamples; ++i) {
        vec2 offset = vogelDiscSample(i, dofSamples, theta);
        sceneColor
            += textureLod(
                   colortex0,
                   clamp(
                       vec2(uv + offset * CoC),
                       vec2(0.0),
                       vec2(
                           1.0 - 2.0 * viewPixelSize * rcp(taauViewportScale)
                       )
                   ) * taauViewportScale,
                   0
            )
                   .rgb;
    }

    sceneColor *= rcp(dofSamples);

#ifdef chromaticDispersion
    // Chromatic dispersion: radial spectral fringing scaled by the circle


    sceneColor = applyChromaticDispersion(
        colortex0,
        uv,
        sceneColor,
        length(CoC),
        chromaticDispersionStrength * 0.1,
        vec2(1.0 - 2.0 * viewPixelSize * rcp(taauViewportScale)),
        taauViewportScale
    );
#endif
}
