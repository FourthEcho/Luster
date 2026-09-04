#if !defined INCLUDE_FOG_SMOOTHING
#define INCLUDE_FOG_SMOOTHING

// Fog smoothing is a current-frame edge-aware Gaussian denoising stage. It
// intentionally does not reuse scene color/TAA history: fog radiance is a
// different signal.
//
// Each tap is weighted by a Gaussian falloff over distance from the center
// pixel (so nearby samples contribute far more than samples near the edge
// of the kernel, unlike a flat box filter) multiplied by a bilateral range
// weight based on luminance difference (so the blur doesn't bleed across
// hard fog-density edges, e.g. cave mouths or fog-bank boundaries).

#include "/include/utility/fast_math.glsl"

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 fog_spatial_filter(
    sampler2D scattering_tex,
    vec2 uv,
    vec2 pixel_size,
    int radius
) {
    vec3 center = texture(scattering_tex, uv).rgb;
    vec3 sum = center;
    float w_sum = 1.0;

    // Standard three-sigma rule: sigma sized so the kernel's edge taps carry
    // negligible weight (~1%) rather than being cut off abruptly by the box
    float sigma = max(float(radius), 1.0) / 3.0;
    float inv_two_sigma_sq = 0.5 / (sigma * sigma);

    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x == 0 && y == 0) continue;

            vec2 offset = vec2(float(x), float(y));
            vec2 sample_uv = uv + offset * pixel_size;
            if (clamp01(sample_uv) != sample_uv) continue;

            vec3 sample_value = texture(scattering_tex, sample_uv).rgb;
            float delta = abs(luminance(sample_value) - luminance(center));

            float spatial_weight = exp(-dot(offset, offset) * inv_two_sigma_sq);
            float range_weight = exp(-delta * 8.0);
            float weight = spatial_weight * range_weight;

            sum += sample_value * weight;
            w_sum += weight;
        }
    }

    return sum / max(w_sum, eps);
}

#endif // INCLUDE_FOG_SMOOTHING
