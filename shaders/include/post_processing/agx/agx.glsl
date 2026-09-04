#if !defined INCLUDE_POST_PROCESSING_AGX
#define INCLUDE_POST_PROCESSING_AGX

// AGX tonemapper for Luster.
// Best-practice minimal AgX without LUT, matching Blender 4.0+ / Filament /
// Godot / three.js. Input and output are linear Rec.709 (linear sRGB).
// Source chain: bWFuanVzYWth/AgX (minimal sigmoid) + EaryChow/AgX_LUT_Gen
// (log formulation) + Filament ToneMapper.cpp (matrices) + Godot tonemap.glsl
// (combined Rec.709->Rec.2020 inset). MIT - see license.md.

#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"

// sRGB OETF / EOTF helpers are provided by color.glsl; we keep local
// saturate helper for agx_curve3 domain.

vec3 agx_saturate(vec3 v) {
    return clamp(v, 0.0, 1.0);
}

// Sigmoid curve used by AgX inset domain. Threshold at 0.606... matches
// Blender's AgXBaseRec2020.py.
vec3 agx_curve3(vec3 v) {
    const float threshold = 0.6060606060606061;
    const float a_up = 69.86278913545539;
    const float a_down = 59.507875;
    const float b_up = 3.25;
    const float b_down = 3.0;
    const float c_up = -0.3076923076923077;
    const float c_down = -0.3333333333333333;

    vec3 mask = step(v, vec3(threshold));
    vec3 a = a_up + (a_down - a_up) * mask;
    vec3 b = b_up + (b_down - b_up) * mask;
    vec3 c = c_up + (c_down - c_up) * mask;
    return 0.5
        + ((-2.0 * threshold) + 2.0 * v)
            * pow(1.0 + a * pow(abs(v - threshold), b), c);
}

// Combined Rec.709 <-> Rec.2020 and AgX inset/outset. Column-major for GLSL.

// EaryChow / Godot combined Rec.709 -> Rec.2020 + AgX inset (Blender LUT Gen).
const mat3 agx_srgb_to_rec2020_inset = mat3(
    0.544814746488245, 0.140416948464053, 0.0888104196149096,
    0.373787398372697, 0.754137554567394, 0.178871756420858,
    0.0813978551390581, 0.105445496968552, 0.732317823964232
);

// Inverse outset + Rec.2020 -> Rec.709.
const mat3 agx_outset_rec2020_to_srgb = mat3(
    1.96488741169489, -0.299313364904742, -0.164352742528393,
    -0.855988495690215, 1.32639796461980, -0.238183969428088,
    -0.108898916004672, -0.0278773002717756, 1.40779985617227
);

// Fallback inset/outset from bWFuanVzYWth minimal (Rec.709 only, no Rec.2020).
const mat3 agx_mat = mat3(
    0.8424010709504686, 0.04240107095046854, 0.04240107095046854,
    0.07843650156180276, 0.8784365015618028, 0.07843650156180276,
    0.0791624274877287, 0.0791624274877287, 0.8791624274877287
);

const mat3 agx_mat_inv = mat3(
    1.1969986613119143, -0.053001338688085674, -0.053001338688085674,
    -0.09804562695225345, 1.1519543730477466, -0.09804562695225345,
    -0.09895303435966087, -0.09895303435966087, 1.151046965640339
);

// Luster AGX Color controls. These are only reached by AgX tonemap operators.
vec3 agx_color_controls(vec3 color) {
    color *= exp2(AGX_EXPOSURE);

    const float pivot = 0.18;
    color = exp2((log2(max(color, vec3(1e-6))) - log2(pivot))
        * AGX_CONTRAST + log2(pivot));

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, max(AGX_SATURATION, 0.0));

    // Additional highlight compression, neutral at zero.
    float high = smoothstep(0.45, 1.0, clamp(luma, 0.0, 1.0));
    color /= 1.0 + max(AGX_HIGHLIGHT_ROLLOFF, 0.0) * high
        * max(color - vec3(pivot), vec3(0.0));

    // Punch: contrast about the perceptual midrange, symmetric around zero.
    if (AGX_PUNCH != 0.0) {
        float p = 1.0 + 0.5 * AGX_PUNCH;
        color = exp2((log2(max(color, vec3(1e-6))) - log2(pivot)) * p + log2(pivot));
    }

    // Golden look: warm highlights while preserving luminance.
    if (AGX_GOLDEN != 0.0) {
        vec3 warm = vec3(1.04, 0.97, 0.82);
        vec3 cool = vec3(0.94, 0.99, 1.06);
        vec3 tint = mix(cool, warm, clamp(0.5 + 0.5 * AGX_GOLDEN, 0.0, 1.0));
        float amount = abs(AGX_GOLDEN) * smoothstep(0.25, 1.0, clamp(luma, 0.0, 1.0));
        color = mix(color, color * tint, amount);
    }

    return clamp(color, vec3(0.0), vec3(1.0));
}


// Core AgX via log-space (EaryChow / Godot). Better highlight roll-off
// and matches Blender's AgX_Base_sRGB.cube LUT.
vec3 tonemap_agx(vec3 color) {
    // Guard against log2(0). 2e-10 is ~ -32 EV, negligible.
    color = max(color, vec3(2e-10));

    // Inset: linear sRGB -> log AgX domain (combined with Rec.2020).
    color = agx_srgb_to_rec2020_inset * color;

    const float min_ev = -12.473931188332413;
    const float max_ev = 4.026068811667588;
    const float dynamic_range = max_ev - min_ev;

    color = (log2(color) / dynamic_range) - (min_ev / dynamic_range);
    color = agx_saturate(color);
    color = agx_curve3(color);
    // Godot applies pow 2.4 (approx sRGB EOTF) before outset; keep for
    // parity with Blender's display transform.
    color = pow(color, vec3(2.4));
    color = agx_outset_rec2020_to_srgb * color;
    return agx_color_controls(agx_saturate(color));
}


// Minimal variant without Rec.2020 (slightly more saturated, faster).
// Presets via CDL-like tweaks (from dmnsgn/glsl-tone-map: agxGolden, agxPunchy).
// These are applied post-tonemap as simple per-channel scale/bias for
// artistic looks; matches Filament's AgX punch / golden.

vec3 agx_apply_look(vec3 color, vec3 slope, vec3 offset, vec3 power, float saturation) {
    // Slope/offset/power as in three.js agxCdl.
    color = pow(max(color + offset, vec3(0.0)), power);
    color = color * slope;
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = luma + saturation * (color - luma);
    return color;
}

vec3 tonemap_agx_punchy(vec3 color) {
    color = tonemap_agx(color);
    return agx_apply_look(color, vec3(1.0), vec3(0.0), vec3(1.0), 1.35);
}

vec3 tonemap_agx_golden(vec3 color) {
    color = tonemap_agx(color);
    return agx_apply_look(color, vec3(1.0, 0.9, 0.5), vec3(0.0), vec3(0.8), 1.3);
}

#endif // INCLUDE_POST_PROCESSING_AGX
