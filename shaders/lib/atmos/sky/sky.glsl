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

#if !defined INCLUDE_SKY_SKY
#define INCLUDE_SKY_SKY

#include "/lib/util/color.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"

#if defined WORLD_OVERWORLD || defined WORLD_END
#if !defined INCLUDE_SKY_STARS
#define INCLUDE_SKY_STARS

// Stars based on https://www.shadertoy.com/view/Md2SR3

vec3 unstableStarField(vec2 coord, float starThreshold) {
    const float minTemp = 4500.0;
    const float maxTemp = 8500.0;

    vec4 noise = hash4(coord);

    float star = linearStep(starThreshold, 1.0, noise.x);
    star = pow16(star) * starsIntensity;

    float temp = mix(minTemp, maxTemp, noise.y);
    vec3 color = blackbody(temp);

    const float twinkleSpeed = 2.0;
    float twinkleAmount = noise.z;
    float twinkleOffset = tau * noise.w;
    star *= 1.0
        - twinkleAmount
            * cos(frameTimeCounter * twinkleSpeed + twinkleOffset);

    return star * color;
}

// Stabilizes the star field by sampling at the four neighboring integer
// coordinates and interpolating
vec3 stableStarField(vec2 coord, float starThreshold) {
    coord = abs(coord) + 33.3 * step(0.0, coord);
    vec2 i, f = modf(coord, i);

    f.x = cubicSmooth(f.x);
    f.y = cubicSmooth(f.y);

    return unstableStarField(i + vec2(0.0, 0.0), starThreshold) * (1.0 - f.x)
        * (1.0 - f.y)
        + unstableStarField(i + vec2(1.0, 0.0), starThreshold) * f.x
        * (1.0 - f.y)
        + unstableStarField(i + vec2(0.0, 1.0), starThreshold) * f.y
        * (1.0 - f.x)
        + unstableStarField(i + vec2(1.0, 1.0), starThreshold) * f.x * f.y;
}

vec3 drawStars(vec3 rayDir, float galaxyLuminance) {
    // Adjust star threshold so that brightest stars appear first
#if defined WORLD_OVERWORLD
    float starThreshold = 1.0
        - 0.05 * starsCoverage * smoothstep(-0.2, 0.05, -sunDir.y)
        - 0.5 * cube(galaxyLuminance);
#else
    float starThreshold = 1.0 - 0.008 * starsCoverage;
#endif

    // Project ray direction onto the plane
    vec2 coord = rayDir.xy * rcp(abs(rayDir.z) + length(rayDir.xy))
        + 41.21 * sign(rayDir.z);
    coord *= 600.0;

    return stableStarField(coord, starThreshold);
}

#endif // INCLUDE_SKY_STARS

#endif

//----------------------------------------------------------------------------//
#if defined WORLD_OVERWORLD

#include "/lib/brdf/fresnel.glsl"
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
#if !defined INCLUDE_MISC_LIGHTNING_FLASH
#define INCLUDE_MISC_LIGHTNING_FLASH

#ifdef lightningFlash
uniform float lightningFlashIris;
#define LIGHTNING_FLASH_UNIFORM lightningFlashIris
#else
#define LIGHTNING_FLASH_UNIFORM 0.0
#endif

const float lightningFlashIntensity = 4.0;

#endif // INCLUDE_MISC_LIGHTNING_FLASH
#include "/lib/atmos/atmosphere.glsl"
#include "/lib/atmos/projection.glsl"
#include "/lib/atmos/sky/rainbow.glsl"
#include "/lib/util/geometry.glsl"

#if defined PROGRAM_DEFERRED0
#include "/lib/atmos/sky/clouds/pipeline.glsl"

#if defined crepuscularRays && !defined blockyClouds
#include "/lib/atmos/crepuscularRays.glsl"
#endif
#endif

