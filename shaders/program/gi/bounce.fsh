#if !defined INCLUDE_PROGRAM_GI_BOUNCE
#define INCLUDE_PROGRAM_GI_BOUNCE

// ============================================================================
//  Bounce shader — trace multiple cosine-weighted rays per pixel, sample the previous
//  bounce's output at the hit, multiply by the hit surface's albedo, and
//  write the result into the next bounce's input buffer.
//
//  Parameters (set by the wrapper .fsh in world0/world1/world-1):
//    BOUNCE_PASS  = 1, 2, 3 or 4
//
//  Buffer flow:
//    bounce1: reads colortex0 (d4 direct-lit scene) writes colortex17
//    bounce2: reads colortex17 (bounce1's output) writes colortex17 (flip)
//    bounce3: reads colortex17 (bounce2's output) writes colortex17 (flip)
//    bounce4: reads colortex17 (bounce3's output) writes colortex17 (flip)
//
//  Each bounce also:
//    * samples the sky map (colortex4) on ray miss, so environment radiance
//      still contributes to the indirect term naturally
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

uniform sampler2D colortex0;  // d4 direct-lit scene color (used as the first-bounce source)
uniform sampler2D colortex1;  // gbuffer data 0 (albedo, normals, lightmaps)
uniform sampler2D colortex2;  // gbuffer data 1 (detailed normal, specular)
uniform sampler2D colortex4;  // sky map + light colors

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
#include "/include/lighting/colors/blocklight_color.glsl"
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
#include "/include/lighting/ao/gtao.glsl"
#ifdef HANDHELD_LIGHTING
#include "/include/lighting/handheld_lighting.glsl"
#endif

// Energy transport for surface-to-surface GI.  There is deliberately no
// arbitrary fixed "bounce multiplier" here: every bounce loses energy through
// the hit material's reflectance plus path-length attenuation.
float gi_segment_attenuation(float segment_distance) {
    float normalized_distance = segment_distance / max(INDIRECT_LIGHTING_RADIUS, 1.0);
    // Keep short surface-to-surface paths nearly lossless. The radius only
    // controls the long-path falloff instead of turning ordinary block-sized
    // color bleeding into a barely visible signal.
    return rcp(1.0 + 0.5 * normalized_distance * normalized_distance);
}

