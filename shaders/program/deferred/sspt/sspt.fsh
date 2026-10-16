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

layout(location = 0) out vec4 indirect;      // colortex17
layout(location = 1) out vec4 filterData;  // colortex19

/* RENDERTARGETS: 17,19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex4; // sky map (skylight bounce sampling)
uniform sampler2D colortex6; // selected AO for SSPT contact-shadow finishing
uniform sampler2D colortex14; // AO history depth for depth-aware AO upscale

uniform sampler2D depthtex1; // geometry depth (non-DH path)

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#if defined shadow && !defined WORLD_NETHER
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef shadowColor
uniform sampler2D shadowcolor0;
#endif

uniform vec3 sun_dir;
uniform vec3 moon_dir;
uniform float sunAngle;
uniform float time_sunrise;
uniform float time_sunset;
uniform float moon_phase_brightness;
#endif

// Shadow matrices stay declared even where no shadow pass runs: the
// cloud-shadow helper chain references them, and unused uniforms are free.
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

#if defined WORLD_OVERWORLD && defined cloudShadows
uniform sampler2D colortex8; // cloud shadow map
#endif

// Declared for the atmosphere/cloud-shadow include chain
uniform float rainStrength;
uniform float desert_sandstorm;
uniform vec3 light_dir;
uniform float eyeAltitude;
uniform int moonPhase;

// ------------
//   Includes
// ------------

#define TRACE_DEPTH combined_depth_tex
#define TRACE_PROJ combined_projection_matrix
#define TRACE_PROJ_INV combined_projection_matrix_inverse

#include "/lib/misc/lodModSupport.glsl"
#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT


#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#define LUSTER_INCLUDE_HANDHELD_LIGHTING
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

#undef LUSTER_INCLUDE_HANDHELD_LIGHTING
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
#include "/lib/light/distortion.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/material/material.glsl"
#include "/lib/sky/projection.glsl"


// Resolution bookkeeping


// ----------------------------------------------------------------------------
/* DITHER */
// ----------------------------------------------------------------------------
// (hash22 below is the only dither hash used.)

