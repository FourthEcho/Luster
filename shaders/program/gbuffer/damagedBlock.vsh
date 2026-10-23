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

out vec2 uv;

uniform vec2 taaOffset;
uniform vec2 viewPixelSize;

void main() {
    uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy
        + gl_TextureMatrix[0][3].xy;

    vec3 viewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
    vec4 clipPos = project(gl_ProjectionMatrix, viewPos);

#if defined taa && defined taau
    clipPos.xy = clipPos.xy * taauViewportScale
        + clipPos.w * (taauViewportScale - 1.0);
    clipPos.xy += taaOffset * clipPos.w;
#elif defined taa
    clipPos.xy += taaOffset * clipPos.w * 0.66;
#endif

    gl_Position = clipPos;
}
