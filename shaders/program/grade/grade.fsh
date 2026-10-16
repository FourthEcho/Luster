/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#include "/lib/global.glsl"

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

#ifdef colorGrading
  #if gradeWhiteBalance != 6500
flat in mat3 white_balance_matrix;
  #endif
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // bloomColor tiles
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

#if !defined INCLUDE_POST_TONEMAP_OPERATORS
#define INCLUDE_POST_TONEMAP_OPERATORS


#include "/lib/util/color.glsl"
#include "/lib/academy/aces.glsl"

// ACES Fit
// ACES RRT and ODT approximation
vec3 tonemap_aces_fit(vec3 rgb) {
    rgb *= 1.6 * exp2(academyRrtExposure); // Match the exposure to the RRT

    rgb = rgb * working_to_ap0;

    rgb = rrt_sweeteners(rgb);
    rgb = rrt_and_odt_fit(rgb);

    // Global desaturation (fit domain is AP0/AP1; use stable AP1 luma so
    // the result does not drift with displayGamut).
    vec3 grayscale = vec3(dot(rgb, luminance_weights_ap1));
    rgb = mix(grayscale, rgb, odt_sat_factor);

    return academy_color_controls(rgb * ap1_to_working);
}

// ACES Full
// ACES RRT and ODT
vec3 tonemap_aces_full(vec3 rgb) {
    rgb *= 1.6 * exp2(academyRrtExposure); // Match the exposure to the RRT

    rgb = rgb * working_to_ap0;

    rgb = aces_rrt(rgb);
    rgb = aces_odt(rgb);

    return academy_color_controls(rgb * ap1_to_working);
}

// Lottes
// Timothy Lottes 2016, "Advanced Techniques and Optimization of HDR Color
// Pipelines" https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf

// https://github.com/dmnsgn/shaders-tone-map (MIT; see the Lottes MIT license reproduced in the root LICENSE)
vec3 tonemap_lottes(vec3 rgb) {
    rgb = max(rgb, vec3(0.0)); // pow() of negatives is NaN
    const vec3 a = vec3(1.6); // Contrast
    const vec3 d = vec3(0.977); // Shoulder contrast
    const vec3 hdr_max = vec3(8.0); // White point
    const vec3 mid_in = vec3(0.18); // Fixed midpoint x
    const vec3 mid_out = vec3(0.267); // Fixed midpoint y

    const vec3 b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    const vec3 c = (pow(hdr_max, a * d) * pow(mid_in, a)
                    - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);

    return pow(rgb, a) / (pow(rgb, a * d) * b + c);
}

// Hejl 2015
// Hejl 2015 filmic, after Jim Hejl's reference ("ToneMapFilmic_Hejl2015").
// GLSL port follows https://github.com/dmnsgn/shaders-tone-map (MIT; see
// the Hejl 2015 MIT license reproduced in the root LICENSE), including its guard: the curve goes negative just above


vec3 tonemap_hejl_2015(vec3 rgb) {
    const float white_point = 5.0;

    vec4 vh = vec4(rgb, white_point);
    vec4 va = (1.425 * vh) + 0.05; // eval filmic curve
    vec4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;

    return max(vec3(0.0), vf.rgb / vf.www); // white point correction
}


// Filmic tonemapping operator made by Jim Hejl and Richard Burgess-Dawson
// ("Filmic Tonemapping for Real-time Rendering", SIGGRAPH 2010 course).
// Modified by Tech to not lose color information below 0.004 (replaces the

vec3 tonemap_hejl_burgess(vec3 rgb) {
    rgb = rgb * min(vec3(1.0), 1.0 - 0.8 * exp(rcp(-0.004) * rgb));
    rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return srgb_eotf_inv(rgb); // Revert built-in sRGB conversion
}

