#version 400 compatibility
#define WORLD_OVERWORLD
#define PROGRAM_GBUFFERS_SPIDEREYES
#define fsh

#include "/settings.glsl"

// Previously gated by USE_SEPARATE_ENTITY_DRAWS (defined in settings.glsl
// when MC_VERSION > 12111). Inlined here so settings.glsl only contains
// user-facing options.
#if defined IS_IRIS && MC_VERSION > 12111
#include "/program/gbuffers_all_translucent.fsh"
#else
#include "/program/gbuffers_all_solid.fsh"
#endif
