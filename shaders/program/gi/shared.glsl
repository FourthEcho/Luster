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
    // Proper Shirley concentric-disk mapping.
    // The previous implementation selected only four azimuths, which meant
    // a nominal 8/16-sample GI pass could repeatedly miss narrow receivers
    // such as a vertical wall standing in front of a floor.
    vec2 p = uv * 2.0 - 1.0;

    float r;
    float phi;
    if (abs(p.x) < eps && abs(p.y) < eps) {
        r = 0.0;
        phi = 0.0;
    } else if (abs(p.x) > abs(p.y)) {
        r = p.x;
        phi = (pi * 0.25) * (p.y / p.x);
    } else {
        r = p.y;
        phi = (pi * 0.5) - (pi * 0.25) * (p.x / p.y);
    }


    // Cosine-weighted hemisphere: z = sqrt(1-r^2).
    float sin_theta = r;
    float cos_theta = sqrt(max0(1.0 - r * r));

    // Build a stable tangent frame.
    vec3 tangent = abs(normal.z) < 0.999
        ? normalize(cross(vec3(0.0, 0.0, 1.0), normal))
        : vec3(1.0, 0.0, 0.0);
    vec3 bitangent = cross(normal, tangent);

    return normalize(
        tangent * (cos(phi) * sin_theta)
      + bitangent * (sin(phi) * sin_theta)
      + normal * cos_theta
    );
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
    // A ray that starts toward the camera can leave the projected segment
    // without ever touching another scene surface. Reject it early.
    if (view_dir.z > 0.0 && view_dir.z >= -view_pos.z) {
        return false;
    }

    vec3 projected_end = view_to_screen_space(
        combined_projection_matrix,
        view_pos + view_dir,
        true
    );
    vec3 screen_dir = projected_end - screen_pos;
    float screen_dir_len = length(screen_dir);
    if (screen_dir_len <= eps) return false;
    screen_dir /= screen_dir_len;

    // Find the first point where the projected ray exits the unit frustum.
    vec3 boundary = abs(sign(screen_dir) - screen_pos)
                  / max(abs(screen_dir), eps);
    float ray_length = min_of(boundary);
    if (ray_length <= eps) return false;

    float step_length = ray_length / float(INDIRECT_LIGHTING_RAY_STEPS);
    vec3 ray_step = screen_dir * step_length;

    // Start slightly away from the receiver and dither the first step.
    vec3 ray_pos = screen_pos
                 + dither * ray_step
                 + length(view_pixel_size) * screen_dir;
    vec3 previous_pos = ray_pos;

    // Screen-depth tolerance. A fixed floor prevents distant/grazing rays from
    // becoming effectively impossible to intersect; scaling by the projected
    // step keeps fast marches from tunnelling through thin geometry.
    float depth_tolerance = max(
        abs(ray_step.z) * 2.5,
        0.0015
    );

    bool hit = false;
    for (int i = 0; i < INDIRECT_LIGHTING_RAY_STEPS; ++i) {
        if (clamp01(ray_pos) != ray_pos) return false;

        ivec2 sample_texel = ivec2(
            ray_pos.xy * view_res * taau_render_scale
        );
        sample_texel = clamp(
            sample_texel,
            ivec2(0),
            ivec2(view_res * taau_render_scale) - ivec2(1)
        );

        float depth = texelFetch(combined_depth_tex, sample_texel, 0).x;
        float delta = ray_pos.z - depth;

        // We only have an intersection when the ray is behind the first
        // visible surface and the crossing is within the thickness tolerance.
        if (depth < ray_pos.z && delta <= depth_tolerance) {
            hit = true;
            break;
        }

        previous_pos = ray_pos;
        ray_pos += ray_step;
    }

    if (!hit) return false;

    // Refine the crossing with a true binary search between the last miss and
    // the first hit. The old refinement moved the ray in one direction without
    // retaining a miss bracket, so it could converge away from the surface.
    vec3 lo = previous_pos;
    vec3 hi = ray_pos;

    for (int i = 0; i < INDIRECT_LIGHTING_REFINEMENT_STEPS; ++i) {
        vec3 mid = 0.5 * (lo + hi);
        ivec2 sample_texel = ivec2(
            mid.xy * view_res * taau_render_scale
        );
        sample_texel = clamp(
            sample_texel,
            ivec2(0),
            ivec2(view_res * taau_render_scale) - ivec2(1)
        );

        float depth = texelFetch(combined_depth_tex, sample_texel, 0).x;
        float delta = mid.z - depth;

        if (depth < mid.z && delta <= depth_tolerance) {
            hi = mid;
        } else {
            lo = mid;
        }
    }

    ray_pos = hi;

    // Reject sky and hand-layer intersections.
    ivec2 final_texel = ivec2(
        ray_pos.xy * view_res * taau_render_scale
    );
    final_texel = clamp(
        final_texel,
        ivec2(0),
        ivec2(view_res * taau_render_scale) - ivec2(1)
    );
    float final_depth = texelFetch(combined_depth_tex, final_texel, 0).x;

    if (ray_pos.z >= 1.0 || final_depth >= 1.0 || final_depth < hand_depth) {
        return false;
    }

    hit_uv = vec3(ray_pos.xy, final_depth);
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
