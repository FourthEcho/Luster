#if !defined INCLUDE_LIGHTING_REFLECTION_CAPTURE
#define INCLUDE_LIGHTING_REFLECTION_CAPTURE

// ---------------------------------------------------------------------
// Screen-space sphere capture for off-screen reflections.
// ---------------------------------------------------------------------

#ifdef REFLECTION_CAPTURE
// Iris requires boolean shader options to be checked with #ifdef/#ifndef.
#define REFLECTION_CAPTURE_OPTION_ENABLED

uniform sampler2D colortex21; // capture color (rgb) + raw depth flag (a: 1 = no data)
uniform sampler2D colortex22; // capture scene position, camera-relative (rgb) + age (a)

// Capture panorama resolution. Must match size.buffer.colortex21/22.
const vec2 reflection_capture_res = vec2(1024.0, 512.0);
const vec2 reflection_capture_rcp = vec2(1.0 / 1024.0, 1.0 / 512.0);

// Capture UV -> world/scene-space direction (equirectangular, u wraps).
vec3 project_capture_direction(vec2 capture_uv) {
    vec2 ang = fract(vec2(capture_uv.x, clamp01(capture_uv.y))) * vec2(tau, pi);
    vec2 sc = vec2(sin(ang.x), cos(ang.x));
    float sp = sin(ang.y);
    return vec3(sc.x * sp, cos(ang.y), sc.y * sp);
}

// World/scene-space direction -> capture UV.
vec2 unproject_capture_direction(vec3 dir) {
    float len_sq = dot(dir, dir);
    if (len_sq < eps) {
        return vec2(0.5, 0.5);
    }
    vec3 n = dir * inversesqrt(len_sq);
    // Poles: azimuth is undefined (atan(0, 0)); any u maps to the same
    // pole point in project_capture_direction, so snap to the seam texel
    // instead of feeding undefined values to atan.
    float u = abs(n.y) > 1.0 - 1e-4
        ? 0.5
        : atan(-n.x, -n.z) * rcp(tau) + 0.5;
    return vec2(u, acos(clamp(n.y, -1.0, 1.0)) * rcp(pi));
}

// Position-aware capture read for an SSR miss. reflect_dir and scene_pos
// must both be camera-relative (scene space). Invalid taps (flag >= 1,
// i.e. sky or never observed) contribute the sky fallback instead.
vec3 read_capture_position_aware(
    vec3 reflect_dir,
    vec3 scene_pos,
    vec3 sky_fallback
) {
    float reflector_dist_sq = dot(scene_pos, scene_pos);
    if (reflector_dist_sq < eps) {
        return sky_fallback;
    }

    vec3 dir = reflect_dir * inversesqrt(max(dot(reflect_dir, reflect_dir), eps));
    vec2 suv = unproject_capture_direction(dir);

    // Reject captured surfaces sitting between the camera and the
    // reflector: from the reflector they would be behind the surface.
    vec3 stored_pos = texelFetch(
        colortex22,
        ivec2(
            clamp(int(suv.x * reflection_capture_res.x), 0, 1023),
            clamp(int(suv.y * reflection_capture_res.y), 0, 511)
        ),
        0
    ).rgb;
    if (any(isnan(stored_pos))) {
        return sky_fallback;
    }
    if (dot(stored_pos, stored_pos) < reflector_dist_sq
        && dot(scene_pos, dir) > 0.0) {
        return sky_fallback;
    }

    // Manual bilinear fetch with horizontal wrap. Invalid taps fall back
    // to sky so never-observed regions blend to sky instead of black.
    vec2 texel_pos = suv * reflection_capture_res - 0.5;
    ivec2 base = ivec2(floor(texel_pos));
    vec2 weights = fract(texel_pos);

    vec4 s00 = texelFetch(
        colortex21,
        ivec2((base.x) & 1023, clamp(base.y, 0, 511)),
        0
    );
    vec4 s10 = texelFetch(
        colortex21,
        ivec2((base.x + 1) & 1023, clamp(base.y, 0, 511)),
        0
    );
    vec4 s01 = texelFetch(
        colortex21,
        ivec2((base.x) & 1023, clamp(base.y + 1, 0, 511)),
        0
    );
    vec4 s11 = texelFetch(
        colortex21,
        ivec2((base.x + 1) & 1023, clamp(base.y + 1, 0, 511)),
        0
    );

    vec3 t00 = (s00.a < 1.0 - 1e-4 && !any(isnan(s00.rgb))) ? s00.rgb : sky_fallback;
    vec3 t10 = (s10.a < 1.0 - 1e-4 && !any(isnan(s10.rgb))) ? s10.rgb : sky_fallback;
    vec3 t01 = (s01.a < 1.0 - 1e-4 && !any(isnan(s01.rgb))) ? s01.rgb : sky_fallback;
    vec3 t11 = (s11.a < 1.0 - 1e-4 && !any(isnan(s11.rgb))) ? s11.rgb : sky_fallback;

    return mix(mix(t00, t10, weights.x), mix(t01, t11, weights.x), weights.y);
}

#endif // REFLECTION_CAPTURE

#endif // INCLUDE_LIGHTING_REFLECTION_CAPTURE
