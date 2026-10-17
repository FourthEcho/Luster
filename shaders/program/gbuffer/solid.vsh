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
out vec3 scenePos;
out vec4 tint;

flat out uint materialMask;
flat out mat3 tbn;

#if defined COLORWHEEL
vec2 lightLevels;
#else
out vec2 lightLevels;
#endif

#if defined pom
out vec2 atlasTileCoord;
out vec3 tangentPos;
flat out vec2 atlasTileOffset;
flat out vec2 atlasTileScale;
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN
out float mcAo;
#elif defined COLORWHEEL
float mcAo;
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
out vec2 uvLocal;
#endif

#if defined PROGRAM_GBUFFERS_VOXELS
out vec3 blockNormal;
#endif

// --------------
//   Attributes
// --------------

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform ivec2 atlasSize;

uniform float frameTimeCounter;
uniform float rainStrength;
uniform float wetness;

uniform vec2 taaOffset;
uniform vec3 lightDir;

uniform float worldAge;
uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;
uniform float biomeTemperature;
uniform float biomeHumidity;

#if defined PROGRAM_GBUFFERS_BLOCK
uniform int blockEntityId;
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES
uniform int entityId;
#endif

#if (defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND) \
    && defined IS_IRIS
uniform int currentRenderedItemId;
#endif

#include "/lib/util/spaceConversion.glsl"
#include "/lib/vertex/displacement.glsl"
#include "/lib/vertex/utility.glsl"

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightLevels = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));
    tint = gl_Color;
    materialMask = getMaterialMask();
    tbn = getTbnMatrix();

#if defined PROGRAM_GBUFFERS_VOXELS
    blockNormal = gl_Normal;
#endif

#if defined PROGRAM_GBUFFERS_TERRAIN
    mcAo = gl_Color.a < 0.1
        ? 1.0
        : gl_Color.a; // fixes models where vanilla ao breaks (eg lecterns)
    mcAo
        = materialMask == 5 ? 1.0 : mcAo; // no vanilla ao on leaves
    tint.a = 1.0;

#ifdef pom
    // from fayer3
    vec2 uvMinusMid = uv - mc_midTexCoord;
    atlasTileOffset = min(uv, mc_midTexCoord - uvMinusMid);
    atlasTileScale = abs(uvMinusMid) * 2.0;
    atlasTileCoord = sign(uvMinusMid) * 0.5 + 0.5;
#endif
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES && !defined COLORWHEEL
    // Fire entities should always glow at full emission
    if (lightLevels.x > 0.99) {
        materialMask = 40;
    }
#endif

#if defined PROGRAM_GBUFFERS_PARTICLES
    // Make enderman/nether portal particles glow
    if (gl_Color.r > gl_Color.g && gl_Color.g < 0.6 && gl_Color.b > 0.4) {
        materialMask = 47;
    }
#endif

#if defined PROGRAM_GBUFFERS_BEACONBEAM
    // Make beacon beam glow
    materialMask = 32;
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES || defined PROGRAM_GBUFFERS_HAND
    // Calculate local uv used to fix hardcoded emission on some
    // handheld/dropped items
    uvLocal = sign(uv - mc_midTexCoord) * 0.5 + 0.5;
#endif

    bool isTopVertex = uv.y < mc_midTexCoord.y;

    vec3 pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
    pos = viewToSceneSpace(pos);
    pos = pos + cameraPosition;
    pos = animateVertex(pos, isTopVertex, lightLevels.y, materialMask);
    pos = pos - cameraPosition;

    scenePos = pos;

#if defined pom && defined PROGRAM_GBUFFERS_TERRAIN
    tangentPos = (pos - gbufferModelViewInverse[3].xyz) * tbn;
#endif

    vec3 viewPos = sceneToViewSpace(pos);
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
