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

#if !defined INCLUDE_FOG_SIMPLE_FOG
#define INCLUDE_FOG_SIMPLE_FOG

#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/fog/waterAbsorption.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/sky/projection.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

const float lava_fog_start = 0.33;
const float lava_fog_density = 1.0;
const vec3 lava_fog_color = gamut_expand(from_display(vec3(0.839, 0.373, 0.075))) * 2.0;

const float snow_fog_start = 0.5;
const float snow_fog_density = 1.0;
const vec3 snow_fog_color = gamut_expand(from_display(vec3(0.957, 0.988, 0.988))) * 0.3;

const float cave_fog_start = 1.0;
// caveFogIntensity scales the cave fog density. At 1.0 it matches the
// previous hardcoded density of 0.0033; at 0 cave fog is invisible.
const float cave_fog_density = 0.0033 * caveFogIntensity;
const vec3 cave_fog_color = vec3(0.033);

const float blindness_fog_start = 2.0;
const float blindness_fog_density = 1.0;

const float darkness_fog_start = 8.0;
const float darkness_fog_density = 2.0;


float nether_fog_density(vec3 world_pos) {
    const float falloff_start = 64.0;
    const float falloff_half_life = 7.0;
    const float mul = -rcp(falloff_half_life);
    const float add = -mul * falloff_start;
    float density = exp2(min(world_pos.y * mul + add, 0.0));
    density *= linear_step(0.0, 64.0, world_pos.y);
    return density;
}

vec3 get_nether_fog_color() {
#ifdef netherUseBiomeColor
    vec3 color = srgb_eotf_inv(clamp(fogColor, 0.0, 1.0)) * rec709_to_working_color;
    color /= max(dot(color, luminance_weights), eps);
    return mix(vec3(1.0), color, netherS);
#else
    return gamut_expand(from_display(vec3(netherR, netherG, netherB)));
#endif
}

float spherical_fog(
    float view_dist,
    float fog_start_distance,
    float fog_density
) {
    return exp2(-fog_density * max0(view_dist - fog_start_distance));
}

float border_fog(vec3 scene_pos, vec3 world_dir) {
#ifndef LOD_MOD_ACTIVE
    float fog = cubic_length(scene_pos.xz) / far;


    fog = exp2(-(8.0 * borderFogIntensity) * pow8(fog));
    float vertical_cutoff_distance = far;
#else
    float fog = length(scene_pos.xz) / float(lod_render_distance);
    fog = exp2(-(2.4 * borderFogIntensity) * sqr(fog));
#endif

#if defined WORLD_OVERWORLD || defined WORLD_END
    fog = mix(fog, 1.0, 0.75 * dampen(linear_step(0.0, 0.2, world_dir.y)));
#endif

#ifndef LOD_MOD_ACTIVE
    float vertical_cutoff = linear_step(-vertical_cutoff_distance, -vertical_cutoff_distance + 16.0, scene_pos.y);
    fog *= vertical_cutoff;
#endif

    return fog;
}

vec4 common_fog(float view_dist, const bool sky, vec3 scene_pos) {
    vec4 fog = vec4(vec3(0.0), 1.0);

    // Lava fog
    float lava_fog = spherical_fog(
        view_dist,
        lava_fog_start,
        lava_fog_density * float(isEyeInWater == 2)
    );
    fog.rgb += lava_fog_color - lava_fog_color * lava_fog;
    fog.a *= lava_fog;

    // Powdered snow fog
    float snow_fog = spherical_fog(
        view_dist,
        snow_fog_start,
        snow_fog_density * float(isEyeInWater == 3)
    );
    fog.rgb += snow_fog_color - snow_fog_color * snow_fog;
    fog.a *= snow_fog;

    // Blindness fog
    fog *= mix(
        1.0,
        spherical_fog(
            view_dist,
            blindness_fog_start,
            blindness * blindness_fog_density
        ),
        blindness
    );

    // Darkness fog
    fog *= mix(
        1.0,
        spherical_fog(
            view_dist,
            darkness_fog_start,
            darknessFactor * darkness_fog_density
        ),
        darknessFactor
    );

#if defined WORLD_OVERWORLD && defined caveFog
    // Cave fog
    float cave_fog = spherical_fog(
        view_dist,
        cave_fog_start,
        cave_fog_density * biome_cave * float(!sky)
    );
    fog.rgb += cave_fog_color - cave_fog_color * cave_fog;
    fog.a *= cave_fog;
#endif

#if defined WORLD_NETHER && !defined vl
    float nether_fog = spherical_fog(
        view_dist,
        0.0,
        0.01 * nether_fog_density(scene_pos + cameraPosition)
    );
    vec3 nether_color = get_nether_fog_color() * netherI;
    fog.rgb += nether_color - nether_color * nether_fog;
    fog.a *= nether_fog;
#endif

    return fog;
}

// Calculates the alpha component only
// Water fog

const vec3 water_absorption_coeff
    = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
    * rec709_to_working_color;

// Simple water fog applied behind water or when volumetric fog is disabled
mat2x3 water_fog_simple(
    vec3 light_color,
    vec3 ambient_color,
    vec3 absorption_coeff,
    vec2 light_levels,
    float dist,
    float LoV,
    float sss_depth
) {
    float skylight_factor = cube(light_levels.y);

    vec3 scattering_coeff = vec3(waterScattering);
    vec3 extinction_coeff = scattering_coeff + absorption_coeff;

    // Multiple scattering approximation from Jessie
    vec3 scattering_albedo = scattering_coeff / extinction_coeff;
    vec3 multiple_scattering_factor = 0.84 * scattering_albedo;
    vec3 multiple_scattering_energy
        = multiple_scattering_factor / (1.0 - multiple_scattering_factor);

    // Minimum distance so that water is always easily visible
    dist = max(dist, 2.0 - 1.0 * skylight_factor);

    vec3 light_ambient = ambient_color * light_levels.y;
    light_ambient
        += 1.41 * blocklight_color * blocklight_scale * sqr(light_levels.x);

    vec3 transmittance = exp(-extinction_coeff * dist);

    vec3 scattering = light_color * exp(-extinction_coeff * sss_depth)
        * smoothstep(0.0, 0.25, light_levels.y); // direct lighting
    scattering *= 0.7 * henyey_greenstein_phase(LoV, 0.4)
        + 0.3 * isotropic_phase; // phase function for direct lighting
    scattering += light_ambient * isotropic_phase; // ambient lighting
    scattering *= (1.0 - transmittance) * scattering_coeff
        / extinction_coeff; // scattering integral
    scattering *= 1.0 + multiple_scattering_energy; // multiple scattering

    return mat2x3(scattering, transmittance);
}

#endif // INCLUDE_FOG_SIMPLE_FOG
