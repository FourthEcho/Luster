#if !defined INCLUDE_PROGRAM_GI_SHARED
#define INCLUDE_PROGRAM_GI_SHARED

// ============================================================================
//  Indirect Lighting shared helpers (Mac-compatible).
//
//  No compute shaders, no atomics, no subgroups, no vendor extensions.
//  Everything runs as full-screen fragment passes at quarter res.
//
//  This file is included by:
//    program/gi/bounce.fsh    (1 cosine ray, sample previous-bounce output)
//    program/gi/accumulate.fsh (temporal EMA + disocclusion reject)
//    program/gi/filter.fsh     (A-Trous SVGF)
//
//  Buffer convention (see include/buffers.glsl):
//    colortex17 : RGBA16F, q-res, cleared every frame — bounce ping-pong
//                 (rgb = bounce-N albedo-modulated radiance, a = unused)
//    colortex18 : RGBA16F, q-res, persistent  — accumulated history
//                 (rgb = accumulated radiance, a = pixel age / sample count)
//    colortex19 : RG16F,   q-res, persistent  — variance / mean luma (A_SVGF)
// ============================================================================

#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/space_conversion.glsl"

// Quarter-res render scale used by every GI pass. AO and fog already use
// 0.5, so we keep parity to share the downsampled gbuffer lookups.
const float gi_render_scale = 0.5;

// Linearise the OpenGL window-space depth to view-space z. Used by the
// raymarcher and by the bilateral filter's depth weight.
float gi_linearize_depth(float depth) {
    return linearize_depth(near, combined_far, depth);
}

// Map a quarter-res gl_FragCoord to the matching full-res texel. Used to
// fetch gbuffer data (colortex1/2) at the corresponding pixel.
ivec2 gi_full_res_texel() {
    return ivec2(gl_FragCoord.xy * (taau_render_scale / gi_render_scale));
}

// Fetch scene normal at the current quarter-res pixel. Luster stores the
// octahedrally-encoded flat normal in colortex1.zw (gbuffer_data_0.z, .w
// together encode it via pack_unorm_2x8). When normal mapping is off the
// encoded value is the surface normal; when on it is the flat normal.
vec3 gi_read_scene_normal(ivec2 texel) {
    vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
    vec2 packed = unpack_unorm_2x8(gbuffer_data_0.z);
    return decode_unit_vector(packed);
}

// Fetch albedo at the current quarter-res pixel. Luster packs albedo into
// the first 6 channels of the mat4x2 unpacking (3 RGB floats across .xyzw).
vec3 gi_read_albedo(ivec2 texel) {
    vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
    mat4x2 data = mat4x2(
        unpack_unorm_2x8(gbuffer_data_0.x),
        unpack_unorm_2x8(gbuffer_data_0.y),
        unpack_unorm_2x8(gbuffer_data_0.z),
        unpack_unorm_2x8(gbuffer_data_0.w)
    );
    return vec3(data[0], data[1].x);
}

// Fetch light levels (blocklight, skylight) at the current quarter-res pixel.
vec2 gi_read_light_levels(ivec2 texel) {
    vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
    mat4x2 data = mat4x2(
        unpack_unorm_2x8(gbuffer_data_0.x),
        unpack_unorm_2x8(gbuffer_data_0.y),
        unpack_unorm_2x8(gbuffer_data_0.z),
        unpack_unorm_2x8(gbuffer_data_0.w)
    );
    return data[3];
}

// Fetch raw depth at the current quarter-res pixel from the combined
// depth texture (handles LoD mod automatically).
float gi_read_depth(ivec2 texel) {
    return texelFetch(combined_depth_tex, texel, 0).x;
}

