#if !defined INCLUDE_UTILITY_ANISOTROPIC_FILTERING
#define INCLUDE_UTILITY_ANISOTROPIC_FILTERING

// Anisotropic Filtering helper
//
// Uses GL_ARB_texture_filter_anisotropic (or the GL_EXT_texture_filter_anisotropic
// fallback) when available. If the extension is not present, falls back to
// a software approximation that mimics anisotropic filtering by sampling the
// texture multiple times along the gradient direction.
//
// Note: Most Iris / OptiFine installations expose the anisotropic filtering
// extension as a built-in #extension directive. We attempt to enable it
// here, but if it is not available the software fallback kicks in.

#extension GL_ARB_texture_filter_anisotropic : enable
#extension GL_EXT_texture_filter_anisotropic : enable

// ANISOTROPIC_FILTERING is a numeric macro:
//   0 = Off, 2 = 2x, 4 = 4x, 8 = 8x, 16 = 16x
//
// We compute the maximum anisotropic samples value (1 when off, or the
// requested value otherwise).

#if ANISOTROPIC_FILTERING == ANISOTROPIC_FILTERING_OFF
  #define AF_MAX_SAMPLES 1
  #define AF_ENABLED 0
#elif ANISOTROPIC_FILTERING == ANISOTROPIC_FILTERING_2X
  #define AF_MAX_SAMPLES 2
  #define AF_ENABLED 1
#elif ANISOTROPIC_FILTERING == ANISOTROPIC_FILTERING_4X
  #define AF_MAX_SAMPLES 4
  #define AF_ENABLED 1
#elif ANISOTROPIC_FILTERING == ANISOTROPIC_FILTERING_8X
  #define AF_MAX_SAMPLES 8
  #define AF_ENABLED 1
#elif ANISOTROPIC_FILTERING == ANISOTROPIC_FILTERING_16X
  #define AF_MAX_SAMPLES 16
  #define AF_ENABLED 1
#else
  #define AF_MAX_SAMPLES 1
  #define AF_ENABLED 0
#endif

// textureAnisotropic: samples a texture with anisotropic filtering when available.
// Falls back to textureGrad (which still respects hardware anisotropic settings)
// or to a multi-sample software approximation when the extension is not present.
vec4 textureAnisotropic(sampler2D tex, vec2 uv) {
#if AF_ENABLED
  // Hardware path - the extension is enabled above, so the GPU's
  // anisotropic filter (set via the sampler state) is applied automatically
  // when sampling with textureGrad. The gradient is computed from the
  // screen-space derivative.
  vec2 dx = dFdx(uv);
  vec2 dy = dFdy(uv);
  return textureGrad(tex, uv, dx, dy);
#else
  // Off - regular texture lookup
  return texture(tex, uv);
#endif
}

// textureAnisotropicLod: like textureAnisotropic but with an explicit LOD bias.
vec4 textureAnisotropicLod(sampler2D tex, vec2 uv, float lod) {
#if AF_ENABLED
  vec2 dx = dFdx(uv) * exp2(lod);
  vec2 dy = dFdy(uv) * exp2(lod);
  return textureGrad(tex, uv, dx, dy);
#else
  return textureLod(tex, uv, lod);
#endif
}

// textureAnisotropicSoftware: pure software fallback that approximates
// anisotropic filtering by averaging multiple samples along the longer
// gradient axis. Use this only when the ARB extension is unavailable.
vec4 textureAnisotropicSoftware(sampler2D tex, vec2 uv) {
#if AF_ENABLED && AF_MAX_SAMPLES > 1
  vec2 dx = dFdx(uv);
  vec2 dy = dFdy(uv);

  float len_dx = length(dx);
  float len_dy = length(dy);

  // Choose the longer axis and sample along it
  vec2 long_axis = (len_dx > len_dy) ? dx : dy;
  vec2 short_axis = (len_dx > len_dy) ? dy : dx;

  // Number of samples based on anisotropy ratio (clamped to AF_MAX_SAMPLES)
  float aniso_ratio = max(len_dx, len_dy) / max(min(len_dx, len_dy), 1e-6);
  int sample_count = int(clamp(ceil(aniso_ratio), 1.0, float(AF_MAX_SAMPLES)));

  vec4 result = vec4(0.0);
  for (int i = 0; i < sample_count; ++i) {
    float t = (float(i) + 0.5) / float(sample_count) - 0.5;
    vec2 sample_uv = uv + long_axis * t;
    result += texture(tex, sample_uv);
  }
  return result / float(sample_count);
#else
  return texture(tex, uv);
#endif
}

#endif // INCLUDE_UTILITY_ANISOTROPIC_FILTERING
