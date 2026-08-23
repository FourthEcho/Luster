#version 400 compatibility
#include "/program/restir_ssgi/common.glsl"

uniform sampler2D colortex17;

layout(location = 0) out vec4 restir_spatial_out;

in vec2 uv;

void main() {
    ivec2 size = textureSize(colortex17, 0);
    ivec2 px = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    RestirSSGIReservoir r = restir_ssgi_unpack(texelFetch(colortex17, px, 0));
    if (!restir_ssgi_valid(r)) {
        restir_spatial_out = vec4(-1.0, -1.0, 0.0, 0.0);
        return;
    }

    vec3 center_albedo, center_normal;
    restir_ssgi_read_surface(px, center_albedo, center_normal);
    float center_depth = texelFetch(combined_depth_tex, px, 0).x;
    float center_z = screen_to_view_space_depth(combined_projection_matrix_inverse, center_depth);

    const ivec2 OFFSETS[4] = ivec2[4](ivec2(2,0), ivec2(-2,0), ivec2(0,2), ivec2(0,-2));
    for (int i = 0; i < 4; ++i) {
        ivec2 np = px + OFFSETS[i];
        if (np.x < 0 || np.y < 0 || np.x >= size.x || np.y >= size.y) continue;
        float nd = texelFetch(combined_depth_tex, np, 0).x;
        if (nd >= 0.999999) continue;
        float nz = screen_to_view_space_depth(combined_projection_matrix_inverse, nd);
        if (abs(nz - center_z) > 0.35 * max(1.0, abs(center_z))) continue;

        RestirSSGIReservoir neighbor = restir_ssgi_unpack(texelFetch(colortex17, np, 0));
        if (!restir_ssgi_valid(neighbor)) continue;
        float weight = neighbor.w_sum * 0.25;
        r = restir_ssgi_update(r, neighbor.hit_uv, weight, min(neighbor.m, 8.0), restir_ssgi_hash(vec2(px + OFFSETS[i]), float(frameCounter)));
    }

    r.m = min(r.m, 64.0);
    r.w_sum = min(r.w_sum, 65504.0);
    restir_spatial_out = restir_ssgi_pack(r);
}
