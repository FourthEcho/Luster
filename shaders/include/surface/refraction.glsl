#if !defined INCLUDE_SURFACE_REFRACTION
#define INCLUDE_SURFACE_REFRACTION

// ============================================================================
//  Translucent-layer refraction
// ----------------------------------------------------------------------------
//  Screen-space UV distortion of the opaque scene color buffer, driven by
//  the translucent surface's packed tangent-space normal. Distance-scaled
//  by both translucent-layer thickness (existing) and raw view distance
//  (new), rejected if the offset sample would land in front of the
//  surface, and optionally split into per-channel R/G/B offsets for a
//  chromatic-dispersion look (new).
//
//  Ported/extracted from program/c1_blend_layers.fsh (original single-
//  sample offset logic); dispersion + view-distance falloff added after
//  studying Bliss Shader's doRefractionEffect() (dimensions/composite3.fsh)
//  as a reference for the same screen-space-distortion technique.
//
//  Required uniforms (declared by the including program before this file):
//    colortex0  - scene color (post-opaque)
//    depthtex1  - solid depth, used for the behind-surface reject test
//    taau_render_scale
//  (isEyeInWater is read by the caller and passed in as eye_underwater,
//   not read directly by this file.)
//  Required macros (defined by settings.glsl before this file):
//    REFRACTION, REFRACTION_OFF, REFRACTION_INTENSITY,
//    REFRACTION_DISPERSION_INTENSITY
// ============================================================================

// Decodes the packed tangent-space refraction normal written by the
// translucent gbuffer pass. Returns vec2(0.0) if there is no translucent
// geometry at this pixel (refraction_data == vec4(0.0)).
vec2 refraction_normal_from(vec4 refraction_data) {
    return vec2(
        unsplit_2x8(refraction_data.xy) * 2.0 - 1.0,
        unsplit_2x8(refraction_data.zw) * 2.0 - 1.0
    );
}

// Base UV offset amount, shared by both the single-sample and dispersion
// paths. Combines the existing translucent-layer-thickness scale with a
// raw view-distance falloff (mirrors Bliss's
// 0.5 / (1.0 + pow(linearDistance, 0.8)) curve) so refraction visibly
// weakens on distant water/glass instead of staying constant with depth.
//
// eye_underwater further dampens the falloff (matching Bliss's dedicated
// underwater case): when the camera's own eye is submerged, it is looking
// through the same medium the surface is made of, so the water-air
// refraction distortion should read as weaker than when viewed from air.
float refraction_amount(float view_distance, float layer_dist, bool eye_underwater) {
    float thickness_scale = rcp(max(view_distance, 1.0)) * min(layer_dist, 8.0);
    float distance_falloff_rate = eye_underwater ? 1.0 : 0.1;
    float distance_falloff = rcp(1.0 + pow(max(view_distance, 0.0), 0.8) * distance_falloff_rate);
    return thickness_scale * distance_falloff * (0.1 * REFRACTION_INTENSITY);
}

// Rejects the offset (falls back to the un-refracted uv) if the refracted
// sample would land in front of the translucent surface itself.
vec2 reject_if_in_front(vec2 refracted_uv, vec2 uv, float front_depth) {
    float depth_refracted = texture(depthtex1, refracted_uv).x;
    return mix(refracted_uv, uv, float(depth_refracted < front_depth));
}

// Full refraction resolve: computes the distorted uv(s) and returns the
// final scene-color sample. Always takes 3 taps (R/G/B) when a translucent
// surface is hit, since REFRACTION_DISPERSION_INTENSITY is a continuous
// runtime slider rather than a preprocessor toggle; at 0.0 all three taps
// land on the same uv, so the result matches a single-sample lookup.
//
// refracted_uv_out receives the base (non-dispersed, green-channel-equivalent)
// refracted uv even on the dispersion path, since downstream code (e.g. the
// cloud-behind-translucents sample in c1_blend_layers.fsh) needs a single
// uv to key off of, not three.
vec3 apply_refraction(
    vec2 uv,
    vec4 refraction_data,
    bool is_translucent,
    float view_distance,
    float layer_dist,
    float front_depth,
    bool eye_underwater,
    out vec2 refracted_uv_out
) {
    vec2 refracted_uv = uv;
    refracted_uv_out = uv;

#if REFRACTION != REFRACTION_OFF
    if (is_translucent && refraction_data != vec4(0.0)) {
        vec2 normal_tangent = refraction_normal_from(refraction_data);
        float amount = refraction_amount(view_distance, layer_dist, eye_underwater);

        refracted_uv = reject_if_in_front(uv + normal_tangent * amount, uv, front_depth);
        refracted_uv_out = refracted_uv;

        // Dispersion is a runtime blend, not a preprocessor branch, so the
        // REFRACTION_DISPERSION_INTENSITY slider can be a continuous float
        // like the pack's other *_INTENSITY sliders. At 0.0 the dispersion
        // vector collapses to zero and all three taps land on refracted_uv,
        // matching the pre-dispersion single-sample result exactly.
        vec2 dispersion = clamp(normal_tangent, -0.2, 0.2) * 5.0
            * (0.035 * REFRACTION_DISPERSION_INTENSITY);

        vec2 uv_r = reject_if_in_front(uv + (normal_tangent + dispersion) * amount, uv, front_depth);
        vec2 uv_b = reject_if_in_front(uv + (normal_tangent - dispersion) * amount, uv, front_depth);

        vec3 fragment_color;
        fragment_color.r = texture(colortex0, uv_r * taau_render_scale).r;
        fragment_color.g = texture(colortex0, refracted_uv * taau_render_scale).g;
        fragment_color.b = texture(colortex0, uv_b * taau_render_scale).b;
        return fragment_color;
    }
#endif

    return texture(colortex0, refracted_uv * taau_render_scale).rgb;
}

#endif // INCLUDE_SURFACE_REFRACTION
