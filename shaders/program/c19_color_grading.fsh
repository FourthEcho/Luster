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

#if GRADE_WHITE_BALANCE != 6500
flat in mat3 white_balance_matrix;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // bloom tiles
uniform sampler2D colortex3; // bloomy-fog/transmittance factor from c1
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
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"

vec3 get_bloom() {
    // Upsample last bloom tile. 

    vec2 pad_amount = 6.0 * view_pixel_size;
    vec2 uv_src = clamp(uv, pad_amount, 1.0 - pad_amount) * 0.5;

    return BLOOM_UPSAMPLING_FILTER(colortex0, uv_src).rgb;
}

// Color grading

vec3 gain(vec3 x, float k) {
    vec3 a = 0.5 * pow(2.0 * mix(x, 1.0 - x, step(0.5, x)), vec3(k));
    return mix(a, 1.0 - a, step(0.5, x));
}

// Color grading applied before tone mapping
// rgb := color in acescg [0, inf]
vec3 grade_input(vec3 rgb) {
    float brightness = 0.83 * GRADE_BRIGHTNESS;
    float contrast = 1.00 * GRADE_CONTRAST;
    float saturation = 0.98 * GRADE_SATURATION;

    // Brightness
    rgb *= brightness;

    // Contrast
    const float log_midpoint = log2(0.18);
    rgb = log2(rgb + eps);
    rgb = contrast * (rgb - log_midpoint) + log_midpoint;
    rgb = max0(exp2(rgb) - eps);

    // Saturation
    float lum = dot(rgb, luminance_weights);
    rgb = max0(mix(vec3(lum), rgb, saturation));

    // Vibrance — perceptual chroma boost.
    // Unlike simple saturation, vibrance boosts chroma more strongly for
    // mid- and low-saturation colors while leaving already-saturated colors
    // (and skin tones) relatively untouched. Implemented in HSL space where
    // the existing orange/teal/green grading also runs, so the visual style
    // is consistent.
    // GRADE_VIBRANT in [-1, 1]: negative = desaturate, positive = boost chroma.
#if GRADE_VIBRANT != 0.0
    {
        vec3 hsl = rgb_to_hsl(rgb);

        // Vibrance scaling: low-sat colors get a bigger boost than high-sat.
        // This is the classic Lightroom-style "vibrance" curve.
        float chroma = hsl.y;
        float vibrance_scale = 1.0 + GRADE_VIBRANT * (1.0 - chroma);

        // Protect very dark colors (would otherwise blow out chroma on
        // near-blacks) by fading the boost as lightness -> 0.
        float luma_guard = smoothstep(0.0, 0.15, hsl.z);
        vibrance_scale = mix(1.0, vibrance_scale, luma_guard);

        hsl.y = clamp01(chroma * vibrance_scale);
        rgb = hsl_to_rgb(hsl);
    }
#endif

    // White balance
#if GRADE_WHITE_BALANCE != 6500
    rgb = rgb * rec2020_to_xyz;
    rgb = rgb * white_balance_matrix;
    rgb = rgb * xyz_to_rec2020;
#endif

    rgb = max0(rgb);

    return rgb;
}

// Color grading applied after tone mapping
// rgb := color in linear rec.709 [0, 1]
vec3 grade_output(vec3 rgb) {
    // Convert to roughly perceptual RGB for color grading
    rgb = sqrt(rgb);

    // HSL color grading inspired by Tech's color grading setup in Lux Shaders

    const float orange_sat_boost = GRADE_ORANGE_SAT_BOOST;
    const float teal_sat_boost = GRADE_TEAL_SAT_BOOST;
    const float green_sat_boost = GRADE_GREEN_SAT_BOOST;
    const float green_hue_shift = GRADE_GREEN_HUE_SHIFT / 360.0;

    vec3 hsl = rgb_to_hsl(rgb);

    // Oranges
    float orange = isolate_hue(hsl, 30.0, 20.0);
    hsl.y *= 1.0 + orange_sat_boost * orange;

    // Teals
    float teal = isolate_hue(hsl, 210.0, 20.0);
    hsl.y *= 1.0 + teal_sat_boost * teal;

    // Greens
    float green = isolate_hue(hsl, 90.0, 44.0);
    hsl.x += green_hue_shift * green;
    hsl.y *= 1.0 + green_sat_boost * green;

    rgb = hsl_to_rgb(hsl);

    rgb = gain(rgb, 1.05);

    // Gamma — applied post-tonemap on linear rec.709 output.
    // pow(rgb, 1/gamma): gamma < 1 brightens midtones, gamma > 1 darkens them.
    // Skipped at gamma == 1.0 to avoid the pow() cost on the hot path.
#if GRADE_GAMMA != 1.0
    rgb = pow(clamp01(rgb), vec3(1.0 / GRADE_GAMMA));
#endif

    return sqr(rgb);
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

    return vignette;
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

#ifdef VIGNETTE
    scene_color *= vignette(uv);
#endif

    scene_color = grade_input(scene_color);

#ifdef TONEMAP_COMPARISON
    scene_color
        = uv.x < 0.5 ? tonemap_left(scene_color) : tonemap_right(scene_color);
#else
    scene_color = tonemap(scene_color);
#endif

    scene_color = clamp01(scene_color * working_to_display_color);
    scene_color = grade_output(scene_color);

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
