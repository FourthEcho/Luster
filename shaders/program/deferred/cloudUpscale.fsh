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

layout(location = 0) out vec4 cloudsHistory;
layout(location = 1) out vec3 cloudsData;

/* RENDERTARGETS: 11,12 */

#ifdef LOD_MOD_ACTIVE
layout(location = 2) out float combinedDepth;

/* RENDERTARGETS: 11,12,15 */
#endif

in vec2 uv;

// ------------
//   Uniforms
// ------------


uniform sampler2D colortex14; // previous frame depth
uniform sampler2D colortex9; // low-res clouds
uniform sampler2D colortex10; // low-res clouds apparent distance
uniform sampler2D colortex11; // clouds history
uniform sampler2D colortex12; // clouds data

uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;
uniform float eyeAltitude;

uniform int moonPhase;
uniform int frameCounter;
uniform float frameTime;

uniform vec3 lightDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;
uniform vec2 cloudsOffset;

uniform bool daylightCycleEnabled;
uniform bool worldAgeChanged;

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION

#include "/lib/lodMod.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/checkerboard.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/geometry.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

vec4 minOf(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e) {
    return min(a, min(b, min(c, min(d, e))));
}

vec4 maxOf(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e) {
    return max(a, max(b, max(c, max(d, e))));
}

float textureMin4x4(sampler2D s, vec2 coord) {
    vec2 pixelSize = rcp(textureSize(s, 0).xy);

    vec4 samples0 = textureGather(
        s,
        coord + vec2(2.0 * pixelSize.x, 2.0 * pixelSize.y)
    );
    vec4 samples1 = textureGather(
        s,
        coord + vec2(-2.0 * pixelSize.x, 2.0 * pixelSize.y)
    );
    vec4 samples2 = textureGather(
        s,
        coord + vec2(2.0 * pixelSize.x, -2.0 * pixelSize.y)
    );
    vec4 samples3 = textureGather(
        s,
        coord + vec2(-2.0 * pixelSize.x, -2.0 * pixelSize.y)
    );

    return min(
        min(minOf(samples0), minOf(samples1)),
        min(minOf(samples2), minOf(samples3))
    );
}

vec3 reprojectClouds(vec2 uv, float distanceToCloud) {
    const float planetRadius = 6371e3;
    const float cloudsCumulusRadius = planetRadius + cloudsCumulusAltitude;
    const float cloudsAltocumulusRadius
        = planetRadius + cloudsAltocumulusAltitude;
    const float cloudsCirrusRadius = planetRadius + cloudsCirrusAltitude;
    const float cumulusWindAngleRad = cloudsCumulusWindAngle * degree;
    const float altocumulusWindAngleRad
        = cloudsAltocumulusWindAngle * degree;
    const float cirrusWindAngleRad = cloudsCirrusWindAngle * degree;
    const vec3 cloudsCumulusVelocity = cloudsCumulusWindSpeed
        * vec3(cos(cumulusWindAngleRad),
               0.0,
               sin(cumulusWindAngleRad));
    const vec3 cloudsAltocumulusVelocity = cloudsAltocumulusWindSpeed
        * vec3(cos(altocumulusWindAngleRad),
               0.0,
               sin(altocumulusWindAngleRad));
    const vec3 cloudsCirrusVelocity = cloudsCirrusWindSpeed
        * vec3(cos(cirrusWindAngleRad),
               0.0,
               sin(cirrusWindAngleRad));

    vec3 viewPos = screenToViewSpace(vec3(uv, 1.0), false, false);
    vec3 scenePos = viewToSceneSpace(viewPos);
    vec3 worldDir = normalize(scenePos - gbufferModelViewInverse[3].xyz);

    vec3 cloudPos
        = worldDir * distanceToCloud + gbufferModelViewInverse[3].xyz;

    // Work out which layer this cloud belongs to
    vec3 velocity;
    vec3 airCloudPos
        = vec3(
              0.0,
              cloudsScale * (eyeAltitude - 63.0) + planetRadius,
              0.0
          )
        + cloudsScale * cloudPos;
    float r = length(airCloudPos);

    if (r < cloudsAltocumulusRadius) {
        velocity = cloudsCumulusVelocity;
    } else if (r < cloudsCirrusRadius) {
        velocity = cloudsAltocumulusVelocity;
    } else {
        velocity = cloudsCirrusVelocity;
    }

    cloudPos += velocity * frameTime * rcp(cloudsScale)
        * float(daylightCycleEnabled);

    return reprojectSceneSpace(cloudPos, false, false);
}

