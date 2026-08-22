#if !defined INCLUDE_PROGRAM_GI_BOUNCE
#define INCLUDE_PROGRAM_GI_BOUNCE

// ============================================================================
//  Bounce shader — trace one cosine ray per pixel, sample the previous
//  bounce's output at the hit, multiply by the hit surface's albedo, and
//  write the result into the next bounce's input buffer.
//
//  Parameters (set by the wrapper .fsh in world0/world1/world-1):
//    BOUNCE_PASS  = 1, 2, 3 or 4
//
//  Buffer flow:
//    bounce1: reads colortex18 (last frame's accumulated) writes colortex17
//    bounce2: reads colortex17 (bounce1's output)   writes colortex17 (flip)
//    bounce3: reads colortex17 (bounce2's output)   writes colortex17 (flip)
//    bounce4: reads colortex17 (bounce3's output)   writes colortex17 (flip)
//
//  Each bounce also:
//    * samples the sky map (colortex4) on ray miss, so sky radiance flows
//      into the bounce chain naturally
//    * modulates the result by the hit pixel's albedo — the final bounce
//      output is "radiance leaving the surface after N bounces"
//    * applies skylight gating from the lightmap so enclosed spaces don't
//      get free sky light
// ============================================================================

#include "/include/global.glsl"

// ----------------------------------------------------------------------------
//   Uniforms
//
//   NB: these MUST be declared before the includes below — space_conversion,
//   light_color and the GI shared helpers reference them at global scope, and
//   GLSL requires declaration before use.
// ----------------------------------------------------------------------------

#if BOUNCE_PASS == 1
  #define BOUNCE_INPUT_SAMPLER  colortex18
  uniform sampler2D colortex18; // last frame's accumulated GI
#else
  #define BOUNCE_INPUT_SAMPLER  colortex17
  uniform sampler2D colortex17; // previous bounce's output (this frame)
#endif

uniform sampler2D colortex1;  // gbuffer data 0 (albedo, normals, lightmaps)
uniform sampler2D colortex2;  // gbuffer data 1 (detailed normal, specular)
uniform sampler2D colortex4;  // sky map + light colors
uniform sampler2D colortex5;  // TAA scene history — used for sky-miss fallback

#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
uniform sampler2D colortex8;  // cloud shadow map
#endif

#ifndef WORLD_NETHER
#ifdef SHADOW
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;
#ifdef SHADOW_COLOR
uniform sampler2D shadowcolor0;
#endif
#endif
#endif

uniform sampler2D noisetex;
uniform sampler2D depthtex1; // fallback combined_depth_tex when no LoD mod

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

// Needed by ibl.glsl / light_color.glsl / atmosphere.glsl
uniform float rainStrength;
uniform float sunAngle;
uniform int moonPhase;
uniform float eyeAltitude;
uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;
uniform vec3 view_light_dir;
uniform float time_sunrise;
uniform float time_sunset;

layout(location = 0) out vec4 bounce_out;

/* RENDERTARGETS: 17 */

in vec2 uv;

// ----------------------------------------------------------------------------
//   Includes
// ----------------------------------------------------------------------------

#define TEMPORAL_REPROJECTION

#include "/include/lighting/ibl/ibl.glsl"
#if defined WORLD_OVERWORLD
#include "/include/lighting/colors/light_color.glsl"
#include "/include/lighting/shadows/common.glsl"
#include "/include/lighting/shadows/pcss.glsl"
#include "/include/lighting/shadows/ssrt.glsl"
#ifdef CLOUD_SHADOWS
#include "/include/lighting/cloud_shadows.glsl"
#endif
#elif defined WORLD_END
#include "/include/lighting/colors/end_color.glsl"
#include "/include/lighting/shadows/common.glsl"
#include "/include/lighting/shadows/pcss.glsl"
#include "/include/lighting/shadows/ssrt.glsl"
#endif
#include "/program/gi/shared.glsl"

// Cosine-weighted sample of the sky map at the given world direction,
// gated by skylight so enclosed pixels don't get free sky light.
vec3 gi_sample_sky(vec3 world_dir, float skylight) {
    vec3 sky = get_ibl_sky_irradiance(world_dir, hash2(vec3(uv * 255.0, frameCounter)), 4);
    return sky * skylight;
}

