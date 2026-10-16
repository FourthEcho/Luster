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

#if !defined INCLUDE_FOG_NETHER_FOG_VL
#define INCLUDE_FOG_NETHER_FOG_VL

#include "/lib/light/distortion.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

float nether_fog_density(vec3 world_pos) {
    const float falloff_start = 64.0;
    const float falloff_half_life = 7.0;

    const float mul = -rcp(falloff_half_life);
    const float add = -mul * falloff_start;

    float density = exp2(min(world_pos.y * mul + add, 0.0));

    // fade away below the island
    density *= linear_step(0.0, 64.0, world_pos.y);

    return density;
}


vec3 nether_wind_offset(vec3 wind, float t) {
    float gust_phase = 2.2 * sin(t * 0.23 + 1.3) + 3.5 * sin(t * 0.071 + 0.5);
    return wind * (3.5 * t + gust_phase);
}

vec3 nether_fog_emission(vec3 world_pos) {
    vec3 main_col;
#ifdef netherUseBiomeColor
    main_col = srgb_eotf_inv(clamp(fogColor, 0.0, 1.0)) * rec709_to_working_color;
    main_col /= max(dot(main_col, luminance_weights), eps);
    main_col = mix(vec3(1.0), main_col, netherS);
#else
    main_col = gamut_expand(from_display(vec3(netherR, netherG, netherB)));
#endif
    main_col *= netherI;

    const vec3 alt_col = gamut_expand(from_display(vec3(netherR * 0.65, netherG * 0.18, max(netherB * 0.10, 0.002))));
    const vec3 wind0 = vec3(1.0, 0.1, 0.5) * 0.01;
    const vec3 wind1 = vec3(-0.7, -0.1, -0.1) * 0.05;
    const vec3 wind2 = vec3(0.3, 0.05, -0.4) * 0.01;

    float base_noise = texture(
        colortex0,
        0.02 * world_pos + nether_wind_offset(wind0, frameTimeCounter)
    ).x;
    float detail_noise = texture(
        colortex0,
        0.04 * world_pos + nether_wind_offset(wind1, frameTimeCounter)
    ).x
            * 0.8
        - 0.4;
    float color_noise = texture(
        colortex0,
        0.02 * world_pos + 0.2 + nether_wind_offset(wind2, frameTimeCounter)
    ).x;

    float density = max0(linear_step(0.6, 0.9, base_noise) + detail_noise);
    float color_mix = linear_step(0.5, 0.7, color_noise);

    float view_dist = distance(world_pos, cameraPosition);
    float fade_near = 1.0 - exp2(-0.1 * view_dist);
    float fade_far = exp2(-0.05 * view_dist);
    float fade_height = exp2(-0.05 * max0(cameraPosition.y - 120.0))
        * linear_step(0.0, 64.0, world_pos.y);

    return mix(main_col, alt_col, color_mix)
        * (density * fade_near * fade_far * fade_height);
}


#ifdef netherSmoke
vec3 nether_smoke_v2_emission(vec3 world_pos, vec3 world_start_pos) {
    vec3 main_col;
#ifdef netherUseBiomeColor
    main_col = srgb_eotf_inv(clamp(fogColor, 0.0, 1.0)) * rec709_to_working_color;
    main_col /= max(dot(main_col, luminance_weights), eps);
    main_col = mix(vec3(1.0), main_col, netherS);
#else
    main_col = gamut_expand(from_display(vec3(netherR, netherG, netherB)));
#endif
    main_col *= netherI;

    // Warm ember color the glow blends toward as smoke gets closer/thicker
    const vec3 ember_col = gamut_expand(from_display(vec3(1.0, 0.35, 0.05)));

    const vec3 wind0 = vec3(1.0, 0.1, 0.5) * 0.01;
    const vec3 wind1 = vec3(-0.7, -0.1, -0.1) * 0.05;


    vec3 warp_pos = world_pos * 0.02;
    warp_pos += (texture(
        colortex0,
        warp_pos * 2.0 + nether_wind_offset(wind0, frameTimeCounter)
    ).x * 2.0 - 1.0) * 0.03;
    warp_pos += (texture(
        colortex0,
        warp_pos * 4.0 + nether_wind_offset(wind1, frameTimeCounter)
    ).x * 2.0 - 1.0) * 0.015;

    float base_noise = texture(
        colortex0,
        warp_pos + nether_wind_offset(wind0, frameTimeCounter)
    ).x;
    float detail_noise = texture(
        colortex0,
        warp_pos * 2.0 + nether_wind_offset(wind1, frameTimeCounter)
    ).x * 0.8 - 0.4;

    float height_fade = sqr(1.0 - linear_step(128.0, 256.0, world_pos.y))
        * (exp2(-max0(world_pos.y - 32.0) * 0.02) * 0.6 + 0.4)
        * linear_step(0.0, 64.0, world_pos.y);

    float density = max0(linear_step(0.55, 0.85, base_noise) + detail_noise) * height_fade;


    float dist_to_camera = distance(world_pos, world_start_pos);
    float glow_proximity = sqrt(clamp01(linear_step(24.0, 4.0, dist_to_camera)));
    float glow = clamp01((glow_proximity * (0.3 + cube(height_fade) * 0.15) - detail_noise) * pi)
        * height_fade;

    float fade_near = 1.0 - exp2(-0.1 * dist_to_camera);
    float fade_far = exp2(-0.05 * dist_to_camera);

    vec3 col = mix(main_col, ember_col, glow) * density;
    return col * (fade_near * fade_far);
}
#endif

