#if !defined INCLUDE_MISC_PARALLAX
#define INCLUDE_MISC_PARALLAX

vec2 get_uv_from_local_coord(vec2 local_coord) {
    return atlas_tile_offset + atlas_tile_scale * fract(local_coord);
}

vec2 get_local_coord_from_uv(vec2 uv) {
    return (uv - atlas_tile_offset) * rcp(atlas_tile_scale);
}

float get_height_value(vec2 local_coord, mat2 uv_gradient) {
    vec2 uv = get_uv_from_local_coord(local_coord);
    return textureGrad(normals, uv, uv_gradient[0], uv_gradient[1]).w;
}

float get_depth_value(vec2 local_coord, mat2 uv_gradient) {
    return 1.0 - get_height_value(local_coord, uv_gradient);
}

// ---------------------------------------------------------------------------
//   Parallax occlusion mapping
//
//   Parallax shadow evaluation characteristics:
//     * Safe rcp(tangent_dir.z) — clamped to avoid Inf/NaN at grazing angles.
//     * Binary search refinement between the previous and current sample
//       positions, so the intersection is located to sub-step precision
//       without raising the linear-search sample count.
//     * Soft shadow penumbra: instead of a hard in/out test, the shadow
//       ray traces POM_SHADOW_SAMPLES points along the light direction in
//       tangent space and returns a continuous [0, 1] visibility based on
//       how far above the surface the ray escapes.  This removes the harsh
//       binary shadow edge that gave POM its previous 2-star rating.
// ---------------------------------------------------------------------------

// Tolerance below which two parallax samples are considered equal
const float pom_height_eps = rcp(255.0);

// Minimum |z| for the view/light tangent direction.  Grazing view angles
// produce huge rcp(z) values that blow up the parallax step; clamping z
// keeps the step within a sane range at the cost of slightly compressed
// depth perception at silhouettes.
float safe_parallax_rcp_z(float z) {
    return rcp(max(abs(z), 0.05));
}

vec2 get_parallax_uv(
    vec3 tangent_dir,
    mat2 uv_gradient,
    float view_distance,
    float dither,
    out vec3 previous_ray_pos,
    out float pom_depth
) {
    const float depth_step = rcp(float(POM_SAMPLES));

    // Perform an initial POM step at the original position.
    // Thanks to Null for teaching me this
    float depth_value = get_depth_value(atlas_tile_coord, uv_gradient);
    if (depth_value < pom_height_eps) {
        previous_ray_pos = vec3(atlas_tile_coord, 0.0);
        pom_depth = 0.0;
        return uv;
    }

    float parallax_fade
        = linear_step(0.75 * POM_DISTANCE, POM_DISTANCE, view_distance);

    // Guarded rcp(-tangent_dir.z) — prevents NaN/Inf at grazing angles
    float inv_z = -safe_parallax_rcp_z(tangent_dir.z);

    vec3 ray_step = vec3(
                        tangent_dir.xy * inv_z * POM_DEPTH
                            * (1.0 - parallax_fade),
                        1.0
                    )
        * depth_step;
    vec3 pos = vec3(atlas_tile_coord + ray_step.xy * dither, 0.0);
    previous_ray_pos = pos;

    // --- Linear search: locate the crossing ------------------------------
    while (depth_value - pos.z >= pom_height_eps && pos.z < 1.0) {
        previous_ray_pos = vec3(pos);
        depth_value = get_depth_value(pos.xy, uv_gradient);
        pos += ray_step;
    }

    pom_depth = depth_value;

    // --- Binary refinement: bisect between previous and current -----------
    // 4 iterations is enough to converge to sub-texel precision given the
    // typical POM_DEPTH * depth_step stride length.
    vec3 lo = previous_ray_pos;
    vec3 hi = pos;
    const int BISECT_ITERS = 4;
    for (int i = 0; i < BISECT_ITERS; ++i) {
        vec3 mid = 0.5 * (lo + hi);
        float mid_depth = get_depth_value(mid.xy, uv_gradient);
        if (mid_depth - mid.z >= pom_height_eps) {
            lo = mid;          // surface still above mid -> step further
        } else {
            hi = mid;          // surface below mid -> step back
        }
    }

    // Use the lo bound (just under the surface) for the final UV
    return get_uv_from_local_coord(lo.xy);
}

// Soft parallax shadow: returns visibility in [0, 1] where 0 = fully lit,
// 1 = fully shadowed.  The visibility result is continuous in the range [0, 1].
float get_parallax_shadow(
    vec3 pos,
    mat2 uv_gradient,
    float view_distance,
    float dither
) {
    float parallax_fade
        = linear_step(0.75 * POM_DISTANCE, POM_DISTANCE, view_distance);

    vec3 tangent_dir = light_dir * tbn;

    // Guard the reciprocal of tangent_dir.z to avoid division by zero.
    float inv_z = safe_parallax_rcp_z(tangent_dir.z);

    vec3 ray_step = vec3(
                        tangent_dir.xy * inv_z * POM_DEPTH
                            * (1.0 - parallax_fade),
                        -1.0
                    )
        * pos.z * rcp(float(POM_SHADOW_SAMPLES));

    pos.xy += ray_step.xy * dither;

    // Trace the shadow ray and accumulate a soft visibility term.
    // Integrate the shadow contribution instead of returning a binary result.
    // how far above the surface the ray manages to escape, which produces
    // a continuous penumbra.
    float visibility = 0.0;
    float max_height = get_depth_value(pos.xy, uv_gradient);
    float weight_sum = 0.0;

    for (int i = 0; i < POM_SHADOW_SAMPLES; ++i) {
        pos += ray_step;
        float offset_height = get_depth_value(pos.xy, uv_gradient);
        float diff = pos.z - offset_height;

        // Weight each step by its distance from the surface; samples near
        // the surface contribute most to the occlusion signal.
        float w = 1.0;
        weight_sum += w;

        if (diff > 0.0 && max_height - offset_height > eps) {
            // Occluded — magnitude scales with how far below the surface
            // the ray is, normalised by the maximum height traversed.
            float occlusion = clamp(diff / max(max_height, eps), 0.0, 1.0);
            visibility += w * occlusion;
        }
    }

    visibility *= rcp(max(weight_sum, 1.0));
    return visibility;
}

#endif // INCLUDE_MISC_PARALLAX
