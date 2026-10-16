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

#if !defined INCLUDE_FOG_AIR_FOG_VL
#define INCLUDE_FOG_AIR_FOG_VL

#include "/lib/fog/overworld/constants.glsl"
#include "/lib/util/phaseFunctions.glsl"
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
// ---- Mist mode sentinels (also defined in settings.glsl for Iris) ----
#ifndef mistModeOff
#define mistModeOff      0
#define mistModeBasic    1
#define mistModeAdvanced 2
#endif

#if mistMode != mistModeOff


float mist_density(vec3 world_pos) {
    // Slow horizontal drift — two independent directions for each octave
    vec2 wind0 = vec2(frameTimeCounter * 0.004,  frameTimeCounter * 0.0025);
    vec2 wind1 = vec2(frameTimeCounter * 0.0068, frameTimeCounter * 0.0041);

    float n0 = texture(noisetex, world_pos.xz * 0.008 + wind0).w;
    float n1 = texture(noisetex, world_pos.xz * 0.022 + wind1).w;
    float noise = n0 * 0.7 + n1 * 0.3;

    float altitude = world_pos.y;

    // Exponential falloff above sea level, hard cap at mistAltitude.
    // wetness thickens the layer — after rain, evaporation raises mist density.
    float alt_above_sea = altitude - (63.0 + mistSeaLevelBias);
    float envelope = exp2(-max0(alt_above_sea) * mistFalloffRate);
    envelope *= sqr(1.0 - linear_step(
        float(mistAltitude) - 12.0,
        float(mistAltitude),
        altitude
    ));
    envelope *= 1.0 + 0.4 * wetness;

    return linear_step(0.35, 0.75, noise) * envelope * mistDensity;
}

// Density-varying phase function.


float mist_phase(float cos_theta, float local_density) {
    float g = mix(0.75, 0.40, clamp01(local_density * 8.0));
    return 0.8 * henyey_greenstein_phase(cos_theta, g)
         + 0.2 * henyey_greenstein_phase(cos_theta, -0.1);
}

#if mistMode == mistModeAdvanced


float mist_shadow_od(vec3 world_pos, float local_density) {
    if (local_density < 0.01 || sun_dir.y > 0.3) return 0.0;

    const int   steps     = mistShadowSteps;
    const float step_size = mistShadowStepLength;

    float od = 0.0;
    vec3  pos = world_pos;

    for (int i = 0; i < steps; ++i, pos += light_dir * step_size) {
        if (pos.y > float(mistAltitude)) break;
        od += mist_density(pos) * step_size;
    }

#ifdef cloudShadows
    od *= get_cloud_shadows(colortex8, world_pos - cameraPosition);
#endif

    return od;
}
#endif // mistModeAdvanced

#endif // mistMode != mistModeOff
#include "/lib/light/distortion.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/sky/atmosphere.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

vec2 air_fog_density(vec3 world_pos) {
    const vec2 mul = -rcp(air_fog_falloff_half_life);
    const vec2 add = -mul * air_fog_falloff_start;

    vec2 density = exp2(min(world_pos.y * mul + add, 0.0));

    // fade away below sea level
    density *= linear_step(air_fog_volume_bottom, 63.0, world_pos.y);

#ifdef airFogCloudyNoise
    const vec3 wind = 0.0003 * vec3(1.0, 0.0, 0.7);

    float noise
        = texture(noisetex, 0.001 * world_pos.xz + wind.xz * frameTimeCounter)
              .w;

    density.y *= 4.0 * sqr(noise);
#endif

    return density * (0.5 * overworldFogIntensity);
}