// Tech
// Tone mapping operator made by Tech for his shader pack Lux
vec3 tonemap_tech(vec3 rgb) {
    vec3 a = rgb * min(vec3(1.0), 1.0 - exp(-1.0 / 0.038 * rgb));
    a = mix(a, rgb, rgb * rgb);
    return a / (a + 0.6);
}

// Uncharted 2
// Filmic tonemapping operator made by John Hable for Uncharted 2
vec3 tonemap_uncharted_2_partial(vec3 rgb) {
    const float a = 0.15;
    const float b = 0.50;
    const float c = 0.10;
    const float d = 0.20;
    const float e = 0.02;
    const float f = 0.30;

    return ((rgb * (a * rgb + (c * b)) + (d * e))
            / (rgb * (a * rgb + b) + d * f))
        - e / f;
}

vec3 tonemap_uncharted_2(vec3 rgb) {
    const float exposure_bias = 2.0;
    const vec3 w = vec3(11.2);

    vec3 curr = tonemap_uncharted_2_partial(rgb * exposure_bias);
    vec3 white_scale = vec3(1.0) / tonemap_uncharted_2_partial(w);
    return curr * white_scale;
}

// Ozius
// Tonemapping operator made by Zombye for his old shader pack Ozius
// It was given to me by Jessie
vec3 tonemap_ozius(vec3 rgb) {
    const vec3 a = vec3(0.46, 0.46, 0.46);
    const vec3 b = vec3(0.60, 0.60, 0.60);

    rgb *= 1.6;

    vec3 cr = mix(vec3(dot(rgb, luminance_weights)), rgb, 0.5) + 1.0;

    rgb = pow(rgb / (1.0 + rgb), a);
    return pow(rgb * rgb * (-2.0 * rgb + 3.0), cr / b);
}

// Reinhard
vec3 tonemap_reinhard(vec3 rgb) { return rgb / (rgb + 1.0); }

// Reinhard Jodie
// Reinhard driven by luminance, then blended per channel by the per-channel

// see https://64.github.io/tonemapping/#reinhard-jodie


vec3 tonemap_reinhard_jodie(vec3 rgb) {
    vec3 reinhard = rgb / (rgb + 1.0);
    return mix(rgb / (dot(rgb, luminance_weights) + 1.0), reinhard, reinhard);
}

#endif // INCLUDE_POST_TONEMAP_OPERATORS
#if !defined INCLUDE_COLOR_GRADING
#define INCLUDE_COLOR_GRADING

// Stage A: scene-linear controls before tone mapping.
// Stage B: display-linear perceptual controls after tone mapping.

vec3 color_grade_lift_gamma_gain(vec3 rgb) {
    // Log-domain-friendly lift, then power/gain. Defaults are mathematically neutral.
    vec3 lift = vec3(gradeLiftR, gradeLiftG, gradeLiftB);
    vec3 gamma = vec3(max(gradeGammaR, 0.05), max(gradeGammaG, 0.05), max(gradeGammaB, 0.05));
    vec3 gain = vec3(gradeGainR, gradeGainG, gradeGainB);

    rgb = max(rgb + lift, vec3(0.0));
    rgb = pow(rgb, rcp(gamma));
    return max(rgb * gain, vec3(0.0));
}

vec3 color_grade_input(vec3 rgb, mat3 white_balance_matrix) {
    float brightness = max(gradeBrightness, 0.0);
    float contrast = max(gradeContrast, 0.0);
    float pivot = max(gradePivot, 1e-4);

    rgb = max(rgb, vec3(0.0));
    rgb *= brightness;

    // Symmetric contrast around a scene-linear pivot, performed in log space so exposure stops stay natural.
    rgb = log2(rgb + 1e-6);
    float log_pivot = log2(pivot);
    rgb = exp2((rgb - log_pivot) * contrast + log_pivot);
    rgb = max(rgb - 1e-6, vec3(0.0));

    // White balance in chromaticity space. A Bradford matrix is calculated in the vertex shader.
    rgb = max(rgb * white_balance_matrix, vec3(0.0));

    // Lift / gamma / gain (ASC-style three-way control).
    rgb = color_grade_lift_gamma_gain(rgb);
    return max(rgb, vec3(0.0));
}


