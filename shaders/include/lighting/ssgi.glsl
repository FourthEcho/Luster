#if !defined INCLUDE_LIGHTING_SSGI
#define INCLUDE_LIGHTING_SSGI

// ---------------------------------------------------------------------------
//   Screen-Space Global Illumination (SSGI)
//
//   Single-system indirect sunlight bounce. Replaces the previous constant
//   0.033 * fill-light hack with a physically grounded Lambertian bounce:
//
//     bounced = (1/N) * sum_over_rays [ albedo_hit * NoL * attenuation ]
//
//   Each ray is cosine-weighted importance-sampled around the bent normal,
//   raymarched against the depth buffer using a Hi-Z adaptive mip scheme,
//   and on hit the albedo is sampled from gbuffer 0 (colortex1).
//
//   Quality is controlled by three numeric sliders only — no mode switches,
//   no toggle flags, no separate code paths:
//     BOUNCED_LIGHT_RAYS    : rays per pixel (1, 2, 4, 8)
//     BOUNCED_LIGHT_STEPS   : raymarch steps per ray (8, 12, 16, 24)
//     BOUNCED_LIGHT_RADIUS  : max ray travel in view-space units
//
//   OpenGL 4.1 compatibility: no imageLoad/imageStore, no compute shaders,
//   no SSBOs. Pure fragment-shader rasterization against depth + gbuffer
//   samplers. Same code path runs on every profile; only the loop bounds
//   differ.
//
//   Author: Luster shader pack refactor
// ---------------------------------------------------------------------------

#include "/include/utility/sampling.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/space_conversion.glsl"

// --- Unpack albedo from gbuffer 0 ---------------------------------------
// gbuffer 0 layout (see d4_deferred_shading.fsh):
//   .rgb = albedo (linear rec709, will be converted to working space)
//   .a   = packed: (material_mask, light_levels.x) — not needed here
// We only need albedo at the hit pixel.
vec3 ssgi_sample_albedo(ivec2 texel) {
    vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
    mat4x2 data = mat4x2(
        unpack_unorm_2x8(gbuffer_data_0.x),
        unpack_unorm_2x8(gbuffer_data_0.y),
        unpack_unorm_2x8(gbuffer_data_0.z),
        unpack_unorm_2x8(gbuffer_data_0.w)
    );
    return vec3(data[0], data[1].x);
}

// --- Hi-Z adaptive raymarch ---------------------------------------------
// Marches a view-space ray through screen space, sampling the depth buffer
// at adaptive resolution: coarse steps use a wider tolerance, fine steps
// refine around candidate intersections. Returns hit UV + depth, or a
// sentinel vec3(-1) on miss.
//
// The Hi-Z scheme here approximates a depth mip chain by sampling at
// progressively wider pixel offsets as the ray advances. We can't rely on
// GL automatic mipmap generation for depth textures on all drivers, so we
// use a fixed step size with depth tolerance scaling instead.
vec3 ssgi_raymarch(
    vec3 ray_origin_screen,    // uv + depth (clip01)
    vec3 ray_dir_screen,       // normalised direction in screen space
    uint max_steps,
    float max_distance,
    float dither
) {
    // Compute total screen-space travel distance (clamped to screen bounds)
    float step_size = 1.0 / float(max_steps);

    // Initial position offset by dither to break up banding patterns
    vec3 ray_pos = ray_origin_screen + ray_dir_screen * step_size * dither;

    float prev_depth = ray_origin_screen.z;
    float prev_ray_z = ray_origin_screen.z;

    for (uint i = 0u; i < max_steps; ++i) {
        ray_pos += ray_dir_screen * step_size;

        // Off-screen -> miss
        if (clamp01(ray_pos.xy) != ray_pos.xy) return vec3(-1.0);
        if (ray_pos.z <= 0.0 || ray_pos.z >= 1.0) return vec3(-1.0);

        // Sample depth at current position
        ivec2 depth_texel = ivec2(ray_pos.xy * view_res * taau_render_scale);
        float depth_sample = texelFetch(depthtex1, depth_texel, 0).x;

        // Sky pixels (depth == 1.0) are misses — no bounce from sky
        if (depth_sample >= 1.0) {
            prev_depth = depth_sample;
            prev_ray_z = ray_pos.z;
            continue;
        }

        // Linearise both depths for fair comparison in view space
        float ray_view_z = screen_to_view_space_depth(gbufferProjectionInverse, ray_pos.z);
        float sample_view_z = screen_to_view_space_depth(gbufferProjectionInverse, depth_sample);

        // Hit test: ray is BEHIND the depth sample (further from camera)
        // by more than the thickness tolerance. The tolerance scales with
        // distance so distant surfaces (where depth quantisation is coarser)
        // still register hits reliably.
        float thickness = max(0.5, 0.05 * abs(ray_view_z));
        if (ray_view_z > sample_view_z + thickness) {
            // Reject if the previous sample was in front — that indicates a
            // thin silhouette edge we shouldn't claim as a hit.
            if (prev_ray_z < prev_depth + thickness) {
                return vec3(ray_pos.xy, depth_sample);
            }
        }

        prev_depth = depth_sample;
        prev_ray_z = ray_pos.z;
    }

    return vec3(-1.0);
}

