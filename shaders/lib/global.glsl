#if !defined INCLUDE_GLOBAL
#define INCLUDE_GLOBAL
// Extensions

/*
#ifdef MC_GL_KHR_shader_subgroup
    #extension GL_KHR_shader_subgroup_vote : enable
#endif

#ifdef useHalfPrecisionFp
    #if defined MC_GL_AMD_gpu_shader_half_float
        #extension GL_AMD_gpu_shader_half_float : enable
        #define HAS_F16
    #elif defined MC_GL_NV_gpu_shader5
        #extension GL_NV_gpu_shader5 : enable
        #define HAS_F16
    #endif
#endif
*/

#ifdef HAS_F16
#define f16 float16T
#else
#define f16 float
#define f16vec2 vec2
#define f16vec3 vec3
#define f16vec4 vec4
#define f16mat2 mat2
#define f16mat2x2 mat2x2
#define f16mat2x3 mat2x3
#define f16mat2x4 mat2x4
#define f16mat3 mat3
#define f16mat3x2 mat3x2
#define f16mat3x3 mat3x3
#define f16mat3x4 mat3x4
#define f16mat4 mat4
#define f16mat4x2 mat4x2
#define f16mat4x3 mat4x3
#define f16mat4x4 mat4x4
#endif

// LoD mod detection

#if defined DISTANT_HORIZONS || defined VOXY
#define LOD_MOD_ACTIVE
#endif

#if defined VOXY && defined DISTANT_HORIZONS
// Cancel Voxy DH emulation
#undef DISTANT_HORIZONS
#endif

// Settings

#include "/settings.glsl"


#define MATERIAL_WATER 1
#define MATERIAL_SMALL_PLANTS 2
#define MATERIAL_TALL_PLANTS_LOWER 3
#define MATERIAL_TALL_PLANTS_UPPER 4
#define MATERIAL_LEAVES 5
#define MATERIAL_LAVA 39
#define MATERIAL_OPEN_EYEBLOSSOM 59
#define MATERIAL_NETHER_PORTAL 62
#define MATERIAL_END_PORTAL 63
#define MATERIAL_ITEM 100
#define MATERIAL_BOAT 101
#define MATERIAL_LIGHTNING_BOLT 102

// Special material for dragon death beams
#define MATERIAL_DRAGON_BEAM 103

// Compatibility fixes

#if MC_VERSION < 11700
#define gtexture tex
#endif

#ifndef MC_GL_VENDOR_INTEL
#define attribute in
#endif

// Common constants

const float eps = 1e-6;
const float e = exp(1.0);
const float pi = acos(-1.0);
const float tau = 2.0 * pi;
const float halfPi = 0.5 * pi;
const float rcpPi = 1.0 / pi;
const float degree
    = tau / 360.0; // Size of one degree in radians, useful because radians() is
                   // not a constant expression on all platforms
const float goldenRatio = 0.5 + 0.5 * sqrt(5.0);
const float goldenAngle = tau / goldenRatio / goldenRatio;
const float handDepth = 0.56;

#if defined taa && defined taau
const float taauViewportScale = taauRenderScale;
#else
const float taauViewportScale = 1.0;
#endif

// Helper functions

#define rcp(x) (1.0 / (x))
#define clamp01(x) clamp(x, 0.0, 1.0) // free on operation output
#define max0(x) max(x, 0.0)
#define min1(x) min(x, 1.0)

float sqr(float x) { return x * x; }

vec2 sqr(vec2 v) { return v * v; }

vec3 sqr(vec3 v) { return v * v; }

vec4 sqr(vec4 v) { return v * v; }

float cube(float x) { return x * x * x; }

float maxOf(vec2 v) { return max(v.x, v.y); }

float maxOf(vec3 v) { return max(v.x, max(v.y, v.z)); }

float maxOf(vec4 v) { return max(v.x, max(v.y, max(v.z, v.w))); }

float minOf(vec2 v) { return min(v.x, v.y); }

float minOf(vec3 v) { return min(v.x, min(v.y, v.z)); }

float minOf(vec4 v) { return min(v.x, min(v.y, min(v.z, v.w))); }

vec3 minOf(vec3 a, vec3 b, vec3 c, vec3 d, vec3 f) {
    return min(a, min(b, min(c, min(d, f))));
}

vec3 maxOf(vec3 a, vec3 b, vec3 c, vec3 d, vec3 f) {
    return max(a, max(b, max(c, max(d, f))));
}

