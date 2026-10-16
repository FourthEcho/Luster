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

// Luster Mac all-on split: deferred11 = lighting, deferred12 = compose.
// World stubs define LUSTER_D4_PASS before including; default is lighting.
#ifndef LUSTER_D4_PASS
#define LUSTER_D4_PASS 1
#endif

layout(location = 0) out vec3 fragment_color;

#if LUSTER_D4_PASS == 1
#ifdef useSeparateEntityDraws
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
#ifdef hBasisSkylight
flat in vec3 h_sky[6];
#endif

#if defined WORLD_OVERWORLD
flat in vec3 sun_color;
flat in vec3 moon_color;

#include "/lib/fog/overworld/parameters.glsl"
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

#ifndef useSeparateEntityDraws
uniform sampler2D colortex3; // OF damage overlay, armor glint
#endif

#if defined WORLD_OVERWORLD && defined galaxy
uniform sampler2D colortex13;

// Galaxy/LoD support can both declare colortex15
#ifndef LUSTER_COLORTEX15_DECLARED
#define LUSTER_COLORTEX15_DECLARED
uniform sampler2D colortex15;
#endif
#define galaxy_sampler colortex13
#endif

#ifdef cloudShadows
uniform sampler2D colortex8; // cloud shadow map
#endif

uniform sampler3D depthtex0; // atmosphere scattering LUT
uniform sampler2D depthtex1;

#ifdef blockyClouds
uniform sampler2D depthtex2; // minecraft cloud texture
#endif

#ifndef WORLD_NETHER
#ifdef shadow
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef shadowColor
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

#include "/lib/fog/simpleFog.glsl"
#if !defined INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
#define INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

// H-basis directional sky ambient.

#include "/lib/sky/projection.glsl"

void project_sky_h_basis(out vec3 h[6]) {
    for (int i = 0; i < 6; ++i) {
        h[i] = vec3(0.0);
    }

    for (int i = 0; i < hBasisSkySamples; ++i) {
        // Uniform-sphere low-discrepancy sequence (deterministic by design).
        vec2 u = vec2(
            (float(i) + 0.5) / float(hBasisSkySamples),
            fract(float(i) * 0.61803398875)
        );

        float phi = tau * u.y;
        float cos_theta = 2.0 * u.x - 1.0;
        float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
        vec3 d = vec3(
            sin_theta * cos(phi), cos_theta, sin_theta * sin(phi)
        );

        vec3 radiance = max0(texture(colortex4, project_sky(d)).rgb);

        h[0] += radiance;
        h[1] += radiance * d.x;
        h[2] += radiance * d.y;
        h[3] += radiance * d.z;
        h[4] += radiance * (1.5 * d.y * d.y - 0.5);
        h[5] += radiance * (d.x * d.x - d.z * d.z) * 0.5;
    }

    float inv_n = 1.0 / float(hBasisSkySamples);
    for (int i = 0; i < 6; ++i) {
        h[i] *= inv_n;
    }
}

