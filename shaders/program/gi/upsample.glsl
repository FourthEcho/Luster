#if !defined INCLUDE_PROGRAM_GI_UPSAMPLE
#define INCLUDE_PROGRAM_GI_UPSAMPLE

// ============================================================================
//  Bilateral upsample — fetch the quarter-res filtered GI at the current
//  full-res pixel using depth-aware weights so the GI doesn't bleed across
//  silhouette edges. Included by d4_deferred_shading.fsh when
//  INDIRECT_LIGHTING is on.
//
//  The filter takes 4 taps (a 2x2 footprint in the quarter-res buffer) and
//  weights each by how close its depth is to the current full-res pixel's
//  depth. This is much cheaper than a full bilateral filter and produces
//  acceptable results on Minecraft's blocky geometry where depth edges
//  are sharp.
//
//  The returned radiance is the final scene-referred indirect diffuse
//  contribution that d4 should add to fragment_color (albedo already
//  applied, INDIRECT_LIGHTING_INTENSITY already applied, AO already
//  applied).
// ============================================================================

#include "/include/utility/space_conversion.glsl"

// Reads colortex18 (filtered GI) at quarter res, bilaterally upsampled to
// full res using the current pixel's depth.
//
//   uv       : full-res screen-space UV
//   depth    : full-res depth at this pixel
//   albedo   : surface albedo at this pixel (for final albedo modulation)
//   ao       : ambient occlusion at this pixel (for final AO modulation)
//   skylight : light_levels.y — gates indirect contribution from enclosed
//              spaces where the GI ray might not have reached.
vec3 sample_gi_bilateral(vec2 uv, float depth, vec3 albedo, float ao, float skylight) {
    // Bail cleanly on sky / hand — no GI there.
    if (depth >= 1.0 || depth < hand_depth) return vec3(0.0);

    // colortex18 is half-resolution relative to the main render target.
    // TAAU does not change this persistent GI buffer's declared size.
    vec2 gi_texel_f = uv * view_res * 0.5;
    ivec2 p00 = ivec2(floor(gi_texel_f - 0.5));
    ivec2 p10 = p00 + ivec2(1, 0);
    ivec2 p01 = p00 + ivec2(0, 1);
    ivec2 p11 = p00 + ivec2(1, 1);

    // Bilinear weights for the 2x2 footprint.
    vec2 frac = fract(gi_texel_f - 0.5 - p00);

    // 4 bilinear taps with depth-aware weights.
    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;

    // Current view-space z for the depth weight.
    float center_view_z = screen_to_view_space_depth(
        combined_projection_matrix_inverse, depth
    );

    for (int i = 0; i < 4; ++i) {
        ivec2 p;
        float w_xy;
        if (i == 0)      { p = p00; w_xy = (1.0 - frac.x) * (1.0 - frac.y); }
        else if (i == 1) { p = p10; w_xy = frac.x         * (1.0 - frac.y); }
        else if (i == 2) { p = p01; w_xy = (1.0 - frac.x) * frac.y;         }
        else             { p = p11; w_xy = frac.x         * frac.y;         }

        if (p.x < 0 || p.y < 0
            || p.x >= int(view_res.x * 0.5)
            || p.y >= int(view_res.y * 0.5)) continue;

        vec4 gi_sample = texelFetch(colortex18, p, 0);
        if (gi_sample.a <= 0.0) continue;  // sky/hand tap — skip

        // Depth weight: fetch the gbuffer depth at the corresponding
        // full-res pixel and compare to the current pixel's depth. We
        // map quarter-res texel -> full-res texel by multiplying by 2 / 1
        // (i.e. the inverse of view_res * 0.5 -> view_res).
        ivec2 p_full = p * 2;
        if (p_full.x < 0 || p_full.y < 0
            || p_full.x >= int(view_res.x)
            || p_full.y >= int(view_res.y)) continue;
        float n_depth = texelFetch(combined_depth_tex, p_full, 0).x;
        float n_view_z = screen_to_view_space_depth(
            combined_projection_matrix_inverse, n_depth
        );
        float w_d = exp(-abs(center_view_z - n_view_z) * 0.05);

        float w = w_xy * w_d;
        sum += gi_sample.rgb * w;
        weight_sum += w;
    }

    if (weight_sum < 1e-4) return vec3(0.0);

    vec3 gi_radiance = sum / weight_sum;

    // Apply albedo, AO, skylight gating, and the intensity slider. The
    // radiance stored in colortex18 is already scene-referred (it has been
    // through all the bounce + accumulate + filter passes), so we just need
    // to modulate by the receiver's surface properties.
    return gi_radiance * albedo * ao * INDIRECT_LIGHTING_INTENSITY;
}

#endif // INCLUDE_PROGRAM_GI_UPSAMPLE
