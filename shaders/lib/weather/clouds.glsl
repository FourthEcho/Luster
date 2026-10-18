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

#if !defined INCLUDE_WEATHER_CLOUDS
#define INCLUDE_WEATHER_CLOUDS

#include "/lib/atmos/sky/clouds/core/constants.glsl"
#include "/lib/atmos/sky/clouds/core/params.glsl"
#include "/lib/weather/core.glsl"

float cloudsCumulusCongestusBlend(Weather weather, vec2 l0Coverage) {
    float temperatureWeight = linearStep(0.5, 1.0, weather.temperature);
    float humidityWeight = linearStep(0.3, 0.9, weather.humidity);
    float windWeight = sqr(weather.wind);
    float l0HighCoverage
        = linearStep(0.45, 0.5, dot(l0Coverage, vec2(0.66, 0.33)));

    return clamp01(
        1.5 * dampen(dampen(temperatureWeight * humidityWeight * windWeight))
        * (1.0 - l0HighCoverage)
    );
}

float cloudsL0CumulusStratusBlend(Weather weather) {
    float temperatureWeight
        = dampen(linearStep(0.5, 1.0, 1.0 - weather.temperature));
    float windWeight = dampen(1.0 - weather.wind);

    return clamp01(temperatureWeight * windWeight);
}

vec2 cloudsL0Coverage(Weather weather, float cumulusCongestusBlend) {
    // very high temperature -> lower coverage
    // higher humidity -> higher coverage
    float temperatureWeight
        = 1.0 - 0.15 * linearStep(0.6, 1.0, weather.temperature);
    float humidityWeight
        = 0.4 * weather.humidity + 0.5 * sqr(weather.humidity);
    float stratusSheet = sqr(cloudsL0CumulusStratusBlend(weather));
    vec2 localVariation = vec2(-0.1, 1.0) * (0.1 + 0.1 * weather.wind);

    return clamp01(
               temperatureWeight * humidityWeight + localVariation
               + 0.3 * stratusSheet
           )
        * cloudsCumulusCoverage;
}

vec2 cloudsL0DetailWeights(Weather weather, float cumulusStratusBlend) {
    float windTornFactor
        = linearStep(0.66, 0.9, weather.wind) * (1.0 - cumulusStratusBlend);

    return mix(vec2(0.33, 0.40) * (1.0 + 0.5 * windTornFactor),
               vec2(0.07, 0.10),
               vec2(sqr(cumulusStratusBlend), cumulusStratusBlend))
        * cloudsCumulusDetailStrength;
}

vec2 cloudsL0EdgeSharpening(Weather weather, float cumulusStratusBlend) {
    return mix(vec2(3.0, 12.0), vec2(2.0, 7.0), sqr(cumulusStratusBlend));
}

float cloudsL0AltitudeScale(Weather weather, vec2 coverage) {
    float dynamicThickness
        = mix(0.5, 1.0, smoothstep(0.4, 0.6, dot(coverage, vec2(0.25, 0.75))));
    return 0.8 * rcp(dynamicThickness * cumulusLayerThickness);
}

float cloudsL1CumulusStratusBlend(Weather weather) {
    float temperatureWeight
        = linearStep(0.5, 0.66, 1.0 - weather.temperature);

    return cubicSmooth(temperatureWeight);
}

vec2 cloudsL1Coverage(Weather weather, float cumulusStratusBlend) {
    // Altocumulus: high humidity, high wind, not too high temperature
    vec2 coverageAc = (linearStep(0.4, 1.0, weather.humidity) * 0.5 + 0.5)
        * linearStep(0.4, 0.66, weather.wind)
        * (linearStep(1.0, 0.8, weather.temperature)) * vec2(0.5, 1.5);

    // Altostratus: high wind, high humidity
    vec2 coverageAs
        = vec2(linearStep(0.25, 0.45, weather.wind * weather.humidity));

    return clamp01(mix(coverageAc, coverageAs, cumulusStratusBlend))
        * cloudsAltocumulusCoverage;
}

