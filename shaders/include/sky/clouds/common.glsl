#if !defined INCLUDE_SKY_CLOUDS_COMMON
#define INCLUDE_SKY_CLOUDS_COMMON

#include "/include/sky/atmosphere.glsl"
#include "/include/sky/clouds/constants.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/geometry.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"

uniform float day_factor;

// 3D curl vector field loaded from shaders/image/curl_3d.dat.
// The raw RGB8 values are encoded from [-1, 1] into [0, 1].
uniform sampler3D curl_noise_3d;
uniform sampler3D perlin_noise_3d;

vec3 sample_curl_noise_3d(vec3 coord) {
    return texture(curl_noise_3d, fract(coord)).xyz * 2.0 - 1.0;
}

float sample_perlin_noise_3d(vec3 coord) {
    // Precomputed tileable 4-octave 3D improved-Perlin field, normalized to [0, 1].
    return texture(perlin_noise_3d, fract(coord)).r;
}

// ----

struct CloudsResult {
    vec4 scattering; // w = ambient scattering, for lightning flashes
    float transmittance;
    float apparent_distance;
};

const CloudsResult clouds_not_hit = CloudsResult(vec4(0.0), 1.0, 1e5);

// ----

// from https://iquilezles.org/articles/gradientnoise/
vec2 perlin_gradient(vec2 coord) {
    vec2 i = floor(coord);
    vec2 f = fract(coord);

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    vec2 g0 = hash2(i + vec2(0.0, 0.0));
    vec2 g1 = hash2(i + vec2(1.0, 0.0));
    vec2 g2 = hash2(i + vec2(0.0, 1.0));
    vec2 g3 = hash2(i + vec2(1.0, 1.0));

    float v0 = dot(g0, f - vec2(0.0, 0.0));
    float v1 = dot(g1, f - vec2(1.0, 0.0));
    float v2 = dot(g2, f - vec2(0.0, 1.0));
    float v3 = dot(g3, f - vec2(1.0, 1.0));

    return vec2(
        g0 + u.x * (g1 - g0) + u.y * (g2 - g0) + u.x * u.y * (g0 - g1 - g2 + g3)
        + // d/dx
        du * (u.yx * (v0 - v1 - v2 + v3) + vec2(v1, v2) - v0) // d/dy
    );
}

vec2 curl2D(vec2 coord) {
    vec2 gradient = perlin_gradient(coord);
    return vec2(gradient.y, -gradient.x);
}


float clouds_ground_ambient_weight(float altitude_fraction) {
    return mix(1.30, 0.28, smoothstep(0.0, 1.0, altitude_fraction));
}

float clouds_sky_ambient_weight(float altitude_fraction) {
    return mix(0.48, 1.18, smoothstep(0.0, 1.0, altitude_fraction));
}

float clouds_core_light_attenuation(
    float density,
    float light_optical_depth,
    float altitude_fraction
) {
    float core = smoothstep(0.18, 0.85, density);
    float vertical = mix(1.0, 0.72, smoothstep(0.35, 1.0, altitude_fraction));
    return exp(-0.42 * light_optical_depth * core * vertical);
}

float clouds_internal_bounce_light(
    float direct_light,
    float density,
    float light_optical_depth,
    float altitude_fraction,
    float cos_theta
) {
    // Bounce 0 is direct sunlight. Each enabled bounce carries the previous
    // bounce through a density-dependent feedback term. Height and angular
    // response deliberately vary per bounce so the result does not collapse
    // into the same multiplier repeated N times.
    float bounce_light = direct_light;
    float accumulated = 0.0;

    float height = clamp01(altitude_fraction);
    float forward = clamp01(cos_theta * 0.5 + 0.5);
    float edge = 1.0 - smoothstep(0.16, 0.68, density);
    float density_feedback = mix(0.08, 0.52, smoothstep(0.02, 0.75, density));

    for (int i = 0; i < CLOUDS_LIGHTING_BOUNCES; ++i) {
        float bounce = float(i + 1);
        float height_gain = mix(1.04 - 0.05 * bounce,
                                0.70 - 0.025 * bounce,
                                height);
        float angle_gain = mix(0.62 + 0.04 * bounce,
                                1.18 + 0.06 * bounce,
                                forward);
        float edge_gain = 1.0 + 0.35 * edge * forward;
        float attenuation = exp(
            -light_optical_depth
                * mix(0.58 + 0.05 * bounce, 0.82 + 0.08 * bounce, height)
                * (0.55 + 0.45 * clamp01(density))
        );

        bounce_light *= attenuation * density_feedback
            * height_gain * angle_gain * edge_gain;

        // Later bounces are increasingly diffuse and weaker.
        bounce_light *= mix(0.94, 0.68, clamp01(0.20 * bounce));
        accumulated += bounce_light;

        density_feedback *= mix(0.90, 0.68, height);
    }

    return accumulated;
}

