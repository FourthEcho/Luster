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

#if !defined INCLUDE_LIGHT_BSDF_SPECULAR_LIGHT
#define INCLUDE_LIGHT_BSDF_SPECULAR_LIGHT

#include "/lib/brdf/fresnel.glsl"
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/util/lodMod.glsl"
#include "/lib/util/geometry.glsl"
#include "/lib/atmos/projection.glsl"
#include "/lib/brdf/material.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

#if defined WORLD_OVERWORLD
#include "/lib/atmos/air/overworld/analytic.glsl"
#endif

// Microfacet distribution & geometry (GGX/Smith). Kept with the specular
// https://www.gdcvault.com/play/1024478/PBR-Diffuse-Lighting-for-GGX
float distributionGgx(float NoH_sq, float alphaSq) {
    // Clamp: a perfect mirror (alpha = 0) gives 0/0 = NaN at NoH = 1
    alphaSq = max(alphaSq, 1e-6);
    return alphaSq / (pi * sqr(1.0 - NoH_sq + NoH_sq * alphaSq));
}

float v1SmithGgx(float cosTheta, float alphaSq) {
    return 1.0
        / (cosTheta
           + sqrt((-cosTheta * alphaSq + cosTheta) * cosTheta + alphaSq));
}

float v2SmithGgx(float NoL, float NoV, float alphaSq) {
    float ggxL = NoV * sqrt((-NoL * alphaSq + NoL) * NoL + alphaSq);
    float ggxV = NoL * sqrt((-NoV * alphaSq + NoV) * NoV + alphaSq);
    return 0.5 / (ggxL + ggxV);
}

#if defined SSRT_LOD
#define SSRT_DEPTH_SAMPLER lodDepthTexShading
#define SSRT_PROJECTION_MATRIX lodProjectionMatrix
#define SSRT_PROJECTION_MATRIX_INVERSE lodProjectionMatrixInverse
#else
#define SSRT_DEPTH_SAMPLER combinedDepthTex
#define SSRT_PROJECTION_MATRIX combinedProjectionMatrix
#define SSRT_PROJECTION_MATRIX_INVERSE combinedProjectionMatrixInverse
#endif

bool raymarchDepthBuffer(
    vec3 screenPos,
    vec3 viewPos,
    vec3 viewDir,
    float dither,
    uint intersectionStepCount,
    uint refinementStepCount,
    out vec3 rayPos
) {
    if (viewDir.z > 0.0 && viewDir.z >= -viewPos.z) {
        return false;
    }

    vec3 screenDir = normalize(
        viewToScreenSpace(SSRT_PROJECTION_MATRIX, viewPos + viewDir, true)
        - screenPos
    );

    float rayLength = minOf(
        abs(sign(screenDir) - screenPos) / max(abs(screenDir), eps)
    );

    float stepLength = rayLength * rcp(float(intersectionStepCount));

    vec3 rayStep = screenDir * stepLength;
    rayPos
        = screenPos + dither * rayStep + length(viewPixelSize) * screenDir;

    float depthTolerance = max(
        abs(rayStep.z) * 3.0,
        0.02 / sqr(viewPos.z)
    ); // from DrDesten <3

    bool hit = false;

    // Intersection loop

    for (int i = 0; i < intersectionStepCount; ++i, rayPos += rayStep) {
#ifdef LOD_MOD_ACTIVE
        if (rayPos.z < 0.0) {
            continue;
        }
#endif
        if (clamp01(rayPos) != rayPos) {
            return false;
        }

        float depth = texelFetch(
                          SSRT_DEPTH_SAMPLER,
                          ivec2(rayPos.xy * viewRes * taauViewportScale),
                          0
        )
                          .x;

        if (depth < rayPos.z
            && abs(depthTolerance - (rayPos.z - depth)) < depthTolerance) {
            hit = true;
            break;
        }
    }

    if (!hit) {
        return false;
    }

    // Refinement loop

    float finalDepth;

    for (int i = 0; i < refinementStepCount; ++i) {
        rayStep *= 0.5;

        float depth = texelFetch(
                          SSRT_DEPTH_SAMPLER,
                          ivec2(rayPos.xy * viewRes * taauViewportScale),
                          0
        )
                          .x;

        if (depth < rayPos.z
            && abs(depthTolerance - (rayPos.z - depth)) < depthTolerance) {
            rayPos -= rayStep;
        } else {
            rayPos += rayStep;
        }

        finalDepth = depth;
    }

    // No intersection if the binary search landed on a sky pixel or a hand
    // pixel
    return handDepth < finalDepth && finalDepth < 1.0;
}

