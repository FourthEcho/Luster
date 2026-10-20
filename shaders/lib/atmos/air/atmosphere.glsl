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

#if !defined INCLUDE_ATMOS_AIR_ATMOSPHERE
#define INCLUDE_ATMOS_AIR_ATMOSPHERE

#include "/lib/academy/matrices.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/geometry.glsl"
#include "/lib/util/phaseFunctions.glsl"
#include "/lib/atmos/air/overworld/aerosols.glsl"

// These have to be macros so that they can be used by constant expressions
#define coneAngleToSolidAngle(theta) (tau * (1.0 - cos(theta)))
#define solidAngleToConeAngle(theta) acos(1.0 - (theta) / tau)

const vec3 sunlightColor = vec3(
    1.051,
    0.985,
    0.940
); // Color of sunlight in space, obtained from AM0 solar irradiance spectrum
   // from https://www.nrel.gov/grid/solar-resource/spectra-astm-e490.html using
   // the CIE (2006) 2-deg LMS cone fundamentals

const float sunAngularSizeRad = sunAngularRadius * degree;
const float moonAngularSizeRad = moonAngularRadius * degree;

const ivec2 transmittanceRes = ivec2(/* mu */ 256, /* r */ 64);
const ivec3 scatteringRes = ivec3(/* nu */ 16, /* mu */ 64, /* muS */ 32);

const float minMuS = -0.35;

// Atmosphere boundaries

const float planetRadius = 6371e3; // m

const float atmosphereInnerRadius = planetRadius - 1e3; // m
const float atmosphereOuterRadius = planetRadius + 110e3; // m

const float planetRadiusSq = planetRadius * planetRadius;
const float atmosphereThickness
    = atmosphereOuterRadius - atmosphereInnerRadius;
const float atmosphereInnerRadiusSq
    = atmosphereInnerRadius * atmosphereInnerRadius;
const float atmosphereOuterRadiusSq
    = atmosphereOuterRadius * atmosphereOuterRadius;

// Atmosphere coefficients

const float airMieAlbedo = 0.9;
const float airMieEnergyParam
    = 3000.0; // Energy parameter for the Klein-Nishina phase function
const float airMieG
    = mieAnisotropy; // Anisotropy parameter for Henyey-Greenstein phase function

const vec2 airScaleHeights = vec2(8.4e3, 1.25e3); // m

// Coefficients for Rec. 709 primaries transformed to Rec. 2020
const vec3 airRayleighCoef
    = vec3(8.059375432e-06, 1.671209429e-05, 4.080133294e-05)
    * rec709ToWorkingColor;
const vec3 airMieCoef
    = vec3(1.666442358e-06, 1.812685127e-06, 1.958927896e-06)
    * vec3(mieColorR, mieColorG, mieColorB) // user tint (Rec. 709)
    * rec709ToWorkingColor;
const vec3 airOzoneCoef
    = vec3(8.304280072e-07, 1.314911970e-06, 5.440679729e-08)
    * vec3(ozoneColorR, ozoneColorG, ozoneColorB) // user tint (Rec. 709)
    * rec709ToWorkingColor;

const mat2x3 airScatteringCoefs
    = mat2x3(airRayleighCoef, airMieAlbedo* airMieCoef);
const mat3x3 airExtinctionCoefs = mat3x3(
    airRayleighCoef,
    airMieCoef,
    airOzoneCoef
);

uniform float atmosphereSaturationBoostAmount;


vec3 atmosphereTransmittance(float mu, float r);

float atmosphereMiePhase(float nu, bool useKleinNishinaPhase) {
    return useKleinNishinaPhase
        ? kleinNishinaPhaseArea(
              nu,
              airMieEnergyParam,
              moonAngularSizeRad
          )
        : henyeyGreensteinPhase(nu, airMieG);
}

