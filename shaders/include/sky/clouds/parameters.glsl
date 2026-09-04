#if !defined INCLUDE_SKY_CLOUDS_PARAMETERS
#define INCLUDE_SKY_CLOUDS_PARAMETERS

struct CloudsParameters {
    // Cumulus congestus
    float cumulus_congestus_blend; // replaces layer 0
    // Volumetric layer 0
    vec2 l0_coverage;
    vec2 l0_detail_weights;
    vec2 l0_edge_sharpening;
    float l0_altitude_scale;
    float l0_cumulus_stratus_blend;
    float l0_extinction_coeff; // also applies for Cu Con
    float l0_scattering_coeff; // also applies for Cu Con
    float l0_shadow;
    // Volumetric layer 1
    vec2 l1_coverage;
    float l1_cumulus_stratus_blend;
    // Planar clouds
    float cirrus_amount;
    float cirrocumulus_amount;
    float noctilucent_amount;
    // Other
    float crepuscular_rays_amount;
    float l0_turbulence; // domain-warp amount for the coverage field
};

#endif // INCLUDE_SKY_CLOUDS_PARAMETERS
