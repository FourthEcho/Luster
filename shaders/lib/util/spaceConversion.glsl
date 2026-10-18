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

#if !defined INCLUDE_UTILITY_SPACE_CONVERSION
#define INCLUDE_UTILITY_SPACE_CONVERSION

#include "/lib/lodMod.glsl"


// https://wiki.shaderlabs.org/wiki/Shader_tricks#Linearizing_depth


// Approximate linear depth function by DrDesten
float linearizeDepthFast(float near, float depth) {
    return near / (1.0 - depth);
}

float linearizeDepthFast(float depth) {
    return linearizeDepthFast(near, depth);
}

vec3 screenToViewSpace(
    mat4 projectionMatrixInverse,
    vec3 screenPos,
    bool handleJitter
) {
    vec3 ndcPos = 2.0 * screenPos - 1.0;

#ifdef taa
#ifdef taau
    vec2 jitterOffset = taaOffset * rcp(taauViewportScale);
#else
    vec2 jitterOffset = taaOffset * 0.66;
#endif

    if (handleJitter) {
        ndcPos.xy -= jitterOffset;
    }
#endif

    return projectAndDivide(projectionMatrixInverse, ndcPos);
}

vec3 viewToScreenSpace(
    mat4 projectionMatrix,
    vec3 viewPos,
    bool handleJitter
) {
    vec3 ndcPos = projectAndDivide(projectionMatrix, viewPos);

#ifdef taa
#ifdef taau
    vec2 jitterOffset = taaOffset * rcp(taauViewportScale);
#else
    vec2 jitterOffset = taaOffset * 0.66;
#endif

    if (handleJitter) {
        ndcPos.xy += jitterOffset;
    }
#endif

    return ndcPos * 0.5 + 0.5;
}

vec3 screenToViewSpace(vec3 screenPos, bool handleJitter) {
    return screenToViewSpace(
        gbufferProjectionInverse,
        screenPos,
        handleJitter
    );
}

vec3 viewToScreenSpace(vec3 viewPos, bool handleJitter) {
    return viewToScreenSpace(gbufferProjection, viewPos, handleJitter);
}

vec3 screenToViewSpace(
    vec3 screenPos,
    bool handleJitter,
    bool isLodTerrain
) {
#ifdef LOD_MOD_ACTIVE
    mat4 projectionMatrixInverse = isLodTerrain
        ? lodProjectionMatrixInverse
        : gbufferProjectionInverse;

    return screenToViewSpace(
        projectionMatrixInverse,
        screenPos,
        handleJitter
    );
#else
    return screenToViewSpace(
        gbufferProjectionInverse,
        screenPos,
        handleJitter
    );
#endif
}

vec3 viewToScreenSpace(
    vec3 viewPos,
    bool handleJitter,
    bool isLodTerrain
) {
#ifdef LOD_MOD_ACTIVE
    mat4 projectionMatrix
        = isLodTerrain ? lodProjectionMatrix : gbufferProjection;

    return viewToScreenSpace(projectionMatrix, viewPos, handleJitter);
#else
    return viewToScreenSpace(gbufferProjection, viewPos, handleJitter);
#endif
}

float screenToViewSpaceDepth(mat4 projectionMatrixInverse, float depth) {
    depth = depth * 2.0 - 1.0;
    vec2 zw = depth * projectionMatrixInverse[2].zw
        + projectionMatrixInverse[3].zw;
    return -zw.x / zw.y;
}

float viewToScreenSpaceDepth(mat4 projectionMatrix, float depth) {
    vec2 zw = -depth * projectionMatrix[2].zw + projectionMatrix[3].zw;
    return (zw.x / zw.y) * 0.5 + 0.5;
}

vec3 viewToSceneSpace(vec3 viewPos) {
    return transform(gbufferModelViewInverse, viewPos);
}

vec3 sceneToViewSpace(vec3 scenePos) {
    return transform(gbufferModelView, scenePos);
}

mat3 getTbnMatrix(vec3 normal) {
    vec3 tangent = abs(normal.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), normal));
    vec3 bitangent = normalize(cross(tangent, normal));
    return mat3(tangent, bitangent, normal);
}

#if defined TEMPORAL_REPROJECTION
vec3 reprojectSceneSpace(vec3 scenePos, bool hand, bool isLodTerrain) {
#ifdef LOD_MOD_ACTIVE
    mat4 previousProjectionMatrix = isLodTerrain
        ? lodPreviousProjectionMatrix
        : gbufferPreviousProjection;
#else
    mat4 previousProjectionMatrix = gbufferPreviousProjection;
#endif

    vec3 cameraOffset
        = hand ? vec3(0.0) : cameraPosition - previousCameraPosition;

    vec3 previousPos
        = transform(gbufferPreviousModelView, scenePos + cameraOffset);
    previousPos = projectAndDivide(previousProjectionMatrix, previousPos);

    return previousPos * 0.5 + 0.5;
}

vec3 reproject(vec3 screenPos, bool isLodTerrain) {
    vec3 pos = screenToViewSpace(screenPos, false, isLodTerrain);
    pos = viewToSceneSpace(pos);

    bool hand = screenPos.z < handDepth;

    return reprojectSceneSpace(pos, hand, isLodTerrain);
}

vec3 reproject(vec3 screenPos) { return reproject(screenPos, false); }

vec3 reproject(vec3 screenPos, sampler2D velocitySampler) {
    vec3 velocity
        = texelFetch(velocitySampler, ivec2(screenPos.xy * viewRes), 0).xyz;

    if (maxOf(abs(velocity)) < eps) {
        return reproject(screenPos);
    } else {
        vec3 pos = screenToViewSpace(screenPos, false);
        pos = pos - velocity;
        pos = viewToScreenSpace(pos, false);

        return pos;
    }
}
#endif

#endif // INCLUDE_UTILITY_SPACE_CONVERSION
