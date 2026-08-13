#if !defined INCLUDE_WEATHER_CORE
#define INCLUDE_WEATHER_CORE

#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

uniform float day_factor;

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

// Returns the daily wind direction angle in radians [0, 2π).
float weather_wind_direction_angle() {
    return weather_wind_angle;
}

struct Weather {
    float temperature; // [0, 1]
    float humidity; // [0, 1]
    float wind; // [0, 1]
};

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

Weather get_weather() {
    Weather weather;

    weather.temperature = weather_temperature();
    weather.humidity = weather_humidity();
    weather.wind = weather_wind();

    return weather;
}

#endif // INCLUDE_WEATHER_CORE
