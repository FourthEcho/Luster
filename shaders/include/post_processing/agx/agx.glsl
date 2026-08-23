#if !defined INCLUDE_POST_PROCESSING_AGX
#define INCLUDE_POST_PROCESSING_AGX

// AGX — Algorithmic tonemapping by Troy Sobotka (OpenColorIO)
// Reference: https://github.com/AcademySoftwareFoundation/OpenColorIO
// Three "look" variants are provided: Base, Golden, Punchy.

// ACES matrices.glsl already declares rec2020_to_ap0 and ap0_to_rec2020,
// so we just include it to get the conversion matrices we need.
#include "/include/post_processing/aces/matrices.glsl"
#include "/include/utility/color.glsl"

// --- AGX parameters ----------------------------------------------------------

const float agx_min_ev = -12.47393;
const float agx_max_ev =  4.026069;
const float agx_pre_exposure = 1.0;

// 3-stop inset: slope (desaturate), power (shape midtone)
const vec3 agx_inset_slope = vec3(0.42);
const vec3 agx_inset_power = vec3(1.95);

// --- AGX log encode / decode -------------------------------------------------

vec3 agx_log_enc(vec3 rgb) {
    // Inset (desaturate + shape)
    vec3 luma = vec3(dot(rgb, luminance_weights_rec2020));
    vec3 inset = luma + (rgb - luma) * agx_inset_slope;
    inset = pow(max(inset, vec3(0.0)), agx_inset_power);

    vec3 log_rgb = log2(inset + eps);
    log_rgb = (log_rgb - agx_min_ev) / (agx_max_ev - agx_min_ev);
    return clamp(log_rgb, 0.0, 1.0);
}

vec3 agx_log_dec(vec3 log_rgb) {
    vec3 inset = agx_min_ev + log_rgb * (agx_max_ev - agx_min_ev);
    vec3 rgb = pow(vec3(2.0), inset);
    rgb = pow(max(rgb, vec3(0.0)), 1.0 / agx_inset_power);
    vec3 luma = vec3(dot(rgb, luminance_weights_rec2020));
    return luma + (rgb - luma) / agx_inset_slope;
}

// --- AGX base ----------------------------------------------------------------

vec3 agx_base(vec3 rgb) {
    rgb = clamp(rgb, vec3(0.0), vec3(1e8));
    rgb *= agx_pre_exposure;

    // Rec.2020 -> AP0
    rgb = rec2020_to_ap0 * rgb;

    vec3 log_rgb = agx_log_enc(rgb);
    log_rgb = log_rgb / (1.0 + log_rgb);
    vec3 out_rgb = agx_log_dec(log_rgb);

    return ap0_to_rec2020 * out_rgb;
}

// --- AGX "look" transforms (applied on the [0,1] Rec.2020 output) ------------

vec3 agx_look_golden(vec3 rgb) {
    // Warmer, slightly desaturated, lifted shadows
    const vec3 slope  = vec3(1.0, 0.97, 0.90);
    const vec3 offset = vec3(0.0, 0.005, 0.012);
    const vec3 power  = vec3(0.95, 1.0, 1.05);
    const float sat   = 0.95;

    float luma = dot(rgb, luminance_weights_rec2020);
    vec3 tint = (rgb - luma) * sat + luma;
    return pow(max(tint * slope + offset, vec3(0.0)), power);
}

vec3 agx_look_punchy(vec3 rgb) {
    // Higher contrast + saturation, deeper blacks
    const vec3 slope  = vec3(1.15);
    const vec3 offset = vec3(0.0);
    const vec3 power  = vec3(0.90);
    const float sat   = 1.20;

    float luma = dot(rgb, luminance_weights_rec2020);
    vec3 tint = (rgb - luma) * sat + luma;
    return pow(max(tint * slope + offset, vec3(0.0)), power);
}

// --- Public tonemap entries --------------------------------------------------

vec3 tonemap_agx(vec3 rgb) {
    return agx_base(rgb);
}

vec3 tonemap_agx_golden(vec3 rgb) {
    return agx_look_golden(agx_base(rgb));
}

vec3 tonemap_agx_punchy(vec3 rgb) {
    return agx_look_punchy(agx_base(rgb));
}

#endif // INCLUDE_POST_PROCESSING_AGX
