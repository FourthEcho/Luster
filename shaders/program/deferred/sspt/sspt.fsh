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

layout(location = 0) out vec4 indirect;      // colortex17
layout(location = 1) out vec4 filterData;  // colortex19

/* RENDERTARGETS: 17,19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex22; // baked emission radiance (gbuffer writers)
uniform sampler2D colortex4; // sky map (skylight bounce sampling)
uniform sampler2D colortex6; // selected AO for SSPT contact-shadow finishing
uniform sampler2D colortex14; // AO history depth for depth-aware AO upscale

// Required on the non-DH path: combinedDepthTex expands to depthtex1 in
// lodMod.glsl, so this must stay declared even though the name never
// appears literally in this file.
uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

#if defined shadow && !defined WORLD_NETHER
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef shadowColor
uniform sampler2D shadowcolor0;
#endif

uniform vec3 sunDir;
uniform vec3 moonDir;
uniform float sunAngle;
uniform float timeSunrise;
uniform float timeSunset;
uniform float moonPhaseBrightness;
#endif

// Shadow matrices stay declared even where no shadow pass runs: the
// cloud-shadow helper chain references them, and unused uniforms are free.
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

#if defined WORLD_OVERWORLD && defined cloudShadows
uniform sampler2D colortex8; // cloud shadow map
#endif

// Declared for the atmosphere/cloud-shadow include chain
uniform float rainStrength;
uniform float desertSandstormWeather;
uniform vec3 lightDir;
uniform float eyeAltitude;
uniform int moonPhase;
uniform int isEyeInWater;

// ------------
//   Includes
// ------------

#define TRACE_DEPTH combinedDepthTex
#define TRACE_PROJ combinedProjectionMatrix
#define TRACE_PROJ_INV combinedProjectionMatrixInverse

#include "/lib/util/lodMod.glsl"
#if !defined INCLUDE_LIGHT_INDIRECT_LIGHT_SSPT
#define INCLUDE_LIGHT_INDIRECT_LIGHT_SSPT


#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/weather/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/direct/handheld.glsl"

#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/clouds/util/constants.glsl"
#include "/lib/util/bicubic.glsl"

const ivec2 cloudShadowRes = ivec2(512);

const float cloudShadowExtent = 256.0 / (cloudsScale / 10.0);

vec2 shadowViewToCloudShadowSpace(vec3 shadowViewPos) {
    vec2 cloudShadowPos = shadowViewPos.xy / cloudShadowExtent;
    cloudShadowPos /= 1.0 + length(cloudShadowPos);
    cloudShadowPos = cloudShadowPos * 0.5 + 0.5;

    return cloudShadowPos;
}

vec2 projectCloudShadowMap(vec3 scenePos) {
    return shadowViewToCloudShadowSpace(
        transform(shadowModelView, scenePos)
    );
}

vec3 unprojectCloudShadowMap(vec2 cloudShadowPos) {
    cloudShadowPos = cloudShadowPos * 2.0 - 1.0;
    cloudShadowPos /= 1.0 - length(cloudShadowPos);

    vec3 shadowViewPos = vec3(cloudShadowPos * cloudShadowExtent, 1.0);

    return transform(shadowModelViewInverse, shadowViewPos);
}

float getCloudShadows(sampler2D cloudShadowMap, vec3 scenePos) {
#ifndef cloudShadows
    return 1.0;
#else
    vec2 cloudShadowPos = projectCloudShadowMap(scenePos)
        * vec2(cloudShadowRes) / vec2(textureSize(cloudShadowMap, 0));

    if (clamp01(cloudShadowPos) != cloudShadowPos) {
        return 1.0;
    }

    // fade out cloud shadows when:
    //  - the fragment is above the cloud layer
    //  - the sun is near the horizon
    float r = planetRadius
        + (scenePos.y + eyeAltitude - 63.0) * cloudsScale;
    float altitudeFraction
        = linearStep(cloudsCumulusRadius, cloudsCumulusTopRadius, r);
    float cloudShadowFade = smoothstep(0.05, 0.15, lightDir.y)
        * clamp01(1.0 - altitudeFraction);

    float cloudShadow = bicubicFilter(cloudShadowMap, cloudShadowPos).x;
    cloudShadow = cloudShadow * cloudShadowFade + (1.0 - cloudShadowFade);

    return cloudShadow * cloudShadowsIntensity
        + (1.0 - cloudShadowsIntensity);
#endif
}

#if defined PROGRAM_PREPARE && defined cloudShadows
#include "/lib/atmos/clouds/altocumulus.glsl"
#include "/lib/atmos/clouds/cirrus.glsl"
#include "/lib/atmos/clouds/cumulus.glsl"
#include "/lib/atmos/clouds/cumulusCongestus.glsl"

vec2 renderCloudShadowMap(vec2 uv) {
    // Transform position from scene-space to clouds-space
    vec3 rayOrigin = unprojectCloudShadowMap(uv);
    rayOrigin = vec3(rayOrigin.xz, rayOrigin.y + eyeAltitude - 63.0).xzy
            * cloudsScale
        + vec3(0.0, planetRadius, 0.0);

    vec3 pos;
    float t, density, extinctionCoeff;
    float shadowVis = 1.0;
    float shadowCumulusOnly = 1.0;
    float distanceFade;
    float distanceFadeStrength = 0.00000001 * pulse(lightDir.y, -0.01, 0.2);

#ifdef cloudsCumulus
    extinctionCoeff = 0.25 * cloudsParams.l0ExtinctionCoeff;
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsCumulusRadius + 0.25 * cumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * cumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
    shadowCumulusOnly = shadowVis;
#endif

#ifdef cloudsAltocumulus
    extinctionCoeff = mix(0.05, 0.1, dayFactor) * cloudsAltocumulusDensity
        * (1.0 - 0.33 * rainStrength);
    t = intersectSphere(
            rayOrigin,
            lightDir,
            cloudsAltocumulusRadius + 0.5 * altocumulusLayerThickness
    )
            .y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = altocumulusDensityProfile(pos);
    shadowVis *= exp(
        -1.00 * distanceFade * extinctionCoeff * altocumulusLayerThickness
        * rcp(abs(lightDir.y) + eps) * density
    );
#endif

#ifdef cloudsCirrus
    t = intersectSphere(rayOrigin, lightDir, cloudsCirrusRadius).y;
    pos = rayOrigin + lightDir * t;
    distanceFade = exp2(-distanceFadeStrength * length(pos.xy));
    density = cirrusDensityProfile(pos.xz, 0.5);
    shadowVis *= exp(-1.00 * distanceFade * cloudsCirrusExtinctionCoeff
                  * cirrusLayerThickness * rcp(abs(lightDir.y) + eps)
                  * density)
            * 0.5
        + 0.5;
#endif

    return vec2(shadowVis, shadowCumulusOnly);
}
#endif
#endif // INCLUDE_LIGHT_CLOUD_SHADOWS
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS
#include "/lib/light/direct/distortion.glsl"
#include "/lib/util/lodMod.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/encode.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/atmos/projection.glsl"


// Resolution bookkeeping


// ----------------------------------------------------------------------------
/* DITHER */
// ----------------------------------------------------------------------------
// (hash22 below is the only dither hash used.)

