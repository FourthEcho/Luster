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

#if defined WORLD_OVERWORLD
flat out vec3 sunColor;
flat out vec3 moonColor;
flat out vec3 skyColor;

flat out float auroraAmount;
flat out mat2x3 auroraColors;

flat out float rainbowAmount;

#include "/lib/atmos/clouds/util/params.glsl"
flat out CloudsParams cloudsParams;

#include "/lib/atmos/air/overworld/params.glsl"
flat out OverworldFogParams fogParams;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D noisetex;

uniform float blindness;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float wetness;

uniform int worldTime;
uniform int worldDay;
uniform int moonPhase;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;

uniform vec3 fogColor;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform float worldAge;
uniform float eyeSkylight;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float biomeCave;
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

uniform float desertSandstormWeather;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0

#if defined WORLD_OVERWORLD
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/atmos/aurora.glsl"
#include "/lib/weather/clouds.glsl"
#include "/lib/weather/fog.glsl"
#include "/lib/weather/rainbow.glsl"
#endif
// Dimension-specific light and ambient colors (inlined; single consumer)
#include "/lib/util/color.glsl"

#if defined WORLD_NETHER
vec3 getLightColor() { return vec3(0.0); }

vec3 getAmbientColor() {
#ifdef netherUseBiomeColor
    vec3 netherColor = srgbEotfInv(fogColor) * rec709ToWorkingColor;
    netherColor /= max(dot(netherColor, luminanceWeights), eps);
    netherColor = mix(vec3(1.0), netherColor, netherS);
    netherColor *= 0.05 * netherI;
#else
    vec3 netherColor
        = fromDisplay(vec3(netherR, netherG, netherB)) * 0.1 * netherI;
#endif

    return netherColor;
}
#elif defined WORLD_END
vec3 getLightColor() {
    return fromDisplay(vec3(endLightR, endLightG, endLightB)) * endLightI;
}

vec3 getAmbientColor() {
    return fromDisplay(vec3(endAmbientR, endAmbientG, endAmbientB))
        * endAmbientI;
}
#endif
#if defined WORLD_OVERWORLD
vec3 getAmbientColor() {
    sunColor = getSunExposure() * getSunTint();
    moonColor = getMoonExposure() * getMoonTint();

    const vec3 skyDir = normalize(
        vec3(0.0, 1.0, -0.8)
    ); // don't point direcly upwards to avoid the sun halo when the sun path
       // rotation is 0
    skyColor = atmosphereScattering(
        skyDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        false
    );
    skyColor = tau * skyColor * 1.13;
#ifdef desertSandstorm


    skyColor = mix(
        skyColor,
        tau * getWeatherColor(),
        clamp01(rainStrength + desertSandstormWeather)
    );
#else
    skyColor = mix(skyColor, tau * getWeatherColor(), rainStrength);
#endif

    return skyColor;
}
#endif

void main() {
    uv = gl_MultiTexCoord0.xy;

    lightColor = getLightColor();
    ambientColor = getAmbientColor();

#if defined WORLD_OVERWORLD
    auroraAmount = getAuroraAmount();
    auroraColors = getAuroraColors();

    Weather weather = getWeather();
    rainbowAmount = getRainbowAmount(weather);
    cloudsParams = getCloudsParams(weather);
    fogParams = getFogParams(weather);


    vec3 auroraLight
        = mix(auroraColors[0], auroraColors[1], 0.25) * auroraAmount;
    skyColor += auroraCloudLight * auroraLight;
    ambientColor += auroraGroundLight * auroraLight;
#endif

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
