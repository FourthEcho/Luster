#if !defined INCLUDE_LIGHTING_RSM_GI
#define INCLUDE_LIGHTING_RSM_GI

// Single-bounce diffuse GI from reflective shadow maps.
// Dachsbacher & Stamminger, "Reflective Shadow Maps" (I3D 2005): every texel
// of the sun shadow map is treated as a virtual point light (VPL). The
// shadow pass captures each texel's albedo and world-space normal in
// shadowcolor1 (see program/shadow.fsh), so no extra scene pass is required.
//
// Known limitation (accepted): there is no visibility test between VPL and
// receiver, so light can leak through thin walls. The two cos terms below
// (VPL facing the receiver, receiver facing the VPL) suppress most of it,
// and the sample disk radius (RSM_GI_RADIUS) is kept modest; keep it small
// indoors. Full occlusion-correct RSM (imperfect shadow maps, voxel methods)
// is far too expensive for a real-time Minecraft scene.
//
// Requires in the including program:
//   uniform sampler2D shadowtex0;    (opaque shadow depth)
//   uniform sampler2D shadowcolor1;  (VPL albedo + packed normal)
//   uniform mat4 shadowModelView, shadowModelViewInverse;
//   uniform mat4 shadowProjection, shadowProjectionInverse;
//   uniform vec3 light_dir;
//   uniform float near, far;

#include "/include/utility/fast_math.glsl"
#include "/include/lighting/shadows/common.glsl"
#include "/include/lighting/shadows/distortion.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/sampling.glsl"

// Separate name so that this can coexist with pcss.glsl's shadow_map_res
const int rsm_shadow_map_res = int(float(shadowMapResolution) * MC_SHADOW_QUALITY);

// Reconstruct the scene-space position of a shadow map texel (its VPL)
vec3 rsm_vpl_scene_pos(vec2 shadow_uv, float shadow_depth) {
    vec3 distorted_pos = vec3(shadow_uv * 2.0 - 1.0, shadow_depth * 2.0 - 1.0);
    vec3 shadow_clip_pos = undistort_shadow_space(distorted_pos);

    vec3 shadow_view_pos
        = project_ortho(shadowProjectionInverse, shadow_clip_pos);

    return transform(shadowModelViewInverse, shadow_view_pos);
}

// Gather the RSM GI irradiance for one receiver. Uses a fixed, fully
// unrolled sample loop (no data-dependent branches) with a Vogel spiral
// in shadow clip space, re-dithered every frame so that the temporal
// accumulation pass can converge.
vec3 rsm_gi_gather(
    vec3 scene_pos,
    vec3 flat_normal,
    float skylight,
    vec3 light_color,
    float dither
) {
    float NoL = dot(flat_normal, light_dir);

    // Same bias the filtered shadows use, so the receiver's own texel does
    // not light itself
    vec3 bias = get_shadow_bias(scene_pos, flat_normal, NoL, skylight);

    vec3 shadow_view_pos = transform(shadowModelView, scene_pos + bias);
    vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);
    vec3 shadow_screen_pos = distort_shadow_space(shadow_clip_pos) * 0.5 + 0.5;

    // Fade out at the edge of / beyond the shadow map. This also masks
    // receivers whose projection falls outside [0, 1] shadow uv.
    float distance_fade = get_shadow_distance_fade(scene_pos, shadow_screen_pos);

    // Prevent sunlight bouncing into spots the sun can't reach (caves)
    float leak_prevention = get_lightmap_light_leak_prevention(skylight);

    // Disk radius, given in blocks, converted to shadow clip units
    float radius_clip = RSM_GI_RADIUS * shadowProjection[0].x;

    vec3 sum = vec3(0.0);

    for (int i = 0; i < RSM_GI_SAMPLES; ++i) {
        vec2 offset
            = vogel_disc_sample(i, RSM_GI_SAMPLES, dither * tau) * radius_clip;

        vec2 sample_pos = shadow_clip_pos.xy + offset;

        // Keep the fetch in bounds; masked below if the sample left the map
        float in_bounds = step(max_of(abs(sample_pos)), 1.0);
        vec2 sample_uv = clamp01(sample_pos) * 0.5 + 0.5;

        ivec2 sample_texel = min(
            ivec2(sample_uv * float(rsm_shadow_map_res)),
            ivec2(rsm_shadow_map_res - 1)
        );

        float vpl_depth = texelFetch(shadowtex0, sample_texel, 0).x;
        vec4 vpl_data = texelFetch(shadowcolor1, sample_texel, 0);

        // Shadow texels at depth 1.0 hold no geometry (sky) -> no VPL
        float vpl_valid = step(vpl_depth, 1.0 - 1e-3) * in_bounds;

        vec3 vpl_normal = decode_unit_vector(unpack_unorm_2x8(vpl_data.a));
        vec3 vpl_pos = rsm_vpl_scene_pos(sample_uv, vpl_depth);

        // Flux emitted by the VPL: its albedo times the sunlight it receives
        vec3 flux = vpl_data.rgb * light_color * max0(dot(vpl_normal, light_dir));

        vec3 vpl_to_receiver = scene_pos - vpl_pos;
        float dist = length(vpl_to_receiver);
        vec3 dir = vpl_to_receiver * rcp(max(dist, eps));

        // Clamped 1/d^4 kernel (per Dachsbacher, kills the singularity)
        float atten = rcp(max(pow4(dist), pow4(RSM_GI_MIN_DISTANCE)));

        sum += flux
            * max0(dot(flat_normal, dir))
            * max0(dot(vpl_normal, -dir))
            * (atten * vpl_valid);
    }

    // Uniform-disk Monte Carlo estimator: sum * disk area / sample count
    vec3 gi = sum * (pi * sqr(RSM_GI_RADIUS) * rcp(float(RSM_GI_SAMPLES)));

    return gi * leak_prevention * (1.0 - clamp01(distance_fade));
}

#endif // INCLUDE_LIGHTING_RSM_GI