#define HASHSCALE3 vec3(0.1031, 0.1030, 0.0973)
vec2 hash22(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ----------------------------------------------------------------------------
/* COSINE HEMISPHERE SAMPLING */
// ----------------------------------------------------------------------------

vec3 genUnitVector(vec2 p) {
    p.x *= tau; p.y = p.y * 2.0 - 1.0;
    return vec3(cos(p.x) * sqrt(1.0 - p.y * p.y),
                sin(p.x) * sqrt(1.0 - p.y * p.y),
                p.y);
}

// Lambertian BRDF sampling without a tangent frame (Malley's method).

// http://www.amietia.com/lambertnotangent.html
vec3 cosineVector(vec3 vector, vec2 xy) {
    vec3 sampleLobe = vector + genUnitVector(xy);
    float lenSq = dot(sampleLobe, sampleLobe);
    return lenSq > 0.0 ? sampleLobe * inversesqrt(lenSq) : vector;
}

// ----------------------------------------------------------------------------
/* SCREENSPACE RAYTRACER */


vec3 rayHit(vec3 screenPos) {
    float depthSample = texelFetch(
        TRACE_DEPTH,
        ivec2(screenPos.xy * viewRes * taauViewportScale),
        0
    ).x;

    if (depthSample >= screenPos.z) return vec3(1.1); // no occlusion yet

    float hitViewDepth = screenToViewSpaceDepth(TRACE_PROJ_INV, depthSample);
    float rayViewDepth = screenToViewSpaceDepth(TRACE_PROJ_INV, screenPos.z);

    float dist = abs(hitViewDepth - rayViewDepth) / max(abs(rayViewDepth), 1e-6);

    return dist <= 0.1 ? vec3(screenPos.xy, depthSample) : vec3(1.1);
}

#ifdef ssptFullRangeRT
//  Works fully in screenspace. Potentially every pixel can be hit. Needs a
//  lot more iterations for results of similar quality.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint maxSteps = 16;

    float rayLength = ((position.z + direction.z * far * sqrt(3.0)) > -sqrt(3.0) * near)
                      ? (-sqrt(3.0) * near - position.z) / direction.z : far * sqrt(3.0);

    vec3 screenPosition = viewToScreenSpace(TRACE_PROJ, position, true);
    vec3 endPosition = position + direction * rayLength;
    vec3 endScreenPosition = viewToScreenSpace(TRACE_PROJ, endPosition, true);

    vec3 screenDirection = normalize(endScreenPosition - screenPosition);
        screenDirection.xy = normalize(screenDirection.xy);

    vec3 maxLength = (step(0.0, screenDirection) - screenPosition) / screenDirection;
    float stepMult = minOf(maxLength);
    vec3 screenVector = screenDirection * stepMult / float(maxSteps);

    vec3 screenPos = screenPosition
        + screenDirection * maxOf(viewPixelSize * pi);

    if (clamp01(screenPos.xy) == screenPos.xy) {
        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;
    }

        screenPos += screenVector * noise;

    for (uint i = 0; i < maxSteps; ++i) {
        if (clamp01(screenPos.xy) != screenPos.xy) break;

        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;

        screenPos += screenVector;
    }

    return vec3(1.1);
}
#else
//  Short range variant (default). Traces a bounded view-space
//  distance and rescales the step vector so the ray ends on-screen.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint maxSteps = 10;
    const float stepSize = tau / float(maxSteps);

    vec3 stepVector = direction * stepSize;

    vec3 endPosition = position + stepVector * float(maxSteps);
    vec3 endScreenPosition = viewToScreenSpace(TRACE_PROJ, endPosition, true);

    vec2 maxPosXy = max(abs(endScreenPosition.xy * 2.0 - 1.0), vec2(1.0));
    float stepMult = minOf(rcp(maxPosXy));
        stepVector *= stepMult;

    // closest texel iteration
    vec3 samplePos = position;

        samplePos += stepVector / 6.0;
    vec3 screenPos = viewToScreenSpace(TRACE_PROJ, samplePos, true);

    if (clamp01(screenPos.xy) == screenPos.xy) {
        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;
    }

        samplePos += stepVector * noise;

    for (uint i = 0; i < maxSteps; ++i) {
        vec3 screenPos = viewToScreenSpace(TRACE_PROJ, samplePos, true);
            samplePos += stepVector;
        if (clamp01(screenPos.xy) != screenPos.xy) break;

        vec3 hit = rayHit(screenPos);
        if (hit.z < 1.0) return hit;
    }

    return vec3(1.1);
}
#endif

