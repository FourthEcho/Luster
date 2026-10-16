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

#if defined(LUSTER_INCLUDE_MOON_PHASE_COLOR)
// Moon-phase color influence.
#if !defined INCLUDE_LIGHTING_COLORS_MOON_PHASE_INFLUENCE
#define INCLUDE_LIGHTING_COLORS_MOON_PHASE_INFLUENCE

#include "/lib/util/color.glsl"

// Moon Phase Influence helpers -------


float get_moon_phase_curve() {
    if (moonPhase == 0) return 1.0;
    else if (moonPhase == 1) return 0.875;
    else if (moonPhase == 2) return 0.75;
    else if (moonPhase == 3) return 0.625;
    else if (moonPhase == 4) return 0.5;
    else if (moonPhase == 5) return 0.75;
    else if (moonPhase == 6) return 0.875;
    else return 1.0;
}


vec3 apply_moon_phase_influence(
    vec3 color,
    float intensity,
    float contrast,
    float saturation
) {
    float phase = get_moon_phase_curve();
    phase = clamp01(0.5 + (phase - 0.5) * contrast);

    float brightness_mul = mix(1.0, phase, clamp01(intensity));
    color *= brightness_mul;

    float sat_mul = mix(1.0, phase, clamp01(saturation));
    float lum = dot(color, luminance_weights);
    color = mix(vec3(lum), color, sat_mul);

    return color;
}

#endif
#endif

#if defined(LUSTER_INCLUDE_BLOCKLIGHT_COLOR)
// Blocklight color and emissive scale.
#if !defined INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR

#include "/lib/util/color.glsl"

const float blocklight_scale = 6.0;


const float emission_scale = 40.0;

#define blocklight_color \
    (from_display(vec3(blocklightR, blocklightG, blocklightB)) * blocklightI)

#endif // INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#endif

#if defined(LUSTER_INCLUDE_LIGHT_COLOR)
// Sun/moon color and exposure helpers.
#if !defined INCLUDE_LIGHTING_COLORS_LIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_LIGHT_COLOR

#include "/lib/sky/atmosphere.glsl"
#include "/lib/util/color.glsl"
uniform float moon_phase_brightness;

// Magic brightness adjustment so that auto exposure isn't needed
float get_sun_exposure() {
    const float base_scale = 7.0 * sunI;

    float blue_hour
        = linear_step(0.05, 1.0, exp(-190.0 * sqr(sun_dir.y + 0.09604)));

    float daytime_mul
        = 1.0 + 0.5 * (time_sunset + time_sunrise) + 40.0 * blue_hour;

    return base_scale * daytime_mul;
}

vec3 get_sun_tint() {
    float blue_hour
        = linear_step(0.05, 1.0, exp(-190.0 * sqr(sun_dir.y + 0.09604)));

    vec3 morning_evening_tint = vec3(1.05, 0.84, 0.93) * 1.2;
    morning_evening_tint = mix(
        vec3(1.0),
        morning_evening_tint,
        sqr(pulse(sun_dir.y, 0.17, 0.40))
    );

    vec3 blue_hour_tint = vec3(0.95, 0.80, 1.0);
    blue_hour_tint = mix(vec3(1.0), blue_hour_tint, blue_hour);

    // User tint

    const vec3 tint_morning = from_display(vec3(sunMr, sunMg, sunMb));
    const vec3 tint_noon = from_display(vec3(sunNr, sunNg, sunNb));
    const vec3 tint_evening = from_display(vec3(sunEr, sunEg, sunEb));

    vec3 user_tint = mix(tint_noon, tint_morning, time_sunrise);
    user_tint = mix(user_tint, tint_evening, time_sunset);

    return morning_evening_tint * blue_hour_tint * user_tint;
}

float get_moon_exposure() {
    const float base_scale = 0.66 * moonI;

    float time_boost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sun_dir.y, 0.1)));

    return base_scale * moon_phase_brightness * time_boost;
}

vec3 get_moon_tint() {
    const vec3 base_tint = from_display(vec3(moonR, moonG, moonB));

    return base_tint;
}

vec3 get_light_color() {
    vec3 light_color
        = sunlight_color * atmosphere_transmittance(light_dir.y, planet_radius);
    light_color = atmosphere_post_processing(light_color);
    vec3 moon_light = get_moon_exposure() * get_moon_tint();

    light_color *= mix(
        get_sun_exposure() * get_sun_tint(),
        moon_light,
        step(0.5, sunAngle)
    );
    light_color *= clamp01(
        rcp(0.02) * light_dir.y
    ); // fade away during day/night transition
    light_color *= 1.0 - 0.25 * pulse(abs(light_dir.y), 0.15, 0.11);

    return light_color;
}

#endif // INCLUDE_LIGHTING_COLORS_LIGHT_COLOR
#endif

#if defined(LUSTER_INCLUDE_WEATHER_COLOR)
// Precipitation and weather color helpers.
#if !defined INCLUDE_LIGHTING_COLORS_WEATHER_COLOR
#define INCLUDE_LIGHTING_COLORS_WEATHER_COLOR

#include "/lib/sky/atmosphere.glsl"

uniform float biome_may_sandstorm;

vec3 get_rain_color() {
    return mix(0.033, 0.66, smoothstep(-0.1, 0.5, sun_dir.y)) * sunlight_color
        * vec3(0.49, 0.65, 1.00);
}

vec3 get_snow_color() {
#if defined PROGRAM_WEATHER
    return mix(0.5, 1.60, smoothstep(-0.1, 0.5, sun_dir.y)) * sunlight_color
        * vec3(0.49, 0.65, 1.00);
#else
    return mix(0.060, 1.60, smoothstep(-0.1, 0.5, sun_dir.y)) * sunlight_color
        * vec3(0.49, 0.65, 1.00);
#endif
}

vec3 get_sandstorm_color() {
    return mix(0.033, 0.66, smoothstep(-0.1, 0.5, sun_dir.y)) * sunlight_color
        * vec3(1.00, 0.83, 0.60);
}

vec3 get_weather_color() {
    vec3 weather_color
        = mix(get_rain_color(), get_snow_color(), biome_may_snow);
    weather_color
        = mix(weather_color, get_sandstorm_color(), biome_may_sandstorm);

    return weather_color;
}

#endif // INCLUDE_LIGHTING_COLORS_WEATHER_COLOR
#endif
