#if !defined INCLUDE_WEATHER_CORE
#define INCLUDE_WEATHER_CORE

#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

// Daily random wind direction.
//
// Picks one of 8 compass directions per Minecraft day, derived from a hash
// of `worldDay`. The direction is stable across a single day so rain and
// foliage all lean the same way, then rotates to a new direction at
// midnight. Snow uses the same particle shader as rain so it benefits
// automatically.
//
// Driven by the `weather_wind_angle` uniform declared in shaders.properties:
//
//     uniform.float.weather_wind_angle = (worldDay % 8) * 0.7853981633974483
//
// (0.785398... = 45 degrees in radians, so 8 steps cover the full circle.)
uniform float weather_wind_angle;

// Returns the daily wind direction as a unit vec2 in world XZ.
vec2 weather_wind_direction() {
    return vec2(cos(weather_wind_angle), sin(weather_wind_angle));
}

struct Weather {
    float temperature; // [0, 1]
    float humidity; // [0, 1]
    float wind; // [0, 1]
    float convection; // [0, 1]
    float storm; // [0, 1]
};

float weather_value_noise_2d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = cubic_smooth(fract(p));

    float a = hash1(dot(i, vec2(1.0, 57.0)));
    float b = hash1(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
    float c = hash1(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
    float d = hash1(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 weather_spatial_field(vec2 world_xz) {
    // Very low-frequency, stage-safe weather cells. This deliberately avoids
    // noisetex because this shared file is included by vertex and fragment
    // stages, while Iris exposes noisetex only where it is explicitly bound.
    float advect_time = float(world_age) * 0.0000000125 * WEATHER_ADVECTION_STRENGTH;
    vec2 wind = weather_wind_direction();
    vec2 drift = world_xz * (0.00000135 * WEATHER_CELL_SCALE);
    drift += wind * advect_time;

    float large0 = weather_value_noise_2d(drift);
    float large1 = weather_value_noise_2d(drift * 0.91 + vec2(17.3, -11.7));
    float medium0 = weather_value_noise_2d(drift * 2.33 + vec2(-31.1, 8.4));
    float medium1 = weather_value_noise_2d(drift * 2.33 + vec2(12.6, 23.7));

    float coverage = clamp(0.62 * large0 + 0.38 * medium1, 0.0, 1.0);
    float humidity = clamp(0.55 * large1 + 0.45 * medium0, 0.0, 1.0);
    float convection = clamp(0.55 * medium1 + 0.45 * large0, 0.0, 1.0);
    float storm = smoothstep(0.48, 0.82, coverage * 0.60 + humidity * 0.40);
    storm *= smoothstep(0.42, 0.86, convection);
    storm = clamp(storm * (1.0 + WEATHER_STORM_FEEDBACK * 0.28), 0.0, 1.0);

    return vec4(coverage, humidity, convection, storm);
}

float weather_temperature() {
    const float temperature_variation_speed = 0.37 * golden_ratio * rcp(600.0)
        * WEATHER_TEMPERATURE_VARIATION_SPEED;
    const float random_temperature_min = 0.0;
    const float random_temperature_max = 1.0;
    const float biome_temperature_influence = 0.1;

#ifdef RANDOM_WEATHER_VARIATION
    float temperature = mix(
        random_temperature_min,
        random_temperature_max,
        noise_1d(world_age * temperature_variation_speed + 2.5)
    );
#else
    float temperature = 0.5;
#endif

    // Time-of-day-based variation

    temperature -= 0.2 * time_sunrise + 0.2 * time_midnight;

    // Biome-based variation

#ifdef BIOME_WEATHER_VARIATION
    temperature
        *= 1.0 + (biome_temperature - 0.6) * biome_temperature_influence;
#endif

    // User adjustment

    temperature += WEATHER_TEMPERATURE_BIAS;

    return clamp01(temperature);
}

float weather_humidity() {
    const float humidity_variation_speed
        = 0.37 * golden_ratio * rcp(600.0) * WEATHER_HUMIDITY_VARIATION_SPEED;
    const float random_humidity_min = 0.2;
    const float random_humidity_max = 0.8;
    const float biome_humidity_influence = 0.1;

#ifdef RANDOM_WEATHER_VARIATION
    float humidity = mix(
        random_humidity_min,
        random_humidity_max,
        noise_1d(world_age * humidity_variation_speed + 46.618)
    );
#else
    float humidity = 0.5;
#endif

    // Biome-based variation

#ifdef BIOME_WEATHER_VARIATION
    humidity *= 1.0 + (biome_humidity + 0.2) * biome_humidity_influence;
#endif

    // Weather-based variation

    humidity += wetness;

    // User adjustment

    humidity += WEATHER_HUMIDITY_BIAS;

    return clamp01(humidity);
}

float weather_wind() {
    const float wind_variation_speed
        = 0.5 * golden_ratio * rcp(600.0) * WEATHER_WIND_VARIATION_SPEED;
    const float random_wind_min = 0.0;
    const float random_wind_max = 1.0;

#ifdef RANDOM_WEATHER_VARIATION
    float wind = mix(
        random_wind_min,
        random_wind_max,
        noise_1d(world_age * wind_variation_speed + 83.236)
    );
#else
    float wind = 0.5;
#endif

    // Weather-based variation

    wind += 0.33 * wetness;

    // User adjustment

    wind += WEATHER_WIND_BIAS;

    return clamp01(wind);
}

Weather get_weather(vec3 weather_origin) {
    Weather weather;

    weather.temperature = weather_temperature();
    weather.humidity = weather_humidity();
    weather.wind = weather_wind();

    vec4 field = weather_spatial_field(weather_origin.xz);
    // Spatial humidity/convection modifies the slowly varying global weather.
    weather.humidity = clamp01(mix(weather.humidity, field.y, 0.42));
    weather.convection = clamp01(field.z * (0.55 + 0.65 * weather.humidity));
    weather.storm = clamp01(field.w * (0.45 + 0.85 * weather.humidity));

    return weather;
}

#endif // INCLUDE_WEATHER_CORE