// Cosine-weighted sample of the sky map at the given world direction,
// gated by skylight so enclosed pixels don't get free sky light.
vec3 gi_sample_sky(vec3 world_dir, float skylight) {
    vec3 sky = get_ibl_sky_irradiance_shared(world_dir, hash2(vec3(uv * 255.0, frameCounter)));
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
        MOON_PHASE_NIGHT_LIGHTING_INTENSITY * MOON_PHASE_INFLUENCE_INTENSITY,
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

#ifdef HANDHELD_LIGHTING
vec3 gi_direct_handheld_radiance(
    vec3 scene_pos,
    vec3 albedo
) {
    // Handheld lights are already evaluated as local irradiance by the shared
    // handheld-lighting implementation.  Treat it as a direct source at the
    // hit surface, then filter it through that surface's albedo so colored
    // material bounce is preserved.
    return max0(
        albedo * get_handheld_lighting(scene_pos, 1.0)
    );
}
#endif

void main() {
#if BOUNCE_PASS > INDIRECT_LIGHTING_BOUNCES
    bounce_out = vec4(0.0);
    return;
#endif

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

    // Stochastic per-pixel sampling. Multiple cosine-weighted rays are traced
    // per quarter-resolution pixel so narrow/vertical surfaces (like a red wool
    // wall in front of a floor) are actually reached instead of relying on a
    // single directional lottery. Temporal accumulation then further reduces
    // the residual sampling noise.
    float base_dither = texelFetch(noisetex, texel & 511, 0).b;
    base_dither = r1(frameCounter, base_dither);

    vec3 accumulated_radiance = vec3(0.0);
    vec3 radiance = vec3(0.0);
    int valid_samples = 0;

    for (int sample_index = 0; sample_index < INDIRECT_LIGHTING_SAMPLES; ++sample_index) {
        vec2 sample_hash = hash2(vec3(
            uv * view_res + vec2(float(sample_index) * 17.0, float(sample_index) * 31.0),
            float(frameCounter + sample_index * 13)
        ));
        float sample_dither = fract(
            base_dither + sample_hash.x * 0.61803398875
                     + float(sample_index) * 0.17320508075
        );

        vec3 ray_view = gi_cosine_sample_hemisphere(normal_view, sample_hash);
        ray_view = normalize(ray_view);

        // Push the origin off the receiver surface to suppress self-intersections
        // and the bright one-pixel GI halos they can create.
        float ray_origin_offset = max(0.0025, 0.015 * length(view_pixel_size));
        vec3 ray_origin_view = view_pos + normal_view * ray_origin_offset;
        vec3 ray_origin_screen = view_to_screen_space(
            combined_projection_matrix,
            ray_origin_view,
            true
        );

        vec3 hit_uv;
        bool hit = gi_raymarch(
            ray_origin_screen,
            ray_origin_view,
            ray_view,
            sample_dither,
            hit_uv
        );

        vec3 sample_radiance = vec3(0.0);
        if (hit) {
            // Bounce 1 uses the already-computed d4 scene color as the direct
            // source at the hit surface. That guarantees the GI source matches
            // the actual lighting/shadow/material result seen on screen and
            // avoids a second, divergent direct-light implementation here.
            // Later bounces transport the previous bounce's radiance.
#if BOUNCE_PASS == 1
            vec3 source_radiance = texture(colortex0, hit_uv.xy).rgb;
            source_radiance = max0(source_radiance);
#else
            vec3 source_radiance = texture(BOUNCE_INPUT_SAMPLER, hit_uv.xy).rgb;
            source_radiance = max0(source_radiance);
#endif

            ivec2 hit_full_texel = ivec2(
                hit_uv.xy * view_res * taau_render_scale
            );
            hit_full_texel = clamp(
                hit_full_texel,
                ivec2(0),
                ivec2(view_res * taau_render_scale) - ivec2(1)
            );
            float hit_depth = texelFetch(
                combined_depth_tex,
                hit_full_texel,
                0
            ).x;
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
            vec3 hit_albedo = clamp01(gi_read_albedo(hit_full_texel));

            // Reject invalid/back-facing screen-space hits.
            vec3 hit_to_receiver = normalize(scene_pos - hit_scene_pos);
            float hit_NoV = dot(hit_normal_scene, hit_to_receiver);
            if (hit_NoV <= 0.0) {
                continue;
            }

            // Local horizon occlusion suppresses corner/crease leakage. This
            // is applied to the transported energy only, never added as light.
            vec3 bent_normal;
            vec2 gtao = compute_gtao(
                screen_pos,
                view_pos,
                normal_view,
                vec2(sample_dither, fract(sample_hash.x + sample_hash.y)),
                false,
                bent_normal
            );
            float receiver_occlusion = clamp01(gtao.x);

#if BOUNCE_PASS == 1
            // colortex0 already contains the hit surface's complete direct-lit
            // radiance, including its material/albedo response. Do not multiply
            // the hit albedo a second time. This is the actual source term that
            // carries a red wool wall's red energy into the receiver.
            sample_radiance = source_radiance;
#else
            // For subsequent bounces, source_radiance is the radiance arriving
            // at the hit surface from the previous bounce. Reflect it from the
            // hit material so color transport continues correctly.
            sample_radiance = source_radiance * hit_albedo;
#endif

            float segment_distance = length(hit_scene_pos - scene_pos);
            float segment_attenuation = gi_segment_attenuation(segment_distance);
            sample_radiance *= segment_attenuation * receiver_occlusion;
            valid_samples++;
        } else {
            // Sky miss — environment radiance contributes to indirect lighting.
            vec3 ray_world = normalize(mat3(gbufferModelViewInverse) * ray_view);
            sample_radiance = gi_sample_sky(ray_world, skylight);
            valid_samples++;
        }

        accumulated_radiance += max0(sample_radiance);
    }

    if (valid_samples > 0) {
        radiance = accumulated_radiance / float(valid_samples);
    }

    // Write the bounce radiance. Alpha is unused by subsequent bounces;
    // accumulate writes the pixel age into colortex18's alpha separately.
    bounce_out = vec4(max0(radiance), 1.0);
}

#endif // INCLUDE_PROGRAM_GI_BOUNCE
