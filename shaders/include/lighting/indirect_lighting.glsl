#if !defined INCLUDE_LIGHTING_INDIRECT
#define INCLUDE_LIGHTING_INDIRECT

// ============================================================================
// Luster Indirect Lighting
// OpenGL 4.1-safe core: fragment shaders + framebuffer textures only.
// ============================================================================

#ifndef INDIRECT_SAMPLES
#define INDIRECT_SAMPLES 8
#endif
#ifndef INDIRECT_RADIUS
#define INDIRECT_RADIUS 2.25
#endif
#ifndef INDIRECT_INTENSITY
#define INDIRECT_INTENSITY 0.85
#endif
const float indirect_depth_rejection = 0.35;
const float indirect_normal_rejection = 0.15;
const float indirect_cache_strength = 0.55;
const float indirect_history_strength = 0.75;
#ifndef INDIRECT_SECOND_BOUNCE_ENERGY
#define INDIRECT_SECOND_BOUNCE_ENERGY 0.55
#endif
#ifndef INDIRECT_THIRD_BOUNCE_ENERGY
#define INDIRECT_THIRD_BOUNCE_ENERGY 0.30
#endif
#if defined COLORED_LIGHTS && !defined INDIRECT_LPV_INTENSITY
#define INDIRECT_LPV_INTENSITY 0.70
#endif

const float indirect_tau = 6.28318530718;

vec3 indirect_reconstruct_view_position(vec2 coord, float depth) {
    return screen_to_view_space(gbufferProjectionInverse, vec3(coord, depth), true);
}

vec3 indirect_reconstruct_normal(vec2 coord) {
    ivec2 texel = ivec2(coord * view_res);
    ivec2 max_texel = ivec2(view_res) - ivec2(1);

    ivec2 xl = clamp(texel + ivec2(-1, 0), ivec2(0), max_texel);
    ivec2 xr = clamp(texel + ivec2( 1, 0), ivec2(0), max_texel);
    ivec2 yd = clamp(texel + ivec2( 0,-1), ivec2(0), max_texel);
    ivec2 yu = clamp(texel + ivec2( 0, 1), ivec2(0), max_texel);

    float dc = texelFetch(depthtex0, texel, 0).x;
    float dl = texelFetch(depthtex0, xl, 0).x;
    float dr = texelFetch(depthtex0, xr, 0).x;
    float dd = texelFetch(depthtex0, yd, 0).x;
    float du = texelFetch(depthtex0, yu, 0).x;

    if (dc >= 1.0) return vec3(0.0, 0.0, 1.0);

    vec3 pl = indirect_reconstruct_view_position((vec2(xl) + 0.5) / view_res, dl);
    vec3 pr = indirect_reconstruct_view_position((vec2(xr) + 0.5) / view_res, dr);
    vec3 pd = indirect_reconstruct_view_position((vec2(yd) + 0.5) / view_res, dd);
    vec3 pu = indirect_reconstruct_view_position((vec2(yu) + 0.5) / view_res, du);

    vec3 dx = pr - pl;
    vec3 dy = pu - pd;
    vec3 n = normalize(cross(dy, dx));
    vec3 p = indirect_reconstruct_view_position(coord, dc);
    if (dot(n, -p) < 0.0) n = -n;
    return n;
}

float indirect_depth_weight(float a, float b, float scale) {
    if (a >= 1.0 || b >= 1.0) return 0.0;
    float za = abs(screen_to_view_space_depth(gbufferProjectionInverse, a));
    float zb = abs(screen_to_view_space_depth(gbufferProjectionInverse, b));
    float dz = abs(za - zb);
    return exp2(-indirect_depth_rejection * dz * rcp(max(scale, 0.25)));
}

vec2 indirect_cache_uv(vec2 uv_in, float slice) {
    float s = clamp(slice, 0.0, 3.0);
    float sx = mod(s, 2.0);
    float sy = floor(s * 0.5);
    return (uv_in + vec2(sx, sy)) * 0.5;
}

vec3 indirect_sample_cache(vec2 uv_in, float view_depth) {
    float denom = max(log2(1.0 + max(far, 1.0)), 1.0);
    float z = clamp(log2(1.0 + max(view_depth, 0.0)) / denom, 0.0, 1.0);
    float slice_f = z * 3.0;
    float slice0 = floor(slice_f);
    float slice1 = min(slice0 + 1.0, 3.0);
    float t = fract(slice_f);
    vec3 a = texture(colortex7, indirect_cache_uv(uv_in, slice0)).rgb;
    vec3 b = texture(colortex7, indirect_cache_uv(uv_in, slice1)).rgb;
    return mix(a, b, t);
}