#define HASHSCALE3 vec3(0.1031, 0.1030, 0.0973)
vec2 hash22(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ----------------------------------------------------------------------------
/* COSINE HEMISPHERE SAMPLING */
// ----------------------------------------------------------------------------

vec3 genUnitVector(vec2 p) {
    p.x *= tau; p.y = p.y * 2.0 - 1.0;
    return vec3(cos(p.x) * sqrt(1.0 - p.y * p.y),
                sin(p.x) * sqrt(1.0 - p.y * p.y),
                p.y);
}

// Lambertian BRDF sampling without a tangent frame (Malley's method).

// http://www.amietia.com/lambertnotangent.html
vec3 cosineVector(vec3 vector, vec2 xy) {
    vec3 cosine_vector = vector + genUnitVector(xy);
    float len_sq = dot(cosine_vector, cosine_vector);
    return len_sq > 0.0 ? cosine_vector * inversesqrt(len_sq) : vector;
}

// ----------------------------------------------------------------------------
/* SCREENSPACE RAYTRACER */


vec3 rayHit(vec3 screen_pos) {
    float depth_sample = texelFetch(
        TRACE_DEPTH,
        ivec2(screen_pos.xy * view_res * taau_render_scale),
        0
    ).x;

    if (depth_sample >= screen_pos.z) return vec3(1.1); // no occlusion yet

    float hit_view_depth = screen_to_view_space_depth(TRACE_PROJ_INV, depth_sample);
    float ray_view_depth = screen_to_view_space_depth(TRACE_PROJ_INV, screen_pos.z);

    float dist = abs(hit_view_depth - ray_view_depth) / max(abs(ray_view_depth), 1e-6);

    return dist <= 0.1 ? vec3(screen_pos.xy, depth_sample) : vec3(1.1);
}

#ifdef ssptFullRangeRT
//  Works fully in screenspace. Potentially every pixel can be hit. Needs a
//  lot more iterations for results of similar quality.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint max_steps = 16;

    float ray_length = ((position.z + direction.z * far * sqrt(3.0)) > -sqrt(3.0) * near)
                      ? (-sqrt(3.0) * near - position.z) / direction.z : far * sqrt(3.0);

    vec3 screen_position = view_to_screen_space(TRACE_PROJ, position, true);
    vec3 end_position = position + direction * ray_length;
    vec3 end_screen_position = view_to_screen_space(TRACE_PROJ, end_position, true);

    vec3 screen_direction = normalize(end_screen_position - screen_position);
        screen_direction.xy = normalize(screen_direction.xy);

    vec3 max_length = (step(0.0, screen_direction) - screen_position) / screen_direction;
    float step_mult = min_of(max_length);
    vec3 screen_vector = screen_direction * step_mult / float(max_steps);

    vec3 screen_pos = screen_position
        + screen_direction * max_of(view_pixel_size * pi);

    if (clamp01(screen_pos.xy) == screen_pos.xy) {
        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;
    }

        screen_pos += screen_vector * noise;

    for (uint i = 0; i < max_steps; ++i) {
        if (clamp01(screen_pos.xy) != screen_pos.xy) break;

        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;

        screen_pos += screen_vector;
    }

    return vec3(1.1);
}
#else
//  Short range variant (default). Traces a bounded view-space
//  distance and rescales the step vector so the ray ends on-screen.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint max_steps = 10;
    const float step_size = tau / float(max_steps);

    vec3 step_vector = direction * step_size;

    vec3 end_position = position + step_vector * float(max_steps);
    vec3 end_screen_position = view_to_screen_space(TRACE_PROJ, end_position, true);

    vec2 max_pos_xy = max(abs(end_screen_position.xy * 2.0 - 1.0), vec2(1.0));
    float step_mult = min_of(rcp(max_pos_xy));
        step_vector *= step_mult;

    // closest texel iteration
    vec3 sample_pos = position;

        sample_pos += step_vector / 6.0;
    vec3 screen_pos = view_to_screen_space(TRACE_PROJ, sample_pos, true);

    if (clamp01(screen_pos.xy) == screen_pos.xy) {
        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;
    }

        sample_pos += step_vector * noise;

    for (uint i = 0; i < max_steps; ++i) {
        vec3 screen_pos = view_to_screen_space(TRACE_PROJ, sample_pos, true);
            sample_pos += step_vector;
        if (clamp01(screen_pos.xy) != screen_pos.xy) break;

        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;
    }

    return vec3(1.1);
}
#endif

// ----------------------------------------------------------------------------
/* HIT SURFACE DATA — Luster-main gbuffer unpack (kept for the bounce path) */


struct HitData {
    vec3 albedo;
    vec3 scene_normal;
    vec2 light_levels;
    uint mask;
};

HitData unpackHit(vec4 gbuffer_data) {
    HitData hit;

    hit.albedo = vec3(
        unpack_unorm_2x8(gbuffer_data.x),
        unpack_unorm_2x8(gbuffer_data.y).x
    );
    hit.mask = uint(255.0 * unpack_unorm_2x8(gbuffer_data.y).y);
    hit.scene_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data.z));
    hit.light_levels = unpack_unorm_2x8(gbuffer_data.w);

    return hit;
}

// ----------------------------------------------------------------------------
/* HIT SURFACE EMISSION — material path */