// ----------------------------------------------------------------------------
/* HIT SURFACE DATA — Luster-main gbuffer unpack (kept for the bounce path) */


struct HitData {
    vec3 albedo;
    vec3 sceneNormal;
    vec2 lightLevels;
    uint mask;
};

HitData unpackHit(vec4 gbufferData) {
    HitData hit;

    hit.albedo = vec3(
        unpackUnorm2x8(gbufferData.x),
        unpackUnorm2x8(gbufferData.y).x
    );
    hit.mask = uint(255.0 * unpackUnorm2x8(gbufferData.y).y);
    hit.sceneNormal = decodeUnitVector(unpackUnorm2x8(gbufferData.z));
    hit.lightLevels = unpackUnorm2x8(gbufferData.w);

    return hit;
}

// ----------------------------------------------------------------------------
/* HIT SURFACE EMISSION — baked radiance fetch */


// Emission radiance is baked into colortex22 by the gbuffer writers from
// the same material decode the direct path uses: tier-scaled hardcoded
// emitters, the chroma-boosted color path, and the labPBR map path curved
// by labEmissionCurve, all selected by ssptEmissionMode at bake time.
// The fetch is patch-weighted: sampling at a mip level matched to the
// travelled ray distance returns the average radiance of the hit's
// screen-space neighborhood instead of one point texel. A point fetch feeds
// a pixel the full emitter radiance only when one of the few rays per frame
// clips the emitter patch, reading as blinking speckle on the surfaces the
// emitter lights; patch-averaged radiance keeps that contribution continuous
// in ray count. Requires colortex22MipmapEnabled in shaders.properties.
vec3 hitEmission(ivec2 hitTexel, float hitDistance) {
    float mip = log2(clamp(hitDistance, 1.0, 16.0));

    return textureLod(
        colortex22,
        (vec2(hitTexel) + 0.5) / vec2(textureSize(colortex22, 0)),
        mip
    ).rgb;
}

