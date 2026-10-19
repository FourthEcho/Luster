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
out vec3 positionView;
out vec3 positionScene;
out vec4 tint;

#if defined COLORWHEEL
vec2 lightLevels;
#else
out vec2 lightLevels;
#endif

flat out uint materialMask;
flat out mat3 tbn;

#if defined PROGRAM_GBUFFERS_WATER
out vec2 atlasTileCoord;
out vec3 positionTangent;
flat out vec2 atlasTileOffset;
flat out vec2 atlasTileScale;
#endif

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/overworld/params.glsl"
flat out OverworldFogParams fogParams;
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
uniform int renderStage;

uniform int worldTime;
uniform int worldDay;
uniform int frameCounter;
uniform float frameTimeCounter;

uniform float sunAngle;
uniform float rainStrength;
uniform float wetness;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform vec3 lightDir;
uniform vec3 sunDir;

uniform float eyeSkylight;

uniform float biomeTemperate;
uniform float biomeArid;
uniform float biomeSnowy;
uniform float biomeTaiga;
uniform float biomeJungle;
uniform float biomeSwamp;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeTemperature;
uniform float biomeHumidity;

uniform float worldAge;
uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float desertSandstormWeather;

#if defined PROGRAM_GBUFFERS_ENTITIES_TRANSLUCENT \
    || defined PROGRAM_GBUFFERS_LIGHTNING
uniform int entityId;
#endif

#if defined PROGRAM_GBUFFERS_BLOCK_TRANSLUCENT
uniform int blockEntityId;
#endif

#if ( \
    defined PROGRAM_GBUFFERS_ENTITIES_TRANSLUCENT \
    || defined PROGRAM_GBUFFERS_HAND_WATER \
) && defined IS_IRIS
uniform int currentRenderedItemId;
#endif

#include "/lib/util/spaceConversion.glsl"
#include "/lib/vertex/displacement.glsl"
#include "/lib/vertex/utility.glsl"

#if defined WORLD_OVERWORLD
#include "/lib/weather/fog.glsl"
#endif

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0)
             .xy; // Faster method breaks on Intel for some reason, thanks to
                  // ilux-git for finding this!
    lightLevels = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));
    tint = gl_Color;
    materialMask = getMaterialMask();
    tbn = getTbnMatrix();

    bool isTopVertex = uv.y < mc_midTexCoord.y;

    positionScene
        = transform(gl_ModelViewMatrix, gl_Vertex.xyz); // To view space
    positionScene = viewToSceneSpace(positionScene); // To scene space
    positionScene = positionScene + cameraPosition; // To world space
    positionScene = animateVertex(
        positionScene,
        isTopVertex,
        lightLevels.y,
        materialMask
    ); // Apply vertex animations
    positionScene = positionScene - cameraPosition; // Back to scene space

#if defined PROGRAM_GBUFFERS_WATER
    tint.a = 1.0;

    if (materialMask == 62) {
        // Nether portal
        positionTangent
            = (positionScene - gbufferModelViewInverse[3].xyz) * tbn;

        // (from fayer3)
        vec2 uvMinusMid = uv - mc_midTexCoord;
        atlasTileOffset = min(uv, mc_midTexCoord - uvMinusMid);
        atlasTileScale = abs(uvMinusMid) * 2.0;
        atlasTileCoord = sign(uvMinusMid) * 0.5 + 0.5;
    }
#endif

#if defined PROGRAM_GBUFFERS_LIGHTNING && defined WORLD_END
    // For some reason the Ender Dragon death beams also use gbuffers_lightning

    // Ender Dragon death beam check from Euphoria Patches by SpacEagle17, used
    // with permission https://www.euphoriapatches.com/
    bool isDragonDeathBeam
        = entityId == 0 && (tint.a < 0.2 || tint.a == 1.0);

    if (isDragonDeathBeam) {
        materialMask = MATERIAL_DRAGON_BEAM;

        if (tint.r < 0.2) {
            // Dark bit at the end
            tint.a = 0.0;
        }
    }
#endif

#if defined PROGRAM_GBUFFERS_TEXTURED
    // Make world border emissive
    if (renderStage == MC_RENDER_STAGE_WORLD_BORDER) {
        materialMask = 4;
    }
#endif

#if defined PROGRAM_GBUFFERS_WATER
    // Fix issue where the normal of the bottom of the water surface is flipped
    if (dot(positionScene, tbn[2]) > 0.0) {
        tbn[2] = -tbn[2];
    }
#endif

#if defined WORLD_OVERWORLD
    fogParams = getFogParams(getWeather());
#endif

    positionView = sceneToViewSpace(positionScene);
    vec4 positionClip = project(gl_ProjectionMatrix, positionView);

#if defined taa && defined taau
    positionClip.xy = positionClip.xy * taauViewportScale
        + positionClip.w * (taauViewportScale - 1.0);
    positionClip.xy += taaOffset * positionClip.w;
#elif defined taa
    positionClip.xy += taaOffset * positionClip.w * 0.66;
#endif

    gl_Position = positionClip;
}
