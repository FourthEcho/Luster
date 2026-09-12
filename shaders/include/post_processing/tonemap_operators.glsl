#if !defined INCLUDE_MISC_TONEMAP_OPERATORS
#define INCLUDE_MISC_TONEMAP_OPERATORS

// Host include for every selectable tonemap operator (see the `tonemap`
// option in "/settings.glsl"). Each operator lives in its own file and is
// pulled in here so programs only need this single include. The AGX family
// already lives under "agx/" and is included directly.

#include "/include/post_processing/aces_fit.glsl"
#include "/include/post_processing/aces_full.glsl"
#include "/include/post_processing/lottes.glsl"
#include "/include/post_processing/hejl_2015.glsl"
#include "/include/post_processing/hejl_burgess.glsl"
#include "/include/post_processing/tech.glsl"
#include "/include/post_processing/uncharted_2.glsl"
#include "/include/post_processing/ozius.glsl"
#include "/include/post_processing/reinhard.glsl"
#include "/include/post_processing/reinhard_jodie.glsl"
#include "/include/post_processing/agx/agx.glsl"

#endif // INCLUDE_MISC_TONEMAP_OPERATORS
