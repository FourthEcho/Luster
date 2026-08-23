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

#ifdef INDIRECT_LIGHTING
#ifdef RESTIR_SSGI
vec3 restir_ssgi_indirect_contribution(vec3 albedo) {
    return restir_ssgi_bilinear() * albedo * rcp_pi * INDIRECT_LIGHTING_INTENSITY;
}
#endif
#endif

#endif
