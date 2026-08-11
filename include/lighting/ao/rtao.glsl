#if !defined INCLUDE_LIGHTING_AO_RTAO
#define INCLUDE_LIGHTING_AO_RTAO

#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

float compute_rtao(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_normal,
    vec2 dither
) {
    // Ray traced ambient occlusion
    // Marches rays against the depth buffer in a cosine-weighted hemisphere to
    // find occluders, giving more accurate AO than screen-space heuristics
    mat3 tbn = get_tbn_matrix(view_normal);

    const float step_size = RTAO_RADIUS * rcp(float(RTAO_STEPS));

    float occlusion = 0.0;

    for (int i = 0; i < RTAO_STEPS; ++i) {
        // Cosine-weighted hemisphere sample
        float u1 = fract(dither.x + float(i) * golden_angle);
        float u2 = fract(dither.y + float(i) * 0.7548776662466927);

        float cos_theta = sqrt(1.0 - u1);
        float sin_theta = sqrt(u1);
        float phi = u2 * tau;

        vec3 dir = tbn[0] * (sin_theta * cos(phi))
            + tbn[1] * (sin_theta * sin(phi)) + tbn[2] * cos_theta;

        // Ray march the sample direction
        vec3 ray_pos = view_pos + view_normal * 0.02;

        for (int j = 1; j <= RTAO_STEPS; ++j) {
            vec3 sample_pos = ray_pos + dir * step_size * float(j);

            vec2 sample_uv = view_to_screen_space(
                combined_projection_matrix,
                sample_pos,
                true
            ).xy;

            if (any(lessThan(sample_uv, vec2(0.0)))
                || any(greaterThan(sample_uv, vec2(1.0)))) {
                break;
            }

            ivec2 texel
                = ivec2(clamp01(sample_uv) * view_res * taau_render_scale - 0.5);
            float depth = texelFetch(combined_depth_tex, texel, 0).x;

            if (depth == 1.0 || depth < hand_depth || depth == screen_pos.z) {
                continue;
            }

            vec3 occluder_view = screen_to_view_space(
                combined_projection_matrix_inverse,
                vec3(sample_uv, depth),
                true
            );

            vec3 offset = occluder_view - view_pos;
            float dist = length(offset);

            // The occluder sits in front of the sample along the ray direction
            if (dot(offset, dir) > 0.0 && dist < step_size * float(j)) {
                occlusion += 1.0 - smoothstep(0.0, step_size, dist);
                break;
            }
        }
    }

    return clamp01(1.0 - occlusion * rcp(float(RTAO_STEPS)));
}

#endif // INCLUDE_LIGHTING_AO_RTAO