vec3 atmosphereMiePhaseSun(float nu) {
    float r = nvidiaPhaseArea(nu, 0.85, 1.0, sunAngularSizeRad);
    float g = nvidiaPhaseArea(nu, 0.86, 1.0, sunAngularSizeRad);
    float b = nvidiaPhaseArea(nu, 0.87, 1.0, sunAngularSizeRad);
    vec3 nvidiaRGB = vec3(r, g, b);
    return nvidiaRGB * 0.2; // artistic scale
}

vec3 atmosphereMiePhaseMoon(float nu) {
    float moonIntensity = 1.02;

    float t = float(moonPhase) / 4.0;
    t = t > 1.0 ? 2.0 - t : t;
    t = sqr(1.0 - t) * 0.04 + 0.96; // small phase difference

    float r = nvidiaPhaseArea(nu, 0.895 * t, 1.0, 2 * moonAngularSizeRad);
    float g = nvidiaPhaseArea(nu, 0.90 * t, 1.0, 2 * moonAngularSizeRad);
    float b = nvidiaPhaseArea(nu, 0.905 * t, 1.0, 2 * moonAngularSizeRad);
    vec3 nvidiaRGB = vec3(r, g, b);
    return nvidiaRGB * moonIntensity;
}

#ifdef planetBounce

// Planet bounce light

const vec3 planetBounceAlbedo = vec3(0.30, 0.33, 0.22);

vec3 atmospherePlanetBounce(
    vec3 rayDir,
    vec3 sunColor,
    vec3 sunDir,
    vec3 moonColor,
    vec3 moonDir
) {


    const vec3 groundNormal = vec3(0.0, 1.0, 0.0);

    vec3 albedo = mix(
        planetBounceAlbedo,
        planetBounceAlbedo * vec3(0.4),
        rainStrength
    );

    float sunNdotl = max0(dot(groundNormal, sunDir));
    float moonNdotl = max0(dot(groundNormal, moonDir));


    vec3 downSun = atmosphereTransmittance(sunDir.y, planetRadius);
    vec3 downMoon = atmosphereTransmittance(moonDir.y, planetRadius);
    vec3 upPath = atmosphereTransmittance(max(rayDir.y, 0.01), planetRadius);

    vec3 bounced = albedo * (1.0 / pi) * (
        sunNdotl * sunColor * downSun +
        moonNdotl * moonColor * downMoon
    ) * upPath;

#if defined ozoneLayer && defined ozonePlanetBounce


    bounced *= ozoneMultipleScattering(1.0);
#endif

#if defined desertSandstorm && defined sandstormBounce


    bounced *= sandstormTransmittance(0.6);
#endif


    float groundWeight = clamp01(1.0 - rayDir.y * 2.0);

    return bounced * groundWeight * planetBounceIntensity;
}
#endif

// Post-processing applied to the atmosphere color
vec3 atmospherePostProcessing(vec3 atmosphere) {
    // The boost and the rain desaturation each have their own toggle, so the
    // intensity sliders only apply while the feature is enabled.
    float saturationBoost = 0.0;
    float rainDesaturation = 0.0;

#ifdef atmosphereSaturationBoost
    saturationBoost = atmosphereSaturationBoostIntensity * atmosphereSaturationBoostAmount;
#endif

#ifdef atmosphereRainDesaturation
    rainDesaturation = atmosphereRainDesaturationIntensity;
#endif

    // Atmosphere saturation boost and rain saturation influence
    atmosphere = mix(
        vec3(dot(atmosphere, luminanceWeights)),
        atmosphere,
        (1 + saturationBoost) * (1 - rainStrength * rainDesaturation)
    );

    return atmosphere;
}

/*
 * Mapping functions from Eric Bruneton's 2020 atmosphere implementation
 * https://ebruneton.github.io/precomputedAtmosphericScattering/atmosphere/functions.glsl.html
 *
 * License:
 * Copyright (c) 2017 Eric Bruneton
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its
 * contributors may be used to endorse or promote products derived from this
 * software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * nu: cos view-light angle
 * mu: cos view-zenith angle
 * muS: cos light-zenith angle
 * r: distance to planet centre
 */

