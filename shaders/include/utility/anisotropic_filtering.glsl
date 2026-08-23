#if !defined INCLUDE_UTILITY_ANISOTROPIC_FILTERING
#define INCLUDE_UTILITY_ANISOTROPIC_FILTERING

// ---------------------------------------------------------------------------
//   Anisotropic filtering strategy
// ---------------------------------------------------------------------------
//
// The shader exposes a user-facing ANISOTROPIC_FILTERING_MODE setting with
// levels Off / 2x / 4x / 8x / 16x.
//
// When the host (Minecraft / Iris / OptiFine) exposes the
// GL_ARB_texture_filter_anisotropic extension (or the legacy
// GL_EXT_texture_filter_anisotropic), anisotropic filtering is performed
// in hardware by the texture sampler. The shader just calls texture() and
// the GPU does the rest — no extra samples, no extra cost beyond what the
// sampler already pays.
//
// When the extension is NOT available, we fall back to a full software
// implementation: we take N elongated samples along the dominant
// screen-space texture-coordinate gradient (the axis a surface is
// foreshortened along, e.g. a floor viewed at a grazing angle) and
// average them, rather than relying on a single isotropic mip sample.
// The sample count is derived from the ANISOTROPIC_FILTERING_MODE setting,
// clamped to the actual anisotropy ratio of the footprint so we don't
// waste samples when the surface isn't actually foreshortened.
//
// Either way, calling code should use the read_tex_anisotropic() macro
// below — it expands to the right thing depending on what's available.
// ---------------------------------------------------------------------------

// Detect hardware anisotropic support. Iris exposes GL extensions as
// MC_GL_<extension_name> preprocessor defines, mirroring the GL_STRING
// query. Both ARB (core in 4.6) and EXT (older drivers) spellings exist.
#if defined MC_GL_ARB_texture_filter_anisotropic \
    || defined MC_GL_EXT_texture_filter_anisotropic
  #define ANISOTROPIC_FILTERING_HARDWARE
#endif

#if ANISOTROPIC_FILTERING_MODE != ANISOTROPIC_FILTERING_OFF \
    && !defined ANISOTROPIC_FILTERING_HARDWARE

// --- Software fallback sample counts ----------------------------------------

#if ANISOTROPIC_FILTERING_MODE == ANISOTROPIC_FILTERING_2
  #define ANISOTROPIC_FILTERING_SAMPLES 2
#elif ANISOTROPIC_FILTERING_MODE == ANISOTROPIC_FILTERING_4
  #define ANISOTROPIC_FILTERING_SAMPLES 4
#elif ANISOTROPIC_FILTERING_MODE == ANISOTROPIC_FILTERING_8
  #define ANISOTROPIC_FILTERING_SAMPLES 8
#elif ANISOTROPIC_FILTERING_MODE == ANISOTROPIC_FILTERING_16
  #define ANISOTROPIC_FILTERING_SAMPLES 16
#else
  #define ANISOTROPIC_FILTERING_SAMPLES 4
#endif

// --- Software anisotropic sampler -------------------------------------------
//
// Emulates anisotropic filtering by taking several elongated samples
// along the dominant screen-space texture-coordinate gradient (the axis
// a surface is foreshortened along, e.g. a floor viewed at a grazing
// angle) and averaging them, rather than relying on a single isotropic
// mip sample. The minor-axis gradient is passed to textureGrad() so the
// mip level selection still respects the narrowest dimension of the
// footprint (matching what hardware anisotropic does).
//
// The number of samples actually taken is clamped to the real anisotropy
// ratio of the footprint — when the surface is square-on to the camera
// (ratio ~1) we take a single sample, when it's heavily foreshortened we
// take up to ANISOTROPIC_FILTERING_SAMPLES samples.
vec4 aniso_sample(sampler2D samp, vec2 texcoord, vec2 dx, vec2 dy) {
    float len_x = length(dx);
    float len_y = length(dy);

    bool x_is_major = len_x > len_y;

    vec2 major_axis = x_is_major ? dx : dy;
    vec2 minor_axis = x_is_major ? dy : dx;

    float major_len = max(len_x, len_y);
    float minor_len = max(min(len_x, len_y), 1e-6);

    float aniso_ratio = clamp(
        major_len / minor_len,
        1.0,
        float(ANISOTROPIC_FILTERING_SAMPLES)
    );
    int sample_count = int(aniso_ratio + 0.5);
    sample_count = max(sample_count, 1);

    vec4 result = vec4(0.0);
    for (int i = 0; i < sample_count; ++i) {
        float t = (float(i) + 0.5) / float(sample_count) - 0.5;
        vec2 sample_uv = texcoord + major_axis * t;
        result += textureGrad(samp, sample_uv, minor_axis, minor_axis);
    }

    return result / float(sample_count);
}

// Convenience overload that derives the gradients from the fragment
// shader's implicit derivatives. This matches the signature of
// texture(sampler, uv, lod_bias) so it can be used as a drop-in.
vec4 aniso_sample(sampler2D samp, vec2 texcoord) {
    return aniso_sample(samp, texcoord, dFdx(texcoord), dFdy(texcoord));
}

// Drop-in macro for replacing texture() calls in gbuffer shaders.
// Uses the implicit-derivative overload above.
#define read_tex_anisotropic(samp, texcoord) aniso_sample(samp, texcoord)

#endif // software fallback active

// ---------------------------------------------------------------------------
//   read_tex macro — picks hardware vs software vs plain based on context
// ---------------------------------------------------------------------------
//
// Usage in a gbuffer fragment shader:
//
//   #include "/include/utility/anisotropic_filtering.glsl"
//
//   // POM path takes precedence — it has its own gradients from the
//   // parallax trace and must use textureGrad() directly.
//   #if defined PROGRAM_GBUFFERS_TERRAIN && defined POM
//     #define read_tex(x) textureGrad(x, parallax_uv, uv_gradient[0], uv_gradient[1])
//   #elif ANISOTROPIC_FILTERING_MODE != ANISOTROPIC_FILTERING_OFF && !defined ANISOTROPIC_FILTERING_HARDWARE
//     #define read_tex(x) read_tex_anisotropic(x, uv)
//   #else
//     // Hardware anisotropic (host-managed sampler state) OR filtering
//     // disabled — plain texture() does the right thing in both cases.
//     #define read_tex(x) texture(x, uv, lod_bias)
//   #endif
//
// The macro is intentionally NOT defined here because each gbuffer
// shader has slightly different context (POM vs no-POM, uv vs parallax_uv,
// lod_bias availability, etc.) and needs to wire it up itself. The helper
// file just provides aniso_sample() and read_tex_anisotropic() when the
// software path is active.
// ---------------------------------------------------------------------------

#endif // INCLUDE_UTILITY_ANISOTROPIC_FILTERING
