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

flat out uint materialMask;
flat out vec3 tint;

#ifdef waterCaustics
out vec3 scenePos;
#endif


#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
out vec2 atlasTileCoord;
out float pomViewDistance;
flat out vec2 atlasTileOffset;
flat out vec2 atlasTileScale;
flat out mat3 tbn;
#endif

// --------------
//   Attributes
// --------------

attribute vec3 at_midBlock;
attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

// ------------
//   Uniforms
// ------------

uniform sampler2D tex;
uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

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

// ------------
//   Includes
// ------------

#include "/lib/light/direct/distortion.glsl"
#include "/lib/vertex/displacement.glsl"

void main() {
    uv = gl_MultiTexCoord0.xy;
    materialMask = uint(mc_Entity.x - 10000.0);
    tint = gl_Color.rgb;

#if defined WORLD_NETHER
    // No shadows, discard vertices now
#ifdef waterCaustics
    scenePos = vec3(0.0);
#endif
    gl_Position = vec4(-1.0);
    return;
#endif

    bool isTopVertex = uv.y < mc_midTexCoord.y;

    vec3 pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

#if !defined PROGRAM_SHADOW_ENTITIES
    // Animations
    pos = transform(shadowModelViewInverse, pos);
    pos = pos + cameraPosition;
    pos = animateVertex(
        pos,
        isTopVertex,
        clamp01(rcp(240.0) * gl_MultiTexCoord1.y),
        materialMask
    );
    pos = pos - cameraPosition;

#ifdef waterCaustics
    scenePos = pos;
#endif

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
    // Same tile / TBN construction as gbuffers_all_solid.vsh, but with the
    // shadow view matrices, so the tangent frame matches the gbuffer's.
    {
        vec2 uvMinusMid = uv - mc_midTexCoord;
        atlasTileOffset = min(uv, mc_midTexCoord - uvMinusMid);
        atlasTileScale = abs(uvMinusMid) * 2.0;
        atlasTileCoord = sign(uvMinusMid) * 0.5 + 0.5;

        mat3 pomTbn;
        pomTbn[0] = mat3(shadowModelViewInverse)
            * normalize(gl_NormalMatrix * at_tangent.xyz);
        pomTbn[2] = mat3(shadowModelViewInverse)
            * normalize(gl_NormalMatrix * gl_Normal);
        pomTbn[1] = cross(pomTbn[0], pomTbn[2]) * sign(at_tangent.w);
        tbn = pomTbn;

        // Camera-relative distance: drives the same pom distance fade as
        // the gbuffer pass so shadow and depth displacement agree.
        pomViewDistance = length(pos);
    }
#endif

    pos = transform(shadowModelView, pos);
    ;
#endif

    vec3 shadowClipPos = projectOrtho(gl_ProjectionMatrix, pos);
    shadowClipPos = distortShadowSpace(shadowClipPos);

    gl_Position = vec4(shadowClipPos, 1.0);
}