vec3 atmosphereDensity(float r) {
    const vec2 rcpScaleHeights = rcp(airScaleHeights);
    const vec2 scaledPlanetRadius = planetRadius * rcpScaleHeights;

    vec2 rayleighMie = exp(r * -rcpScaleHeights + scaledPlanetRadius);

    // Ozone density distribution from Jessie -
    // https://www.desmos.com/calculator/b66xr8madc
    float altitudeKm = r * 1e-3 - (planetRadius * 1e-3);
    float o1 = 12.5 * exp(rcp(8.0) * (0.0 - altitudeKm));
    float o2
        = 30.0 * exp(rcp(80.0) * (18.0 - altitudeKm) * (altitudeKm - 18.0));
    float o3
        = 75.0 * exp(rcp(50.0) * (23.5 - altitudeKm) * (altitudeKm - 23.5));
    float o4
        = 50.0 * exp(rcp(150.0) * (30.0 - altitudeKm) * (altitudeKm - 30.0));
    float ozone = 7.428e-3 * (o1 + o2 + o3 + o4);

    return vec3(rayleighMie, ozone);
}

#if defined ATMOSPHERE_SCATTERING_LUT
vec3 atmosphereScatteringUv(float nu, float mu, float muS) {
    // Improved mapping for nu from Spectrum by Zombye

    float halfRangeNu = sqrt(max((1.0 - mu * mu) * (1.0 - muS * muS), 0.0));
    float nuMin = mu * muS - halfRangeNu;
    float nuMax = mu * muS + halfRangeNu;

    float uNu
        = (nuMin == nuMax) ? nuMin : (nu - nuMin) / (nuMax - nuMin);
    uNu = getUvFromUnitRange(uNu, scatteringRes.x);

    // Stretch the sky near the horizon upwards (to make it easier to admire the
    // sunset without zooming in)

    if (mu > 0.0) {
        mu *= sqrt(sqrt(mu));
    }

    // Mapping for mu

    const float r = planetRadius; // distance to the planet centre
    const float H = sqrt(
        atmosphereOuterRadiusSq - atmosphereInnerRadiusSq
    ); // distance to the atmosphere upper limit for a horizontal ray at ground
       // level
    const float rho = sqrt(
        max0(planetRadius * planetRadius - atmosphereInnerRadiusSq)
    ); // distance to the horizon

    // Discriminant of the quadratic equation for the intersections of the ray
    // (r, mu) with the ground
    float rmu = r * mu;
    float discriminant = rmu * rmu - r * r + atmosphereInnerRadiusSq;

    float uMu;
    if (mu < 0.0 && discriminant >= 0.0) { // Ray (r, mu) intersects ground
        // Distance to the ground for the ray (r, mu) and its minimum and
        // maximum values over all mu
        float d = -rmu - sqrt(max0(discriminant));
        float dMin = r - atmosphereInnerRadius;
        float dMax = rho;

        uMu = dMax == dMin ? 0.0 : (d - dMin) / (dMax - dMin);
        uMu = getUvFromUnitRange(uMu, scatteringRes.y / 2);
        uMu = 0.5 - 0.5 * uMu;
    } else {
        // Distance to exit the atmosphere outer limit for the ray (r, mu) and
        // its minimum and maximum values over all mu
        float d = -rmu + sqrt(discriminant + H * H);
        float dMin = atmosphereOuterRadius - r;
        float dMax = rho + H;

        uMu = (d - dMin) / (dMax - dMin);
        uMu = getUvFromUnitRange(uMu, scatteringRes.y / 2);
        uMu = 0.5 + 0.5 * uMu;
    }

    // Mapping for muS

    // Distance to the atmosphere outer limit for the ray
    // (atmosphereInnerRadius, muS)
    float d = intersectSphere(
                  muS,
                  atmosphereInnerRadius,
                  atmosphereOuterRadius
    )
                  .y;
    float dMin = atmosphereThickness;
    float dMax = H;
    float a = (d - dMin) / (dMax - dMin);

    // Distance to the atmosphere upper limit for the ray
    // (atmosphereInnerRadius, minMuS)
    float D = intersectSphere(
                  minMuS,
                  atmosphereInnerRadius,
                  atmosphereOuterRadius
    )
                  .y;
    float A = (D - dMin) / (dMax - dMin);


    float uMuS = getUvFromUnitRange(
        max0(1.0 - a / A) / (1.0 + a),
        scatteringRes.z
    );

    return vec3(uNu, uMu, uMuS);
}