vec3 indirect_gather_scene(
    vec2 uv_in,
    vec3 receiver_view_pos,
    vec3 receiver_normal,
    vec3 receiver_albedo,
    vec2 texel_scale,
    out float sample_weight
) {
    const vec2 taps[12] = vec2[12](
        vec2( 0.9238795,  0.3826834), vec2( 0.3826834,  0.9238795),
        vec2(-0.3826834,  0.9238795), vec2(-0.9238795,  0.3826834),
        vec2(-0.9238795, -0.3826834), vec2(-0.3826834, -0.9238795),
        vec2( 0.3826834, -0.9238795), vec2( 0.9238795, -0.3826834),
        vec2( 0.7071068,  0.7071068), vec2(-0.7071068, 0.7071068),
        vec2(-0.7071068,-0.7071068), vec2( 0.7071068,-0.7071068)
    );

    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;
    float current_depth = texture(depthtex0, uv_in).x;
    float radius = INDIRECT_RADIUS * max(1.0, length(receiver_view_pos) * 0.015);

    float angle = indirect_tau * fract(float(frameCounter) * 0.61803398875);
    mat2 rotation = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

    for (int i = 0; i < INDIRECT_SAMPLES; ++i) {
        vec2 dir = rotation * taps[i];
        float scale = radius * (0.65 + 0.35 * fract(float(i) * 0.61803398875));
        vec2 sample_uv = clamp01(uv_in + dir * texel_scale * scale);
        float sample_depth = texture(depthtex0, sample_uv).x;
        if (sample_depth >= 0.99999) continue;

        vec3 sample_view = indirect_reconstruct_view_position(sample_uv, sample_depth);
        vec3 to_source = normalize(sample_view - receiver_view_pos);
        vec3 source_to_receiver = -to_source;
        vec3 source_normal = indirect_reconstruct_normal(sample_uv);
        float receiver_cos = max0(dot(receiver_normal, to_source));
        float source_cos = max0(dot(source_normal, source_to_receiver));
        if (receiver_cos <= 0.001 || source_cos <= 0.001) continue;

        float distance = length(sample_view - receiver_view_pos);
        float radial = max0(1.0 - distance / max(radius * 1.5, 0.001));
        radial *= radial;
        float depth_weight = indirect_depth_weight(current_depth, sample_depth, max(distance, 0.25));
        float normal_weight = smoothstep(0.0, 1.0,
            max0(dot(receiver_normal, source_normal) - indirect_normal_rejection));
        float weight = receiver_cos * source_cos * radial * depth_weight
            * mix(1.0, normal_weight, 0.75);
        if (weight <= 1e-5) continue;

        vec3 source_radiance = texture(colortex0, sample_uv).rgb;
        source_radiance *= receiver_albedo;
        sum += source_radiance * weight;
        weight_sum += weight;
    }

    sample_weight = weight_sum;
    if (weight_sum > 1e-5) sum *= rcp(weight_sum);
    return sum;
}