float lengthSquared(vec2 v) { return dot(v, v); }

float lengthSquared(vec3 v) { return dot(v, v); }

vec2 normalizeSafe(vec2 v) { return v == vec2(0.0) ? v : normalize(v); }

vec3 normalizeSafe(vec3 v) { return v == vec3(0.0) ? v : normalize(v); }

// Remapping functions

float linearStep(float edge0, float edge1, float x) {
    return clamp01((x - edge0) / (edge1 - edge0));
}

float linearStepUnclamped(float edge0, float edge1, float x) {
    return (x - edge0) / (edge1 - edge0);
}

vec2 linearStep(vec2 edge0, vec2 edge1, vec2 x) {
    return clamp01((x - edge0) / (edge1 - edge0));
}

// Can be used similarly to sqrt() to shape a signal on [0, 1]
float dampen(float x) {
    x = clamp01(x);
    return x * (2.0 - x);
}


float lift(float x, float amount) {
    return (x + x * amount) / (1.0 + x * amount);
}

vec3 lift(vec3 x, float amount) {
    return (x + x * amount) / (1.0 + x * amount);
}

// Smoothing function used by smoothstep
// Zero derivative at zero and one
float cubicSmooth(float x) { return sqr(x) * (3.0 - 2.0 * x); }

vec2 cubicSmooth(vec2 x) { return sqr(x) * (3.0 - 2.0 * x); }


float getUvFromUnitRange(float values, const int res) {
    return values * (1.0 - 1.0 / float(res)) + (0.5 / float(res));
}


// (the following functions are from https://iquilezles.org/articles/functions/)

float pulse(float x, float center, float width) {
    x = abs(x - center) / width;
    return x > 1.0 ? 0.0 : 1.0 - cubicSmooth(x);
}

float pulse(float x, float center, float width, const float period) {
    x = (x - center + 0.5 * period) / period;
    x = fract(x) * period - (0.5 * period);

    return pulse(x, 0.0, width);
}


float cubicLength(vec2 v) {
    return pow(cube(abs(v.x)) + cube(abs(v.y)), rcp(3.0));
}

// Matrix operations

vec2 diagonal(mat2 m) { return vec2(m[0].x, m[1].y); }

vec3 diagonal(mat3 m) { return vec3(m[0].x, m[1].y, m[2].z); }

vec4 diagonal(mat4 m) { return vec4(m[0].x, m[1].y, m[2].z, m[3].w); }

vec3 transform(mat4 m, vec3 pos) { return mat3(m) * pos + m[3].xyz; }

vec4 project(mat4 m, vec3 pos) {
    return vec4(m[0].x, m[1].y, m[2].zw) * pos.xyzz + m[3];
}

vec3 projectAndDivide(mat4 m, vec3 pos) {
    vec4 homogenous = project(m, pos);
    return homogenous.xyz / homogenous.w;
}

vec3 projectOrtho(mat4 m, vec3 pos) {
    return diagonal(m).xyz * pos + m[3].xyz;
}

// Hand

void fixHandDepth(inout float depth, out bool isHand) {
    isHand = depth < handDepth; // NB: Not the same as mcHandDepth
    if (isHand) {
        depth = depth * 2.0 - 1.0;
        depth *= rcp(MC_HAND_DEPTH);
        depth = depth * 0.5 + 0.5;
    }
}

void fixHandDepth(inout float depth) {
    bool unused;
    fixHandDepth(depth, unused);
}

// GUI visibility shims. Iris only lists a boolean #define in the settings GUI
// if the macro is referenced by an #ifdef / #ifndef somewhere in the pack's
// source (plain #if defined(X) does NOT count, and neither do shaders.properties
// directives such as shadowEntities / program.*.enabled). The references below
// exist purely so these options appear in the GUI.
#ifdef entityShadows
  #define lusterGuiEntityShadows
#endif
#ifdef blockEntityShadows
  #define lusterGuiBlockEntityShadows
#endif
#ifdef vanillaAo
  #define lusterGuiVanillaAo
#endif
#ifdef caveFog
  #define lusterGuiCaveFog
#endif
#ifdef crepRays
  #define lusterGuiCrepRays
#endif
#ifdef ssrRoughnessSupport
  #define lusterGuiSsrRoughnessSupport
#endif
#ifdef motionBlur
  #define lusterGuiMotionBlur
#endif
#ifdef purkinjeShift
  #define lusterGuiPurkinjeShift
#endif

#endif // INCLUDE_GLOBAL
