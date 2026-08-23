#version 400 compatibility
#include "/include/global.glsl"
#include "/program/restir_ssgi/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;

layout(location = 0) out vec4 restir_candidate_out;

in vec2 uv;

void main() {
    ivec2 size = textureSize(colortex0, 0);
    ivec2 px = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    float depth = texelFetch(combined_depth_tex, px, 0).x;
    if (depth >= 0.999999 || depth < hand_depth) {
        restir_candidate_out = vec4(-1.0, -1.0, 0.0, 0.0);
        return;
    }

    vec3 albedo, normal;
    restir_ssgi_read_surface(px, albedo, normal);
    if (dot(normal, normal) < 0.5) {
        restir_candidate_out = vec4(-1.0, -1.0, 0.0, 0.0);
        return;
    }

    vec3 view_pos = screen_to_view_space(combined_projection_matrix_inverse, vec3(uv, depth), true);
    vec2 xi = restir_ssgi_hash2(vec2(px), float(frameCounter));
    vec3 ray = restir_ssgi_basis_sample(normalize(mat3(gbufferModelView) * normal), xi);
    vec2 hit_uv;
    float hit_depth;

    if (!restir_ssgi_trace(view_pos + ray * 0.02, ray, hit_uv, hit_depth)) {
        restir_candidate_out = vec4(-1.0, -1.0, 0.0, 0.0);
        return;
    }

    vec3 Li = restir_ssgi_hit_radiance(hit_uv);
    float cos_n = max(dot(normalize(mat3(gbufferModelView) * normal), ray), 0.0);
    float target = restir_ssgi_luma(Li) * max(cos_n, 0.02);
    restir_candidate_out = vec4(hit_uv, target, 1.0);
}
