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

layout(location = 0) out vec3 bloomInput;
layout(location = 1) out vec4 result;

/* RENDERTARGETS: 0,5 */

in vec2 uv;

flat in float exposure;

#if debugView == debugViewHistogram
flat in vec4[histogramBins / 4] histogramPdf;
flat in float histogramSelectedBin;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color
uniform sampler2D colortex5; // Scene history

#ifdef taau
uniform sampler2D colortex1; // taa min color
uniform sampler2D colortex2; // taa max color
#endif

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

#include "/lib/util/lodMod.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/spaceConversion.glsl"

#define TAA_VARIANCE_CLIPPING // More aggressive neighborhood clipping method
                              // which further reduces ghosting but can
                              // introduce flickering artifacts
#define TAA_OFFCENTER_REJECTION \
    0.25 // Reduces blur when moving quickly. Too much offcenter rejection
         // results in aliasing and jittering in motion
#define TAAU_CONFIDENCE_REJECTION \
    5.0 // Controls the impact of the "confidence-of-quality" factor on temporal
        // upscaling. Tradeoff between image clarity and time taken to converge
#define TAAU_FLICKER_REDUCTION \
    1.0 // Increases ghosting but reduces flickering caused by aggressive
        // clipping

#if !defined INCLUDE_POST_TAA
#define INCLUDE_POST_TAA


// Reinhard operator used to blend in SDR.


// Respects TAA_VARIANCE_CLIPPING when defined by the includer before this


#include "/lib/util/color.glsl"

// Invertible tonemapping operator (Reinhard) applied before blending the
// current and previous frames Improves the appearance of emissive objects
vec3 reinhard(vec3 rgb) { return rgb / (rgb + 1.0); }

vec3 reinhardInverse(vec3 rgb) { return rgb / (1.0 - rgb); }

// Estimates the closest fragment in a 5x5 radius with 5 samples in a cross
// pattern Improves reprojection for objects in motion
vec3 getClosestFragment(sampler2D depthSampler, ivec2 texel0) {
    ivec2 texel1 = texel0 + ivec2(-2, -2);
    ivec2 texel2 = texel0 + ivec2(2, -2);
    ivec2 texel3 = texel0 + ivec2(-2, 2);
    ivec2 texel4 = texel0 + ivec2(2, 2);

    float depth0 = texelFetch(depthSampler, texel0, 0).x;
    float depth1 = texelFetch(depthSampler, texel1, 0).x;
    float depth2 = texelFetch(depthSampler, texel2, 0).x;
    float depth3 = texelFetch(depthSampler, texel3, 0).x;
    float depth4 = texelFetch(depthSampler, texel4, 0).x;

    vec3 pos = depth0 < depth1 ? vec3(texel0, depth0) : vec3(texel1, depth1);
    vec3 pos1 = depth2 < depth3 ? vec3(texel2, depth2) : vec3(texel3, depth3);
    pos = pos.z < pos1.z ? pos : pos1;
    pos = pos.z < depth4 ? pos : vec3(texel4, depth4);

    return vec3(
        (pos.xy + 0.5) * viewPixelSize * rcp(taauViewportScale),
        pos.z
    );
}

// AABB clipping from "Temporal Reprojection Anti-Aliasing in INSIDE"
vec3 clipAabb(
    vec3 historyColor,
    vec3 minColor,
    vec3 maxColor,
    out bool historyClipped
) {
    vec3 pClip = 0.5 * (maxColor + minColor);
    vec3 eClip = 0.5 * (maxColor - minColor);

    vec3 vClip = historyColor - pClip;
    vec3 vUnit = vClip / max(eClip, 1e-3);
    vec3 aUnit = abs(vUnit);
    float maUnit = maxOf(aUnit);
    historyClipped = maUnit > 1.0;

    return historyClipped ? pClip + vClip / maUnit : historyColor;
}

vec3 clipAabb(vec3 historyColor, vec3 minColor, vec3 maxColor) {
    bool historyClipped;
    return clipAabb(historyColor, minColor, maxColor, historyClipped);
}

