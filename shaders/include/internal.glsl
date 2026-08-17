#if !defined INCLUDE_INTERNAL_SETTINGS
#define INCLUDE_INTERNAL_SETTINGS

// ============================================================================
//  Internal tuning constants
//
//  These options were previously defined in settings.glsl but were intentionally
//  hidden from the user-facing GUI. They have been moved here so that
//  settings.glsl contains only user-tunable options. Edit the values in this
//  file directly if you want to change internal shader behaviour.
//
//  Consumed by: every shader pass that #include's /include/global.glsl.
// ============================================================================

// ----------------------------------------------------------------------------
//  World
// ----------------------------------------------------------------------------

  // Sea level used by cloud shadows and air-fog vertical falloff.
  // Vanilla default: y = 63.
  #define SEA_LEVEL 63.0

  // Vanilla ambient occlusion multiplier applied on top of the in-shader AO.
  // 1.00 = vanilla strength, 0.00 = vanilla AO disabled.
  #define VANILLA_AO_INTENSITY 1.00

  // Apply shadowed-SSS ambient occlusion to direct sunlight. Disabling it
  // makes outdoor scenes look slightly flatter.
  #define AO_IN_SUNLIGHT

  // Inject vanilla lightning flash into ambient + sky lighting during storms.
  #define LIGHTNING_FLASH

  // NOTE: HANDHELD_LIGHTING is a *derived* flag — it is defined in
  // settings.glsl whenever the user-facing HANDHELD_LIGHTING_MODE selector
  // is set to anything other than HANDHELD_LIGHTING_OFF. Do not hardcode
  // here.

// ----------------------------------------------------------------------------
//  Shadows
// ----------------------------------------------------------------------------

  // Sub-surface scattering step count used during blocker search.
  // Higher = softer SSS penumbra at higher cost.
  #define SSS_STEPS 12

  // PCF step count scaling factor. Multiplies the adaptive step count derived
  // from the penumbra size; 1.0 = use the SHADOW_PCF_STEPS_MIN/MAX range as-is.
  #define SHADOW_PCF_STEPS_SCALE 1.0

  // Adaptive PCF step-count range consumed by include/lighting/shadows/pcss.glsl
  // in shadow_pcf().  The actual step count per pixel is computed as:
  //     step_count = clamp(int(MIN + SCALE * filter_scale), MIN, MAX)
  // where `filter_scale` is derived from the penumbra size relative to the
  // minimum filter radius.  These were previously GUI sliders but had no
  // user-perceivable effect over a sensible fixed range; they are now
  // hardcoded here.  Profiles may still override them via shaders.properties
  // profile directives — the #ifndef guard below lets those overrides win
  // without producing a redefinition error.
  //   4 / 8  → matches the previous profile.low / profile.medium defaults.
  //   8 / 16 → profile.ultra override (still respected if the user picks
  //            the Ultra profile).
  #ifndef SHADOW_PCF_STEPS_MIN
    #define SHADOW_PCF_STEPS_MIN 4
  #endif
  #ifndef SHADOW_PCF_STEPS_MAX
    #define SHADOW_PCF_STEPS_MAX 8
  #endif

  // Search radius (in shadow clip space units) for the PCSS blocker search.
  #define SHADOW_BLOCKER_SEARCH_RADIUS 0.5

  // Depth scale applied when reading the shadow map; smaller = tighter depth
  // bias but more peter-panning, larger = more light-bleeding.
  #define SHADOW_DEPTH_SCALE 0.2

  // Shadow frustum distortion factor. Higher = more area sampled near the
  // camera at the cost of precision at the edges.
  #define SHADOW_DISTORTION 0.85

// ----------------------------------------------------------------------------
//  Sky / atmosphere
// ----------------------------------------------------------------------------


  // Maximum number of temporal accumulation frames for the volumetric cloud
  // buffer before history is reset.
  #define CLOUDS_ACCUMULATION_LIMIT 20

  // Vertical thickness (in world blocks) of the cirrus cloud layer.
  #define CLOUDS_CIRRUS_THICKNESS 1500.0

// ----------------------------------------------------------------------------
//  Fog
// ----------------------------------------------------------------------------

  // Pale Garden biome air-fog Rayleigh scattering coefficients.
  #define AIR_FOG_RAYLEIGH_DENSITY_PALE_GARDEN 0.03
  #define AIR_FOG_RAYLEIGH_R_PALE_GARDEN       0.90
  #define AIR_FOG_RAYLEIGH_G_PALE_GARDEN       0.80
  #define AIR_FOG_RAYLEIGH_B_PALE_GARDEN       1.00

  // Mie scattering density used during snowfall.
  #define AIR_FOG_MIE_DENSITY_SNOW 0.015

  // Volumetric noise modulation in cloudy weather (Rayleigh + Mie channels).
  #define AIR_FOG_CLOUDY_NOISE

  // Master intensity multiplier for the Nether fog volume.
  #define NETHER_FOG_INTENSITY 1.00

// ----------------------------------------------------------------------------
//  Surface materials
// ----------------------------------------------------------------------------

  // Use the shader's hardcoded emission table when a block does not provide
  // its own emission in the labPBR texture.
  #define HARDCODED_EMISSION

  // Use the shader's hardcoded sub-surface scattering table for blocks that
  // don't ship a labPBR SSS map.
  #define HARDCODED_SSS

  // Master multiplier for block emission. 1.00 = labPBR values used as-is.
  #define EMISSION_STRENGTH 1.00

// ----------------------------------------------------------------------------
//  Water
// ----------------------------------------------------------------------------

  // Underwater volumetric absorption + scattering coefficients. These differ
  // from the surface-water values because the camera is fully submerged.
  #define WATER_ABSORPTION_R_UNDERWATER 0.20
  #define WATER_ABSORPTION_G_UNDERWATER 0.08
  #define WATER_ABSORPTION_B_UNDERWATER 0.04
  #define WATER_SCATTERING_UNDERWATER   0.03

// ----------------------------------------------------------------------------
//  Post-processing
// ----------------------------------------------------------------------------

  // Bloom upsampling filter function. Allowed values:
  //   texture         - bilinear hardware sampling (cheap, default)
  //   bicubic_filter  - bicubic filter for sharper bloom
  // The macro is invoked as BLOOM_UPSAMPLING_FILTER(sampler, uv).
  #define BLOOM_UPSAMPLING_FILTER texture

#endif // INCLUDE_INTERNAL_SETTINGS