// ----------------------
//   Specular Highlight
// ----------------------

// GGX spherical area light approximation from Horizon: Zero Dawn
// https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa
float get_NoH_squared(float NoL, float NoV, float LoV, float lightRadius) {
    float radiusCos = cos(lightRadius);
    float radiusTan = tan(lightRadius);

    // Early out if R falls within the disc​
    float RoL = 2.0 * NoL * NoV - LoV;
    if (RoL >= radiusCos) {
        return 1.0;
    }

    float rOverLengthT
        = radiusCos * radiusTan * inversesqrt(1.0 - RoL * RoL);
    float notR = rOverLengthT * (NoV - RoL * NoL);
    float votR = rOverLengthT * (2.0 * NoV * NoV - 1.0 - RoL * LoV);

    // Calculate dot(cross(N, L), V). This could already be calculated and
    // available.​
    float triple = sqrt(
        clamp01(1.0 - NoL * NoL - NoV * NoV - LoV * LoV + 2.0 * NoL * NoV * LoV)
    );

    // Do one Newton iteration to improve the bent light Direction​
    float NoB_r = rOverLengthT * triple,
          VoB_r = rOverLengthT * (2.0 * triple * NoV);
    float NoL_vt_r = NoL * radiusCos + NoV + notR,
          LoV_vt_r = LoV * radiusCos + 1.0 + votR;
    float p = NoB_r * LoV_vt_r, q = NoL_vt_r * LoV_vt_r, s = VoB_r * NoL_vt_r;
    float xNum = q * (-0.5 * p + 0.25 * VoB_r * NoL_vt_r);
    float xDenom = p * p + s * ((s - 2.0 * p))
        + NoL_vt_r
            * ((NoL * radiusCos + NoV) * LoV_vt_r * LoV_vt_r
               + q * (-0.5 * (LoV_vt_r + LoV * radiusCos) - 0.5));
    float twoX1 = 2.0 * xNum / (xDenom * xDenom + xNum * xNum);
    float sinTheta = twoX1 * xDenom;
    float cosTheta = 1.0 - twoX1 * xNum;
    notR
        = cosTheta * notR + sinTheta * NoB_r; // use new T to update notR​
    votR
        = cosTheta * votR + sinTheta * VoB_r; // use new T to update votR​

    // Calculate (N.H)^2 based on the bent light direction​
    float new_NoL = NoL * radiusCos + notR;
    float new_LoV = LoV * radiusCos + votR;
    float NoH = NoV + new_NoL;
    float HoH = 2.0 * new_LoV + 2.0;

    return clamp01(NoH * NoH / HoH);
}

