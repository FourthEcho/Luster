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

#if !defined INCLUDE_MATERIAL_PARALLAX
#define INCLUDE_MATERIAL_PARALLAX

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


float get_pom_distance_fade(float view_distance) {
    return linear_step(0.75 * pomDistance, pomDistance, view_distance);
}

float get_pom_relief_scale(float view_distance) {
    return 1.0 - get_pom_distance_fade(view_distance);
}


float get_pom_world_relief(float pom_depth, float view_distance) {
    return pom_depth * pomDepth * get_pom_relief_scale(view_distance);
}

vec3 get_pom_slope_normal(vec2 local_coord, mat2 uv_gradient) {


    vec2 texel = rcp(atlas_tile_scale * vec2(textureSize(normals, 0)));


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

    // The pom height field is displaced by pomDepth in tangent space.


    return vec3(pomDepth * depth_dx, pomDepth * depth_dy, 0.0);
}

vec2 get_parallax_uv(
    vec3 tangent_dir,
    mat2 uv_gradient,
    float view_distance,
    float dither,
    out vec3 previous_ray_pos,
    out float pom_depth
) {
    const float depth_step = rcp(float(pomSamples));

    // Perform one pom step at the original position, fixes pom tiling
    // Thanks to Null for teaching me this
    float depth_value = get_depth_value(atlas_tile_coord, uv_gradient);
    if (depth_value < rcp(255.0)) {
        previous_ray_pos = vec3(atlas_tile_coord, 0.0);
        pom_depth = 0.0;
        return uv;
    }

    float relief_scale = get_pom_relief_scale(view_distance);

    vec3 ray_step = vec3(
                        tangent_dir.xy * rcp(-tangent_dir.z) * pomDepth
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

    for (int i = 0; i < pomSamples && curr_diff > 0.0; ++i) {
        prev_pos = curr_pos;
        prev_diff = curr_diff;
        curr_pos += ray_step;
        curr_diff = get_depth_value(curr_pos.xy, uv_gradient) - curr_pos.z;
    }


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
                        tangent_dir.xy * rcp(tangent_dir.z) * pomDepth
                            * relief_scale,
                        -1.0
                    )
        * pos.z * rcp(float(pomShadowSamples));

    pos.xy += ray_step.xy * dither;

    float max_height = get_depth_value(pos.xy, uv_gradient);
    for (int i = 0; i < pomShadowSamples; ++i) {
        pos += ray_step;
        float offset_height = get_depth_value(pos.xy, uv_gradient);
        float diff = pos.z - offset_height;
        if (diff > 0.0 && max_height - offset_height > eps) {
            return true;
        }
    }

    return false;
}

#endif // INCLUDE_MATERIAL_PARALLAX
