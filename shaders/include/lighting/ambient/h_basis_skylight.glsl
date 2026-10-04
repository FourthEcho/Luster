#if !defined INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
#define INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

// H-basis directional sky ambient.

#include "/include/sky/projection.glsl"

void project_sky_h_basis(out vec3 h[6]) {
    for (int i = 0; i < 6; ++i) {
        h[i] = vec3(0.0);
    }

    for (int i = 0; i < H_BASIS_SKY_SAMPLES; ++i) {
        // Uniform-sphere low-discrepancy sequence (deterministic by design).
        vec2 u = vec2(
            (float(i) + 0.5) / float(H_BASIS_SKY_SAMPLES),
            fract(float(i) * 0.61803398875)
        );

        float phi = tau * u.y;
        float cos_theta = 2.0 * u.x - 1.0;
        float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
        vec3 d = vec3(
            sin_theta * cos(phi), cos_theta, sin_theta * sin(phi)
        );

        vec3 radiance = max0(texture(colortex4, project_sky(d)).rgb);

        h[0] += radiance;
        h[1] += radiance * d.x;
        h[2] += radiance * d.y;
        h[3] += radiance * d.z;
        h[4] += radiance * (1.5 * d.y * d.y - 0.5);
        h[5] += radiance * (d.x * d.x - d.z * d.z) * 0.5;
    }

    float inv_n = 1.0 / float(H_BASIS_SKY_SAMPLES);
    for (int i = 0; i < 6; ++i) {
        h[i] *= inv_n;
    }
}

vec3 evaluate_h_basis_irradiance(vec3 h[6], vec3 normal) {
    vec3 n = normalize(normal);

    vec3 result = h[0] * pi;
    result += (2.0 * pi / 3.0) * (h[1] * n.x + h[2] * n.y + h[3] * n.z);
    result += (pi * 0.125) * h[4] * (3.0 * n.y * n.y - 1.0);
    result += (pi * 0.125) * h[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
