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

#if !defined INCLUDE_LIGHT_DIRECT_LIGHT_DISTORTION
#define INCLUDE_LIGHT_DIRECT_LIGHT_DISTORTION

#include "/lib/util/fastMath.glsl"

// Euclidean distance is sqrt(a^2 + b^2 + ...). This function instead
// computes quarticRoot(a^4 + b^4 + ...) -> smaller distances on diagonals
float quarticLength(vec2 v) { return sqrt(sqrt(pow4(v.x) + pow4(v.y))); }

float getDistortionFactor(vec2 shadowClipPos) {
    return quarticLength(shadowClipPos) * shadowDistortion
        + (1.0 - shadowDistortion);
}

vec3 distortShadowSpace(vec3 shadowClipPos, float distortionFactor) {
    return shadowClipPos
        * vec3(vec2(rcp(distortionFactor)), shadowDepthScale);
}

vec3 distortShadowSpace(vec3 shadowClipPos) {
    float distortionFactor = getDistortionFactor(shadowClipPos.xy);
    return distortShadowSpace(shadowClipPos, distortionFactor);
}

// Shadow bias method from Complementary Reimagined by Emin

// https://www.complementary.dev/reimagined
vec3 getShadowBias(vec3 scenePos, vec3 normal, float NoL, float skylight) {
#if defined WORLD_END
    skylight = 1.0;
#endif

    // Shadow bias without peter-panning
    return 0.25 * normal * clamp01(0.12 + 0.01 * length(scenePos))
        * (2.0 - clamp01(NoL));
}

#endif // INCLUDE_LIGHT_DIRECT_LIGHT_DISTORTION