vec3 grade_rgb_to_oklab(vec3 c) {
    vec3 lms = c * working_to_xyz_color * xyz_to_lms;
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return vec3(
        0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
        1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
        0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z
    );
}

vec3 grade_oklab_to_rgb(vec3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    vec3 lms = vec3(l, m, s);
    lms = lms * lms * lms;
    return max((lms * lms_to_xyz) * xyz_to_working_color, vec3(0.0));
}

vec2 grade_rotate(vec2 v, float radians_angle) {
    float s = sin(radians_angle), c = cos(radians_angle);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec2 grade_hue_vector(float degrees, float saturation) {
    float h = radians(degrees);
    return vec2(cos(h), sin(h)) * saturation;
}

vec3 color_grade_output(vec3 rgb) {
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));

    vec3 lab = grade_rgb_to_oklab(rgb);
    float chroma = length(lab.yz);

    // Global saturation + vibrance: vibrance preferentially boosts low-chroma colors.
    float vibrance_mask = 1.0 - clamp(chroma * 3.5, 0.0, 1.0);
    float sat_mul = max(gradeSaturation + gradeVibrance * vibrance_mask, 0.0);
    lab.yz *= sat_mul;

    // Gentle perceptual contrast with a stable pivot around middle gray.
    lab.x = clamp((lab.x - gradeOklabPivot) * gradeOklabContrast + gradeOklabPivot, 0.0, 1.0);

    // Split-tone masks use the perceptual lightness channel.
    float shadows = 1.0 - smoothstep(gradeShadowLow, gradeShadowHigh, lab.x);
    float highlights = smoothstep(gradeHighlightLow, gradeHighlightHigh, lab.x);
    float mids = clamp(1.0 - shadows - highlights, 0.0, 1.0);

    // Three-way hue rotation while preserving existing chroma magnitude.
    if (chroma > 1e-6) {
        float shadow_w = shadows * gradeShadowStrength;
        float mid_w = mids * gradeMidStrength;
        float highlight_w = highlights * gradeHighlightStrength;
        vec2 ab = lab.yz;
        ab = grade_rotate(ab, radians(gradeShadowHue) * shadow_w);
        ab = grade_rotate(ab, radians(gradeMidHue) * mid_w);
        ab = grade_rotate(ab, radians(gradeHighlightHue) * highlight_w);
        lab.yz = ab;
    }

    // Add controlled chroma bias for classic split toning.
    float tint_scale = sqrt(max(lab.x, 0.0));
    lab.yz += grade_hue_vector(gradeShadowTintHue, gradeShadowTintSat * shadows) * tint_scale;
    lab.yz += grade_hue_vector(gradeHighlightTintHue, gradeHighlightTintSat * highlights) * tint_scale;

    // Convert the perceptual pass back to RGB, then apply selective HSL accents.
    vec3 perceptual_rgb = grade_oklab_to_rgb(lab);
    vec3 hsv = rgb_to_hsv(perceptual_rgb);
    float orange = isolate_hue(hsv, 30.0, 20.0);
    float teal = isolate_hue(hsv, 210.0, 20.0);
    float green = isolate_hue(hsv, 90.0, 44.0);
    hsv.y = clamp(hsv.y * (1.0 + gradeOrangeSatBoost * orange), 0.0, 1.0);
    hsv.y = clamp(hsv.y * (1.0 + gradeTealSatBoost * teal), 0.0, 1.0);
    hsv.y = clamp(hsv.y * (1.0 + gradeGreenSatBoost * green), 0.0, 1.0);
    hsv.x = fract(hsv.x + (gradeGreenHueShift / 360.0) * green);
    vec3 selective_rgb = hsv_to_rgb(hsv);
    rgb = mix(perceptual_rgb, selective_rgb, clamp(gradeSelectiveBlend, 0.0, 1.0));

    // Black/white point control, applied last to avoid fighting the tonemapper.
    rgb = max((rgb - gradeBlackPoint) / max(1.0 - gradeBlackPoint - gradeWhitePoint, 1e-4), vec3(0.0));
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));
    return rgb;
}

