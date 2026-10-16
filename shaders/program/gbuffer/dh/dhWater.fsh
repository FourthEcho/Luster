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

#include "/lib/global.glsl"

layout(location = 0) out vec4 fragment_color;
layout(
    location = 1
) out vec4 gbuffer_data; // albedo, block ID, flat normal, light levels

/* RENDERTARGETS: 0,1 */

in vec2 light_levels;
in vec3 scene_pos;
in vec3 normal;
in vec4 tint;

flat in uint is_water;
flat in vec3 light_color;
flat in vec3 ambient_color;

#if defined PROGRAM_GBUFFERS_WATER
in vec2 atlas_tile_coord;
in vec3 tangent_pos;
flat in vec2 atlas_tile_offset;
flat in vec2 atlas_tile_scale;
#endif

#if defined WORLD_OVERWORLD
#include "/lib/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex5; // scene history (used by SSR reflection reprojection)
uniform sampler2D colortex7; // fog scattering history (used by SSR reflection reprojection)


#ifdef cloudShadows
uniform sampler2D colortex8; // Cloud shadow map
#endif

uniform sampler2D depthtex0;

#ifdef shadow
#ifdef WORLD_OVERWORLD
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;
#endif

#ifdef WORLD_END
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;
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

uniform float near;
uniform float far;

uniform float frameTimeCounter;
uniform float sunAngle;
uniform float rainStrength;
uniform float desert_sandstorm;
uniform float wetness;

uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;

uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;
uniform float eyeAltitude;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float eye_skylight;

uniform float biome_cave;
uniform float biome_may_rain;
uniform float biome_may_snow;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

#if defined PROGRAM_GBUFFERS_ENTITIES_TRANSLUCENT
uniform vec4 entityColor;
#endif

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION

#ifdef shadowColor
#undef shadowColor
#endif

#if defined PROGRAM_GBUFFERS_TEXTURED \
    || defined PROGRAM_GBUFFERS_PARTICLES_TRANSLUCENT
#define NO_NORMAL
#endif


#include "/lib/fog/simpleFog.glsl"
#include "/lib/brdf/diffuseLight.glsl"
#include "/lib/light/pcss.glsl"
#include "/lib/brdf/specular.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/material/material.glsl"
#include "/lib/material/water.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/spaceConversion.glsl"

#ifdef cloudShadows
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHTING_CLOUD_SHADOWS
#define INCLUDE_LIGHTING_CLOUD_SHADOWS

#include "/lib/sky/clouds/constants.glsl"
#include "/lib/util/bicubic.glsl"

const ivec2 cloud_shadow_res = ivec2(512);

const float cloud_shadow_extent = 256.0 / (cloudsScale / 10.0);

vec2 shadow_view_to_cloud_shadow_space(vec3 shadow_view_pos) {
    vec2 cloud_shadow_pos = shadow_view_pos.xy / cloud_shadow_extent;
    cloud_shadow_pos /= 1.0 + length(cloud_shadow_pos);
    cloud_shadow_pos = cloud_shadow_pos * 0.5 + 0.5;

    return cloud_shadow_pos;
}

vec2 project_cloud_shadow_map(vec3 scene_pos) {
    return shadow_view_to_cloud_shadow_space(
        transform(shadowModelView, scene_pos)
    );
}

vec3 unproject_cloud_shadow_map(vec2 cloud_shadow_pos) {
    cloud_shadow_pos = cloud_shadow_pos * 2.0 - 1.0;
    cloud_shadow_pos /= 1.0 - length(cloud_shadow_pos);

    vec3 shadow_view_pos = vec3(cloud_shadow_pos * cloud_shadow_extent, 1.0);

    return transform(shadowModelViewInverse, shadow_view_pos);
}

float get_cloud_shadows(sampler2D cloud_shadow_map, vec3 scene_pos) {
#ifndef cloudShadows
    return 1.0;
#else
    vec2 cloud_shadow_pos = project_cloud_shadow_map(scene_pos)
        * vec2(cloud_shadow_res) / vec2(textureSize(cloud_shadow_map, 0));

    if (clamp01(cloud_shadow_pos) != cloud_shadow_pos) {
        return 1.0;
    }

    // fade out cloud shadows when:
    //  - the fragment is above the cloud layer
    //  - the sun is near the horizon
    float r = planet_radius
        + (scene_pos.y + eyeAltitude - 63.0) * cloudsScale;
    float altitude_fraction
        = linear_step(clouds_cumulus_radius, clouds_cumulus_top_radius, r);
    float cloud_shadow_fade = smoothstep(0.05, 0.15, light_dir.y)
        * clamp01(1.0 - altitude_fraction);

    float cloud_shadow = bicubic_filter(cloud_shadow_map, cloud_shadow_pos).x;
    cloud_shadow = cloud_shadow * cloud_shadow_fade + (1.0 - cloud_shadow_fade);

    return cloud_shadow * cloudShadowsIntensity
        + (1.0 - cloudShadowsIntensity);
#endif
}

