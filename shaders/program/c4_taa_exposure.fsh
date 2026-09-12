/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c4_taa_exposure:
  TAA and auto exposure

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 bloom_input;
layout(location = 1) out vec4 result;

/* RENDERTARGETS: 0,5 */

in vec2 uv;

flat in float exposure;

#if DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
flat in vec4[HISTOGRAM_BINS / 4] histogram_pdf;
flat in float histogram_selected_bin;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color
uniform sampler2D colortex5; // Scene history

#ifdef TAAU
uniform sampler2D colortex1; // TAA min color
uniform sampler2D colortex2; // TAA max color
#endif

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float frameTime;
uniform float near;
uniform float far;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#define TEMPORAL_REPROJECTION

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/space_conversion.glsl"

#define TAA_VARIANCE_CLIPPING // More aggressive neighborhood clipping method
                              // which further reduces ghosting but can
                              // introduce flickering artifacts
#define TAA_OFFCENTER_REJECTION \
    0.25 // Reduces blur when moving quickly. Too much offcenter rejection
         // results in aliasing and jittering in motion
#define TAAU_CONFIDENCE_REJECTION \
    5.0 // Controls the impact of the "confidence-of-quality" factor on temporal
        // upscaling. Tradeoff between image clarity and time taken to converge
#define TAAU_FLICKER_REDUCTION \
    1.0 // Increases ghosting but reduces flickering caused by aggressive
        // clipping

#include "/include/post_processing/taa.glsl"

/*
(needed by vertex stage for auto exposure)
#if AUTO_EXPOSURE != AUTO_EXPOSURE_OFF
const bool colortex0MipmapEnabled = true;
#endif
 */

#if AUTO_EXPOSURE == AUTO_EXPOSURE_HISTOGRAM \
    && DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
void draw_histogram(ivec2 texel) {
    const int width = 512;
    const int height = 256;

    const vec3 white = vec3(1.0);
    const vec3 black = vec3(0.0);
    const vec3 red = vec3(1.0, 0.0, 0.0);

    vec2 coord = texel / vec2(width, height);

    if (all(lessThan(texel, ivec2(width, height)))) {
        int index = int(HISTOGRAM_BINS * coord.x);
        float threshold = coord.y;

        result.rgb
            = histogram_pdf[index >> 2][index & 3] > threshold ? black : white;

        float median = max0(1.0 - abs(index - histogram_selected_bin));
        result.rgb = mix(result.rgb, red, median) / exposure;
    }
}
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy * taau_render_scale);

#ifdef TAA
#ifndef LOD_MOD_ACTIVE
    vec3 closest = get_closest_fragment(depthtex0, texel);

    const bool is_lod = false;
#else
    vec3 closest = get_closest_fragment(depthtex0, texel);
    vec3 closest_lod = get_closest_fragment(lod_depth_tex, texel);

    bool is_lod = is_lod_terrain(closest.z, closest_lod.z);

    closest = is_lod ? closest_lod : closest;
#endif

    vec3 closest_view = screen_to_view_space(closest, false, is_lod);
    vec3 closest_scene = view_to_scene_space(closest_view);

    bool hand = closest.z < hand_depth;

    vec2 velocity
        = closest.xy - reproject_scene_space(closest_scene, hand, is_lod).xy;
    vec2 previous_uv = uv - velocity;

    vec3 history_color
        = catmull_rom_filter_fast_rgb(colortex5, previous_uv, 0.6);
    history_color = max0(history_color); // Eliminate NaNs in the history

    float pixel_age = texelFetch(colortex5, ivec2(previous_uv * view_res), 0).a;
    pixel_age
        = max0(pixel_age * float(clamp01(previous_uv) == previous_uv) + 1.0);

    // Distance factor to favour responsiveness closer to the camera and image
    // stability further away
    float distance_factor = 1.0 - exp2(-0.025 * length(closest_view));

    // Dynamic blend weight lending equal weight to all frames in the history,
    // drastically reducing time taken to converge when upscaling.
    //
    // TAA_INTENSITY scales how aggressively the temporal blend rejects the
    // current frame in favour of the history buffer:
    //   1.0  -> default (blend_weight 0.35 near, 0.10 far)
    //   >1.0 -> more temporal accumulation, smoother but more ghosting
    //   <1.0 -> less temporal accumulation, sharper but more aliased
    // We divide by TAA_INTENSITY so a higher value reduces the current
    // frame's contribution (i.e. increases the relative weight of history).
    float blend_weight = mix(0.35, 0.10, distance_factor) * rcp(TAA_INTENSITY);
    float alpha = max(1.0 / pixel_age, blend_weight);

#ifndef TAAU
    // Native resolution TAA
    vec3 current_color = texelFetch(colortex0, texel, 0).rgb;

    // "Tonemapping" before applying TAA in order to perform the AA in SDR
    // This improves the result because the differences between the luminances
    // are closer to how they will be in the final output
    current_color = reinhard(current_color);
    history_color = reinhard(history_color);

    history_color = neighborhood_clipping(
        texel,
        current_color,
        history_color,
        distance_factor
    );
#else
    // Temporal upscaling
    vec2 pos = clamp01(uv + 0.5 * taa_offset * rcp(taau_render_scale))
        * taau_render_scale;

    float confidence; // Confidence-of-quality factor, see "A Survey of Temporal
                      // Antialiasing Techniques" section 5.1
    vec3 current_color = catmull_rom_filter(colortex0, pos, confidence).rgb;

    if (min_of(current_color) < 0.0) {
        // Fix negatives arising around very dark objects
        current_color = texture(colortex0, pos).rgb;
    }

    current_color = reinhard(current_color);
    history_color = reinhard(history_color);

    // Interpolate AABB bounds across pixels
    vec3 min_color = texture(colortex1, pos).rgb * 2.0 - 1.0;
    vec3 max_color = texture(colortex2, pos).rgb * 2.0 - 1.0;

    bool history_clipped;
    history_color = rgb_to_ycocg(history_color);
    history_color
        = clip_aabb(history_color, min_color, max_color, history_clipped);
    float flicker_reduction = history_clipped
        ? 0.0
        : get_flicker_reduction(history_color, min_color, max_color);
    history_color = ycocg_to_rgb(history_color);

    alpha *= pow(confidence, TAAU_CONFIDENCE_REJECTION);
    alpha *= 1.0 - TAAU_FLICKER_REDUCTION * flicker_reduction;
#endif

    // Offcenter rejection from Jessie, which is originally by Zombye
    // Reduces blur in motion
    vec2 pixel_offset = 1.0 - abs(2.0 * fract(view_res * previous_uv) - 1.0);
    float offcenter_rejection
        = sqrt(pixel_offset.x * pixel_offset.y) * TAA_OFFCENTER_REJECTION
        + (1.0 - TAA_OFFCENTER_REJECTION);

    alpha = 1.0 - alpha;
    alpha *= offcenter_rejection;
    alpha = 1.0 - alpha;

    current_color = mix(history_color, current_color, alpha);
    current_color = reinhard_inverse(current_color);

    result = vec4(current_color, pixel_age * offcenter_rejection);
#else // TAA disabled
    result = texelFetch(colortex0, texel, 0);
#endif

    // Store exposure in the alpha component of the bottom left texel of the
    // history buffer
    if (texel == ivec2(0)) {
        result.a = exposure;
    }

#if AUTO_EXPOSURE == AUTO_EXPOSURE_HISTOGRAM \
    && DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
    draw_histogram(texel);
#endif

    bloom_input = result.rgb;
}