// Flicker reduction using the "distance to clamp" method from "High Quality
// Temporal Supersampling" by Brian Karis. Only used for taau
float getFlickerReduction(
    vec3 historyColor,
    vec3 minColor,
    vec3 maxColor
) {
    const float flickerSensitivity = 5.0;

    vec3 minOffset = (historyColor - minColor);
    vec3 maxOffset = (maxColor - historyColor);

    float distanceToClip
        = length(min(minOffset, maxOffset)) * flickerSensitivity * exposure;
    return clamp01(distanceToClip);
}

vec3 neighborhoodClipping(
    ivec2 texel,
    vec3 currentColor,
    vec3 historyColor,
    float distanceFactor
) {
    vec3 minColor, maxColor;

    // Fetch 3x3 neighborhood
    // a b c
    // d e f
    // g h i
    vec3 a = texelFetch(colortex0, texel + ivec2(-1, 1), 0).rgb;
    vec3 b = texelFetch(colortex0, texel + ivec2(0, 1), 0).rgb;
    vec3 c = texelFetch(colortex0, texel + ivec2(1, 1), 0).rgb;
    vec3 d = texelFetch(colortex0, texel + ivec2(-1, 0), 0).rgb;
    vec3 e = currentColor;
    vec3 f = texelFetch(colortex0, texel + ivec2(1, 0), 0).rgb;
    vec3 g = texelFetch(colortex0, texel + ivec2(-1, -1), 0).rgb;
    vec3 h = texelFetch(colortex0, texel + ivec2(0, -1), 0).rgb;
    vec3 i = texelFetch(colortex0, texel + ivec2(1, -1), 0).rgb;

    // Convert to YCoCg


    a = rgbToYcocg(reinhard(a));
    b = rgbToYcocg(reinhard(b));
    c = rgbToYcocg(reinhard(c));
    d = rgbToYcocg(reinhard(d));
    e = rgbToYcocg(reinhard(e));
    f = rgbToYcocg(reinhard(f));
    g = rgbToYcocg(reinhard(g));
    h = rgbToYcocg(reinhard(h));
    i = rgbToYcocg(reinhard(i));


    // family; cf. Yang et al., "A Survey of Temporal Antialiasing


    minColor = minOf(b, d, e, f, h);
    minColor += minOf(minColor, a, c, g, i);
    minColor *= 0.5;

    maxColor = maxOf(b, d, e, f, h);
    maxColor += maxOf(maxColor, a, c, g, i);
    maxColor *= 0.5;

#ifdef TAA_VARIANCE_CLIPPING
    // Variance clipping ("An Excursion in Temporal Supersampling")
    mat2x3 moments;
    moments[0] = (1.0 / 9.0) * (a + b + c + d + e + f + g + h + i);
    moments[1] = (1.0 / 9.0)
        * (a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h
           + i * i);

    // Strictness parameter, higher gamma => more temporally stable but more
    // ghosting
    float gamma = mix(0.75, 1.25, linearStep(0.25, 1.0, distanceFactor));

    vec3 mu = moments[0];
    vec3 sigma = sqrt(moments[1] - moments[0] * moments[0]);

    minColor = max(minColor, mu - gamma * sigma);
    maxColor = min(maxColor, mu + gamma * sigma);
#endif


    historyColor = rgbToYcocg(historyColor);
    historyColor = clipAabb(historyColor, minColor, maxColor);
    historyColor = ycocgToRgb(historyColor);

    return historyColor;
}

#endif // INCLUDE_POST_TAA

// Mip chain on the scene color, needed by the vertex stage auto-exposure
// histogram below (it taps colortex0 with textureLod).
#ifdef autoExposure
const bool colortex0MipmapEnabled = true;
#endif

#if defined(autoExposure) \
    && debugView == debugViewHistogram
void drawHistogram(ivec2 texel) {
    const int width = 512;
    const int height = 256;

    const vec3 white = vec3(1.0);
    const vec3 black = vec3(0.0);
    const vec3 red = vec3(1.0, 0.0, 0.0);

    vec2 coord = texel / vec2(width, height);

    if (all(lessThan(texel, ivec2(width, height)))) {
        int index = int(histogramBins * coord.x);
        float thresh = coord.y;

        result.rgb
            = histogramPdf[index >> 2][index & 3] > thresh ? black : white;

        float median = max0(1.0 - abs(index - histogramSelectedBin));
        result.rgb = mix(result.rgb, red, median) / exposure;
    }
}
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy * taauViewportScale);

