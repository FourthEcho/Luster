/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/p1_ssgi:
  SSGI bounce 1 — gather indirect radiance from the directly lit scene

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 bounce_radiance;
/* RENDERTARGETS: 17 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0; // lit scene color
uniform sampler2D colortex1; // gbuffer data

uniform sampler2D depthtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec2 view_res;

uniform float near;
uniform float far;
uniform vec2 taa_offset;

uniform int frameCounter;

#include "/include/lighting/ssgi.glsl"

void main() {
#ifdef SSGI
    ivec2 texel = ivec2(gl_FragCoord.xy);

    float depth = texelFetch(depthtex0, texel, 0).x;

    if (depth >= 1.0 || depth < hand_depth) {
        bounce_radiance = vec3(0.0);
        return;
    }

    vec3 albedo, normal;
    ssgi_decode_gbuffer(texel, albedo, normal);

    vec3 position_view = screen_to_view_space(vec3(uv, depth), true);

    float dither = texelFetch(noisetex, texel & 511, 0).b;
    dither = r1(frameCounter, dither);

    // Bounce 1: gather the directly lit scene
    bounce_radiance = ssgi_gather(position_view, normal, colortex0, texel, dither);
#else
    bounce_radiance = vec3(0.0);
#endif
}
