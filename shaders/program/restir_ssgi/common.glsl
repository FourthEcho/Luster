#ifndef INCLUDE_PROGRAM_RESTIR_SSGI_COMMON
#define INCLUDE_PROGRAM_RESTIR_SSGI_COMMON

#include "/include/global.glsl"
#include "/include/utility/space_conversion.glsl"
#include "/include/utility/encoding.glsl"

struct RestirSSGIReservoir {
    vec2 hit_uv;
    float w_sum;
    float m;
};

float restir_ssgi_hash(vec2 p, float frame) {
    vec3 q = fract(vec3(p.xyx) * 0.1031 + frame * 0.0177);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

vec2 restir_ssgi_hash2(vec2 p, float frame) {
    return vec2(
        restir_ssgi_hash(p + vec2(0.0, 19.19), frame),
        restir_ssgi_hash(p + vec2(73.73, 7.11), frame + 11.0)
    );
}

RestirSSGIReservoir restir_ssgi_invalid() {
    RestirSSGIReservoir r;
    r.hit_uv = vec2(-1.0);
    r.w_sum = 0.0;
    r.m = 0.0;
    return r;
}

bool restir_ssgi_valid(RestirSSGIReservoir r) {
    return r.m > 0.0 && r.w_sum > 0.0
        && all(greaterThanEqual(r.hit_uv, vec2(0.0)))
        && all(lessThanEqual(r.hit_uv, vec2(1.0)));
}

RestirSSGIReservoir restir_ssgi_unpack(vec4 v) {
    RestirSSGIReservoir r;
    r.hit_uv = v.xy;
    r.w_sum = max(v.z, 0.0);
    r.m = max(v.w, 0.0);
    return r;
}

vec4 restir_ssgi_pack(RestirSSGIReservoir r) {
    return vec4(r.hit_uv, r.w_sum, r.m);
}

vec3 restir_ssgi_basis_sample(vec3 n, vec2 xi) {
    float phi = 6.28318530718 * xi.x;
    float cos_theta = sqrt(max(0.0, 1.0 - xi.y));
    float sin_theta = sqrt(max(0.0, xi.y));
    vec3 h = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 t = normalize(cross(h, n));
    vec3 b = cross(n, t);
    return normalize(t * (cos(phi) * sin_theta) + b * (sin(phi) * sin_theta) + n * cos_theta);
}

bool restir_ssgi_trace(vec3 origin_view, vec3 ray_view, out vec2 hit_uv, out float hit_depth) {
    hit_uv = vec2(-1.0);
    hit_depth = 1.0;
    const int STEPS = 18;
    const float RADIUS = 4.5;
    const float THICKNESS = 0.20;

    for (int i = 1; i <= STEPS; ++i) {
        float t = float(i) / float(STEPS) * RADIUS;
        vec3 p = origin_view + ray_view * t;
        vec3 s = view_to_screen_space(combined_projection_matrix, p, true);
        if (s.x <= 0.002 || s.x >= 0.998 || s.y <= 0.002 || s.y >= 0.998) break;

        ivec2 px = ivec2(s.xy * view_res * taau_render_scale);
        ivec2 size = textureSize(combined_depth_tex, 0);
        px = clamp(px, ivec2(0), size - ivec2(1));
        float d = texelFetch(combined_depth_tex, px, 0).x;
        if (d >= 0.999999) continue;

        vec3 hit = screen_to_view_space(combined_projection_matrix_inverse, vec3(s.xy, d), true);
        if (d < s.z && abs(hit.z - p.z) < THICKNESS + 0.08 * t) {
            hit_uv = s.xy;
            hit_depth = d;
            return true;
        }
    }
    return false;
}

vec3 restir_ssgi_hit_radiance(vec2 uv_hit) {
    ivec2 size = textureSize(colortex0, 0);
    ivec2 p = ivec2(uv_hit * vec2(size));
    p = clamp(p, ivec2(0), size - ivec2(1));
    return max(texelFetch(colortex0, p, 0).rgb, vec3(0.0));
}

float restir_ssgi_luma(vec3 v) {
    return max(dot(v, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
}

void restir_ssgi_read_surface(ivec2 texel, out vec3 albedo, out vec3 normal) {
    vec4 g = texelFetch(colortex1, texel, 0);
    mat4x2 data = mat4x2(unpack_unorm_2x8(g.x), unpack_unorm_2x8(g.y), unpack_unorm_2x8(g.z), unpack_unorm_2x8(g.w));
    albedo = vec3(data[0], data[1].x);
    normal = decode_unit_vector(data[2]);
}

RestirSSGIReservoir restir_ssgi_update(RestirSSGIReservoir r, vec2 uv_hit, float weight, float m, float random_value) {
    if (weight <= 0.0 || m <= 0.0) return r;
    float next_sum = r.w_sum + weight;
    if (random_value < weight / max(next_sum, 1e-6)) r.hit_uv = uv_hit;
    r.w_sum = next_sum;
    r.m += m;
    return r;
}

#endif