// ----------------------------------------------------------------------------
/* HIT DIRECT LIGHT — sun/moon + handheld bounce */

//  Shadowed sun/moon light at the traced hit, tinted by the hit albedo (one


//  falloff/color of the primary pass. Skylight stays out (owned by the
//  traced sky / bent-cone ambient, never by the bounce itself).


#if defined shadow && !defined WORLD_NETHER
#define DIRECT_SUN_BOUNCE 1
#endif
#define DIRECT_HANDHELD_BOUNCE 1


#define DIRECT_SKY_BOUNCE 1

vec3 tracedWaterAttenuation(vec3 viewPos, vec3 hitViewPos) {
    if (isEyeInWater != 1) return vec3(1.0);
    const vec3 absorptionCoeff
        = vec3(
              waterAbsorptionRUnderwater,
              waterAbsorptionGUnderwater,
              waterAbsorptionBUnderwater
          )
        * rec709ToWorkingColor;
    return exp(-absorptionCoeff * distance(hitViewPos, viewPos));
}

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE


#ifdef DIRECT_SUN_BOUNCE
vec3 sunRadiance() {
    float blueHour = linearStep(0.05, 1.0, exp(-190.0 * sqr(sunDir.y + 0.09604)));
    float exposure = 7.0 * sunI
                   * (1.0 + 0.5 * (timeSunset + timeSunrise) + 40.0 * blueHour);

    vec3 tint = mix(
        vec3(1.0),
        vec3(1.05, 0.84, 0.93) * 1.2,
        sqr(pulse(sunDir.y, 0.17, 0.40))
    );
    tint *= mix(vec3(1.0), vec3(0.95, 0.80, 1.0), blueHour);

    vec3 userTint = mix(
        fromDisplay(vec3(sunNr, sunNg, sunNb)),
        fromDisplay(vec3(sunMr, sunMg, sunMb)),
        timeSunrise
    );
    userTint = mix(userTint, fromDisplay(vec3(sunEr, sunEg, sunEb)), timeSunset);

    return exposure * tint * userTint;
}

