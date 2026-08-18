/*
--------------------------------------------------------------------------------

  Luster Shaders

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
uniform int frameCounter;

#define TEMPORAL_REPROJECTION

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/space_conversion.glsl"

#define TAA_OFFCENTER_REJECTION \
    0.25 // Reduces blur when moving quickly. Too much offcenter rejection
         // results in aliasing and jittering in motion
#define TAAU_CONFIDENCE_REJECTION \
    5.0 // Controls the impact of the "confidence-of-quality" factor on temporal
        // upscaling. Tradeoff between image clarity and time taken to converge
#define TAAU_FLICKER_REDUCTION \
    1.0 // Increases ghosting but reduces flickering caused by aggressive
        // clipping

/*
(needed by vertex stage for auto exposure)
#if AUTO_EXPOSURE != AUTO_EXPOSURE_OFF
const bool colortex0MipmapEnabled = true;
#endif
 */

vec3 min_of(vec3 a, vec3 b, vec3 c, vec3 d, vec3 f) {
    return min(a, min(b, min(c, min(d, f))));
}

vec3 max_of(vec3 a, vec3 b, vec3 c, vec3 d, vec3 f) {
    return max(a, max(b, max(c, max(d, f))));
}

vec3 reinhard(vec3 rgb) { return rgb / (rgb + 1.0); }
vec3 reinhard_inverse(vec3 rgb) { return rgb / (1.0 - rgb); }

vec3 get_closest_fragment(sampler2D depth_sampler, ivec2 texel0) {
    ivec2 texel1 = texel0 + ivec2(-2, -2);
    ivec2 texel2 = texel0 + ivec2(2, -2);
    ivec2 texel3 = texel0 + ivec2(-2, 2);
    ivec2 texel4 = texel0 + ivec2(2, 2);

    float depth0 = texelFetch(depth_sampler, texel0, 0).x;
    float depth1 = texelFetch(depth_sampler, texel1, 0).x;
    float depth2 = texelFetch(depth_sampler, texel2, 0).x;
    float depth3 = texelFetch(depth_sampler, texel3, 0).x;
    float depth4 = texelFetch(depth_sampler, texel4, 0).x;

    vec3 pos = depth0 < depth1 ? vec3(texel0, depth0) : vec3(texel1, depth1);
    vec3 pos1 = depth2 < depth3 ? vec3(texel2, depth2) : vec3(texel3, depth3);
    pos = pos.z < pos1.z ? pos : pos1;
    pos = pos.z < depth4 ? pos : vec3(texel4, depth4);

    return vec3(
        (pos.xy + 0.5) * view_pixel_size * rcp(taau_render_scale),
        pos.z
    );
}

vec3 clip_aabb(
    vec3 history_color,
    vec3 min_color,
    vec3 max_color,
    out bool history_clipped
) {
    vec3 p_clip = 0.5 * (max_color + min_color);
    vec3 e_clip = 0.5 * (max_color - min_color);

    vec3 v_clip = history_color - p_clip;
    vec3 v_unit = v_clip / max(e_clip, 1e-3);
    vec3 a_unit = abs(v_unit);
    float ma_unit = max_of(a_unit);
    history_clipped = ma_unit > 1.0;

    return history_clipped ? p_clip + v_clip / ma_unit : history_color;
}

vec3 clip_aabb(vec3 history_color, vec3 min_color, vec3 max_color) {
    bool history_clipped;
    return clip_aabb(history_color, min_color, max_color, history_clipped);
}

float get_flicker_reduction(
    vec3 history_color,
    vec3 min_color,
    vec3 max_color
) {
    const float flicker_sensitivity = 5.0;

    vec3 min_offset = (history_color - min_color);
    vec3 max_offset = (max_color - history_color);

    float distance_to_clip
        = length(min(min_offset, max_offset)) * flicker_sensitivity * exposure;
    return clamp01(distance_to_clip);
}

