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

#ifdef fogSmoothing
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"

float luminance(vec3 c) {
    return dot(c, luminance_weights);
}

vec3 fog_spatial_filter(
    sampler2D scattering_tex,
    vec2 uv,
    vec2 pixel_size,
    int radius
) {
    vec3 center = texture(scattering_tex, uv).rgb;
    vec3 sum = center;
    float w_sum = 1.0;

    // Standard three-sigma rule: sigma sized so the kernel's edge taps carry
    // negligible weight (~1%) rather than being cut off abruptly by the box
    float sigma = max(float(radius), 1.0) / 3.0;
    float inv_two_sigma_sq = 0.5 / (sigma * sigma);

    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x == 0 && y == 0) continue;

            vec2 offset = vec2(float(x), float(y));
            vec2 sample_uv = uv + offset * pixel_size;
            if (clamp01(sample_uv) != sample_uv) continue;

            vec3 sample_value = texture(scattering_tex, sample_uv).rgb;
            float delta = abs(luminance(sample_value) - luminance(center));

            float spatial_weight = exp(-dot(offset, offset) * inv_two_sigma_sq);
            float range_weight = exp(-delta * 8.0);
            float weight = spatial_weight * range_weight;

            sum += sample_value * weight;
            w_sum += weight;
        }
    }

    return sum / max(w_sum, eps);
}
#endif

layout(location = 0) out vec3 fragment_color;

/* RENDERTARGETS: 0 */

#ifdef bloomyFog
layout(location = 1) out float bloomy_fog;

/* RENDERTARGETS: 0,3 */
#endif

in vec2 uv;

flat in vec3 ambient_color;
flat in vec3 light_color;

#ifdef WORLD_OVERWORLD
#include "/lib/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0; // scene color
uniform sampler2D colortex3; // refraction data
uniform sampler2D colortex4; // sky map
uniform sampler2D colortex5; // scene history (used by SSR reflection reprojection)
uniform sampler2D colortex6; // volumetric fog scattering
uniform sampler2D colortex7; // volumetric fog transmittance
uniform sampler2D colortex11; // clouds history
uniform sampler2D colortex12; // clouds data
uniform sampler2D colortex13; // rendered translucent layer

#ifdef DISTANT_HORIZONS
// colortex1 gbuffer fetch for the DH water path below.
uniform sampler2D colortex1;
#endif

#ifdef VOXY
uniform sampler2D colortex16; // distant water gbuffer 0
#endif

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

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
uniform float eyeAltitude;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

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

// ------------
//   Includes
// ------------

#define SSRT_LOD
#define TEMPORAL_REPROJECTION

#include "/lib/fog/simpleFog.glsl"
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

// Cloud shadow map for the analytic-fog gates below (p0 renders it
// unconditionally, so this is valid in every config, mods or not).
uniform sampler2D colortex8;
#if !defined INCLUDE_MISC_LIGHTNING_FLASH
#define INCLUDE_MISC_LIGHTNING_FLASH

#ifdef lightningFlash
uniform float lightning_flash_iris;
#define LIGHTNING_FLASH_UNIFORM lightning_flash_iris
#else
#define LIGHTNING_FLASH_UNIFORM 0.0
#endif

const float lightning_flash_intensity = 4.0;

#endif // INCLUDE_MISC_LIGHTNING_FLASH
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/sampling.glsl"
#include "/lib/util/spaceConversion.glsl"

// Inlined from /lib/misc/refraction.glsl (single consumer: apply_refraction
// below). Decodes the packed tangent-space refraction normal written by the
// translucent gbuffer pass.
vec2 refraction_normal_from(vec4 refraction_data) {
    return vec2(
        unsplit_2x8(refraction_data.xy) * 2.0 - 1.0,
        unsplit_2x8(refraction_data.zw) * 2.0 - 1.0
    );
}

float refraction_amount(float view_distance, float layer_dist, bool eye_underwater) {
    float thickness_scale = rcp(max(view_distance, 1.0)) * min(layer_dist, 8.0);
    float distance_falloff_rate = eye_underwater ? 1.0 : 0.1;
    float distance_falloff = rcp(1.0 + pow(max(view_distance, 0.0), 0.8) * distance_falloff_rate);
    return thickness_scale * distance_falloff * (0.1 * refractionIntensity);
}

