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
out vec4 tint;

flat out uint isWater;
flat out vec3 lightColor;
flat out vec3 ambientColor;

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/overworld/params.glsl"
flat out OverworldFogParams fogParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex4; // Sky map, lighting colors

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 dhProjection;
uniform mat4 dhProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform ivec2 atlasSize;

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

#if defined WORLD_OVERWORLD
#include "/lib/weather/fog.glsl"
#endif

void main() {
    lightLevels = linearStep(
        vec2(1.0 / 32.0),
        vec2(31.0 / 32.0),
        (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy
    );
    tint = gl_Color;
    normal = mat3(gbufferModelViewInverse)
        * (mat3(gl_ModelViewMatrix) * gl_Normal);

    lightColor = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    // Use the baked sky ambient published to colortex4(191, 1), the same
    // term the rest of the forward-shaded world uses.
    ambientColor = texelFetch(colortex4, ivec2(191, 1), 0).rgb
        * clamp01(lightLevels.y);

    isWater = uint(dhMaterialId == DH_BLOCK_WATER);

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

#if defined WORLD_OVERWORLD
    fogParams = getFogParams(getWeather());
#endif

    gl_Position = clipPos;
}