vec3 atmosphereScattering(
    float nu,
    float mu,
    float muS,
    bool useKleinNishinaPhase
) {
    // Keep the unclamped view zenith cosine around for the ozone layer's
    // view-path absorption below
    float muView = mu;

    float horizonMu = mix(-0.01, 0.03, smoothstep(-0.05, 0.1, muS));
    mu = max(mu, horizonMu);

    vec3 uv = atmosphereScatteringUv(nu, mu, muS);

    float miePhase = atmosphereMiePhase(nu, useKleinNishinaPhase);

    vec3 scattering;

    // Rayleigh + multiple scattering
    // The LUT is baked in Rec. 2020, so it is converted into the working
    // gamut before it is combined with the working space sun colour.
    uv.x *= 0.5;
    scattering = texture(ATMOSPHERE_SCATTERING_LUT, uv).rgb
        * rec2020ToWorkingColor;

    // Single mie scattering
    uv.x += 0.5;
    scattering += texture(ATMOSPHERE_SCATTERING_LUT, uv).rgb
        * rec2020ToWorkingColor * miePhase;

#if defined ozoneLayer && defined ozoneSky


    scattering *= ozoneLayerViewTransmittance(muView, planetRadius);
#endif

#if defined desertSandstorm && defined sandstormSky


    scattering *= sandstormTransmittance(muView);
#endif

    return atmospherePostProcessing(scattering);
}

vec3 atmosphereScattering(
    vec3 rayDir,
    vec3 lightDir,
    bool useKleinNishinaPhase
) {
    float nu = dot(rayDir, lightDir);
    float mu = rayDir.y;
    float muS = lightDir.y;

    return atmosphereScattering(nu, mu, muS, useKleinNishinaPhase);
}

