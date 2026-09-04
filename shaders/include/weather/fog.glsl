#if !defined INCLUDE_WEATHER_FOG
#define INCLUDE_WEATHER_FOG

#include "/include/fog/overworld/parameters.glsl"
#include "/include/fog/overworld/constants.glsl"
#include "/include/utility/color.glsl"
#include "/include/weather/core.glsl"

// Sentinel guards so MIST_MODE comparisons compile even when mist.glsl
// has not been included yet (e.g. in vertex shaders).
#ifndef MIST_MODE_OFF
#define MIST_MODE_OFF      0
#define MIST_MODE_BASIC    1
#define MIST_MODE_ADVANCED 2
#endif

uniform float biome_pale_garden;

OverworldFogParameters get_fog_parameters(Weather weather) {
    OverworldFogParameters params;

    // Rayleigh coefficient

    const vec3 rayleigh_normal
        = from_srgb(
              vec3(AIR_FOG_RAYLEIGH_R, AIR_FOG_RAYLEIGH_G, AIR_FOG_RAYLEIGH_B)
          )
        * AIR_FOG_RAYLEIGH_DENSITY;
    const vec3 rayleigh_rain
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_RAIN,
              AIR_FOG_RAYLEIGH_G_RAIN,
              AIR_FOG_RAYLEIGH_B_RAIN
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_RAIN;
    const vec3 rayleigh_arid
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_ARID,
              AIR_FOG_RAYLEIGH_G_ARID,
              AIR_FOG_RAYLEIGH_B_ARID
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_ARID;
    const vec3 rayleigh_snowy
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_SNOWY,
              AIR_FOG_RAYLEIGH_G_SNOWY,
              AIR_FOG_RAYLEIGH_B_SNOWY
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_SNOWY;
    const vec3 rayleigh_taiga
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_TAIGA,
              AIR_FOG_RAYLEIGH_G_TAIGA,
              AIR_FOG_RAYLEIGH_B_TAIGA
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_TAIGA;
    const vec3 rayleigh_jungle
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_JUNGLE,
              AIR_FOG_RAYLEIGH_G_JUNGLE,
              AIR_FOG_RAYLEIGH_B_JUNGLE
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_JUNGLE;
    const vec3 rayleigh_swamp
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_SWAMP,
              AIR_FOG_RAYLEIGH_G_SWAMP,
              AIR_FOG_RAYLEIGH_B_SWAMP
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_SWAMP;
    const vec3 rayleigh_pale_garden
        = from_srgb(vec3(
              AIR_FOG_RAYLEIGH_R_PALE_GARDEN,
              AIR_FOG_RAYLEIGH_G_PALE_GARDEN,
              AIR_FOG_RAYLEIGH_B_PALE_GARDEN
          ))
        * AIR_FOG_RAYLEIGH_DENSITY_PALE_GARDEN;

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

    float mie = AIR_FOG_MIE_DENSITY_MORNING * time_sunrise
        + AIR_FOG_MIE_DENSITY_NOON * time_noon
        + AIR_FOG_MIE_DENSITY_EVENING * time_sunset
        + AIR_FOG_MIE_DENSITY_MIDNIGHT * time_midnight
        + AIR_FOG_MIE_DENSITY_BLUE_HOUR * blue_hour;

    // Weather influence
    mie = mix(
        mie
            + 8.0 * AIR_FOG_MIE_DENSITY_NOON
                * sqr(clamp01(weather.humidity * rcp(0.8))),
        AIR_FOG_MIE_DENSITY_RAIN,
        rainStrength * biome_may_rain
    );
    mie = mix(mie, AIR_FOG_MIE_DENSITY_SNOW, rainStrength * biome_may_snow);

    float mie_albedo = mix(0.9, 0.5, rainStrength * biome_may_rain);
    params.mie_scattering_coeff = vec3(mie_albedo * mie);
    params.mie_extinction_coeff = vec3(mie);

    // ---- Mist scattering coefficient ----
    // Tinted by the current Rayleigh colour so mist picks up the correct
    // time-of-day hue (orange at sunset, blue-white at dawn) without needing
    // a sky-map sample in the vertex shader.
#if MIST_MODE != MIST_MODE_OFF
    {
        vec3 horizon_tint = normalize(params.rayleigh_scattering_coeff + 1e-6);
        params.mist_scattering_coeff = mist_base_scatter_coeff
            * MIST_DENSITY * horizon_tint;
        // Thicken mist during and after rain
        params.mist_scattering_coeff *= 1.0 + 0.5 * rainStrength * biome_may_rain;
    }
#else
    params.mist_scattering_coeff = vec3(0.0);
#endif

#ifdef DESERT_SANDSTORM
    // DESERT_SANDSTORM_INTENSITY scales the sandstorm fog density and
    // extinction coefficients. Default 1.0 matches the previous constant
    // of 0.2; higher values produce thicker, more opaque sandstorms.
    const float desert_sandstorm_density = 0.2 * DESERT_SANDSTORM_INTENSITY;
    const float desert_sandstorm_scattering = desert_sandstorm_density * 0.5;
    const vec3 desert_sandstorm_extinction
        = desert_sandstorm_density * vec3(0.2, 0.27, 0.45);

    params.mie_scattering_coeff
        += desert_sandstorm * desert_sandstorm_scattering;
    params.mie_extinction_coeff
        += desert_sandstorm * desert_sandstorm_extinction;
#endif

    return params;
}

#endif // INCLUDE_WEATHER_FOG