vec3 hitEmission(vec4 hit_data_0, ivec2 hit_texel, vec3 hit_view_pos) {
    vec3 hit_albedo = vec3(
        unpack_unorm_2x8(hit_data_0.x),
        unpack_unorm_2x8(hit_data_0.y).x
    );
    uint hit_mask = uint(255.0 * unpack_unorm_2x8(hit_data_0.y).y);
    vec3 hit_scene_normal = decode_unit_vector(unpack_unorm_2x8(hit_data_0.z));
    vec2 hit_light_levels = unpack_unorm_2x8(hit_data_0.w);

    // world position for position-dependent hardcoded emission
    vec3 hit_world_pos = view_to_scene_space(hit_view_pos) + cameraPosition;

    Material hit_material = material_from(
        hit_albedo,
        hit_mask,
        hit_world_pos,
        hit_scene_normal,
        hit_light_levels
    );

    // Raw hardcoded source (populated by material_from() only when
    // hardcodedEmission is on; otherwise zero).
    vec3 hardcoded_raw = hit_material.emission;

#if ssptEmissionMode != 0
    // Raw resource-pack map source (same channel decoding as
    // decode_emission()'s map path, pre-curve).
    vec4 hit_specular_map = texelFetch(colortex2, hit_texel, 0);
    vec4 sspt_map = vec4(
        unpack_unorm_2x8(hit_specular_map.z),
        unpack_unorm_2x8(hit_specular_map.w)
    );
    vec3 map_raw;
    #if textureFormat == textureFormatLab
    float has_emission_map = step(sspt_map.a, 254.5 / 255.0);
    float emission_value = (sspt_map.a * 255.0 - 1.0) / 254.0;
    // Exclusive: unmapped texels emit nothing (no hardcoded fallback).
    map_raw = hit_material.albedo * emission_value * has_emission_map;
    #else
    float has_emission_map = step(0.5 / 255.0, sspt_map.b);
    // Exclusive: unmapped texels emit nothing (no hardcoded fallback).
    map_raw = hit_material.albedo * sspt_map.b * has_emission_map;
    #endif
#endif

    // SSPT-only source selection. Direct lighting is untouched.
    #if ssptEmissionMode == 2
    vec3 emission_raw = map_raw;
    #elif ssptEmissionMode == 1
    // Brighter source wins (luminance comparison, whole vector kept so
    // hue is preserved instead of mixing channels).
    float hardcoded_luma = dot(max0(hardcoded_raw), luminance_weights);
    float map_luma = dot(max0(map_raw), luminance_weights);
    vec3 emission_raw = map_luma > hardcoded_luma ? map_raw : hardcoded_raw;
    #else
    vec3 emission_raw = hardcoded_raw;
    #endif

    // Same global shaping as the primary pass so bounced and directly
    // viewed emitters agree on response.
    hit_material.emission = pow(
        max(emission_raw, vec3(0.0)),
        vec3(globalEmissionCurve)
    ) * globalEmissionIntensity;


    return hit_material.emission * hit_material.albedo
        * emission_scale * ssptIntensity;
}

// ----------------------------------------------------------------------------
/* HIT DIRECT LIGHT — sun/moon + handheld bounce */

//  Shadowed sun/moon light at the traced hit, tinted by the hit albedo (one


//  falloff/color of the primary pass. Skylight stays out (owned by the
//  traced sky / bent-cone ambient, never by the bounce itself).


#if defined shadow && !defined WORLD_NETHER
#define DIRECT_SUN_BOUNCE 1
#endif
#ifdef handheldLighting
#define DIRECT_HANDHELD_BOUNCE 1
#endif


#define DIRECT_SKY_BOUNCE 1

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE


#ifdef DIRECT_SUN_BOUNCE
vec3 sunRadiance() {
    float blue_hour = linear_step(0.05, 1.0, exp(-190.0 * sqr(sun_dir.y + 0.09604)));
    float exposure = 7.0 * sunI
                   * (1.0 + 0.5 * (time_sunset + time_sunrise) + 40.0 * blue_hour);

    vec3 tint = mix(
        vec3(1.0),
        vec3(1.05, 0.84, 0.93) * 1.2,
        sqr(pulse(sun_dir.y, 0.17, 0.40))
    );
    tint *= mix(vec3(1.0), vec3(0.95, 0.80, 1.0), blue_hour);

    vec3 user_tint = mix(
        from_display(vec3(sunNr, sunNg, sunNb)),
        from_display(vec3(sunMr, sunMg, sunMb)),
        time_sunrise
    );
    user_tint = mix(user_tint, from_display(vec3(sunEr, sunEg, sunEb)), time_sunset);

    return exposure * tint * user_tint;
}

