#if !defined INCLUDE_CAMERA_VIGNETTE
#define INCLUDE_CAMERA_VIGNETTE

// Filmic vignette with darkness/pulse response.
//
// Requires from the including program:
//   - frameTimeCounter, biome_cave, blindness, darknessFactor uniforms
//   - VIGNETTE_INTENSITY / VIGNETTE_START / VIGNETTE_END / VIGNETTE_EXPONENT
//     settings, dampen() from "/include/global.glsl".

float vignette(vec2 uv) {
    const float vignette_size = 16.0;
    const float vignette_intensity = 0.08 * VIGNETTE_INTENSITY;

    float darkness_pulse = 1.0 - dampen(abs(cos(2.0 * frameTimeCounter)));

    float vignette
        = vignette_size * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    vignette = pow(
        vignette,
        vignette_intensity + 0.1 * biome_cave + 0.3 * blindness
            + 0.2 * darkness_pulse * darknessFactor
    );

    // Radial shaping: confine the falloff between START and END with
    // EXPONENT rolloff. At defaults the corners and center match the
    // unshaped curve exactly; only the midrange blend softens.
    float vignette_r = length((uv - 0.5) * 2.0);
    float vignette_shaping = pow(
        smoothstep(
            VIGNETTE_START,
            max(VIGNETTE_END, VIGNETTE_START + 1e-3),
            vignette_r
        ),
        VIGNETTE_EXPONENT
    );

    return mix(1.0, vignette, vignette_shaping);
}

#endif // INCLUDE_CAMERA_VIGNETTE