vec3 evaluate_h_basis_irradiance(vec3 h[6], vec3 normal) {
    vec3 n = normalize(normal);

    vec3 result = h[0] * pi;
    result += (2.0 * pi / 3.0) * (h[1] * n.x + h[2] * n.y + h[3] * n.z);
    result += (pi * 0.125) * h[4] * (3.0 * n.y * n.y - 1.0);
    result += (pi * 0.125) * h[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT
#include "/lib/brdf/diffuseLight.glsl"
#include "/lib/light/common.glsl"
#include "/lib/light/pcss.glsl"
#if !defined INCLUDE_LIGHTING_DIRECT_LIGHTING_SSRT
#define INCLUDE_LIGHTING_DIRECT_LIGHTING_SSRT

#include "/lib/light/common.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/sampling.glsl"
#include "/lib/util/spaceConversion.glsl"

bool raymarch_shadow(
    sampler2D depth_sampler,
    mat4 projection_matrix,
    mat4 projection_matrix_inverse,
    vec3 ray_origin_screen,
    vec3 ray_origin_view,
    vec3 ray_dir_view,
    bool has_sss,
    float dither,
    out float sss_depth
) {
    const uint step_count = uint(shadowSsrtSteps);
    const float step_ratio = 2.0; // geometric sample distribution
    const float z_tolerance = 10.0; // assumed thickness in blocks

    vec3 ray_dir_screen = normalize(
        view_to_screen_space(
            projection_matrix,
            ray_origin_view + ray_dir_view,
            true
        )
        - ray_origin_screen
    );


    vec3 inv_dir = 1.0 / (ray_dir_screen + vec3(1e-9));
    vec3 t_to_edge = max(
        (vec3(0.0) - ray_origin_screen) * inv_dir,
        (vec3(1.0) - ray_origin_screen) * inv_dir
    );
    float ray_length = min_of(max(t_to_edge, vec3(0.0)));
    ray_length = min(
        ray_length,
        max(0.1, exp(-max0(length(ray_origin_view) * 0.025 - 1.0)))
    );

    const float initial_step_scale = step_ratio == 1.0
        ? rcp(float(step_count))
        : (step_ratio - 1.0) / (pow(step_ratio, float(step_count)) - 1.0);
    float step_length = ray_length * initial_step_scale;

    vec3 ray_pos = ray_origin_screen + length(view_pixel_size) * ray_dir_screen;

    bool hit = false;
    bool hit_after_sss = false;
    bool sss_raymarch = has_sss;
    vec3 exit_pos = ray_origin_screen;

    for (int i = 0; i < step_count; ++i) {
        vec3 ray_step = ray_dir_screen * step_length;
        step_length *= step_ratio;
        vec3 dithered_pos = ray_pos + dither * ray_step;
        ray_pos += ray_step;

#ifdef LOD_MOD_ACTIVE
        if (dithered_pos.z < 0.0) {
            continue;
        }
#endif
        if (clamp01(dithered_pos) != dithered_pos) {
            break;
        }

        float depth = texelFetch(
                          depth_sampler,
                          ivec2(dithered_pos.xy * view_res * taau_render_scale),
                          0
        )
                          .x;

        float z_ray = screen_to_view_space_depth(
            projection_matrix_inverse,
            dithered_pos.z
        );
        float z_sample
            = screen_to_view_space_depth(projection_matrix_inverse, depth);

        bool inside = depth != 0.0 && depth < dithered_pos.z
            && abs(z_tolerance - (z_ray - z_sample)) < z_tolerance;
        hit = inside || hit;

        if (sss_raymarch) {
            if (!inside) {
                exit_pos = dithered_pos;
                sss_raymarch = false;
            }
        }

        else if (!sss_raymarch) {
            hit_after_sss = inside || hit_after_sss;
            if (hit) {
                break;
            }
        }
    }

    exit_pos = screen_to_view_space(projection_matrix_inverse, exit_pos, true);
    sss_depth = hit_after_sss ? -1.0
                              : max0(distance(ray_origin_view, exit_pos) * 0.2);

    return hit;
}

float get_screen_space_shadows(
    vec2 position_screen_xy,
    vec3 position_view,
    float depth,
#ifdef LOD_MOD_ACTIVE
    float depth_lod,
#endif
    float skylight,
    bool has_sss,
    inout float sss_depth
) {
    // Dithering for ray offset
    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);

    // Slightly randomise ray direction to create soft shadows
    vec2 hash = hash2(gl_FragCoord.xy);
    vec3 ray_dir
        = normalize(view_light_dir + 0.03 * uniform_sphere_sample(hash));

#ifdef LOD_MOD_ACTIVE


    bool raymarch_combined_depth = length_squared(position_view)
        < sqr(far + 64.0); // heuristic of 4 chunks overlap
    bool hit;

    /*
    #ifdef MC_GL_KHR_shader_subgroup
    // Using subgroup ops, we make sure that if any fragments in a warp are
    raymarching the
    // combined depth buffer, they all do, to avoid divergent branches.
    raymarch_combined_depth = subgroupAny(raymarch_combined_depth);
    #endif
    */

    if (raymarch_combined_depth) {
        hit = raymarch_shadow(
            combined_depth_tex,
            combined_projection_matrix,
            combined_projection_matrix_inverse,
            vec3(position_screen_xy, depth),
            position_view,
            ray_dir,
            has_sss,
            dither,
            sss_depth
        );
    } else {
        hit = raymarch_shadow(
            lod_depth_tex,
            lod_projection_matrix,
            lod_projection_matrix_inverse,
            vec3(position_screen_xy, depth_lod),
            screen_to_view_space(
                lod_projection_matrix_inverse,
                vec3(position_screen_xy, depth_lod),
                true
            ),
            ray_dir,
            has_sss,
            dither,
            sss_depth
        );
    }
#else
    bool hit = raymarch_shadow(
        depthtex1,
        gbufferProjection,
        gbufferProjectionInverse,
        vec3(position_screen_xy, depth),
        position_view,
        view_light_dir,
        has_sss,
        dither,
        sss_depth
    );
#endif

    return float(!hit) * get_lightmap_light_leak_prevention(skylight);
}

#endif // INCLUDE_LIGHTING_DIRECT_LIGHTING_SSRT

#include "/lib/brdf/specular.glsl"
#include "/lib/misc/lodModSupport.glsl"
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
#include "/lib/sky/sky.glsl"
#include "/lib/misc/edgeHighlight.glsl"
#include "/lib/material/material.glsl"
#define LUSTER_INCLUDE_RAIN_PUDDLES
#include "/lib/material/rain.glsl"
#undef LUSTER_INCLUDE_RAIN_PUDDLES
#include "/lib/util/bicubic.glsl"
#include "/lib/util/spaceConversion.glsl"


void bilateral_upscale_sample(
    sampler2D data_sampler,
    sampler2D depth_sampler,
    ivec2 base_texel,
    out vec4 data00,
    out vec4 data10,
    out vec4 data01,
    out vec4 data11,
    out float depth00,
    out float depth10,
    out float depth01,
    out float depth11
) {
    ivec2 p10 = base_texel + ivec2(1, 0);
    ivec2 p01 = base_texel + ivec2(0, 1);
    ivec2 p11 = base_texel + ivec2(1, 1);

    data00 = texelFetch(data_sampler, base_texel, 0);
    data10 = texelFetch(data_sampler, p10, 0);
    data01 = texelFetch(data_sampler, p01, 0);
    data11 = texelFetch(data_sampler, p11, 0);

    depth00 = texelFetch(depth_sampler, base_texel, 0).x;
    depth10 = texelFetch(depth_sampler, p10, 0).x;
    depth01 = texelFetch(depth_sampler, p01, 0).x;
    depth11 = texelFetch(depth_sampler, p11, 0).x;
}


vec4 bilateral_upscale_resolve(
    vec4 data00,
    vec4 data10,
    vec4 data01,
    vec4 data11,
    float depth00,
    float depth10,
    float depth01,
    float depth11,
    vec2 f,
    mat4 projection_matrix_inverse,
    float current_lin_z,
    float depth_weight_scale
) {
#define depth_weight(reversed_depth) \
    exp2( \
        -depth_weight_scale \
        * abs( \
            screen_to_view_space_depth( \
                projection_matrix_inverse, \
                1.0 - reversed_depth \
            ) \
            - current_lin_z \
        ) \
    )
    float w00 = depth_weight(depth00) * (1.0 - f.x) * (1.0 - f.y);
    float w10 = depth_weight(depth10) * (f.x - f.x * f.y);
    float w01 = depth_weight(depth01) * (f.y - f.x * f.y);
    float w11 = depth_weight(depth11) * (f.x * f.y);
#undef depth_weight

    float weight_sum = w00 + w10 + w01 + w11;

    if (abs(weight_sum) > eps) {
        return (data00 * w00 + data10 * w10 + data01 * w01 + data11 * w11)
            * rcp(weight_sum);
    }

    return data00;
}
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"


#if defined WORLD_OVERWORLD
#include "/lib/sky/clouds/sampling.glsl"
#include "/lib/sky/rainbow.glsl"
#if defined blockyClouds
#if !defined INCLUDE_SKY_BLOCKY_CLOUDS
#define INCLUDE_SKY_BLOCKY_CLOUDS

#include "/lib/sky/atmosphere.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"
#include "/lib/util/random.glsl"

// Blocky volumetric clouds

const float blocky_clouds_altitude_l0 = blockyCloudsAltitude;
const float blocky_clouds_altitude_l1 = blockyCloudsAltitude2;
const float blocky_clouds_thickness = blockyCloudsThickness;

float blocky_clouds_extinction_coeff
    = mix(0.66, 1.0, smoothstep(0.0, 0.3, abs(sun_dir.y)));
float blocky_clouds_scattering_coeff = blocky_clouds_extinction_coeff;

float blocky_clouds_phase_single(
    float cos_theta
) { // Single scattering phase function
    return 0.7 * klein_nishina_phase(cos_theta, 2600.0) // forwards lobe
        + 0.3 * henyey_greenstein_phase(cos_theta, -0.2); // backwards lobe
}

float blocky_clouds_phase_multi(
    float cos_theta,
    vec3 g
) { // Multiple scattering phase function
    return 0.65 * henyey_greenstein_phase(cos_theta, g.x) // forwards lobe
        + 0.10 * henyey_greenstein_phase(cos_theta, g.y) // forwards peak
        + 0.25 * henyey_greenstein_phase(cos_theta, -g.z); // backwards lobe
}

float texture_soft(sampler2D sampler, vec2 coord, float softness) {
    vec2 res = vec2(textureSize(sampler, 0));

    coord = coord * res + 0.5;
    vec2 i, f = modf(coord, i);

    f = smoothstep(
        0.5 - softness,
        0.5 + softness,
        f
    ); // the closer the borders are to 0.5, the sharper the cloud edge
    coord = i * rcp(res) + rcp(res);

    vec4 samples = textureGather(sampler, coord, 3);
    vec4 weights = vec4(
        f.y - f.x * f.y,
        f.x * f.y,
        f.x - f.x * f.y,
        1.0 - f.x - f.y + f.x * f.y
    );

    return dot(samples, weights);
}

float blocky_clouds_density(
    vec3 world_pos,
    float altitude_fraction,
    float layer_offset
) {
    const float wind_angle = blockyCloudsWindAngle * degree;
    const vec2 wind_velocity
        = blockyCloudsWindSpeed * vec2(cos(wind_angle), sin(wind_angle));

    const float roundness
        = 0.5 * blockyCloudsRoundness; // Controls the roundness of the clouds
    const float sharpness = 0.5
        * blockyCloudsSharpness; // Controls the sharpness of the cloud edges

    // Adjust position

    world_pos.xz = abs(world_pos.xz + 3000.0 + layer_offset);
    world_pos.xz += wind_velocity * world_age;

    // Minecraft cloud noise

    float density = texture_soft(
        depthtex2,
        world_pos.xz * rcp(blockyCloudsSize * 5000),
        roundness
    );

    // Adjust density
    density *= linear_step(0.0, roundness, altitude_fraction);
    density *= linear_step(0.0, roundness, 1.0 - altitude_fraction);
    density = linear_step(sharpness, 1.0 - sharpness, density);

    return clamp01(density) * blockyCloudsDensity;
}

float blocky_clouds_optical_depth(
    vec3 ray_origin,
    vec3 ray_dir,
    float layer_altitude,
    float layer_offset,
    float dither,
    const uint step_count
) {
    const float step_growth = 1.2;

    float step_length = blocky_clouds_thickness / float(step_count); // m

    vec3 ray_pos = ray_origin;
    vec4 ray_step = vec4(ray_dir, 1.0) * step_length;

    float optical_depth = 0.0;

    for (uint i = 0u; i < step_count; ++i, ray_pos += ray_step.xyz) {
        ray_step *= step_growth;
        vec3 world_pos = ray_pos + ray_step.xyz * dither;
        float altitude_fraction = clamp01(
            (world_pos.y - layer_altitude) * rcp(blocky_clouds_thickness)
        );

        optical_depth
            += blocky_clouds_density(world_pos, altitude_fraction, layer_offset)
            * ray_step.w;
    }

    return optical_depth;
}

vec2 blocky_clouds_scattering(
    float density,
    float light_optical_depth,
    float sky_optical_depth,
    float ground_optical_depth,
    float step_transmittance,
    float cos_theta,
    float bounced_light
) {
    vec2 scattering = vec2(0.0);

    float scatter_amount = blocky_clouds_scattering_coeff;
    float extinct_amount = blocky_clouds_extinction_coeff;

    float powder = 5.0 * (1.0 - exp2(-8.0 * density));

    float scattering_integral_times_density
        = (1.0 - step_transmittance) / blocky_clouds_extinction_coeff;

    float phase = blocky_clouds_phase_single(cos_theta);
    vec3 phase_g = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + light_optical_depth));

    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatter_amount
            * exp(-extinct_amount * light_optical_depth) * phase;
        scattering.x += scatter_amount
            * exp(-extinct_amount * ground_optical_depth) * isotropic_phase
            * bounced_light;
        scattering.y += scatter_amount
            * exp(-extinct_amount * sky_optical_depth) * isotropic_phase;

        scatter_amount *= 0.5;
        extinct_amount *= 0.5;
        phase_g *= 0.8;

        phase = blocky_clouds_phase_multi(cos_theta, phase_g);
    }

    return scattering * scattering_integral_times_density * powder;
}

