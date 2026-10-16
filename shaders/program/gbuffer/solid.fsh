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

#ifdef pomSlopeNormals
// Iris requires boolean shader options to be checked with #ifdef/#ifndef.
#define POM_SLOPE_NORMALS_OPTION_ENABLED
#endif
// Legacy singular guard name (pre-rename). Treat it as the plural toggle.
#ifdef POM_SLOPE_NORMAL
#define POM_SLOPE_NORMALS_OPTION_ENABLED
#ifndef pomSlopeNormals
#define pomSlopeNormals
#endif
#endif
#ifdef pomDepthWrite
// Iris requires boolean shader options to be checked with #ifdef/#ifndef.
#define POM_DEPTH_WRITE_OPTION_ENABLED
#endif

layout(
    location = 0
) out vec4 gbuffer_data_0; // albedo, block ID, flat normal, light levels
layout(
    location = 1
) out vec4 gbuffer_data_1; // detailed normal, specular map (optional)

/* RENDERTARGETS: 1 */

#ifdef normalMapping
/* RENDERTARGETS: 1,2 */
#endif

#ifdef specularMapping
/* RENDERTARGETS: 1,2 */
#endif

in vec2 uv;
in vec3 scene_pos;
in vec4 tint;

flat in uint material_mask;
flat in mat3 tbn;

#if defined pom
in vec2 atlas_tile_coord;
in vec3 tangent_pos;
flat in vec2 atlas_tile_offset;
flat in vec2 atlas_tile_scale;
#endif

#ifdef COLORWHEEL
vec2 light_levels;
float vanilla_ao;
#else
in vec2 light_levels;
#if defined PROGRAM_GBUFFERS_TERRAIN
in float vanilla_ao;
#endif
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
in vec2 uv_local;
#endif

#if defined PROGRAM_GBUFFERS_VOXELS
in vec3 block_normal;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D gtexture;

#if defined normalMapping || defined pom
uniform sampler2D normals;
#endif

#if defined specularMapping
uniform sampler2D specular;
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform vec3 light_dir;

uniform float alphaTestRef = 0.1;

#if defined PROGRAM_GBUFFERS_ENTITIES
uniform int entityId;
uniform vec4 entityColor;
#endif

#if defined PROGRAM_GBUFFERS_PARTICLES
#define NO_NORMAL
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom
#include "/lib/material/parallax.glsl"
#endif

#ifdef directionalLightmaps
#define LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS
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

#undef LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS
#endif
// Change the material mask of some handheld/dropped items to help the hardcoded
// emission

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
uint fix_material_mask() {
#if defined PROGRAM_GBUFFERS_ENTITIES
    if (entityId != 10100) {
        return material_mask;
    }
    bool is_top_face = tbn[2].y > 0.5;
#else
    bool is_top_face = (mat3(gbufferModelView) * tbn[2]).y > 0.5;
#endif

    // Warped stems
    if (19 <= material_mask && material_mask < 22) {
        bool is_lit = !is_top_face
            || any(
                lessThan(vec4(uv_local, 1.0 - uv_local), vec4(rcp(16.0) - 1e-3))
            );
        return is_lit ? 22u : 0u;
    }

    // Crimson stems
    if (23 <= material_mask && material_mask < 26) {
        bool is_lit = !is_top_face
            || any(
                lessThan(vec4(uv_local, 1.0 - uv_local), vec4(rcp(16.0) - 1e-3))
            );
        return is_lit ? 26u : 0u;
    }

    return material_mask;
}
#endif
#include "/lib/util/dithering.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

#if defined PROGRAM_GBUFFERS_VOXELS
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom
#define read_tex(x) textureGrad(x, parallax_uv, uv_gradient[0], uv_gradient[1])
#else
// Plain isotropic sampling with the render-scale LOD bias.
#define read_tex(x) texture(x, uv, lod_bias)
#endif