// Moon radiance. Moon-phase albedo influence is intentionally not applied:
// the bounce uses the raw moon color.
vec3 moonRadiance() {
    float night_boost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sun_dir.y, 0.1)));
    float exposure = 0.66 * moonI * moon_phase_brightness * night_boost;
    return exposure * from_display(vec3(moonR, moonG, moonB));
}
#endif // DIRECT_SUN_BOUNCE

vec3 hitDirectLight(HitData hit, vec3 hit_view_pos) {
    vec3 hit_scene_pos = view_to_scene_space(hit_view_pos);
    vec3 sun_moon_direct = vec3(0.0);
    vec3 indirect_direct = vec3(0.0);

#ifdef DIRECT_SUN_BOUNCE


    vec3 light_dir_world = sunAngle < 0.5 ? sun_dir : moon_dir;

    float NoL = dot(hit.scene_normal, light_dir_world);
    if (NoL > 0.0) {
        vec3 bias = get_shadow_bias(hit_scene_pos, hit.scene_normal, NoL, hit.light_levels.y);
        vec3 shadow_view_pos = transform(shadowModelView, hit_scene_pos + bias);
        vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);
        vec3 shadow_coords = distort_shadow_space(shadow_clip_pos) * 0.5 + 0.5;

        bool outside_shadow_map = any(lessThan(shadow_coords, vec3(0.0)))
                               || any(greaterThan(shadow_coords, vec3(1.0)));

        float visibility = outside_shadow_map ? 1.0 : texture(shadowtex1, shadow_coords);
        if (visibility > 0.0) {
            vec3 radiance = sunAngle < 0.5 ? sunRadiance() : moonRadiance();
            sun_moon_direct = radiance * (visibility * NoL);

#ifdef shadowColor
            if (!outside_shadow_map) {
                // Sunlight passing through stained glass picks up the glass tint.
                ivec2 shadow_texel = ivec2(shadow_coords.xy * vec2(textureSize(shadowtex0, 0)));
                float blocker_depth = texelFetch(shadowtex0, shadow_texel, 0).x;
                vec3 transmission = texelFetch(shadowcolor0, shadow_texel, 0).rgb;
                sun_moon_direct *= mix(vec3(1.0), 4.0 * transmission, step(blocker_depth, shadow_coords.z));
            }
#endif

#if defined WORLD_OVERWORLD && defined cloudShadows
            sun_moon_direct *= get_cloud_shadows(colortex8, hit_scene_pos);
#endif
        }
    }
#endif // DIRECT_SUN_BOUNCE

#ifdef DIRECT_SKY_BOUNCE


    vec3 sky_radiance = texture(colortex4, project_sky(hit.scene_normal)).rgb;
    indirect_direct += sky_radiance * hit.light_levels.y;
#endif // DIRECT_SKY_BOUNCE

#ifdef DIRECT_HANDHELD_BOUNCE


    indirect_direct += get_handheld_lighting(hit_scene_pos, 1.0);
#endif


    return hit.albedo * (sun_moon_direct + indirect_direct * ssptIntensity);
}

#endif // defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE

// ----------------------------------------------------------------------------
/* HAMMON DIFFUSE BRDF (Kappa-style lib; includes fresnelSchlickInverse) */
// ----------------------------------------------------------------------------

#include "/lib/brdf/hammon.glsl"


// INDIRECT TRACER


//  and is tinted by the hit albedo inside hitDirectLight. Multibounce


