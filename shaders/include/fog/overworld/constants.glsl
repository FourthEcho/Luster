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
    = vec2(AIR_FOG_RAYLEIGH_FALLOFF_HALF_LIFE, AIR_FOG_MIE_FALLOFF_HALF_LIFE)
#ifdef FOG_SMOOTHING
    // Fog smoothing: enlarge the falloff half-life by the user-controlled
    // radius, which softens the altitude-based density gradient and reduces
    // harsh fog edges. A larger radius yields a smoother, more gradual fog.
    + vec2(FOG_SMOOTHING_RADIUS)
#endif
    ;

#endif // INCLUDE_FOG_OVERWORLD_CONSTANTS
