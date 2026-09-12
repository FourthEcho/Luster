#if !defined INCLUDE_POST_PROCESSING_SHARPENING
#define INCLUDE_POST_PROCESSING_SHARPENING

// Final-image sharpening: FidelityFX contrast-adaptive sharpening (CAS) plus
// an edge-aware sharpen pass.
//
// Requires from the including program:
//   - a sampler2D scene color sampler passed to each filter
//   - display_eotf from "/include/utility/color.glsl"
// The 5-argument min_of/max_of overloads come from "/include/global.glsl".

#include "/include/utility/color.glsl"

// FidelityFX contrast-adaptive sharpening filter
// https://github.com/GPUOpen-Effects/FidelityFX-CAS
// Edge-aware final image sharpening, independent from CAS.
vec3 image_sharpen_filter(
    sampler2D sampler,
    ivec2 texel,
    vec3 center,
    float amount
) {
    if (amount <= 0.0) return center;

    vec3 left  = display_eotf(texelFetch(sampler, texel + ivec2(-1, 0), 0).rgb);
    vec3 right = display_eotf(texelFetch(sampler, texel + ivec2( 1, 0), 0).rgb);
    vec3 up    = display_eotf(texelFetch(sampler, texel + ivec2(0, -1), 0).rgb);
    vec3 down  = display_eotf(texelFetch(sampler, texel + ivec2(0,  1), 0).rgb);

    vec3 neighborhood = 0.25 * (left + right + up + down);
    vec3 detail = center - neighborhood;
    vec3 sharpened = center + detail * (0.9 * amount);

    vec3 lo = min(min(left, right), min(up, down));
    vec3 hi = max(max(left, right), max(up, down));
    return clamp(sharpened, lo, hi);
}

vec3 cas_filter(sampler2D sampler, ivec2 texel, const float sharpness) {
#ifndef CAS
    return display_eotf(texelFetch(sampler, texel, 0).rgb);
#endif

    // Fetch 3x3 neighborhood
    // a b c
    // d e f
    // g h i
    vec3 a = texelFetch(sampler, texel + ivec2(-1, -1), 0).rgb;
    vec3 b = texelFetch(sampler, texel + ivec2(0, -1), 0).rgb;
    vec3 c = texelFetch(sampler, texel + ivec2(1, -1), 0).rgb;
    vec3 d = texelFetch(sampler, texel + ivec2(-1, 0), 0).rgb;
    vec3 e = texelFetch(sampler, texel, 0).rgb;
    vec3 f = texelFetch(sampler, texel + ivec2(1, 0), 0).rgb;
    vec3 g = texelFetch(sampler, texel + ivec2(-1, 1), 0).rgb;
    vec3 h = texelFetch(sampler, texel + ivec2(0, 1), 0).rgb;
    vec3 i = texelFetch(sampler, texel + ivec2(1, 1), 0).rgb;

    // Convert to sRGB before performing CAS
    a = display_eotf(a);
    b = display_eotf(b);
    c = display_eotf(c);
    d = display_eotf(d);
    e = display_eotf(e);
    f = display_eotf(f);
    g = display_eotf(g);
    h = display_eotf(h);
    i = display_eotf(i);

    // Soft min and max. These are 2x bigger (factored out the extra multiply)
    vec3 min_color = min_of(d, e, f, b, h);
    min_color += min_of(min_color, a, c, g, i);

    vec3 max_color = max_of(d, e, f, b, h);
    max_color += max_of(max_color, a, c, g, i);

    // Smooth minimum distance to the signal limit divided by smooth max
    vec3 w = clamp01(min(min_color, 2.0 - max_color) / max_color);
    w = 1.0 - sqr(1.0 - w); // Shaping amount of sharpening
    w *= -1.0 / mix(8.0, 5.0, sharpness);

    // Filter shape:
    // 0 w 0
    // w 1 w
    // 0 w 0
    vec3 weight_sum = 1.0 + 4.0 * w;
    return clamp01((b + d + f + h) * w + e) / weight_sum;
}

#endif // INCLUDE_POST_PROCESSING_SHARPENING