float cloudsCirrusAmount(Weather weather) {
    float temperatureWeight = 0.6
        - 0.4 * sqr(linearStep(0.5, 0.9, weather.temperature))
        + 0.4 * (1.0 - linearStep(0.0, 0.2, weather.temperature));
    float humidityWeight
        = 1.0 - 0.5 * linearStep(0.5, 0.75, weather.humidity);

    return clamp01(
               0.5 * temperatureWeight * humidityWeight + 0.5 * rainStrength
           )
        * cloudsCirrusCoverage;
}

float cloudsCirrocumulusAmount(Weather weather) {
    float temperatureWeight
        = 1.0 - 0.3 * linearStep(0.5, 1.0, weather.temperature);
    float humidityWeight = 0.5 + 0.5 * linearStep(0.4, 1.0, weather.humidity);
    float windWeight = pow1d5(weather.wind);

    return 0.8 * dampen(temperatureWeight * humidityWeight * windWeight)
        * cloudsCirrocumulusCoverage;
}

float cloudsNoctilucentAmount() {
    float intensity = hash1(fract(float(worldDay) * goldenRatio));
    intensity = linearStep(cloudsNoctilucentRarity, 1.0, intensity);

    return dampen(intensity) * cloudsNoctilucentIntensity;
}

CloudsParams getCloudsParams(Weather weather) {
    CloudsParams params;

    // Shaping parameters

    // Volumetric layer 0 - cumulus/stratocumulus/stratus
    params.l0CumulusStratusBlend = cloudsL0CumulusStratusBlend(weather);
    params.l0Coverage
        = cloudsL0Coverage(weather, params.cumulusCongestusBlend);
    params.l0DetailWeights
        = cloudsL0DetailWeights(weather, params.l0CumulusStratusBlend);
    params.l0EdgeSharpening
        = cloudsL0EdgeSharpening(weather, params.l0CumulusStratusBlend);
    params.l0AltitudeScale
        = cloudsL0AltitudeScale(weather, params.l0Coverage);

    // Volumetric layer 1 - altocumulus/altostratus/undulatus
    params.l1CumulusStratusBlend = cloudsL1CumulusStratusBlend(weather);
    params.l1Coverage
        = cloudsL1Coverage(weather, params.l1CumulusStratusBlend);

    // Planar clouds
    params.cirrusAmount = cloudsCirrusAmount(weather);
    params.cirrocumulusAmount = cloudsCirrocumulusAmount(weather);
    params.noctilucentAmount = cloudsNoctilucentAmount();

    params.cumulusCongestusBlend
        = cloudsCumulusCongestusBlend(weather, params.l0Coverage);

    // Lighting parameters

    params.l0Shadow
        = linearStep(
              0.7,
              1.0,
              dot(params.l1Coverage, vec2(0.25, 0.75))
                  * (1.0 + params.l1CumulusStratusBlend)
          )
        * dampen(dayFactor);
    params.l0ExtinctionCoeff
        = mix(0.05, 0.1, smoothstep(0.0, 0.3, abs(sunDir.y)))
        * (1.0 - 0.33 * rainStrength) * (1.0 - 0.6 * params.l0Shadow)
        * cloudsCumulusDensity;
    params.l0ExtinctionCoeff *= 1.0
        - 0.4
            * linearStep(
                0.8,
                1.0,
                params.l0Coverage.y
                    - params.l0Coverage.y * params.l0CumulusStratusBlend
            );
    params.l0ExtinctionCoeff *= 1.0 - 0.5 * params.l0CumulusStratusBlend;
    params.l0ScatteringCoeff
        = params.l0ExtinctionCoeff * mix(1.00, 0.66, rainStrength);

    // Crepuscular rays

    params.crepuscularRaysAmount = dampen(clamp01(2.0 * weather.humidity))
        * (linearStep(
            0.45,
            0.7,
            (1.0 + 0.2 * sqr(params.l0CumulusStratusBlend))
                    * dot(params.l0Coverage, vec2(0.66, 0.33))
                + 0.09 * params.l1Coverage.y
        ));

    return params;
}

#endif // INCLUDE_WEATHER_CLOUDS