#endif
#if !defined INCLUDE_CAMERA_CAMERA
#define INCLUDE_CAMERA_CAMERA

// Reference setup: every triangle factor is normalized to these, so the
// shipped defaults reproduce the pre-physical look exactly.
const float camera_reference_fstops = 3.2;
const float camera_reference_shutter = 60.0; // 1/60 s
const float camera_reference_iso = 100.0;

// Focal length in millimetres from the vertical FOV and the sensor height
// (sensor width shared across axes, height derived from aspect ratio).
float camera_sensor_height_mm(float aspect_ratio) {
    return float(camSensorWidth) / max(aspect_ratio, 1e-4);
}

float camera_focal_length_mm(float projection_11, float aspect_ratio) {
    float sensor_h = camera_sensor_height_mm(aspect_ratio);
    return 0.5 * sensor_h * projection_11;
}

// Thin-lens circle of confusion as a fraction of screen height:
// CoC = (f^2 / N) * |1/S - 1/D|, distances in metres.
float camera_coc_height_fraction(
    float focal_mm,
    float sensor_h,
    float focus_m,
    float dist_m
) {
    float coc_mm = focal_mm * focal_mm / max(camFstops, 1e-4)
        * abs(1.0 / (focus_m * 1000.0) - 1.0 / (dist_m * 1000.0));
    return coc_mm / max(sensor_h, 1e-4);
}

// Shutter trail factor relative to the 60Hz reference capture.
float camera_shutter_trail_factor() {
    return camera_reference_shutter / float(camShutterSpeed);
}

// Closed-triangle exposure factor: t * ISO / N^2, normalized to the
// reference setup, times the EV compensation dial.
float camera_exposure_triangle_factor() {
    float t = camera_shutter_trail_factor();
    float iso = float(camIso) / camera_reference_iso;
    float n = camera_reference_fstops / max(camFstops, 1e-4);
    return t * iso * n * n * exp2(camExposureCompensation);
}

#endif // INCLUDE_CAMERA_CAMERA
#if !defined INCLUDE_CAMERA_LOCAL_EXPOSURE
#define INCLUDE_CAMERA_LOCAL_EXPOSURE

#include "/lib/util/color.glsl"

float local_exposure_luma(vec3 rgb) {
    return max(dot(max(rgb, vec3(0.0)), luminance_weights_ap1), 1e-5);
}

#ifdef localExposure
float compute_local_exposure_ev(vec2 texel_uv, vec3 center_rgb, float anchor_log) {
    float center_log = log2(local_exposure_luma(center_rgb));

    float sum_log = center_log * 4.0;
    float sum_w = 4.0;


    // a per-pixel post pass; larger-scale adaptation is already handled by the

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

    // Centered on the global meter anchor, not an absolute middle gray.
    // Same adaptation for detail and regional so the two stages agree.
    const float adaptation = 0.28;
    float ev = (anchor_log - local_log) * adaptation;


    ev = clamp(ev * localExposureDetail, -0.6666667, 0.6666667);


    float region_lod = ceil(log2(max_of(rcp(view_pixel_size)) * 0.02));
    vec3 region_rgb
        = textureLod(colortex5, texel_uv, region_lod).rgb;
    float region_log = log2(local_exposure_luma(region_rgb));
    float region_ev = clamp(
        (anchor_log - region_log) * adaptation,
        -localExposureRange,
        localExposureRange
    );

    return mix(ev, region_ev, localExposureRegional);
}
#endif

