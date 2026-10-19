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

flat out vec3 ambientColor;
flat out vec3 lightColor;
#ifdef hBasisSkylight
flat out vec3 hSky[6];
#endif

#if defined WORLD_OVERWORLD
flat out vec3 sunColor;
flat out vec3 moonColor;

#include "/lib/atmos/air/overworld/params.glsl"
flat out OverworldFogParams fogParams;


flat out float rainbowAmount;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D depthtex0; // Atmosphere scattering LUT

uniform sampler2D colortex4; // Sky map and lighting colors

uniform int worldTime;
uniform int worldDay;
uniform int moonPhase;
uniform float sunAngle;
uniform float rainStrength;
uniform float wetness;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform float biomeCave;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeSnowy;
uniform float biomeTemperate;
uniform float biomeArid;
uniform float biomeTaiga;
uniform float biomeJungle;
uniform float biomeSwamp;
uniform float biomeTemperature;
uniform float biomeHumidity;
uniform float desertSandstormWeather;

uniform float worldAge;
uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define WEATHER_AURORA

#if defined WORLD_OVERWORLD
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/atmos/projection.glsl"
#include "/lib/weather/fog.glsl"
#include "/lib/weather/rainbow.glsl"
#endif

#include "/lib/util/bicubic.glsl"
#include "/lib/util/random.glsl"
#if !defined INCLUDE_LIGHT_AMBIENT_H_BASIS_SKYLIGHT
#define INCLUDE_LIGHT_AMBIENT_H_BASIS_SKYLIGHT

// H-basis directional sky ambient.

#include "/lib/atmos/projection.glsl"

void projectSkyHBasis(out vec3 h[6]) {
    for (int i = 0; i < 6; ++i) {
        h[i] = vec3(0.0);
    }

    for (int i = 0; i < hBasisSkySamples; ++i) {
        // Uniform-sphere low-discrepancy sequence (deterministic by design).
        vec2 u = vec2(
            (float(i) + 0.5) / float(hBasisSkySamples),
            fract(float(i) * 0.61803398875)
        );

        float phi = tau * u.y;
        float cosTheta = 2.0 * u.x - 1.0;
        float sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0));
        vec3 d = vec3(
            sinTheta * cos(phi), cosTheta, sinTheta * sin(phi)
        );

        vec3 radiance = max0(texture(colortex4, projectSky(d)).rgb);

        h[0] += radiance;
        h[1] += radiance * d.x;
        h[2] += radiance * d.y;
        h[3] += radiance * d.z;
        h[4] += radiance * (1.5 * d.y * d.y - 0.5);
        h[5] += radiance * (d.x * d.x - d.z * d.z) * 0.5;
    }

    float invN = 1.0 / float(hBasisSkySamples);
    for (int i = 0; i < 6; ++i) {
        h[i] *= invN;
    }
}

vec3 evaluateHBasisIrradiance(vec3 h[6], vec3 normal) {
    vec3 n = normalize(normal);

    vec3 result = h[0] * pi;
    result += (2.0 * pi / 3.0) * (h[1] * n.x + h[2] * n.y + h[3] * n.z);
    result += (pi * 0.125) * h[4] * (3.0 * n.y * n.y - 1.0);
    result += (pi * 0.125) * h[5] * (n.x * n.x - n.z * n.z);

    return max0(result);
}

#endif // INCLUDE_LIGHTING_AMBIENT_H_BASIS_SKYLIGHT

void main() {
    uv = gl_MultiTexCoord0.xy;

    lightColor = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    // Flat average stays for sky/blocky-cloud consumers in this unit;
    // diffuse skylight uses the directional H-basis instead.
    ambientColor = texelFetch(colortex4, ivec2(191, 1), 0).rgb;
#ifdef hBasisSkylight
    projectSkyHBasis(hSky);
#endif

#if defined WORLD_OVERWORLD
    Weather weather = getWeather();

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
    fogParams = getFogParams(weather);


    rainbowAmount = getRainbowAmount(weather);
#endif

    vec2 vertexPos = gl_Vertex.xy * taauViewportScale;
    gl_Position = vec4(vertexPos * 2.0 - 1.0, 0.0, 1.0);
}
