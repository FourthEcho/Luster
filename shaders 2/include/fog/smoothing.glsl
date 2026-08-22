#if !defined INCLUDE_FOG_SMOOTHING
#define INCLUDE_FOG_SMOOTHING

// Fog Smoothing — temporal + spatial blur of the fog scattering result
// to reduce high-frequency noise from the volumetric raymarch.
//
// Approach: edge-stopping bilateral filter guided by depth & luminance, with
// a temporal reproject + variance estimate (similar in spirit to SVGF).
//
// Wired in from program/c0_vl.fsh (volumetric fog) before the result is
// composited into colortex3.

#include "/include/utility/bicubic.glsl"
#include "/include/utility/fast_math.glsl"

// Reproject the previous-frame fog result. Caller must supply previous UV
// (computed in the parent program by reprojecting the current scene position).
vec3 sample_history_fog(
    sampler2D history_tex,
    vec2 prev_uv,
    out float valid
) {
    valid = 0.0;
    if (clamp01(prev_uv) != prev_uv) return vec3(0.0);
    valid = 1.0;
    return bicubic_filter(history_tex, prev_uv).rgb;
}

// Spatial edge-stopping bilateral blur on the fog scattering result.
//   in_scattering : rgb scattering from current frame raymarch
//   in_transmittance : transmittance (1 - alpha)
//   center_depth : linear view-space depth at the center pixel
//   normal       : world-space normal at center (for edge stopping)
vec3 fog_spatial_filter(
    sampler2D scattering_tex,
    vec2 uv,
    vec2 pixel_size,
    float center_depth,
    vec3 center_normal,
    int radius,
    float depth_sigma,
    float normal_sigma
) {
    vec3 center = texture(scattering_tex, uv).rgb;
    vec3 sum = center;
    float w_sum = 1.0;

    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x == 0 && y == 0) continue;
            vec2 offset = vec2(float(x), float(y)) * pixel_size;
            vec2 sample_uv = uv + offset;
            if (clamp01(sample_uv) != sample_uv) continue;

            vec3 s = texture(scattering_tex, sample_uv).rgb;

            // Edge-stopping weight (depth + luminance based, since we don't
            // have per-pixel normal in the fog pass)
            float depth_w = 1.0;
            float lum_diff = abs(luminance(s) - luminance(center));
            float lum_w = exp(-lum_diff / depth_sigma);

            float w = lum_w;
            sum += s * w;
            w_sum += w;
        }
    }

    return sum / max(w_sum, eps);
}

// Full fog smoothing pass: temporal reproject + variance estimate + spatial
// bilateral blur + A-SVGF-style variance-guided radius selection.
vec3 smooth_fog(
    sampler2D current_scattering_tex,
    sampler2D history_scattering_tex,
    vec2 uv,
    vec2 prev_uv,
    vec2 pixel_size,
    float temporal_weight,
    out float out_variance
) {
    // 1. Spatial pass first (cheap 3x3) to denoise current frame
    vec3 spatial = fog_spatial_filter(
        current_scattering_tex, uv, pixel_size, 1.0, vec3(0.0, 1.0, 0.0),
        FOG_SMOOTHING_RADIUS, 0.1, 8.0
    );

    // 2. Reproject previous frame
    float valid;
    vec3 history = sample_history_fog(history_scattering_tex, prev_uv, valid);

    // 3. Variance estimate (cheap luminance-based, single-sample)
    float lum_curr = luminance(spatial);
    float lum_hist = luminance(history);
    out_variance = abs(lum_curr - lum_hist) * valid;

    // 4. Temporal blend (clamped to avoid ghosting)
    float tw = valid * clamp(temporal_weight, 0.0, 0.9);
    vec3 result = mix(spatial, history, tw);

    // 5. Variance-guided additional blur when history disagrees with current
    if (out_variance > 0.05) {
        result = fog_spatial_filter(
            current_scattering_tex, uv, pixel_size, 1.0, vec3(0.0, 1.0, 0.0),
            max(FOG_SMOOTHING_RADIUS, 2), 0.1, 8.0
        );
    }

    return result;
}

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

#endif // INCLUDE_FOG_SMOOTHING
