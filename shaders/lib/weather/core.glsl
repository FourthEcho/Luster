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

uniform float dayFactor;

struct Weather {
    float temperature; // [0, 1]
    float humidity; // [0, 1]
    float wind; // [0, 1]
    float turbulence; // [0, 1]
};

float weatherTemperature() {
    const float temperatureVariationSpeed = 0.37 * goldenRatio * rcp(600.0)
        * weatherTemperatureVariationSpeed;
    const float randomTemperatureMin = 0.0;
    const float randomTemperatureMax = 1.0;
    const float biomeTemperatureInfluence = 0.1;

#ifdef randomWeatherVariation
    float temperature = mix(
        randomTemperatureMin,
        randomTemperatureMax,
        noise1d(worldAge * temperatureVariationSpeed + 2.5)
    );
#else
    float temperature = 0.5;
#endif

    // Time-of-day-based variation

    temperature -= 0.2 * timeSunrise + 0.2 * timeMidnight;

    // Biome-based variation

#ifdef biomeWeatherVariation
    temperature
        *= 1.0 + (biomeTemperature - 0.6) * biomeTemperatureInfluence;
#endif

    // User adjustment

    temperature += weatherTemperatureBias;

    return clamp01(temperature);
}

float weatherHumidity() {
    const float humidityVariationSpeed
        = 0.37 * goldenRatio * rcp(600.0) * weatherHumidityVariationSpeed;
    const float randomHumidityMin = 0.2;
    const float randomHumidityMax = 0.8;
    const float biomeHumidityInfluence = 0.1;

#ifdef randomWeatherVariation
    float humidity = mix(
        randomHumidityMin,
        randomHumidityMax,
        noise1d(worldAge * humidityVariationSpeed + 46.618)
    );
#else
    float humidity = 0.5;
#endif

    // Biome-based variation

#ifdef biomeWeatherVariation
    humidity *= 1.0 + (biomeHumidity + 0.2) * biomeHumidityInfluence;
#endif

    // Weather-based variation

    humidity += wetness;

    // User adjustment

    humidity += weatherHumidityBias;

    return clamp01(humidity);
}

float weatherWind() {
    const float windVariationSpeed
        = 0.5 * goldenRatio * rcp(600.0) * weatherWindVariationSpeed;
    const float randomWindMin = 0.0;
    const float randomWindMax = 1.0;

#ifdef randomWeatherVariation
    float wind = mix(
        randomWindMin,
        randomWindMax,
        noise1d(worldAge * windVariationSpeed + 83.236)
    );
#else
    // Hardcoded neutral wind keeps foliage moving when variation is disabled.
    float wind = 0.5;
#endif

#ifdef biomeWeatherVariation
    // Warm, dry biomes receive slightly stronger wind; cool, humid biomes
    // receive gentler wind. Keep the biome influence deliberately subtle.
    float biomeTemperature01 = clamp01(0.5 + 0.5 * biomeTemperature);
    float biomeHumidity01 = clamp01(0.5 + 0.5 * biomeHumidity);
    float biomeWindFactor = mix(
        0.85,
        1.15,
        clamp01(0.5 * biomeTemperature01 + 0.5 * (1.0 - biomeHumidity01))
    );
    wind *= biomeWindFactor;
#endif

    // Weather-based variation

    wind += 0.33 * wetness;

    // User adjustment

    wind += weatherWindBias;

    return clamp01(wind);
}

float weatherTurbulence(Weather weather) {


    // dimension driven by wind variation with temperature-contrast and


    const float turbulenceVariationSpeed
        = 0.61 * goldenRatio * rcp(600.0) * weatherTurbulenceVariationSpeed;
    const float randomTurbulenceMin = 0.15;
    const float randomTurbulenceMax = 0.85;

#ifdef randomWeatherVariation
    float turbulence = mix(
        randomTurbulenceMin,
        randomTurbulenceMax,
        noise1d(worldAge * turbulenceVariationSpeed + 131.071)
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

Weather getWeather() {
    Weather weather;

    weather.temperature = weatherTemperature();
    weather.humidity = weatherHumidity();
    weather.wind = weatherWind();
    weather.turbulence = weatherTurbulence(weather);

    return weather;
}

#endif // INCLUDE_WEATHER_CORE
