#if !defined INCLUDE_FOG_SMOOTHING
#define INCLUDE_FOG_SMOOTHING

// Fog smoothing is a current-frame edge-aware denoising stage. It intentionally
// does not reuse scene color/TAA history: fog radiance is a different signal.

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

    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x == 0 && y == 0) continue;

            vec2 sample_uv = uv + vec2(float(x), float(y)) * pixel_size;
            if (clamp01(sample_uv) != sample_uv) continue;

            vec3 sample_value = texture(scattering_tex, sample_uv).rgb;
            float delta = abs(luminance(sample_value) - luminance(center));
            float weight = exp(-delta * 8.0);

            sum += sample_value * weight;
            w_sum += weight;
        }
    }

    return sum / max(w_sum, eps);
}

#endif // INCLUDE_FOG_SMOOTHING
