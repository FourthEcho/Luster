#if !defined INCLUDE_PROGRAM_GI_UPSAMPLE
#define INCLUDE_PROGRAM_GI_UPSAMPLE
#include "/program/restir_ssgi/common.glsl"

uniform sampler2D colortex19;

vec3 restir_ssgi_bilinear() {
    vec2 p = uv * view_res * 0.5 - 0.5;
    ivec2 b = ivec2(floor(p));
    vec2 f = fract(p);
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    float center_depth = texelFetch(combined_depth_tex, ivec2(gl_FragCoord.xy), 0).x;
    float center_z = screen_to_view_space_depth(combined_projection_matrix_inverse, center_depth);
    ivec2 size = textureSize(colortex19, 0);
    for (int j = 0; j < 2; ++j) {
        for (int i = 0; i < 2; ++i) {
            ivec2 q = b + ivec2(i, j);
            if (q.x < 0 || q.y < 0 || q.x >= size.x || q.y >= size.y) continue;
            vec4 s = texelFetch(colortex19, q, 0);
            if (s.a <= 0.0) continue;
            float wxy = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
            ivec2 fq = clamp(q * 2, ivec2(0), ivec2(view_res) - ivec2(1));
            float z = screen_to_view_space_depth(combined_projection_matrix_inverse, texelFetch(combined_depth_tex, fq, 0).x);
            float w = wxy * exp(-abs(center_z - z) * 0.18);
            sum += s.rgb * w;
            wsum += w;
        }
    }
    return wsum > 1e-4 ? sum / wsum : vec3(0.0);
}

vec3 restir_ssgi_diffuse_wrapper(
    Material material,
    vec3 scene_pos,
    vec3 normal,
    vec3 flat_normal,
    vec3 bent_normal,
    vec3 shadows,
    vec2 light_levels,
    float ao,
    float ambient_sss,
    float sss_depth,
#ifdef CLOUD_SHADOWS
    float cloud_shadows,
#endif
    float shadow_distance_fade,
    float NoL,
    float NoV,
    float NoH,
    float LoV
) {
    vec3 base = get_diffuse_lighting(
        material, scene_pos, normal, flat_normal, bent_normal, shadows, light_levels,
        ao, ambient_sss, sss_depth,
#ifdef CLOUD_SHADOWS
        cloud_shadows,
#endif
        shadow_distance_fade, NoL, NoV, NoH, LoV
    );
    if (material.is_metal) return base;
    return base + restir_ssgi_bilinear() * material.albedo * rcp_pi * INDIRECT_LIGHTING_INTENSITY;
}

#define GET_DIFFUSE_LIGHTING_RESTIR_SSGI 1
#ifdef CLOUD_SHADOWS
#define get_diffuse_lighting(material, scene_pos, normal, flat_normal, bent_normal, shadows, light_levels, ao, ambient_sss, sss_depth, cloud_shadows, shadow_distance_fade, NoL, NoV, NoH, LoV) restir_ssgi_diffuse_wrapper(material, scene_pos, normal, flat_normal, bent_normal, shadows, light_levels, ao, ambient_sss, sss_depth, cloud_shadows, shadow_distance_fade, NoL, NoV, NoH, LoV)
#else
#define get_diffuse_lighting(material, scene_pos, normal, flat_normal, bent_normal, shadows, light_levels, ao, ambient_sss, sss_depth, shadow_distance_fade, NoL, NoV, NoH, LoV) restir_ssgi_diffuse_wrapper(material, scene_pos, normal, flat_normal, bent_normal, shadows, light_levels, ao, ambient_sss, sss_depth, shadow_distance_fade, NoL, NoV, NoH, LoV)
#endif

#endif
