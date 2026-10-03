#if !defined INCLUDE_CAMERA_LOCAL_EXPOSURE
#define INCLUDE_CAMERA_LOCAL_EXPOSURE

#include "/include/utility/color.glsl"

// HDR-aware local exposure: one system with the global meter.
//
// The global exposure already moved the frame to the metered anchor
// (see program/c4_taa_exposure.vsh). This pass only adds a zero-mean
// spatially-varying correction around THAT anchor — never a second
// independent push to middle gray. anchor_log is log2(metered luminance)
// derived from the stored global exposure, so when local == metered the
// correction is exactly 0 (centered, no net brightening). Log domain =>
// stops; bilateral similarity term prevents halo bleed.
// Must match the global meter in c4_taa_exposure.vsh (luminance_weights_ap1),
// not the display-gamut luminance_weights — otherwise the anchor derived
// from global exposure lives in a different primary set than local_log and
// the correction gains a systematic offset.
float local_exposure_luma(vec3 rgb) {
    return max(dot(max(rgb, vec3(0.0)), luminance_weights_ap1), 1e-5);
}

#ifdef LOCAL_EXPOSURE
float compute_local_exposure_ev(vec2 texel_uv, vec3 center_rgb, float anchor_log) {
    float center_log = log2(local_exposure_luma(center_rgb));

    float sum_log = center_log * 4.0;
    float sum_w = 4.0;

    // Small Gaussian footprint. Radius is deliberately modest because this is
    // a per-pixel post pass; larger-scale adaptation is already handled by the
    // global exposure system.
    const vec2 o = vec2(2.0);
    vec3 s;
    float l, w, d;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(-o.x, 0.0), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695); // ~= exp(-d)
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2( o.x, 0.0), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(0.0, -o.y), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(0.0,  o.y), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    const float diag = 1.41421356 * 2.0;
    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(-diag, -diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2( diag, -diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(-diag,  diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2( diag,  diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    float local_log = sum_log / max(sum_w, 1e-5);

    // Centered on the global meter anchor, not an absolute middle gray.
    // Same adaptation for detail and regional so the two stages agree.
    const float adaptation = 0.28;
    float ev = (anchor_log - local_log) * adaptation;

    // Keep local exposure a detail-preserving correction, never a replacement
    // for the user's global exposure. The symmetric limit is 2/3 stop.
    // DETAIL scales the fine bilateral term (1.0 = full detail correction).
    ev = clamp(ev * LOCAL_EXPOSURE_DETAIL, -0.6666667, 0.6666667);

    // Regional adaptation: the fine bilateral taps above only see pixels,
    // so broad light/shadow regions (a bright sky over a dark valley) slip
    // through. A low-res neighborhood luminance steers whole regions toward
    // middle gray — dodge and burn at area scale — clamped to RANGE stops
    // so it grades but never overrides the global exposure.
    float region_lod = ceil(log2(max_of(rcp(view_pixel_size)) * 0.02));
    vec3 region_rgb
        = textureLod(colortex5, texel_uv, region_lod).rgb;
    float region_log = log2(local_exposure_luma(region_rgb));
    float region_ev = clamp(
        (anchor_log - region_log) * adaptation,
        -LOCAL_EXPOSURE_RANGE,
        LOCAL_EXPOSURE_RANGE
    );

    return mix(ev, region_ev, LOCAL_EXPOSURE_REGIONAL);
}
#endif

#endif // INCLUDE_CAMERA_LOCAL_EXPOSURE