mat2x3 raymarch_nether_fog(
    vec3 world_start_pos,
    vec3 world_end_pos,
    bool sky,
    float dither
) {
    const uint min_step_count = 16;
    const uint max_step_count = 25;
    const float volume_top = 256.0;
    const float volume_bottom = 0.0;
    const float step_count_growth = 0.5;

    vec3 nether_color;
#ifdef netherUseBiomeColor
    nether_color = srgb_eotf_inv(clamp(fogColor, 0.0, 1.0)) * rec709_to_working_color;
    nether_color /= max(dot(nether_color, luminance_weights), eps);
    nether_color = mix(vec3(1.0), nether_color, netherS);
#else
    nether_color = gamut_expand(from_display(vec3(netherR, netherG, netherB)));
#endif
    const float density_scale = 0.01;
    vec3 absorption_coeff = exp2(-nether_color) * density_scale;
    const vec3 scattering_coeff = vec3(1.0) * density_scale;
    vec3 extinction_coeff = absorption_coeff + scattering_coeff;

    const uint multiple_scattering_iterations = 4;

    vec3 world_dir = world_end_pos - world_start_pos;
    float ray_length;
    length_normalize(world_dir, world_dir, ray_length);

    float distance_to_lower_plane = (volume_bottom - eyeAltitude) / world_dir.y;
    float distance_to_upper_plane = (volume_top - eyeAltitude) / world_dir.y;
    float distance_to_volume_start, distance_to_volume_end;

    if (eyeAltitude < volume_bottom) {
        // Below volume
        distance_to_volume_start = distance_to_lower_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? -1.0 : distance_to_upper_plane;
    } else if (eyeAltitude < volume_top) {
        // Inside volume
        distance_to_volume_start = 0.0;
        distance_to_volume_end = world_dir.y < 0.0
            ? distance_to_lower_plane
            : distance_to_upper_plane;
    } else {
        // Above volume
        distance_to_volume_start = distance_to_upper_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? distance_to_upper_plane : -1.0;
    }

    if (distance_to_volume_end < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    ray_length = sky ? distance_to_volume_end : ray_length;
    ray_length = clamp(ray_length - distance_to_volume_start, 0.0, far);

    // Adjust step count based on ray length
    uint step_count
        = uint(float(min_step_count) + step_count_growth * ray_length);
    step_count = min(step_count, max_step_count);

    float step_length = ray_length * rcp(float(step_count));
    vec3 world_step = world_dir * step_length;

    // Jitter ray origin
    vec3 world_pos = world_start_pos
        + world_dir * (distance_to_volume_start + step_length * dither);

    // Space conversions

    vec3 shadow_pos = transform(shadowModelView, world_pos - cameraPosition);
    shadow_pos = project_ortho(shadowProjection, shadow_pos);

    vec3 shadow_step = mat3(shadowModelView) * world_step;
    shadow_step = diagonal(shadowProjection).xyz * shadow_step;

    // Calculations moved out of the loop

    float LoV = dot(world_dir, light_dir);

    vec3 scattering = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    for (int i = 0; i < step_count;
         ++i, world_pos += world_step, shadow_pos += shadow_step) {
        vec3 shadow_screen_pos = distort_shadow_space(shadow_pos) * 0.5 + 0.5;

#ifdef shadow
        ivec2 shadow_texel = ivec2(
            shadow_screen_pos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );
        float depth0 = texelFetch(shadowtex0, shadow_texel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        float shadowVis = step(
            float(clamp01(shadow_screen_pos) == shadow_screen_pos)
                * shadow_screen_pos.z,
            depth1
        );
#else
#define shadowVis 1.0
#endif


        float billow = mix(
            0.55,
            1.45,
            texture(
                colortex0,
                0.02 * world_pos
                    + nether_wind_offset(
                          vec3(0.8, 0.15, 0.4) * 0.01,
                          frameTimeCounter
                      )
            ).x
        );
        float density = nether_fog_density(world_pos) * billow * step_length;

        vec3 step_optical_depth = extinction_coeff * density;
        vec3 step_transmittance = exp(-step_optical_depth);
        vec3 step_transmitted_fraction
            = (1.0 - step_transmittance) / max(step_optical_depth, eps);

        vec3 visible_scattering = step_transmitted_fraction * transmittance;

        float anisotropy = 1.0;
        float scattering_amount = 1.0;
        for (uint i = 0u; i < multiple_scattering_iterations; ++i) {
            float mie_phase
                = 0.7 * henyey_greenstein_phase(LoV, 0.5 * anisotropy)
                + 0.3 * isotropic_phase;

            // Sunlight
            scattering += density * light_color * mie_phase * shadowVis
                * visible_scattering * scattering_amount;

            // Ambient light
            scattering += density * ambient_color * isotropic_phase
                * visible_scattering * scattering_amount;

            anisotropy *= 0.5;
            scattering_amount *= 0.5;
        }

#if defined netherFogGlow || defined endGlow
        // Emission
#ifdef netherSmoke
        scattering
            += 4.0 * nether_smoke_v2_emission(world_pos, world_start_pos)
                * step_length * transmittance * netherSmokeIntensity;
#else
        scattering
            += 4.0 * nether_fog_emission(world_pos) * step_length * transmittance;
#endif
#endif

        transmittance *= step_transmittance;
    }

    scattering *= scattering_coeff;
    transmittance = pow(transmittance, vec3(0.75));

    return mat2x3(scattering, transmittance);
}

#ifdef shadowVis
#undef shadowVis
#endif

#endif // INCLUDE_FOG_NETHER_FOG_VL