vec3 getSpecularHighlight(
    Material material,
    float NoL,
    float NoV,
    float NoH,
    float LoV,
    float LoH
) {
    const float specularMaxValue
        = 4.0; // Maximum value imposed on specular highlight to prevent it from
               // overloading bloom

#if defined WORLD_OVERWORLD
    const float sunAngularSizeRad = sunAngularRadius * degree;
    const float moonAngularSizeRad = moonAngularRadius * degree;
    float lightRadius
        = (sunAngle < 0.5) ? sunAngularSizeRad : moonAngularSizeRad;

    // No specular highlight on a new moon
    if (sunAngle > 0.5 && moonPhase == 4) {
        return vec3(0.0);
    }
#else
    const float lightRadius = sunAngularRadius * degree;
#endif

    vec3 fresnel;
    if (material.isHardcodedMetal) {
        fresnel = fresnelConductor(LoH, material.f0, material.f82);
    } else if (material.isMetal) {
        fresnel = fresnelSchlick(LoH, material.albedo);
    } else {
        fresnel = fresnelDielectric(LoH, material.f0.x);
    }

    if (NoL <= eps) {
        return vec3(0.0);
    }
    if (all(lessThan(fresnel, vec3(1e-2)))) {
        return vec3(0.0);
    }

    vec3 albedoTint
        = mix(vec3(1.0), material.albedo, float(material.isHardcodedMetal));

    float NoH_squared = get_NoH_squared(NoL, NoV, LoV, lightRadius);
    float alphaSquared = material.roughness * material.roughness;

    float d = distributionGgx(NoH_squared, alphaSquared);
    float v = v2SmithGgx(max(NoL, 1e-2), max(NoV, 1e-2), alphaSquared);

    return min((NoL * d * v) * fresnel * albedoTint, vec3(specularMaxValue));
}

// ------------------------
//   Specular Reflections
// ------------------------

vec3 sampleGgxVndf(vec3 viewerDir, vec2 alpha, vec2 hash) {
    /*
        // from https://jcgt.org/published/0007/04/01/paper.pdf: "Sampling the
    GGX distribution of visible normals"

        // Section 3.2: transforming the view direction to the hemisphere
    configuration viewerDir = normalize(vec3(alpha * viewerDir.xy,
    viewerDir.z));

        // Section 4.1: orthonormal basis (with special case if cross product is
    zero) float lenSq = lengthSquared(viewerDir.xy); vec3 T1 = (lenSq > 0) ?
    vec3(-viewerDir.y, viewerDir.x, 0) * inversesqrt(lenSq) : vec3(1.0, 0.0,
    0.0); vec3 T2 = cross(viewerDir, T1);

        // Section 4.2: parameterization of the projected area
        float r = sqrt(hash.x);
        float phi = 2.0 * pi * hash.y;
        float t1 = r * cos(phi);
        float t2 = r * sin(phi);
        float s = 0.5 + 0.5 * viewerDir.z;

        t2 = (1.0 - s) * sqrt(1.0 - t1 * t1) + s * t2;

        // Section 4.3: reprojection onto hemisphere
        vec3 normal = t1 * T1 + t2 * T2 + sqrt(max0(1.0 - t1 * t1 - t2 * t2)) *
    viewerDir;

        // Section 3.4: transforming the normal back to the ellipsoid
    configuration normal = normalize(vec3(alpha * normal.xy, max0(normal.z)));

        return normal;
    /*/
    // Improved GGX importance sampling function by zombye
    // https://ggx-research.github.io/publication/2023/06/09/publication-ggx.html

    // Transform viewer direction to the hemisphere configuration
    viewerDir = normalize(vec3(alpha * viewerDir.xy, viewerDir.z));

    // Sample a reflection direction off the hemisphere
    const float tau = 6.2831853; // 2 * pi
    float phi = tau * hash.x;
    float cosTheta = fma(1.0 - hash.y, 1.0 + viewerDir.z, -viewerDir.z);
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0));
    vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta);

    // Evaluate halfway direction
    // This gives the normal on the hemisphere
    vec3 halfway = reflected + viewerDir;

    // Transform the halfway direction back to hemiellispoid configuation
    // This gives the final sampled normal
    return normalize(vec3(alpha * halfway.xy, halfway.z));
    //*/
}

