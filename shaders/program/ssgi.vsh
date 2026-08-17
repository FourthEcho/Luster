/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/ssgi.vsh:
  Fullscreen pass vertex shader shared by the SSGI prepare passes

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

void main() {
    uv = gl_MultiTexCoord0.xy;
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
