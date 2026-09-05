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
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"

// HDR-aware local exposure.
//
// The global exposure is still the photographic exposure of the whole scene.
// This pass only adds a restrained spatially-varying correction around that
// exposure. The neighborhood is measured in log luminance, which makes the
// response behave in stops instead of raw linear multiplication. A center-
// luminance similarity term keeps the filter from bleeding exposure across
// strong depth/color boundaries, reducing the classic local-tone halos.
float local_exposure_luma(vec3 rgb) {
    return max(dot(max(rgb, vec3(0.0)), luminance_weights), 1e-5);
}

#ifdef LOCAL_EXPOSURE
float compute_local_exposure_ev(vec2 texel_uv, vec3 center_rgb) {
    float center_log = log2(local_exposure_luma(center_rgb));

    float sum_log = center_log * 4.0;
    float sum_w = 4.0;

    // Small Gaussian footprint. Radius is deliberately modest because this is
    // a per-pixel post pass; larger-scale adaptation is already handled by the
    // global exposure system.
    const vec2 o = vec2(2.0);
    vec3 s;
    float l, w, d;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(-o.x, 0.0), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695); // ~= exp(-d)
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2( o.x, 0.0), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(0.0, -o.y), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(0.0,  o.y), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = 2.0 * exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    const float diag = 1.41421356 * 2.0;
    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(-diag, -diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2( diag, -diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2(-diag,  diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    s = textureLod(colortex5, texel_uv + view_pixel_size * vec2( diag,  diag), 0.0).rgb;
    l = log2(local_exposure_luma(s));
    d = abs(l - center_log);
    w = exp2(-d * 1.442695);
    sum_log += l * w; sum_w += w;

    float local_log = sum_log / max(sum_w, 1e-5);

    // The global exposure pipeline targets the meter-calibrated middle gray.
    // Local exposure only moves a fraction of the way toward that target.
    const float middle_gray = 0.18;
    const float adaptation = 0.28;
    float ev = (log2(middle_gray) - local_log) * adaptation;

    // Keep local exposure a detail-preserving correction, never a replacement
    // for the user's global exposure. The symmetric limit is 2/3 stop.
    // DETAIL scales the fine bilateral term (1.0 = full detail correction).
    ev = clamp(ev * LOCAL_EXPOSURE_DETAIL, -0.6666667, 0.6666667);

    // Regional adaptation: the fine bilateral taps above only see pixels,
    // so broad light/shadow regions (a bright sky over a dark valley) slip
    // through. A low-res neighborhood luminance steers whole regions toward
    // middle gray — dodge and burn at area scale — clamped to RANGE stops
    // so it grades but never overrides the global exposure.
    float region_lod = ceil(log2(max_of(rcp(view_pixel_size)) * 0.02));
    vec3 region_rgb
        = textureLod(colortex5, texel_uv, region_lod).rgb;
    float region_log = log2(local_exposure_luma(region_rgb));
    float region_ev = clamp(
        (log2(middle_gray) - region_log) * adaptation,
        -LOCAL_EXPOSURE_RANGE,
        LOCAL_EXPOSURE_RANGE
    );

    return mix(ev, region_ev, LOCAL_EXPOSURE_REGIONAL);
}
#endif

vec3 get_bloom() {
    // Upsample last bloom tile. 

    vec2 pad_amount = 6.0 * view_pixel_size;
    vec2 uv_src = clamp(uv, pad_amount, 1.0 - pad_amount) * 0.5;

    return BLOOM_UPSAMPLING_FILTER(colortex0, uv_src).rgb;
}

float vignette(vec2 uv) {
    const float vignette_size = 16.0;
    const float vignette_intensity = 0.08 * VIGNETTE_INTENSITY;

    float darkness_pulse = 1.0 - dampen(abs(cos(2.0 * frameTimeCounter)));

    float vignette
        = vignette_size * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    vignette = pow(
        vignette,
        vignette_intensity + 0.1 * biome_cave + 0.3 * blindness
            + 0.2 * darkness_pulse * darknessFactor
    );

    // Radial shaping: confine the falloff between START and END with
    // EXPONENT rolloff (Kappa-style). At defaults the corners and center
    // match the unshaped curve exactly; only the midrange blend softens.
    float vignette_r = length((uv - 0.5) * 2.0);
    float vignette_shaping = pow(
        smoothstep(VIGNETTE_START, VIGNETTE_END, vignette_r),
        VIGNETTE_EXPONENT
    );

    return mix(1.0, vignette, vignette_shaping);
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    scene_color = texelFetch(colortex5, texel, 0).rgb;

    float exposure = texelFetch(colortex5, ivec2(0), 0).a;

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
