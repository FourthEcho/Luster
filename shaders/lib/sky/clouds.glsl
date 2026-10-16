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

#if !defined INCLUDE_SKY_CLOUDS
#define INCLUDE_SKY_CLOUDS

#include "/lib/sky/clouds/altocumulus.glsl"
#include "/lib/sky/clouds/cirrus.glsl"
#include "/lib/sky/clouds/cumulus.glsl"
#include "/lib/sky/clouds/cumulusCongestus.glsl"
#if !defined INCLUDE_SKY_CLOUDS_NOCTILUCENT
#define INCLUDE_SKY_CLOUDS_NOCTILUCENT

// 4th layer: Noctilucent clouds

#include "/lib/sky/clouds/common.glsl"

float clouds_noctilucent_density(vec2 coord, vec3 ray_dir) {
    coord *= 0.25;

    vec2 curl = curl2D(0.00002 * coord) * 0.5 + curl2D(0.00004 * coord) * 0.25
        + curl2D(0.00008 * coord) * 0.125;

    float density = dampen(texture(noisetex, 0.000001 * coord + 0.02 * curl).y);

    float detail_amplitude = 0.3;
    float detail_frequency = 0.00001;
    float curl_strength = 0.05;

    for (int i = 0; i < 4; ++i) {
        float detail
            = texture(noisetex, coord * detail_frequency + curl * curl_strength)
                  .y;

        density += detail * detail_amplitude;

        detail_amplitude *= 0.5;
        detail_frequency *= 1.5;
        curl_strength *= 4.0;
    }

    float highlight
        = dampen(texture(noisetex, 0.000004 * coord + 0.02 * curl).y);
    highlight
        -= (1.0 - texture(noisetex, 0.000014 * coord + 0.05 * curl).y) * 0.15;

    density += 2.0 * pow8(max0(highlight));

    return sqr(max0(density)) * clouds_params.noctilucent_amount;
}

vec4 draw_noctilucent_clouds(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky
) {
    const vec3 color = 0.35 * vec3(1.5, 2.0, 9.0);
    const float phase_g = 0.8;
    const float extinction_coeff = 0.001;

    float visibility = pulse(sun_dir.y, -0.10, 0.1);

    if (visibility < eps || clouds_params.noctilucent_amount < eps) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    // ---------------
    //   Ray Casting
    // ---------------

    float r = length(air_viewer_pos);

    vec2 dists
        = intersect_sphere(air_viewer_pos, ray_dir, clouds_noctilucent_radius);
    bool planet_intersected
        = intersect_sphere(
              air_viewer_pos,
              ray_dir,
              min(r - 10.0, planet_radius)
          )
              .y
        >= 0.0;

    if (
        dists.y < 0.0 // sphere not intersected
        || planet_intersected
            && r < clouds_noctilucent_radius // planet blocking clouds
    ) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    float distance_to_sphere = (r < clouds_cirrus_radius) ? dists.y : dists.x;
    vec3 sphere_pos = air_viewer_pos + ray_dir * distance_to_sphere;

    // ------------------
    //   Cloud Lighting
    // ------------------

    float density = clouds_noctilucent_density(sphere_pos.xz, ray_dir);
    float transmittance = exp(-extinction_coeff * density);

    float phase = henyey_greenstein_phase(dot(ray_dir, sun_dir), phase_g);
    vec3 scattering = visibility * color * density * phase;
    scattering = clouds_aerial_perspective(
        scattering,
        transmittance,
        air_viewer_pos,
        sphere_pos,
        ray_dir,
        clear_sky
    );

    return vec4(scattering, transmittance);
}

#endif // INCLUDE_SKY_CLOUDS_NOCTILUCENT


bool clouds_early_exit(CloudsResult result, float r, float layer_radius) {
    bool has_congestus = clouds_params.cumulus_congestus_blend > eps;

    return result.transmittance < 1e-3 && r < layer_radius
        && (result.apparent_distance < clouds_cumulus_congestus_distance
            || !has_congestus);
}

CloudsResult draw_clouds(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky,
    float distance_to_terrain,
    float dither
) {
    CloudsResult result = clouds_not_hit;
    float r = length(air_viewer_pos);

#ifdef cloudsCumulus
    result = draw_cumulus_clouds(
        air_viewer_pos,
        ray_dir,
        clear_sky,
        distance_to_terrain,
        dither
    );
    if (clouds_early_exit(result, r, clouds_cumulus_radius)) {
        return result;
    }
#endif

#ifdef cloudsAltocumulus
    CloudsResult result_ac = draw_altocumulus_clouds(
        air_viewer_pos,
        ray_dir,
        clear_sky,
        distance_to_terrain,
        dither
    );
    result = blend_layers(result, result_ac);
    if (clouds_early_exit(result, r, clouds_altocumulus_radius)) {
        return result;
    }
#endif

#ifdef cloudsCumulusCongestus
    if (clouds_params.cumulus_congestus_blend > eps) {
        CloudsResult result_cu_con = draw_cumulus_congestus_clouds(
            air_viewer_pos,
            ray_dir,
            clear_sky,
            distance_to_terrain,
            dither
        );

        // fade existing clouds into congestus
        float distance_fade = mix(
            1.0,
            result_cu_con.transmittance,
            linear_step(
                0.75,
                1.0,
                result.apparent_distance
                    * rcp(clouds_cumulus_congestus_distance)
            )
        );
        result.scattering *= distance_fade;
        result.transmittance
            += (1.0 - result.transmittance) * (1.0 - distance_fade);
        result.apparent_distance = mix(
            result_cu_con.apparent_distance,
            result.apparent_distance,
            distance_fade
        );

        result = blend_layers(result, result_cu_con);
        if (result.transmittance < 1e-3) {
            return result;
        }
    }
#endif

#ifdef cloudsCirrus
    CloudsResult result_ci = draw_cirrus_clouds(
        air_viewer_pos,
        ray_dir,
        clear_sky,
        distance_to_terrain,
        dither
    );
    result = blend_layers(result, result_ci);
    if (result.transmittance < 1e-3) {
        return result;
    }
#endif

#ifdef cloudsNoctilucent
    vec4 result_nlc
        = draw_noctilucent_clouds(air_viewer_pos, ray_dir, clear_sky);
    result.scattering.rgb += result_nlc.xyz * result.transmittance;
    result.transmittance *= result_nlc.w;
#endif

    return result;
}

#endif // INCLUDE_SKY_CLOUDS
