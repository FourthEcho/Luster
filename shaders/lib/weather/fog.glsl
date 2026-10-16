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

#include "/lib/fog/overworld/parameters.glsl"
#include "/lib/fog/overworld/constants.glsl"
#include "/lib/fog/overworld/ozone.glsl"
#include "/lib/fog/overworld/sandstorm.glsl"
#include "/lib/util/color.glsl"
#include "/lib/weather/core.glsl"

// Sentinel guards so mistMode comparisons compile even when mist.glsl
// has not been included yet (e.g. in vertex shaders).
#ifndef mistModeOff
#define mistModeOff      0
#define mistModeBasic    1
#define mistModeAdvanced 2
#endif

uniform float biome_pale_garden;

OverworldFogParameters get_fog_parameters(Weather weather) {
    OverworldFogParameters params;

    // Rayleigh coefficient

    const vec3 rayleigh_normal
        = from_display(
              vec3(airFogRayleighR, airFogRayleighG, airFogRayleighB)
          )
        * airFogRayleighDensity;
    const vec3 rayleigh_rain
        = from_display(vec3(
              airFogRayleighRRain,
              airFogRayleighGRain,
              airFogRayleighBRain
          ))
        * airFogRayleighDensityRain;
    const vec3 rayleigh_arid
        = from_display(vec3(
              airFogRayleighRArid,
              airFogRayleighGArid,
              airFogRayleighBArid
          ))
        * airFogRayleighDensityArid;
    const vec3 rayleigh_snowy
        = from_display(vec3(
              airFogRayleighRSnowy,
              airFogRayleighGSnowy,
              airFogRayleighBSnowy
          ))
        * airFogRayleighDensitySnowy;
    const vec3 rayleigh_taiga
        = from_display(vec3(
              airFogRayleighRTaiga,
              airFogRayleighGTaiga,
              airFogRayleighBTaiga
          ))
        * airFogRayleighDensityTaiga;
    const vec3 rayleigh_jungle
        = from_display(vec3(
              airFogRayleighRJungle,
              airFogRayleighGJungle,
              airFogRayleighBJungle
          ))
        * airFogRayleighDensityJungle;
    const vec3 rayleigh_swamp
        = from_display(vec3(
              airFogRayleighRSwamp,
              airFogRayleighGSwamp,
              airFogRayleighBSwamp
          ))
        * airFogRayleighDensitySwamp;
    const vec3 rayleigh_pale_garden
        = from_display(vec3(
              airFogRayleighRPaleGarden,
              airFogRayleighGPaleGarden,
              airFogRayleighBPaleGarden
          ))
        * airFogRayleighDensityPaleGarden;

    params.rayleigh_scattering_coeff = rayleigh_normal * biome_temperate
        + rayleigh_arid * biome_arid + rayleigh_snowy * biome_snowy
        + rayleigh_taiga * biome_taiga + rayleigh_jungle * biome_jungle
        + rayleigh_swamp * biome_swamp
        + rayleigh_pale_garden * biome_pale_garden;

    // rain
    params.rayleigh_scattering_coeff = mix(
        params.rayleigh_scattering_coeff
            * (1.0 + weather.humidity * weather.temperature),
        rayleigh_rain,
        rainStrength * biome_may_rain
    );

    // Mie coefficient

    // Increased mie density and scattering strength during late sunset / blue
    // hour
    float blue_hour
        = linear_step(0.05, 1.0, exp(-190.0 * sqr(sun_dir.y + 0.07283)));

    float mie = airFogMieDensityMorning * time_sunrise
        + airFogMieDensityNoon * time_noon
        + airFogMieDensityEvening * time_sunset
        + airFogMieDensityMidnight * time_midnight
        + airFogMieDensityBlueHour * blue_hour;

    // Weather influence
    mie = mix(
        mie
            + 8.0 * airFogMieDensityNoon
                * sqr(clamp01(weather.humidity * rcp(0.8))),
        airFogMieDensityRain,
        rainStrength * biome_may_rain
    );
    mie = mix(mie, airFogMieDensitySnow, rainStrength * biome_may_snow);

    float mie_albedo = mix(0.9, 0.5, rainStrength * biome_may_rain);
    // User Mie tint: same multiplier the sky's Mie coefficient uses, so haze
    // in the sky and air fog stay the same colour.
    const vec3 mie_tint = vec3(mieColorR, mieColorG, mieColorB);
    params.mie_scattering_coeff = vec3(mie_albedo * mie) * mie_tint;
    params.mie_extinction_coeff = vec3(mie) * mie_tint;

    // ---- Mist scattering coefficient ----
    // Tinted by the current Rayleigh colour so mist picks up the correct


#if mistMode != mistModeOff
    {
        vec3 horizon_tint = normalize(params.rayleigh_scattering_coeff + 1e-6);

#if defined ozoneLayer && defined ozoneMist


#if mistMode == mistModeAdvanced
        float mist_ozone_mu = sun_dir.y;
#else
        float mist_ozone_mu = 0.1;
#endif
        vec3 ozone_filtered = horizon_tint
            * ozone_layer_transmittance(mist_ozone_mu, ozone_planet_radius);
        float twilight = linear_step(0.7, 1.0, 1.0 - abs(sun_dir.y));
        horizon_tint = mix(
            horizon_tint,
            normalize(ozone_filtered + 1e-6),
            twilight
        );
#endif
#if defined desertSandstorm && defined sandstormMist


        horizon_tint = normalize(mix(
            horizon_tint,
            sandstorm_tint(),
            sandstorm_strength()
        ) + 1e-6);
#endif

        params.mist_scattering_coeff = mist_base_scatter_coeff
            * mistDensity * horizon_tint
            * vec3(mistColorR, mistColorG, mistColorB);
        // Thicken mist during and after rain
        params.mist_scattering_coeff *= 1.0 + 0.5 * rainStrength * biome_may_rain;
    }
#else
    params.mist_scattering_coeff = vec3(0.0);
#endif

#ifdef desertSandstorm


    const float desert_sandstorm_density = 0.2 * desertSandstormIntensity;
    const float desert_sandstorm_scattering = desert_sandstorm_density * 0.5;
    const vec3 desert_sandstorm_extinction
        = desert_sandstorm_density * vec3(0.2, 0.27, 0.45);

    params.mie_scattering_coeff
        += desert_sandstorm * desert_sandstorm_scattering;
    params.mie_extinction_coeff
        += desert_sandstorm * desert_sandstorm_extinction;
#endif


    params.rayleigh_scattering_coeff
        = gamut_expand(params.rayleigh_scattering_coeff);

    return params;
}

#endif // INCLUDE_WEATHER_FOG