// Rejects the offset (falls back to the un-refracted uv) if the refracted
// sample would land in front of the translucent surface itself.
vec2 reject_if_in_front(vec2 refracted_uv, vec2 uv, float front_depth) {
    float depth_refracted = texture(depthtex1, refracted_uv).x;
    return mix(refracted_uv, uv, float(depth_refracted < front_depth));
}

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

#if refraction != refractionOff
    if (is_translucent && refraction_data != vec4(0.0)) {
        vec2 normal_tangent = refraction_normal_from(refraction_data);
        float amount = refraction_amount(view_distance, layer_dist, eye_underwater);

        refracted_uv = reject_if_in_front(uv + normal_tangent * amount, uv, front_depth);
        refracted_uv_out = refracted_uv;

        vec2 dispersion = clamp(normal_tangent, -0.2, 0.2) * 5.0
            * (0.035 * refractionDispersionIntensity);

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

#ifdef WORLD_OVERWORLD
#include "/lib/fog/overworld/analytic.glsl"
#include "/lib/sky/clouds/sampling.glsl"

#ifdef LOD_MOD_ACTIVE
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
#endif

#ifdef LOD_MOD_ACTIVE
#if !defined INCLUDE_MISC_DISTANT_WATER
#define INCLUDE_MISC_DISTANT_WATER

#include "/lib/brdf/specular.glsl"
#if !defined INCLUDE_POST_PURKINJE_SHIFT
#define INCLUDE_POST_PURKINJE_SHIFT

// Purkinje effect: mesopic shift toward rod (scotopic) peak sensitivity.
// https://en.wikipedia.org/wiki/Purkinje_effect
vec3 purkinje_shift(vec3 rgb, vec2 light_levels) {
#if !(defined purkinjeShift && defined WORLD_OVERWORLD)
    return rgb;
#else
    float purkinje_intensity = 0.05 * purkinjeShiftIntensity;
    purkinje_intensity = purkinje_intensity
        - purkinje_intensity * smoothstep(-0.12, -0.06, sun_dir.y)
            * light_levels.y; // No purkinje shift in daylight
    purkinje_intensity *= clamp01(
        1.0 - light_levels.x
    ); // Reduce purkinje intensity in blocklight
    purkinje_intensity *= clamp01(
        0.3 + 0.7 * cube(max(light_levels.y, eye_skylight))
    ); // Reduce purkinje intensity underground

    if (purkinje_intensity < eps) {
        return rgb;
    }

    const vec3 purkinje_tint = vec3(
        purkinjeShiftR,
        purkinjeShiftG,
        purkinjeShiftB
    ) * rec709_to_working_color;
    const vec3 rod_response
        = vec3(7.15e-5, 4.81e-1, 3.28e-1) * rec709_to_working_color;

    vec3 xyz = rgb * working_to_xyz_color;

    vec3 scotopic_luminance
        = xyz * (1.33 * (1.0 + (xyz.y + xyz.z) / xyz.x) - 1.68);

    float purkinje = dot(rod_response, scotopic_luminance * xyz_to_working_color);

    rgb = mix(
        rgb,
        purkinje * purkinje_tint,
        exp2(-rcp(purkinje_intensity) * purkinje)
    );

    return max0(rgb);
#endif
}

#endif // INCLUDE_POST_PURKINJE_SHIFT
#include "/lib/material/water.glsl"

vec4 draw_distant_water(
    vec3 position_screen,
    vec3 position_view,
    vec3 position_world,
    vec3 direction_world,
    vec3 flat_normal,
    vec3 tint,
    vec2 light_levels,
    float view_distance,
    float layer_distance
) {
    vec4 water_color = vec4(0.0);

    // Use hardcoded TBN matrix pointing upwards that is the same for LoD water
    // and regular water
    const mat3 tbn
        = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0));

    // Common fog

    float fog_visibility = common_fog(view_distance, false, position_world - cameraPosition).a;

    // Cloud shadows

#if defined WORLD_OVERWORLD && defined cloudShadows
    float cloud_shadows
        = get_cloud_shadows(colortex8, position_world - cameraPosition);
#else
    const float cloud_shadows = 1.0;
#endif

    // Water absorption approx (must match gbuffers_water)

#ifdef DISTANT_HORIZONS
    tint.rgb *= 1.45;