#endif // INCLUDE_CAMERA_LOCAL_EXPOSURE
// Vignette mask (inlined; only used by this grading stage)
float vignetteMask(vec2 uv) {
    const float vignette_size = 16.0;
    const float vignette_intensity = 0.08 * vignetteIntensity;

    float darkness_pulse = 1.0 - dampen(abs(cos(2.0 * frameTimeCounter)));

    float vignetteBase
        = vignette_size * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    vignetteBase = pow(
        vignetteBase,
        vignette_intensity + 0.1 * biome_cave + 0.3 * blindness
            + 0.2 * darkness_pulse * darknessFactor
    );


    float vignette_r = length((uv - 0.5) * 2.0);
    float vignette_shaping = pow(
        smoothstep(
            vignetteStart,
            max(vignetteEnd, vignetteStart + 1e-3),
            vignette_r
        ),
        vignetteExponent
    );

    return mix(1.0, vignetteBase, vignette_shaping);
}
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#if !defined INCLUDE_CAMERA_LENS_FLARE
#define INCLUDE_CAMERA_LENS_FLARE

#ifdef lensFlare
// Blurred bright source: bloom tile 2 is the full frame downsampled into a
// Threshold is subtractive so sub-threshold sky contributes exactly zero.
vec3 lens_flare_source(vec2 screen_uv) {
#ifdef bloom
    const float tile_scale = 0.5 * exp2(-2.0);
    const vec2 tile_offset = vec2(1.0 - exp2(-2.0), 0.0);
    vec2 tile_uv = clamp(screen_uv, vec2(0.0), vec2(1.0)) * tile_scale
        + tile_offset;
    vec3 c = bicubic_filter(colortex0, tile_uv).rgb;
#else
    vec3 c = texture(colortex5, clamp(screen_uv, vec2(0.0), vec2(1.0))).rgb;
#endif
    return max0(c - lensFlareThreshold);
}

// Project the sun into screen UV; facing fades to 0 as the sun drops
// below the horizon or swings behind the camera.
vec2 lens_flare_sun_uv(out float facing) {
    vec3 view_sun = mat3(gbufferModelView) * sun_dir;
    vec4 clip = gbufferProjection * vec4(view_sun * 100.0, 1.0);
    vec2 sun_uv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
    facing = smoothstep(0.05, -0.15, view_sun.z)
        * smoothstep(-0.12, 0.02, sun_dir.y);
    return sun_uv;
}


vec3 lens_flare_ghosts(vec2 uv) {
    vec2 mirror = 1.0 - uv;
    vec2 axis = (vec2(0.5) - mirror) * lensFlareSpacing;

    vec3 acc = vec3(0.0);
    for (int i = 1; i <= lensFlareGhosts; ++i) {
        float fi = float(i);
        vec2 base = mirror + axis * fi;
        if (clamp01(base) != base) {
            continue;
        }
        vec3 ghost;
        ghost.r = lens_flare_source(base + axis * 0.01 * fi).r;
        ghost.g = lens_flare_source(base).g;
        ghost.b = lens_flare_source(base - axis * 0.01 * fi).b;

        float edge = 1.0 - smoothstep(0.0, 0.75, length(base - 0.5));
        acc += ghost * (edge * edge) / (1.0 + fi * 0.5);
    }

    return acc;
}

#ifdef lensFlareHalo
// Halo ring around the sun position: gaussian annulus sampled
// chromatically, widened/narrowed by the width control.
vec3 lens_flare_halo(vec2 uv, vec2 sun_uv) {
    vec2 huv = uv - sun_uv;
    huv.x *= aspectRatio;
    float dist = length(huv);
    vec2 dir = huv / max(dist, 1e-4);

    float ring = exp(
        -pow(
            (dist / max(lensFlareHaloRadius, 1e-4) - 1.0)
                / max(lensFlareHaloWidth, 0.05),
            2.0
        )
    );
    if (ring < 1e-4) {
        return vec3(0.0);
    }

    vec2 base = sun_uv + dir * lensFlareHaloRadius
        * vec2(1.0 / aspectRatio, 1.0);
    vec3 halo;
    halo.r = lens_flare_source(base + dir * 0.004).r;
    halo.g = lens_flare_source(base).g;
    halo.b = lens_flare_source(base - dir * 0.004).b;

    return halo * ring;
}
#endif