vec3 traceIndirect(
    vec3 view_pos,
    vec3 scene_normal,
    vec2 dither,
    bool hand,
    float contact_ao,
    out bool geometry_hit
) {
    vec3 view_normal = mat3(gbufferModelView) * scene_normal;

    vec3 emission = vec3(0.0);
    geometry_hit = false;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    vec3 bounce = vec3(0.0);
    // Candidate count for bounce normalization: bounce averages over
    // candidates like emission does, not over hits.
    float bounce_samples = 0.0;
#endif

    // R2-sequence constants: 1/rho and 1/rho^2 (plastic constant)
    const float a1 = 1.0 / 1.3247179572447460;
    const float a2 = a1 * a1;

    #if ssptBounces <= 1

    /* ------ SINGLE BOUNCE ------ */
    //  Every candidate is a cosine-lobe ray, stratified over pixel +
    //  frame + candidate index so temporal accumulation blends them.

    vec2 quasirandom_curr = 0.5 + fract(vec2(a1, a2) * float(frameCounter) + 0.5);

    vec2 noise_curr = hash22(gl_FragCoord.xy + float(frameCounter));

    for (uint i = 0; i < ssptSPP; ++i) {
        ++quasirandom_curr;
        noise_curr += hash22(
            vec2(gl_FragCoord.xy + vec2(cos(quasirandom_curr.x), sin(quasirandom_curr.y)))
        );

        vec2 vector_xy = fract(sqrt(2.0) * quasirandom_curr + noise_curr);


        bounce_samples += 1.0;

        vec3 ray_direction = cosineVector(scene_normal, vector_xy);
            ray_direction = normalize(mat3(gbufferModelView) * ray_direction);

        if (dot(view_normal, ray_direction) < 0.0) ray_direction = -ray_direction;

        float brdf = brdfWeight(view_normal, -normalize(view_pos), ray_direction);

        vec3 hit_position = screenspaceRT(view_pos, ray_direction, dither.y);

        if (hit_position.z < 1.0) {
            geometry_hit = true;
            ivec2 hit_texel = ivec2(hit_position.xy * view_res * taau_render_scale);
            vec4 hit_data_0 = texelFetch(colortex1, hit_texel, 0);

            vec3 hit_view_pos = screen_to_view_space(TRACE_PROJ_INV, hit_position, true);

            // Cubic emission distance falloff.
            float emission_falloff = 1.0 - linear_step(
                ssptEmissionDistance * rcp_pi,
                ssptEmissionDistance,
                distance(hit_view_pos, view_pos)
            );
                emission_falloff = cube(emission_falloff);

            emission += hitEmission(hit_data_0, hit_texel, hit_view_pos)
                      * emission_falloff * brdf;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
            // Direct-light bounce: no distance falloff, BRDF-weighted.
            // (Counted per cosine candidate above, not per hit.)
            bounce += hitDirectLight(unpackHit(hit_data_0), hit_view_pos) * brdf;
#endif
        }
    }

    #else

    /* ------ MULTIBOUNCE (ssptBounces > 1) ------ */


    //  Sky escapes end the chain.

    for (uint i = 0; i < ssptSPP; ++i) {
        int frame_counter_new = frameCounter + int(i) * 31;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
        // Multibounce samples are all cosine-lobe: count every sample so
        // the shared normalization below reproduces the old average.
        bounce_samples += 1.0;
#endif

        vec2 quasirandom_curr = 0.5 + fract(vec2(a1, a2) * float(frame_counter_new) + 0.5);

        vec2 noise_curr = hash22(gl_FragCoord.xy + float(frame_counter_new));

        vec3 contribution = vec3(1.0);

        vec3 ray_direction = -normalize(view_pos);

        vec3 hit_normal = view_normal;
        vec3 hit_normal_scene = scene_normal;

        for (uint n = 0; n < ssptBounces; ++n) {
            ++quasirandom_curr;
            noise_curr += hash22(
                vec2(gl_FragCoord.xy + vec2(cos(quasirandom_curr.x), sin(quasirandom_curr.y)))
            );

            vec2 vector_xy = fract(sqrt(2.0) * quasirandom_curr + noise_curr);

            vec3 old_direction = ray_direction;

                ray_direction = cosineVector(hit_normal_scene, vector_xy);
                ray_direction = normalize(mat3(gbufferModelView) * ray_direction);

            if (dot(hit_normal, ray_direction) < 0.0) ray_direction = -ray_direction;

            vec3 hit_position = screenspaceRT(view_pos, ray_direction, dither.y);

            float brdf = brdfWeight(hit_normal, -old_direction, ray_direction);
                contribution *= brdf;

            if (hit_position.z < 1.0) {
                geometry_hit = true;
                ivec2 hit_texel = ivec2(hit_position.xy * view_res * taau_render_scale);
                vec4 hit_data_0 = texelFetch(colortex1, hit_texel, 0);

                vec3 hit_albedo = vec3(
                    unpack_unorm_2x8(hit_data_0.x),
                    unpack_unorm_2x8(hit_data_0.y).x
                );
                hit_normal_scene = decode_unit_vector(unpack_unorm_2x8(hit_data_0.z));
                hit_normal = mat3(gbufferModelView) * hit_normal_scene;

                vec3 hit_view_pos = screen_to_view_space(TRACE_PROJ_INV, hit_position, true);

                float emission_falloff = 1.0 - linear_step(
                    ssptEmissionDistance * rcp_pi,
                    ssptEmissionDistance,
                    distance(hit_view_pos, view_pos)
                );
                    emission_falloff = cube(emission_falloff);

                emission += hitEmission(hit_data_0, hit_texel, hit_view_pos)
                          * emission_falloff * contribution;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
                // Direct-light bounce on every path vertex.
                bounce += hitDirectLight(unpackHit(hit_data_0), hit_view_pos)
                        * contribution;
#endif

                contribution *= hit_albedo; // colored bleed into deeper bounces
            } else {
                // miss: sky escape contributes no emission; stop the chain
                break;
            }
        }
    }

    #endif

    emission /= float(ssptSPP);


    float emission_luma = dot(max0(emission), luminance_weights);
    emission *= rcp(1.0 + emission_luma * rcp(8.0));
    float compressed_luma = dot(max0(emission), luminance_weights);
    emission = mix(vec3(compressed_luma), emission, 1.4);

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    // Bounce averages over candidates, matching emission's normalization.
    if (bounce_samples > 0.5) bounce /= bounce_samples;
    // Finish traced bounced lighting with the selected screen-space AO.
    // Keep material emission unoccluded so emitters do not lose radiance.
    bounce *= clamp01(contact_ao);
#endif

    emission *= float(!hand); // hand geometry gets no emission or sky
    // (hand keeps its direct-light bounce)


#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    return emission + bounce;
#else
    return emission;
#endif
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT
#include "/lib/util/encoding.glsl"
#include "/lib/util/spaceConversion.glsl"

// Depth-aware 2x2 upscale of the quarter-res AO buffer (colortex6.x with
// colortex14 depth weights, same 10.0 scale as the shading pass bilateral
// resolve). Works at any SSPT buffer resolution set by indirectResReduction
// and for both DSSAO (scalar) and DGTAO (scalar visibility; bent normal stays
// in the shading pass for directional sky). Bilinear texture() would bleed AO
// across depth discontinuities and leak/halo the bounce finishing.
float fetch_sspt_contact_ao(vec2 uv, float lin_z) {
#if shaderAo == shaderAoNone
    return 1.0;
#else
    vec2 ao_size = vec2(textureSize(colortex6, 0));
    vec2 ao_pos = uv * ao_size - 0.5;
    ivec2 base = ivec2(floor(ao_pos));
    vec2 f = fract(ao_pos);

    vec4 ao_taps;
    vec4 ao_depths;
    ao_taps.x = texelFetch(colortex6, clamp(base, ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_taps.y = texelFetch(colortex6, clamp(base + ivec2(1, 0), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_taps.z = texelFetch(colortex6, clamp(base + ivec2(0, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_taps.w = texelFetch(colortex6, clamp(base + ivec2(1, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;

    ao_depths.x = texelFetch(colortex14, clamp(base, ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_depths.y = texelFetch(colortex14, clamp(base + ivec2(1, 0), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_depths.z = texelFetch(colortex14, clamp(base + ivec2(0, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;
    ao_depths.w = texelFetch(colortex14, clamp(base + ivec2(1, 1), ivec2(0), ivec2(ao_size) - 1), 0).x;

    vec4 w;
    w.x = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.x) - lin_z));
    w.y = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.y) - lin_z));
    w.z = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.z) - lin_z));
    w.w = exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - ao_depths.w) - lin_z));

    w.x *= (1.0 - f.x) * (1.0 - f.y);
    w.y *= f.x * (1.0 - f.y);
    w.z *= (1.0 - f.x) * f.y;
    w.w *= f.x * f.y;

    float w_sum = w.x + w.y + w.z + w.w;
    if (w_sum <= 1e-6) {
        return clamp01(dot(ao_taps, vec4(0.25)));
    }
    return clamp01(dot(ao_taps, w) / w_sum);
#endif
}

// ------------
//   Main
// ------------

void main() {
    // This pass renders at the selected SSPT buffer resolution; gl_FragCoord is
    // in buffer texels while uv spans the whole screen.
    ivec2 gbuffer_texel = ivec2(uv * view_res * taau_render_scale);

    // initialize outputs before any early return (sky = vec4(0.0),
    // filter gbuffer = (0,0,1)*0.5+0.5 packed + depth 1)
    indirect = vec4(0.0);
    filterData = vec4(0.5, 0.5, 1.0, 1.0);

    if (clamp(gbuffer_texel, ivec2(0), ivec2(view_res) - 1) != gbuffer_texel) {
        return;
    }

    float depth = texelFetch(combined_depth_tex, gbuffer_texel, 0).x;

    if (depth >= 1.0) {
        return;
    }

    bool is_hand = depth < hand_depth;

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );

    // ---- gbuffer unpack (same packing as d4_deferred_shading) ----

    vec4 gbuffer_data_0 = texelFetch(colortex1, gbuffer_texel, 0);

    vec3 flat_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data_0.z));
    vec3 view_normal = mat3(gbufferModelView) * flat_normal;

    // ---- filter gbuffer side-data ----


    filterData = vec4(
        view_normal * 0.5 + 0.5,
        sqrt(clamp01(-view_pos.z / far))
    );

    // ---- trace ----
    // Hash dithers, consumed as the screenspace-RT march noise by traceIndirect.

    vec2 dither = vec2(
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b,
        texelFetch(noisetex, (ivec2(gl_FragCoord.xy) + 249) & 511, 0).b
    );

    // Emission + sun/moon + handheld bounce.


    // AO is already temporally stabilized by deferred3. Its selected scalar
    // visibility is applied to traced bounce lighting, not to emission.
    // DSSAO and DGTAO share this scalar finishing path; DGTAO's bent normal
    // additionally steers directional sky in the shading pass.
    float lin_z = screen_to_view_space_depth(
        combined_projection_matrix_inverse,
        depth
    );
    float contact_ao = is_hand ? 1.0 : fetch_sspt_contact_ao(uv, lin_z);

    bool geometry_hit;
    vec3 indirect_light = traceIndirect(
        view_pos,
        flat_normal,
        dither,
        is_hand,
        contact_ao,
        geometry_hit
    );


    indirect = vec4(indirect_light, float(geometry_hit));
}
