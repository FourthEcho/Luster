#if !defined INCLUDE_SURFACE_RAIN_RIPPLES
#define INCLUDE_SURFACE_RAIN_RIPPLES

// Raindrop ripple normals, based on Eclipse-Shader's lib/ripples.glsl
// (Merlin1809, itself crediting the Shadertoy "ldfyzl" rain experiment
// by Zavie / Ctrl-Alt-Test):
//   - one scattered drop point per grid cell (hash-positioned, so rings
//     never sit on a visible lattice),
//   - each drop grows a real multi-ring sine wavefront (capillary look)
//     with (1-t)^2 decay and per-drop random phasing,
//   - the gradient is computed ANALYTICALLY from the wave phase, so one
//     call returns a finished normal — no 3-tap finite differences, no
//     noise textures, no extra samplers.
// Used both by open water (water_normal.glsl) and by land puddles
// (rain_puddles.glsl) so both surfaces share the same rainfall.
#ifdef RAIN_RIPPLES
// Renamed with a rain_ prefix: the pack already defines hash22 in
// sspt.glsl, and both headers can land in one translation unit.
float rain_hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 rain_hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// coord: world-space surface position (meters). time: seconds.
vec3 rain_ripple_normal(vec2 coord, float time) {
    const float cell_density = 5.0; // ~20 cm cells at world scale
    const int max_radius = 1;
    const float wave_frequency = 21.0; // ~30 cm ring wavelength
    const float h = 1e-2;

    vec2 uv = coord * cell_density;
    vec2 p0 = floor(uv);
    vec2 circles = vec2(0.0);

    for (int j = -max_radius; j <= max_radius; ++j) {
        for (int i = -max_radius; i <= max_radius; ++i) {
            vec2 pi = p0 + vec2(i, j);
            vec2 p = pi + rain_hash22(pi);

            float t = fract(0.9 * time + rain_hash12(pi));
            vec2 v = p - uv;
            // Hardened normalize: a drop centered exactly on the fragment
            // would divide by zero (undefined -> NaN poison).
            vec2 dir = v / max(length(v), 1e-4);

            float d = length(v) - float(max_radius + 1) * t;
            float d1 = d - h;
            float d2 = d + h;
            float envelope1 = smoothstep(-0.6, -0.3, d1) * smoothstep(0.0, -0.3, d1);
            float envelope2 = smoothstep(-0.6, -0.3, d2) * smoothstep(0.0, -0.3, d2);
            float p1 = sin(wave_frequency * d1) * envelope1;
            float p2 = sin(wave_frequency * d2) * envelope2;
            float decay = (1.0 - t) * (1.0 - t);
            circles += 0.5 * dir * ((p2 - p1) / (2.0 * h) * decay);
        }
    }
    circles /= float((max_radius * 2 + 1) * (max_radius * 2 + 1));

    vec3 n = vec3(circles, sqrt(max(1.0 - dot(circles, circles), 0.0)));
    return n;
}
#endif

#endif // INCLUDE_SURFACE_RAIN_RIPPLES
