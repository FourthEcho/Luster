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

layout(location = 0) out vec3 fog_transmittance;
layout(location = 1) out vec3 fog_scattering;

/* RENDERTARGETS: 6,7 */

in vec2 uv;

flat in vec3 ambient_color;
flat in vec3 light_color;

#if defined WORLD_OVERWORLD
#include "/lib/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler3D colortex0; // 3D worley noise
uniform sampler2D colortex1; // gbuffer data
uniform sampler2D colortex4; // sky map (SH projection helper needs it declared)
uniform sampler2D colortex8; // cloud shadow map

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#ifdef shadow
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
#ifdef shadowColor
uniform sampler2D shadowcolor0;
#endif
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 fogColor;

uniform float near;
uniform float far;

uniform float blindness;
uniform float darknessFactor;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float wetness;

uniform float sunAngle;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;

uniform float world_age;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float eye_skylight;
uniform float desert_sandstorm;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

// ------------
//   Includes
// ------------

#if defined WORLD_OVERWORLD
#include "/lib/fog/overworld/raymarched.glsl"
#endif

#if defined WORLD_END
#include "/lib/fog/endFogVl.glsl"
#endif

#include "/lib/fog/waterFogVl.glsl"
#include "/lib/fog/netherFogVl.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

void main() {
    ivec2 fog_texel = ivec2(gl_FragCoord.xy);
    ivec2 view_texel
        = ivec2(gl_FragCoord.xy * taau_render_scale * rcp(0.50));

    float depth0 = texelFetch(depthtex0, view_texel, 0).x;
    float depth1 = texelFetch(depthtex1, view_texel, 0).x;
    vec4 gbuffer_data_0 = texelFetch(colortex1, view_texel, 0);

#ifdef LOD_MOD_ACTIVE
    mat4 projection_matrix, projection_matrix_inverse;
    bool is_lod;
    float depth_lod = texelFetch(lod_depth_tex, view_texel, 0).x;

    if (depth0 == 1.0) {
        is_lod = true;
        depth0 = depth_lod;
        depth1 = depth_lod;
        projection_matrix = lod_projection_matrix;
        projection_matrix_inverse = lod_projection_matrix_inverse;
    } else {
        is_lod = false;
        projection_matrix = gbufferProjection;
        projection_matrix_inverse = gbufferProjectionInverse;
    }
#else
#define is_lod false
#define projection_matrix gbufferProjection
#define projection_matrix_inverse gbufferProjectionInverse
#endif

    float skylight = unpack_unorm_2x8(gbuffer_data_0.w).y;

    vec3 view_pos = screen_to_view_space(
        projection_matrix_inverse,
        vec3(uv, depth0),
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);
    vec3 world_pos = scene_pos + cameraPosition;

    vec3 view_back_pos = screen_to_view_space(vec3(uv, depth1), true);
    vec3 scene_back_pos = view_to_scene_space(view_back_pos);
    vec3 world_back_pos = scene_back_pos + cameraPosition;


    // Replaces the old white-noise noisetex tap.
    float dither = interleaved_gradient_noise(vec2(fog_texel), frameCounter);

    vec3 world_start_pos = gbufferModelViewInverse[3].xyz + cameraPosition;
    vec3 world_end_pos = world_pos;

    // Volumetric lighting

#if defined vl
    switch (isEyeInWater) {
        case 0:
#if defined WORLD_OVERWORLD
            mat2x3 fog = raymarch_air_fog(
                world_start_pos,
                world_end_pos,
                depth0 == 1.0,
                skylight,
                dither
            );
#elif defined WORLD_NETHER
            mat2x3 fog = raymarch_nether_fog(
                world_start_pos,
                world_end_pos,
                depth0 == 1.0,
                dither
            );
#elif defined WORLD_END
            mat2x3 fog = raymarch_end_fog(
                world_start_pos,
                world_end_pos,
                depth0 == 1.0,
                dither
            );
#endif

            fog_scattering = fog[0];
            fog_transmittance = fog[1];

            break;

        case 1:
            mat2x3 water_fog = raymarch_water_fog(
                world_start_pos,
                world_end_pos,
                depth0 == 1.0,
                dither
            );

            fog_scattering = water_fog[0];
            fog_transmittance = water_fog[1];

            break;

        default:
            fog_scattering = vec3(0.0);
            fog_transmittance = vec3(1.0);

            break;

        // Prevent potential game crash due to empty switch statement
        case -1:
            break;
    }
#else
    fog_scattering = vec3(0.0);
    fog_transmittance = vec3(1.0);
#endif

}
