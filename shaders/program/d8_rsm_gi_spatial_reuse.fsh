/*
--------------------------------------------------------------------------------

  Luster RSM GI — precomputed spatial reuse

  This follows Alpha Piscium's spatial-reuse resource model:
    * spatial_reuse0..3.bin are precomputed 256x256 RG8UI coordinate maps.
    * the .bin files are NOT reservoir storage; they only select reuse partners.
    * the GI result itself is accumulated with a weighted ReSTIR-style reservoir.

  The four maps are intentionally static resources so every frame uses the same
  low-discrepancy spatial pairing pattern without sampling a procedural kernel.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float near;
uniform float far;
uniform vec2 view_res;
uniform vec2 taa_offset;
uniform int frameCounter;

#include "/include/utility/encoding.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

#if defined RSM_GI && defined RSM_GI_SPATIAL_REUSE && defined SHADOW && defined WORLD_OVERWORLD

layout(location = 0) out vec4 spatial_reuse_result;
/* RENDERTARGETS: 21 */

in vec2 uv;

uniform sampler2D colortex17;
uniform sampler2D colortex1;

uniform usampler2D spatial_reuse0;
uniform usampler2D spatial_reuse1;
uniform usampler2D spatial_reuse2;
uniform usampler2D spatial_reuse3;

// Alpha Piscium-style static reuse textures.

const float rsm_gi_render_scale = 0.25;
const int REUSE_TEX_SIZE = 256;
const int REUSE_TEX_MASK = 255;

struct Reservoir {
    vec3 sample_value;
    float weight_sum;
    float selected_weight;
    float M;
};

vec3 get_flat_normal(ivec2 view_texel) {
    ivec2 max_texel = ivec2(view_res) - ivec2(1);
    vec4 g = texelFetch(colortex1, clamp(view_texel, ivec2(0), max_texel), 0);
    return decode_unit_vector(unpack_unorm_2x8(g.z));
}

float gi_luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void reservoir_reset(out Reservoir r, vec3 initial_sample) {
    r.sample_value = initial_sample;
    r.weight_sum = 1.0;
    r.selected_weight = 1.0;
    r.M = 1.0;
}

void reservoir_update(inout Reservoir r, vec3 candidate, float candidate_weight, float random_u) {
    float w = max(candidate_weight, 0.0);
    if (w <= eps) return;

    float new_weight_sum = r.weight_sum + w;
    r.M += 1.0;

    if (random_u < w / max(new_weight_sum, eps)) {
        r.sample_value = candidate;
        r.selected_weight = w;
    }

    r.weight_sum = new_weight_sum;
}

float reservoir_estimate_scale(Reservoir r) {
    return r.weight_sum / max(r.M * r.selected_weight, eps);
}

float reservoir_random(ivec2 texel, int stage, int candidate_id) {
    vec2 seed = vec2(texel)
        + vec2(float(stage) * 53.0 + float(candidate_id) * 17.0,
               float(frameCounter) * 0.75487766 + float(stage) * 19.0);
    // The pack's random.glsl exposes hash1(float), while the vec2 overload
    // is intentionally disabled there. Fold the 2D seed to one scalar.
    float p = dot(seed, vec2(127.1, 311.7));
    return hash1(p);
}

float reuse_weight(
    vec4 center,
    vec4 candidate,
    vec3 center_normal,
    vec3 candidate_normal,
    float depth_sigma,
    float normal_power,
    float luma_sigma,
    float spatial_weight
) {
    if (candidate.a >= 1.0) return 0.0;

    float center_z = screen_to_view_space_depth(gbufferProjectionInverse, center.a);
    float candidate_z = screen_to_view_space_depth(gbufferProjectionInverse, candidate.a);

    float depth_scale = max(abs(center_z), 0.5);
    float depth_weight = exp2(-depth_sigma * abs(center_z - candidate_z) / depth_scale);

    float normal_dot = clamp01(dot(center_normal, candidate_normal));
    float normal_weight = pow(normal_dot, max(normal_power, 1.0));

    float center_luma = gi_luma(center.rgb);
    float candidate_luma = gi_luma(candidate.rgb);
    float ratio = (candidate_luma + 0.001) / (center_luma + 0.001);
    float luminance_weight = exp2(-luma_sigma * abs(log2(max(ratio, 0.001))));

    return depth_weight * normal_weight * luminance_weight * spatial_weight;
}

ivec2 reuse_partner(ivec2 texel, usampler2D reuse_tex) {
    ivec2 coord = texel & ivec2(REUSE_TEX_MASK);
    uvec4 packed = texelFetch(reuse_tex, coord, 0);
    ivec2 local_partner = ivec2(int(packed.x), int(packed.y));
    ivec2 local_origin = texel - coord;
    return local_origin + local_partner;
}