#if defined PROGRAM_GBUFFERS_BLOCK
vec3 draw_end_portal() {
    const int layer_count = 8; // Number of layers
    const float depth_scale = 0.33; // Apparent distance between layers
    const float depth_fade = 0.5; // How quickly the layers fade to black
    const float threshold = 0.99; // Threshold for the "stars". Lower values
                                  // mean more stars appear
    const float twinkle_speed = 0.4; // How fast the stars appear to twinkle
    const float twinkle_amount = 0.04; // How many twinkling stars appear
    const vec3 color0 = pow(vec3(0.80, 0.90, 0.99), vec3(2.2));
    const vec3 color1 = pow(vec3(0.75, 0.40, 0.93), vec3(2.2));
    const vec3 color2 = pow(vec3(0.20, 0.70, 0.90), vec3(2.2));

    vec3 screen_pos = vec3(
        gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale),
        gl_FragCoord.z
    );
    vec3 view_pos = screen_to_view_space(screen_pos, true);
    vec3 scene_pos = view_to_scene_space(view_pos);

    vec3 world_pos = scene_pos + cameraPosition;
    vec3 world_dir = normalize(scene_pos - gbufferModelViewInverse[3].xyz);

    // Get tangent-space position/direction without tangent/bitangent

    vec2 tangent_pos, tangent_dir;
    if (abs(tbn[2].x) > 0.5) {
        tangent_pos = world_pos.yz;
        tangent_dir = world_dir.yz / abs(world_dir.x + eps);
    } else if (abs(tbn[2].y) > 0.5) {
        tangent_pos = world_pos.xz;
        tangent_dir = world_dir.xz / abs(world_dir.y + eps);
    } else {
        tangent_pos = world_pos.xy;
        tangent_dir = world_dir.xy / abs(world_dir.z + eps);
    }

    vec3 result = vec3(0.0);

    for (int i = 0; i < layer_count; ++i) {
        // Random layer offset
        vec2 layer_offset = r2(i) * 512.0;

        // Make layers drift over time
        float angle = i * golden_angle;
        vec2 drift
            = 0.033 * vec2(cos(angle), sin(angle)) * frameTimeCounter * r1(i);

        // Snap tangent_pos to a grid and calculate a seed for the RNG
        ivec2 grid_pos = ivec2((tangent_pos + drift) * 32.0 + layer_offset);
        uint seed = uint(80000 * grid_pos.y + grid_pos.x);

        // 4 random numbers for this grid cell
        vec4 random = rand_next_vec4(seed);

        // Twinkling animation
        float twinkle_offset = tau * random.w;
        random.x *= 1.0
            - twinkle_amount
                * cos(frameTimeCounter * twinkle_speed + twinkle_offset);

        // Stomp all values below threshold to zero
        float intensity = pow8(linear_step(threshold, 1.0, random.x));

        // Blend between the 3 colors
        vec3 color = mix(color0, color1, random.y);
        color = mix(color, color2, random.z);

        // Fade away with depth
        float fade = exp2(-depth_fade * float(i));

        result += color * intensity * exp2(-3.0 * (1.0 - fade) * (1.0 - color))
            * fade;

        // Step along the view ray
        tangent_pos
            += tangent_dir * depth_scale * gbufferProjection[1][1] * rcp(1.37);

        if (random.x > threshold) {
            break;
        }
    }

    result *= 0.8;
    result = sqrt(result);
    result *= sqrt(result);

    return result;
}
#endif

const float lod_bias = log2(taau_render_scale);