#if defined PROGRAM_PREPARE && defined cloudShadows
#include "/lib/sky/clouds/altocumulus.glsl"
#include "/lib/sky/clouds/cirrus.glsl"
#include "/lib/sky/clouds/cumulus.glsl"
#include "/lib/sky/clouds/cumulusCongestus.glsl"

vec2 render_cloud_shadow_map(vec2 uv) {
    // Transform position from scene-space to clouds-space
    vec3 ray_origin = unproject_cloud_shadow_map(uv);
    ray_origin = vec3(ray_origin.xz, ray_origin.y + eyeAltitude - 63.0).xzy
            * cloudsScale
        + vec3(0.0, planet_radius, 0.0);

    vec3 pos;
    float t, density, extinction_coeff;
    float shadowVis = 1.0;
    float shadow_cumulus_only = 1.0;
    float distance_fade;
    float distance_fade_strength = 0.00000001 * pulse(light_dir.y, -0.01, 0.2);

#ifdef cloudsCumulus
    extinction_coeff = 0.25 * clouds_params.l0_extinction_coeff;
    t = intersect_sphere(
            ray_origin,
            light_dir,
            clouds_cumulus_radius + 0.25 * clouds_cumulus_thickness
    )
            .y;
    pos = ray_origin + light_dir * t;
    distance_fade = exp2(-distance_fade_strength * length(pos.xy));
    density = clouds_cumulus_density(pos);
    shadowVis *= exp(
        -1.00 * distance_fade * extinction_coeff * clouds_cumulus_thickness
        * rcp(abs(light_dir.y) + eps) * density
    );
    shadow_cumulus_only = shadowVis;
#endif

#ifdef cloudsAltocumulus
    extinction_coeff = mix(0.05, 0.1, day_factor) * cloudsAltocumulusDensity
        * (1.0 - 0.33 * rainStrength);
    t = intersect_sphere(
            ray_origin,
            light_dir,
            clouds_altocumulus_radius + 0.5 * clouds_altocumulus_thickness
    )
            .y;
    pos = ray_origin + light_dir * t;
    distance_fade = exp2(-distance_fade_strength * length(pos.xy));
    density = clouds_altocumulus_density(pos);
    shadowVis *= exp(
        -1.00 * distance_fade * extinction_coeff * clouds_altocumulus_thickness
        * rcp(abs(light_dir.y) + eps) * density
    );
#endif

#ifdef cloudsCirrus
    t = intersect_sphere(ray_origin, light_dir, clouds_cirrus_radius).y;
    pos = ray_origin + light_dir * t;
    distance_fade = exp2(-distance_fade_strength * length(pos.xy));
    density = clouds_cirrus_density(pos.xz, 0.5);
    shadowVis *= exp(-1.00 * distance_fade * clouds_cirrus_extinction_coeff
                  * clouds_cirrus_thickness * rcp(abs(light_dir.y) + eps)
                  * density)
            * 0.5
        + 0.5;
#endif

    return vec2(shadowVis, shadow_cumulus_only);
}
#endif
#endif // INCLUDE_LIGHTING_CLOUD_SHADOWS
#endif

#if defined(LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS)
// Directional lightmap modulation.
#if !defined INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS

// Based on Ninjamike's implementation in shaderLABS #snippets

