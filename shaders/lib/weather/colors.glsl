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

#if defined(LUSTER_INCLUDE_MOON_PHASE_COLOR)
// Moon-phase color influence.
#if !defined INCLUDE_LIGHT_COLORS_MOON_PHASE_INFLUENCE
#define INCLUDE_LIGHT_COLORS_MOON_PHASE_INFLUENCE

#include "/lib/util/color.glsl"

// Moon Phase Influence helpers -------


float getMoonPhaseCurve() {
    if (moonPhase == 0) return 1.0;
    else if (moonPhase == 1) return 0.875;
    else if (moonPhase == 2) return 0.75;
    else if (moonPhase == 3) return 0.625;
    else if (moonPhase == 4) return 0.5;
    else if (moonPhase == 5) return 0.75;
    else if (moonPhase == 6) return 0.875;
    else return 1.0;
}


vec3 applyMoonPhaseInfluence(
    vec3 color,
    float intensity,
    float contrast,
    float saturation
) {
    float phase = getMoonPhaseCurve();
    phase = clamp01(0.5 + (phase - 0.5) * contrast);

    float brightnessMul = mix(1.0, phase, clamp01(intensity));
    color *= brightnessMul;

    float satMul = mix(1.0, phase, clamp01(saturation));
    float lum = dot(color, luminanceWeights);
    color = mix(vec3(lum), color, satMul);

    return color;
}

#endif
#endif

#if defined(LUSTER_INCLUDE_BLOCKLIGHT_COLOR)
// Blocklight color and emissive scale.
#if !defined INCLUDE_LIGHT_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHT_COLORS_BLOCKLIGHT_COLOR

#include "/lib/util/color.glsl"

const float blocklightScale = 6.0;


const float emissionScale = 40.0;

// Indirect lighting (skylight and the sun/moon bounce) sits at half
// strength so traced emission stays the dominant indirect term.
const float indirectLightScale = 0.50;

#define blocklightColor \
    (fromDisplay(vec3(blocklightR, blocklightG, blocklightB)) * blocklightI)

#endif // INCLUDE_LIGHT_COLORS_BLOCKLIGHT_COLOR
#endif

#if defined(LUSTER_INCLUDE_LIGHT_COLOR)
// Sun/moon color and exposure helpers.
#if !defined INCLUDE_LIGHT_COLORS_LIGHT_COLOR
#define INCLUDE_LIGHT_COLORS_LIGHT_COLOR

#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/util/color.glsl"
uniform float moonPhaseBrightness;

// Magic brightness adjustment so that auto exposure isn't needed
float getSunExposure() {
    const float baseScale = 7.0 * sunI;

    float blueHour
        = linearStep(0.05, 1.0, exp(-190.0 * sqr(sunDir.y + 0.09604)));

    float daytimeMul
        = 1.0 + 0.5 * (timeSunset + timeSunrise) + 40.0 * blueHour;

    return baseScale * daytimeMul;
}

vec3 getSunTint() {
    float blueHour
        = linearStep(0.05, 1.0, exp(-190.0 * sqr(sunDir.y + 0.09604)));

    vec3 morningEveningTint = vec3(1.05, 0.84, 0.93) * 1.2;
    morningEveningTint = mix(
        vec3(1.0),
        morningEveningTint,
        sqr(pulse(sunDir.y, 0.17, 0.40))
    );

    vec3 blueHourTint = vec3(0.95, 0.80, 1.0);
    blueHourTint = mix(vec3(1.0), blueHourTint, blueHour);

    // User tint

    const vec3 tintMorning = fromDisplay(vec3(sunMr, sunMg, sunMb));
    const vec3 tintNoon = fromDisplay(vec3(sunNr, sunNg, sunNb));
    const vec3 tintEvening = fromDisplay(vec3(sunEr, sunEg, sunEb));

    vec3 userTint = mix(tintNoon, tintMorning, timeSunrise);
    userTint = mix(userTint, tintEvening, timeSunset);

    return morningEveningTint * blueHourTint * userTint;
}

float getMoonExposure() {
    const float baseScale = 0.66 * moonI;

    float timeBoost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sunDir.y, 0.1)));

#ifdef moonPhaseAffectsBrightness
    return baseScale * moonPhaseBrightness * timeBoost;
#else
    // The moon phase only tints the night, it does not change its brightness.
    return baseScale * timeBoost;
#endif
}

vec3 getMoonTint() {
    const vec3 baseTint = fromDisplay(vec3(moonR, moonG, moonB));

    return baseTint;
}

vec3 getLightColor() {
    vec3 lightColor
        = sunlightColor * atmosphereTransmittance(lightDir.y, planetRadius);
    lightColor = atmospherePostProcessing(lightColor);
    vec3 moonLight = getMoonExposure() * getMoonTint();

    lightColor *= mix(
        getSunExposure() * getSunTint(),
        moonLight,
        step(0.5, sunAngle)
    );
    lightColor *= clamp01(
        rcp(0.02) * lightDir.y
    ); // fade away during day/night transition
    lightColor *= 1.0 - 0.25 * pulse(abs(lightDir.y), 0.15, 0.11);

    return lightColor;
}

#endif // INCLUDE_LIGHT_COLORS_LIGHT_COLOR
#endif

#if defined(LUSTER_INCLUDE_WEATHER_COLOR)
// Precipitation and weather color helpers.
#if !defined INCLUDE_LIGHT_COLORS_WEATHER_COLOR
#define INCLUDE_LIGHT_COLORS_WEATHER_COLOR

#include "/lib/atmos/air/atmosphere.glsl"

uniform float biomeMaySandstorm;

vec3 getRainColor() {
    return mix(0.033, 0.66, smoothstep(-0.1, 0.5, sunDir.y)) * sunlightColor
        * vec3(0.49, 0.65, 1.00);
}

vec3 getSnowColor() {
#if defined PROGRAM_WEATHER
    return mix(0.5, 1.60, smoothstep(-0.1, 0.5, sunDir.y)) * sunlightColor
        * vec3(0.49, 0.65, 1.00);
#else
    return mix(0.060, 1.60, smoothstep(-0.1, 0.5, sunDir.y)) * sunlightColor
        * vec3(0.49, 0.65, 1.00);
#endif
}

vec3 getSandstormColor() {
    return mix(0.033, 0.66, smoothstep(-0.1, 0.5, sunDir.y)) * sunlightColor
        * vec3(1.00, 0.83, 0.60);
}

vec3 getWeatherColor() {
    vec3 weatherColor
        = mix(getRainColor(), getSnowColor(), biomeMaySnow);
    weatherColor
        = mix(weatherColor, getSandstormColor(), biomeMaySandstorm);

    return weatherColor;
}

#endif // INCLUDE_LIGHT_COLORS_WEATHER_COLOR
#endif