void main() {
    const int checkerboardArea
        = cloudsTemporalUpscaling * cloudsTemporalUpscaling;

    ivec2 dstTexel = ivec2(gl_FragCoord.xy);
    ivec2 srcTexel = clamp(
        dstTexel / cloudsTemporalUpscaling,
        ivec2(0),
        ivec2(vec2(textureSize(colortex9, 0).xy) * taauViewportScale - 1.0)
    );

    vec4 current = texelFetch(colortex9, srcTexel, 0);
    vec2 currentData = texelFetch(colortex10, srcTexel, 0).xy;
    float depth = texelFetch(depthtex1, dstTexel, 0).x;

    bool isHand;
    fixHandDepth(depth, isHand);

    // -----------------------------------------
    //   combined depth buffer for LoD terrain
    // -----------------------------------------

#ifdef LOD_MOD_ACTIVE
    // Check for LoD terrain
    float depthLod = texelFetch(lodDepthTexShading, dstTexel, 0).x;
    bool isLod = isLodTerrain(depth, depthLod);

    float depthLinear
        = screenToViewSpaceDepth(gbufferProjectionInverse, depth);
    float depthLinearDh
        = screenToViewSpaceDepth(lodProjectionMatrixInverse, depthLod);

    combinedDepth = isLod
        ? viewToScreenSpaceDepth(
              combinedProjectionMatrix,
              depthLinearDh
          )
        : viewToScreenSpaceDepth(combinedProjectionMatrix, depthLinear);

    if (depth >= 1.0 && !isLod) {
        // Sky
        combinedDepth = 1.0;
    } else if (isHand) {
        // 0 signals hand
        combinedDepth = 0.0;
    }
#else
    const bool isLod = false;
#endif

    // --------------------
    //   clouds upscaling
    // --------------------

#if !defined WORLD_OVERWORLD
    return;
#endif

#if defined taau
    // Fixes issue at the top and left side of the screen with taau
    vec2 uvClamped = clamp(uv, 0.0, 0.95);
#else
#define uvClamped uv
#endif

    float apparentDistance = currentData.x;
    float ambientScattering = currentData.y;

    // Find the closest cloud distance between the current frame and a 4x4 area
    // of the previous frame
    float closestDistance = min(
        apparentDistance,
        textureMin4x4(colortex12, uvClamped * taauViewportScale)
    );

    // Early exit if clouds covered by terrain
    if (depth != 1.0) {
        float viewDistanceSquared
            = lengthSquared(screenToViewSpace(vec3(uv, depth), true));
        if (viewDistanceSquared < sqr(closestDistance) || isHand) {
            cloudsHistory = current;
            cloudsData.x = 1e6; // apparent distance
            cloudsData.y = 0.0; // pixel age
            cloudsData.z = 0.0; // ambient scattering
            return;
        }
    }

    // Reproject clouds
    vec2 previousUv = reprojectClouds(uv, closestDistance).xy;

#ifdef taau
    vec2 previousUvClamped = clamp(
        previousUv,
        vec2(0.0),
        1.0 - 2.0 * viewPixelSize / taauViewportScale
    );
#else
#define previousUvClamped previousUv
#endif

    vec4 history = max0(catmullRomFilterFast(
        colortex11,
        previousUvClamped * taauViewportScale,
        0.5
    ));
    vec3 historyData
        = texture(colortex12, previousUvClamped * taauViewportScale).xyz;

    // Depth at the previous position
    float historyDepth
        = 1.0 - maxOf(textureGather(colortex14, previousUvClamped, 0));

    // Get distance to terrain in the previous frame
    float distanceToTerrainSquared = lengthSquared(screenToViewSpace(
        combinedProjectionMatrixInverse,
        vec3(previousUv, historyDepth),
        true
    ));

    // Work out whether the history should be invalidated
    bool disocclusion = clamp01(previousUv) != previousUv;
    disocclusion = disocclusion
        || (historyDepth < 1.0
            && distanceToTerrainSquared < sqr(closestDistance));
    disocclusion = disocclusion || historyDepth == 0.0; // Signals hand
    disocclusion = disocclusion || any(isnan(history));
    disocclusion = disocclusion || worldAgeChanged;

    // Replace history if a disocclusion was detected
    if (disocclusion) {
        history = current;
        history.z = ambientScattering;
    }

    // Perform neighbourhood clamping when moving quickly relative to the clouds
    float velocity = rcp(sqr(frameTime))
        * lengthSquared(cameraPosition - previousCameraPosition);
    float velocityFactor = 75.0 * velocity / max(sqr(closestDistance), eps);
    velocityFactor = velocityFactor / (velocityFactor + 1.0);

    if (velocityFactor > 0.1) {
        // Fetch 3x3 neighborhood
        vec4 a = texelFetch(colortex9, srcTexel + ivec2(-1, -1), 0);
        vec4 b = texelFetch(colortex9, srcTexel + ivec2(0, -1), 0);
        vec4 c = texelFetch(colortex9, srcTexel + ivec2(1, -1), 0);
        vec4 d = texelFetch(colortex9, srcTexel + ivec2(-1, 0), 0);
        vec4 f = texelFetch(colortex9, srcTexel + ivec2(1, 0), 0);
        vec4 g = texelFetch(colortex9, srcTexel + ivec2(-1, 1), 0);
        vec4 h = texelFetch(colortex9, srcTexel + ivec2(0, 1), 0);
        vec4 i = texelFetch(colortex9, srcTexel + ivec2(1, 1), 0);
        vec4 e = current;


        vec4 aabbMin = minOf(b, d, e, f, h);
        aabbMin += minOf(aabbMin, a, c, g, i);
        aabbMin *= 0.5;
        aabbMin = max0(aabbMin);

        vec4 aabbMax = maxOf(b, d, e, f, h);
        aabbMax += maxOf(aabbMax, a, c, g, i);
        aabbMax *= 0.5;
        aabbMax = max0(aabbMax);

        history
            = mix(history, clamp(history, aabbMin, aabbMax), velocityFactor);
    }

    // Get previous pixel age and apparent distance
    float apparentDistanceHistory = historyData.x;
    apparentDistanceHistory
        = disocclusion ? apparentDistance : apparentDistanceHistory;

    // Checkerboard upscaling
    ivec2 offset0 = dstTexel % cloudsTemporalUpscaling;
    ivec2 offset1
        = cloudsCheckerboardOffsets[frameCounter % checkerboardArea];
    if (offset0 != offset1 && !disocclusion) {
        current = history;
        apparentDistance = min(apparentDistance, apparentDistanceHistory);
        ambientScattering = historyData.z;
    }

    float pixelAge = max0(historyData.y) * float(!disocclusion);
    float historyWeight = 1.0 - rcp(max(pixelAge - checkerboardArea, 1.0));

#ifndef taau
    // Offcenter rejection
    vec2 pixelCenterOffset
        = 1.0 - abs(fract(previousUv * viewRes) * 2.0 - 1.0);
    float offcenterRejection
        = sqrt(pixelCenterOffset.x * pixelCenterOffset.y);
    offcenterRejection = mix(1.0, offcenterRejection, historyWeight);

    historyWeight *= offcenterRejection;
#endif

    cloudsHistory = max0(mix(current, history, historyWeight));
    cloudsData.x
        = mix(apparentDistance, apparentDistanceHistory, historyWeight);
    cloudsData.y = min(++pixelAge, cloudsAccumLimit);
    cloudsData.z = mix(ambientScattering, historyData.z, historyWeight);
}