vec4 raymarch_blocky_clouds(
    vec3 world_start_pos,
    vec3 world_end_pos,
    bool sky,
    float layer_altitude,
    float dither
) {
    const uint primary_steps = blockyCloudsPrimarySteps;
    const uint lighting_steps = blockyCloudsLightingSteps;
    const float max_ray_length = 512;
    const float min_transmittance = 0.075;

    // ---------------------
    //   Raymarching Setup
    // ---------------------

    vec3 world_dir = world_end_pos - world_start_pos;

    float length_sq = length_squared(world_dir);
    float norm = inversesqrt(length_sq);
    float ray_length = length_sq * norm;
    world_dir *= norm;

    float distance_to_lower_plane
        = (layer_altitude - eyeAltitude) / world_dir.y;
    float distance_to_upper_plane
        = (layer_altitude + blocky_clouds_thickness - eyeAltitude)
        / world_dir.y;
    float distance_to_volume_start, distance_to_volume_end;

    if (eyeAltitude < layer_altitude) {
        // Below volume
        distance_to_volume_start = distance_to_lower_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? -1.0 : distance_to_upper_plane;
    } else if (eyeAltitude < layer_altitude + blocky_clouds_thickness) {
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

    if (distance_to_volume_end < 0.0) {
        return vec4(vec3(0.0), 1.0);
    }

    ray_length = sky ? distance_to_volume_end : ray_length;
    ray_length
        = clamp(ray_length - distance_to_volume_start, 0.0, max_ray_length);

    float step_length = ray_length * rcp(float(primary_steps));

    vec3 world_step = world_dir * step_length;
    vec3 world_pos = world_start_pos
        + world_dir * (distance_to_volume_start + step_length * dither);

    // ------------------
    //   Lighting Setup
    // ------------------

    vec3 scattering = vec3(0.0);
    float transmittance = 1.0;

    float lighting_dither
        = interleaved_gradient_noise(gl_FragCoord.xy, frameCounter);

    bool moonlit = sun_dir.y < -0.06;

    vec3 light_dir = moonlit ? moon_dir : sun_dir;

    vec3 light_color = moonlit ? moon_color : sun_color;
    light_color *= atmosphere_transmittance(light_dir.y, planet_radius + 1e3);
    light_color *= 1.5 - 0.5 * smoothstep(0.0, 0.15, abs(sun_dir.y));
    light_color *= 1.0 - rainStrength;

    float cos_theta = dot(world_dir, light_dir);
    float bounced_light = blockyCloudsBottomlight;

    mat2x3 light_colors = mat2x3(light_color, ambient_color);

    float distance_sum = 0.0;
    float distance_weight_sum = 0.0;

#ifdef blockyCloudsLayer2
    // Offset upper layer so it isn't identical to the below
    float layer_offset
        = abs(layer_altitude - blocky_clouds_altitude_l1) < 0.5 ? 3000.0 : 0.0;
#else
    const float layer_offset = 0.0;
#endif

    // --------------------
    //   Raymarching Loop
    // --------------------

    for (uint i = 0u; i < primary_steps; ++i, world_pos += world_step) {
        if (transmittance < min_transmittance) {
            break;
        }

        float altitude_fraction
            = (world_pos.y - layer_altitude) * rcp(blocky_clouds_thickness);

        float density
            = blocky_clouds_density(world_pos, altitude_fraction, layer_offset);
        if (density < eps) {
            continue;
        }

        float step_optical_depth
            = density * blocky_clouds_extinction_coeff * step_length;
        float step_transmittance = exp(-step_optical_depth);

        float light_optical_depth = blocky_clouds_optical_depth(
            world_pos,
            light_dir,
            layer_altitude,
            layer_offset,
            lighting_dither,
            lighting_steps
        );
        float ground_optical_depth
            = blocky_clouds_thickness * altitude_fraction;
        float sky_optical_depth
            = blocky_clouds_thickness * (1.0 - altitude_fraction);

        scattering
            += light_colors
            * blocky_clouds_scattering(
                   density,
                   light_optical_depth,
                   sky_optical_depth,
                   ground_optical_depth,
                   step_transmittance,
                   cos_theta,
                   bounced_light
            )
            * transmittance * mix(0.8, 1.25, cubic_smooth(altitude_fraction));

        transmittance *= step_transmittance;

        // Update distance to cloud
        float distance_to_sample = distance(cameraPosition, world_pos);
        distance_sum += distance_to_sample * density;
        distance_weight_sum += density;
    }

    // Remap the transmittance so that min_transmittance is 0
    float clouds_transmittance
        = linear_step(min_transmittance, 1.0, transmittance);

    // Distance fade
    float distance_fade = distance_weight_sum == 0.0
        ? 1.0
        : exp(-0.002 * distance_sum / distance_weight_sum);

#ifdef blockyCloudsAtmosphericScattering
    scattering
        *= distance_fade * mix(vec3(1.0, 0.66, 0.50), vec3(1.0), distance_fade);
#else
    scattering *= distance_fade;
#endif
    scattering *= blockyCloudsBrightness;

    transmittance = mix(1.0, transmittance, distance_fade);

    return vec4(scattering, transmittance);
}

#endif // INCLUDE_SKY_BLOCKY_CLOUDS

#endif
#endif

#if defined cloudShadows
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
#if LUSTER_D4_PASS == 1 && !defined useSeparateEntityDraws
    colortex3_clear = vec4(0.0);
#endif

    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Sample textures

    float depth = texelFetch(combined_depth_tex, texel, 0).x;
    vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
#if defined normalMapping || defined specularMapping
    vec4 gbuffer_data_1 = texelFetch(colortex2, texel, 0);
#endif
#if LUSTER_D4_PASS == 1 && !defined useSeparateEntityDraws
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

#ifdef blockyClouds
    vec3 world_start_pos = gbufferModelViewInverse[3].xyz + cameraPosition;
    vec3 world_end_pos = position_world;

    vec4 blocky_clouds = raymarch_blocky_clouds(
        world_start_pos,
        world_end_pos,
        depth == 1.0,
        blocky_clouds_altitude_l0,
        dither
    );

#ifdef blockyCloudsLayer2
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
#if defined WORLD_OVERWORLD && defined blockyClouds
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

#if LUSTER_D4_PASS == 1 && !defined useSeparateEntityDraws
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

#ifdef normalMapping
            normal = decode_unit_vector(gbuffer_data_1.xy);
#endif

#ifdef specularMapping
            vec4 specular_map = vec4(
                unpack_unorm_2x8(gbuffer_data_1.z),
                unpack_unorm_2x8(gbuffer_data_1.w)
            );
            decode_specular_map(specular_map, material, parallax_shadow);
#elif defined normalMapping
            parallax_shadow = gbuffer_data_1.z >= 0.5;
#endif

#ifdef LOD_MOD_ACTIVE
        }