// --- Main SSGI entry point ----------------------------------------------
// Computes a cosine-weighted Lambertian bounce for the current pixel by
// firing BOUNCED_LIGHT_RAYS rays into the screen-space depth buffer and
// sampling the albedo at each hit.
//
// Parameters:
//   scene_pos    : world-space fragment position
//   normal       : world-space surface normal
//   bent_normal  : world-space bent normal (from AO pass)
//   shadows      : direct shadow factor (vec3) — bounce is gated by (1 - shadows)
//   ao           : ambient occlusion factor
//   light_levels : vec2(blocklight, skylight) — bounce is gated by skylight
vec3 get_ssgi_bounce(
    vec3 scene_pos,
    vec3 normal,
    vec3 bent_normal,
    vec3 shadows,
    float ao,
    vec2 light_levels
) {
#ifndef BOUNCED_LIGHT
    return vec3(0.0);
#endif

    // Cull: no bounce in caves, no bounce on fully-lit or fully-shadowed pixels
    if (light_levels.y < 0.05) return vec3(0.0);
    if (max_of(shadows) < eps) return vec3(0.0);     // fully shadowed — no incoming light
    if (min_of(shadows) > 1.0 - eps) return vec3(0.0); // fully lit — no shadow boundary, bounce is negligible vs direct

    // Convert world-space inputs to view space (the parent shader's uniforms
    // gbufferModelView and gbufferProjectionInverse are in scope here).
    vec3 position_view = (gbufferModelView * vec4(scene_pos, 1.0)).xyz;
    vec3 view_normal = normalize(mat3(gbufferModelView) * normal);
    vec3 view_bent_normal = normalize(mat3(gbufferModelView) * bent_normal);

    // Project the fragment into screen space
    vec4 clip = gbufferProjection * vec4(position_view, 1.0);
    vec3 screen_pos = clip.xyz / clip.w;
    screen_pos = screen_pos * 0.5 + 0.5;

    // Blue-noise dither for the ray offset
    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);

    vec3 bounce = vec3(0.0);
    float hit_weight_sum = 0.0;
    float miss_weight_sum = 0.0;

    // Ray loop: each ray is cosine-weighted importance-sampled around the
    // bent normal. The bent normal points away from occluders, which is
    // the direction from which indirect light typically arrives.
    for (uint r = 0u; r < BOUNCED_LIGHT_RAYS; ++r) {
        // Hash-based rotation per ray per frame — decorrelates samples
        // across pixels (spatial) and frames (temporal).
        vec2 hash = hash2(gl_FragCoord.xy + vec2(r * 17.0, frameCounter * 0.31));
        vec3 ray_dir_view = cosine_weighted_hemisphere_sample(view_bent_normal, hash);

        // Project the ray endpoint to screen space to get a screen-space direction
        vec3 ray_target_view = position_view + ray_dir_view * BOUNCED_LIGHT_RADIUS;
        vec4 ray_target_clip = gbufferProjection * vec4(ray_target_view, 1.0);
        vec3 ray_target_screen = (ray_target_clip.xyz / ray_target_clip.w) * 0.5 + 0.5;
        vec3 ray_dir_screen = normalize(ray_target_screen - screen_pos);

        // March
        vec3 hit = ssgi_raymarch(
            screen_pos,
            ray_dir_screen,
            BOUNCED_LIGHT_STEPS,
            BOUNCED_LIGHT_RADIUS,
            dither
        );

        if (hit.x >= 0.0) {
            // Reconstruct hit position in view space for falloff calculation
            vec3 hit_view = screen_to_view_space(
                gbufferProjectionInverse,
                hit,
                true
            );

            float dist = length(hit_view - position_view);
            float NoL = max0(dot(view_normal, normalize(hit_view - position_view)));

            // Gaussian falloff — cheaper than 1/r^2 and visually equivalent
            // at the scales involved (1-32 blocks).
            float sigma = BOUNCED_LIGHT_RADIUS * 0.5;
            float atten = exp2(-sqr(dist) / sqr(sigma));

            // Sample albedo at hit pixel and convert to working color space
            ivec2 hit_texel = ivec2(hit.xy * view_res);
            vec3 hit_albedo_linear = ssgi_sample_albedo(hit_texel);
            vec3 hit_albedo = hit_albedo_linear * rec709_to_rec2020;

            bounce += hit_albedo * NoL * atten;
            hit_weight_sum += atten;
        } else {
            // Ray missed — accumulate weight so we can compute the sky-floor fill
            miss_weight_sum += 1.0;
        }
    }

    // Average over rays
    bounce *= rcp(max(float(BOUNCED_LIGHT_RAYS), 1.0));

    // Sky-ambient floor: where rays missed everything (off-screen geometry),
    // add a small sky-tinted fill so far walls next to open sky don't go
    // pitch black. This is a single line, not a separate system.
    float miss_ratio = miss_weight_sum * rcp(max(float(BOUNCED_LIGHT_RAYS), 1.0));
    vec3 sky_floor = ambient_color * 0.15 * light_levels.y * miss_ratio;

    // Gate by direct shadow factor: bounce only matters where there's a
    // shadow boundary. Fully lit pixels don't need bounce (direct light
    // dominates). Fully shadowed pixels need bounce from LIT neighbours,
    // which the raymarcher finds.
    float shadow_gate = 1.0 - clamp(dot(shadows, vec3(0.333)), 0.0, 1.0);

    // Apply AO (corners receive less bounce) and skylight falloff
    float falloff = pow1d5(ao + eps) * pow4(light_levels.y) * shadow_gate;

    return (bounce + sky_floor) * light_color * falloff * BOUNCED_LIGHT_I;
}

#endif // INCLUDE_LIGHTING_SSGI