// Samples atmospheric scattering LUT for both sun and moon together
// Prevents a few repeated calculations
vec3 atmosphereScattering(
    vec3 rayDir,
    vec3 sunColor,
    vec3 sunDir,
    vec3 moonColor,
    vec3 moonDir,
    bool useKleinNishinaPhase
) {
    // Calculate nu, mu, muS

    float mu = rayDir.y;

    // Keep the unclamped view zenith cosine around for the ozone layer's
    // view-path absorption below
    float muView = mu;

    float nuSun = dot(rayDir, sunDir);
    float nuMoon = dot(rayDir, moonDir);

    float muSun = sunDir.y;
    float muMoon = moonDir.y;


    vec3 sunLutColor = sunColor;
    vec3 moonLutColor = moonColor;
#if defined ozoneLayer && defined ozoneSky
    sunLutColor *= ozoneLayerTransmittance(muSun, planetRadius);
    moonLutColor *= ozoneLayerTransmittance(muMoon, planetRadius);
#endif
#if defined desertSandstorm && defined sandstormSky


    sunLutColor *= sandstormTransmittance(muSun);
    moonLutColor *= sandstormTransmittance(muMoon);
#endif

    float horizonMu = mix(
        -0.01,
        0.03,
        clamp01(smoothstep(-0.05, 0.1, muSun) + smoothstep(0.05, 0.1, muMoon))
    );
    mu = max(mu, horizonMu);

    // Improved mapping for nu from Spectrum by Zombye

    float halfRangeNu, nuMin, nuMax;

    halfRangeNu = sqrt(max((1.0 - mu * mu) * (1.0 - muSun * muSun), 0.0));
    nuMin = mu * muSun - halfRangeNu;
    nuMax = mu * muSun + halfRangeNu;

    float uNuSun
        = (nuMin == nuMax) ? nuMin : (nuSun - nuMin) / (nuMax - nuMin);
    uNuSun = getUvFromUnitRange(uNuSun, scatteringRes.x);

    halfRangeNu = sqrt(max((1.0 - mu * mu) * (1.0 - muMoon * muMoon), 0.0));
    nuMin = mu * muMoon - halfRangeNu;
    nuMax = mu * muMoon + halfRangeNu;

    float uNuMoon
        = (nuMin == nuMax) ? nuMin : (nuMoon - nuMin) / (nuMax - nuMin);
    uNuMoon = getUvFromUnitRange(uNuMoon, scatteringRes.x);

    // Stretch the sky near the horizon upwards (to make it easier to admire the
    // sunset without zooming in)

    if (mu > 0.0) {
        mu *= sqrt(sqrt(mu));
    }

    // Mapping for mu

    const float r = planetRadius; // distance to the planet centre
    const float H = sqrt(
        atmosphereOuterRadiusSq - atmosphereInnerRadiusSq
    ); // distance to the atmosphere upper limit for a horizontal ray at ground
       // level
    const float rho = sqrt(
        max0(planetRadius * planetRadius - atmosphereInnerRadiusSq)
    ); // distance to the horizon

    // Discriminant of the quadratic equation for the intersections of the ray
    // (r, mu) with the ground
    float rmu = r * mu;
    float discriminant = rmu * rmu - r * r + atmosphereInnerRadiusSq;

    float uMu;
    if (mu < 0.0 && discriminant >= 0.0) { // Ray (r, mu) intersects ground
        // Distance to the ground for the ray (r, mu) and its minimum and
        // maximum values over all mu
        float d = -rmu - sqrt(max0(discriminant));
        float dMin = r - atmosphereInnerRadius;
        float dMax = rho;

        uMu = dMax == dMin ? 0.0 : (d - dMin) / (dMax - dMin);
        uMu = getUvFromUnitRange(uMu, scatteringRes.y / 2);
        uMu = 0.5 - 0.5 * uMu;
    } else {
        // Distance to exit the atmosphere outer limit for the ray (r, mu) and
        // its minimum and maximum values over all mu
        float d = -rmu + sqrt(discriminant + H * H);
        float dMin = atmosphereOuterRadius - r;
        float dMax = rho + H;

        uMu = (d - dMin) / (dMax - dMin);
        uMu = getUvFromUnitRange(uMu, scatteringRes.y / 2);
        uMu = 0.5 + 0.5 * uMu;
    }

    // Mapping for muS

    float d, a;

    const float dMin = atmosphereThickness;
    const float dMax = H;

    // Distance to the atmosphere upper limit for the ray
    // (atmosphereInnerRadius, minMuS)
    float D = intersectSphere(
                  minMuS,
                  atmosphereInnerRadius,
                  atmosphereOuterRadius
    )
                  .y;
    float A = (D - dMin) / (dMax - dMin);

    // Distance to the atmosphere outer limit for the ray
    // (atmosphereInnerRadius, muS)
    d = intersectSphere(
            muSun,
            atmosphereInnerRadius,
            atmosphereOuterRadius
    )
            .y;
    a = (d - dMin) / (dMax - dMin);


    float uMuSun = getUvFromUnitRange(
        max0(1.0 - a / A) / (1.0 + a),
        scatteringRes.z
    );

    d = intersectSphere(
            muMoon,
            atmosphereInnerRadius,
            atmosphereOuterRadius
    )
            .y;
    a = (d - dMin) / (dMax - dMin);

    float uMuMoon = getUvFromUnitRange(
        max0(1.0 - a / A) / (1.0 + a),
        scatteringRes.z
    );

    // Sample atmosphere LUT

    vec3 uvSc = vec3(
        uNuSun * 0.5,
        uMu,
        uMuSun
    ); // Rayleigh + multiple scattering, sunlight
    vec3 uvSm = vec3(
        uNuSun * 0.5 + 0.5,
        uMu,
        uMuSun
    ); // Mie scattering, sunlight
    vec3 uvMc = vec3(
        uNuMoon * 0.5,
        uMu,
        uMuMoon
    ); // Rayleigh + multiple scattering, moonlight
    vec3 uvMm = vec3(
        uNuMoon * 0.5 + 0.5,
        uMu,
        uMuMoon
    ); // Mie scattering, moonlight

    // The LUT is baked in Rec. 2020, so it is converted into the working
    // gamut before it is combined with the working space sun colour.
    vec3 scatteringSc = texture(ATMOSPHERE_SCATTERING_LUT, uvSc).rgb
        * rec2020ToWorkingColor;
    vec3 scatteringSm = texture(ATMOSPHERE_SCATTERING_LUT, uvSm).rgb
        * rec2020ToWorkingColor;
    vec3 scatteringMc = texture(ATMOSPHERE_SCATTERING_LUT, uvMc).rgb
        * rec2020ToWorkingColor;
    vec3 scatteringMm = texture(ATMOSPHERE_SCATTERING_LUT, uvMm).rgb
        * rec2020ToWorkingColor;

    vec3 miePhaseSun = atmosphereMiePhaseSun(nuSun);
    vec3 miePhaseMoon = atmosphereMiePhaseMoon(nuMoon);

    vec3 lutScattering
        = (scatteringSc + scatteringSm * miePhaseSun) * sunLutColor
        + (scatteringMc + scatteringMm * miePhaseMoon) * moonLutColor;

#if defined ozoneLayer && defined ozoneSky


    lutScattering *= ozoneLayerViewTransmittance(muView, planetRadius);
#endif
#if defined desertSandstorm && defined sandstormSky
    // View-path dust extinction. Planet bounce carries its own up-path
    // dust filtering, so it is added after this factor (see below).
    lutScattering *= sandstormTransmittance(muView);
#endif

    vec3 atmosphere = lutScattering;

#ifdef planetBounce
    atmosphere += atmospherePlanetBounce(
        rayDir,
        sunColor,
        sunDir,
        moonColor,
        moonDir
    );
#endif

#ifdef renderBelowHorizon


    float belowHorizon
        = linearStep(horizonMu, horizonMu - 0.3, muView);
    if (belowHorizon > 0.0) {
        const vec3 belowPlanetAlbedo = vec3(0.30, 0.33, 0.22);

        vec3 downSun = atmosphereTransmittance(sunDir.y, planetRadius);
        vec3 downMoon = atmosphereTransmittance(moonDir.y, planetRadius);
        // Lambert ground, same 1/pi convention as atmospherePlanetBounce
        // so the disc meets the bounce glow seamlessly at the horizon.
        vec3 groundLight = belowPlanetAlbedo * rcpPi
            * (
                max0(sunDir.y) * sunLutColor * downSun
              + max0(moonDir.y) * moonLutColor * downMoon
            );


        vec3 groundUpPath = mix(
            atmosphereTransmittance(1.0, planetRadius),
            atmosphereTransmittance(0.02, planetRadius),
            linearStep(horizonMu - 0.3, horizonMu, muView)
        );
        groundLight *= groundUpPath;

        atmosphere = mix(
            atmosphere,
            groundLight * renderBelowHorizonIntensity,
            belowHorizon
        );
    }
#endif

    return atmospherePostProcessing(atmosphere);
}
#else
vec3 atmosphereScattering(vec3 rayDir, vec3 lightDir) { return vec3(0.0); }
#endif

