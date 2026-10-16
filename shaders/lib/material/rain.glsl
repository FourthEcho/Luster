/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#if !defined INCLUDE_MATERIAL_RAIN_RIPPLES
#define INCLUDE_MATERIAL_RAIN_RIPPLES

// Rain-ripple normals adapted from Eclipse-Shader by Merlin1809, crediting Zavie / Ctrl-Alt-Test.
#ifdef rainRipples
// Use a rain_ prefix to avoid collisions with other hash helpers.
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
#endif // rainRipples

#endif // INCLUDE_MATERIAL_RAIN_RIPPLES

#ifdef LUSTER_INCLUDE_RAIN_PUDDLES
#if !defined INCLUDE_MATERIAL_RAIN_PUDDLES
#define INCLUDE_MATERIAL_RAIN_PUDDLES


float get_ripple_height(vec2 coord) {
    const float ripple_frequency = 0.3;
    const float ripple_speed = 0.1;
    const vec2 ripple_dir_0 = vec2(3.0, 4.0) / 5.0;
    const vec2 ripple_dir_1 = vec2(-5.0, -12.0) / 13.0;

    float ripple_noise_1
        = texture(
              noisetex,
              coord * ripple_frequency
                  + frameTimeCounter * ripple_speed * ripple_dir_0
        )
              .y;
    float ripple_noise_2
        = texture(
              noisetex,
              coord * ripple_frequency
                  + frameTimeCounter * ripple_speed * ripple_dir_1
        )
              .y;

    return mix(ripple_noise_1, ripple_noise_2, 0.5);
}

// Keep puddles limited to biomes where rain is possible.
float get_puddle_weather_factor() {
    return biome_may_rain;
}

float get_puddle_noise(vec3 world_pos, vec3 flat_normal, vec2 light_levels) {
    const float puddle_frequency = 0.025;

    float puddle = texture(noisetex, world_pos.xz * puddle_frequency).w;

    float weather_factor = get_puddle_weather_factor();

    // wetness is the host-smoothed rain amount, gated by biome.
    puddle = linear_step(0.45, 0.55, puddle) * wetness * weather_factor
        * step(0.99, flat_normal.y);

    // Require sky visibility and suppress puddles near strong blocklight.
    puddle *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    // Apply user-controlled puddle intensity slider.
    puddle *= rainPuddlesIntensity;

    return puddle;
}

// Per-channel wet-porosity darkening with saturating reflectance.
vec3 apply_wet_porosity_darkening(vec3 albedo, float porosityAmount, float wetness_factor) {
#ifndef porosity
    return albedo;
#else
    // Maximum absorbed fraction per internal bounce, scaled by porosityAmount.
    // effect self-limiting on already-dark surfaces.
    vec3 k = 0.7 * porosityAmount * sqrt(albedo);

    // KM saturating-absorption: R_wet = (1-k)*R / (1 - k*R)
    vec3 wet_albedo = (1.0 - k) * albedo / max(vec3(1e-4), 1.0 - k * albedo);

    return mix(albedo, wet_albedo, wetness_factor * porosityAmount);
#endif
}

bool get_rain_puddles(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels,
    float porosityAmount,
    uint material_mask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness,
    inout float ssr_multiplier
) {
#ifndef rainPuddles
    return false;
#endif

    const float puddle_f0 = 0.02;
    const float puddle_roughness = 0.002;
    const float puddle_darkening_factor = 0.33;
    const float puddle_darkening_factor_porous = 0.67;

    // Skip leaves entirely — puddles on leaves look wrong since the
    // canopy should be shedding water, not pooling it.
    if (material_mask == MATERIAL_LEAVES) {
        return false;
    }

    // Negative sentinels identify dimensions or biomes where water cannot reach.
    if (wetness < 0.0 || biome_may_rain < 0.0) {
        return false;
    }

    float puddle = get_puddle_noise(world_pos, flat_normal, light_levels);

    if (puddle < eps) {
        return false;
    }

    // Porous materials darken more and retain less surface water.
    albedo *= 1.0 - puddle_darkening_factor_porous * porosityAmount * puddle;
    puddle *= 1.0 - porosityAmount;
    albedo *= 1.0 - puddle_darkening_factor * puddle;

    // Replace material with puddle material
    f0 = max(f0, mix(f0, vec3(puddle_f0), puddle));
    roughness = puddle_roughness;
    ssr_multiplier = max(ssr_multiplier, puddle);

    // Blend the same rain-ring normals used by open water into wet areas.
    const float h = 0.1;
#ifdef rainRipples
    // Shared analytic rings; puddle coverage keeps dry land unaffected.
    vec3 ripple_normal = vec3(
        rain_ripple_normal(world_pos.xz, frameTimeCounter).xy,
        1.0
    );
#else
    float ripple0 = get_ripple_height(world_pos.xz);
    float ripple1 = get_ripple_height(world_pos.xz + vec2(h, 0.0));
    float ripple2 = get_ripple_height(world_pos.xz + vec2(0.0, h));
    vec3 ripple_normal = vec3(ripple1 - ripple0, ripple2 - ripple0, h);
#endif
#ifdef rainRipples
    // Same strength convention as open water so one slider drives both.
    float ripple_gain = 0.30 * rainRippleStrength;
#else
    float ripple_gain = 0.05;
#endif
    ripple_normal.xy
        *= ripple_gain
        * smoothstep(
               0.0,
               0.1,
               abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
        );
    ripple_normal = normalize(ripple_normal);
    ripple_normal = ripple_normal.xzy; // convert to world space

    normal = mix(normal, flat_normal, puddle);
    normal = mix(normal, ripple_normal, puddle * rainStrength);
    normal = normalize_safe(normal);

    return true;
}

#endif // INCLUDE_MATERIAL_RAIN_PUDDLES
#endif // LUSTER_INCLUDE_RAIN_PUDDLES