// Moon radiance. Moon-phase albedo influence is intentionally not applied:
// the bounce uses the raw moon color.
vec3 moonRadiance() {
    float nightBoost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sunDir.y, 0.1)));
    float exposure = 0.66 * moonI * moonPhaseBrightness * nightBoost;
    return exposure * fromDisplay(vec3(moonR, moonG, moonB));
}
#endif // DIRECT_SUN_BOUNCE

vec3 hitDirectLight(HitData hit, vec3 hitViewPos) {
    vec3 hitScenePos = viewToSceneSpace(hitViewPos);
    vec3 sunMoonDirect = vec3(0.0);
    vec3 indirectDirect = vec3(0.0);

#ifdef DIRECT_SUN_BOUNCE


    vec3 lightDirWorld = sunAngle < 0.5 ? sunDir : moonDir;

    float NoL = dot(hit.sceneNormal, lightDirWorld);
    if (NoL > 0.0) {
        vec3 bias = getShadowBias(hitScenePos, hit.sceneNormal, NoL, hit.lightLevels.y);
        vec3 shadowViewPos = transform(shadowModelView, hitScenePos + bias);
        vec3 shadowClipPos = projectOrtho(shadowProjection, shadowViewPos);
        vec3 shadowCoords = distortShadowSpace(shadowClipPos) * 0.5 + 0.5;

        bool outsideShadowMap = any(lessThan(shadowCoords, vec3(0.0)))
                               || any(greaterThan(shadowCoords, vec3(1.0)));

        float visibility = outsideShadowMap ? 1.0 : texture(shadowtex1, shadowCoords);
        if (visibility > 0.0) {
            vec3 radiance = sunAngle < 0.5 ? sunRadiance() : moonRadiance();
            sunMoonDirect = radiance * (visibility * NoL);

#ifdef shadowColor
            if (!outsideShadowMap) {
                // Sunlight passing through stained glass picks up the glass tint.
                ivec2 shadowTexel = ivec2(shadowCoords.xy * vec2(textureSize(shadowtex0, 0)));
                float blockerDepth = texelFetch(shadowtex0, shadowTexel, 0).x;
                vec3 transmission = texelFetch(shadowcolor0, shadowTexel, 0).rgb;
                sunMoonDirect *= mix(vec3(1.0), 4.0 * transmission, step(blockerDepth, shadowCoords.z));
            }
#endif

#if defined WORLD_OVERWORLD && defined cloudShadows
            sunMoonDirect *= getCloudShadows(colortex8, hitScenePos);
#endif
        }
    }
#endif // DIRECT_SUN_BOUNCE

#ifdef DIRECT_SKY_BOUNCE


    vec3 skyRadiance = texture(colortex4, projectSky(hit.sceneNormal)).rgb;
    indirectDirect += skyRadiance * hit.lightLevels.y;
#endif // DIRECT_SKY_BOUNCE

#ifdef DIRECT_HANDHELD_BOUNCE


    indirectDirect += getHandheldLight(hitScenePos, 1.0);
#endif


    return hit.albedo * (sunMoonDirect + indirectDirect) * indirectLightScale;
}

#endif // defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE

// ----------------------------------------------------------------------------
/* HAMMON DIFFUSE BRDF */
// ----------------------------------------------------------------------------

#include "/lib/brdf/hammon.glsl"


// INDIRECT TRACER


//  and is tinted by the hit albedo inside hitDirectLight. Multibounce


