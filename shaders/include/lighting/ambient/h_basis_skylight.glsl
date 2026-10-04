#if !defined INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
#define INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

// H-basis directional sky ambient.
//
// The flat sky average answers "how bright is the sky" but not "from
// where", so walls, floors and ceilings under open sky all receive the
// same tint. This projects the live sky map once per frame into six RGB
// H-basis coefficients (the rotation-symmetric subset of second-order
// spherical harmonics: constant, linear xyz, and the two quadratic
// vertical/azimuthal lobes), and reconstructs cosine-weighted hemisphere
// irradiance around any normal in closed form. The cross terms (xy, xz,
// yz) are dropped deliberately: skylight is dominated by the vertical
// gradient (zenith blue vs horizon warmth vs ground bounce), which the
// kept lobes capture, while the dropped terms mostly fit noise.
//
// Projection runs in a fullscreen-triangle vertex shader (a few hundred
// taps per frame total), evaluation is ~15 ALU per fragment with no
// textures, so this stays always on with no quality toggle. Sample
// positions are deterministic: the coefficients feed lighting directly
// with no temporal accumulation, so per-frame jitter would read as
// flickering illumination.
//
// Math follows Habel et al., "Efficient Irradiance Normal Mapping"
// (2008): E(n) = pi*h0 + (2pi/3)*sum(hi*ni) + (pi/8)*h4*(3ny^2-1)
//              + (pi/8)*h5*(nx^2-nz^2), y-up.

#include "/include/sky/projection.glsl"

// Sample count comes from settings (H_BASIS_SKY_SAMPLES slider):
// projection cost is verts * N, so fullscreen passes pay ~3*N taps
// per frame.

// Projects the live sky map into 6 RGB coefficients. Call once per frame
// from a fullscreen vertex stage; pass the result flat to the fragment
// stage. Requires colortex4 (sky map) readable in the calling stage.
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

// Cosine-weighted hemisphere irradiance around normal. Evaluate at the
// bent normal wherever one is available: in occluded areas it already
// points away from blockers, so the result is the average visible sky
// rather than the geometric normal staring at a wall.
vec3 evaluate_h_basis_irradiance(vec3 h[6], vec3 normal) {
    vec3 n = normalize(normal);

    vec3 result = h[0] * pi;
    result += (2.0 * pi / 3.0) * (h[1] * n.x + h[2] * n.y + h[3] * n.z);
    result += (pi * 0.125) * h[4] * (3.0 * n.y * n.y - 1.0);
    result += (pi * 0.125) * h[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
