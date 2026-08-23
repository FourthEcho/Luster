/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge (Luster fork)

  program/d7_rsm_gi_denoise:
  Vertex stage — full-viewport quad over the quarter-res GI buffer

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

void main() {
    uv = gl_MultiTexCoord0.xy;
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
