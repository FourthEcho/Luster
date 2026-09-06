/*
--------------------------------------------------------------------------------

  program/sspt_vertex:
  Fullscreen quad shared by the SSPT passes. Those passes render into the
  reduced-resolution SSPT buffers (colortex17-20), so the quad covers the
  whole screen while the viewport is the buffer's own resolution — same
  convention as program/d3_ao.vsh.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

// Fullscreen quad: pass the vanilla vertex attribute through and push the
// clip-space position out to the viewport corners.
void main() {
    uv = gl_MultiTexCoord0.xy;
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
