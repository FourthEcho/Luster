#version 400 compatibility
#define WORLD_END

// Indirect lighting A-Trous SVGF filter pass 1 (size=8)
// See program/gi/filter.fsh
#define SVGF_SIZE 8
#include "/program/gi/filter.fsh"