void main() {
#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);
    if (clamp01(coord) != coord) {
        discard;
        return;
    }
#endif

    bool parallax_shadow = false;
    float dither = interleaved_gradient_noise(gl_FragCoord.xy, frameCounter);
    // pom relief state shared by slope normals and depth write. Stays zero
    // when the march is skipped so both effects fade out together.
    float pom_relief = 0.0;
    float pom_slope_fade = 0.0;

#ifndef PROGRAM_GBUFFERS_VOXELS
#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom
    float view_distance = length(tangent_pos);

    bool has_pom
        = view_distance < pomDistance; // Only calculate pom for close terrain
    has_pom = has_pom
        && material_mask
            != MATERIAL_LAVA; // Do not calculate pom for water or lava

    vec3 tangent_dir = -normalize(tangent_pos);
    mat2 uv_gradient = mat2(dFdx(uv), dFdy(uv));

    vec2 parallax_uv;

    if (has_pom) {
        float pom_depth;
        vec3 shadow_trace_pos;

        parallax_uv = get_parallax_uv(
            tangent_dir,
            uv_gradient,
            view_distance,
            dither,
            shadow_trace_pos,
            pom_depth
        );

        pom_relief = get_pom_world_relief(pom_depth, view_distance);
        pom_slope_fade = get_pom_relief_scale(view_distance);
#ifdef pomShadow
        if (dot(tbn[2], light_dir) >= eps) {
            parallax_shadow = get_parallax_shadow(
                shadow_trace_pos,
                uv_gradient,
                view_distance,
                dither
            );
        } else {
            parallax_shadow = false;
        }
#endif
    } else {
        parallax_uv = uv;
        parallax_shadow = false;
    }
#endif

    //--//

    vec4 base_color;
#if defined COLORWHEEL
    base_color = read_tex(gtexture);
    vec4 overlayColor;

    clrwl_computeFragment(
        base_color,
        base_color,
        light_levels,
        vanilla_ao,
        overlayColor
    );
    light_levels = clamp((light_levels - 1.0 / 32.0) * 32.0 / 30.0, 0.0, 1.0);
#else
    base_color = read_tex(gtexture) * tint;
#endif

#ifdef normalMapping
    vec3 normal_map = read_tex(normals).xyz;
#endif
#ifdef specularMapping
    vec4 specular_map = read_tex(specular);
#endif
#else
    vec3 screen_pos = vec3(
        gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale),
        gl_FragCoord.z
    );

    vec3 view_pos = screen_to_view_space(screen_pos, true);
    vec3 scene_pos = view_to_scene_space(view_pos);

    vec3 world_pos = scene_pos + cameraPosition;
    vec3 world_dir = normalize(scene_pos - gbufferModelViewInverse[3].xyz);

    RayJob ray = RayJob(
        world_pos - world_offset - 0.001f * block_normal, // Ray origin
        world_dir, // Ray direction
        vec3(0),
        vec3(0),
        vec3(0),
        false
    );

    ray_constraint = ivec3(ray.origin);
    trace_ray(ray);

    if (!ray.result_hit) {
        discard;
    }
    if (ray.result_normal == vec3(0.0)) {
        ray.result_normal = block_normal;
    }

    scene_pos = ray.result_position + world_offset - cameraPosition;
    view_pos = scene_to_view_space(scene_pos);
    screen_pos = view_to_screen_space(gbufferProjection, view_pos, true);

    gl_FragDepth = screen_pos.z;

    vec4 base_color = vec4(ray.result_color, 1.0f);
    vec3 ph_normal = ray.result_normal;

#if defined specularMapping
    vec4 specular_map = vec4(0.0f);
#endif
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES
    if (material_mask == MATERIAL_LIGHTNING_BOLT) {
        base_color = vec4(1.0);
    }
    if (base_color.a < alphaTestRef && material_mask != MATERIAL_BOAT) {
        discard;
        return;
    } // Save transparent quad in boats, which masks out water
#elif !defined PROGRAM_GBUFFERS_TERRAIN_SOLID
    if (base_color.a < alphaTestRef) {
        discard;
        return;
    }
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined vanillaAo
#if shaderAo != shaderAoNone
    const float vanilla_ao_strength = 0.9 * 1.00;
    const float vanilla_ao_lift = clamp(0.5 * (1-((1-1.00)*0.5)) + vanillaAoLift, 0.0, 1.0);
#else
    const float vanilla_ao_strength = 1.0 * 1.00;
    const float vanilla_ao_lift = clamp(vanillaAoLift, 0.0, 1.0);
#endif

    base_color.rgb *= lift(vanilla_ao, vanilla_ao_lift) * vanilla_ao_strength
        + (1.0 - vanilla_ao_strength);
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES
    base_color.rgb = mix(base_color.rgb, entityColor.rgb, entityColor.a);
#endif

#if defined COLORWHEEL
    base_color.rgb = mix(base_color.rgb, overlayColor.rgb, overlayColor.a);
#endif

#if defined PROGRAM_GBUFFERS_BLOCK
    // parallax end portal
    if (material_mask == MATERIAL_END_PORTAL) {
        base_color.rgb = draw_end_portal();
    }
#endif

#if defined PROGRAM_GBUFFERS_BEACONBEAM
    // Discard the translucent edge part of the beam
    if (base_color.a < 0.5) {
        discard;
    }
#endif

    vec2 adjusted_light_levels = light_levels;

#if defined normalMapping && !defined PROGRAM_GBUFFERS_VOXELS
    vec3 normal;
    float material_ao;
#if defined pomSlopeNormalsOnly || defined pomSlopeNormalOnly
    normal = vec3(0.0, 0.0, 1.0);
    material_ao = 1.0;
