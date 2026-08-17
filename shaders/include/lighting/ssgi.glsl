#if !defined INCLUDE_LIGHTING_SSGI
#define INCLUDE_LIGHTING_SSGI

/*
  Screen-space global illumination.

  Bounce chain (true multi-bounce, one prepare pass per bounce):
    prepare1: B1 = gather(direct lit scene, colortex0)   -> colortex17
    prepare2: B2 = B1 + gather(B1)                       -> colortex17 (+flip)
    prepare3: B3 = B2 + gather(B2), then filter + temporal accumulate
              + apply to the scene color (colortex0)     -> colortex0, colortex18

  Only prepare3 applies and accumulates temporally (ping-pong on colortex18),
  regardless of the bounce count, so the temporal state machine has a single
  fixed producer.  Everything runs in plain fragment shaders (GL 4.1
  compatible — no compute, no SSBOs, no image load/store).
*/

#include "/include/utility/dithering.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"
#include "/include/utility/space_conversion.glsl"

// ----------------------------------------------------------------------------
//  Gbuffer decode (albedo + flat view-space normal from colortex1)
// ----------------------------------------------------------------------------

void ssgi_decode_gbuffer(ivec2 texel, out vec3 albedo, out vec3 normal) {
    vec4 gbuffer_data = texelFetch(colortex1, texel, 0);

    mat4x2 data = mat4x2(
        unpack_unorm_2x8(gbuffer_data.x),
        unpack_unorm_2x8(gbuffer_data.y),
        unpack_unorm_2x8(gbuffer_data.z),
        unpack_unorm_2x8(gbuffer_data.w)
    );

    albedo = vec3(data[0], data[1].x);
    normal = decode_unit_vector(data[2]);
}

// ----------------------------------------------------------------------------
//  Screen-space raymarch.  Marches a view-space ray against depthtex0 and
//  returns the screen-space hit position, or vec3(0.0) on a miss.
// ----------------------------------------------------------------------------

vec3 ssgi_trace_ray(
    vec3 ray_start_view,
    vec3 ray_dir_view,
    float ray_length,
    float dither
) {
    const float thickness = 0.5; // relative depth-slab thickness for a valid hit

    vec3 ray_end_view = ray_start_view + ray_dir_view * ray_length;

    vec3 start_screen = view_to_screen_space(gbufferProjection, ray_start_view, false);
    vec3 end_screen = view_to_screen_space(gbufferProjection, ray_end_view, false);

    vec3 ray_screen = end_screen - start_screen;
    ray_screen /= max(abs(ray_screen.z), eps); // parametrize by depth

    vec3 pos_screen = start_screen + ray_screen * dither;
    float prev_depth = pos_screen.z;

    for (int i = 0; i < SSGI_RAY_STEPS; ++i) {
        pos_screen += ray_screen;

        if (clamp01(pos_screen.xy) != pos_screen.xy) break;

        float sample_depth = texelFetch(depthtex0, ivec2(pos_screen.xy * view_res), 0).x;

        if (sample_depth >= 1.0) continue; // sky

        float depth_difference = pos_screen.z - sample_depth;

        if (depth_difference > 0.0 && depth_difference < thickness * (1.0 - sample_depth)) {
            return pos_screen;
        }

        prev_depth = sample_depth;
    }

    return vec3(0.0);
}

// ----------------------------------------------------------------------------
//  One-bounce gather: cosine-weighted hemisphere rays traced in screen space,
//  sampling the incoming radiance buffer at the hit points.
// ----------------------------------------------------------------------------

vec3 ssgi_gather(
    vec3 position_view,
    vec3 normal_view,
    sampler2D radiance_sampler,
    ivec2 texel,
    float dither
) {
    // Orthonormal basis around the normal (view space)
    vec3 up = abs(normal_view.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal_view));
    vec3 bitangent = cross(normal_view, tangent);
    mat3 tbn = mat3(tangent, bitangent, normal_view);

    // Per-pixel ray rotation for temporal decorrelation
    float rotation = interleaved_gradient_noise(texel, frameCounter & 63) * tau;

    vec3 radiance = vec3(0.0);

    const int ray_count = 2;

    for (int i = 0; i < ray_count; ++i) {
        vec2 hash = vec2(
            r1(i + ray_count * (frameCounter & 7), dither),
            fract(dither + float(i) * 0.61803398875)
        );
        vec3 local_dir = cosine_weighted_hemisphere_sample(hash);
        local_dir.xy = mat2(cos(rotation), sin(rotation),
                            -sin(rotation), cos(rotation)) * local_dir.xy;
        vec3 ray_dir = tbn * local_dir;

        vec3 hit = ssgi_trace_ray(position_view, ray_dir, SSGI_RADIUS, dither);

        if (hit.z > 0.0) {
            radiance += texelFetch(
                radiance_sampler,
                ivec2(clamp(hit.xy * view_res, vec2(0.0), view_res - 1.0)),
                0
            ).rgb;
        }
    }

    return radiance * rcp(float(ray_count));
}

#endif // INCLUDE_LIGHTING_SSGI
