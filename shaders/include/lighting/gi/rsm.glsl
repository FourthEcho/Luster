/*
--------------------------------------------------------------------------------

  Luster

  include/lighting/gi/rsm.glsl:
  Single-bounce indirect diffuse lighting via Reflective Shadow Maps.

  Every shadow map texel doubles as a virtual point light (VPL): it has a
  world position (from shadowtex0), a surface normal and a sunlit albedo
  (from shadowcolor1, written in program/shadow). To light a gbuffer pixel,
  we disk-sample a handful of nearby shadow map texels, reconstruct each
  VPL's position/normal/albedo, and accumulate a diffuse light-transfer term
  between the VPL and the shaded point.

  Reference: Dachsbacher & Stamminger, "Reflective Shadow Maps" (2005).
  Independently written for Luster's pipeline -- no code from any other
  shader pack. No compute shaders or image load/store are used, so this is
  fully compatible with the GL 4.1 core profile.

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_LIGHTING_GI_RSM
#define INCLUDE_LIGHTING_GI_RSM

#include "/include/lighting/shadows/distortion.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/sampling.glsl"

// Unpacks one VPL from shadowcolor1/shadowtex0 at the given shadow map
// texel. Returns false if the texel has no valid VPL (water, sky, or empty
// shadow space).
bool rsm_fetch_vpl(
    ivec2 texel,
    out vec3 vpl_scene_pos,
    out vec3 vpl_normal,
    out vec3 vpl_albedo
) {
    vec4 packed_vpl = texelFetch(shadowcolor1, texel, 0);

    vec2 albedo_b_and_valid = unpack_unorm_2x8(packed_vpl.w);
    if (albedo_b_and_valid.y < 0.5) {
        return false;
    }

    vpl_normal = decode_unit_vector(packed_vpl.xy);
    vpl_albedo = vec3(unpack_unorm_2x8(packed_vpl.z), albedo_b_and_valid.x);

    float vpl_depth = texelFetch(shadowtex0, texel, 0).x;

    // shadow texel -> shadow clip -> shadow view -> scene space
    vec2 shadow_res = vec2(textureSize(shadowtex0, 0));
    vec2 vpl_shadow_uv = (vec2(texel) + 0.5) * rcp(shadow_res);
    vec2 vpl_clip_xy = vpl_shadow_uv * 2.0 - 1.0;
    vpl_clip_xy *= get_distortion_factor(vpl_clip_xy);

    vec3 vpl_clip_pos = vec3(
        vpl_clip_xy,
        (vpl_depth * 2.0 - 1.0) / SHADOW_DEPTH_SCALE
    );
    vec3 vpl_view_pos = project_ortho(shadowProjectionInverse, vpl_clip_pos);
    vpl_scene_pos = transform(shadowModelViewInverse, vpl_view_pos);

    return true;
}

// Gathers single-bounce indirect diffuse light onto `scene_pos`/`normal`
// from nearby VPLs in the shadow map. `dither` should be a temporally- and
// spatially-varying [0, 1) value to decorrelate the sampling pattern
// between neighboring pixels/frames.
vec3 get_rsm_gi(vec3 scene_pos, vec3 normal, float skylight, float dither) {
    // Fade out as the sun drops below the point where the shadow map still
    // resolves useful VPLs for this pixel (mirrors the direct shadow fade).
    float skylight_fade = linear_step(1.0 / 15.0, 4.0 / 15.0, skylight);
    if (skylight_fade < eps) {
        return vec3(0.0);
    }

    vec3 shadow_view_pos = transform(shadowModelView, scene_pos);
    vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);

    // Fade near the edge of the shadow map so pixels don't pop when the
    // gather disk starts sampling outside its bounds.
    float edge_fade = 1.0 - linear_step(0.8, 1.0, max_of(abs(shadow_clip_pos.xy)));
    if (edge_fade < eps) {
        return vec3(0.0);
    }

    ivec2 shadow_res = textureSize(shadowtex0, 0);
    float gather_radius_clip = RSM_GI_RADIUS * shadowProjection[0].x;

    // Match the reference RSM estimator: progressively larger golden-angle
    // samples carry more area/importance toward the outside of the disk.
    float vpl_area_sq = sqr(RSM_GI_RADIUS) * rcp(float(RSM_GI_SAMPLES));

    vec3 gathered_light = vec3(0.0);
    float rotation = dither * tau;

    for (int i = 0; i < RSM_GI_SAMPLES; ++i) {
        float u = (float(i) + dither) * rcp(float(RSM_GI_SAMPLES));
        float theta = float(i) * golden_angle + rotation;
        float weight = u;

        vec2 disk_offset = (u * gather_radius_clip)
            * vec2(cos(theta), sin(theta));
        vec2 sample_clip_xy = shadow_clip_pos.xy + disk_offset;

        vec2 sample_uv = sample_clip_xy * rcp(get_distortion_factor(sample_clip_xy));
        sample_uv = sample_uv * 0.5 + 0.5;

        if (clamp01(sample_uv) != sample_uv) {
            continue;
        }

        ivec2 texel = ivec2(sample_uv * vec2(shadow_res));

        vec3 vpl_scene_pos, vpl_normal, vpl_albedo;
        if (!rsm_fetch_vpl(texel, vpl_scene_pos, vpl_normal, vpl_albedo)) {
            continue;
        }

        vec3 to_vpl = vpl_scene_pos - scene_pos;
        float dist_sq = dot(to_vpl, to_vpl);
        vec3 to_vpl_dir = to_vpl * inversesqrt(dist_sq + eps);

        float cos_receiver = max0(dot(normal, to_vpl_dir));
        float cos_emitter = max0(dot(vpl_normal, -to_vpl_dir));
        float vpl_irradiance = max0(dot(vpl_normal, light_dir));

        float falloff = rcp(dist_sq + vpl_area_sq);

        gathered_light += vpl_albedo * (vpl_irradiance * cos_receiver * cos_emitter * falloff * weight);
    }

    gathered_light *= 12.0 * sqr(RSM_GI_RADIUS)
        * rcp(float(RSM_GI_SAMPLES));

    return gathered_light * (skylight_fade * edge_fade);
}

#endif // INCLUDE_LIGHTING_GI_RSM