mat2x3 raymarch_air_fog(
    vec3 world_start_pos,
    vec3 world_end_pos,
    bool sky,
    float skylight,
    float dither
) {
    vec3 world_dir = world_end_pos - world_start_pos;

    float length_sq = length_squared(world_dir);
    float norm = inversesqrt(length_sq);
    float ray_length = length_sq * norm;
    world_dir *= norm;

    vec3 shadow_start_pos
        = transform(shadowModelView, world_start_pos - cameraPosition);
    shadow_start_pos = project_ortho(shadowProjection, shadow_start_pos);

    vec3 shadow_dir = mat3(shadowModelView) * world_dir;
    shadow_dir = diagonal(shadowProjection).xyz * shadow_dir;

    float distance_to_lower_plane
        = (air_fog_volume_bottom - eyeAltitude) / world_dir.y;
    float distance_to_upper_plane
        = (air_fog_volume_top - eyeAltitude) / world_dir.y;
    float distance_to_volume_start, distance_to_volume_end;

    if (eyeAltitude < air_fog_volume_bottom) {
        // Below volume
        distance_to_volume_start = distance_to_lower_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? -1.0 : distance_to_upper_plane;
    } else if (eyeAltitude < air_fog_volume_top) {
        // Inside volume
        distance_to_volume_start = 0.0;
        distance_to_volume_end = world_dir.y < 0.0
            ? distance_to_lower_plane
            : distance_to_upper_plane;
    } else {
        // Above volume
        distance_to_volume_start = distance_to_upper_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? distance_to_lower_plane : -1.0;
    }

#ifdef LOD_MOD_ACTIVE
    float fog_end = float(lod_render_distance);
#else
    float fog_end = far;
#endif

    if (distance_to_volume_end < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    ray_length = sky ? distance_to_volume_end : ray_length;
    ray_length = clamp(ray_length - distance_to_volume_start, 0.0, fog_end);

    uint step_count = uint(
        float(air_fog_min_step_count) + air_fog_step_count_growth * ray_length
    );
    step_count = min(step_count, air_fog_max_step_count);

    float step_length = ray_length * rcp(float(step_count));

    vec3 world_step = world_dir * step_length;
    vec3 world_pos = world_start_pos
        + world_dir * (distance_to_volume_start + step_length * dither);

    vec3 shadow_step = shadow_dir * step_length;
    vec3 shadow_pos = shadow_start_pos
        + shadow_dir * (distance_to_volume_start + step_length * dither);

    vec3 transmittance = vec3(1.0);

    mat2x3 light_sun = mat2x3(0.0); // Rayleigh, mie
    mat2x3 light_sky = mat2x3(0.0); // Rayleigh, mie

    for (int i = 0; i < step_count;
         ++i, world_pos += world_step, shadow_pos += shadow_step) {
        vec3 shadow_screen_pos = distort_shadow_space(shadow_pos) * 0.5 + 0.5;

#if defined shadow && !defined PROGRAM_DEFERRED0
        ivec2 shadow_texel = ivec2(
            shadow_screen_pos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );

#ifdef airFogColoredLightShafts
        float depth0 = texelFetch(shadowtex0, shadow_texel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        vec3 color
            = clamp01(texelFetch(shadowcolor0, shadow_texel, 0).rgb * 4.0);
        float color_weight
            = step(depth0, shadow_screen_pos.z) * step(eps, max_of(color));

        color = color * color_weight + (1.0 - color_weight);
        color = mix(vec3(1.0), color, airFogColoredLightShaftsIntensity);

        vec3 shadowVis = step(shadow_screen_pos.z, depth1) * color;
        shadowVis = (clamp01(shadow_screen_pos) == shadow_screen_pos)
            ? shadowVis
            : vec3(1.0);
        // Scalar sun visibility for mist below: float(vec3 > 0.0) is
        // illegal GLSL, so reduce explicitly (this branch is rgb).
        float shadow_binary = step(eps, max_of(shadowVis));
#else
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        float shadowVis = step(
            float(clamp01(shadow_screen_pos) == shadow_screen_pos)
                * shadow_screen_pos.z,
            depth1
        );
        float shadow_binary = shadowVis;
#endif
#else
#define shadowVis 1.0
#define shadow_binary 1.0
#endif

        vec2 density = air_fog_density(world_pos) * step_length;

        vec3 step_optical_depth
            = fog_params.rayleigh_scattering_coeff * density.x
            + fog_params.mie_extinction_coeff * density.y;

#if mistMode != mistModeOff
        float mist_d = mist_density(world_pos) * step_length;
        step_optical_depth += fog_params.mist_scattering_coeff * mist_d;
#endif

        vec3 step_transmittance = exp(-step_optical_depth);
        vec3 step_transmitted_fraction
            = (1.0 - step_transmittance) / max(step_optical_depth, eps);

        vec3 visible_scattering = step_transmitted_fraction * transmittance;

        light_sun[0] += visible_scattering * density.x * shadowVis;
        light_sun[1] += visible_scattering * density.y * shadowVis;
        light_sky[0] += visible_scattering * density.x;
        light_sky[1] += visible_scattering * density.y;

#if mistMode != mistModeOff
        if (mist_d > 1e-5) {
            float LoV = dot(world_dir, light_dir);

#if mistMode == mistModeAdvanced
            float mist_od  = mist_shadow_od(world_pos, mist_d / step_length);
            // Power-law self-extinction keeps dense mist from glowing
            // through itself, plus cloud occlusion above the mist layer
            float mist_sun_shadow = pow(1.0 + 0.7 * mist_od, -1.0 / 0.7) * shadow_binary;
            float mist_phase_val  = mist_phase(LoV, mist_d / step_length);
#else
            float mist_sun_shadow = shadow_binary;
            float mist_phase_val  = mist_phase(LoV, mist_d / step_length);
#endif

            vec3 mist_scatter = fog_params.mist_scattering_coeff * mist_d * visible_scattering;
            light_sun[1] += mist_scatter * mist_phase_val * mist_sun_shadow;
            light_sky[1] += mist_scatter * isotropic_phase;
        }
#endif

        transmittance *= step_transmittance;
    }


    vec3 mid_world_pos = world_start_pos
        + world_dir * (distance_to_volume_start + ray_length * 0.5);
    light_sun *= get_cloud_shadows(colortex8, mid_world_pos - cameraPosition);

    light_sun[0] *= fog_params.rayleigh_scattering_coeff;
    light_sun[1] *= fog_params.mie_scattering_coeff;
    light_sky[0] *= fog_params.rayleigh_scattering_coeff;
    light_sky[1] *= fog_params.mie_scattering_coeff;

    if (!sky) {
        // Skylight falloff
        light_sky[0] *= max(skylight, eye_skylight);
        light_sky[1] *= max(skylight, eye_skylight);
    }

    float LoV = dot(world_dir, light_dir);
    float mie_phase = 0.7 * henyey_greenstein_phase(LoV, fogMieAnisotropy)
        + 0.3 * henyey_greenstein_phase(LoV, -0.2);

    /*
    // Single scattering
    vec3 scattering  = light_color * (light_sun * vec2(isotropic_phase,
    mie_phase)); scattering += ambient_color * (light_sky *
    vec2(isotropic_phase));
    /*/
    // Multiple scattering
    vec3 scattering = vec3(0.0);
    float scatter_amount = 1.0;
    float anisotropy = 1.0;

#if defined PROGRAM_DEFERRED0
    vec3 ambient_color = ambient_color_fog;
#endif

    scattering += 2.0 * light_sky * vec2(isotropic_phase)
        * ambient_color;

    for (int i = 0; i < 4; ++i) {
        float mie_phase = 0.7 * henyey_greenstein_phase(LoV, fogMieAnisotropy * anisotropy)
            + 0.3 * henyey_greenstein_phase(LoV, -0.2 * anisotropy);

        vec3 order_light = light_color;
#if defined ozoneLayer && defined ozoneFog


        order_light *= ozone_multiple_scattering(float(i));
#endif

        scattering += scatter_amount
            * (light_sun * vec2(isotropic_phase, mie_phase)) * order_light
            * (1.0 - 0.9 * rainStrength);

        scatter_amount *= 0.5;
        anisotropy *= 0.7;
    }
    //*/

    scattering *= clamp01(1.0 - blindness - darknessFactor);

    // Artifically brighten fog in the early morning and evening (looks nice)
    float evening_glow
        = 0.75 * linear_step(0.05, 1.0, exp(-300.0 * sqr(sun_dir.y + 0.02)));
    scattering += scattering * evening_glow;

    return mat2x3(scattering, transmittance);
}

#ifdef shadowVis
#undef shadowVis
#endif

#endif // INCLUDE_FOG_AIR_FOG_VL
