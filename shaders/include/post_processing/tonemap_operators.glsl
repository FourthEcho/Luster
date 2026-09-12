#if !defined INCLUDE_MISC_TONEMAP_OPERATORS
#define INCLUDE_MISC_TONEMAP_OPERATORS

// Host include for every selectable tonemap operator (see the `tonemap`
// option in "/settings.glsl"). Each operator lives in its own directory
// and is pulled in here so programs only need this single include. The
// ACES and AGX families already live under "aces/" and "agx/".

#include "/include/post_processing/aces_fit/aces_fit.glsl"
#include "/include/post_processing/aces_full/aces_full.glsl"
#include "/include/post_processing/lottes/lottes.glsl"
#include "/include/post_processing/hejl_2015/hejl_2015.glsl"
#include "/include/post_processing/hejl_burgess/hejl_burgess.glsl"
#include "/include/post_processing/tech/tech.glsl"
#include "/include/post_processing/uncharted_2/uncharted_2.glsl"
#include "/include/post_processing/ozius/ozius.glsl"
#include "/include/post_processing/reinhard/reinhard.glsl"
#include "/include/post_processing/reinhard_jodie/reinhard_jodie.glsl"
#include "/include/post_processing/agx/agx.glsl"

#endif // INCLUDE_MISC_TONEMAP_OPERATORS