vec3 getSkyReflection(vec3 rayDir, float skylight, vec3 hitPos) {
#if defined WORLD_OVERWORLD
    bool hitSky
        = false; // clamp01(hitPos.xy) == hitPos.xy && hitPos.z >= 1.0;
    float skylightFalloff
        = hitSky ? 1.0 : pow12(linearStep(0.0, 0.75, skylight));
    vec3 reflection = bicubicFilter(colortex4, projectSky(rayDir)).rgb
        * skylightFalloff;
#else
    vec3 reflection = texture(colortex4, projectSky(rayDir)).rgb;
#endif

#ifdef moonPhaseReflections
    // Only shape the reflected sky's moon contribution at night
    if (sunAngle > 0.5) {
        reflection = applyMoonPhaseInfluence(
            reflection,
            moonPhaseReflectionsIntensity * moonPhaseInfluenceIntensity,
            1.00,
            1.00
        );
    }
#endif

    return reflection;
}

vec3 traceSpecularRay(
    vec3 screenPos,
    vec3 viewPos,
    vec3 worldPos,
    vec3 rayDir,
    float dither,
    float skylight,
    uint intersectionStepCount,
    uint refinementStepCount,
    int mipLevel
) {
    vec3 viewDir = mat3(gbufferModelView) * rayDir;

#ifdef environmentReflections
    vec3 hitPos;
    bool hit = raymarchDepthBuffer(
        screenPos,
        viewPos,
        viewDir,
        dither,
        intersectionStepCount,
        refinementStepCount,
        hitPos
    );
#else
    const bool hit = false;
    const vec3 hitPos = vec3(0.0);
#endif

#ifdef skyReflections
    vec3 skyReflection = getSkyReflection(rayDir, skylight, hitPos);
#else
    const vec3 skyReflection = vec3(0.0);
#endif

    if (hit) {
        float borderAttenuationFactor
            = mix(0.01, eps, pow4(clamp01(1.0 - gbufferModelViewInverse[2].y)));
        float borderAttenuation = (hitPos.x * hitPos.y - hitPos.x)
            * (hitPos.x * hitPos.y - hitPos.y);
        borderAttenuation = dampen(
            linearStep(0.0, borderAttenuationFactor, borderAttenuation)
        );

        vec3 hitPosView = screenToViewSpace(
            SSRT_PROJECTION_MATRIX_INVERSE,
            hitPos,
            false
        );
        vec3 hitPosScene = viewToSceneSpace(hitPosView);

        vec2 hitUvPrev
            = reprojectSceneSpace(hitPosScene, false, false).xy;
        if (clamp01(hitUvPrev) != hitUvPrev) {
            return skyReflection;
        }

        vec3 reflection = textureLod(colortex5, hitUvPrev, mipLevel).rgb;

        vec3 fogScatteringPrevious = texture(colortex7, hitUvPrev).rgb;

#if defined WORLD_OVERWORLD
#ifdef vl


        // the direction of the sun then the fog would be shadowed by the hit

        float fogShadow = hit ? 1.0 - sqr(max0(dot(lightDir, rayDir))) : 1.0;
#else
        const float fogShadow = 1.0;
#endif

        // Apply analytic fog in reflection
        mat2x3 analyticFog = airFogAnalytic(
            worldPos,
            hitPosScene + cameraPosition,
            false,
            eyeSkylight,
            fogShadow
        );

        reflection = max0(reflection - fogScatteringPrevious);
        reflection = reflection * analyticFog[1] + analyticFog[0];
#endif

        return mix(skyReflection, reflection, borderAttenuation);
    } else {
        // SSR miss falls back to sky.
        return skyReflection;
    }
}