// ---------------------------------------------------------------------------
//  Cosine-weighted hemisphere sampling
//  Builds an orthonormal basis from the normal, then maps a uniform 2D
//  sample to a cosine lobe. PDF = cos_theta / pi, which cancels with the
//  Lambertian 1/pi, leaving the radiance estimate = sum(R_i) / N.
//  This is the standard trick from http://www.amietia.com/lambertnotangent.html
// ---------------------------------------------------------------------------
vec3 gi_cosine_sample_hemisphere(vec3 normal, vec2 uv) {
    // Map uv to a point on the unit disk (concentric Shirley mapping).
    vec2 p = uv * 2.0 - 1.0;
    float r, phi;
    if (p.x == 0.0 && p.y == 0.0) {
        r = 0.0; phi = 0.0;
    } else if (abs(p.x) > abs(p.y)) {
        r = p.x; phi = (p.y > 0.0) ? 0.25 * pi : 0.75 * pi;
    } else {
        r = p.y; phi = (p.x > 0.0) ? 0.0 : 0.5 * pi;
        if (p.y < 0.0) phi = (p.x > 0.0) ? 1.5 * pi : pi;
    }
    float cos_theta = sqrt(max0(1.0 - r * r));
    float sin_theta = r;

    // Build TBN from normal (Fris method — handles all normals robustly).
    vec3 t1 = abs(normal.z) < 0.999
        ? normalize(vec3(normal.y, -normal.x, 0.0))
        : vec3(1.0, 0.0, 0.0);
    vec3 t2 = cross(normal, t1);
    return normalize(t1 * (cos(phi) * sin_theta)
                   + t2 * (sin(phi) * sin_theta)
                   + normal * cos_theta);
}

// ---------------------------------------------------------------------------
//  Screen-space raymarcher
//
//  Linear-in-screen-space marching like Luster's existing
//  raymarch_depth_buffer in include/misc/raytracer.glsl, but inlined here
//  so the bounce shader can read gbuffer normals at the hit (the original
//  raymarcher only returns the screen-space hit position).
//
//  Returns true on hit and writes hit_uv (xy = screen UV, z = depth).
//  Returns false on miss (ray left the frustum or hit sky).
// ---------------------------------------------------------------------------
bool gi_raymarch(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_dir,
    float dither,
    out vec3 hit_uv
) {
    if (view_dir.z > 0.0 && view_dir.z >= -view_pos.z) {
        return false;
    }

    // Project the direction into screen space.
    vec3 screen_dir = normalize(
        view_to_screen_space(combined_projection_matrix, view_pos + view_dir, true)
        - screen_pos
    );

    // Total ray length until it leaves the screen frustum in UV space.
    float ray_length = min_of(
        abs(sign(screen_dir) - screen_pos) / max(abs(screen_dir), eps)
    );
    float step_length = ray_length / float(INDIRECT_LIGHTING_RAY_STEPS);
    vec3 ray_step = screen_dir * step_length;

    // Stochastic starting offset (per-pixel blue-noise dither from caller).
    vec3 ray_pos = screen_pos + dither * ray_step
                 + length(view_pixel_size) * screen_dir;

    // Depth tolerance scales with the screen-space step size, so distant
    // surfaces that compress heavily in screen Z are still detected.
    float depth_tolerance = max(abs(ray_step.z) * 3.0, 0.02 / sqr(view_pos.z));

    bool hit = false;
    for (int i = 0; i < INDIRECT_LIGHTING_RAY_STEPS; ++i, ray_pos += ray_step) {
        if (clamp01(ray_pos) != ray_pos) return false;

        float depth = texelFetch(
            combined_depth_tex,
            ivec2(ray_pos.xy * view_res * taau_render_scale),
            0
        ).x;

        if (depth < ray_pos.z
            && abs(depth_tolerance - (ray_pos.z - depth)) < depth_tolerance) {
            hit = true;
            break;
        }
    }

    if (!hit) return false;

    // Binary refinement — walk back toward the ray origin, narrowing by
    // 50% per step so we land close to the true surface.
    for (int i = 0; i < INDIRECT_LIGHTING_REFINEMENT_STEPS; ++i) {
        ray_step *= 0.5;
        float depth = texelFetch(
            combined_depth_tex,
            ivec2(ray_pos.xy * view_res * taau_render_scale),
            0
        ).x;
        if (depth < ray_pos.z
            && abs(depth_tolerance - (ray_pos.z - depth)) < depth_tolerance) {
            ray_pos -= ray_step;
        } else {
            ray_pos += ray_step;
        }
    }

    // Reject hits on the hand layer (depth < hand_depth) or on the sky.
    if (ray_pos.z >= 1.0 || ray_pos.z < hand_depth) return false;

    hit_uv = ray_pos;
    return true;
}

// ---------------------------------------------------------------------------
//  Reprojection
//
//  For accumulate: reproject the current pixel's scene position into the
//  previous frame's screen UV, so we can fetch the previous accumulated
//  radiance and blend it as the temporal history.
// ---------------------------------------------------------------------------
vec3 gi_reproject(vec3 scene_pos, bool hand) {
    return reproject_scene_space(scene_pos, hand, false);
}

#endif // INCLUDE_PROGRAM_GI_SHARED
