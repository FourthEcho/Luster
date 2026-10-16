/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#include "/lib/global.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;

#include "/lib/light/distortion.glsl"

out vec3 cage_normal;
out vec3 world_pos;
flat out vec3 tint;

void main() {
    tint = gl_Color.rgb;

#if !defined WORLD_NETHER
    vec3 pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

    cage_normal = gl_Normal;
    world_pos = transform(shadowModelViewInverse, pos) + cameraPosition;

    vec3 shadow_clip_pos = project_ortho(gl_ProjectionMatrix, pos);
    shadow_clip_pos = distort_shadow_space(shadow_clip_pos);

    gl_Position = vec4(shadow_clip_pos, 1.0);

#else
    // No shadows, discard vertices now
    gl_Position = vec4(-1.0);
    return;
#endif
}
