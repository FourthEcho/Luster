#include "/include/global.glsl"

layout(location = 0) out vec3 irradiance_cache;

/* RENDERTARGETS: 17 */

in vec2 uv;

uniform sampler2D colortex0; // scene radiance used to build the cache
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform float far;

#include "/include/utility/space_conversion.glsl"

float cache_target_depth(float slice) {
    float u = (slice + 0.5) * 0.25;
    float log_far = log2(1.0 + max(far, 1.0));
    return exp2(u * log_far) - 1.0;
}

vec2 cache_atlas_local_uv(vec2 frag) {
    vec2 tile_res = view_res * 0.25;
    return fract(frag / max(tile_res, vec2(1.0)));
}

void main() {
    vec2 tile_res = view_res * 0.25;
    vec2 p = gl_FragCoord.xy;
    vec2 cell = floor(p / max(tile_res, vec2(1.0)));
    float slice = clamp(cell.x + cell.y * 2.0, 0.0, 3.0);
    vec2 local_uv = cache_atlas_local_uv(p);

    float target_z = cache_target_depth(slice);
    float weight_sum = 0.0;
    vec3 sum = vec3(0.0);
    vec2 step_uv = view_pixel_size * 2.0;

    const vec2 taps[9] = vec2[9](
        vec2(-1.0,-1.0), vec2(0.0,-1.0), vec2(1.0,-1.0),
        vec2(-1.0,0.0),  vec2(0.0,0.0),  vec2(1.0,0.0),
        vec2(-1.0,1.0),  vec2(0.0,1.0),  vec2(1.0,1.0)
    );

    for (int i = 0; i < 9; ++i) {
        vec2 sample_uv = clamp01(local_uv + taps[i] * step_uv);
        float depth = texture(depthtex0, sample_uv).x;
        if (depth >= 0.99999) continue;

        float sample_z = abs(screen_to_view_space_depth(gbufferProjectionInverse, depth));
        float z_delta = abs(log2(1.0 + sample_z) - log2(1.0 + target_z));
        float z_weight = exp2(-z_delta * 5.0);
        vec3 radiance = texture(colortex0, sample_uv).rgb;
        sum += radiance * z_weight;
        weight_sum += z_weight;
    }

    if (weight_sum > 1e-4) irradiance_cache = sum / weight_sum;
    else irradiance_cache = vec3(0.0);
}
