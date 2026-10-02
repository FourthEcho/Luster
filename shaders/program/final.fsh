/*
--------------------------------------------------------------------------------

  Luster Shader by FourthEcho

  program/program/final.glsl:
  CAS, dithering, debug views

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 fragment_color;

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color

#if DEBUG_VIEW == DEBUG_VIEW_SAMPLER
uniform sampler2D DEBUG_SAMPLER;
#endif

uniform float viewHeight;
uniform float viewWidth;
uniform float frameTimeCounter;

#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/text_rendering.glsl"
#include "/include/post_processing/sharpening.glsl"

#ifdef DISTANCE_VIEW
uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec2 view_res;
uniform vec2 taa_offset;

uniform float near;
uniform float far;

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/space_conversion.glsl"
#endif

const int debug_text_scale = 2;
ivec2 debug_text_position = ivec2(0, int(viewHeight) / debug_text_scale);

#if DEBUG_VIEW == DEBUG_VIEW_WEATHER
#include "/include/misc/debug_weather.glsl"
#endif

#ifdef FRAMING_TOOL
// Composition-guide line profile shared by the thirds/aspect/safe
// overlays at the end of main.
float framing_line_profile(float d) {
    return 1.0 - smoothstep(
        FRAMING_LINE_WIDTH * 0.5 - 0.5,
        FRAMING_LINE_WIDTH * 0.5 + 0.5,
        d
    );
}
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    if (abs(MC_RENDER_QUALITY - 1.0) < 0.01) {
        fragment_color
            = cas_filter(colortex0, texel, CAS_INTENSITY * 2.0 - 1.0);
    } else {
        fragment_color = catmull_rom_filter_fast_rgb(colortex0, uv, 0.6);
        fragment_color = display_eotf(fragment_color);
    }

    fragment_color = image_sharpen_filter(
        colortex0,
        texel,
        fragment_color,
        IMAGE_SHARPENING_INTENSITY
    );

    fragment_color = dither_8bit(fragment_color, bayer16(vec2(texel)));

#if DEBUG_VIEW == DEBUG_VIEW_SAMPLER
    if (clamp(texel, ivec2(0), ivec2(textureSize(DEBUG_SAMPLER, 0))) == texel) {
        fragment_color = texelFetch(DEBUG_SAMPLER, texel, 0).rgb;
        fragment_color = display_eotf(fragment_color);
    }
#elif DEBUG_VIEW == DEBUG_VIEW_WEATHER
    debug_weather(fragment_color);
#endif

#ifdef DISTANCE_VIEW
    float depth
        = texelFetch(depthtex0, ivec2(uv * view_res * taau_render_scale), 0).x;

    vec3 position_screen = vec3(uv, depth);
    vec3 position_view
        = screen_to_view_space(gbufferProjectionInverse, position_screen, true);

    bool is_sky = depth == 1.0;

#ifdef LOD_MOD_ACTIVE
    float depth_lod = texelFetch(lod_depth_tex, texel, 0).x;
    bool is_lod = is_lod_terrain(depth, depth_lod);

    if (is_lod) {
        position_view = screen_to_view_space(
            lod_projection_matrix_inverse,
            vec3(uv, depth_lod),
            true
        );
    }

    is_sky = is_sky && depth_lod == 1.0;
#endif

#if DISTANCE_VIEW_METHOD == DISTANCE_VIEW_DISTANCE
    float dist = length(position_view);
#elif DISTANCE_VIEW_METHOD == DISTANCE_VIEW_DEPTH
    float dist = -position_view.z;
#endif

    fragment_color = is_sky
        ? vec3(1.0)
        : vec3(clamp01(dist * rcp(DISTANCE_VIEW_MAX_DISTANCE)));
#endif

#ifdef FRAMING_TOOL
    // Composition guides: rule-of-thirds grid, target aspect box and
    // safe-area rect. Overlaid last so grading never tints the guides.
    {
        vec2 framing_res = vec2(viewWidth, viewHeight);
        float guide = 0.0;
#ifdef FRAMING_THIRDS
        vec2 third = framing_res / 3.0;
        float thirds_dist = min(
            min(
                abs(gl_FragCoord.x - third.x),
                abs(gl_FragCoord.x - 2.0 * third.x)
            ),
            min(
                abs(gl_FragCoord.y - third.y),
                abs(gl_FragCoord.y - 2.0 * third.y)
            )
        );
        guide = max(guide, framing_line_profile(thirds_dist));
#endif
#ifdef FRAMING_ASPECT
        float screen_aspect = framing_res.x / max(framing_res.y, 1.0);
        float aspect_dist;
        if (screen_aspect > FRAMING_ASPECT_RATIO) {
            float half_w = 0.5 * framing_res.y * FRAMING_ASPECT_RATIO;
            aspect_dist = min(
                abs(gl_FragCoord.x - (0.5 * framing_res.x - half_w)),
                abs(gl_FragCoord.x - (0.5 * framing_res.x + half_w))
            );
        } else {
            float half_h = 0.5 * framing_res.x / max(FRAMING_ASPECT_RATIO, 1e-4);
            aspect_dist = min(
                abs(gl_FragCoord.y - (0.5 * framing_res.y - half_h)),
                abs(gl_FragCoord.y - (0.5 * framing_res.y + half_h))
            );
        }
        guide = max(guide, framing_line_profile(aspect_dist));
        vec2 safe_q = abs(gl_FragCoord.xy - 0.5 * framing_res)
            - 0.5 * framing_res * FRAMING_SAFE_AREA;
        float safe_dist = length(max(safe_q, vec2(0.0)))
            + min(max(safe_q.x, safe_q.y), 0.0);
        guide = max(guide, framing_line_profile(abs(safe_dist)));
#endif
        fragment_color = mix(fragment_color, vec3(1.0), guide * FRAMING_OPACITY);
    }
#endif
}

#include "/include/buffers.glsl"
