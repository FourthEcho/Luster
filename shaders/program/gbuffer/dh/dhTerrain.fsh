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

layout(
    location = 0
) out vec4 gbuffer_data_0; // albedo, block ID, flat normal, light levels

/* RENDERTARGETS: 1 */

#ifdef normalMapping
/* RENDERTARGETS: 1,2 */
#endif

#ifdef specularMapping
/* RENDERTARGETS: 1,2 */
#endif

in vec2 light_levels;
in vec3 scene_pos;
in vec3 normal;
in vec3 color;

flat in uint material_mask;

uniform vec2 view_pixel_size;
uniform int frameCounter;

#include "/lib/util/dithering.glsl"
#include "/lib/util/encoding.glsl"

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform vec3 cameraPosition;
uniform float far;

mat3 get_tbn_matrix(vec3 normal) {
    vec3 tangent = normal.y == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), normal));
    vec3 bitangent = normalize(cross(tangent, normal));
    return mat3(tangent, bitangent, normal);
}

void main() {
    // Clip to taau viewport

#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);
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

#ifdef noiseOnDhTerrain
    mat3 tbn = get_tbn_matrix(normal);
    vec3 world_pos = scene_pos + cameraPosition;
    vec2 noise_pos = (world_pos * tbn).xy;

    float noise = texture(noisetex, noise_pos.xy * 0.2).x;
    vec3 adjusted_color = clamp01(color * (noise * 0.25 + 0.85));
#else
    vec3 adjusted_color = color;
#endif

    gbuffer_data_0.x = pack_unorm_2x8(adjusted_color.rg);
    gbuffer_data_0.y = pack_unorm_2x8(
        adjusted_color.b,
        clamp01(float(material_mask) * rcp(255.0))
    );
    gbuffer_data_0.z = pack_unorm_2x8(encode_unit_vector(normal));
    gbuffer_data_0.w = pack_unorm_2x8(light_levels);
}