#if defined ATMOSPHERE_TRANSMITTANCE_LUT || defined ATMOSPHERE_IRRADIANCE_LUT
vec2 atmosphereTransmittanceUv(float mu, float r) {
    // Distance to the atmosphere outer limit for a horizontal ray at ground
    // level
    const float H
        = sqrt(max(atmosphereOuterRadiusSq - atmosphereInnerRadiusSq, 0));

    // Distance to the horizon
    float rho = sqrt(max0(r * r - atmosphereInnerRadiusSq));

    // Distance to the atmosphere upper limit and its minimum and maximum values
    // over all mu
    float d = intersectSphere(mu, r, atmosphereOuterRadius).y;
    float dMin = atmosphereOuterRadius - r;
    float dMax = rho + H;

    float uMu = getUvFromUnitRange(
        (d - dMin) / (dMax - dMin),
        transmittanceRes.x
    );
    float uR = getUvFromUnitRange(rho / H, transmittanceRes.y);

    return vec2(uMu, uR);
}
#endif

#if defined ATMOSPHERE_TRANSMITTANCE_LUT
vec3 atmosphereTransmittance(float mu, float r) {
    if (intersectSphere(mu, r, planetRadius).x >= 0.0) {
        return vec3(0.0);
    }

    vec2 uv = atmosphereTransmittanceUv(mu, r);
    return texture(ATMOSPHERE_TRANSMITTANCE_LUT, uv).rgb;
}
#else
// Source: http://www.thetenthplanet.de/archives/4519
float chapmanFunctionApprox(float x, float cosTheta) {
    float c = sqrt(halfPi * x);

    if (cosTheta >= 0.0) { // => theta <= 90 deg
        return c / ((c - 1.0) * cosTheta + 1.0);
    } else {
        float sinTheta = sqrt(clamp01(1.0 - sqr(cosTheta)));
        return c / ((c - 1.0) * cosTheta - 1.0)
            + 2.0 * c * exp(x - x * sinTheta) * sqrt(sinTheta);
    }
}

