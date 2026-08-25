#if !defined INCLUDE_SKY_CLOUDS_CLOUD_BOUNCE
#define INCLUDE_SKY_CLOUDS_CLOUD_BOUNCE

// Shared cloud multiple-scattering source used by all volumetric cloud layers.
// Returns x = bounced celestial/ground source and y = bounced sky source.
vec2 clouds_multiple_scattering_bounce(
    float extinction_coeff,
    float scattering_coeff,
    float light_optical_depth,
    float sky_optical_depth,
    float ground_optical_depth,
    float altitude_fraction,
    vec3 light_dir,
    float ground_albedo
) {
    vec2 bounced = vec2(0.0);
#if CLOUD_LIGHTING_BOUNCES > 0
    float single_scatter_albedo
        = clamp01(scattering_coeff * rcp(max(extinction_coeff, eps)));
    float bounce_gain = 0.55 * single_scatter_albedo;

    float celestial_source = max(light_dir.y, 0.0)
        * ground_albedo
        * exp(-extinction_coeff
              * (light_optical_depth + ground_optical_depth));

    float sky_source = dot(sky_color, luminance_weights)
        * exp(-extinction_coeff * sky_optical_depth);

    float ground_share = 1.0 - clamp01(altitude_fraction);
    float sky_share = 1.0 - ground_share;
    float order_energy = celestial_source + sky_source;

    for (int bounce = 0; bounce < 4; ++bounce) {
        if (bounce >= CLOUD_LIGHTING_BOUNCES) break;
        bounced += order_energy * vec2(ground_share, sky_share);
        order_energy *= bounce_gain;
    }
#endif
    return bounced;
}

#endif // INCLUDE_SKY_CLOUDS_CLOUD_BOUNCE
