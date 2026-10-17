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

#if !defined INCLUDE_MISC_EDGE_HIGHLIGHT
#define INCLUDE_MISC_EDGE_HIGHLIGHT

#include "/lib/util/encoding.glsl"
#include "/lib/util/spaceConversion.glsl"

// MC Dungeons-inspired edge highlight effect

bool hasEdgeHighlight(vec3 normal) {
    // Returns true for faces pointing along an axis
    return abs(dot(abs(normal), vec3(1.0)) - 1.0) < 0.1;
}

float edgeHighlightCheck(
    vec3 offset,
    vec3 centerPos,
    vec3 centerNormal,
    float centerDepth,
    float rcp_NoV,
    vec2 depthGradient
) {
    // Calculate sample position in screen space
    vec3 samplePos = sceneToViewSpace(centerPos + offset);
    samplePos
        = viewToScreenSpace(combinedProjectionMatrix, samplePos, true);

    // Sample depth and gbuffer data
    ivec2 texel = ivec2(samplePos.xy * viewRes * taauViewportScale);
    float sampleDepth = texelFetch(combinedDepthTex, texel, 0).x;
    float sampleData = texelFetch(colortex1, texel, 0).z;

    // Test for depth discontinuity
    sampleDepth = linearizeDepthFast(sampleDepth);
    float expectedDepth
        = centerDepth + dot(depthGradient, samplePos.xy - uv);
    float depthEdge = float(
        abs(sampleDepth - expectedDepth) > 0.25 * rcp_NoV
        && expectedDepth < sampleDepth
    );

    // Test for normal discontinuity
    vec3 sampleNormal = decodeUnitVector(unpackUnorm2x8(sampleData));
    float normalEdge = float(
        abs(dot(centerNormal, sampleNormal)) < 0.99
        && dot(sampleNormal, normalize(offset)) > 0.01
    );

    return (depthEdge + normalEdge) * float(clamp01(samplePos) == samplePos)
        * float(
               hasEdgeHighlight(sampleNormal) || centerDepth < sampleDepth
        );
}

float getEdgeHighlight(
    vec3 scenePos,
    vec3 worldNormal,
    float depth,
    uint materialMask
) {
    // Size of one block pixel in world-space
    const float pixelSize = rcp(edgeHighlightScale);

    // Calculate tangent and bitangent
    mat3 tbn = getTbnMatrix(worldNormal) * pixelSize;


    float depthLinear = linearizeDepthFast(depth);
    vec2 depthGradient = vec2(dFdx(depthLinear), dFdy(depthLinear));

    float rcp_NoV = abs(rcp(dot(normalize(scenePos), worldNormal)));

    // Check for an edge in 5 directions around the sample point
    float highlight = edgeHighlightCheck(
        tbn[0],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        -tbn[0],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        tbn[1],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        -tbn[1],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        tbn[2],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );

    return clamp01(float(hasEdgeHighlight(worldNormal)) * highlight);
}

#endif // INCLUDE_MISC_EDGE_HIGHLIGHT
