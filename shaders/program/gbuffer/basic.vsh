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

flat out vec2 lightLevels;
flat out vec4 tint;
in vec4 vaColor;

#ifdef PROGRAM_GBUFFERS_LINE
// gbuffers_line seems to break in Iris 1.6 when the compatibility profile is
// used, so we must use the core spec
in vec3 vaPosition;
in vec3 vaNormal;
in ivec2 vaUV2;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

#if boxLineWidth != 2
uniform int renderStage;
#endif
#endif

uniform vec2 taaOffset;
uniform vec2 viewRes;
uniform vec2 viewPixelSize;

void main() {
#if defined PROGRAM_GBUFFERS_LINE
    lightLevels = clamp01(vec2(vaUV2) * rcp(240.0));

    // Taken from Minecraft 1.17's rendertypeLines.vsh

    const float viewShrink = 1.0 - (1.0 / 256.0);
    const mat4 viewScale = mat4(
        viewShrink,
        0.0,
        0.0,
        0.0,
        0.0,
        viewShrink,
        0.0,
        0.0,
        0.0,
        0.0,
        viewShrink,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0
    );

    vec4 linePosStart = vec4(vaPosition, 1.0);
    linePosStart
        = projectionMatrix * viewScale * modelViewMatrix * linePosStart;
    vec4 linePosEnd = vec4(vaPosition + vaNormal, 1.0);
    linePosEnd
        = projectionMatrix * viewScale * modelViewMatrix * linePosEnd;

    vec3 ndc1 = linePosStart.xyz / linePosStart.w;
    vec3 ndc2 = linePosEnd.xyz / linePosEnd.w;

    vec2 lineScreenDir = normalize((ndc2.xy - ndc1.xy) * viewRes);

    vec2 lineOffset =
#if boxLineWidth != 2
        vec2(-lineScreenDir.y, lineScreenDir.x) * viewPixelSize
        * ((renderStage == MC_RENDER_STAGE_OUTLINE) ? float(boxLineWidth)
                                                    : 2.0);
#else
        vec2(-lineScreenDir.y, lineScreenDir.x) * viewPixelSize * 2.0;
#endif

    if (lineOffset.x < 0.0) {
        lineOffset *= -1.0;
    }

    vec4 clipPos = (gl_VertexID & 1) == 0
        ? vec4(
              (ndc1 + vec3(lineOffset, 0.0)) * linePosStart.w,
              linePosStart.w
          )
        : vec4(
              (ndc1 - vec3(lineOffset, 0.0)) * linePosStart.w,
              linePosStart.w
          );
#else
    lightLevels = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));
    vec3 viewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
    vec4 clipPos = project(gl_ProjectionMatrix, viewPos);
#endif

#if defined taa && defined taau
    clipPos.xy = clipPos.xy * taauViewportScale
        + clipPos.w * (taauViewportScale - 1.0);
    clipPos.xy += taaOffset * clipPos.w;
#elif defined taa
    clipPos.xy += taaOffset * clipPos.w * 0.66;
#endif

    tint = vaColor;
    gl_Position = clipPos;
}