vec3 neighborhood_clipping(
    ivec2 texel,
    vec3 current_color,
    vec3 history_color,
    float distance_factor
) {
    vec3 min_color, max_color;

    vec3 a = texelFetch(colortex0, texel + ivec2(-1, 1), 0).rgb;
    vec3 b = texelFetch(colortex0, texel + ivec2(0, 1), 0).rgb;
    vec3 c = texelFetch(colortex0, texel + ivec2(1, 1), 0).rgb;
    vec3 d = texelFetch(colortex0, texel + ivec2(-1, 0), 0).rgb;
    vec3 e = current_color;
    vec3 f = texelFetch(colortex0, texel + ivec2(1, 0), 0).rgb;
    vec3 g = texelFetch(colortex0, texel + ivec2(-1, -1), 0).rgb;
    vec3 h = texelFetch(colortex0, texel + ivec2(0, -1), 0).rgb;
    vec3 i = texelFetch(colortex0, texel + ivec2(1, -1), 0).rgb;

    a = rgb_to_ycocg(reinhard(a));
    b = rgb_to_ycocg(reinhard(b));
    c = rgb_to_ycocg(reinhard(c));
    d = rgb_to_ycocg(reinhard(d));
    e = rgb_to_ycocg(reinhard(e));
    f = rgb_to_ycocg(reinhard(f));
    g = rgb_to_ycocg(reinhard(g));
    h = rgb_to_ycocg(reinhard(h));
    i = rgb_to_ycocg(reinhard(i));

    min_color = min_of(b, d, e, f, h);
    min_color += min_of(min_color, a, c, g, i);
    min_color *= 0.5;

    max_color = max_of(b, d, e, f, h);
    max_color += max_of(max_color, a, c, g, i);
    max_color *= 0.5;

#ifdef TAA_VARIANCE_CLIPPING
    mat2x3 moments;
    moments[0] = (1.0 / 9.0) * (a + b + c + d + e + f + g + h + i);
    moments[1] = (1.0 / 9.0)
        * (a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h
           + i * i);

    float gamma = mix(0.75, 1.25, linear_step(0.25, 1.0, distance_factor));
    gamma *= 1.0 + (0.75 - TAA_VARIANCE_CLIPPING) * 0.5;

    vec3 mu = moments[0];
    vec3 sigma = sqrt(moments[1] - moments[0] * moments[0]);

    min_color = max(min_color, mu - gamma * sigma);
    max_color = min(max_color, mu + gamma * sigma);
#endif

    history_color = rgb_to_ycocg(history_color);
    history_color = clip_aabb(history_color, min_color, max_color);
    history_color = ycocg_to_rgb(history_color);

    return history_color;
}

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
    history_color = max0(history_color);

    float pixel_age = texelFetch(colortex5, ivec2(previous_uv * view_res), 0).a;
    pixel_age
        = max0(pixel_age * float(clamp01(previous_uv) == previous_uv) + 1.0);

    float distance_factor = 1.0 - exp2(-0.025 * length(closest_view));
    float blend_weight = mix(0.35, 0.10, distance_factor);
    float alpha = max(1.0 / pixel_age, blend_weight);

#ifndef TAAU
    vec3 current_color = texelFetch(colortex0, texel, 0).rgb;

    current_color = reinhard(current_color);
    history_color = reinhard(history_color);

    history_color = neighborhood_clipping(
        texel,
        current_color,
        history_color,
        distance_factor
    );
#else
    vec2 pos = clamp01(uv + 0.5 * taa_offset * rcp(taau_render_scale))
        * taau_render_scale;

    float confidence;
    vec3 current_color = catmull_rom_filter(colortex0, pos, confidence).rgb;

    if (min_of(current_color) < 0.0) {
        current_color = texture(colortex0, pos).rgb;
    }

    current_color = reinhard(current_color);
    history_color = reinhard(history_color);

    vec3 min_color = texture(colortex1, pos).rgb * 2.0 - 1.0;
    vec3 max_color = texture(colortex2, pos).rgb * 2.0 - 1.0;
    float flicker_reduction;

    bool history_clipped;
    history_color = rgb_to_ycocg(history_color);
    history_color
        = clip_aabb(history_color, min_color, max_color, history_clipped);
    flicker_reduction = history_clipped
        ? 0.0
        : get_flicker_reduction(history_color, min_color, max_color);
    history_color = ycocg_to_rgb(history_color);

    alpha *= pow(confidence, TAAU_CONFIDENCE_REJECTION);
    alpha *= 1.0 - TAAU_FLICKER_REDUCTION * flicker_reduction;
#endif

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
#else
    result = texelFetch(colortex0, texel, 0);
#endif

    if (texel == ivec2(0)) {
        result.a = exposure;
    }

#if AUTO_EXPOSURE == AUTO_EXPOSURE_HISTOGRAM \
    && DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
    draw_histogram(texel);
#endif

    bloom_input = result.rgb;
}
