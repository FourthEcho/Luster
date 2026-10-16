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

#include "/lib/global.glsl"

layout(
    location = 0
) out vec4 ambient; // ao, ambient sss, octahedrally encoded bent normal
layout(location = 1) out vec2 ambient_history_data; // depth, pixel age

/* RENDERTARGETS: 6,14 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex6; // ambient lighting data
uniform sampler2D colortex14; // ambient lighting history data

uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
// Spherical linear interpolation of two unit vectors
vec3 slerp(vec3 v0, vec3 v1, float t) {
    float cos_theta = clamp(dot(v0, v1), -1.0, 1.0);
    if (cos_theta > 0.999) {
        return v0;
    }

    float theta = fast_acos(cos_theta);
    float rcp_sin_theta = rcp(max(sin(theta), 1e-4));

    float w0 = rcp_sin_theta * sin((1.0 - t) * theta);
    float w1 = rcp_sin_theta * sin(t * theta);

    return v0 * w0 + v1 * w1;
}
#include "/lib/util/spaceConversion.glsl"

#if shaderAo == shaderAoSsao
#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSAO
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSAO

#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

// DSSAO paired-depth sampling adapted from the BSL-derived method credited
// by Kappa v5.3 to Capt Tatsu (used with permission).
vec2 get_dssao_sample_offset(float radius_step) {
    float angle = fract(radius_step * 8.0) * pi;
    return vec2(cos(angle), sin(angle)) * radius_step;
}

float compute_dssao(
    vec3 position_screen,
    vec3 scene_normal,
    vec2 dither
) {
    const float max_occlusion_distance = tau;
    const float anti_bleed_exponent = 0.71;

    float current_depth = screen_to_view_space_depth(
        combined_projection_matrix_inverse,
        position_screen.z
    );

    float orientation_scale = 0.75
        + abs(1.0 - clamp(dot(normalize(scene_normal), vec3(0.0, 1.0, 0.0)), -1.0, 1.0)) * 0.5;
    float radius = max(ssaoRadius, 0.25) * orientation_scale;

    float fov_scale = abs(combined_projection_matrix[1][1]) / 1.37;
    float aspect_inverse = view_res.y / max(view_res.x, 1.0);
    vec2 screen_scale = radius * vec2(aspect_inverse, 1.0)
        * fov_scale / max(current_depth, 5.0);

    int sample_count = max(ssaoSteps, 1);
    float sample_step = 1.2 / float(sample_count);
    float radius_step = sample_step * (1.0 + dither.x);
    float depth_scale = 0.7 / max(radius, 1e-3);
    vec2 texel_half = 0.5 / vec2(textureSize(combined_depth_tex, 0));
    vec2 uv_min = texel_half;
    vec2 uv_max = vec2(1.0) - texel_half;

    float visibility = 0.0;

    for (int i = 0; i < sample_count; ++i) {
        vec2 offset = get_dssao_sample_offset(radius_step) * screen_scale;
        vec2 sample_uv_a = clamp(position_screen.xy + offset, uv_min, uv_max);
        vec2 sample_uv_b = clamp(position_screen.xy - offset, uv_min, uv_max);

        float sample_depth_a = texture(combined_depth_tex, sample_uv_a).x;
        float sample_depth_b = texture(combined_depth_tex, sample_uv_b).x;
        float linear_depth_a = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            sample_depth_a
        );
        float linear_depth_b = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            sample_depth_b
        );

        float sample_delta_a = (current_depth - linear_depth_a) * depth_scale;
        float sample_delta_b = (current_depth - linear_depth_b) * depth_scale;

        float anti_bleed_a = 1.0 - rcp(
            1.0 + max0(abs(linear_depth_a - current_depth) - max_occlusion_distance)
                * anti_bleed_exponent
        );
        float anti_bleed_b = 1.0 - rcp(
            1.0 + max0(abs(linear_depth_b - current_depth) - max_occlusion_distance)
                * anti_bleed_exponent
        );

        float angle = mix(clamp01(0.5 - sample_delta_a), 0.5, anti_bleed_a);
        float distance_term = mix(clamp01(0.25 * sample_delta_a - 1.0), 0.5, anti_bleed_a);
        angle += mix(clamp01(0.5 - sample_delta_b), 0.5, anti_bleed_b);
        distance_term += mix(clamp01(0.25 * sample_delta_b - 1.0), 0.5, anti_bleed_b);

        visibility += clamp01(angle + distance_term);
        radius_step += sample_step;
    }

    return clamp01(visibility / float(sample_count));
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSAO
#endif

#if shaderAo == shaderAoGtao
#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_GTAO
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_GTAO

#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

float integrate_arc(vec2 h, float n, float cos_n) {
    vec2 tmp = cos_n + 2.0 * h * sin(n) - cos(2.0 * h - n);
    return 0.25 * (tmp.x + tmp.y);
}

float compute_maximum_horizon_angle(
    vec3 view_slice_dir,
    vec3 viewer_dir,
    vec3 screen_pos,
    vec3 view_pos,
    float radius,
    float dither,
    bool is_lod
) {
    float step_size = (gtaoRadius * rcp(float(gtaoHorizonSteps))) * radius;

    float max_cos_theta = -1.0;

    vec2 ray_step
        = (view_to_screen_space(
               view_pos + view_slice_dir * step_size,
               true,
               is_lod
           )
           - screen_pos)
              .xy;
    vec2 ray_pos = screen_pos.xy
        + ray_step * (dither + max_of(view_pixel_size) * rcp_length(ray_step));

    for (int i = 0; i < gtaoHorizonSteps; ++i, ray_pos += ray_step) {
        ivec2 texel
            = ivec2(clamp01(ray_pos) * view_res * taau_render_scale + 0.5);
        float depth = texelFetch(combined_depth_tex, texel, 0).x;

        if (depth == 1.0 || depth < hand_depth || depth == screen_pos.z) {
            continue;
        }

        vec3 offset = screen_to_view_space(
                          combined_projection_matrix_inverse,
                          vec3(ray_pos, depth),
                          true
                      )
            - view_pos;

        float len_sq = length_squared(offset);

        // Self-sample: zero offset would make inversesqrt diverge
        if (len_sq < eps) {
            continue;
        }

        float norm = inversesqrt(len_sq);

        float distance_falloff = linear_step(
            gtaoFalloffStart * gtaoRadius,
            gtaoRadius,
            len_sq * norm * rcp(radius)
        );

        float cos_theta = dot(viewer_dir, offset) * norm;
        cos_theta = mix(cos_theta, -1.0, distance_falloff);

        max_cos_theta = max(cos_theta, max_cos_theta);
    }

    return fast_acos(clamp(max_cos_theta, -1.0, 1.0));
}

vec2 compute_gtao(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_normal,
    vec2 dither,
    bool is_lod,
    float surface_albedo,
    out vec3 bent_normal
) {
    float ao = 0.0;
    float ambient_sss = 0.0;
    bent_normal = vec3(0.0);

    // Construct local working space. Looking straight up/down makes the
    // up-cross degenerate, so fall back to +X like get_tbn_matrix does.
    vec3 viewer_dir = normalize(-view_pos);
    vec3 viewer_right = abs(viewer_dir.y) > 1.0 - 1e-4
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), viewer_dir));
    vec3 viewer_up = cross(viewer_dir, viewer_right);
    mat3 local_to_view = mat3(viewer_right, viewer_up, viewer_dir);

    // Reduce AO radius very close up, makes some screen-space artifacts less
    // obvious
    float ao_radius = max(
        0.25 + 0.75 * smoothstep(0.0, 81.0, length_squared(view_pos)),
        0.5
    );

    // Increase AO radius for LoD terrain (looks nice)
#ifdef LOD_MOD_ACTIVE
    if (is_lod) {
        ao_radius *= 3.0;
    }
#endif

    for (int i = 0; i < gtaoSlices; ++i) {
        float slice_angle = (i + dither.x) * (pi / float(gtaoSlices));

        vec3 slice_dir = vec3(cos(slice_angle), sin(slice_angle), 0.0);
        vec3 view_slice_dir = local_to_view * slice_dir;

        vec3 ortho_dir = slice_dir - dot(slice_dir, viewer_dir) * viewer_dir;
        vec3 axis = cross(slice_dir, viewer_dir);
        vec3 projected_normal = view_normal - axis * dot(view_normal, axis);

        float len_sq = dot(projected_normal, projected_normal);
        float norm = inversesqrt(len_sq);

        float sgn_gamma = sign(dot(ortho_dir, projected_normal));
        float cos_gamma = clamp01(dot(projected_normal, viewer_dir) * norm);
        float gamma = sgn_gamma * fast_acos(cos_gamma);

        vec2 max_horizon_angles;
        max_horizon_angles.x = compute_maximum_horizon_angle(
            -view_slice_dir,
            viewer_dir,
            screen_pos,
            view_pos,
            ao_radius,
            dither.y,
            is_lod
        );
        max_horizon_angles.y = compute_maximum_horizon_angle(
            view_slice_dir,
            viewer_dir,
            screen_pos,
            view_pos,
            ao_radius,
            dither.y,
            is_lod
        );

        ambient_sss += max0(max_horizon_angles.y - half_pi) * rcp_pi;

        max_horizon_angles = gamma
            + clamp(vec2(-1.0, 1.0) * max_horizon_angles - gamma,
                    -half_pi,
                    half_pi);
        ao += integrate_arc(max_horizon_angles, gamma, cos_gamma) * len_sq
            * norm;

        float bent_angle = dot(max_horizon_angles, vec2(0.5));
        bent_normal
            += viewer_dir * cos(bent_angle) + ortho_dir * sin(bent_angle);
    }


    // approximation (Jimenez et al., "Practical Realtime Strategies for


    float albedo = mix(
        0.0,
        clamp(surface_albedo, 0.02, 0.9),
        gtaoMultibounceIntensity
    );

    ao *= rcp(float(gtaoSlices));
    ambient_sss *= rcp(float(gtaoSlices));
    ao /= albedo * ao + (1.0 - albedo);

    bent_normal = normalize(normalize(bent_normal) - 0.5 * viewer_dir);

    return clamp01(vec2(ao, ambient_sss));
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_GTAO
#endif

const float ao_render_scale = 0.5;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 view_texel
        = ivec2(gl_FragCoord.xy * (taau_render_scale / ao_render_scale));

    if (clamp(view_texel, ivec2(0), ivec2(view_res)) != view_texel) {
        return;
    }

    float depth = texelFetch(combined_depth_tex, view_texel, 0).x;

#ifndef normalMapping
    vec4 gbuffer_data = texelFetch(colortex1, view_texel, 0);
    vec4 gbuffer_data_0 = gbuffer_data;
#else
    vec4 gbuffer_data = texelFetch(colortex2, view_texel, 0);
    vec4 gbuffer_data_0 = texelFetch(colortex1, view_texel, 0);
#endif
    vec2 dither = vec2(
        texelFetch(noisetex, texel & 511, 0).b,
        texelFetch(noisetex, (texel + 249) & 511, 0).b
    );

    // Distant Horizons support

#ifdef LOD_MOD_ACTIVE
    float depth_mc = texelFetch(depthtex1, view_texel, 0).x;
    float depth_lod = texelFetch(lod_depth_tex_shading, view_texel, 0).x;
    bool is_lod = is_lod_terrain(depth_mc, depth_lod);
#else
#define depth_mc depth
    const bool is_lod = false;
#endif

    bool is_hand;
    fix_hand_depth(depth_mc, is_hand);

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    vec3 previous_screen_pos
        = reproject_scene_space(scene_pos, is_hand, false);

    if (depth == 1.0) {
        ambient = vec4(1.0, 0.0, 0.0, 0.0);
        ambient_history_data = vec2(0.0);
        return;
    }

#ifdef normalMapping
    vec3 world_normal = decode_unit_vector(gbuffer_data.xy);

#ifdef LOD_MOD_ACTIVE
    if (is_lod) {
        vec4 gbuffer_data_0 = texelFetch(colortex1, view_texel, 0);
        world_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data_0.z));
    }
#endif
#else
    vec3 world_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data.z));
#endif

    vec3 view_normal = mat3(gbufferModelView) * world_normal;

    dither = r2(frameCounter, dither);


    // approximation used by the merged GTAO implementation — cheap luminance

    vec3 surface_albedo_srgb = vec3(
        unpack_unorm_2x8(gbuffer_data_0.x),
        unpack_unorm_2x8(gbuffer_data_0.y).x
    );
    float surface_albedo
        = dot(srgb_eotf_inv(surface_albedo_srgb), luminance_weights_rec709);

    // Calculate AO

    vec2 ao;
    vec3 bent_normal;

#if shaderAo == shaderAoNone
    ao = vec2(1.0, 0.0);
    bent_normal = view_normal;
#elif shaderAo == shaderAoSsao
    ao.x = compute_dssao(screen_pos, world_normal, dither);
    ao.y = 0.0;
    bent_normal = view_normal;
#elif shaderAo == shaderAoGtao
    ao = compute_gtao(
        screen_pos,
        view_pos,
        view_normal,
        dither,
        is_lod,
        surface_albedo,
        bent_normal
    );
#endif

    // Temporal accumulation

    const float max_accumulated_frames = 10.0;
    const float depth_rejection_strength = 16.0;
    const float offcenter_rejection_strength = 0.25;

    vec4 history = max0(
        catmull_rom_filter_fast(colortex6, previous_screen_pos.xy, 0.65)
    );
    vec2 history_data = max0(texture(colortex14, previous_screen_pos.xy).xy);

    if (clamp01(previous_screen_pos.xy) == previous_screen_pos.xy) {
        // Unpack history data
        float history_depth = 1.0 - history_data.x;
        float pixel_age = min(history_data.y, max_accumulated_frames);

        vec3 history_bent_normal;
        history_bent_normal.xy = history.zw * 2.0 - 1.0;
        history_bent_normal.z = sqrt(
            clamp01(1.0 - dot(history_bent_normal.xy, history_bent_normal.xy))
        );

        // Reproject bent normal
        history_bent_normal
            = history_bent_normal * mat3(gbufferPreviousModelView);
        history_bent_normal = mat3(gbufferModelView) * history_bent_normal;

        // Depth rejection
        float view_norm = rcp_length(view_pos);
        float NoV = abs(dot(view_normal, view_pos))
            * view_norm; // NoV / sqrt(length(view_pos))
        float z0 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            depth
        );
        float z1 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            history_depth
        );
        float depth_weight
            = exp2(-abs(z0 - z1) * depth_rejection_strength * NoV * view_norm);

        // Offcenter rejection from Jessie, which is originally by Zombye
        // Reduces blur in motion
        vec2 pixel_offset = 1.0
            - abs(2.0
                      * fract(
                          view_res * ao_render_scale * previous_screen_pos.xy
                      )
                  - 1.0);
        float offcenter_rejection = sqrt(pixel_offset.x * pixel_offset.y)
                * offcenter_rejection_strength
            + (1.0 - offcenter_rejection_strength);

        pixel_age
            *= depth_weight * offcenter_rejection * float(history_depth != 1.0);

        // Blend with history
        float history_weight = pixel_age / (pixel_age + 1.0);

        ao = mix(ao, history.xy, history_weight);
        bent_normal = slerp(bent_normal, history_bent_normal, history_weight);

        ambient = vec4(ao, bent_normal.xy * 0.5 + 0.5);
        ambient_history_data = vec2(1.0 - depth, pixel_age + 1.0);
    } else {
        ambient = vec4(ao, bent_normal.xy * 0.5 + 0.5);
        ambient_history_data = vec2(0.0);
    }

    if (is_hand) {
        ambient_history_data.x = 1.0;
    }
}
