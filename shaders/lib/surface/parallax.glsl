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

#if !defined INCLUDE_SURFACE_PARALLAX
#define INCLUDE_SURFACE_PARALLAX

vec2 getUvFromLocalCoord(vec2 localCoord) {
    return atlasTileOffset + atlasTileScale * fract(localCoord);
}

vec2 getLocalCoordFromUv(vec2 uv) {
    return (uv - atlasTileOffset) * rcp(atlasTileScale);
}

float getHeightValue(vec2 localCoord, mat2 uvGradient) {
    vec2 uv = getUvFromLocalCoord(localCoord);
    return textureGrad(normals, uv, uvGradient[0], uvGradient[1]).w;
}

float getDepthValue(vec2 localCoord, mat2 uvGradient) {
    return 1.0 - getHeightValue(localCoord, uvGradient);
}


float getPomDistanceFade(float viewDistance) {
    return linearStep(0.75 * pomDistance, pomDistance, viewDistance);
}

float getPomReliefScale(float viewDistance) {
    return 1.0 - getPomDistanceFade(viewDistance);
}


float getPomWorldRelief(float pomDepthNorm, float viewDistance) {
    return pomDepthNorm * pomDepth * getPomReliefScale(viewDistance);
}

vec3 getPomSlopeNormal(vec2 localCoord, mat2 uvGradient) {


    vec2 texel = rcp(atlasTileScale * vec2(textureSize(normals, 0)));


    vec2 uvFootprint = vec2(
        max(abs(uvGradient[0].x), abs(uvGradient[1].x)),
        max(abs(uvGradient[0].y), abs(uvGradient[1].y))
    );
    vec2 sampleStep = max(texel, uvFootprint * rcp(atlasTileScale));
    sampleStep = min(sampleStep, vec2(0.25));

    float depthDx
        = (getDepthValue(localCoord + vec2(sampleStep.x, 0.0), uvGradient)
         - getDepthValue(localCoord - vec2(sampleStep.x, 0.0), uvGradient))
        * rcp(2.0 * sampleStep.x);
    float depthDy
        = (getDepthValue(localCoord + vec2(0.0, sampleStep.y), uvGradient)
         - getDepthValue(localCoord - vec2(0.0, sampleStep.y), uvGradient))
        * rcp(2.0 * sampleStep.y);

    // The pom height field is displaced by pomDepth in tangent space.


    return vec3(pomDepth * depthDx, pomDepth * depthDy, 0.0);
}

vec2 getParallaxUv(
    vec3 tangentDir,
    mat2 uvGradient,
    float viewDistance,
    float dither,
    out vec3 previousRayPos,
    out float pomDepthNorm
) {
    const float depthStep = rcp(float(pomSamples));

    // Perform one pom step at the original position, fixes pom tiling
    // Thanks to Null for teaching me this
    float depthValue = getDepthValue(atlasTileCoord, uvGradient);
    if (depthValue < rcp(255.0)) {
        previousRayPos = vec3(atlasTileCoord, 0.0);
        pomDepthNorm = 0.0;
        return uv;
    }

    float reliefScale = getPomReliefScale(viewDistance);

    vec3 rayStep = vec3(
                        tangentDir.xy * rcp(-tangentDir.z) * pomDepth
                            * reliefScale,
                        1.0
                    )
        * depthStep;
    vec3 currPos = vec3(atlasTileCoord + rayStep.xy * dither, 0.0);
    vec3 prevPos = currPos;

    // Signed distance of the ray above the height field: > 0 while the ray
    // is still above the surface, <= 0 once it has gone under it.
    float currDiff = getDepthValue(currPos.xy, uvGradient) - currPos.z;
    float prevDiff = currDiff;

    for (int i = 0; i < pomSamples && currDiff > 0.0; ++i) {
        prevPos = currPos;
        prevDiff = currDiff;
        currPos += rayStep;
        currDiff = getDepthValue(currPos.xy, uvGradient) - currPos.z;
    }


    float hitT = clamp01(prevDiff * rcp(max(prevDiff - currDiff, 1e-5)));
    vec3 hitPos = mix(prevPos, currPos, hitT);

    previousRayPos = prevPos;
    pomDepthNorm = clamp01(hitPos.z);

    return getUvFromLocalCoord(hitPos.xy);
}

bool getParallaxShadow(
    vec3 pos,
    mat2 uvGradient,
    float viewDistance,
    float dither
) {
    float reliefScale = getPomReliefScale(viewDistance);

    vec3 tangentDir = lightDir * tbn;
    vec3 rayStep = vec3(
                        tangentDir.xy * rcp(tangentDir.z) * pomDepth
                            * reliefScale,
                        -1.0
                    )
        * pos.z * rcp(float(pomShadowSamples));

    pos.xy += rayStep.xy * dither;

    float maxHeight = getDepthValue(pos.xy, uvGradient);
    for (int i = 0; i < pomShadowSamples; ++i) {
        pos += rayStep;
        float offsetHeight = getDepthValue(pos.xy, uvGradient);
        float diff = pos.z - offsetHeight;
        if (diff > 0.0 && maxHeight - offsetHeight > eps) {
            return true;
        }
    }

    return false;
}

#endif // INCLUDE_SURFACE_PARALLAX
