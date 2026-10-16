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

#if defined COLORWHEEL
layout(location = 0) out vec4 shadowcolor0_out;
#else
layout(location = 0) out vec3 shadowcolor0_out;
#endif

/* RENDERTARGETS: 0 */

in vec2 uv;

flat in uint material_mask;
flat in vec3 tint;


#ifdef waterCaustics
in vec3 scene_pos;
#endif

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
in vec2 atlas_tile_coord;
in float pom_view_distance;
flat in vec2 atlas_tile_offset;
flat in vec2 atlas_tile_scale;
flat in mat3 tbn;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D tex;
uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
uniform sampler2D normals;
#endif

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform float frameTimeCounter;
uniform float rainStrength;

uniform vec2 taa_offset;
uniform vec3 light_dir;

#include "/lib/material/water.glsl"
#include "/lib/fog/waterAbsorption.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
#include "/lib/material/parallax.glsl"
#endif

const float air_n = 1.000293; // for 0°C and 1 atm
const float water_n = 1.333; // for 20°C

const vec3 water_absorption_coeff
    = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
    * rec709_to_working_color;
const vec3 water_scattering_coeff = vec3(waterScattering);
const vec3 water_extinction_coeff
    = water_absorption_coeff + water_scattering_coeff;

const float distance_through_water = 5.0; // m

// using the built-in GLSL refract() seems to cause NaNs on Intel drivers, but
// with this function, which does the exact same thing, it's fine
vec3 refract_safe(vec3 I, vec3 N, float eta) {
    float NoI = dot(N, I);
    float k = 1.0 - eta * eta * (1.0 - NoI * NoI);
    if (k < 0.0) {
        return vec3(0.0);
    } else {
        return eta * I - (eta * NoI + sqrt(k)) * N;
    }
}

float get_water_caustics() {
#ifndef waterCaustics
    return 1.0;
#else
    // TBN matrix for a face pointing directly upwards
    const mat3 tbn = mat3(-1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0);

    const bool flowing_water = false;
    const vec2 flow_dir = vec2(0.0);

    vec3 world_pos = scene_pos + cameraPosition;

    vec2 coord = -world_pos.xz;
    vec3 normal
        = tbn
        * get_water_normal(
              world_pos,
              tbn[2],
              coord,
              flow_dir,
              1.0 - rainStrength,
              flowing_water
        );

    vec3 old_pos = world_pos;
    vec3 new_pos = world_pos
        + refract_safe(light_dir, normal, air_n / water_n)
            * (distance_through_water * waterCausticsIntensity);

    float old_area
        = length_squared(dFdx(old_pos)) * length_squared(dFdy(old_pos));
    float new_area
        = length_squared(dFdx(new_pos)) * length_squared(dFdy(new_pos));

    if (old_area == 0.0 || new_area == 0.0) {
        return 1.0;
    }

    return 0.25 * inversesqrt(old_area / new_area);
#endif
}

void main() {
#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
    gl_FragDepth = gl_FragCoord.z;
#endif

#ifndef COLORWHEEL
    if (material_mask == 1) { // Water
#if defined PROGRAM_SHADOW_WATER || defined PROGRAM_SHADOW_FALLBACK
        vec3 biome_water_color = srgb_eotf_inv(tint) * rec709_to_working_color;
        vec3 absorption_coeff = biome_water_coeff(biome_water_color);

        shadowcolor0_out = clamp(
            0.25 * exp(-absorption_coeff * distance_through_water)
                * get_water_caustics(),
            rcp(255.0) /* 0 is reserved */,
            1.0
        );
#endif
    } else {
#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)


        // the displaced UV, and push shadow depth away from the light by the

        vec2 pom_shadow_uv = uv;
        float pom_shadow_dz = 0.0;

        vec3 pom_tangent_dir = normalize(light_dir * tbn);
        bool pom_valid = pom_view_distance < pomDistance
            && dot(tbn[0], tbn[0]) > 0.5 // at_tangent actually supplied
            && pom_tangent_dir.z > 0.1; // surface faces the light

        if (pom_valid) {
            mat2 pom_uv_gradient = mat2(dFdx(uv), dFdy(uv));
            vec3 pom_prev_ray_pos;
            float pom_hit_depth;

            pom_shadow_uv = get_parallax_uv(
                pom_tangent_dir,
                pom_uv_gradient,
                pom_view_distance,
                0.0,
                pom_prev_ray_pos,
                pom_hit_depth
            );

            float pom_relief = get_pom_world_relief(
                pom_hit_depth,
                pom_view_distance
            );
            float pom_ray_dist = pom_relief * rcp(max(pom_tangent_dir.z, 0.15));
            pom_shadow_dz = 0.5 * shadowDepthScale
                * -shadowProjection[2][2] * pom_ray_dist;
        }

        vec4 base_color = textureLod(tex, pom_shadow_uv, 0);
#else
        vec4 base_color = textureLod(tex, uv, 0);
#endif
        if (base_color.a < 0.1) {
            discard;
        }
#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
        if (pom_shadow_dz == pom_shadow_dz) {
            gl_FragDepth = min(gl_FragCoord.z + max(pom_shadow_dz, 0.0), 0.999999);
        }
#endif

        shadowcolor0_out = mix(vec3(1.0), base_color.rgb * tint, clamp01(base_color.a * shadowColorIntensity));
        shadowcolor0_out
            = 0.25 * srgb_eotf_inv(shadowcolor0_out) * rec709_to_working_color;
        shadowcolor0_out *= step(base_color.a, 1.0 - rcp(255.0));

    }
#else
    vec4 base_color = textureLod(tex, uv, 0);
    vec2 lmcoord;
    float ao;
    vec4 overlayColor;

    clrwl_computeFragment(base_color, base_color, lmcoord, ao, overlayColor);
    base_color.rgb = mix(base_color.rgb, overlayColor.rgb, overlayColor.a);

    if (base_color.a < 0.1) {
        discard;
    }

    vec3 outColor = mix(vec3(1.0), base_color.rgb, base_color.a);
    outColor = 0.25 * srgb_eotf_inv(outColor) * rec709_to_working_color;
    outColor *= step(base_color.a, 1.0 - rcp(255.0));

    shadowcolor0_out = vec4(outColor, 1.0);
#endif
}
