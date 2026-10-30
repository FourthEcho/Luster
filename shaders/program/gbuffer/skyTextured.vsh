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
out vec3 viewPos;

#if MC_VERSION >= 260100
out vec2 uvMid;
#endif

flat out vec3 tint;
flat out vec3 sunColor;
flat out vec3 moonColor;

#if MC_VERSION >= 260100
attribute vec2 mc_midTexCoord;
#endif

// ------------
//   Uniforms
// ------------

uniform float sunAngle;
uniform float rainStrength;
uniform float desertSandstormWeather;
uniform int moonPhase;

uniform vec2 taaOffset;

uniform vec3 sunDir;
uniform vec3 lightDir;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/weather/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/weather/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR

void main() {
    sunColor = getSunExposure() * getSunTint();
    moonColor = getMoonExposure() * getMoonTint();
#ifdef moonPhaseNightAtmosphere
    moonColor = applyMoonPhaseInfluence(
        moonColor,
        moonPhaseNightAtmosphereIntensity * moonPhaseInfluenceIntensity,
        1.00,
        1.00
    );
#endif

    uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy
        + gl_TextureMatrix[0][3].xy;
    tint = gl_Color.rgb;

#if MC_VERSION >= 260100
    uvMid = mat2(gl_TextureMatrix[0]) * mc_midTexCoord
        + gl_TextureMatrix[0][3].xy;
#endif

    viewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

    vec4 clipPos = project(gl_ProjectionMatrix, viewPos);

#if defined taa && defined taau
    clipPos.xy = clipPos.xy * taauViewportScale
        + clipPos.w * (taauViewportScale - 1.0);
    clipPos.xy += taaOffset * clipPos.w;
#elif defined taa
    clipPos.xy += taaOffset * clipPos.w * 0.75;
#endif

    gl_Position = clipPos;
}