vec3 getSpecularReflections(
    Material material,
    mat3 tbnMatrix,
    vec3 screenPos,
    vec3 viewPos,
    vec3 worldPos,
    vec3 normal,
    vec3 flatNormal,
    vec3 worldDir,
    vec3 tangentDir,
    float skylight,
    bool isWater
) {
    vec3 albedoTint
        = material.isHardcodedMetal ? material.albedo : vec3(1.0);

    float alphaSquared = material.roughness * material.roughness;
    float dither = r1(
        frameCounter,
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b
    );

#ifdef LOD_MOD_ACTIVE
    // Convert screen depth to combined depth
    screenPos = viewToScreenSpace(SSRT_PROJECTION_MATRIX, viewPos, true);
#endif

#if defined ssrRoughnessSupport && defined specularMapping
    if (!isWater) { // Rough reflection
        float mipLevel
            = min(8.0 * (1.0 - pow8(1.0 - material.roughness)), 5.0);

        vec3 reflection = vec3(0.0);

        for (int i = 0; i < ssrRayCount; ++i) {
            vec2 hash;
            hash.x = interleavedGradientNoise(
                gl_FragCoord.xy,
                frameCounter * ssrRayCount + i
            );
            hash.y = interleavedGradientNoise(
                gl_FragCoord.xy + vec2(97.0, 23.0),
                frameCounter * ssrRayCount + i
            );

            vec3 microfacetNormal = tbnMatrix
                * sampleGgxVndf(-tangentDir, vec2(material.roughness), hash);
            vec3 rayDir = reflect(worldDir, microfacetNormal);

            float NoL = dot(normal, rayDir);
            if (NoL < eps) {
                continue;
            }

            vec3 radiance = traceSpecularRay(
                screenPos,
                viewPos,
                worldPos,
                rayDir,
                dither,
                skylight,
                ssrIntersectionStepsRough,
                ssrRefinementSteps,
                int(mipLevel)
            );

            float NoV = max(1e-2, dot(flatNormal, -worldDir));
            float MoV = max(1e-2, dot(microfacetNormal, -worldDir));

            // Microfacet Fresnel takes V.H (MoV), not the geometric NoV
            vec3 fresnel;
            if (material.isHardcodedMetal) {
                fresnel = fresnelConductor(MoV, material.f0, material.f82);
            } else if (material.isMetal) {
                fresnel = fresnelSchlick(MoV, material.albedo);
            } else {
                fresnel = fresnelDielectric(MoV, material.f0.x);
            }

            float v1 = v1SmithGgx(NoV, alphaSquared);
            float v2 = v2SmithGgx(NoL, NoV, alphaSquared);

            reflection += radiance * fresnel * (2.0 * NoL * v2 / v1);
        }

        reflection *= albedoTint * rcp(float(ssrRayCount));
        if (any(isnan(reflection))) {
            reflection = vec3(0.0); // don't reflect NaNs
        }
        return reflection * material.ssrMultiplier;
    }
#else
    // Fade reflection when rough reflections are disabled
    if (material.roughness > 0.05) {
        material.f0 *= 1.0 - sqr(material.roughness);
        material.ssrMultiplier = sqr(1.0 - material.roughness);
    }
#endif

    // Mirror-like reflections

    vec3 rayDir = reflect(worldDir, normal);

    float NoL = dot(normal, rayDir);
    float NoV = clamp01(dot(normal, -worldDir));

    if (NoL < eps) {
        return vec3(0.0);
    }

    vec3 fresnel;
    if (material.isHardcodedMetal) {
        fresnel = fresnelConductor(NoV, material.f0, material.f82);
    } else if (material.isMetal) {
        fresnel = fresnelSchlick(NoV, material.albedo);
    } else {
        fresnel = fresnelDielectric(NoV, material.f0.x);
    }

    float v1 = v1SmithGgx(NoV, alphaSquared);
    float v2 = v2SmithGgx(NoL, NoV, alphaSquared);

    vec3 reflection = traceSpecularRay(
        screenPos,
        viewPos,
        worldPos,
        rayDir,
        dither,
        skylight,
        ssrIntersectionStepsSmooth,
        ssrRefinementSteps,
        0
    );
    reflection *= albedoTint * fresnel;

    if (any(isnan(reflection))) {
        reflection = vec3(0.0); // don't reflect NaNs
    }

    return reflection * material.ssrMultiplier;
}

#endif // INCLUDE_LIGHT_BSDF_SPECULAR_LIGHT
