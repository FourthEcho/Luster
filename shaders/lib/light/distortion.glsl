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

#if !defined INCLUDE_LIGHTING_DIRECT_LIGHTING_DISTORTION
#define INCLUDE_LIGHTING_DIRECT_LIGHTING_DISTORTION

#include "/lib/util/fastMath.glsl"

// Euclidean distance is sqrt(a^2 + b^2 + ...). This function instead
// computes quartic_root(a^4 + b^4 + ...) -> smaller distances on diagonals
float quartic_length(vec2 v) { return sqrt(sqrt(pow4(v.x) + pow4(v.y))); }

float get_distortion_factor(vec2 shadow_clip_pos) {
    return quartic_length(shadow_clip_pos) * shadowDistortion
        + (1.0 - shadowDistortion);
}

vec3 distort_shadow_space(vec3 shadow_clip_pos, float distortion_factor) {
    return shadow_clip_pos
        * vec3(vec2(rcp(distortion_factor)), shadowDepthScale);
}

vec3 distort_shadow_space(vec3 shadow_clip_pos) {
    float distortion_factor = get_distortion_factor(shadow_clip_pos.xy);
    return distort_shadow_space(shadow_clip_pos, distortion_factor);
}

// Shadow bias method from Complementary Reimagined by Emin

// https://www.complementary.dev/reimagined
vec3 get_shadow_bias(vec3 scene_pos, vec3 normal, float NoL, float skylight) {
#if defined WORLD_END
    skylight = 1.0;
#endif

    // Shadow bias without peter-panning
    return 0.25 * normal * clamp01(0.12 + 0.01 * length(scene_pos))
        * (2.0 - clamp01(NoL));
}

#endif // INCLUDE_LIGHTING_DIRECT_LIGHTING_DISTORTION
