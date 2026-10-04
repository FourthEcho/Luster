/*
--------------------------------------------------------------------------------

  Luster Shader by FourthEcho

  program/d4_deferred_shading:
  Shade terrain and entities, draw sky

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

// Luster Mac all-on split: deferred11 = lighting, deferred12 = compose.
// World stubs define LUSTER_D4_PASS before including; default is lighting.
#ifndef LUSTER_D4_PASS
#define LUSTER_D4_PASS 1
#endif

layout(location = 0) out vec3 fragment_color;

#if LUSTER_D4_PASS == 1
#ifdef USE_SEPARATE_ENTITY_DRAWS
/* RENDERTARGETS: 0 */
#else
layout(location = 1) out vec4 colortex3_clear;
/* RENDERTARGETS: 0,3 */
#endif
#else
/* RENDERTARGETS: 0 */
#endif

in vec2 uv;

flat in vec3 ambient_color;
flat in vec3 light_color;
#ifdef H_BASIS_SKYLIGHT
flat in vec3 h_sky[6];
#endif

#if defined WORLD_OVERWORLD
flat in vec3 sun_color;
flat in vec3 moon_color;

#include "/include/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;


flat in float rainbow_amount;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0; // skytextured output / previous pass output
uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex4; // sky map
uniform sampler2D colortex5; // scene history (used by SSR reflection reprojection)
uniform sampler2D colortex6; // ambient lighting data
uniform sampler2D colortex7; // fog scattering history (used by SSR reflection reprojection)
uniform sampler2D colortex11; // clouds history
uniform sampler2D colortex12; // clouds data
uniform sampler2D colortex14; // ambient lighting history data

#ifdef ssptEnabled
uniform sampler2D colortex17; // filtered SSPT emission (half res)
#endif

#ifndef USE_SEPARATE_ENTITY_DRAWS
uniform sampler2D colortex3; // OF damage overlay, armor glint
#endif

#if defined WORLD_OVERWORLD && defined GALAXY
uniform sampler2D colortex13;

// Galaxy/LoD support can both declare colortex15
#ifndef LUSTER_COLORTEX15_DECLARED
#define LUSTER_COLORTEX15_DECLARED
uniform sampler2D colortex15;
#endif
#define galaxy_sampler colortex13
#endif

#ifdef CLOUD_SHADOWS
uniform sampler2D colortex8; // cloud shadow map
#endif

uniform sampler3D depthtex0; // atmosphere scattering LUT
uniform sampler2D depthtex1;

#ifdef BLOCKY_CLOUDS
uniform sampler2D depthtex2; // minecraft cloud texture
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

uniform float eyeAltitude;
uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;
uniform float rainStrength;
uniform float desert_sandstorm;
uniform float wetness;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;
uniform vec3 view_light_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float biome_cave;
uniform float biome_may_rain;
uniform float biome_may_snow;
uniform float biome_snowy;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float world_age;
uniform float eye_skylight;

/*
const bool colortex5MipmapEnabled = true;
const bool colortex11MipmapEnabled = true;
*/

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define TEMPORAL_REPROJECTION

#include "/include/fog/simple_fog.glsl"
#include "/include/lighting/ambient/h_basis_skylight.glsl"
#include "/include/lighting/bsdf/diffuse_lighting.glsl"
#include "/include/lighting/direct_lighting/common.glsl"
#include "/include/lighting/direct_lighting/pcss.glsl"
#include "/include/lighting/direct_lighting/ssrt.glsl"
#include "/include/lighting/bsdf/specular_lighting.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/post_processing/purkinje_shift.glsl"
#include "/include/sky/sky.glsl"
#include "/include/surface/edge_highlight.glsl"
#include "/include/surface/material.glsl"
#include "/include/surface/rain_puddles.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/bilateral_upscale.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/space_conversion.glsl"