vec3 get_lens_flare(vec2 uv) {
    float facing;
    vec2 sun_uv = lens_flare_sun_uv(facing);
    if (facing < 1e-4) {
        return vec3(0.0);
    }

    vec3 flare = lens_flare_ghosts(uv);
#ifdef lensFlareHalo
    flare += lens_flare_halo(uv, sun_uv);
#endif

    // Storms and night haze kill flare faster than the sun itself dims
    flare *= facing * (1.0 - rainStrength * 0.9);


    float brightest = max(max(flare.r, flare.g), max(flare.b, 1e-4));
    flare *= (1.0 - exp(-brightest * lensFlareIntensity * 0.02))
        / brightest;

    return flare;
}
#endif

#endif // INCLUDE_CAMERA_LENS_FLARE

vec3 get_bloom() {
    // Upsample last bloomColor tile. 

    vec2 pad_amount = 6.0 * view_pixel_size;
    vec2 uv_src = clamp(uv, pad_amount, 1.0 - pad_amount) * 0.5;

    return bloomUpsamplingFilter(colortex0, uv_src).rgb;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    scene_color = texelFetch(colortex5, texel, 0).rgb;

    float exposure = texelFetch(colortex5, ivec2(0), 0).a;

#if defined lensFlare && defined WORLD_OVERWORLD
    // Lens flare in HDR before exposure/tonemap so it grades with the scene
    scene_color += get_lens_flare(uv);
#endif

#ifdef bloom
    vec3 bloomColor = get_bloom();
    // Bloom rides the exposure: hot dark-scene gain no longer blows it
    // out, bright scenes keep full bloom. No-op at exposure <= 1.
    float bloom_intensity = 0.12 * bloomIntensity
        / mix(max(exposure, 1.0), 1.0, 0.31);

    // Additive bloomColor: lerping towards bloomColor would dim the base image
    scene_color += bloomColor * bloom_intensity;

#ifdef bloomyFog
    // colortex3 is written by c1, which renders into the lower-left


    vec2 fog_uv = min(
        uv * taau_render_scale,
        vec2(taau_render_scale) - 0.5 * view_pixel_size
    );
    float fog_transmittance = texture(colortex3, fog_uv).x;
    scene_color = mix(
        bloomColor,
        scene_color,
        pow(fog_transmittance, bloomyFogIntensity)
    );
#endif
#endif


    const float exposure_calibration = 12.5 / 100.0 / 1.2;
    float triangle = max(camera_exposure_triangle_factor(), 1e-6);
    float triangle_free = exposure / triangle;
    float anchor_log = log2(0.18);
    if (triangle_free > 1e-6 && !isnan(triangle_free) && !isinf(triangle_free)) {
        anchor_log = log2(max(exposure_calibration / triangle_free, 1e-5));
    }

    scene_color *= exposure;

#ifdef localExposure
    float local_ev = compute_local_exposure_ev(uv, scene_color / max(exposure, 1e-6), anchor_log);
    scene_color *= exp2(local_ev);
#endif

#ifdef vignette
    scene_color *= vignetteMask(uv);
#endif

#ifdef colorGrading
  #if gradeWhiteBalance != 6500
    scene_color = color_grade_input(scene_color, white_balance_matrix);
  #else
    scene_color = color_grade_input(scene_color, mat3(1.0));
  #endif
#endif

#ifdef tonemapComparison
    scene_color
        = uv.x < tonemapComparisonSplit ? tonemap_left(scene_color) : tonemap_right(scene_color);
#else
    scene_color = tonemap(scene_color);
#endif

    scene_color = clamp01(scene_color * working_to_display_color);
#ifdef colorGrading
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
