#version 400 compatibility
#include "/include/global.glsl"
#include "/program/restir_ssgi/common.glsl"

uniform sampler2D colortex17;
uniform sampler2D colortex18;

layout(location = 0) out vec4 restir_temporal_out;

in vec2 uv;

void main() {
    ivec2 size = textureSize(colortex17, 0);
    ivec2 px = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec4 current = texelFetch(colortex17, px, 0);

    float depth = texelFetch(combined_depth_tex, px, 0).x;
    if (depth >= 0.999999) {
        restir_temporal_out = current;
        return;
    }

    RestirSSGIReservoir r = restir_ssgi_unpack(current);
    vec4 history = texture(colortex18, uv);
    RestirSSGIReservoir h = restir_ssgi_unpack(history);

    bool compatible = restir_ssgi_valid(h)
        && abs(h.hit_uv.x - r.hit_uv.x) < 0.35
        && abs(h.hit_uv.y - r.hit_uv.y) < 0.35;
    if (compatible) {
        float rand_value = restir_ssgi_hash(vec2(px) + 0.37, float(frameCounter));
        float history_weight = min(h.w_sum, 32.0);
        r = restir_ssgi_update(r, h.hit_uv, history_weight, min(h.m, 32.0), rand_value);
    }

    r.m = min(r.m, 32.0);
    r.w_sum = min(r.w_sum, 65504.0);
    restir_temporal_out = restir_ssgi_pack(r);
}
