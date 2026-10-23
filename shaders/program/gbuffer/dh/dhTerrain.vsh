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

out vec2 lightLevels;
out vec3 scenePos;
out vec3 normal;
out vec3 color;

flat out uint materialMask;

// ------------
//   Uniforms
// ------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 dhProjection;
uniform vec3 cameraPosition;
uniform vec2 taaOffset;

void main() {
    lightLevels = linearStep(
        vec2(1.0 / 32.0),
        vec2(31.0 / 32.0),
        (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy
    );
    color = gl_Color.rgb;
    normal = mat3(gbufferModelViewInverse)
        * (mat3(gl_ModelViewMatrix) * gl_Normal);

// Prevent compile error on older versions of Iris
#ifndef DH_BLOCK_GRASS
#define DH_BLOCK_GRASS 13
#endif

    // Set material mask based on dhMaterialId
    switch (dhMaterialId) {
        case DH_BLOCK_LEAVES:
            materialMask = 5; // Leaves
            break;

        case DH_BLOCK_GRASS:
        case DH_BLOCK_DIRT:
        case DH_BLOCK_STONE:
        case DH_BLOCK_DEEPSLATE:
        case DH_BLOCK_NETHER_STONE:
            materialMask = 6; // Dirts, stones, deepslate and netherrack
            break;

        case DH_BLOCK_SAND:
            if (color.r > color.b * 2.0) {
                materialMask = 9; // Red sand
            } else {
                materialMask = 7; // Sand
            }
            break;

        case DH_BLOCK_WOOD:
            materialMask = 10; // Woods
            break;

        case DH_BLOCK_METAL:
            materialMask = 12; // Metals
            break;

        case DH_BLOCK_LAVA:
            materialMask = 39; // Lava
            break;

        case DH_BLOCK_ILLUMINATED:
            materialMask = 36; // Other light sources
            break;

        default:
            materialMask = 0;
            break;
    }

    vec3 cameraOffset = fract(cameraPosition);

    vec3 pos = gl_Vertex.xyz;
    pos = floor(pos + cameraOffset + 0.5) - cameraOffset;
    pos = transform(gl_ModelViewMatrix, pos);

    scenePos = transform(gbufferModelViewInverse, pos);

    vec4 clipPos = dhProjection * vec4(pos, 1.0);

#if defined taa && defined taau
    clipPos.xy = clipPos.xy * taauViewportScale
        + clipPos.w * (taauViewportScale - 1.0);
    clipPos.xy += taaOffset * clipPos.w;
#elif defined taa
    clipPos.xy += taaOffset * clipPos.w * 0.66;
#endif

    gl_Position = clipPos;
}
