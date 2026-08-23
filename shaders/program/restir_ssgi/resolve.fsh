#version 400 compatibility
#include "/program/restir_ssgi/common.glsl"

uniform sampler2D colortex17;

layout(location = 0) out vec4 restir_resolve_out;

in vec2 uv;

void main() {
    ivec2 size = textureSize(colortex17, 0);
    ivec2 px = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    RestirSSGIReservoir r = restir_ssgi_unpack(texelFetch(colortex17, px, 0));
    if (!restir_ssgi_valid(r)) {
        restir_resolve_out = vec4(0.0);
        return;
    }

    vec3 Li = restir_ssgi_hit_radiance(r.hit_uv);
    float normalization = r.w_sum / max(r.m, 1.0);
    vec3 indirect = Li * normalization;

    vec3 albedo, normal;
    restir_ssgi_read_surface(px, albedo, normal);
    float depth = texelFetch(combined_depth_tex, px, 0).x;
    if (depth >= 0.999999) {
        restir_resolve_out = vec4(0.0);
        return;
    }

    // Store scene-referred indirect diffuse. The deferred shading path applies
    // the receiver albedo once when injecting this buffer.
    restir_resolve_out = vec4(max(indirect, vec3(0.0)), 1.0);
}
