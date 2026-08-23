/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge (Luster fork)

  program/d5_rsm_gi_gather:
  Vertex stage — full-viewport quad over the quarter-res GI buffer

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

flat out vec3 light_color;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex4; // sky map, lighting colors

void main() {
    uv = gl_MultiTexCoord0.xy;

    light_color = texelFetch(colortex4, ivec2(191, 0), 0).rgb;

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