#if defined WORLD_OVERWORLD || defined WORLD_END
vec3 gi_celestial_shadow(
    vec3 scene_pos,
    vec3 flat_normal,
    float skylight
) {
#if defined SHADOW
    float shadow_distance_fade = 1.0;
    float sss_depth = 0.0;
    vec3 shadow_near = get_filtered_shadows(
        scene_pos,
        flat_normal,
        skylight,
#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
        get_cloud_shadows(colortex8, scene_pos),
#else
        1.0,
#endif
        0.0,
        shadow_distance_fade,
        sss_depth
    );

    float shadow_distant = 0.0;
    if (shadow_distance_fade >= eps) {
#ifdef SHADOW_SSRT
        vec3 scene_view_pos = transform(gbufferModelView, scene_pos);
        vec3 scene_screen_pos = view_to_screen_space(
            gbufferProjection,
            scene_view_pos,
            true
        );
#ifdef LOD_MOD_ACTIVE
        float shadow_depth_lod = texelFetch(
            lod_depth_tex,
            ivec2(scene_screen_pos.xy * view_res * taau_render_scale),
            0
        ).x;
        shadow_distant = get_screen_space_shadows(
            scene_screen_pos.xy,
            scene_view_pos,
            scene_screen_pos.z,
            shadow_depth_lod,
            skylight,
            false,
            sss_depth
        );
#else
        shadow_distant = get_screen_space_shadows(
            scene_screen_pos.xy,
            scene_view_pos,
            scene_screen_pos.z,
            skylight,
            false,
            sss_depth
        );
#endif
#else
        shadow_distant = get_lightmap_shadows(skylight);
#endif
    }

    return mix(
        shadow_near,
        vec3(shadow_distant),
        clamp01(shadow_distance_fade)
    );
#elif defined SHADOW_SSRT
    vec3 scene_view_pos = transform(gbufferModelView, scene_pos);
    vec3 scene_screen_pos = view_to_screen_space(
        gbufferProjection,
        scene_view_pos,
        true
    );
    float sss_depth = 0.0;
#ifdef LOD_MOD_ACTIVE
    float shadow_depth_lod = texelFetch(
        lod_depth_tex,
        ivec2(scene_screen_pos.xy * view_res * taau_render_scale),
        0
    ).x;
    float visibility = get_screen_space_shadows(
        scene_screen_pos.xy,
        scene_view_pos,
        scene_screen_pos.z,
        shadow_depth_lod,
        skylight,
        false,
        sss_depth
    );
#else
    float visibility = get_screen_space_shadows(
        scene_screen_pos.xy,
        scene_view_pos,
        scene_screen_pos.z,
        skylight,
        false,
        sss_depth
    );
#endif
    return vec3(visibility);
#else
    return vec3(get_lightmap_shadows(skylight));
#endif
}

vec3 gi_celestial_source_radiance() {
#if defined WORLD_OVERWORLD
    vec3 sun_radiance = get_sun_exposure() * get_sun_tint() * sunlight_color;
    vec3 moon_radiance = get_moon_exposure() * get_moon_tint();
#ifdef MOON_PHASE_NIGHT_LIGHTING
    moon_radiance = apply_moon_phase_influence(
        moon_radiance,
        MOON_PHASE_NIGHT_LIGHTING_INTENSITY,
        MOON_PHASE_NIGHT_LIGHTING_CONTRAST,
        MOON_PHASE_NIGHT_LIGHTING_SATURATION
    );
#endif
    return mix(sun_radiance, moon_radiance, step(0.5, sunAngle));
#elif defined WORLD_END
    return get_light_color();
#else
    return vec3(0.0);
#endif
}

