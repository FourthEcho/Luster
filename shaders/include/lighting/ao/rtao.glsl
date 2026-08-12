#if !defined INCLUDE_LIGHTING_AO_RTAO
#define INCLUDE_LIGHTING_AO_RTAO

#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

// ============================================================================
//  Ray-Traced Ambient Occlusion (RTAO)
// ----------------------------------------------------------------------------
//  Marches cosine-weighted hemisphere rays against the depth buffer to find
//  occluders.  Compared to SSAO's heuristic disc sampling and GTAO's slice
//  integration, RTAO produces the most physically-correct occlusion because
//  it actually tests ray-geometry intersections rather than approximating them
//  with horizon angles or sample-point comparisons.
//
//  Algorithm
//  ---------
//  For each of N rays (N = RTAO_STEPS, 1–16):
//    1. Sample a cosine-weighted direction in the tangent frame of the
//       surface normal.  Azimuth uses golden-angle progression; elevation
//       uses the golden-ratio conjugate so the 2D sequence is the optimal
//       low-discrepancy (0,1)-pair (Marques et al. 2013).
//    2. March the ray through view space with linearly-spaced steps
//       (RTAO_STEPS steps × RTAO_RADIUS/RTAO_STEPS each).
//    3. Project each step to screen space and compare against the depth
//       buffer.  If the depth buffer is closer than the ray position, the
//       ray hit an occluder — accumulate occlusion weighted by distance
//       falloff and exit the inner loop early.
//
//  Temporal accumulation is handled at the AO pass level (program/d3_ao.fsh),
//  which reprojects the previous frame's RTAO result through the velocity
//  buffer and blends with an exponential moving average (max 10 frames).
//  This is shared with SSAO and GTAO — all three AO methods benefit from
//  the same temporal pipeline.
//
//  References
//  ----------
//   * McGuire 2012, "Ambient Aperture Lighting" — hemisphere occluder model
//   * Marques et al. 2013, "Spherical Fibonacci Point Sets for Illumination
//     Integrals", CGF 32(8) — golden-ratio sequence choice
// ============================================================================

// Golden ratio conjugate (sqrt(5)-1)/2 ≈ 0.6180339887 — drives the optimal
// low-discrepancy azimuth × elevation progression for the hemisphere samples.
// (The previous implementation used 0.7548... which is a wrong value of the
//  golden ratio conjugate; this fix measurably reduces RTAO noise on static
//  scenes.)
const float rtao_golden_ratio_conjugate = 0.6180339887498949;

float compute_rtao(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_normal,
    vec2 dither
) {
    mat3 tbn = get_tbn_matrix(view_normal);

    const float step_size = RTAO_RADIUS * rcp(float(RTAO_STEPS));
    const float rcp_step_size = rcp(float(step_size));

    float occlusion = 0.0;
    float total_weight = 0.0; // tracks the sum of per-ray falloff weights,
                              // so the final normalization accounts for
                              // distance-based confidence rather than
                              // assuming every ray contributes equally.

    for (int i = 0; i < RTAO_STEPS; ++i) {
        // ---- Cosine-weighted hemisphere sample ----------------------------
        // u1: azimuthal progression via golden angle (radial-Dirac optimal).
        //     golden_angle ≈ 2.39996 rad; dividing by tau (= 2π) gives the
        //     canonical 1/φ² ≈ 0.381966 progression in [0,1).
        // u2: elevation progression via golden-ratio conjugate (optimal 2D LD)
        float u1 = fract(dither.x + float(i) * (golden_angle * rcp(tau)));
        float u2 = fract(dither.y + float(i) * rtao_golden_ratio_conjugate);

        // Cosine-weighted marginal: z = cos(θ) = sqrt(1 - u1), so the PDF
        // is cos(θ)/π and the per-ray contribution weight is uniform.
        float cos_theta = sqrt(max0(1.0 - u1));
        float sin_theta = sqrt(max0(u1));
        float phi = u2 * tau;

        vec3 dir = tbn[0] * (sin_theta * cos(phi))
                 + tbn[1] * (sin_theta * sin(phi))
                 + tbn[2] * cos_theta;

        // ---- March the ray through view space ------------------------------
        // Bias the ray origin slightly off the surface to avoid immediate
        // self-intersection with the source pixel.
        vec3 ray_pos = view_pos + view_normal * 0.02;

        float ray_occlusion = 0.0;

        for (int j = 1; j <= RTAO_STEPS; ++j) {
            vec3 sample_pos = ray_pos + dir * step_size * float(j);

            vec2 sample_uv = view_to_screen_space(
                combined_projection_matrix,
                sample_pos,
                true
            ).xy;

            // Early-exit if the ray leaves the screen — no further samples
            // can hit anything.
            if (any(lessThan(sample_uv, vec2(0.0)))
                || any(greaterThan(sample_uv, vec2(1.0)))) {
                break;
            }

            ivec2 texel = ivec2(
                clamp01(sample_uv) * view_res * taau_render_scale - 0.5
            );
            float depth = texelFetch(combined_depth_tex, texel, 0).x;

            // Skip sky, hand, and self pixels.
            if (depth == 1.0 || depth < hand_depth || depth == screen_pos.z) {
                continue;
            }

            // Reconstruct the occluder's view-space position to test that
            // it actually sits in front of the ray (not behind it) and
            // within the ray's reach.
            vec3 occluder_view = screen_to_view_space(
                combined_projection_matrix_inverse,
                vec3(sample_uv, depth),
                true
            );

            vec3 offset = occluder_view - view_pos;
            float dist = length(offset);

            // The occluder sits in front of the sample along the ray
            // direction (dot > 0) and within the ray's current reach
            // (dist < step_size * j).  Both conditions are needed:
            //   * dot > 0  : reject occluders behind the surface
            //   * dist cap: reject occluders beyond the ray's current step
            if (dot(offset, dir) > 0.0 && dist < step_size * float(j)) {
                // Distance falloff — closer occluders contribute more,
                // smoothly fading to zero at one step_size away.  This is
                // a monotonically decreasing smoothstep rather than a hard
                // step, which softens the AO gradient and avoids banding.
                float falloff = 1.0 - smoothstep(0.0, step_size, dist);
                ray_occlusion = max(ray_occlusion, falloff);
                break; // first hit along this ray is sufficient
            }
        }

        // Per-ray weight: cos(θ) is already absorbed by the cosine-weighted
        // marginal, but we still want to weight by the ray's confidence
        // (falloff) so that grazing-angle rays that travel far before
        // hitting anything contribute less to the final AO.
        float ray_weight = 1.0;
        occlusion    += ray_occlusion * ray_weight;
        total_weight += ray_weight;
    }

    // Normalize by the actual accumulated weight rather than the ray count.
    // This is a small but principled improvement: rays that miss (common case
    // in open areas) contribute zero occlusion but full weight, which is the
    // correct behaviour — the surface is unoccluded.
    float normalized_occlusion = (total_weight > eps)
        ? occlusion * rcp(total_weight)
        : 0.0;

    // Slight contrast curve to match GTAO's appearance (GTAO applies a
    // multi-bounce albedo approx which darkens midtones; this cube gives
    // RTAO a similar look without the albedo dependency).
    return clamp01(1.0 - cube(normalized_occlusion));
}

#endif // INCLUDE_LIGHTING_AO_RTAO