#if defined WORLD_OVERWORLD
#include "/include/sky/clouds/sampling.glsl"
#include "/include/sky/rainbow.glsl"
#if defined BLOCKY_CLOUDS
#include "/include/sky/blocky_clouds.glsl"
#endif
#endif

#if defined CLOUD_SHADOWS
#include "/include/lighting/cloud_shadows.glsl"
#endif

void main() {
#if LUSTER_D4_PASS == 1 && !defined USE_SEPARATE_ENTITY_DRAWS
    colortex3_clear = vec4(0.0);
#endif

    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Sample textures

    float depth = texelFetch(combined_depth_tex, texel, 0).x;
    vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
#if defined NORMAL_MAPPING || defined SPECULAR_MAPPING
    vec4 gbuffer_data_1 = texelFetch(colortex2, texel, 0);
#endif
#if LUSTER_D4_PASS == 1 && !defined USE_SEPARATE_ENTITY_DRAWS
    vec4 overlays = texelFetch(colortex3, texel, 0);
#endif

    // Check for LoD terrain

#ifdef LOD_MOD_ACTIVE
    float depth_mc = texelFetch(depthtex1, texel, 0).x;
    float depth_lod = texelFetch(lod_depth_tex_shading, texel, 0).x;
    bool is_lod = is_lod_terrain(depth_mc, depth_lod);
#else
    const bool is_lod = false;
#define depth_mc depth
#endif

    // Space conversions

    bool is_hand;
    fix_hand_depth(depth_mc, is_hand);

    vec3 position_view = screen_to_view_space(
        combined_projection_matrix_inverse,
        vec3(uv, depth),
        true
    );
    vec3 position_scene = view_to_scene_space(position_view);
    vec3 position_world = position_scene + cameraPosition;
    vec3 direction_world
        = normalize(position_scene - gbufferModelViewInverse[3].xyz);

    // Shared stochastic offset used by cloud lighting. Animated IGN so
    // residual noise converges instead of sitting as static grain.
    // Compose pass only (sky, clouds, blocky and SSR live there).
#if LUSTER_D4_PASS == 2
    float dither = interleaved_gradient_noise(vec2(texel), frameCounter);
#endif

#if LUSTER_D4_PASS == 2 && defined WORLD_OVERWORLD
    // Atmosphere

    vec3 atmosphere = atmosphere_scattering(
        direction_world,
        sun_color,
        sun_dir,
        moon_color,
        moon_dir,
        /* use_klein_nishina_phase */ depth == 1.0
    );

    // Read clouds/aurora/crepuscular rays

    float clouds_apparent_distance;
    vec4 clouds_and_aurora
        = read_clouds_and_aurora(uv, clouds_apparent_distance);

    // Blocky clouds

#ifdef BLOCKY_CLOUDS
    vec3 world_start_pos = gbufferModelViewInverse[3].xyz + cameraPosition;
    vec3 world_end_pos = position_world;

    vec4 blocky_clouds = raymarch_blocky_clouds(
        world_start_pos,
        world_end_pos,
        depth == 1.0,
        blocky_clouds_altitude_l0,
        dither
    );

#ifdef BLOCKY_CLOUDS_LAYER_2
    float visibility = pow4(blocky_clouds.a);
    vec4 blocky_clouds_l2 = raymarch_blocky_clouds(
        world_start_pos,
        world_end_pos,
        depth == 1.0,
        blocky_clouds_altitude_l1,
        dither
    );
    blocky_clouds.rgb += blocky_clouds_l2.xyz * visibility;
    blocky_clouds.a *= mix(1.0, blocky_clouds_l2.a, visibility);
#endif

    float new_alpha = sqr(sqr(blocky_clouds.a));
    blocky_clouds.rgb
        += atmosphere * (1.0 - new_alpha) * (blocky_clouds.a - new_alpha);
    blocky_clouds.a = new_alpha;
#endif
#endif

    if (depth == 1.0) { // Sky
#if LUSTER_D4_PASS == 1
        // Lighting pass: sky is drawn in the compose pass.
        fragment_color = vec3(0.0);
#else
#if defined WORLD_OVERWORLD
        fragment_color = draw_sky(
            direction_world,
            atmosphere,
            clouds_and_aurora,
            clouds_apparent_distance
        );
#else
        fragment_color = draw_sky(direction_world);
#endif

        // Apply blocky clouds
#if defined WORLD_OVERWORLD && defined BLOCKY_CLOUDS
        fragment_color = fragment_color * blocky_clouds.w + blocky_clouds.xyz;
#endif

        // Apply common fog
        vec4 fog = common_fog(far, true, direction_world * far);
        fragment_color = mix(fog.rgb, fragment_color.rgb, fog.a);

        // Apply purkinje shift
        fragment_color = purkinje_shift(fragment_color, vec2(0.0, 1.0));
#endif
    } else { // Terrain
#if LUSTER_D4_PASS == 1
        // Sample ambient occlusion a while before using it (latency hiding)

        vec2 half_res_pos = gl_FragCoord.xy * (0.5 / taau_render_scale) - 0.5;

        ivec2 i = ivec2(half_res_pos);
        vec2 f = fract(half_res_pos);

        // Sampled early for latency hiding - resolved further down once
        // this fragment's own linear depth (lin_z) is available.
        vec4 ao_data00, ao_data10, ao_data01, ao_data11;
        float ao_depth00, ao_depth10, ao_depth01, ao_depth11;
        bilateral_upscale_sample(
            colortex6,
            colortex14,
            i,
            ao_data00, ao_data10, ao_data01, ao_data11,
            ao_depth00, ao_depth10, ao_depth01, ao_depth11
        );

        // Unpack gbuffer data

        mat4x2 data = mat4x2(
            unpack_unorm_2x8(gbuffer_data_0.x),
            unpack_unorm_2x8(gbuffer_data_0.y),
            unpack_unorm_2x8(gbuffer_data_0.z),
            unpack_unorm_2x8(gbuffer_data_0.w)
        );

        vec3 albedo = vec3(data[0], data[1].x);
        uint material_mask = uint(255.0 * data[1].y);
        vec3 flat_normal = decode_unit_vector(data[2]);
        vec2 light_levels = data[3];

#if LUSTER_D4_PASS == 1 && !defined USE_SEPARATE_ENTITY_DRAWS
        uint overlay_id = uint(255.0 * overlays.a);
        albedo = overlay_id == 0u ? albedo + overlays.rgb
                                  : albedo; // enchantment glint
        albedo = overlay_id == 1u && !is_hand
            ? 2.0 * albedo * overlays.rgb
            : albedo; // damage overlay
#endif

        // Get material and normal

        Material material = material_from(
            albedo,
            material_mask,
            position_world,
            flat_normal,
            light_levels
        );

        vec3 normal = flat_normal;
        bool parallax_shadow = false;

#ifdef LOD_MOD_ACTIVE
        if (!is_lod) {
#endif

#ifdef NORMAL_MAPPING
            normal = decode_unit_vector(gbuffer_data_1.xy);
#endif

#ifdef SPECULAR_MAPPING
            vec4 specular_map = vec4(
                unpack_unorm_2x8(gbuffer_data_1.z),
                unpack_unorm_2x8(gbuffer_data_1.w)
            );
            decode_specular_map(specular_map, material, parallax_shadow);
#elif defined NORMAL_MAPPING
            parallax_shadow = gbuffer_data_1.z >= 0.5;
#endif

#ifdef LOD_MOD_ACTIVE
        }
#endif

        // Rain puddles

#if defined WORLD_OVERWORLD && defined RAIN_PUDDLES
        if (wetness > eps && biome_may_rain > eps) {
            bool puddle = get_rain_puddles(
                position_world,
                flat_normal,
                light_levels,
                material.porosity,
                material_mask,
                normal,
                material.albedo,
                material.f0,
                material.roughness,
                material.ssr_multiplier
            );
        }
#endif

        // Wet-porosity albedo darkening (Kubelka-Munk)
        // Runs independently of puddle placement: any porous surface exposed
        // to rain darkens as water fills its pores, even where puddles don't
        // form (e.g. vertical faces, high-porosity surfaces that absorb
        // rather than pool water).
#if defined WORLD_OVERWORLD && defined POROSITY
        if (wetness > eps && material.porosity > eps) {
            material.albedo = apply_wet_porosity_darkening(
                material.albedo,
                material.porosity,
                wetness * max0(biome_may_rain)
            );
        }
#endif

        // Upscale ambient occlusion

        float lin_z = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            depth
        );

        vec4 ambient_upscaled = bilateral_upscale_resolve(
            ao_data00, ao_data10, ao_data01, ao_data11,
            ao_depth00, ao_depth10, ao_depth01, ao_depth11,
            f,
            combined_projection_matrix_inverse,
            lin_z,
            10.0
        );

        float ao = ambient_upscaled.x;
        float ambient_sss = ambient_upscaled.y;

        vec3 bent_normal;
        bent_normal.xy = ambient_upscaled.zw * 2.0 - 1.0;
        bent_normal.z
            = sqrt(clamp01(1.0 - dot(bent_normal.xy, bent_normal.xy)));
        bent_normal = mat3(gbufferModelViewInverse) * bent_normal;

        // Sense check bent normal
        if (dot(bent_normal, normal) < eps) {
            bent_normal = normal;
        }

        // No AO/bent normal on hand
        if (is_hand) {
            ao = 1.0;
            bent_normal = normal;
        }

        // Calculate lighting dot products

        float NoL = dot(normal, light_dir);
        float NoV = clamp01(dot(normal, -direction_world));
        float LoV = dot(light_dir, -direction_world);
        float halfway_norm = inversesqrt(2.0 * LoV + 2.0);
        float NoH = (NoL + NoV) * halfway_norm;
        float LoH = LoV * halfway_norm + halfway_norm;

        // Cloud shadows

#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
        float cloud_shadows = get_cloud_shadows(colortex8, position_scene);
#else
        const float cloud_shadows = 1.0;
#endif

        // Shadows

#if defined WORLD_OVERWORLD || defined WORLD_END
        vec3 shadows = vec3(0.0);
        float shadow_distance_fade = 1.0;
        float sss_depth = 0.0;

        if (NoL > 1e-3 || material.sss_amount > 1e-3) {
            // Calculate near shadows
            vec3 shadow_near = vec3(0.0);
            float shadow_distant = 0.0;
            float sss_depth_near = 0.0;
            float sss_depth_distant = 0.0;

#ifdef SHADOW
            shadow_near = get_filtered_shadows(
                position_scene,
                flat_normal,
                light_levels.y,
                cloud_shadows,
                material.sss_amount,
                shadow_distance_fade,
                sss_depth_near
            );
#endif

            // Calculate distant shadows
            if (shadow_distance_fade >= eps) {
#ifdef SHADOW_SSRT
                shadow_distant = get_screen_space_shadows(
                    uv,
                    position_view,
                    depth,
#ifdef LOD_MOD_ACTIVE
                    depth_lod,
#endif
                    light_levels.y,
                    material.sss_amount > eps,
                    sss_depth_distant
                );
#else
                shadow_distant = get_lightmap_shadows(light_levels.y);
#endif
            }

            shadows = mix(
                shadow_near,
                vec3(shadow_distant),
                clamp01(shadow_distance_fade)
            );

            sss_depth = mix(
                sss_depth_near,
                sss_depth_distant,
                clamp01(shadow_distance_fade)
            );

#if defined POM && defined POM_SHADOW \
    && (defined SPECULAR_MAPPING || defined NORMAL_MAPPING)
            shadows *= float(!parallax_shadow);
#endif

        }
#else
        const vec3 shadows = vec3(1.0);
        const float shadow_distance_fade = 1.0;
        const float sss_depth = 0.0;
#endif

        // Diffuse lighting. Sky irradiance is directional H-basis
        // evaluated at the bent normal, or the flat sky average with
        // the toggle off. Intensity masters both paths.

#ifdef H_BASIS_SKYLIGHT
        vec3 sky_irradiance = H_BASIS_INTENSITY
            * evaluate_h_basis_irradiance(h_sky, bent_normal);
#else
        vec3 sky_irradiance = H_BASIS_INTENSITY * ambient_color;
#endif

        fragment_color = get_diffuse_lighting(
            material,
            position_scene,
            normal,
            flat_normal,
            shadows,
            light_levels,
            ao,
            ambient_sss,
            sss_depth,
#ifdef CLOUD_SHADOWS
            cloud_shadows,
#endif
#ifdef SHADOW_SSRT
            0.0,
#else
            shadow_distance_fade,
#endif
            NoL,
            NoV,
            NoH,
            LoV,
            sky_irradiance
        );

#ifdef ssptEnabled
        {
            // Sample the SSPT chain's output: screen-space path traced
            // emission + colored lighting, temporally accumulated by
            // d5_sspt_accumulate and a-trous filtered by d6_sspt_filter.
            // The indirect buffers span the whole screen, so plain uv works.
            // Where the trace missed (no bounce geometry / off-screen), the
            // accumulation holds only the AO-weighted vanilla fallback
            // (blocklight gate from d4_sspt), so the selected AO mode
            // (SSAO/GTAO/Off) still shapes those pixels via `ao` below and
            // via the gate. With SSPT off this block is compiled out and
            // get_diffuse_lighting() above applies full AO + vanilla
            // blocklight instead.
            vec3 sspt_light = max0(texture(colortex17, uv).rgb);

            // Same application as the vanilla blocklight path:
            // diffuse modulation by albedo and metal diffuse amount. SSPT
            // already accounts for visibility through its screen-space paths;
            // applying the regular AO here would double-darken traced hits.
            // AO is only used for the vanilla fallback on SSPT misses in d5.
            // NOTE: no extra rcp_pi here -- traceIndirect() already draws
            // its rays with cosine-weighted importance sampling, which
            // bakes that pi-normalization into the Monte Carlo estimator
            // itself. Re-applying rcp_pi on top double-counted it and
            // dimmed colored SSPT light by ~3x for no physical reason.
            sspt_light *= material.albedo;
            sspt_light *= mix(1.0, metal_diffuse_amount, float(material.is_metal));

            // NOTE: no cloud_shadows multiply here. Every component already
            // carries its own correct gating: sun bounce is cloud-shadowed
            // at the hit inside hitDirectLight, lamp emission ignores
            // clouds physically, and traced sky arrives pre-darkened by the
            // cloudy sky map. Multiplying the pixel's cloud factor on top
            // would double-darken all three.

            fragment_color += sspt_light;
        }
#endif

        // Sky ambient: the baked base above owns it. Traced SSPT light
        // carries bounce + emission only, never sky, so the sky mean is
        // counted exactly once.

        // Specular highlight

#if defined WORLD_OVERWORLD || defined WORLD_END
        fragment_color
            += get_specular_highlight(material, NoL, NoV, NoH, LoV, LoH)
            * light_color * shadows * cloud_shadows * ao;
#endif
#else
        // Compose pass: start from the lighting result and recompute the
        // material (overlays excluded — negligible for reflections) so
        // reflections/fog need no extra intermediates.
        fragment_color = texelFetch(colortex0, texel, 0).rgb;

        mat4x2 comp_data = mat4x2(
            unpack_unorm_2x8(gbuffer_data_0.x),
            unpack_unorm_2x8(gbuffer_data_0.y),
            unpack_unorm_2x8(gbuffer_data_0.z),
            unpack_unorm_2x8(gbuffer_data_0.w)
        );

        vec3 comp_albedo = vec3(comp_data[0], comp_data[1].x);
        uint material_mask = uint(255.0 * comp_data[1].y);
        vec3 flat_normal = decode_unit_vector(comp_data[2]);
        vec2 light_levels = comp_data[3];

        Material material = material_from(
            comp_albedo,
            material_mask,
            position_world,
            flat_normal,
            light_levels
        );

        vec3 normal = flat_normal;

#ifdef LOD_MOD_ACTIVE
        if (!is_lod) {
#endif

#ifdef NORMAL_MAPPING
            normal = decode_unit_vector(gbuffer_data_1.xy);
#endif

#ifdef SPECULAR_MAPPING
            vec4 comp_specular_map = vec4(
                unpack_unorm_2x8(gbuffer_data_1.z),
                unpack_unorm_2x8(gbuffer_data_1.w)
            );
            bool comp_parallax = false;
            decode_specular_map(comp_specular_map, material, comp_parallax);
#endif

#ifdef LOD_MOD_ACTIVE
        }
#endif

        // Specular reflections

#if defined ENVIRONMENT_REFLECTIONS || defined SKY_REFLECTIONS
        if (material.ssr_multiplier > eps) {
            mat3 tbn = get_tbn_matrix(normal);

            fragment_color += get_specular_reflections(
                material,
                tbn,
                vec3(uv, depth),
                position_view,
                position_world,
                normal,
                flat_normal,
                direction_world,
                direction_world * tbn,
                light_levels.y,
                false
            );
        }
#endif
        // Edge highlight

#ifdef EDGE_HIGHLIGHT
        fragment_color *= 1.0
            + 0.5
                * get_edge_highlight(
                    position_scene,
                    flat_normal,
                    depth,
                    material_mask
                );
#endif

        // Apply fog

        float view_distance = length(position_view);

#ifdef BORDER_FOG
#if defined WORLD_OVERWORLD
        vec3 horizon_dir = normalize(
            vec3(direction_world.xz, min(direction_world.y, -0.1)).xzy
        );
        vec3 horizon_color = texture(colortex4, project_sky(horizon_dir)).rgb;

        float horizon_factor
            = linear_step(0.1, 1.0, exp(-75.0 * sqr(sun_dir.y + 0.0496)));
        horizon_factor = clamp01(horizon_factor + step(0.01, rainStrength));
        horizon_factor = max(
            horizon_factor,
            dampen(linear_step(0.15, 0.05, direction_world.y))
        );

        vec3 border_fog_color
            = mix(atmosphere, horizon_color, sqr(horizon_factor))
            * (1.0 - biome_cave);
#else
        vec3 border_fog_color
            = texture(colortex4, project_sky(direction_world)).rgb;
#endif

        float border_fog = border_fog(position_scene, direction_world);
        fragment_color = mix(border_fog_color, fragment_color, border_fog);
#endif

        vec4 fog = common_fog(view_distance, false, position_scene);
        fragment_color = fragment_color * fog.a + fog.rgb;

#if defined WORLD_OVERWORLD
        // Apply clouds in front of terrain

#ifdef BLOCKY_CLOUDS
        fragment_color = fragment_color * blocky_clouds.w + blocky_clouds.xyz;
#else
        if (sqr(clouds_apparent_distance) < length_squared(position_view)) {
            fragment_color
                = fragment_color * clouds_and_aurora.w + clouds_and_aurora.xyz;
        }
#endif

        // Apply rainbows in front of terrain

#ifdef RAINBOWS
        fragment_color = draw_rainbows(
            fragment_color,
            direction_world,
            min(view_distance,
                mix(clouds_apparent_distance,
                    1e6,
                    linear_step(1.0, 0.95, clouds_and_aurora.w)))
        );
#endif
#endif

        // Apply purkinje shift

        fragment_color = purkinje_shift(fragment_color, light_levels);
// end LUSTER_D4_PASS terrain split
#endif
    }
}
