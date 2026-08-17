#if !defined INCLUDE_FOG_VOXEL_FOG_SCATTER
#define INCLUDE_FOG_VOXEL_FOG_SCATTER

/*
  ============================================================================
  Voxel colored-light fog scattering
  ----------------------------------------------------------------------------
  Replaces the old screen-space colored fog (include/fog/sscl_fog.glsl) with
  a world-space version.  For each raymarch step along the view ray, we
  trilinear-sample the propagated voxel atlas at the step's world position
  and accumulate the resulting glow as inscattering.

  Because the voxel atlas is world-space (not screen-space), this works for
  emitters that are off-screen (as long as they were scattered into the
  atlas by Phase 2) and for emitters behind the camera (as long as they're
  within the voxel grid bounds).

  The pipeline:
    deferred8  (voxelize)        -> colortex19 (initial scatter)
    deferred9  (propagate 19->20) -> colortex20 (step 0)
    deferred10 (propagate 20->19) -> colortex19 (step 1)
    deferred11 (propagate 19->20) -> colortex20 (step 2)
    ...
    c0_vl      (this function)    -> samples the final atlas along the
                                     raymarch and adds colored inscattering
                                     to fog_scattering.

  Gated on VOXEL_COLORED_LIGHTS (the new feature flag) and COLORED_LIGHTS
  (the master toggle).  Scaled by AIR_FOG_COLORED_LIGHT_SHAFTS_INTENSITY.
  ============================================================================
*/

#include "/include/lighting/voxel/atlas.glsl"

uniform float biome_cave;

vec3 get_voxel_fog_scattering(
    vec3 world_start_pos,
    vec3 world_end_pos,
    float dither
) {
    // Per-dimension inscattering strength (mirrors the old SSCL coefficients
    // so existing user profiles continue to feel similar).
#ifdef WORLD_OVERWORLD
    float scattering_scale = 8.0 * mix(
        LPV_VL_INTENSITY_UNDERGROUND,
        LPV_VL_INTENSITY_OVERWORLD,
        biome_cave
    );
#elif defined WORLD_NETHER
    float scattering_scale = 8.0 * LPV_VL_INTENSITY_NETHER;
#else
    float scattering_scale = 8.0 * LPV_VL_INTENSITY_END;
#endif

    const float step_ratio = 1.1; // geometric step growth

    // Voxel light falls off quickly with distance from its source, so this
    // raymarch has no business covering the camera's full view distance.
    // Clamp to a local radius (in world blocks) so the per-step scattering
    // term doesn't blow up to white on long rays.
    const float voxel_fog_max_distance = 48.0;

    vec3 world_ray = world_end_pos - world_start_pos;
    float full_ray_length = length(world_ray);
    float ray_length = min(full_ray_length, voxel_fog_max_distance);
    vec3 ray_dir = world_ray * rcp(max(full_ray_length, eps));

    vec3 scattering = vec3(0.0);
    float step_length = ray_length * rcp(float(LPV_VL_STEPS));
    float transmittance = 1.0;

    for (int i = 0; i < LPV_VL_STEPS; ++i) {
        if (transmittance < 0.01) break;

        float progress
            = (float(i) + dither) * step_length * pow(step_ratio, float(i));
        progress = min(progress, ray_length);

        vec3 world_pos = world_start_pos + ray_dir * progress;

        // World-space trilinear sample of the voxel atlas.  This is the
        // straight function-signature swap from the old screen-space
        // projection + colortex19 fetch.
        vec3 glow = get_voxel_light_color(world_pos);

        scattering += glow * transmittance * scattering_scale * step_length;
        transmittance *= pow(0.99, step_length);
    }

    return scattering * rcp(float(LPV_VL_STEPS));
}

#endif // INCLUDE_FOG_VOXEL_FOG_SCATTER
