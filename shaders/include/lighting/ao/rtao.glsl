#if !defined INCLUDE_LIGHTING_AO_RTAO
#define INCLUDE_LIGHTING_AO_RTAO

#include "/include/misc/lod_mod_support.glsl"
#include "/include/misc/raytracer.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

// Ray-traced AO with bent normal.
// Uses the shared SSMR raymarcher (raytracer.glsl) that already handles
// combined_depth_tex / LOD and view-space tolerances. This gives true
// occlusion (off-screen occluders are caught via depth buffer marching)
// rather than GTAO's horizon-angle approximation.

vec3 sample_cosine_hemisphere(vec2 u) {
    float phi = tau * u.x;
    float cos_theta = sqrt(1.0 - u.y);
    float sin_theta = sqrt(u.y);
    return vec3(
        cos(phi) * sin_theta,
        sin(phi) * sin_theta,
        cos_theta
    );
}

vec2 compute_rtao(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_normal,
    vec2 dither,
    bool is_lod,
    out vec3 bent_normal
) {
    const int sample_count = RTAO_SAMPLES;
    const float radius = RTAO_RADIUS;
    const uint refinement_steps = 2u;

    mat3 tbn = get_tbn_matrix(view_normal);
    vec3 bent_accum = vec3(0.0);
    float occlusion = 0.0;
    float hit_weight_sum = 0.0;

    // Small normal offset to avoid self-intersection.
    vec3 offset_pos = view_pos + view_normal * 0.02;

    for (int i = 0; i < sample_count; ++i) {
        // Low-discrepancy 2D sample with per-pixel dither and frame jitter.
        vec2 u = fract(
            vec2(
                (float(i) + 0.5) / float(sample_count),
                float(i) * 0.7548776662
            )
            + dither
            + r2(frameCounter, vec2(0.13, 0.57))
        );

        vec3 sample_dir_tangent = sample_cosine_hemisphere(u);
        vec3 sample_dir_view = tbn * sample_dir_tangent;

        // Early-out: skip below-hemisphere due to numeric.
        if (dot(sample_dir_view, view_normal) < 0.0) {
            continue;
        }

        vec3 ray_dir = sample_dir_view * radius;
        vec3 hit_pos;

        // Use SSRT raymarcher; it already handles LOD vs combined depth,
        // screen bounds, and depth tolerance from DrDesten.
#if defined SSRT_LOD
        // Force non-LOD for RTAO when LOD active to keep AO stable.
        bool hit = raymarch_depth_buffer(
            screen_pos,
            offset_pos,
            ray_dir,
            u.x,
            uint(RTAO_SAMPLES),
            refinement_steps,
            hit_pos
        );
#else
        bool hit = raymarch_depth_buffer(
            screen_pos,
            offset_pos,
            ray_dir,
            u.x,
            uint(RTAO_SAMPLES),
            refinement_steps,
            hit_pos
        );
#endif

        if (hit) {
            // Distance-based falloff: closer hits occlude more.
            vec3 hit_view = screen_to_view_space(
                SSRT_PROJECTION_MATRIX_INVERSE,
                hit_pos,
                true
            );
            float dist = length(hit_view - view_pos);
            float falloff = exp(-dist * 0.5);
            occlusion += falloff;
            hit_weight_sum += 1.0;
        } else {
            bent_accum += sample_dir_view;
        }
    }

    float ao = 1.0 - clamp01(occlusion * rcp(float(sample_count)));

    // Bent normal is the average unoccluded direction, better than
    // GTAO's horizon-angle bent normal because it integrates actual
    // visibility. This is consumed by H-Basis skylight for directional
    // ambient (evaluate_h_basis_irradiance).
    if (length_squared(bent_accum) < eps) {
        bent_normal = view_normal;
    } else {
        bent_normal = normalize(bent_accum);
        // Pull slightly toward geometric normal to avoid extreme grazing.
        bent_normal = normalize(mix(bent_normal, view_normal, 0.15));
    }

    // Second channel is ambient SSS-like term for compatibility with
    // GTAO's second output; RTAO does not compute SSS, so return 0.
    return vec2(clamp01(ao), 0.0);
}

#endif // INCLUDE_LIGHTING_AO_RTAO