vec3 traceIndirect(
    vec3 viewPos,
    vec3 sceneNormal,
    vec2 dither,
    bool hand,
    float contactAo,
    float skyOcclusion,
    vec3 bentNormalScene,
    out bool geometryHit
) {
    vec3 viewNormal = mat3(gbufferModelView) * sceneNormal;

    vec3 emission = vec3(0.0);
    vec3 skylight = vec3(0.0);
    geometryHit = false;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    vec3 bounce = vec3(0.0);
    // Candidate count for bounce normalization: bounce averages over
    // candidates like emission does, not over hits.
    float bounceSamples = 0.0;
#endif

    // R2-sequence constants: 1/rho and 1/rho^2 (plastic constant)
    const float a1 = 1.0 / 1.3247179572447460;
    const float a2 = a1 * a1;

    #if ssptBounces <= 1

    /* ------ SINGLE BOUNCE ------ */
    //  Every candidate is a cosine-lobe ray, stratified over pixel +
    //  frame + candidate index so temporal accumulation blends them.

    vec2 quasirandomCurr = 0.5 + fract(vec2(a1, a2) * float(frameCounter) + 0.5);

    vec2 noiseCurr = hash22(gl_FragCoord.xy + float(frameCounter));

    for (uint i = 0; i < ssptSPP; ++i) {
        ++quasirandomCurr;
        noiseCurr += hash22(
            vec2(gl_FragCoord.xy + vec2(cos(quasirandomCurr.x), sin(quasirandomCurr.y)))
        );

        vec2 vectorXy = fract(sqrt(2.0) * quasirandomCurr + noiseCurr);


        bounceSamples += 1.0;

        vec3 rayDirection = cosineVector(sceneNormal, vectorXy);
            rayDirection = normalize(mat3(gbufferModelView) * rayDirection);

        if (dot(viewNormal, rayDirection) < 0.0) rayDirection = -rayDirection;

        float brdf = brdfWeight(viewNormal, -normalize(viewPos), rayDirection);

        vec3 hitPosition = screenspaceRT(viewPos, rayDirection, dither.y);

        if (hitPosition.z < 1.0) {
            geometryHit = true;
            ivec2 hitTexel = ivec2(hitPosition.xy * viewRes * taauViewportScale);
            vec4 hitData0 = texelFetch(colortex1, hitTexel, 0);

            vec3 hitViewPos = screenToViewSpace(TRACE_PROJ_INV, hitPosition, true);
            vec3 hitAttenuation = tracedWaterAttenuation(viewPos, hitViewPos);

            // Cubic emission distance falloff.
            float emissionFalloff = 1.0 - linearStep(
                ssptEmissionDistance * rcpPi,
                ssptEmissionDistance,
                distance(hitViewPos, viewPos)
            );
                emissionFalloff = cube(emissionFalloff);

            // Emission is radiance: no BRDF weighting, so emitters stay
            // bright at grazing hits and keep the baked magnitude.
            emission += hitEmission(hitTexel, distance(hitViewPos, viewPos))
                      * emissionFalloff * hitAttenuation;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
            // Direct-light bounce: no distance falloff, BRDF-weighted.
            // (Counted per cosine candidate above, not per hit.)
            bounce += hitDirectLight(unpackHit(hitData0), hitViewPos)
                    * brdf * hitAttenuation;
#endif
        } else {
            // Ray escaped to sky — sample sky map in the escaped direction.
            // This replaces the flat ambient term for SSPT-enabled pixels.
            vec3 worldDir = mat3(gbufferModelViewInverse) * rayDirection;
            float groundOcclusion = exp(-max0(-worldDir.y) * sqrPi);
            vec3 escapedSky = texture(colortex4, projectSky(worldDir)).rgb
                * cube(skyOcclusion) * groundOcclusion;
            skylight += escapedSky * brdf;
        }
    }

    #else

    /* ------ MULTIBOUNCE (ssptBounces > 1) ------ */


    //  Sky escapes end the chain.

    for (uint i = 0; i < ssptSPP; ++i) {
        int frameCounterNew = frameCounter + int(i) * 31;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
        // Multibounce samples are all cosine-lobe: count every sample so
        // the shared normalization below reproduces the old average.
        bounceSamples += 1.0;
#endif

        vec2 quasirandomCurr = 0.5 + fract(vec2(a1, a2) * float(frameCounterNew) + 0.5);

        vec2 noiseCurr = hash22(gl_FragCoord.xy + float(frameCounterNew));

        vec3 contribution = vec3(1.0);

        // Initialized so that -oldDirection is the surface-to-eye direction
        // on the first bounce, matching the single-bounce path's brdfWeight
        // argument convention.
        vec3 rayDirection = normalize(viewPos);

        vec3 hitNormal = viewNormal;
        vec3 hitNormalScene = sceneNormal;
        vec3 rayOrigin = viewPos;

        for (uint n = 0; n < ssptBounces; ++n) {
            ++quasirandomCurr;
            noiseCurr += hash22(
                vec2(gl_FragCoord.xy + vec2(cos(quasirandomCurr.x), sin(quasirandomCurr.y)))
            );

            vec2 vectorXy = fract(sqrt(2.0) * quasirandomCurr + noiseCurr);

            vec3 oldDirection = rayDirection;

                rayDirection = cosineVector(hitNormalScene, vectorXy);
                rayDirection = normalize(mat3(gbufferModelView) * rayDirection);

            if (dot(hitNormal, rayDirection) < 0.0) rayDirection = -rayDirection;

            vec3 hitPosition = screenspaceRT(rayOrigin, rayDirection, dither.y);

            float brdf = brdfWeight(hitNormal, -oldDirection, rayDirection);
            // Emission gathers radiance, so it skips the BRDF weight; the
            // bounce term below keeps the full path throughput.
            vec3 preBrdfThroughput = contribution;
                contribution *= brdf;

            if (hitPosition.z < 1.0) {
                geometryHit = true;
                ivec2 hitTexel = ivec2(hitPosition.xy * viewRes * taauViewportScale);
                vec4 hitData0 = texelFetch(colortex1, hitTexel, 0);

                vec3 hitAlbedo = vec3(
                    unpackUnorm2x8(hitData0.x),
                    unpackUnorm2x8(hitData0.y).x
                );
                hitNormalScene = decodeUnitVector(unpackUnorm2x8(hitData0.z));
                hitNormal = mat3(gbufferModelView) * hitNormalScene;

                vec3 hitViewPos = screenToViewSpace(TRACE_PROJ_INV, hitPosition, true);
                vec3 hitAttenuation = tracedWaterAttenuation(viewPos, hitViewPos);

                // Deeper bounces continue from the hit surface, not the
                // shaded point.
                rayOrigin = hitViewPos;

                float emissionFalloff = 1.0 - linearStep(
                    ssptEmissionDistance * rcpPi,
                    ssptEmissionDistance,
                    distance(hitViewPos, viewPos)
                );
                    emissionFalloff = cube(emissionFalloff);

                emission += hitEmission(hitTexel, distance(hitViewPos, viewPos))
                          * emissionFalloff * preBrdfThroughput
                          * hitAttenuation;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
                // Direct-light bounce on every path vertex.
                bounce += hitDirectLight(unpackHit(hitData0), hitViewPos)
                        * contribution * hitAttenuation;
#endif

                contribution *= hitAlbedo; // colored bleed into deeper bounces
            } else {
                // Ray escaped to sky — sample sky map in the escaped direction.
                vec3 worldDir = mat3(gbufferModelViewInverse) * rayDirection;
                float groundOcclusion = exp(-max0(-worldDir.y) * sqrPi);
                vec3 escapedSky = texture(colortex4, projectSky(worldDir)).rgb
                    * cube(skyOcclusion) * groundOcclusion;
                skylight += escapedSky * contribution;
                break;
            }
        }
    }

    #endif

    emission /= float(ssptSPP);
    skylight /= float(ssptSPP);


    float emissionLuma = dot(max0(emission), luminanceWeights);
    emission = mix(vec3(emissionLuma), emission, 1.4);

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    // Bounce averages over candidates, matching emission's normalization.
    if (bounceSamples > 0.5) bounce /= bounceSamples;
    // Finish traced bounced lighting with the selected screen-space AO.
    // Keep material emission unoccluded so emitters do not lose radiance.
    bounce *= clamp01(contactAo);
#endif

    emission *= float(!hand); // hand geometry gets no emission

    // Pure-ambient pixels (every ray escaped): blend the single-sample sky
    // estimate toward a bent-normal sky lookup. The bent normal approximates
    // the cosine-weighted mean open direction, so this halves directional
    // noise at low SPP without biasing pixels where bounce geometry was hit.
    if (!geometryHit) {
        vec3 bentSky = texture(colortex4, projectSky(bentNormalScene)).rgb
            * cube(skyOcclusion)
            * exp(-max0(-bentNormalScene.y) * sqrPi);
        skylight = mix(skylight, bentSky, 0.5);
    }

    skylight *= indirectLightScale;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    return emission + bounce + skylight;
#else
    return emission + skylight;
#endif
}

