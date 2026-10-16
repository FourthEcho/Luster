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

#if !defined INCLUDE_LIGHTING_DIRECT_LIGHTING_PCSS
#define INCLUDE_LIGHTING_DIRECT_LIGHTING_PCSS

#if defined shadow && (defined WORLD_OVERWORLD || defined WORLD_END)

#include "/lib/light/common.glsl"
#include "/lib/light/distortion.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/sampling.glsl"

const ivec2[9] blur_kernel_offsets_3x3 = ivec2[9](
    ivec2(-1, -1),
    ivec2(0, -1),
    ivec2(1, -1),
    ivec2(-1, 0),
    ivec2(0, 0),
    ivec2(1, 0),
    ivec2(-1, 1),
    ivec2(0, 1),
    ivec2(1, 1)
);

const int shadow_map_res = int(float(shadowMapResolution) * MC_SHADOW_QUALITY);
const float shadow_map_pixel_size = rcp(float(shadow_map_res));

vec2 blocker_search(vec3 scene_pos, float dither, bool has_sss) {
    int step_count = has_sss ? sssSteps : shadowVpsQuality;

    vec3 shadow_view_pos = transform(shadowModelView, scene_pos);
    vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);
    float ref_z = shadow_clip_pos.z * (shadowDepthScale * 0.5) + 0.5;

    float radius = shadowBlockerSearchRadius * shadowProjection[0].x
        * (0.5 + 0.5 * linear_step(0.2, 0.4, light_dir.y));

    float depth_sum = 0.0;
    float weight_sum = 0.0;
    float depth_sum_sss = 0.0;

    for (int i = 0; i < step_count; ++i) {
        vec2 offset = vogel_disc_sample(i, step_count, dither * tau) * radius;
        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        if (clamp01(uv) != uv) {
            continue; // out of shadow map: undefined texelFetch
        }

        float depth = texelFetch(shadowtex0, ivec2(uv * shadow_map_res), 0).x;
        float weight = step(depth, ref_z);

        depth_sum += weight * depth;
        weight_sum += weight;
        depth_sum_sss += max0(ref_z - depth);
    }

    float blocker_depth = weight_sum == 0.0 ? 0.0 : depth_sum / weight_sum;
    // Ortho chain: d_view = d_clip / proj[2].z and d_clip = 2 * d_ref /
    // shadowDepthScale, hence the factor 2
    float sss_depth = -2.0 * shadowProjectionInverse[2].z * depth_sum_sss
        * rcp(shadowDepthScale * float(step_count));

    return vec2(blocker_depth, sss_depth);
}

vec3 shadow_basic(vec3 shadow_screen_pos) {
    float shadowVis = texture(shadowtex1, shadow_screen_pos);

#ifdef shadowColor
    ivec2 texel = ivec2(shadow_screen_pos.xy * shadow_map_res);

    float depth = texelFetch(shadowtex0, texel, 0).x;
    vec3 color = texelFetch(shadowcolor0, texel, 0).rgb * 4.0;
    float weight = step(depth, shadow_screen_pos.z);

    vec3 averageColor = vec3(0.0);
    for (int i = 0; i < 9; ++i) {
        averageColor
            += texelFetch(shadowcolor0, texel + blur_kernel_offsets_3x3[i], 0)
                   .rgb;
    }
    // hide sunlight seams between colored shadow and opaque shadows
    weight *= step(eps, max_of(averageColor));

    color = color * weight + (1.0 - weight);

    return shadowVis * color;
#else
    return vec3(shadowVis);
#endif
}

vec3 shadow_pcf(
    vec3 shadow_screen_pos,
    vec3 shadow_clip_pos,
#ifdef shadowColor
    vec3 shadow_screen_pos_translucent,
    vec3 shadow_clip_pos_translucent,
#endif
    float penumbra_size,
    float dither
) {
    // penumbra_size > max_filter_radius: blur
    // penumbra_size < min_filter_radius: anti-alias (blur then sharpen)
    float distortion_factor = get_distortion_factor(shadow_clip_pos.xy);
    float min_filter_radius = 2.0 * shadow_map_pixel_size * distortion_factor;

    float filter_radius = max(penumbra_size, min_filter_radius);
    float filter_scale = sqr(filter_radius / min_filter_radius);

    int step_count
        = int(shadowPcfStepsMin + shadowPcfStepsScale * filter_scale);
    step_count = min(step_count, shadowPcfStepsMax);

    float shadowVis = 0.0;

    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    // perform first 4 iterations and filter shadow color
    for (int i = 0; i < 4; ++i) {
        vec2 offset
            = vogel_disc_sample(i, step_count, dither * tau) * filter_radius;

        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        shadowVis += texture(shadowtex1, vec3(uv, shadow_screen_pos.z));

#ifdef shadowColor
        // sample shadow color
        uv = shadow_clip_pos_translucent.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        ivec2 texel = ivec2(clamp(uv, vec2(0.0), vec2(1.0)) * shadow_map_res);

        float depth = texelFetch(shadowtex0, texel, 0).x;

        vec3 color = texelFetch(shadowcolor0, texel, 0).rgb;
        color = mix(
            vec3(1.0),
            4.0 * color,
            step(depth, shadow_screen_pos_translucent.z)
        );

        float weight = 1.0;

        color_sum += color * weight;
        weight_sum += weight;
#endif
    }

    vec3 color = weight_sum > 0.0 ? color_sum * rcp(weight_sum) : vec3(1.0);

    // exit early if outside shadow
    if (shadowVis > 4.0 - eps) {
        return color;
    } else if (shadowVis < eps) {
        return vec3(0.0);
    }

    // perform remaining iterations
    for (int i = 4; i < step_count; ++i) {
        vec2 offset
            = vogel_disc_sample(i, step_count, dither * tau) * filter_radius;

        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        shadowVis += texture(shadowtex1, vec3(uv, shadow_screen_pos.z));
    }

    float rcp_steps = rcp(float(step_count));

    // sharpening for small penumbra sizes
    float sharpening_threshold
        = 0.4 * max0((min_filter_radius - penumbra_size) / min_filter_radius);
    shadowVis = linear_step(
        sharpening_threshold,
        1.0 - sharpening_threshold,
        shadowVis * rcp_steps
    );

    return shadowVis * color;
}

