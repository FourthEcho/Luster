#if !defined INCLUDE_POST_PROCESSING_TAA
#define INCLUDE_POST_PROCESSING_TAA

// Temporal anti-aliasing helpers: neighborhood clipping (AABB + variance),
// flicker reduction, closest-fragment reprojection and the invertible
// Reinhard operator used to blend in SDR.
//
// Requires from the including program:
//   - colortex0 sampler (3x3 neighborhood source)
//   - view_pixel_size + taau_render_scale (get_closest_fragment)
//   - flat in float exposure (get_flicker_reduction)
//   - rgb_to_ycocg / ycocg_to_rgb from "/include/utility/color.glsl"
// Respects TAA_VARIANCE_CLIPPING when defined by the includer before this
// include.

#include "/include/utility/color.glsl"

// Invertible tonemapping operator (Reinhard) applied before blending the
// current and previous frames Improves the appearance of emissive objects
vec3 reinhard(vec3 rgb) { return rgb / (rgb + 1.0); }

vec3 reinhard_inverse(vec3 rgb) { return rgb / (1.0 - rgb); }

// Estimates the closest fragment in a 5x5 radius with 5 samples in a cross
// pattern Improves reprojection for objects in motion
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

// AABB clipping from "Temporal Reprojection Anti-Aliasing in INSIDE"
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

// Flicker reduction using the "distance to clamp" method from "High Quality
// Temporal Supersampling" by Brian Karis. Only used for TAAU
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

    // Fetch 3x3 neighborhood
    // a b c
    // d e f
    // g h i
    vec3 a = texelFetch(colortex0, texel + ivec2(-1, 1), 0).rgb;
    vec3 b = texelFetch(colortex0, texel + ivec2(0, 1), 0).rgb;
    vec3 c = texelFetch(colortex0, texel + ivec2(1, 1), 0).rgb;
    vec3 d = texelFetch(colortex0, texel + ivec2(-1, 0), 0).rgb;
    vec3 e = current_color;
    vec3 f = texelFetch(colortex0, texel + ivec2(1, 0), 0).rgb;
    vec3 g = texelFetch(colortex0, texel + ivec2(-1, -1), 0).rgb;
    vec3 h = texelFetch(colortex0, texel + ivec2(0, -1), 0).rgb;
    vec3 i = texelFetch(colortex0, texel + ivec2(1, -1), 0).rgb;

    // Convert to YCoCg
    // Clipping in a luminance-chrominance color space is superior because the
    // eyes are more sensitive to luminance than chrominance so an AABB where
    // luminance is one of the axes will result in less visible ghosting than
    // one which is not aligned to the luminance
    a = rgb_to_ycocg(reinhard(a));
    b = rgb_to_ycocg(reinhard(b));
    c = rgb_to_ycocg(reinhard(c));
    d = rgb_to_ycocg(reinhard(d));
    e = rgb_to_ycocg(reinhard(e));
    f = rgb_to_ycocg(reinhard(f));
    g = rgb_to_ycocg(reinhard(g));
    h = rgb_to_ycocg(reinhard(h));
    i = rgb_to_ycocg(reinhard(i));

    // Soft minimum and maximum over the cross taps averaged with the soft
    // minimum and maximum over the diagonal taps (neighborhood clamping
    // family; cf. Yang et al., "A Survey of Temporal Antialiasing
    // Techniques", 2020)
    //        b         a b c
    // (min d e f + min d e f) / 2
    //        h         g h i
    min_color = min_of(b, d, e, f, h);
    min_color += min_of(min_color, a, c, g, i);
    min_color *= 0.5;

    max_color = max_of(b, d, e, f, h);
    max_color += max_of(max_color, a, c, g, i);
    max_color *= 0.5;

#ifdef TAA_VARIANCE_CLIPPING
    // Variance clipping ("An Excursion in Temporal Supersampling")
    mat2x3 moments;
    moments[0] = (1.0 / 9.0) * (a + b + c + d + e + f + g + h + i);
    moments[1] = (1.0 / 9.0)
        * (a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h
           + i * i);

    // Strictness parameter, higher gamma => more temporally stable but more
    // ghosting
    float gamma = mix(0.75, 1.25, linear_step(0.25, 1.0, distance_factor));

    vec3 mu = moments[0];
    vec3 sigma = sqrt(moments[1] - moments[0] * moments[0]);

    min_color = max(min_color, mu - gamma * sigma);
    max_color = min(max_color, mu + gamma * sigma);
#endif

    // Perform AABB clipping in YCoCg space, which results in a tighter AABB
    // because luminance (Y) is separated from chrominance (CoCg) as its own
    // axis
    history_color = rgb_to_ycocg(history_color);
    history_color = clip_aabb(history_color, min_color, max_color);
    history_color = ycocg_to_rgb(history_color);

    return history_color;
}

#endif // INCLUDE_POST_PROCESSING_TAA
