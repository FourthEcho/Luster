#if !defined INCLUDE_FOG_OVERWORLD_CONSTANTS
#define INCLUDE_FOG_OVERWORLD_CONSTANTS

const uint air_fog_min_step_count = 8;
const uint air_fog_max_step_count = 25;
const float air_fog_step_count_growth = 0.1;
const float air_fog_volume_top = 320.0;
const float air_fog_volume_bottom = SEA_LEVEL - 24.0;
const vec2 air_fog_falloff_start
    = vec2(AIR_FOG_RAYLEIGH_FALLOFF_START, AIR_FOG_MIE_FALLOFF_START)
    + SEA_LEVEL;
const vec2 air_fog_falloff_half_life
    = vec2(AIR_FOG_RAYLEIGH_FALLOFF_HALF_LIFE, AIR_FOG_MIE_FALLOFF_HALF_LIFE);

// ---- Mist constants ----
// MIST_ALTITUDE    : hard ceiling (blocks) above which mist cannot exist
// MIST_FALLOFF_RATE: exp2 decay rate per block above sea level (higher = thinner layer)
// MIST_SEA_LEVEL_BIAS: shifts the mist base up/down relative to SEA_LEVEL
// MIST_SHADOW_STEPS: sun-ray steps for advanced self-shadowing
const float mist_base_scatter_coeff = 8e-3;

#endif // INCLUDE_FOG_OVERWORLD_CONSTANTS