vec3 indirect_gather_bounce2(
    vec2 uv_in,
    vec3 receiver_view_pos,
    vec3 receiver_normal,
    vec3 receiver_albedo,
    out float sample_weight
) {
    const vec2 taps[12] = vec2[12](
        vec2( 0.9238795,  0.3826834), vec2( 0.3826834,  0.9238795),
        vec2(-0.3826834,  0.9238795), vec2(-0.9238795,  0.3826834),
        vec2(-0.9238795, -0.3826834), vec2(-0.3826834, -0.9238795),
        vec2( 0.3826834, -0.9238795), vec2( 0.9238795, -0.3826834),
        vec2( 0.7071068, 0.7071068), vec2(-0.7071068, 0.7071068),
        vec2(-0.7071068,-0.7071068), vec2( 0.7071068,-0.7071068)
    );

    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;
    float current_depth = texture(depthtex0, uv_in).x;
    float radius = INDIRECT_RADIUS;
    float angle = indirect_tau * fract(float(frameCounter + 17) * 0.754877666);
    mat2 rotation = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

    for (int i = 0; i < INDIRECT_SAMPLES; ++i) {
        vec2 dir = rotation * taps[i];
        float scale = radius * (0.60 + 0.40 * fract(float(i) * 0.754877666));
        vec2 sample_uv = clamp01(uv_in + dir * view_pixel_size * scale);
        float sample_depth = texture(depthtex0, sample_uv).x;
        if (sample_depth >= 0.99999) continue;

        vec3 sample_view = indirect_reconstruct_view_position(sample_uv, sample_depth);
        vec3 to_source = normalize(sample_view - receiver_view_pos);
        vec3 source_to_receiver = -to_source;
        vec3 source_normal = indirect_reconstruct_normal(sample_uv);
        float receiver_cos = max0(dot(receiver_normal, to_source));
        float source_cos = max0(dot(source_normal, source_to_receiver));
        if (receiver_cos <= 0.001 || source_cos <= 0.001) continue;

        float distance = length(sample_view - receiver_view_pos);
        float radial = max0(1.0 - distance / max(radius * 1.5, 0.001));
        radial *= radial;
        float depth_weight = indirect_depth_weight(current_depth, sample_depth, max(distance, 0.25));
        float normal_weight = smoothstep(0.0, 1.0,
            max0(dot(receiver_normal, source_normal) - indirect_normal_rejection));
        float weight = receiver_cos * source_cos * radial * depth_weight
            * mix(1.0, normal_weight, 0.75);
        if (weight <= 1e-5) continue;

        vec3 source_radiance = texture(colortex2, sample_uv).rgb;
        source_radiance *= receiver_albedo;
        sum += source_radiance * weight;
        weight_sum += weight;
    }

    sample_weight = weight_sum;
    if (weight_sum > 1e-5) sum *= rcp(weight_sum);
    return sum;
}

vec3 indirect_gather_bounce3(
    vec2 uv_in,
    vec3 receiver_view_pos,
    vec3 receiver_normal,
    vec3 receiver_albedo,
    out float sample_weight
) {
    const vec2 taps[12] = vec2[12](
        vec2( 0.9238795,  0.3826834), vec2( 0.3826834,  0.9238795),
        vec2(-0.3826834,  0.9238795), vec2(-0.9238795, 0.3826834),
        vec2(-0.9238795,-0.3826834), vec2(-0.3826834,-0.9238795),
        vec2( 0.3826834,-0.9238795), vec2( 0.9238795,-0.3826834),
        vec2( 0.7071068, 0.7071068), vec2(-0.7071068,0.7071068),
        vec2(-0.7071068,-0.7071068), vec2( 0.7071068,-0.7071068)
    );

    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;
    float current_depth = texture(depthtex0, uv_in).x;
    float radius = INDIRECT_RADIUS * 1.25;
    float angle = indirect_tau * fract(float(frameCounter + 43) * 0.569840296);
    mat2 rotation = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

    for (int i = 0; i < INDIRECT_SAMPLES; ++i) {
        vec2 dir = rotation * taps[i];
        float scale = radius * (0.60 + 0.40 * fract(float(i) * 0.569840296));
        vec2 sample_uv = clamp01(uv_in + dir * view_pixel_size * scale);
        float sample_depth = texture(depthtex0, sample_uv).x;
        if (sample_depth >= 0.99999) continue;

        vec3 sample_view = indirect_reconstruct_view_position(sample_uv, sample_depth);
        vec3 to_source = normalize(sample_view - receiver_view_pos);
        vec3 source_to_receiver = -to_source;
        vec3 source_normal = indirect_reconstruct_normal(sample_uv);
        float receiver_cos = max0(dot(receiver_normal, to_source));
        float source_cos = max0(dot(source_normal, source_to_receiver));
        if (receiver_cos <= 0.001 || source_cos <= 0.001) continue;

        float distance = length(sample_view - receiver_view_pos);
        float radial = max0(1.0 - distance / max(radius * 1.5, 0.001));
        radial *= radial;
        float depth_weight = indirect_depth_weight(current_depth, sample_depth, max(distance, 0.25));
        float normal_weight = smoothstep(0.0, 1.0,
            max0(dot(receiver_normal, source_normal) - indirect_normal_rejection));
        float weight = receiver_cos * source_cos * radial * depth_weight
            * mix(1.0, normal_weight, 0.75);
        if (weight <= 1e-5) continue;

        vec3 source_radiance = texture(colortex1, sample_uv).rgb;
        source_radiance *= receiver_albedo;
        sum += source_radiance * weight;
        weight_sum += weight;
    }

    sample_weight = weight_sum;
    if (weight_sum > 1e-5) sum *= rcp(weight_sum);
    return sum;
}

#endif
