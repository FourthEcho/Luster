#if !defined INCLUDE_FOG_NETHER_SMOKE_VL
#define INCLUDE_FOG_NETHER_SMOKE_VL

// Custom Luster implementation of Kappa's Nether volumetric smoke behavior.
// The structure and tuning are independently written around Luster's existing
// 3D Perlin volume and fog interfaces.

const float LUSTER_NETHER_HAZE_COEFF  = 0.002;
const float LUSTER_NETHER_SMOKE_COEFF = 0.030;
const float LUSTER_NETHER_MAX_DIST   = 192.0;

float luster_nether_smoke_noise(vec3 p) {
    // Luster's 64^3 texture contains related Perlin scales in RGB.
    // Sample two scales and combine them to approximate Kappa's continuous
    // value-noise octaves while retaining the pack's existing texture.
    vec3 n0 = texture(perlin_3d, p).rgb;
    vec3 n1 = texture(perlin_3d, p * 2.0 + vec3(0.173, 0.317, 0.271)).rgb;
    return clamp(n0.r * 0.55 + n0.g * 0.30 + n1.b * 0.15, 0.0, 1.0);
}

vec3 luster_nether_smoke_density(vec3 ray_pos, float altitude) {
#ifdef NETHER_SMOKE
    float fade = sqr(1.0 - linear_step(128.0, 256.0, altitude));
    fade *= exp(-max(altitude - 32.0, 0.0) * 0.015) * 0.6 + 0.4;

    if (fade <= 1e-10) {
        return vec3(1.0, 0.0, 0.0);
    }

    float t = frameTimeCounter * 0.6;
    vec3 wind = t * vec3(1.0, -0.9, 0.1);

    vec3 p = (ray_pos + cameraPosition) * 0.03;

    // Domain warp: broad billows first, then finer turbulent displacement.
    p += luster_nether_smoke_noise(p * 4.0 + wind * 0.5) * 1.5 - 0.75;
    p += luster_nether_smoke_noise(p * 8.0 - wind) - 0.5;
    p.x *= 0.7;

    float noise = luster_nether_smoke_noise(p * 4.0 + wind);
    noise += luster_nether_smoke_noise(p * 8.0 + wind * 2.0 + vec3(noise * 0.5)) * 0.5;
    noise /= 1.5;

    float smoke = max(fade - noise, 0.0);

    // Kappa-style proximity glow channel. Kept separate from extinction.
    float proximity = sqrt(smoothstep(4.0, 24.0, length(ray_pos)));
    float glowing = clamp(
        (proximity * (0.3 + fade * fade * fade * 0.15) - noise) * pi,
        0.0,
        1.0
    );

    smoke = smoke * smoke * smoke * (fade * 0.5 + 0.5);
    glowing *= fade;

    return vec3(1.0, smoke, glowing);
#else
    return vec3(1.0, 0.0, 0.0);
#endif
}

mat2x3 raymarch_nether_smoke(vec3 world_start, vec3 world_end, float dither) {
    vec3 end_pos = world_end;
    vec3 ray = end_pos - world_start;
    float ray_len = length(ray);

    if (ray_len > LUSTER_NETHER_MAX_DIST) {
        ray = normalize(ray) * LUSTER_NETHER_MAX_DIST;
        end_pos = world_start + ray;
        ray_len = LUSTER_NETHER_MAX_DIST;
    }

    float step_factor = clamp(
        ray_len / clamp(far, 128.0, LUSTER_NETHER_MAX_DIST),
        0.0,
        1.0
    );
    int step_count = 8 + int(step_factor * 16.0);

    vec3 step_vector = ray / float(step_count);
    float step_length = length(step_vector);
    vec3 sample_pos = world_start + step_vector * dither;

    // Density channels mirror Kappa's layout conceptually:
    // channel 0 = low-frequency haze, channel 1 = smoke, channel 2 = emission.
    vec3 scatter_accum = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    // Keep haze and smoke independently tunable, with no constant 1.0 density.
    vec3 haze_coeff  = vec3(LUSTER_NETHER_HAZE_COEFF);
    vec3 smoke_coeff = vec3(LUSTER_NETHER_SMOKE_COEFF * NETHER_SMOKE_INTENSITY);

    for (int i = 0; i < step_count; ++i) {
        sample_pos += step_vector;

        if (max(max(transmittance.r, transmittance.g), transmittance.b) < 0.01) {
            break;
        }

        float altitude = sample_pos.y + eyeAltitude;
        if (altitude > 256.0) {
            continue;
        }

        vec3 density = luster_nether_smoke_density(sample_pos, altitude);
        vec2 step_density = density.xy * step_length;

        vec3 optical_depth = haze_coeff * step_density.x
                           + smoke_coeff * step_density.y;

        vec3 step_transmittance = exp(-optical_depth);
        vec3 scatter_integral = clamp(
            (step_transmittance - 1.0) / -max(optical_depth, vec3(1e-6)),
            0.0,
            1.0
        );

        vec3 visible = transmittance * scatter_integral;
        vec3 weighting = visible * transmittance;

        vec3 haze_step = haze_coeff * step_density.x * weighting;
        vec3 smoke_step = smoke_coeff * step_density.y * weighting;

        // Kappa's Nether palette is driven by the vanilla Nether fog color.
        // Recreate that role with Luster's working color space rather than
        // feeding the full ambient-light value back into the fog.
        vec3 nether_fog = srgb_eotf_inv(clamp(fogColor, 0.0, 1.0))
                        * rec709_to_working_color;
        vec3 fog_color = normalize(max(nether_fog, vec3(1e-5)));
        vec3 fog_color_soft = nether_fog * 0.8;

        vec3 emission_color = mix(
            vec3(1.0, 0.1, 0.0),
            max(light_color, vec3(0.02)) * 0.5,
            clamp(density.z, 0.0, 1.0)
        );

        scatter_accum += haze_step * fog_color_soft;
        scatter_accum += smoke_step * fog_color;
        scatter_accum += density.z * emission_color * step_density.y * weighting
                       * 0.6 * NETHER_SMOKE_INTENSITY;

        transmittance *= step_transmittance;
    }

    if (any(isnan(scatter_accum)) || any(isnan(transmittance))) {
        scatter_accum = vec3(0.0);
        transmittance = vec3(1.0);
    }

    return mat2x3(scatter_accum, clamp(transmittance, 0.0, 1.0));
}

#endif
