/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c19_color_grading:
  Apply bloom, color grading and tone mapping then convert to rec. 709

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

#ifdef COLOR_GRADING
  #if GRADE_WHITE_BALANCE != 6500
flat in mat3 white_balance_matrix;
  #endif
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // bloom tiles
uniform sampler2D colortex3; // fog transmittance
uniform sampler2D colortex5; // scene color

uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;

uniform vec3 sun_dir;

uniform float rainStrength;

uniform float aspectRatio;
uniform float blindness;
uniform float darknessFactor;
uniform float frameTimeCounter;

uniform float biome_cave;
uniform float time_noon;
uniform float eye_skylight;

uniform vec2 view_pixel_size;

#include "/include/post_processing/tonemap_operators.glsl"
#include "/include/post_processing/color_grading.glsl"
#include "/include/camera/local_exposure.glsl"
#include "/include/camera/vignette.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"
#include "/include/camera/lens_flare.glsl"

vec3 get_bloom() {
    // Upsample last bloom tile. 

    vec2 pad_amount = 6.0 * view_pixel_size;
    vec2 uv_src = clamp(uv, pad_amount, 1.0 - pad_amount) * 0.5;

    return BLOOM_UPSAMPLING_FILTER(colortex0, uv_src).rgb;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    scene_color = texelFetch(colortex5, texel, 0).rgb;

    float exposure = texelFetch(colortex5, ivec2(0), 0).a;

#if defined LENS_FLARE && defined WORLD_OVERWORLD
    // Lens flare in HDR before exposure/tonemap so it grades with the scene
    scene_color += get_lens_flare(uv);
#endif

#ifdef BLOOM
    vec3 bloom = get_bloom();
    float bloom_intensity = 0.12 * BLOOM_INTENSITY;

    scene_color = mix(scene_color, bloom, bloom_intensity);

#ifdef BLOOMY_FOG
    float fog_transmittance = texture(colortex3, uv * taau_render_scale).x;
    scene_color = mix(
        bloom,
        scene_color,
        pow(fog_transmittance, BLOOMY_FOG_INTENSITY)
    );
#endif
#endif

    scene_color *= exposure;

#ifdef LOCAL_EXPOSURE
    float local_ev = compute_local_exposure_ev(uv, scene_color / max(exposure, 1e-6));
    scene_color *= exp2(local_ev);
#endif

#ifdef VIGNETTE
    scene_color *= vignette(uv);
#endif

#ifdef COLOR_GRADING
  #if GRADE_WHITE_BALANCE != 6500
    scene_color = color_grade_input(scene_color, white_balance_matrix);
  #else
    scene_color = color_grade_input(scene_color, mat3(1.0));
  #endif
#endif

#ifdef TONEMAP_COMPARISON
    scene_color
        = uv.x < TONEMAP_COMPARISON_SPLIT ? tonemap_left(scene_color) : tonemap_right(scene_color);
#else
    scene_color = tonemap(scene_color);
#endif

    scene_color = clamp01(scene_color * working_to_display_color);
#ifdef COLOR_GRADING
    scene_color = color_grade_output(scene_color);
#endif

#if 0 // Tonemap plot
        const float scale = 2.0;
        vec2 uv_scaled = uv * scale * vec2(1.0, 1.0 / aspectRatio);
        float x = uv_scaled.x;
        float y = tonemap(vec3(x)).x;

        if (abs(uv_scaled.x - 1.0) < 0.001 * scale) scene_color = vec3(1.0, 0.0, 0.0);
        if (abs(uv_scaled.y - 1.0) < 0.001 * scale) scene_color = vec3(1.0, 0.0, 0.0);
        if (abs(uv_scaled.y - y) < 0.001 * scale) scene_color = vec3(1.0);
#endif
}