#endif // INCLUDE_LIGHT_INDIRECT_LIGHT_SSPT
#include "/lib/util/encode.glsl"
#include "/lib/util/spaceConversion.glsl"

#include "/program/deferred/sspt/indirectAO.glsl"

// ------------
//   Main
// ------------

void main() {
    // This pass renders at the selected SSPT buffer resolution; gl_FragCoord is
    // in buffer texels while uv spans the whole screen.
    ivec2 gbufferTexel = ivec2(uv * viewRes * taauViewportScale);

    // initialize outputs before any early return (sky = vec4(0.0),
    // filter gbuffer = (0,0,1)*0.5+0.5 packed + depth 1)
    indirect = vec4(0.0);
    filterData = vec4(0.5, 0.5, 1.0, 1.0);

    if (clamp(gbufferTexel, ivec2(0), ivec2(viewRes) - 1) != gbufferTexel) {
        return;
    }

    float depth = texelFetch(combinedDepthTex, gbufferTexel, 0).x;

    if (depth >= 1.0) {
        return;
    }

    bool isHand = depth < handDepth;

    vec3 screenPos = vec3(uv, depth);
    vec3 viewPos = screenToViewSpace(
        combinedProjectionMatrixInverse,
        screenPos,
        true
    );

    // ---- gbuffer unpack (same packing as d4DeferredShading) ----

    vec4 gbufferData0 = texelFetch(colortex1, gbufferTexel, 0);

    vec3 flatNormal = decodeUnitVector(unpackUnorm2x8(gbufferData0.z));
    vec3 viewNormal = mat3(gbufferModelView) * flatNormal;
    float skyOcclusion = unpackUnorm2x8(gbufferData0.w).y;

    // ---- filter gbuffer side-data ----


    filterData = vec4(
        viewNormal * 0.5 + 0.5,
        sqrt(clamp01(-viewPos.z / far))
    );

    // ---- trace ----
    // Hash dithers, consumed as the screenspace-RT march noise by traceIndirect.

    vec2 dither = vec2(
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b,
        texelFetch(noisetex, (ivec2(gl_FragCoord.xy) + 249) & 511, 0).b
    );

    // Emission + sun/moon + handheld bounce.


    // AO is already temporally stabilized by deferred3. Its selected scalar
    // visibility is applied to traced bounce lighting, not to emission.
    // DSSAO and DGTAO share this scalar finishing path; the bent normal
    // steers directional sky here and in the shading pass.
    float linZ = screenToViewSpaceDepth(
        combinedProjectionMatrixInverse,
        depth
    );
    float contactAo = fetchFinishingAo(colortex6, colortex14, uv, linZ, isHand);

    // Bent normal from deferred3 (view space), steering the pure-ambient
    // sky estimate in traceIndirect. Degenerate directions fall back to the
    // flat normal.
    vec3 bentNormalScene
        = mat3(gbufferModelViewInverse) * fetchBentNormalView(colortex6, uv);
    if (dot(bentNormalScene, flatNormal) < eps) {
        bentNormalScene = flatNormal;
    }

    bool geometryHit;
    vec3 indirectLight = traceIndirect(
        viewPos,
        flatNormal,
        dither,
        isHand,
        contactAo,
        skyOcclusion,
        bentNormalScene,
        geometryHit
    );


    indirect = vec4(indirectLight, float(geometryHit));
}
