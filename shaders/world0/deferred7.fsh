#version 400 compatibility
#define WORLD_OVERWORLD

// Indirect lighting bounce 3 — see program/gi/bounce.fsh
// (this is a thin world-specific wrapper so Iris picks up the right file
//  and applies the dimension-specific #defines before the include).

#define BOUNCE_PASS 3
#include "/program/gi/bounce.fsh"
