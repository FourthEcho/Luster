#if !defined INCLUDE_LIGHTING_SSPT_TEMPORAL
#define INCLUDE_LIGHTING_SSPT_TEMPORAL

// Shared bookkeeping for the SSPT temporal passes (d5 accumulate + d6
// SVGF filter): half-res buffer helpers and the packed-gbuffer fetch.
//
// Requires from the including program:
//   - colortex19 sampler (packed normal + squared depth)
//   - view_res uniform
//   - sqr() from "/include/global.glsl", luminance weights from
//     "/include/utility/color.glsl".

#include "/include/utility/color.glsl"

// Half-res SSPT buffer bookkeeping (matches size.buffer.colortex17-20)
const float bufferScale = 0.5;

// Relative luminance in the pack's working color space (Rec. 2020).
float getLuma(vec3 c) {
    return dot(c, luminance_weights_rec2020);
}

vec2 bufferSize() {
    return view_res * bufferScale;
}

ivec2 clampTexel(ivec2 texel) {
    return clamp(texel, ivec2(0), ivec2(bufferSize()) - 1);
}

vec4 fetchGbuffer(ivec2 texel) {
    vec4 val = texelFetch(colortex19, texel, 0);
    return vec4(val.rgb * 2.0 - 1.0, sqr(val.a));
}

#endif // INCLUDE_LIGHTING_SSPT_TEMPORAL
