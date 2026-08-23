#if !defined INCLUDE_MISC_VOXY_SUPPORT
#define INCLUDE_MISC_VOXY_SUPPORT

// Voxy mod support — GUI-driven toggles + sliders that gate Voxy-specific
// shader paths. These are referenced from the per-world Voxy programs
// (world0/world1/world-1/voxy_*.glsl) and from the master
// shaders/program/voxy_*.glsl files.
//
// Voxy supplies its own fragment parameter struct (see
// docs/voxy_fragment_parameters.txt):
//
//   struct VoxyFragmentParameters {
//       vec4 sampledColour;
//       vec2 tile;
//       vec2 uv;
//       uint face;
//       uint modelId;
//       vec2 lightMap;
//       vec4 tinting;
//       uint customId;
//   };
//
// The Voxy shader stage calls `void voxy_emitFragment(VoxyFragmentParameters)`
// which we implement in program/voxy_opaque.glsl and program/voxy_translucent.glsl.

// --- Quality mode (master switch) -------------------------------------------
// 0 = off (Voxy paths fully disabled)
// 1 = basic (forward diffuse + simple fog)
// 2 = standard (basic + PBR materials + specular)
// 3 = high (standard + shadows + LPV colour)
const int VOXY_QUALITY_OFF      = 0;
const int VOXY_QUALITY_BASIC    = 1;
const int VOXY_QUALITY_STANDARD = 2;
const int VOXY_QUALITY_HIGH     = 3;
#ifndef VOXY_QUALITY
#define VOXY_QUALITY VOXY_QUALITY_STANDARD
#endif

// --- Lighting model toggle --------------------------------------------------
// 0 = vanilla lightmap only (cheap)
// 1 = full PBR with sky/blocklight mixing (default)
#ifndef VOXY_LIGHTING_MODE
#define VOXY_LIGHTING_MODE 1
#endif

// --- Shadow toggle for Voxy geometry ----------------------------------------
#ifdef VOXY_SHADOWS
#define VOXY_SHADOWS_ENABLED 1
#else
#define VOXY_SHADOWS_ENABLED 0
#endif

// --- Reflections toggle for Voxy translucent --------------------------------
#ifdef VOXY_REFLECTIONS
#define VOXY_REFLECTIONS_ENABLED 1
#else
#define VOXY_REFLECTIONS_ENABLED 0
#endif

// --- Helper predicates used by the voxy_* programs --------------------------

bool voxy_enabled() {
    return VOXY_QUALITY > VOXY_QUALITY_OFF;
}

bool voxy_uses_pbr() {
    return VOXY_QUALITY >= VOXY_QUALITY_STANDARD && VOXY_LIGHTING_MODE >= 1;
}

bool voxy_uses_shadows() {
    return VOXY_QUALITY >= VOXY_QUALITY_HIGH && VOXY_SHADOWS_ENABLED != 0;
}

bool voxy_uses_reflections() {
    return VOXY_QUALITY >= VOXY_QUALITY_STANDARD && VOXY_REFLECTIONS_ENABLED != 0;
}

// Intensity scale applied to Voxy fragment color before writeout
float voxy_brightness_scale() {
    return VOXY_BRIGHTNESS;
}

#endif // INCLUDE_MISC_VOXY_SUPPORT
