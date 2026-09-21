#if !defined INCLUDE_SKY_CLOUDS_CLOUD_BOUNCE
#define INCLUDE_SKY_CLOUDS_CLOUD_BOUNCE

// Shared cloud multiple-scattering source used by all volumetric cloud layers.
// Returns white bounce energy per channel:
//   x = sun-channel ambient  (the call site lights it with light_color),
//   y = sky-channel ambient  (the call site lights it with sky_color),
//   z = ground-bounce energy (white; the call site tints it with the biome
//       ground albedo, so deserts bounce warm and snowfields bounce bright).
vec3 clouds_multiple_scattering_bounce(
    float extinction_coeff,
    float scattering_coeff,
    float light_optical_depth,
    float sky_optical_depth,
    float ground_optical_depth,
    float altitude_fraction,
    vec3 light_dir
) {
    vec3 bounced = vec3(0.0);
#if CLOUD_LIGHTING_BOUNCES > 0
    float single_scatter_albedo
        = clamp01(scattering_coeff * rcp(max(extinction_coeff, eps)));
    float bounce_gain = 0.55 * single_scatter_albedo;

    // Storm-core darkening: bounced orders die inside optically thick
    // columns, so precipitation cores go dark while thin edges stay lit
    float core_darkening = exp(-light_optical_depth * 0.35);

    float celestial_source = max(light_dir.y, 0.0)
        * exp(-extinction_coeff
              * (light_optical_depth + ground_optical_depth));

    float sky_source = dot(sky_color, luminance_weights)
        * exp(-extinction_coeff * sky_optical_depth);

    // Smooth base-to-top split: low samples drink ground bounce,
    // high samples drink sky ambient
    float ground_share = 1.0 - smoothstep(0.0, 1.0, altitude_fraction);
    float sky_share = 1.0 - ground_share;

    float sky_energy = sky_source;
    float ground_energy = celestial_source;
    for (int bounce = 0; bounce < 8; ++bounce) {
        if (bounce >= CLOUD_LIGHTING_BOUNCES) break;
        // Higher orders leak out of the cloud faster (escape falloff)
        float order_gain = bounce_gain * (1.0 - 0.06 * float(bounce))
            * core_darkening;
        bounced.x += sky_energy * ground_share;
        bounced.y += sky_energy * sky_share;
        bounced.z += ground_energy * ground_share;
        sky_energy *= order_gain;
        ground_energy *= order_gain;
    }
#endif
    return bounced;
}

#endif // INCLUDE_SKY_CLOUDS_CLOUD_BOUNCE
