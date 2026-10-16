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

#if !defined INCLUDE_WEATHER_CORE
#define INCLUDE_WEATHER_CORE

#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"

uniform float day_factor;

struct Weather {
    float temperature; // [0, 1]
    float humidity; // [0, 1]
    float wind; // [0, 1]
    float turbulence; // [0, 1]
};

float weather_temperature() {
    const float temperature_variation_speed = 0.37 * golden_ratio * rcp(600.0)
        * weatherTemperatureVariationSpeed;
    const float random_temperature_min = 0.0;
    const float random_temperature_max = 1.0;
    const float biome_temperature_influence = 0.1;

#ifdef randomWeatherVariation
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

#ifdef biomeWeatherVariation
    temperature
        *= 1.0 + (biome_temperature - 0.6) * biome_temperature_influence;
#endif

    // User adjustment

    temperature += weatherTemperatureBias;

    return clamp01(temperature);
}

float weather_humidity() {
    const float humidity_variation_speed
        = 0.37 * golden_ratio * rcp(600.0) * weatherHumidityVariationSpeed;
    const float random_humidity_min = 0.2;
    const float random_humidity_max = 0.8;
    const float biome_humidity_influence = 0.1;

#ifdef randomWeatherVariation
    float humidity = mix(
        random_humidity_min,
        random_humidity_max,
        noise_1d(world_age * humidity_variation_speed + 46.618)
    );
#else
    float humidity = 0.5;
#endif

    // Biome-based variation

#ifdef biomeWeatherVariation
    humidity *= 1.0 + (biome_humidity + 0.2) * biome_humidity_influence;
#endif

    // Weather-based variation

    humidity += wetness;

    // User adjustment

    humidity += weatherHumidityBias;

    return clamp01(humidity);
}

float weather_wind() {
    const float wind_variation_speed
        = 0.5 * golden_ratio * rcp(600.0) * weatherWindVariationSpeed;
    const float random_wind_min = 0.0;
    const float random_wind_max = 1.0;

#ifdef randomWeatherVariation
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

    wind += weatherWindBias;

    return clamp01(wind);
}

float weather_turbulence(Weather weather) {


    // dimension driven by wind variation with temperature-contrast and


    const float turbulence_variation_speed
        = 0.61 * golden_ratio * rcp(600.0) * weatherTurbulenceVariationSpeed;
    const float random_turbulence_min = 0.15;
    const float random_turbulence_max = 0.85;

#ifdef randomWeatherVariation
    float turbulence = mix(
        random_turbulence_min,
        random_turbulence_max,
        noise_1d(world_age * turbulence_variation_speed + 131.071)
    );
#else
    float turbulence = 0.5;
#endif

    // Gusty wind breeds turbulence; dead-calm air suppresses it
    turbulence *= 0.35 + 0.65 * weather.wind;

    // Temperature contrast (hot or cold extremes vs mild air) stirs mixing
    turbulence += 0.25 * abs(weather.temperature - 0.5);

    // Storms are turbulent
    turbulence += 0.35 * wetness;

    // User adjustment
    turbulence += weatherTurbulenceBias;

    return clamp01(turbulence);
}

Weather get_weather() {
    Weather weather;

    weather.temperature = weather_temperature();
    weather.humidity = weather_humidity();
    weather.wind = weather_wind();
    weather.turbulence = weather_turbulence(weather);

    return weather;
}

#endif // INCLUDE_WEATHER_CORE