float clouds_silver_lining(float density, float cos_theta) {
    float edge = 1.0 - smoothstep(0.12, 0.58, density);
    float facing = smoothstep(0.20, 0.92, cos_theta * 0.5 + 0.5);
    return 1.0 + 0.42 * edge * facing;
}

float clouds_phase_single(float cos_theta) { // Single scattering phase function
    float forwards_a = klein_nishina_phase(
        cos_theta,
        2600.0
    ); // this gives a nice glow very close to the sun
    float forwards_b = henyey_greenstein_phase(cos_theta, 0.8);

    return 0.8
        * max(forwards_a,
              forwards_b) // forwards lobe (max'ing them is completely
                          // nonsensical but it looks nice)
        + 0.2 * henyey_greenstein_phase(cos_theta, -0.2); // backwards lobe
}

float clouds_phase_multi(
    float cos_theta,
    vec3 g
) { // Multiple scattering phase function
    return 0.65 * henyey_greenstein_phase(cos_theta, g.x) // forwards lobe
        + 0.10 * henyey_greenstein_phase(cos_theta, g.y) // forwards peak
        + 0.25 * henyey_greenstein_phase(cos_theta, -g.z); // backwards lobe
}

float clouds_powder_effect(float density, float cos_theta) {
    float powder = pi * density / (density + 0.15);
    powder = mix(powder, 1.0, 0.8 * sqr(cos_theta * 0.5 + 0.5));

    return powder;
}

vec3 clouds_aerial_perspective(
    vec3 clouds_scattering,
    float clouds_transmittance,
    vec3 ray_origin,
    vec3 ray_end,
    vec3 ray_dir,
    vec3 clear_sky
) {
    vec3 air_transmittance;

#if CLOUDS_AERIAL_PERSPECTIVE_BOOST != 0
    ray_end
        = mix(ray_origin, ray_end, float(1 << CLOUDS_AERIAL_PERSPECTIVE_BOOST));
#endif

    if (length_squared(ray_origin) < length_squared(ray_end)) {
        vec3 trans_0 = atmosphere_transmittance(ray_origin, ray_dir);
        vec3 trans_1 = atmosphere_transmittance(ray_end, ray_dir);

        air_transmittance = clamp01(trans_0 / trans_1);
    } else {
        vec3 trans_0 = atmosphere_transmittance(ray_origin, -ray_dir);
        vec3 trans_1 = atmosphere_transmittance(ray_end, -ray_dir);

        air_transmittance = clamp01(trans_1 / trans_0);
    }

    // Blend to rain color during rain
    clear_sky = mix(
        clear_sky,
        sky_color * rcp(tau),
        rainStrength * mix(1.0, 0.9, time_sunrise + time_sunset)
    );
    air_transmittance
        = mix(air_transmittance, vec3(air_transmittance.x), 0.8 * rainStrength);

    return mix(
        (1.0 - clouds_transmittance) * clear_sky,
        clouds_scattering,
        air_transmittance
    );
}

CloudsResult blend_layers(CloudsResult old, CloudsResult new) {
    bool new_in_front = new.apparent_distance < old.apparent_distance;

    vec4 scattering_behind = new_in_front ? old.scattering : new.scattering;
    vec4 scattering_in_front = new_in_front ? new.scattering : old.scattering;
    float transmittance_in_front
        = new_in_front ? new.transmittance : old.transmittance;

    return CloudsResult(
        scattering_in_front + transmittance_in_front * scattering_behind,
        old.transmittance * new.transmittance,
        min(old.apparent_distance, new.apparent_distance)
    );
}

#endif