vec3 get_filtered_shadows(
    vec3 scene_pos,
    vec3 flat_normal,
    float skylight,
    float cloud_shadows,
    float sss_amount,
    inout float distance_fade,
    inout float sss_depth
) {
    sss_depth = 0.0;

    float NoL = dot(flat_normal, light_dir);

    vec3 bias = get_shadow_bias(scene_pos, flat_normal, NoL, skylight);

    // Light leaking prevention from Complementary Reimagined, used with
    // permission
    vec3 edge_factor
        = 0.1 - 0.2 * fract(scene_pos + cameraPosition + flat_normal * 0.01);
    edge_factor -= edge_factor * skylight;

#ifdef pixelatedShadows
    // Snap position to the nearest block texel
    const float pixel_scale = float(pixelatedShadowsResolution);
    scene_pos = scene_pos + cameraPosition;
    scene_pos = floor(scene_pos * pixel_scale + 0.01) * rcp(pixel_scale)
        + (0.5 / pixel_scale);
    scene_pos = scene_pos - cameraPosition;
#endif

    vec3 shadow_view_pos
        = transform(shadowModelView, scene_pos + bias + edge_factor);
    vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);
    vec3 shadow_screen_pos = distort_shadow_space(shadow_clip_pos) * 0.5 + 0.5;

    distance_fade = get_shadow_distance_fade(scene_pos, shadow_screen_pos);

    if (distance_fade >= 1.0) {
        return vec3(1.0);
    }

    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);

#ifdef shadowVps
    // Test blockers from the same biased position as the receiver so the
    // reference depth matches the PCF comparison depth
    vec2 blocker_search_result = blocker_search(
        scene_pos + bias + edge_factor,
        dither,
        sss_amount > eps
    );

    sss_depth = blocker_search_result.y;

    if (NoL < 1e-3) {
        return vec3(0.0); // now we can exit early for sss blocks
    }
    if (blocker_search_result.x < eps) {
        return vec3(1.0); // blocker search empty handed => no occluders
    }

    float penumbra_size = 16.0 * shadowPenumbraScale
        * (shadow_screen_pos.z - blocker_search_result.x)
        / blocker_search_result.x;
    penumbra_size
        *= 5.0 - 4.0 * cloud_shadows; // Increase penumbra radius inside cloud
                                      // shadows, nice overcast look
    penumbra_size = min(penumbra_size, shadowBlockerSearchRadius);
    penumbra_size *= shadowProjection[0].x;
#else
    float penumbra_size
        = sqrt(0.5) * shadow_map_pixel_size * shadowPenumbraScale;

    // Increase blur radius to approximate subsurface scattering
    penumbra_size *= 1.0 + 7.0 * sss_amount;
#endif

#ifdef shadowColor


    vec3 shadow_view_pos_translucent
        = transform(shadowModelView, scene_pos + bias);
    vec3 shadow_clip_pos_translucent
        = project_ortho(shadowProjection, shadow_view_pos_translucent);
    vec3 shadow_screen_pos_translucent
        = distort_shadow_space(shadow_clip_pos_translucent) * 0.5 + 0.5;
#endif

#ifdef shadowPcf
    vec3 shadowVis = shadow_pcf(
        shadow_screen_pos,
        shadow_clip_pos,
#ifdef shadowColor
        shadow_screen_pos_translucent,
        shadow_clip_pos_translucent,
#endif
        penumbra_size,
        dither
    );
#else
    vec3 shadowVis = shadow_basic(shadow_screen_pos);
#endif

    return shadowVis;
}
#endif

#endif // INCLUDE_LIGHTING_DIRECT_LIGHTING_PCSS