void add_reuse_candidate(
    inout Reservoir r,
    vec4 center,
    vec3 center_normal,
    ivec2 center_texel,
    ivec2 candidate_texel,
    ivec2 gi_buffer_max,
    int stage,
    int candidate_id,
    float stage_radius
) {
    candidate_texel = clamp(candidate_texel, ivec2(0), gi_buffer_max);
    vec4 candidate = texelFetch(colortex17, candidate_texel, 0);
    if (candidate.a >= 1.0) return;

    ivec2 candidate_view_texel = ivec2(
        vec2(candidate_texel) * (taau_render_scale / rsm_gi_render_scale)
    );
    vec3 candidate_normal = get_flat_normal(candidate_view_texel);

    vec2 delta = vec2(candidate_texel - center_texel);
    float distance_sq = max(dot(delta, delta), 1.0);
    float spatial_weight = exp2(-distance_sq / max(stage_radius * stage_radius, 1.0));

    float weight = reuse_weight(
        center,
        candidate,
        center_normal,
        candidate_normal,
        1.25 + float(stage) * 0.35,
        8.0 + float(stage) * 2.0,
        0.75 + float(stage) * 0.15,
        spatial_weight
    );

    if (candidate_texel == center_texel) weight = 1.0;
    reservoir_update(r, candidate.rgb, weight, reservoir_random(center_texel, stage, candidate_id));
}

Reservoir do_reuse_stage(
    vec4 center,
    vec3 center_normal,
    ivec2 texel,
    ivec2 gi_buffer_max,
    int stage,
    usampler2D reuse_tex,
    float stage_radius
) {
    Reservoir r;
    reservoir_reset(r, center.rgb);

    // Center sample anchors every stage.
    add_reuse_candidate(r, center, center_normal, texel, texel, gi_buffer_max, stage, 0, stage_radius);

    // The .bin texture selects the primary spatial partner for this stage.
    ivec2 partner = reuse_partner(texel, reuse_tex);
    add_reuse_candidate(r, center, center_normal, texel, partner, gi_buffer_max, stage, 1, stage_radius);

    // Two cheap adjacent candidates around the precomputed partner provide a
    // small local cluster while keeping the .bin resource as the selection map.
    add_reuse_candidate(r, center, center_normal, texel, partner + ivec2(1, 0), gi_buffer_max, stage, 2, stage_radius);
    add_reuse_candidate(r, center, center_normal, texel, partner + ivec2(0, 1), gi_buffer_max, stage, 3, stage_radius);

    return r;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 gi_buffer_max = max(ivec2(0), ivec2(view_res * rsm_gi_render_scale) - ivec2(1));
    texel = clamp(texel, ivec2(0), gi_buffer_max);

    vec4 center = texelFetch(colortex17, texel, 0);
    if (center.a >= 1.0) {
        spatial_reuse_result = center;
        return;
    }

    ivec2 view_texel = ivec2(vec2(texel) * (taau_render_scale / rsm_gi_render_scale));
    vec3 center_normal = get_flat_normal(view_texel);

    Reservoir r0 = do_reuse_stage(center, center_normal, texel, gi_buffer_max, 0, spatial_reuse0, 8.0);
    vec3 stage0 = r0.sample_value * reservoir_estimate_scale(r0);

    vec4 stage1_input = vec4(stage0, center.a);
    Reservoir r1 = do_reuse_stage(stage1_input, center_normal, texel, gi_buffer_max, 1, spatial_reuse1, 12.0);
    vec3 stage1 = r1.sample_value * reservoir_estimate_scale(r1);

    vec4 stage2_input = vec4(stage1, center.a);
    Reservoir r2 = do_reuse_stage(stage2_input, center_normal, texel, gi_buffer_max, 2, spatial_reuse2, 16.0);
    vec3 stage2 = r2.sample_value * reservoir_estimate_scale(r2);

    vec4 stage3_input = vec4(stage2, center.a);
    Reservoir r3 = do_reuse_stage(stage3_input, center_normal, texel, gi_buffer_max, 3, spatial_reuse3, 20.0);
    vec3 stage3 = r3.sample_value * reservoir_estimate_scale(r3);

    // Keep the reuse estimator bounded relative to the original GI sample.
    vec3 lo = center.rgb * 0.125;
    vec3 hi = center.rgb * 8.0 + vec3(0.001);
    spatial_reuse_result = vec4(clamp(stage3, lo, hi), center.a);
}

#endif
