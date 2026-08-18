#version 400 compatibility
#define WORLD_OVERWORLD
#define PROGRAM_GBUFFERS_SPIDEREYES
#define fsh

#include "/settings.glsl"

// Entity eye rendering follows the entity-draw path used by the active renderer configuration; this local declaration keeps world-specific eye shaders self-contained.
// when MC_VERSION > 12111). Inlined here so settings.glsl only contains
// user-facing options.
#if defined IS_IRIS && MC_VERSION > 12111
#include "/program/gbuffers_all_translucent.fsh"
#else
#include "/program/gbuffers_all_solid.fsh"
#endif