#endif

    vec3 biome_water_color = srgb_eotf_inv(tint.rgb) * rec709_to_working_color;
    vec3 absorption_coeff = biome_water_coeff(biome_water_color);

    mat2x3 water_fog = water_fog_simple(
        light_color * cloud_shadows,
        ambient_color,
        absorption_coeff,
        light_levels,
        layer_distance,
        dot(light_dir, direction_world),
        0.0
    );

    float brightness_control = 1.0 - exp(-0.33 * layer_distance);
    brightness_control
        = (1.0 - light_levels.y) + brightness_control * light_levels.y;

    water_color.rgb = water_fog[0] * (1.0 + 6.0 * sqr(water_fog[1]))
        * brightness_control * fog_visibility;
    water_color.a = 1.0 - water_fog[1].x;

    // Get water wave normal

    // Account for 1/8 height difference between water and terrain
    vec3 water_surface_pos = position_world - vec3(0.0, rcp(8.0), 0.0);

    vec3 normal = flat_normal;

#ifdef waterWaves
    if (flat_normal.y > eps) {
        vec2 coord = -(water_surface_pos * tbn).xy;
        normal = tbn
            * get_water_normal(
                     water_surface_pos,
                     flat_normal,
                     coord,
                     vec2(0.0),
                     light_levels.y,
                     false
            );
    }
#endif

    // Specular highlight

#if (defined WORLD_OVERWORLD || defined WORLD_END)
    float NoL = dot(normal, light_dir);
    float NoV = clamp01(dot(normal, -direction_world));
    float LoV = dot(light_dir, -direction_world);
    float halfway_norm = inversesqrt(2.0 * LoV + 2.0);
    float NoH = (NoL + NoV) * halfway_norm;
    float LoH = LoV * halfway_norm + halfway_norm;

    water_color.rgb
        += get_specular_highlight(water_material, NoL, NoV, NoH, LoV, LoH)
        * light_color * cloud_shadows * fog_visibility;
#endif

    // Specular reflections

#if defined environmentReflections || defined skyReflections
    mat3 new_tbn = get_tbn_matrix(normal);
    water_color.rgb
        += get_specular_reflections(
               water_material,
               new_tbn,
               position_screen,
               position_view,
               position_world,
               normal,
               flat_normal,
               direction_world,
               direction_world * new_tbn,
               light_levels.y,
               true
           )
        * fog_visibility;
#endif

    // Purkinje shift

    water_color.rgb = purkinje_shift(water_color.rgb, light_levels);

    return water_color;
}

#endif // INCLUDE_MISC_DISTANT_WATER
#endif
#include "/lib/sky/projection.glsl"