vec2 get_directional_lightmaps(vec3 position_scene, vec3 normal) {
    vec2 lightmap_mul = vec2(1.0);

    vec2 lightmap_gradient;
    vec3 lightmap_dir;
    mat2x3 pos_gradient = mat2x3(dFdx(position_scene), dFdy(position_scene));

    // Blocklight

    lightmap_gradient = vec2(dFdx(light_levels.x), dFdy(light_levels.x));
    lightmap_dir = pos_gradient * lightmap_gradient;

    if (length_squared(lightmap_gradient) > 1e-12) {
        lightmap_mul.x = (clamp01(dot(normalize(lightmap_dir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(light_levels.x, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmap_mul.x = mix(
            1.0,
            lightmap_mul.x,
            sqr(linear_step(0.03, 0.30, light_levels.x))
        );
    }

    // Skylight

    lightmap_gradient = vec2(dFdx(light_levels.y), dFdy(light_levels.y));
    lightmap_dir = pos_gradient * lightmap_gradient;

    if (length_squared(lightmap_gradient) > 1e-12) {
        lightmap_mul.y = (clamp01(dot(normalize(lightmap_dir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(light_levels.y, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmap_mul.y = mix(
            1.0,
            lightmap_mul.y,
            sqr(linear_step(0.03, 0.30, light_levels.y))
        );
    }

    return lightmap_mul;
}

#endif // INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#endif

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHTING)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#define HANDHELD_LIGHTING_COLORS
#if handheldLightingMode == handheldLightingColored
const vec3 handheld_emitter_light_color[48] = vec3[48](
    vec3(1.00, 1.00, 1.00) * 12.0, // Strong white light
    vec3(1.00, 1.00, 1.00) * 6.0, // Medium white light
    vec3(1.00, 1.00, 1.00) * 1.0, // Weak white light
    vec3(1.00, 0.55, 0.27) * 14.0, // Strong golden light
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.57, 0.30) * 6.0, // Weak golden light
    vec3(1.00, 0.18, 0.10) * 5.0, // Redstone components
    vec3(1.00, 0.38, 0.10) * 7.0, // Lava
    vec3(1.00, 0.45, 0.10) * 9.0, // Medium orange light
    vec3(1.00, 0.63, 0.15) * 4.0, // Brewing stand
    vec3(1.00, 0.57, 0.30) * 12.0, // Medium golden light
    vec3(0.45, 0.73, 1.00) * 6.0, // Soul lights
    vec3(0.45, 0.73, 1.00) * 14.0, // Beacon
    vec3(0.75, 1.00, 0.83) * 3.0, // Sculk
    vec3(0.75, 1.00, 0.83) * 1.0, // End portal frame
    vec3(0.60, 0.10, 1.00) * 2.5, // Pink glow
    vec3(0.75, 1.00, 0.50) * 1.0, // Sea pickle
    vec3(1.00, 0.50, 0.25) * 4.0, // Nether plants
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.65, 0.30) * 8.0, // Ochre froglight
    vec3(0.86, 1.00, 0.44) * 8.0, // Verdant froglight
    vec3(0.75, 0.44, 1.00) * 8.0, // Pearlescent froglight
    vec3(0.60, 0.10, 1.00) * 2.0, // Enchanting table
    vec3(0.75, 0.44, 1.00) * 4.0, // Amethyst cluster
    vec3(0.75, 0.44, 1.00) * 4.0, // Calibrated sculk sensor
    vec3(0.75, 1.00, 0.83) * 6.0, // Active sculk sensor
    vec3(1.00, 0.18, 0.10) * 3.3, // Redstone block
    vec3(1.00, 0.50, 0.25) * 3.0, // Open eyeblossom
    vec3(0.85, 1.3, 1.0) * 3.9, // Copper torch and lanterns
    vec3(1.00, 0.57, 0.30) * 8.0, // Copper Bulbs
    vec3(0.60, 0.10, 1.00) * 12.0, // Nether portal
    vec3(0.0), // End portal
    // Colors for modded light sources (block IDs 64-79)
    vec3(1.00, 1.00, 1.00) * 10.0, // 32 - White       (block 64)
    vec3(0.85, 0.85, 0.85) *  9.0, // 33 - Light Gray  (block 65)
    vec3(0.55, 0.55, 0.55) *  8.0, // 34 - Gray        (block 66)
    vec3(0.20, 0.20, 0.22) *  6.0, // 35 - Black       (block 67)
    vec3(0.55, 0.35, 0.20) *  8.0, // 36 - Brown       (block 68)
    vec3(1.00, 0.10, 0.10) * 10.0, // 37 - Red         (block 69)
    vec3(1.00, 0.45, 0.10) * 10.0, // 38 - Orange      (block 70)
    vec3(1.00, 0.95, 0.20) * 10.0, // 39 - Yellow      (block 71)
    vec3(0.55, 1.00, 0.20) * 10.0, // 40 - Lime        (block 72)
    vec3(0.15, 1.00, 0.20) * 10.0, // 41 - Green       (block 73)
    vec3(0.15, 0.95, 1.00) * 10.0, // 42 - Cyan        (block 74)
    vec3(0.45, 0.75, 1.00) * 10.0, // 43 - Light Blue  (block 75)
    vec3(0.15, 0.30, 1.00) * 10.0, // 44 - Blue        (block 76)
    vec3(0.55, 0.15, 1.00) * 10.0, // 45 - Purple      (block 77)
    vec3(1.00, 0.20, 0.90) * 10.0, // 46 - Magenta     (block 78)
    vec3(1.00, 0.55, 0.85) * 10.0  // 47 - Pink        (block 79)
);
#endif // handheldLightingMode == handheldLightingColored

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 get_handheld_light_color(int held_item_id, int held_item_light_value) {
#if handheldLightingMode == handheldLightingColored
    const int first_emitter_id = 10032;
    const int emitter_count = 48;
    int emitter_index = held_item_id - first_emitter_id;

    if (emitter_index >= 0 && emitter_index < emitter_count) {
        return handheld_emitter_light_color[emitter_index];
    }
#endif

    return (blocklight_color * blocklight_scale * rcp(15.0))
        * held_item_light_value;
}

float get_handheld_light_falloff(vec3 scene_pos, float ao) {
    float falloff = lift(rcp(dot(scene_pos, scene_pos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * 1.00;
}

vec3 get_handheld_lighting(vec3 scene_pos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scene_pos += relativeEyePosition;
#endif

    vec3 light_color = max(
        get_handheld_light_color(heldItemId, heldBlockLightValue),
        get_handheld_light_color(heldItemId2, heldBlockLightValue2)
    );

    float falloff = get_handheld_light_falloff(scene_pos, ao);

    return light_color * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS
#endif

void main() {
    // Clip to taau viewport

    vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);

#if defined taa && defined taau
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    // Overdraw fade

    float dh_fade_start_distance
        = max0(far - dhOverdrawDistance - dhOverdrawFadeLength);
    float dh_fade_end_distance = max0(far - dhOverdrawDistance);
    float view_distance = length(scene_pos);

    float dither = interleaved_gradient_noise(gl_FragCoord.xy, frameCounter);
    float fade = smoothstep(
        dh_fade_start_distance,
        dh_fade_end_distance,
        view_distance
    );

    if (dither > fade) {
        discard;
        return;
    }

    // Encode gbuffer data

    gbuffer_data.x = pack_unorm_2x8(tint.rg);
    gbuffer_data.y
        = pack_unorm_2x8(tint.b, clamp01(((is_water == 1) ? rcp(255.0) : 0.0)));
    gbuffer_data.z = pack_unorm_2x8(encode_unit_vector(normal));
    gbuffer_data.w = pack_unorm_2x8(dither_8bit(light_levels, 0.5));

    if (is_water == 1.0) {
        fragment_color = vec4(0.0);
        return;
    }

    // Space conversions

    float back_depth_mc = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
    float back_depth_dh = texelFetch(dhDepthTex1, ivec2(gl_FragCoord.xy), 0).x;
    bool back_is_dh_terrain = is_lod_terrain(back_depth_mc, back_depth_dh);

    // Prevent water behind terrain from rendering on top of it
    float dh_depth_linear
        = screen_to_view_space_depth(dhProjectionInverse, gl_FragCoord.z);
    float mc_depth_linear
        = screen_to_view_space_depth(gbufferProjectionInverse, back_depth_mc);

    if (mc_depth_linear < dh_depth_linear && back_depth_mc != 1.0) {
        discard;
        return;
    }

    vec3 world_pos = scene_pos + cameraPosition;
    vec3 world_dir = normalize(scene_pos - gbufferModelViewInverse[3].xyz);

    vec3 view_back_pos = back_is_dh_terrain
        ? screen_to_view_space(vec3(coord, back_depth_dh), true, true)
        : screen_to_view_space(vec3(coord, back_depth_mc), true, false);
    vec3 scene_back_pos = view_to_scene_space(view_back_pos);

    float layer_dist = length(
        scene_pos - scene_back_pos
    ); // distance to solid layer along view ray

    // Get material and normal

    Material material;
    fragment_color = tint;

    vec2 adjusted_light_levels = light_levels;
    material = material_from(
        fragment_color.rgb,
        0u,
        world_pos,
        normal,
        adjusted_light_levels
    );

    // Shadows

#ifndef NO_NORMAL
    float NoL = dot(normal, light_dir);
#else
    float NoL = 1.0;
#endif
    float NoV = clamp01(dot(normal, -world_dir));
    float LoV = dot(light_dir, -world_dir);
    float halfway_norm = inversesqrt(2.0 * LoV + 2.0);
    float NoH = (NoL + NoV) * halfway_norm;
    float LoH = LoV * halfway_norm + halfway_norm;

    vec3 shadows = vec3(pow8(light_levels.y));
#define sss_depth 0.0
#define shadow_distance_fade 0.0

#ifdef cloudShadows
    float cloud_shadows = get_cloud_shadows(colortex8, scene_pos);
    shadows *= cloud_shadows;
#endif

    fragment_color.rgb = get_diffuse_lighting(
        material,
        scene_pos,
        normal,
        normal,
        shadows,
        light_levels,
        1.0,
        0.0,
        sss_depth,
#ifdef cloudShadows
        cloud_shadows,
#endif
        shadow_distance_fade,
        NoL,
        NoV,
        NoH,
        LoV,
        ambient_color
    );

    // Apply fog

    vec4 fog = common_fog(length(scene_pos), false, scene_pos);
    fragment_color.rgb = fragment_color.rgb * fog.a + fog.rgb;

    fragment_color.a *= border_fog(scene_pos, world_dir);
}
