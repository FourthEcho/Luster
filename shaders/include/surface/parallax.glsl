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

// POM slope normals: central differences of the heightfield around the ray
// hit, converted to a tangent-space perturbation. The caller gates this
// helper with POM_SLOPE_NORMALS so the POM screen can control it independently
// from the parallax UV offset.
float get_pom_distance_fade(float view_distance) {
    return linear_step(0.75 * POM_DISTANCE, POM_DISTANCE, view_distance);
}

float get_pom_relief_scale(float view_distance) {
    return 1.0 - get_pom_distance_fade(view_distance);
}

// World-space relief of the raymarched hit, in the same units as POM_DEPTH
// (one atlas tile ~= one block metre). Faded to zero at POM_DISTANCE so the
// UV offset, slope normals and depth write all agree and nothing pops when
// the close-range march hands off to the flat quad.
float get_pom_world_relief(float pom_depth, float view_distance) {
    return pom_depth * POM_DEPTH * get_pom_relief_scale(view_distance);
}

vec3 get_pom_slope_normal(vec2 local_coord, mat2 uv_gradient) {
    // Reconstruct the height-field normal from central differences at the
    // ray hit. Work in tile-relative coordinates so atlas neighbors cannot
    // leak into the derivative.
    vec2 texel = rcp(atlas_tile_scale * vec2(textureSize(normals, 0)));

    // Match the finite-difference footprint to the filtered height samples.
    // This keeps close surfaces detailed while preventing one-texel normals
    // from shimmering after the height map reaches a coarser mip level.
    vec2 uv_footprint = vec2(
        max(abs(uv_gradient[0].x), abs(uv_gradient[1].x)),
        max(abs(uv_gradient[0].y), abs(uv_gradient[1].y))
    );
    vec2 sample_step = max(texel, uv_footprint * rcp(atlas_tile_scale));
    sample_step = min(sample_step, vec2(0.25));

    float depth_dx
        = (get_depth_value(local_coord + vec2(sample_step.x, 0.0), uv_gradient)
         - get_depth_value(local_coord - vec2(sample_step.x, 0.0), uv_gradient))
        * rcp(2.0 * sample_step.x);
    float depth_dy
        = (get_depth_value(local_coord + vec2(0.0, sample_step.y), uv_gradient)
         - get_depth_value(local_coord - vec2(0.0, sample_step.y), uv_gradient))
        * rcp(2.0 * sample_step.y);

    // The POM height field is displaced by POM_DEPTH in tangent space.
    // Since depth = 1 - height, these derivatives already have the
    // correct sign for the tangent-space normal perturbation.
    return vec3(POM_DEPTH * depth_dx, POM_DEPTH * depth_dy, 0.0);
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

    // Perform one POM step at the original position, fixes POM tiling
    // Thanks to Null for teaching me this
    float depth_value = get_depth_value(atlas_tile_coord, uv_gradient);
    if (depth_value < rcp(255.0)) {
        previous_ray_pos = vec3(atlas_tile_coord, 0.0);
        pom_depth = 0.0;
        return uv;
    }

    float relief_scale = get_pom_relief_scale(view_distance);

    vec3 ray_step = vec3(
                        tangent_dir.xy * rcp(-tangent_dir.z) * POM_DEPTH
                            * relief_scale,
                        1.0
                    )
        * depth_step;
    vec3 curr_pos = vec3(atlas_tile_coord + ray_step.xy * dither, 0.0);
    vec3 prev_pos = curr_pos;

    // Signed distance of the ray above the height field: > 0 while the ray
    // is still above the surface, <= 0 once it has gone under it.
    float curr_diff = get_depth_value(curr_pos.xy, uv_gradient) - curr_pos.z;
    float prev_diff = curr_diff;

    for (int i = 0; i < POM_SAMPLES && curr_diff > 0.0; ++i) {
        prev_pos = curr_pos;
        prev_diff = curr_diff;
        curr_pos += ray_step;
        curr_diff = get_depth_value(curr_pos.xy, uv_gradient) - curr_pos.z;
    }

    // Linearly interpolate to the ray/height-field crossing between the last
    // two steps instead of snapping to the step below the surface. Removes
    // the stair-stepping in UVs, slope normals and the depth write.
    float hit_t = clamp01(prev_diff * rcp(max(prev_diff - curr_diff, 1e-5)));
    vec3 hit_pos = mix(prev_pos, curr_pos, hit_t);

    previous_ray_pos = prev_pos;
    pom_depth = clamp01(hit_pos.z);

    return get_uv_from_local_coord(hit_pos.xy);
}

bool get_parallax_shadow(
    vec3 pos,
    mat2 uv_gradient,
    float view_distance,
    float dither
) {
    float relief_scale = get_pom_relief_scale(view_distance);

    vec3 tangent_dir = light_dir * tbn;
    vec3 ray_step = vec3(
                        tangent_dir.xy * rcp(tangent_dir.z) * POM_DEPTH
                            * relief_scale,
                        -1.0
                    )
        * pos.z * rcp(float(POM_SHADOW_SAMPLES));

    pos.xy += ray_step.xy * dither;

    float max_height = get_depth_value(pos.xy, uv_gradient);
    for (int i = 0; i < POM_SHADOW_SAMPLES; ++i) {
        pos += ray_step;
        float offset_height = get_depth_value(pos.xy, uv_gradient);
        float diff = pos.z - offset_height;
        if (diff > 0.0 && max_height - offset_height > eps) {
            return true;
        }
    }

    return false;
}

#endif // INCLUDE_MISC_PARALLAX