#ifdef taa
#ifndef LOD_MOD_ACTIVE
    vec3 closest = getClosestFragment(depthtex0, texel);

    const bool isLod = false;
#else
    vec3 closest = getClosestFragment(depthtex0, texel);
    vec3 closestLod = getClosestFragment(lodDepthTex, texel);

    bool isLod = isLodTerrain(closest.z, closestLod.z);

    closest = isLod ? closestLod : closest;
#endif

    vec3 closestView = screenToViewSpace(closest, false, isLod);
    vec3 closestScene = viewToSceneSpace(closestView);

    bool hand = closest.z < handDepth;

    vec2 velocity
        = closest.xy - reprojectSceneSpace(closestScene, hand, isLod).xy;
    vec2 previousUv = uv - velocity;

    vec3 historyColor
        = catmullRomFilterFastRgb(colortex5, previousUv, 0.6);
    historyColor = max0(historyColor); // Eliminate NaNs in the history

    float pixelAge = texelFetch(colortex5, ivec2(previousUv * viewRes), 0).a;
    pixelAge
        = max0(pixelAge * float(clamp01(previousUv) == previousUv) + 1.0);

    // Distance factor to favour responsiveness closer to the camera and image
    // stability further away
    float distanceFactor = 1.0 - exp2(-0.025 * length(closestView));


    float blendWeight = mix(0.35, 0.10, distanceFactor) * rcp(1.00);
    float alpha = max(1.0 / pixelAge, blendWeight);

#ifndef taau
    // Native resolution taa
    vec3 currentColor = texelFetch(colortex0, texel, 0).rgb;


    currentColor = reinhard(currentColor);
    historyColor = reinhard(historyColor);

    historyColor = neighborhoodClipping(
        texel,
        currentColor,
        historyColor,
        distanceFactor
    );
#else
    // Temporal upscaling
    vec2 pos = clamp01(uv + 0.5 * taaOffset * rcp(taauViewportScale))
        * taauViewportScale;

    float confidence; // Confidence-of-quality factor, see "A Survey of Temporal
                      // Antialiasing Techniques" section 5.1
    vec3 currentColor = catmullRomFilter(colortex0, pos, confidence).rgb;

    if (minOf(currentColor) < 0.0) {
        // Fix negatives arising around very dark objects
        currentColor = texture(colortex0, pos).rgb;
    }

    currentColor = reinhard(currentColor);
    historyColor = reinhard(historyColor);

    // Interpolate AABB bounds across pixels
    vec3 minColor = texture(colortex1, pos).rgb * 2.0 - 1.0;
    vec3 maxColor = texture(colortex2, pos).rgb * 2.0 - 1.0;

    bool historyClipped;
    historyColor = rgbToYcocg(historyColor);
    historyColor
        = clipAabb(historyColor, minColor, maxColor, historyClipped);
    float flickerReduction = historyClipped
        ? 0.0
        : getFlickerReduction(historyColor, minColor, maxColor);
    historyColor = ycocgToRgb(historyColor);

    alpha *= pow(confidence, TAAU_CONFIDENCE_REJECTION);
    alpha *= 1.0 - TAAU_FLICKER_REDUCTION * flickerReduction;
#endif

    // Offcenter rejection from Jessie, which is originally by Zombye
    // Reduces blur in motion
    vec2 pixelOffset = 1.0 - abs(2.0 * fract(viewRes * previousUv) - 1.0);
    float offcenterRejection
        = sqrt(pixelOffset.x * pixelOffset.y) * TAA_OFFCENTER_REJECTION
        + (1.0 - TAA_OFFCENTER_REJECTION);

    alpha = 1.0 - alpha;
    alpha *= offcenterRejection;
    alpha = 1.0 - alpha;

    currentColor = mix(historyColor, currentColor, alpha);
    currentColor = reinhardInverse(currentColor);

    result = vec4(currentColor, pixelAge * offcenterRejection);
#else // taa disabled
    result = texelFetch(colortex0, texel, 0);
#endif

    // Store exposure in the alpha component of the bottom left texel of the
    // history buffer
    if (texel == ivec2(0)) {
        result.a = exposure;
    }

#if defined(autoExposure) \
    && debugView == debugViewHistogram
    drawHistogram(texel);
#endif

    bloomInput = result.rgb;
}
