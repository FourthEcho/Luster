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

#include "/lib/light/direct/distortion.glsl"

out vec3 cageNormal;
out vec3 worldPos;
flat out vec3 tint;

void main() {
    tint = gl_Color.rgb;

#if !defined WORLD_NETHER
    vec3 pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

    cageNormal = gl_Normal;
    worldPos = transform(shadowModelViewInverse, pos) + cameraPosition;

    vec3 shadowClipPos = projectOrtho(gl_ProjectionMatrix, pos);
    shadowClipPos = distortShadowSpace(shadowClipPos);

    gl_Position = vec4(shadowClipPos, 1.0);

#else
    // No shadows, discard vertices now
    gl_Position = vec4(-1.0);
    return;
#endif
}
