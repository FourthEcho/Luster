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

#if !defined INCLUDE_SSPT_INDIRECT_AO
#define INCLUDE_SSPT_INDIRECT_AO

float fetchFinishingAo(
    sampler2D aoBuffer,
    sampler2D aoDepthBuffer,
    vec2 uv,
    float linZ,
    bool isHand
) {
    if (isHand) {
        return 1.0;
    }

#if shaderAo == shaderAoNone
    return 1.0;
#else
    vec2 aoSize = vec2(textureSize(aoBuffer, 0));
    vec2 aoPos = uv * aoSize - 0.5;
    ivec2 base = ivec2(floor(aoPos));
    vec2 f = fract(aoPos);
    ivec2 maxTexel = ivec2(aoSize) - 1;

    vec4 aoTaps;
    aoTaps.x = texelFetch(aoBuffer, clamp(base, ivec2(0), maxTexel), 0).x;
    aoTaps.y = texelFetch(aoBuffer, clamp(base + ivec2(1, 0), ivec2(0), maxTexel), 0).x;
    aoTaps.z = texelFetch(aoBuffer, clamp(base + ivec2(0, 1), ivec2(0), maxTexel), 0).x;
    aoTaps.w = texelFetch(aoBuffer, clamp(base + ivec2(1, 1), ivec2(0), maxTexel), 0).x;

    vec4 aoDepths;
    aoDepths.x = texelFetch(aoDepthBuffer, clamp(base, ivec2(0), maxTexel), 0).x;
    aoDepths.y = texelFetch(aoDepthBuffer, clamp(base + ivec2(1, 0), ivec2(0), maxTexel), 0).x;
    aoDepths.z = texelFetch(aoDepthBuffer, clamp(base + ivec2(0, 1), ivec2(0), maxTexel), 0).x;
    aoDepths.w = texelFetch(aoDepthBuffer, clamp(base + ivec2(1, 1), ivec2(0), maxTexel), 0).x;

    vec4 tapViewDepth = vec4(
        screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.x),
        screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.y),
        screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.z),
        screenToViewSpaceDepth(combinedProjectionMatrixInverse, 1.0 - aoDepths.w)
    );

    vec4 dist = abs(tapViewDepth - linZ);

    vec4 w = exp2(-10.0 * dist);
    w.x *= (1.0 - f.x) * (1.0 - f.y);
    w.y *= f.x * (1.0 - f.y);
    w.z *= (1.0 - f.x) * f.y;
    w.w *= f.x * f.y;

    float wSum = w.x + w.y + w.z + w.w;

    if (wSum <= 1e-6) {
        // Full rejection (silhouette): use the depth-nearest tap so the AO
        // edge stays sharp instead of averaging across the depth break.
        float bestDist = dist.x;
        float bestAo = aoTaps.x;
        if (dist.y < bestDist) { bestDist = dist.y; bestAo = aoTaps.y; }
        if (dist.z < bestDist) { bestDist = dist.z; bestAo = aoTaps.z; }
        if (dist.w < bestDist) { bestAo = aoTaps.w; }
        return clamp01(bestAo);
    }

    return clamp01(dot(aoTaps, w) / wSum);
#endif
}

// Bilinear fetch of the octahedrally-encoded bent normal stored alongside
// the AO (deferred3: view-space xy in .zw, z reconstructed). With
// shaderAoNone the AO pass stores the flat view normal here, so the result
// is always a usable direction.
vec3 fetchBentNormalView(sampler2D aoBuffer, vec2 uv) {
    vec2 aoSize = vec2(textureSize(aoBuffer, 0));
    vec2 aoPos = uv * aoSize - 0.5;
    ivec2 base = ivec2(floor(aoPos));
    vec2 f = fract(aoPos);
    ivec2 maxTexel = ivec2(aoSize) - 1;

    vec2 nxy
        = texelFetch(aoBuffer, clamp(base, ivec2(0), maxTexel), 0).zw
              * ((1.0 - f.x) * (1.0 - f.y))
        + texelFetch(aoBuffer, clamp(base + ivec2(1, 0), ivec2(0), maxTexel), 0).zw
              * (f.x * (1.0 - f.y))
        + texelFetch(aoBuffer, clamp(base + ivec2(0, 1), ivec2(0), maxTexel), 0).zw
              * ((1.0 - f.x) * f.y)
        + texelFetch(aoBuffer, clamp(base + ivec2(1, 1), ivec2(0), maxTexel), 0).zw
              * (f.x * f.y);

    vec3 bentNormalView;
    bentNormalView.xy = nxy * 2.0 - 1.0;
    bentNormalView.z = sqrt(clamp01(1.0 - dot(bentNormalView.xy, bentNormalView.xy)));

    return normalize(bentNormalView);
}

#endif // INCLUDE_SSPT_INDIRECT_AO
