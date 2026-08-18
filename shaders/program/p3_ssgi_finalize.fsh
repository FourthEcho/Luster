/*
--------------------------------------------------------------------------------

  Luster Shaders

  program/p3_ssgi_finalize:
  SSGI bounce 3 (optional) + spatial filter + temporal accumulation (ping-pong
  on colortex18 with depth-rejected reprojection) + application to the scene

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 scene_color;
layout(location = 1) out vec3 ssgi_history;
/* RENDERTARGETS: 0,18 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0;  // lit scene color
uniform sampler2D colortex1;  // gbuffer data
uniform sampler2D colortex17; // accumulated bounce radiance
uniform sampler2D colortex18; // SSGI temporal history (previous frame)

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec2 view_res;

uniform float near;
uniform float far;
uniform vec2 taa_offset;

uniform int frameCounter;

#define TEMPORAL_REPROJECTION

#include "/include/lighting/ssgi.glsl"

// Depth-aware spatial filter over the bounce radiance
vec3 ssgi_filter(ivec2 texel, float depth) {
    vec3 sum = texelFetch(colortex17, texel, 0).rgb;
    float weight = 1.0;

    for (int x = -SSGI_FILTER_RADIUS; x <= SSGI_FILTER_RADIUS; ++x) {
        for (int y = -SSGI_FILTER_RADIUS; y <= SSGI_FILTER_RADIUS; ++y) {
            if (x == 0 && y == 0) continue;

            ivec2 sample_texel = texel + ivec2(x, y);
            float sample_depth = texelFetch(depthtex0, sample_texel, 0).x;

            // Reject samples across depth discontinuities
            float depth_weight = exp2(-256.0 * abs(sample_depth - depth));
            sum += texelFetch(colortex17, sample_texel, 0).rgb * depth_weight;
            weight += depth_weight;
        }
    }

    return sum * rcp(weight);
}

void main() {
#ifdef SSGI
    ivec2 texel = ivec2(gl_FragCoord.xy);

    float depth = texelFetch(depthtex0, texel, 0).x;
    vec3 pre_ssgi_color = texelFetch(colortex0, texel, 0).rgb;

    if (depth >= 1.0 || depth < hand_depth) {
        scene_color = pre_ssgi_color;
        ssgi_history = vec3(0.0);
        return;
    }

    vec3 albedo, normal;
    ssgi_decode_gbuffer(texel, albedo, normal);

    vec3 position_view = screen_to_view_space(vec3(uv, depth), true);

    float dither = texelFetch(noisetex, texel & 511, 0).b;
    dither = r1(frameCounter, dither);

    vec3 bounce_radiance = texelFetch(colortex17, texel, 0).rgb;

#if SSGI_BOUNCES >= 3
    // Bounce 3: gather from the accumulated bounce-1+2 radiance
    bounce_radiance += ssgi_gather(position_view, normal, colortex17, texel, dither);
#endif

    // Spatial filter
#if SSGI_FILTER_RADIUS > 0
    bounce_radiance = ssgi_filter(texel, depth);
#endif

#ifdef SSGI_TEMPORAL_ACCUMULATION
    // Temporal accumulation (approach 2): reproject this pixel into the
    // reprojected frame and blend with depth rejection
    vec3 previous_screen = reproject(vec3(uv, depth));
    vec3 blended = bounce_radiance;

    if (clamp01(previous_screen.xy) == previous_screen.xy) {
        float previous_depth = texelFetch(
            depthtex0,
            ivec2(previous_screen.xy * view_res),
            0
        ).x;

        // Reject temporal history when reprojection lands on a materially different surface.
        float depth_rejection = exp2(-64.0 * abs(previous_depth - previous_screen.z));
        vec3 history = texelFetch(
            colortex18,
            ivec2(previous_screen.xy * view_res),
            0
        ).rgb;

        blended = mix(bounce_radiance, history, SSGI_TEMPORAL_WEIGHT * depth_rejection);
    }

    ssgi_history = blended;
#else
    vec3 blended = bounce_radiance;
    ssgi_history = bounce_radiance;
#endif

    // Apply: modulate by the surface albedo so bounce light is re-emitted
    // with the surface's color
    scene_color = pre_ssgi_color + albedo * blended * SSGI_INTENSITY;
#else
    ivec2 texel = ivec2(gl_FragCoord.xy);
    scene_color = texelFetch(colortex0, texel, 0).rgb;
    ssgi_history = vec3(0.0);
#endif
}