const float sunLuminance = rcp(
    coneAngleToSolidAngle(sunAngularSizeRad)
); // luminance of sun disk
const float moonLuminance = 10.0; // luminance of moon disk

vec3 drawSun(vec3 rayDir) {
    float nu = dot(rayDir, sunDir);

    // Limb darkening model from
    // http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
    const vec3 alpha = vec3(0.429, 0.522, 0.614);
    float centerToEdge = max0(sunAngularSizeRad - fastAcos(clamp(nu, -1.0, 1.0)));
    vec3 limbDarkening
        = pow(vec3(1.0 - sqr(1.0 - centerToEdge)), 0.5 * alpha);

    return sunLuminance * sunColor * step(0.0, centerToEdge)
        * limbDarkening;
}

vec4 drawMoon(vec3 rayDir) {
    const vec3 litColor
        = vec3(moonR, moonG <= 0.03 ? 0.0 : moonG - 0.03, moonB);
    const vec3 glowColor
        = vec3(moonR <= 0.05 ? 0.0 : moonR - 0.05, moonG, moonB);

    // Cut out the moon disc.
    float MoV = dot(rayDir, moonDir);
    if (MoV < cos(moonAngularSizeRad)) {
        return vec4(0.0);
    }

    // Find distance from center to edge.
    float dist = clamp01(fastAcos(clamp(MoV, -1.0, 1.0)) / moonAngularSizeRad);

    // Transform the coordinate space such that z is parallel to moonDir
    vec3 tangent = abs(moonDir.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
    vec3 bitangent = normalize(cross(tangent, moonDir));
    mat3 tbn = mat3(tangent, bitangent, moonDir);

    // Vector from ray dir to moon dir.
    vec2 offset = ((rayDir - moonDir) * tbn).xy;
    offset = fract(offset + 0.5);

    vec3 noise = texture(noisetex, 2.0 * offset).xyz;
    float moonTexture
        = pow1d5(noise.x) * 0.75 + 0.6 * cube(noise.y) - 0.1 * noise.z;

    // Find the distance to the moon if it were 1 unit away, and its normal.
    float moonDist
        = intersectSphere(-moonDir, rayDir, moonAngularSizeRad).x;
    vec3 moonNormal = normalize(rayDir * moonDist - moonDir);

    // Get light direction which orbits around moon. Anchored to the fixed
    // moon frame so the phase terminator does not swim with the view ray.
    float lightAngle = 0.125 * tau * float(moonPhase);
    vec3 leftDir = abs(moonDir.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
    vec3 lightDir = cos(lightAngle) * -moonDir + sin(lightAngle) * leftDir;
    float moonShadow = dampen(max0(dot(moonNormal, lightDir)));

    float edgeGlow = sqr(sqr(sqr(dist)));

    vec3 color = max(moonShadow * litColor * (1.0 + 4.0 * edgeGlow),
                     0.5 * glowColor * (0.1 + 0.1 * edgeGlow))
        * (0.2 + 0.8 * moonTexture);
    color = moonLuminance * sqr(color);
    return vec4(color, 1.0);
}

#ifdef galaxy
vec3 drawGalaxy(vec3 rayDir, out float galaxyLuminance) {
    const vec3 galaxyTint = vec3(0.75, 0.66, 1.0) * galaxyIntensity;

    float galaxyBrightness = 0.05 + 1.0 * linearStep(-0.1, 0.25, -sunDir.y);

    float lon = atan(rayDir.x, rayDir.z);
    float lat = fastAcos(clamp(-rayDir.y, -1.0, 1.0));

    vec3 galaxyColor
        = texture(galaxySampler, vec2(lon * rcp(tau) + 0.5, lat * rcp(pi)))
              .rgb;

    galaxyColor = srgbEotfInv(galaxyColor) * rec709ToWorkingColor;

    galaxyColor *= galaxyBrightness * galaxyTint;

    galaxyLuminance = dot(galaxyColor, luminanceWeights);

    galaxyColor = mix(vec3(galaxyLuminance), galaxyColor, 2.0);

    return max0(galaxyColor);
}
#endif

vec3 drawSky(
    vec3 rayDir,
    vec3 atmosphere,
    vec4 cloudsAndAurora,
    float cloudsApparentDistance
) {
    vec3 sky = vec3(0.0);

#if defined shadow
    // Trick to make stars rotate with sun and moon
    mat3 rot = (sunAngle < 0.5)
        ? mat3(shadowModelViewInverse)
        : mat3(
              -shadowModelViewInverse[0].xyz,
              shadowModelViewInverse[1].xyz,
              -shadowModelViewInverse[2].xyz
          );

    vec3 celestialDir = rayDir * rot;
#else
    vec3 celestialDir = rayDir;
#endif

    // Galaxy

#ifdef galaxy
    float galaxyLuminance;
    sky += drawGalaxy(celestialDir, galaxyLuminance);
#else
    const float galaxyLuminance = 0.0;
#endif

    // Sun, moon stars

#if defined PROGRAM_DEFERRED11
    vec3 skytexturedOutput
        = texelFetch(colortex0, ivec2(gl_FragCoord.xy), 0).rgb;
    sky += skytexturedOutput;

#ifdef stars
    // Stars
    float starsVisibility
        = clamp01(1.0 - dot(skytexturedOutput, vec3(0.33) * 256.0));
    sky += drawStars(celestialDir, galaxyLuminance) * starsVisibility;
#endif

#ifndef vanillaSun
    // Shader sun
    sky += drawSun(rayDir);
#endif

#ifndef vanillaMoon
    // Shader moon
    vec4 moon = drawMoon(rayDir);
    sky *= 1.0 - moon.a;
    sky += moon.rgb;
#endif
#endif

    // Atmosphere

    sky *= atmosphereTransmittance(rayDir.y, planetRadius)
        * (1.0 - rainStrength);
#if defined desertSandstorm && defined sandstormSky


    sky *= sandstormTransmittance(rayDir.y);
#endif
    sky += atmosphere;

    // Clouds, aurora, crepuscular rays

    sky *= cloudsAndAurora.a; // Transmittance
    sky += cloudsAndAurora.rgb; // Scattering

    // Rainbow

    sky = drawRainbows(
        sky,
        rayDir,
        mix(cloudsApparentDistance,
            1e6,
            linearStep(1.0, 0.95, cloudsAndAurora.w))
    );

    // Cave sky fix

#if !defined PROGRAM_DEFERRED0
    // Fade lower part of sky into cave fog color when underground so that the
    // sky isn't visible beyond the render distance
    float undergroundSkyFade
        = biomeCave * smoothstep(-0.1, 0.1, 0.4 - rayDir.y);
    sky = mix(sky, vec3(0.0), undergroundSkyFade);
#endif

    return sky;
}

#if defined PROGRAM_DEFERRED0
vec4 getCloudsAndAurora(
    vec3 rayDir,
    vec3 clearSky,
    out float cloudsApparentDistance
) {
    cloudsApparentDistance = 1e6;

    ivec2 texel = ivec2(gl_FragCoord.xy);
    texel.x = texel.x % (skyMapRes.x - 4);

    float dither = interleavedGradientNoise(vec2(texel));

    // Clouds

#ifndef blockyClouds
    const vec3 airViewerPos = vec3(0.0, planetRadius, 0.0);
    CloudsResult result
        = drawClouds(airViewerPos, rayDir, clearSky, -1.0, dither);

    // Lightning flash
    result.scattering.rgb += LIGHTNING_FLASH_UNIFORM * lightningFlashIntensity
        * result.scattering.a;
#else
    CloudsResult result = cloudsNotHit;
#endif

    cloudsApparentDistance = result.apparentDistance;

    // Aurora

    vec3 aurora = drawAurora(rayDir, dither);

    vec4 cloudsAndAurora = vec4(
        result.scattering.xyz + aurora * result.transmittance,
        result.transmittance
    );

    // Crepuscular rays (sky-map ambient path only)

#if defined crepuscularRays && !defined blockyClouds
    vec4 crepuscularRaysSample
        = drawCrepuscularRays(colortex8, rayDir, false, dither);
    cloudsAndAurora *= crepuscularRaysSample.w;
    cloudsAndAurora.rgb += crepuscularRaysSample.xyz;
#endif

    return cloudsAndAurora;
}

vec3 drawSky(vec3 rayDir) {
    vec3 atmosphere = atmosphereScattering(
        rayDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        true
    );
    float cloudsApparentDistance;
    vec4 cloudsAndAurora
        = getCloudsAndAurora(rayDir, atmosphere, cloudsApparentDistance);
    return drawSky(
        rayDir,
        atmosphere,
        cloudsAndAurora,
        cloudsApparentDistance
    );
}
#endif

//----------------------------------------------------------------------------//
#elif defined WORLD_NETHER

vec3 drawSky(vec3 rayDir) { return ambientColor; }

//----------------------------------------------------------------------------//
#elif defined WORLD_END

#include "/lib/atmos/atmosphere.glsl"

const float sunSolidAngle = coneAngleToSolidAngle(sunAngularSizeRad);
const vec3 endSunColor = vec3(1.0, 0.5, 0.25);

vec3 drawSun(vec3 rayDir) {
    float nu = dot(rayDir, sunDir);
    float r = fastAcos(clamp(nu, -1.0, 1.0));

    // Sun disk

    const vec3 alpha = vec3(0.6, 0.5, 0.4);
    float centerToEdge = max0(sunAngularSizeRad - r);
    vec3 limbDarkening
        = pow(vec3(1.0 - sqr(1.0 - centerToEdge)), 0.5 * alpha);
    vec3 sunDisk = limbDarkening * vec3(r < sunAngularSizeRad);

    // Solar flare effect

    // Transform the coordinate space such that z is parallel to sunDir
    vec3 tangent = sunDir.y == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), sunDir));
    vec3 bitangent = normalize(cross(tangent, sunDir));
    mat3 rot = mat3(tangent, bitangent, sunDir);

    // Vector from ray dir to sun dir
    vec2 q = ((rayDir - sunDir) * rot).xy;

    float theta = fract(
        linearStep(-pi, pi, atan(q.y, q.x)) + 0.015 * frameTimeCounter
        - 0.33 * r
    );

    float flare
        = texture(noisetex, vec2(theta, r - 0.025 * frameTimeCounter)).x;
    flare = pow5(flare) * exp(-25.0 * (r - sunAngularSizeRad));
    flare = r < sunAngularSizeRad ? 0.0 : flare;

    return endSunColor * rcp(sunSolidAngle) * max0(sunDisk + 0.1 * flare);
}

vec3 drawSky(vec3 rayDir) {
    // Sky gradient

    float upGradient
        = linearStep(0.0, 0.4, rayDir.y) + linearStep(0.1, 0.8, -rayDir.y);
    vec3 sky = ambientColor * mix(0.1, 0.04, upGradient);
    float miePhase = cornetteShanksPhase(dot(rayDir, sunDir), 0.6);
    sky += 0.1 * (ambientColor + 0.5 * endSunColor) * miePhase;

#if defined PROGRAM_DEFERRED11
    // Sun

#ifdef endSunEffect
    // Fixed End sun disk brightness


    sky += drawSun(rayDir) * 1.00;
#endif

    // Stars

    vec3 starsFade
        = exp2(-0.1 * max0(1.0 - rayDir.y) / max(ambientColor, eps))
        * linearStep(-0.2, 0.0, rayDir.y);
    sky += drawStars(rayDir, 0.0).xzy * starsFade;
#endif

    return sky;
}

#endif

#endif // INCLUDE_SKY_SKY
