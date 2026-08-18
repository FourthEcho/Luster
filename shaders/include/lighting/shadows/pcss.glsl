#if !defined INCLUDE_LIGHTING_SHADOWS
#define INCLUDE_LIGHTING_SHADOWS

#if defined SHADOW && (defined WORLD_OVERWORLD || defined WORLD_END)

#include "/include/lighting/shadows/common.glsl"
#include "/include/lighting/shadows/distortion.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/rotation.glsl"
#include "/include/utility/sampling.glsl"

// Hardware PCF uses the core sampler2DShadow comparison path; no vendor-specific extension is required.

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
    int step_count = has_sss ? SSS_STEPS : 3;

    vec3 shadow_view_pos = transform(shadowModelView, scene_pos);
    vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);
    float ref_z = shadow_clip_pos.z * (SHADOW_DEPTH_SCALE * 0.5) + 0.5;

    float radius = SHADOW_BLOCKER_SEARCH_RADIUS * shadowProjection[0].x
        * (0.5 + 0.5 * linear_step(0.2, 0.4, light_dir.y));

    float depth_sum = 0.0;
    float weight_sum = 0.0;
    float depth_sum_sss = 0.0;

    for (int i = 0; i < step_count; ++i) {
        vec2 offset = vogel_disc_sample(i, step_count, dither * tau) * radius;
        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        float depth = texelFetch(shadowtex0, ivec2(uv * shadow_map_res), 0).x;
        float weight = step(depth, ref_z);

        depth_sum += weight * depth;
        weight_sum += weight;
        depth_sum_sss += max0(ref_z - depth);
    }

    float blocker_depth = weight_sum == 0.0 ? 0.0 : depth_sum / weight_sum;
    float sss_depth = -shadowProjectionInverse[2].z * depth_sum_sss
        * rcp(SHADOW_DEPTH_SCALE * float(step_count));

    return vec2(blocker_depth, sss_depth);
}

vec3 shadow_unfiltered(vec3 shadow_screen_pos) {
    ivec2 texel = ivec2(clamp(
        shadow_screen_pos.xy * shadow_map_res,
        vec2(0.0),
        vec2(float(shadow_map_res - 1))
    ));
    float depth = texelFetch(shadowtex0, texel, 0).x;
    float shadow = step(shadow_screen_pos.z, depth);

#ifdef SHADOW_COLOR
    vec3 color = texelFetch(shadowcolor0, texel, 0).rgb * 4.0;
    vec3 averageColor = vec3(0.0);
    for (int i = 0; i < 9; ++i) {
        averageColor += texelFetch(
            shadowcolor0,
            clamp(texel + blur_kernel_offsets_3x3[i], ivec2(0), ivec2(shadow_map_res - 1)),
            0
        ).rgb;
    }
    shadow *= step(eps, max_of(averageColor));
    color = color * shadow + (1.0 - shadow);
    return color;
#else
    return vec3(shadow);
#endif
}



vec3 shadow_pcf(
    vec3 shadow_screen_pos,
    vec3 shadow_clip_pos,
#ifdef SHADOW_COLOR
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
        = int(LUSTER_PCF_STEPS_MIN + SHADOW_PCF_STEPS_SCALE
            * SHADOW_PCF_SAMPLE_SCALE * filter_scale);
    step_count = min(step_count, LUSTER_PCF_STEPS_MAX);

    float shadow = 0.0;

    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    // perform first 4 iterations and filter shadow color
    for (int i = 0; i < 4; ++i) {
        vec2 offset
            = vogel_disc_sample(i, step_count, dither * tau) * filter_radius;

        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        ivec2 texel = ivec2(clamp(
            uv * shadow_map_res,
            vec2(0.0),
            vec2(float(shadow_map_res - 1))
        ));
        float depth = texelFetch(shadowtex0, texel, 0).x;
        shadow += step(shadow_screen_pos.z, depth);

#ifdef SHADOW_COLOR
        // sample shadow color
        uv = shadow_clip_pos_translucent.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        ivec2 texel = ivec2(uv * shadow_map_res);

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
    if (shadow > 4.0 - eps) {
        return color;
    } else if (shadow < eps) {
        return vec3(0.0);
    }

    // perform remaining iterations
    for (int i = 4; i < step_count; ++i) {
        vec2 offset
            = vogel_disc_sample(i, step_count, dither * tau) * filter_radius;

        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;

        ivec2 texel = ivec2(clamp(
            uv * shadow_map_res,
            vec2(0.0),
            vec2(float(shadow_map_res - 1))
        ));
        float depth = texelFetch(shadowtex0, texel, 0).x;
        shadow += step(shadow_screen_pos.z, depth);
    }

    float rcp_steps = rcp(float(step_count));

    // sharpening for small penumbra sizes
    float sharpening_threshold
        = 0.4 * max0((min_filter_radius - penumbra_size) / min_filter_radius);
    shadow = linear_step(
        sharpening_threshold,
        1.0 - sharpening_threshold,
        shadow * rcp_steps
    );

    return shadow * color;
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

#ifdef PIXELATED_SHADOWS
    // Snap position to the nearest block texel
    const float pixel_scale = float(PIXELATED_SHADOWS_RESOLUTION);
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

#if defined SHADOW_PCF && defined SHADOW_VPS
    vec2 blocker_search_result
        = blocker_search(scene_pos, dither, sss_amount > eps);

    sss_depth = blocker_search_result.y;

    if (NoL < 1e-3) {
        return vec3(0.0); // Exit early for subsurface-scattering blocks when the material path does not require shadow evaluation.
    }
    if (blocker_search_result.x < eps) {
        return vec3(1.0); // blocker search empty handed => no occluders
    }

    float penumbra_size = 16.0 * SHADOW_PENUMBRA_SCALE
        * (shadow_screen_pos.z - blocker_search_result.x)
        / blocker_search_result.x;
    penumbra_size
        *= 5.0 - 4.0 * cloud_shadows; // Increase penumbra radius inside cloud
                                      // shadows, nice overcast look
    penumbra_size = min(penumbra_size, SHADOW_BLOCKER_SEARCH_RADIUS);
    penumbra_size *= shadowProjection[0].x;
#else
    float penumbra_size
        = sqrt(0.5) * shadow_map_pixel_size * SHADOW_PENUMBRA_SCALE;

    // Increase blur radius to approximate subsurface scattering.
    penumbra_size *= 1.0 + 7.0 * sss_amount;
#endif

#ifdef SHADOW_COLOR
    // Reconstruct the shadow position before translucent light-leak suppression so colored shadow transmittance remains stable.
    // Translucent shadow light-leak suppression is omitted because it introduces visible artifacts on colored transmitters.
    // water caustics
    vec3 shadow_view_pos_translucent
        = transform(shadowModelView, scene_pos + bias);
    vec3 shadow_clip_pos_translucent
        = project_ortho(shadowProjection, shadow_view_pos_translucent);
    vec3 shadow_screen_pos_translucent
        = distort_shadow_space(shadow_clip_pos_translucent) * 0.5 + 0.5;
#endif

#ifdef SHADOW_PCF
    vec3 shadow = shadow_pcf(
        shadow_screen_pos,
        shadow_clip_pos,
#ifdef SHADOW_COLOR
        shadow_screen_pos_translucent,
        shadow_clip_pos_translucent,
#endif
        penumbra_size,
        dither
    );
#else
    vec3 shadow = shadow_unfiltered(shadow_screen_pos);
#endif

    return shadow;
}
#endif

#endif // INCLUDE_LIGHTING_SHADOWS
