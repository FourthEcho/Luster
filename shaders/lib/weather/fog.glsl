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

#if !defined INCLUDE_WEATHER_FOG
#define INCLUDE_WEATHER_FOG

#include "/lib/atmos/air/overworld/params.glsl"
#include "/lib/atmos/air/overworld/constants.glsl"
#include "/lib/atmos/air/overworld/aerosols.glsl"
#include "/lib/util/color.glsl"
#include "/lib/weather/core.glsl"

uniform float biomePaleGarden;

OverworldFogParams getFogParams(Weather weather) {
    OverworldFogParams params;

    // Rayleigh coefficient

    const vec3 rayleighNormal
        = fromDisplay(
              vec3(airFogRayleighR, airFogRayleighG, airFogRayleighB)
          )
        * airFogRayleighDensity;
    const vec3 rayleighRain
        = fromDisplay(vec3(
              airFogRayleighRRain,
              airFogRayleighGRain,
              airFogRayleighBRain
          ))
        * airFogRayleighDensityRain;
    const vec3 rayleighArid
        = fromDisplay(vec3(
              airFogRayleighRArid,
              airFogRayleighGArid,
              airFogRayleighBArid
          ))
        * airFogRayleighDensityArid;
    const vec3 rayleighSnowy
        = fromDisplay(vec3(
              airFogRayleighRSnowy,
              airFogRayleighGSnowy,
              airFogRayleighBSnowy
          ))
        * airFogRayleighDensitySnowy;
    const vec3 rayleighTaiga
        = fromDisplay(vec3(
              airFogRayleighRTaiga,
              airFogRayleighGTaiga,
              airFogRayleighBTaiga
          ))
        * airFogRayleighDensityTaiga;
    const vec3 rayleighJungle
        = fromDisplay(vec3(
              airFogRayleighRJungle,
              airFogRayleighGJungle,
              airFogRayleighBJungle
          ))
        * airFogRayleighDensityJungle;
    const vec3 rayleighSwamp
        = fromDisplay(vec3(
              airFogRayleighRSwamp,
              airFogRayleighGSwamp,
              airFogRayleighBSwamp
          ))
        * airFogRayleighDensitySwamp;
    const vec3 rayleighPaleGarden
        = fromDisplay(vec3(
              airFogRayleighRPaleGarden,
              airFogRayleighGPaleGarden,
              airFogRayleighBPaleGarden
          ))
        * airFogRayleighDensityPaleGarden;

    params.rayleighScatteringCoeff = rayleighNormal * biomeTemperate
        + rayleighArid * biomeArid + rayleighSnowy * biomeSnowy
        + rayleighTaiga * biomeTaiga + rayleighJungle * biomeJungle
        + rayleighSwamp * biomeSwamp
        + rayleighPaleGarden * biomePaleGarden;

    // rain
    params.rayleighScatteringCoeff = mix(
        params.rayleighScatteringCoeff
            * (1.0 + weather.humidity * weather.temperature),
        rayleighRain,
        rainStrength * biomeMayRain
    );

    // Mie coefficient

    // Increased mie density and scattering strength during late sunset / blue
    // hour
    float blueHour
        = linearStep(0.05, 1.0, exp(-190.0 * sqr(sunDir.y + 0.07283)));

    float mie = airFogMieDensityMorning * timeSunrise
        + airFogMieDensityNoon * timeNoon
        + airFogMieDensityEvening * timeSunset
        + airFogMieDensityMidnight * timeMidnight
        + airFogMieDensityBlueHour * blueHour;

    // Weather influence
    mie = mix(
        mie
            + 8.0 * airFogMieDensityNoon
                * sqr(clamp01(weather.humidity * rcp(0.8))),
        airFogMieDensityRain,
        rainStrength * biomeMayRain
    );
    mie = mix(mie, airFogMieDensitySnow, rainStrength * biomeMaySnow);

    float mieAlbedo = mix(0.9, 0.5, rainStrength * biomeMayRain);
    // User Mie tint: same multiplier the sky's Mie coefficient uses, so haze
    // in the sky and air fog stay the same colour.
    const vec3 mieTint = vec3(mieColorR, mieColorG, mieColorB);
    params.mieScatteringCoeff = vec3(mieAlbedo * mie) * mieTint;
    params.mieExtinctionCoeff = vec3(mie) * mieTint;

    params.rayleighScatteringCoeff
        = gamutExpand(params.rayleighScatteringCoeff);

    params.mistScatteringCoeff = mistBaseScatterCoeff
        * mistDensity
        * vec3(mistColorR, mistColorG, mistColorB);

#ifdef desertSandstorm
    // A sandstorm buries the layer in dust no matter how thin the mist is
    // set to be — the storm density dominates over the user's coefficient.
    params.mistScatteringCoeff = max(
        params.mistScatteringCoeff,
        vec3(sandstormStrength() * 12.0)
    );
#endif

#ifdef desertSandstorm


    const float desertSandstormDensity = 0.2 * desertSandstormIntensity;
    const float desertSandstormScattering = desertSandstormDensity * 0.5;
    const vec3 desertSandstormExtinction
        = desertSandstormDensity * vec3(0.2, 0.27, 0.45);

    params.mieScatteringCoeff
        += desertSandstormWeather * desertSandstormScattering;
    params.mieExtinctionCoeff
        += desertSandstormWeather * desertSandstormExtinction;
#endif


    return params;
}

#endif // INCLUDE_WEATHER_FOG