#else
    decode_normal_map(normal_map, normal, material_ao);
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom \
    && defined pomSlopeNormals && info > 0


    if (has_pom && pom_slope_fade > 1e-4) {
        normal = normalize(
            normal
            + get_pom_slope_normal(
                get_local_coord_from_uv(parallax_uv),
                uv_gradient
            )
                * pom_slope_fade
        );
    }
#endif

    normal = tbn * normal;

#ifdef textureAo


    // occlude the lightmap. Off by default.
    adjusted_light_levels *= mix(0.7, 1.0, clamp01(material_ao));
#endif

#ifdef directionalLightmaps
    adjusted_light_levels *= get_directional_lightmaps(scene_pos, normal);
#endif
#elif defined PROGRAM_GBUFFERS_TERRAIN && defined pom \
    && defined pomSlopeNormals && info > 0


    vec3 normal = tbn[2];
    if (has_pom && pom_slope_fade > 1e-4) {
        normal = tbn * normalize(
            vec3(0.0, 0.0, 1.0)
            + get_pom_slope_normal(
                get_local_coord_from_uv(parallax_uv),
                uv_gradient
            )
                * pom_slope_fade
        );
    }
#endif

#if defined PROGRAM_GBUFFERS_VOXELS
#define flat_normal ph_normal
#define detailed_normal ph_normal
#elif defined NO_NORMAL
    // No normal vector => make one from screen-space partial derivatives
    vec3 particle_normal = normalize(cross(dFdx(scene_pos), dFdy(scene_pos)));
#define flat_normal particle_normal
#define detailed_normal particle_normal
#else
#define flat_normal tbn[2]
#define detailed_normal normal
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
    uint new_material_mask = fix_material_mask();
#define material_mask new_material_mask
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN && defined pom && defined pomDepthWrite
    // pom depth write: recess the fragment into the surface by the raymarched


    gl_FragDepth = gl_FragCoord.z;
    if (has_pom && pom_relief > 1e-5) {


        float pom_cos_theta = max(abs(tangent_dir.z), 0.15);
        float pom_ray_dist = pom_relief * rcp(pom_cos_theta);
        vec3 pom_displaced_scene
            = scene_pos * (1.0 + pom_ray_dist * rcp(max(length(scene_pos), 1e-3)));
        vec3 pom_displaced_view = scene_to_view_space(pom_displaced_scene);
        vec3 pom_displaced_screen = view_to_screen_space(
            gbufferProjection,
            pom_displaced_view,
            true
        );
        float pom_depth_z = pom_displaced_screen.z;
        // Only accept finite results, never pull the surface toward the
        // camera, and stay strictly inside the depth range (>= 1.0 = sky).
        if (pom_depth_z == pom_depth_z) {
            gl_FragDepth = clamp(
                max(pom_depth_z, gl_FragCoord.z),
                0.0,
                0.999999
            );
        }
    }
#endif

    gbuffer_data_0.x = pack_unorm_2x8(base_color.rg);
    gbuffer_data_0.y = pack_unorm_2x8(
        base_color.b,
        clamp01(float(material_mask) * rcp(255.0))
    );
    gbuffer_data_0.z = pack_unorm_2x8(encode_unit_vector(flat_normal));
    gbuffer_data_0.w
        = pack_unorm_2x8(dither_8bit(adjusted_light_levels, dither));

#ifdef normalMapping
    gbuffer_data_1.xy = encode_unit_vector(detailed_normal);
#endif

#ifdef specularMapping
#if defined pom && defined pomShadow
    // Pack parallax shadow in alpha component of specular map
    // Specular map alpha >= 0.5 => parallax shadow
    specular_map.a *= step(specular_map.a, 0.999);
    specular_map.a
        = clamp01(specular_map.a * 0.5 + 0.5 * float(parallax_shadow));
#endif

    gbuffer_data_1.z = pack_unorm_2x8(specular_map.xy);
    gbuffer_data_1.w = pack_unorm_2x8(specular_map.zw);
#else
#if defined pom && defined pomShadow
    gbuffer_data_1.z = float(parallax_shadow);
#endif
#endif

#if defined PROGRAM_GBUFFERS_PARTICLES
    // Kill the little rain splash particles
    if (base_color.r < 0.29 && base_color.g < 0.45 && base_color.b > 0.75) {
        discard;
    }
#endif
}