vec3 blend_layers_with_fog(
    vec3 background_color,
    vec4 translucent_color,
    vec3 front_position_world,
    vec3 back_position_world,
    bool is_translucent,
    bool is_sky,
    bool front_is_hand,
    bool back_is_hand
) {
    if (back_is_hand) {
        return background_color * (1.0 - translucent_color.a)
            + translucent_color.rgb;
    }

    // Apply analytic fog behind translucents

#if defined WORLD_OVERWORLD
    if (is_translucent) {
        // Directional sky ambient along the segment: horizon warmth vs
        // zenith blue instead of the flat average.
        vec3 back_dir;
        float back_len;
        length_normalize(
            back_position_world - front_position_world,
            back_dir,
            back_len
        );
        vec3 fog_ambient_back = textureLod(
            colortex4, project_sky(back_dir), 0.0
        ).rgb;
        mat2x3 analytic_fog = air_fog_analytic(
            front_position_world,
            back_position_world,
            is_sky,
            eye_skylight,
            1.0,
            fog_ambient_back
        );


        vec3 mid_scene = 0.5 * (front_position_world + back_position_world)
            - cameraPosition;
        analytic_fog[0] *= get_cloud_shadows(colortex8, mid_scene);

        background_color = background_color * analytic_fog[1] + analytic_fog[0];
    }
#endif

    return background_color * (1.0 - translucent_color.a)
        + translucent_color.rgb;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Sample textures

    float front_depth = texelFetch(depthtex0, texel, 0).x;
    float back_depth = texelFetch(depthtex1, texel, 0).x;

    vec4 refraction_data = texelFetch(colortex3, texel, 0);
    vec4 translucent_color = texelFetch(colortex13, texel, 0);

#if defined vl
    vec3 fog_transmittance = smooth_filter(colortex6, uv).rgb;
    vec3 fog_scattering = smooth_filter(colortex7, uv).rgb;
#ifdef fogSmoothing
    // Denoise the fog buffers themselves. Do not use scene/taa history as a
    // substitute for volumetric radiance.
    fog_transmittance = fog_spatial_filter(
        colortex6, uv, vec2(view_pixel_size.x, view_pixel_size.y),
        max(fogSmoothingRadius, 1)
    );
    fog_scattering = fog_spatial_filter(
        colortex7, uv, vec2(view_pixel_size.x, view_pixel_size.y),
        max(fogSmoothingRadius, 1)
    );
#endif
#endif

    // LoD mod support

#ifdef LOD_MOD_ACTIVE
    float front_depth_lod = texelFetch(lod_depth_tex, texel, 0).x;
    float back_depth_lod = texelFetch(lod_depth_tex_solid, texel, 0).x;

    bool front_is_lod_terrain = is_lod_terrain(front_depth, front_depth_lod);
    bool back_is_lod_terrain = is_lod_terrain(back_depth, back_depth_lod);

    bool is_translucent_lod = front_depth_lod != back_depth_lod;
#else
#define front_depth_lod front_depth
#define back_depth_lod back_depth
#define front_is_lod_terrain false
#define back_is_lod_terrain false
#define is_translucent_lod false
#endif

    bool is_translucent = front_depth != back_depth;
    bool is_sky = back_depth == 1.0 && back_depth_lod == 1.0;

    // Space conversions

    bool front_is_hand;
    bool back_is_hand;
    fix_hand_depth(front_depth, front_is_hand);
    fix_hand_depth(back_depth, back_is_hand);

    vec3 front_position_screen
        = vec3(uv, front_is_lod_terrain ? front_depth_lod : front_depth);
    vec3 front_position_view = screen_to_view_space(
        front_position_screen,
        true,
        front_is_lod_terrain
    );
    vec3 front_position_scene = view_to_scene_space(front_position_view);
    vec3 front_position_world = front_position_scene + cameraPosition;

    vec3 back_position_screen
        = vec3(uv, back_is_lod_terrain ? back_depth_lod : back_depth);
    vec3 back_position_view
        = screen_to_view_space(back_position_screen, true, back_is_lod_terrain);
    vec3 back_position_world
        = view_to_scene_space(back_position_view) + cameraPosition;

    vec3 direction_world;
    float view_distance;
    length_normalize(
        front_position_scene - gbufferModelViewInverse[3].xyz,
        direction_world,
        view_distance
    );

    // Refraction

    float layer_dist = abs(view_distance - length(back_position_view));
    vec2 refracted_uv;

    fragment_color = apply_refraction(
        uv,
        refraction_data,
        is_translucent,
        view_distance,
        layer_dist,
        front_depth,
        isEyeInWater == 1,
        refracted_uv
    );


    vec3 original_color = fragment_color;

    // Draw LoD water

#if defined LOD_MOD_ACTIVE
    if (front_depth_lod != back_depth_lod) {
        // if there is a layer of LoD water behind the translucent layer, these
        // will store the position of that layer
        vec3 lod_position_screen = front_position_screen;
        vec3 lod_position_view = front_position_view;
        vec3 lod_position_world = front_position_world;

        // detect whether translucent LoD terrain may be behind the translucent
        // layer
        float z_mc
            = screen_to_view_space_depth(gbufferProjectionInverse, front_depth);
        float z_lod = screen_to_view_space_depth(
            lod_projection_matrix_inverse,
            front_depth_lod
        );

        const float error_margin = 1.0;
        bool lod_behind_translucent
            = z_lod > z_mc + error_margin && back_depth == 1.0;

        if (front_is_lod_terrain || lod_behind_translucent) {
            if (lod_behind_translucent) {
                lod_position_screen = vec3(uv, front_depth_lod);
                lod_position_view = screen_to_view_space(
                    lod_projection_matrix_inverse,
                    lod_position_screen,
                    true
                );
                lod_position_world
                    = view_to_scene_space(lod_position_view) + cameraPosition;
            }

            // Unpack gbuffer data

#ifdef VOXY
            vec4 gbuffer_data = texelFetch(colortex16, texel, 0);
            bool is_water = min_of(gbuffer_data) > eps;
#else
            vec4 gbuffer_data = texelFetch(colortex1, texel, 0);
#endif

            mat4x2 data = mat4x2(
                unpack_unorm_2x8(gbuffer_data.x),
                unpack_unorm_2x8(gbuffer_data.y),
                unpack_unorm_2x8(gbuffer_data.z),
                unpack_unorm_2x8(gbuffer_data.w)
            );

            vec3 tint = vec3(data[0], data[1].x);
            vec3 flat_normal = decode_unit_vector(data[2]);
            vec2 light_levels = data[3];

#ifdef DISTANT_HORIZONS
            uint material_mask = uint(255.0 * data[1].y);
            bool is_water = material_mask == MATERIAL_WATER;
#else
            float water_alpha = data[1].y;
#endif

            if (is_water) { // Water
                vec4 water_color = draw_distant_water(
                    lod_position_screen,
                    lod_position_view,
                    lod_position_world,
                    direction_world,
                    flat_normal,
                    tint,
                    light_levels,
                    length_knowing_direction(
                        cameraPosition - lod_position_world,
                        direction_world
                    ),
                    length_knowing_direction(
                        lod_position_world - back_position_world,
                        direction_world
                    )
                );

#ifdef VOXY
                // Account for darkening by alpha of water surface
                // water_color *= 8.0;
#endif

                fragment_color
                    = fragment_color * (1.0 - water_color.a) + water_color.rgb;
            }

            back_position_world = lod_behind_translucent
                ? lod_position_world
                : back_position_world;
        }
    }
#endif

    // Blend layers

    fragment_color = blend_layers_with_fog(
        fragment_color,
        translucent_color,
        front_position_world,
        back_position_world,
        is_translucent,
        is_sky,
        front_is_hand,
        back_is_hand
    );

    // Border fog

#ifdef borderFog
    fragment_color = mix(
        original_color,
        fragment_color,
        border_fog(front_position_scene, direction_world)
    );
#endif

    // Blend clouds in front of translucents

#if defined WORLD_OVERWORLD
    float clouds_apparent_distance;
    vec4 clouds_and_aurora
        = read_clouds_and_aurora(refracted_uv, clouds_apparent_distance);

    if (is_translucent || is_translucent_lod) {
        if (clouds_apparent_distance < view_distance) {
            fragment_color
                = fragment_color * clouds_and_aurora.w + clouds_and_aurora.xyz;
        }
    }
#endif

    // Blend fog

#if defined vl
    // Volumetric fog

    fragment_color = fragment_color * fog_transmittance + fog_scattering;

#ifdef bloomyFog
    bloomy_fog
        = clamp01(dot(fog_transmittance, vec3(luminance_weights)));
    bloomy_fog = isEyeInWater == 1 ? sqrt(bloomy_fog) : bloomy_fog;
#endif
#endif

#if !defined vl
    // Analytic fog

    if (isEyeInWater == 1) {
        // Underwater fog
        float LoV = dot(direction_world, light_dir);

        mat2x3 analytic_fog = water_fog_simple(
            light_color,
            ambient_color,
            water_absorption_coeff,
            vec2(0.0, eye_skylight),
            view_distance,
            LoV,
            15.0 * eye_skylight
        );

        fragment_color *= analytic_fog[1];
        fragment_color += analytic_fog[0];

#ifdef bloomyFog
        bloomy_fog = sqrt(clamp01(dot(analytic_fog[1], vec3(0.33))));
#endif
    } else {
#if defined WORLD_OVERWORLD
        // Overworld fog. Directional sky ambient along the view ray
        // instead of the flat average.
        vec3 fog_ambient_front = textureLod(
            colortex4, project_sky(direction_world), 0.0
        ).rgb;
        mat2x3 analytic_fog = air_fog_analytic(
            cameraPosition,
            front_position_world,
            is_sky,
            eye_skylight,
            1.0,
            fog_ambient_front
        );

        // Same cloud gate as above, at this segment's midpoint.
        vec3 mid_scene_main
            = 0.5 * (front_position_world - cameraPosition);
        analytic_fog[0] *= get_cloud_shadows(colortex8, mid_scene_main);

        fragment_color *= analytic_fog[1];
        fragment_color += analytic_fog[0];

#ifdef bloomyFog
        // NOTE: fog_transmittance only exists under vl above; use the
        // analytic transmittance computed just above in this branch.
        bloomy_fog
            = clamp01(dot(analytic_fog[1], vec3(luminance_weights)));
        bloomy_fog = isEyeInWater == 1 ? sqrt(bloomy_fog) : bloomy_fog;
#endif
#else
#ifdef bloomyFog
        bloomy_fog = 1.0;
#endif
#endif
    }
#endif

#ifdef bloomyFog
#if defined WORLD_NETHER
    bloomy_fog
        = spherical_fog(
              view_distance,
              0.0,
              0.0025 * nether_fog_density(front_position_world)
          ) * 0.33
        + 0.67;
#elif defined WORLD_END
    bloomy_fog = bloomy_fog * 0.5 + 0.5;
#endif
#endif
}
