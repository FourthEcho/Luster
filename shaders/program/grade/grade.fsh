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

layout(location = 0) out vec3 sceneColor;

/* RENDERTARGETS: 0 */

in vec2 uv;

#ifdef colorGrading
  #if gradeWhiteBalance != 6500
flat in mat3 whiteBalanceMatrix;
  #endif
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // bloomColor tiles
uniform sampler2D colortex3; // fog transmittance
uniform sampler2D colortex5; // scene color

uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;

uniform vec3 sunDir;

uniform float rainStrength;

uniform float aspectRatio;
uniform float blindness;
uniform float darknessFactor;
uniform float frameTimeCounter;

uniform float biomeCave;
uniform float timeNoon;
uniform float eyeSkylight;

uniform vec2 viewPixelSize;

#if !defined INCLUDE_POST_TONEMAP_OPERATORS
#define INCLUDE_POST_TONEMAP_OPERATORS


#include "/lib/util/color.glsl"
#include "/lib/academy/aces.glsl"

// ACES Fit
// ACES RRT and ODT approximation
vec3 tonemapAcesFit(vec3 rgb) {
    rgb *= 1.6 * exp2(academyRrtExposure); // Match the exposure to the RRT

    rgb = rgb * workingToAp0;

    rgb = rrtSweeteners(rgb);
    rgb = rrtAndOdtFit(rgb);

    // Global desaturation (fit domain is AP0/AP1; use stable AP1 luma so
    // the result does not drift with displayGamut).
    vec3 grayscale = vec3(dot(rgb, luminanceWeightsAp1));
    rgb = mix(grayscale, rgb, odtSatFactor);

    return academyColorControls(rgb * ap1ToWorking);
}

// ACES Full
// ACES RRT and ODT
vec3 tonemapAcesFull(vec3 rgb) {
    rgb *= 1.6 * exp2(academyRrtExposure); // Match the exposure to the RRT

    rgb = rgb * workingToAp0;

    rgb = acesRrt(rgb);
    rgb = acesOdt(rgb);

    return academyColorControls(rgb * ap1ToWorking);
}

// Lottes
// Timothy Lottes 2016, "Advanced Techniques and Optimization of HDR Color
// Pipelines" https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf

// GLSL port via https://github.com/dmnsgn/shaders-tone-map