#endif

        // Rain puddles

#if defined WORLD_OVERWORLD && defined rainPuddles
        if (wetness > eps && biome_may_rain > eps) {
            bool puddle = get_rain_puddles(
                position_world,
                flat_normal,
                light_levels,
                material.porosityAmount,
                material_mask,
                normal,
                material.albedo,
                material.f0,
                material.roughness,
                material.ssr_multiplier
            );
        }
#endif


#if defined WORLD_OVERWORLD && defined porosity
        if (wetness > eps && material.porosityAmount > eps) {
            material.albedo = apply_wet_porosity_darkening(
                material.albedo,
                material.porosityAmount,
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

#if defined WORLD_OVERWORLD && defined cloudShadows
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

#ifdef shadow
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
#ifdef shadowSsrt
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

#if defined pom && defined pomShadow \
    && (defined specularMapping || defined normalMapping)
            shadows *= float(!parallax_shadow);
#endif

        }
#else
        const vec3 shadows = vec3(1.0);
        const float shadow_distance_fade = 1.0;
        const float sss_depth = 0.0;
#endif


#ifdef hBasisSkylight
        vec3 sky_irradiance = hBasisIntensity
            * evaluate_h_basis_irradiance(h_sky, bent_normal);
#else
        vec3 sky_irradiance = hBasisIntensity * ambient_color;
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
#ifdef cloudShadows
            cloud_shadows,
#endif
#ifdef shadowSsrt
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


            // d5_sspt_accumulate and a-trous filtered by d6_sspt_filter.


            vec3 sspt_light = max0(texture(colortex17, uv).rgb);


            // diffuse modulation by albedo and metal diffuse amount. SSPT


            sspt_light *= material.albedo;
            sspt_light *= mix(1.0, metal_diffuse_amount, float(material.is_metal));


            // clouds physically, and traced sky arrives pre-darkened by the


            fragment_color += sspt_light;
        }
#endif


        // Specular highlight

#if defined WORLD_OVERWORLD || defined WORLD_END
        fragment_color
            += get_specular_highlight(material, NoL, NoV, NoH, LoV, LoH)
            * light_color * shadows * cloud_shadows * ao;
#endif
#else


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

#ifdef normalMapping
            normal = decode_unit_vector(gbuffer_data_1.xy);
#endif

#ifdef specularMapping
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

#if defined environmentReflections || defined skyReflections
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

#ifdef edgeHighlight
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

#ifdef borderFog
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

#ifdef blockyClouds
        fragment_color = fragment_color * blocky_clouds.w + blocky_clouds.xyz;
#else
        if (sqr(clouds_apparent_distance) < length_squared(position_view)) {
            fragment_color
                = fragment_color * clouds_and_aurora.w + clouds_and_aurora.xyz;
        }
#endif

        // Apply rainbows in front of terrain

#ifdef rainbows
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