vec3 atmosphereTransmittance(float mu, float r) {
    if (intersectSphere(mu, max(r, planetRadius + 10.0), planetRadius).x
        >= 0.0) {
        return vec3(0.0);
    }

    // Rayleigh and mie density at r. Keep this path consistent with the
    // precomputed-atmosphere density model used elsewhere in the file.
    vec3 density3 = atmosphereDensity(r);
    vec2 density = density3.xy;


    const vec2 rcpScaleHeights = rcp(airScaleHeights);
    vec2 airmass = airScaleHeights * density;
    airmass.x *= chapmanFunctionApprox(r * rcpScaleHeights.x, mu);
    airmass.y *= chapmanFunctionApprox(r * rcpScaleHeights.y, mu);

#if defined ozoneLayer


    float ozoneAirmass = ozoneLayerAirmass(mu, r);
#else
    // Legacy fallback: approximate ozone density as rayleigh density
    float ozoneAirmass = airmass.x;
#endif

    vec3 airmass3 = vec3(airmass.x, airmass.y, ozoneAirmass);
    vec3 transmittance
        = clamp01(exp(-airExtinctionCoefs * airmass3));

#if defined desertSandstorm && defined sandstormLayer

    // Scaled by the live storm strength, so a clear desert noon is

    transmittance *= sandstormTransmittance(mu);
#endif

    return transmittance;
}
#endif

vec3 atmosphereTransmittance(vec3 rayOrigin, vec3 rayDir) {
    float rSq = dot(rayOrigin, rayOrigin);
    float rcpR = inversesqrt(rSq);
    float mu = dot(rayOrigin, rayDir) * rcpR;
    float r = rSq * rcpR;

    return atmosphereTransmittance(mu, r);
}

#endif // INCLUDE_ATMOS_AIR_ATMOSPHERE