// License:
/*
Copyright (C) 2019 Damien Seguin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
vec3 tonemapLottes(vec3 rgb) {
    rgb = max(rgb, vec3(0.0)); // pow() of negatives is NaN
    const vec3 a = vec3(1.6); // Contrast
    const vec3 d = vec3(0.977); // Shoulder contrast
    const vec3 hdrMax = vec3(8.0); // White point
    const vec3 midIn = vec3(0.18); // Fixed midpoint x
    const vec3 midOut = vec3(0.267); // Fixed midpoint y

    const vec3 b = (-pow(midIn, a) + pow(hdrMax, a) * midOut)
        / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);
    const vec3 c = (pow(hdrMax, a * d) * pow(midIn, a)
                    - pow(hdrMax, a) * pow(midIn, a * d) * midOut)
        / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);

    return pow(rgb, a) / (pow(rgb, a * d) * b + c);
}

// Hejl 2015
// Hejl 2015 filmic, after Jim Hejl's reference ("ToneMapFilmic_Hejl2015").
// GLSL port via https://github.com/dmnsgn/shaders-tone-map, including its
// guard: the curve goes negative just above ~0.0046 linear, so the documented
// white point is understated: at the root vf.w is 0 and the correction blows
// up, below it the whole result flips sign. max() keeps black at black.

// License:
/*
Copyright (C) 2019 Damien Seguin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
vec3 tonemapHejl2015(vec3 rgb) {
    const float whitePoint = 5.0;

    vec4 vh = vec4(rgb, whitePoint);
    vec4 va = (1.425 * vh) + 0.05; // eval filmic curve
    vec4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;

    return max(vec3(0.0), vf.rgb / vf.www); // white point correction
}


// Filmic tonemapping operator made by Jim Hejl and Richard Burgess-Dawson
// ("Filmic Tonemapping for Real-time Rendering", SIGGRAPH 2010 course).
// Modified by Tech to not lose color information below 0.004 (replaces the

vec3 tonemapHejlBurgess(vec3 rgb) {
    rgb = rgb * min(vec3(1.0), 1.0 - 0.8 * exp(rcp(-0.004) * rgb));
    rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return srgbEotfInv(rgb); // Revert built-in sRGB conversion
}

// Tech
// Tone mapping operator made by Tech for his shader pack Lux
vec3 tonemapTech(vec3 rgb) {
    vec3 a = rgb * min(vec3(1.0), 1.0 - exp(-1.0 / 0.038 * rgb));
    a = mix(a, rgb, rgb * rgb);
    return a / (a + 0.6);
}

// Uncharted 2
// Filmic tonemapping operator made by John Hable for Uncharted 2
vec3 tonemapUncharted2Partial(vec3 rgb) {
    const float a = 0.15;
    const float b = 0.50;
    const float c = 0.10;
    const float d = 0.20;
    const float e = 0.02;
    const float f = 0.30;

    return ((rgb * (a * rgb + (c * b)) + (d * e))
            / (rgb * (a * rgb + b) + d * f))
        - e / f;
}

vec3 tonemapUncharted2(vec3 rgb) {
    const float exposureBias = 2.0;
    const vec3 w = vec3(11.2);

    vec3 curr = tonemapUncharted2Partial(rgb * exposureBias);
    vec3 whiteScale = vec3(1.0) / tonemapUncharted2Partial(w);
    return curr * whiteScale;
}

// Ozius
// Tonemapping operator made by Zombye for his old shader pack Ozius
// It was given to me by Jessie
vec3 tonemapOzius(vec3 rgb) {
    const vec3 a = vec3(0.46, 0.46, 0.46);
    const vec3 b = vec3(0.60, 0.60, 0.60);

    rgb *= 1.6;

    vec3 cr = mix(vec3(dot(rgb, luminanceWeights)), rgb, 0.5) + 1.0;

    rgb = pow(rgb / (1.0 + rgb), a);
    return pow(rgb * rgb * (-2.0 * rgb + 3.0), cr / b);
}

// Reinhard
vec3 tonemapReinhard(vec3 rgb) { return rgb / (rgb + 1.0); }

// Reinhard Jodie
// Reinhard driven by luminance, then blended per channel by the per-channel
// result, so saturated colors keep their hue instead of skewing towards
// whichever channel compresses first
// https://64.github.io/tonemapping/#reinhard-jodie
// GLSL port via https://github.com/dmnsgn/shaders-tone-map

// License:
/*
Copyright (C) 2019 Damien Seguin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
vec3 tonemapReinhardJodie(vec3 rgb) {
    vec3 reinhard = rgb / (rgb + 1.0);
    return mix(rgb / (dot(rgb, luminanceWeights) + 1.0), reinhard, reinhard);
}

#endif // INCLUDE_POST_TONEMAP_OPERATORS
#if !defined INCLUDE_COLOR_GRADING
#define INCLUDE_COLOR_GRADING

// Stage A: scene-linear controls before tone mapping.
// Stage B: display-linear perceptual controls after tone mapping.

vec3 colorGradeLiftGammaGain(vec3 rgb) {
    // Log-domain-friendly lift, then power/gain. Defaults are mathematically neutral.
    vec3 lift = vec3(gradeLiftR, gradeLiftG, gradeLiftB);
    vec3 gamma = vec3(max(gradeGammaR, 0.05), max(gradeGammaG, 0.05), max(gradeGammaB, 0.05));
    vec3 gain = vec3(gradeGainR, gradeGainG, gradeGainB);

    rgb = max(rgb + lift, vec3(0.0));
    rgb = pow(rgb, rcp(gamma));
    return max(rgb * gain, vec3(0.0));
}

vec3 colorGradeInput(vec3 rgb, mat3 whiteBalanceMatrix) {
    float brightness = max(gradeBrightness, 0.0);
    float contrast = max(gradeContrast, 0.0);
    float pivot = max(gradePivot, 1e-4);

    rgb = max(rgb, vec3(0.0));
    rgb *= brightness;

    // Symmetric contrast around a scene-linear pivot, performed in log space so exposure stops stay natural.
    rgb = log2(rgb + 1e-6);
    float logPivot = log2(pivot);
    rgb = exp2((rgb - logPivot) * contrast + logPivot);
    rgb = max(rgb - 1e-6, vec3(0.0));

    // White balance in chromaticity space. A Bradford matrix is calculated in the vertex shader.
    rgb = max(rgb * whiteBalanceMatrix, vec3(0.0));

    // Lift / gamma / gain (ASC-style three-way control).
    rgb = colorGradeLiftGammaGain(rgb);
    return max(rgb, vec3(0.0));
}


vec3 gradeRgbToOklab(vec3 c) {
    vec3 lms = c * workingToXyzColor * xyzToLms;
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return vec3(
        0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
        1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
        0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z
    );
}

vec3 gradeOklabToRgb(vec3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    vec3 lms = vec3(l, m, s);
    lms = lms * lms * lms;
    return max((lms * lmsToXyz) * xyzToWorkingColor, vec3(0.0));
}

vec2 gradeRotate(vec2 v, float radiansAngle) {
    float s = sin(radiansAngle), c = cos(radiansAngle);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec2 gradeHueVector(float degrees, float saturation) {
    float h = radians(degrees);
    return vec2(cos(h), sin(h)) * saturation;
}

vec3 colorGradeOutput(vec3 rgb) {
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));

    vec3 lab = gradeRgbToOklab(rgb);
    float chroma = length(lab.yz);

    // Global saturation + vibrance: vibrance preferentially boosts low-chroma colors.
    float vibranceMask = 1.0 - clamp(chroma * 3.5, 0.0, 1.0);
    float satMul = max(gradeSaturation + gradeVibrance * vibranceMask, 0.0);
    lab.yz *= satMul;

    // Gentle perceptual contrast with a stable pivot around middle gray.
    lab.x = clamp((lab.x - gradeOklabPivot) * gradeOklabContrast + gradeOklabPivot, 0.0, 1.0);

    // Split-tone masks use the perceptual lightness channel.
    float shadows = 1.0 - smoothstep(gradeShadowLow, gradeShadowHigh, lab.x);
    float highlights = smoothstep(gradeHighlightLow, gradeHighlightHigh, lab.x);
    float mids = clamp(1.0 - shadows - highlights, 0.0, 1.0);

    // Three-way hue rotation while preserving existing chroma magnitude.
    if (chroma > 1e-6) {
        float shadowW = shadows * gradeShadowStrength;
        float midW = mids * gradeMidStrength;
        float highlightW = highlights * gradeHighlightStrength;
        vec2 ab = lab.yz;
        ab = gradeRotate(ab, radians(gradeShadowHue) * shadowW);
        ab = gradeRotate(ab, radians(gradeMidHue) * midW);
        ab = gradeRotate(ab, radians(gradeHighlightHue) * highlightW);
        lab.yz = ab;
    }

    // Add controlled chroma bias for classic split toning.
    float tintScale = sqrt(max(lab.x, 0.0));
    lab.yz += gradeHueVector(gradeShadowTintHue, gradeShadowTintSat * shadows) * tintScale;
    lab.yz += gradeHueVector(gradeHighlightTintHue, gradeHighlightTintSat * highlights) * tintScale;

    // Convert the perceptual pass back to RGB, then apply selective HSL accents.
    vec3 perceptualRgb = gradeOklabToRgb(lab);
    vec3 hsv = rgbToHsv(perceptualRgb);
    float orange = isolateHue(hsv, 30.0, 20.0);
    float teal = isolateHue(hsv, 210.0, 20.0);
    float green = isolateHue(hsv, 90.0, 44.0);
    hsv.y = clamp(hsv.y * (1.0 + gradeOrangeSatBoost * orange), 0.0, 1.0);
    hsv.y = clamp(hsv.y * (1.0 + gradeTealSatBoost * teal), 0.0, 1.0);
    hsv.y = clamp(hsv.y * (1.0 + gradeGreenSatBoost * green), 0.0, 1.0);
    hsv.x = fract(hsv.x + (gradeGreenHueShift / 360.0) * green);
    vec3 selectiveRgb = hsvToRgb(hsv);
    rgb = mix(perceptualRgb, selectiveRgb, clamp(gradeSelectiveBlend, 0.0, 1.0));

    // Black/white point control, applied last to avoid fighting the tonemapper.
    rgb = max((rgb - gradeBlackPoint) / max(1.0 - gradeBlackPoint - gradeWhitePoint, 1e-4), vec3(0.0));
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));
    return rgb;
}

#endif
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
#if !defined INCLUDE_CAMERA_LOCAL_EXPOSURE
#define INCLUDE_CAMERA_LOCAL_EXPOSURE

#include "/lib/util/color.glsl"

float localExposureLuma(vec3 rgb) {
    return max(dot(max(rgb, vec3(0.0)), luminanceWeightsAp1), 1e-5);
}

#ifdef localExposure
// Scene luminance in stops, bounded to a window around the global meter so a
// sun disc, an emissive or a pitch-black void cannot dominate a pooled
// average.
float localExposureLog(vec3 rgb, float anchorLog) {
    return clamp(
        log2(localExposureLuma(rgb)),
        anchorLog - 9.0,
        anchorLog + 6.0
    );
}

// Edge-aware log-average of the pre-exposure history at one spatial scale.
// A hexagonal ring of mip taps is weighted by how close each tap is to the
// pixel's own luminance: a dark pixel beside a bright one is not averaged with
// it (no halo), and a pixel inside a region adapts to that region.
float localExposurePool(
    vec2 uv,
    float centerLog,
    float anchorLog,
    float radiusPx,
    float lod,
    float edgeStop,
    float rotation
) {
    const vec2 hexRing[6] = vec2[6](
        vec2(1.0, 0.0),
        vec2(0.5, 0.8660254),
        vec2(-0.5, 0.8660254),
        vec2(-1.0, 0.0),
        vec2(-0.5, -0.8660254),
        vec2(0.5, -0.8660254)
    );

    float cs = cos(rotation);
    float sn = sin(rotation);

    float sumLog
        = localExposureLog(textureLod(colortex5, uv, lod).rgb, anchorLog);
    float sumW = 1.0;

    for (int i = 0; i < 6; ++i) {
        vec2 d = hexRing[i];
        d = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) * radiusPx
            * viewPixelSize;

        vec2 tapUv = clamp(uv + d, viewPixelSize, 1.0 - viewPixelSize);
        float l = localExposureLog(textureLod(colortex5, tapUv, lod).rgb, anchorLog);

        float w = exp2(-edgeStop * abs(l - centerLog));
        sumLog += l * w;
        sumW += w;
    }

    return sumLog / sumW;
}

// Returns the local exposure offset in stops, relative to the global exposure.
// The pooled luminance is a multi-scale local adaptation level; the offset
// pulls each region toward the global meter anchor, so the global exposure
// stays in charge of overall brightness and the local pass only redistributes
// it inside the frame. The gain is a plain scalar on all three channels,
// which is exactly what changing exposure does, so hue and saturation hold.
float computeLocalExposureEv(vec2 texelUv, float anchorLog, float exposure) {
    vec3 centerRgb = textureLod(colortex5, texelUv, 0.0).rgb;
    float centerLuma = localExposureLuma(centerRgb);
    float centerLog = localExposureLog(centerRgb, anchorLog);

    float screenPx = maxOf(rcp(viewPixelSize));

    float radiusFine = max(2.0, 0.0015 * screenPx) * localExposureScale;
    float radiusMid = 0.012 * screenPx * localExposureScale;
    float radiusCoarse = 0.045 * screenPx * localExposureScale;

    float lodMid = ceil(log2(max(radiusMid * 0.6, 1.0)));
    float lodCoarse = ceil(log2(max(radiusCoarse * 0.6, 1.0)));

    float fine = localExposurePool(
        texelUv, centerLog, anchorLog, radiusFine, 0.0, 1.0, 0.0
    );
    float mid = localExposurePool(
        texelUv, centerLog, anchorLog, radiusMid, lodMid, 0.6, 0.5235988
    );
    float coarse = localExposurePool(
        texelUv, centerLog, anchorLog, radiusCoarse, lodCoarse, 0.3, 0.2617994
    );

    float wFine = 0.40 * localExposureDetail;
    const float wMid = 0.35;
    const float wCoarse = 0.40;

    float adaptationLog
        = (wFine * fine + wMid * mid + wCoarse * coarse)
        / (wFine + wMid + wCoarse);

    // Stops by which the surroundings sit below (+) or above (-) the meter.
    float deficit = anchorLog - adaptationLog;

    float ev = localExposureStrength * deficit;
    ev *= deficit > 0.0 ? localExposureShadows : localExposureHighlights;

    // Smooth saturation toward +-range: slope 1 at zero, never a hard clip, so
    // no banding or contouring where a limit would be hit.
    float range = max(localExposureRange, 1e-3);
    ev /= 1.0 + abs(ev) / range;

    // Never lift a pixel that is already close to white after the global
    // exposure; shadow lift must not push highlights into clipping.
    float exposedLuma = centerLuma * exposure;
    ev *= ev > 0.0 ? 1.0 - smoothstep(0.35, 1.5, exposedLuma) : 1.0;

    return ev;
}
#endif

#endif // INCLUDE_CAMERA_LOCAL_EXPOSURE
// Vignette mask (inlined; only used by this grading stage)
float vignetteMask(vec2 uv) {
    const float vignetteSize = 16.0;
    const float vignetteStrength = 0.08 * vignetteIntensity;

    float darknessPulse = 1.0 - dampen(abs(cos(2.0 * frameTimeCounter)));

    float vignetteBase
        = vignetteSize * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    vignetteBase = pow(
        vignetteBase,
        vignetteStrength + 0.1 * biomeCave + 0.3 * blindness
            + 0.2 * darknessPulse * darknessFactor
    );


    float vignetteR = length((uv - 0.5) * 2.0);
    float vignetteShaping = pow(
        smoothstep(
            vignetteStart,
            max(vignetteEnd, vignetteStart + 1e-3),
            vignetteR
        ),
        vignetteExponent
    );

    return mix(1.0, vignetteBase, vignetteShaping);
}
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#if !defined INCLUDE_CAMERA_LENS_FLARE
#define INCLUDE_CAMERA_LENS_FLARE

#ifdef lensFlare
// Blurred bright source: bloom tile 2 is the full frame downsampled into a
// Threshold is subtractive so sub-threshold sky contributes exactly zero.
vec3 lensFlareSource(vec2 screenUv) {
#ifdef bloom
    const float tileScale = 0.5 * exp2(-2.0);
    const vec2 tileOffset = vec2(1.0 - exp2(-2.0), 0.0);
    vec2 tileUv = clamp(screenUv, vec2(0.0), vec2(1.0)) * tileScale
        + tileOffset;
    vec3 c = bicubicFilter(colortex0, tileUv).rgb;
#else
    vec3 c = texture(colortex5, clamp(screenUv, vec2(0.0), vec2(1.0))).rgb;
#endif
    return max0(c - lensFlareThresh);
}

// Project the sun into screen UV; facing fades to 0 as the sun drops
// below the horizon or swings behind the camera.
vec2 lensFlareSunUv(out float facing) {
    vec3 viewSun = mat3(gbufferModelView) * sunDir;
    vec4 clip = gbufferProjection * vec4(viewSun * 100.0, 1.0);
    vec2 sunUv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
    facing = smoothstep(0.05, -0.15, viewSun.z)
        * smoothstep(-0.12, 0.02, sunDir.y);
    return sunUv;
}


vec3 lensFlareGhostSample(vec2 uv) {
    vec2 mirror = 1.0 - uv;
    vec2 axis = (vec2(0.5) - mirror) * lensFlareSpacing;

    vec3 acc = vec3(0.0);
    for (int i = 1; i <= lensFlareGhosts; ++i) {
        float fi = float(i);
        vec2 base = mirror + axis * fi;
        if (clamp01(base) != base) {
            continue;
        }
        vec3 ghost;
        ghost.r = lensFlareSource(base + axis * 0.01 * fi).r;
        ghost.g = lensFlareSource(base).g;
        ghost.b = lensFlareSource(base - axis * 0.01 * fi).b;

        float edge = 1.0 - smoothstep(0.0, 0.75, length(base - 0.5));
        acc += ghost * (edge * edge) / (1.0 + fi * 0.5);
    }

    return acc;
}

#ifdef lensFlareHalo
// Halo ring around the sun position: gaussian annulus sampled
// chromatically, widened/narrowed by the width control.
vec3 lensFlareHaloSample(vec2 uv, vec2 sunUv) {
    vec2 huv = uv - sunUv;
    huv.x *= aspectRatio;
    float dist = length(huv);
    vec2 dir = huv / max(dist, 1e-4);

    float ring = exp(
        -pow(
            (dist / max(lensFlareHaloRadius, 1e-4) - 1.0)
                / max(lensFlareHaloWidth, 0.05),
            2.0
        )
    );
    if (ring < 1e-4) {
        return vec3(0.0);
    }

    vec2 base = sunUv + dir * lensFlareHaloRadius
        * vec2(1.0 / aspectRatio, 1.0);
    vec3 halo;
    halo.r = lensFlareSource(base + dir * 0.004).r;
    halo.g = lensFlareSource(base).g;
    halo.b = lensFlareSource(base - dir * 0.004).b;

    return halo * ring;
}
#endif

vec3 getLensFlare(vec2 uv) {
    float facing;
    vec2 sunUv = lensFlareSunUv(facing);
    if (facing < 1e-4) {
        return vec3(0.0);
    }

    vec3 flare = lensFlareGhostSample(uv);
#ifdef lensFlareHalo
    flare += lensFlareHaloSample(uv, sunUv);
#endif

    // Storms and night haze kill flare faster than the sun itself dims
    flare *= facing * (1.0 - rainStrength * 0.9);


    float brightest = max(max(flare.r, flare.g), max(flare.b, 1e-4));
    flare *= (1.0 - exp(-brightest * lensFlareIntensity * 0.02))
        / brightest;

    return flare;
}
#endif

#endif // INCLUDE_CAMERA_LENS_FLARE

vec3 getBloom() {
    // Upsample last bloomColor tile. 

    vec2 padAmount = 6.0 * viewPixelSize;
    vec2 uvSrc = clamp(uv, padAmount, 1.0 - padAmount) * 0.5;

    return bloomUpsamplingFilter(colortex0, uvSrc).rgb;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    sceneColor = texelFetch(colortex5, texel, 0).rgb;

    float exposure = texelFetch(colortex5, ivec2(0), 0).a;

#if defined lensFlare && defined WORLD_OVERWORLD
    // Lens flare in HDR before exposure/tonemap so it grades with the scene
    sceneColor += getLensFlare(uv);
#endif

#ifdef bloom
    vec3 bloomColor = getBloom();
    // Bloom rides the exposure: hot dark-scene gain no longer blows it
    // out, bright scenes keep full bloom. No-op at exposure <= 1.
    float bloomStrength = 0.12 * bloomIntensity
        / mix(max(exposure, 1.0), 1.0, 0.31);

    // Additive bloomColor: lerping towards bloomColor would dim the base image
    sceneColor += bloomColor * bloomStrength;

#ifdef bloomyFog
    // colortex3 is written by c1, which renders into the lower-left


    vec2 fogUv = min(
        uv * taauViewportScale,
        vec2(taauViewportScale) - 0.5 * viewPixelSize
    );
    float fogTransmittance = texture(colortex3, fogUv).x;
    sceneColor = mix(
        bloomColor,
        sceneColor,
        pow(fogTransmittance, bloomyFogIntensity)
    );
#endif
#endif


    const float exposureCalibration = 12.5 / 100.0 / 1.2;
    float triangle = max(cameraExposureTriangleFactor(), 1e-6);
    float triangleFree = exposure / triangle;
    float anchorLog = log2(0.18);
    if (triangleFree > 1e-6 && !isnan(triangleFree) && !isinf(triangleFree)) {
        anchorLog = log2(max(exposureCalibration / triangleFree, 1e-5));
    }

    sceneColor *= exposure;

#ifdef localExposure
    float localEv = computeLocalExposureEv(uv, anchorLog, exposure);
    sceneColor *= exp2(localEv);
#endif

#ifdef vignette
    sceneColor *= vignetteMask(uv);
#endif

#ifdef colorGrading
  #if gradeWhiteBalance != 6500
    sceneColor = colorGradeInput(sceneColor, whiteBalanceMatrix);
  #else
    sceneColor = colorGradeInput(sceneColor, mat3(1.0));
  #endif
#endif

#ifdef tonemapComparison
    sceneColor
        = uv.x < tonemapComparisonSplit ? tonemapLeft(sceneColor) : tonemapRight(sceneColor);
#else
    sceneColor = tonemap(sceneColor);
#endif

    sceneColor = clamp01(sceneColor * workingToDisplayColor);
#ifdef colorGrading
    sceneColor = colorGradeOutput(sceneColor);
#endif

}
