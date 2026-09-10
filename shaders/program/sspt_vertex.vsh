/*
--------------------------------------------------------------------------------

  Kappa v5.3 port (program/deferred/vertexSimple.vsh)

  program/sspt_vertex:
  Fullscreen quad for the SSPT passes. The pass renders into the half-res
  SSPT buffers (colortex17-20), so the quad covers the whole screen while
  the viewport is the buffer's own resolution — same convention as
  program/d3_ao.vsh.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

void main() {
    uv = gl_MultiTexCoord0.xy;
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