vec3 gi_direct_celestial_radiance(
    vec3 scene_pos,
    vec3 flat_normal,
    float skylight,
    vec3 albedo
) {
    float NoL = max0(dot(flat_normal, light_dir));
    if (NoL <= eps) {
        return vec3(0.0);
    }

    vec3 light_radiance = gi_celestial_source_radiance();
#if defined WORLD_OVERWORLD
    // scene_pos is camera-relative; atmosphere transmittance expects the
    // world-space position relative to the planet centre. Evaluate the
    // celestial path from the actual hit location rather than applying the
    // receiver-wide direct-light extinction a second time.
    vec3 hit_world_pos = scene_pos + cameraPosition;
    light_radiance *= atmosphere_transmittance(hit_world_pos, light_dir);
#endif

    vec3 visibility = gi_celestial_shadow(scene_pos, flat_normal, skylight);
    return max0(albedo * light_radiance * (NoL * visibility));
}
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 full_texel = gi_full_res_texel();

    // Bail on sky pixels and on hand layer.
    float depth = gi_read_depth(full_texel);
    if (depth >= 1.0 || depth < hand_depth) {
        bounce_out = vec4(0.0);
        return;
    }

    // Reconstruct view-space position from the depth.
    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    // Surface attributes at the receiver.
    vec3 normal_scene = gi_read_scene_normal(full_texel);
    vec3 normal_view = normalize(mat3(gbufferModelView) * normal_scene);
    vec2 light_levels = gi_read_light_levels(full_texel);
    float skylight = clamp01(light_levels.y);

    // Stochastic per-pixel dither (R2 sequence + blue noise). The bounce
    // shader needs a fresh sample every frame so the temporal accumulate
    // pass can average bounce noise across frames.
    float dither = texelFetch(noisetex, texel & 511, 0).b;
    dither = r1(frameCounter, dither);

    vec2 hash = hash2(vec3(uv * view_res, frameCounter));
    vec3 ray_view = gi_cosine_sample_hemisphere(normal_view, hash);
    ray_view = normalize(ray_view);

    vec3 hit_uv;
    bool hit = gi_raymarch(screen_pos, view_pos, ray_view, dither, hit_uv);

    vec3 radiance = vec3(0.0);
    if (hit) {
        // Sample previous bounce's output at the hit UV. The hit position
        // is in quarter-res UV space because that's where the GI passes run.
        // The bounce buffer (colortex17) is already at quarter-res so a
        // direct texture() sample at hit_uv.xy works.
        vec3 prev_radiance = texture(BOUNCE_INPUT_SAMPLER, hit_uv.xy).rgb;
        prev_radiance = max0(prev_radiance);

        // Reconstruct the actual hit surface so direct celestial light can be
        // evaluated there. This is the missing physical path that lets sun or
        // moon light bounce off one surface into the current GI sample.
        ivec2 hit_full_texel = ivec2(hit_uv.xy * view_res * taau_render_scale);
        float hit_depth = texelFetch(combined_depth_tex, hit_full_texel, 0).x;
        vec3 hit_screen_pos = vec3(hit_uv.xy, hit_depth);
        vec3 hit_view_pos = screen_to_view_space(
            combined_projection_matrix_inverse,
            hit_screen_pos,
            true
        );
        vec3 hit_scene_pos = view_to_scene_space(hit_view_pos);
        vec3 hit_normal_scene = gi_read_scene_normal(hit_full_texel);
        vec2 hit_light_levels = gi_read_light_levels(hit_full_texel);
        float hit_skylight = clamp01(hit_light_levels.y);
        vec3 hit_albedo = gi_read_albedo(hit_full_texel);

        // The previous-bounce term carries light arriving from the rest of the
        // path. The explicit celestial term carries direct sun/moon light from
        // the current hit surface. Both are radiance leaving that hit toward
        // the current surface, so cosine-weighted Lambertian sampling can
        // propagate them without another 1/pi factor here.
        radiance = prev_radiance * hit_albedo;
#if defined WORLD_OVERWORLD || defined WORLD_END
        radiance += gi_direct_celestial_radiance(
            hit_scene_pos,
            hit_normal_scene,
            hit_skylight,
            hit_albedo
        );
#endif

        // Apply the cosine-weighted Lambertian estimator. The cosine PDF
        // cancels the BRDF's 1/pi term, leaving albedo-weighted incident
        // radiance for the next path segment.
    } else {
        // Sky miss — sample the live sky map and apply skylight gating.
        // The sky irradiance is fetched from the IBL environment, which is
        // already updated every frame in d0_sky_map.
        vec3 ray_world = normalize(mat3(gbufferModelViewInverse) * ray_view);
        radiance = gi_sample_sky(ray_world, skylight);

#if BOUNCE_PASS == 1
        // First bounce: when the ray misses, also blend in the previous
        // frame's accumulated output so temporal continuity isn't lost on
        // disocclusion. This is the "use TAA's history" trick — the GI
        // history buffer reads what TAA already wrote into colortex5.
        // This avoids a hard pop when the camera moves into a new area.
        vec3 taa_history = max0(texture(colortex5, hit_uv.xy).rgb);
        float history_weight = 0.25 * (1.0 - skylight);
        radiance = mix(radiance, taa_history, history_weight);
#endif
    }

    // Write the bounce radiance. Alpha is unused by subsequent bounces;
    // accumulate writes the pixel age into colortex18's alpha separately.
    bounce_out = vec4(max0(radiance), 1.0);
}

#endif // INCLUDE_PROGRAM_GI_BOUNCE
