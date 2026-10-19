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

#ifndef LUSTER_D4_PASS
#define LUSTER_D4_PASS 1
#endif

layout(location = 0) out vec3 fragmentColor;

#if LUSTER_D4_PASS == 1
#ifdef useSeparateEntityDraws
/* RENDERTARGETS: 0 */
#else
layout(location = 1) out vec4 colortex3Clear;
/* RENDERTARGETS: 0,3 */
#endif
#else
/* RENDERTARGETS: 0 */
#endif

in vec2 uv;

flat in vec3 ambientColor;
flat in vec3 lightColor;
#ifdef hBasisSkylight
flat in vec3 hSky[6];
#endif

#if defined WORLD_OVERWORLD
flat in vec3 sunColor;
flat in vec3 moonColor;

#include "/lib/atmos/air/overworld/params.glsl"
flat in OverworldFogParams fogParams;

flat in float rainbowAmount;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0; // skytextured output / previous pass output
uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex4; // sky map
uniform sampler2D colortex5; // scene history (used by SSR reflection reprojection)
uniform sampler2D colortex6; // ambient lighting data
uniform sampler2D colortex7; // fog scattering history (used by SSR reflection reprojection)
uniform sampler2D colortex11; // clouds history
uniform sampler2D colortex12; // clouds data
uniform sampler2D colortex14; // ambient lighting history data

#ifdef ssptEnabled
uniform sampler2D colortex17; // filtered SSPT emission (half res)
#endif

#ifndef useSeparateEntityDraws
uniform sampler2D colortex3; // OF damage overlay, armor glint
#endif

#if defined WORLD_OVERWORLD && defined galaxy
uniform sampler2D colortex13;

// Galaxy/LoD support can both declare colortex15
#ifndef LUSTER_COLORTEX15_DECLARED
#define LUSTER_COLORTEX15_DECLARED
uniform sampler2D colortex15;
#endif
#define galaxySampler colortex13
#endif

#ifdef cloudShadows
uniform sampler2D colortex8; // cloud shadow map
#endif

uniform sampler3D depthtex0; // atmosphere scattering LUT
uniform sampler2D depthtex1;

#ifdef blockyClouds
uniform sampler2D depthtex2; // minecraft cloud texture
#endif

#ifndef WORLD_NETHER
#ifdef shadow
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef shadowColor
uniform sampler2D shadowcolor0;
#endif
#endif
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float eyeAltitude;
uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;
uniform float rainStrength;
uniform float desertSandstormWeather;
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
uniform vec3 viewLightDir;

uniform vec2 viewRes;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform float biomeCave;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeSnowy;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float worldAge;
uniform float eyeSkylight;

/*
const bool colortex5MipmapEnabled = true;
const bool colortex11MipmapEnabled = true;
*/

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define TEMPORAL_REPROJECTION

#include "/lib/atmos/air/simple.glsl"
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
#include "/lib/brdf/common.glsl"
#include "/lib/light/common.glsl"
#include "/lib/light/pcss.glsl"
#if !defined INCLUDE_LIGHT_DIRECT_LIGHT_SSRT
#define INCLUDE_LIGHT_DIRECT_LIGHT_SSRT

#include "/lib/light/common.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/spaceConversion.glsl"

bool raymarchShadow(
    sampler2D depthSampler,
    mat4 projectionMatrix,
    mat4 projectionMatrixInverse,
    vec3 rayOriginScreen,
    vec3 rayOriginView,
    vec3 rayDirView,
    bool hasSss,
    float dither,
    out float sssDepth
) {
    const uint stepCount = uint(shadowSsrtSteps);
    const float stepRatio = 2.0; // geometric sample distribution
    const float zTolerance = 10.0; // assumed thickness in blocks

    vec3 rayDirScreen = normalize(
        viewToScreenSpace(
            projectionMatrix,
            rayOriginView + rayDirView,
            true
        )
        - rayOriginScreen
    );

    vec3 invDir = 1.0 / (rayDirScreen + vec3(1e-9));
    vec3 tToEdge = max(
        (vec3(0.0) - rayOriginScreen) * invDir,
        (vec3(1.0) - rayOriginScreen) * invDir
    );
    float rayLength = minOf(max(tToEdge, vec3(0.0)));
    rayLength = min(
        rayLength,
        max(0.1, exp(-max0(length(rayOriginView) * 0.025 - 1.0)))
    );

    const float initialStepScale = stepRatio == 1.0
        ? rcp(float(stepCount))
        : (stepRatio - 1.0) / (pow(stepRatio, float(stepCount)) - 1.0);
    float stepLength = rayLength * initialStepScale;

    vec3 rayPos = rayOriginScreen + length(viewPixelSize) * rayDirScreen;

    bool hit = false;
    bool hitAfterSss = false;
    bool sssRaymarch = hasSss;
    vec3 exitPos = rayOriginScreen;

    for (int i = 0; i < stepCount; ++i) {
        vec3 rayStep = rayDirScreen * stepLength;
        stepLength *= stepRatio;
        vec3 ditheredPos = rayPos + dither * rayStep;
        rayPos += rayStep;

#ifdef LOD_MOD_ACTIVE
        if (ditheredPos.z < 0.0) {
            continue;
        }
#endif
        if (clamp01(ditheredPos) != ditheredPos) {
            break;
        }

        float depth = texelFetch(
                          depthSampler,
                          ivec2(ditheredPos.xy * viewRes * taauViewportScale),
                          0
        )
                          .x;

        float zRay = screenToViewSpaceDepth(
            projectionMatrixInverse,
            ditheredPos.z
        );
        float zSample
            = screenToViewSpaceDepth(projectionMatrixInverse, depth);

        bool inside = depth != 0.0 && depth < ditheredPos.z
            && abs(zTolerance - (zRay - zSample)) < zTolerance;
        hit = inside || hit;

        if (sssRaymarch) {
            if (!inside) {
                exitPos = ditheredPos;
                sssRaymarch = false;
            }
        }

        else if (!sssRaymarch) {
            hitAfterSss = inside || hitAfterSss;
            if (hit) {
                break;
            }
        }
    }

    exitPos = screenToViewSpace(projectionMatrixInverse, exitPos, true);
    sssDepth = hitAfterSss ? -1.0
                              : max0(distance(rayOriginView, exitPos) * 0.2);

    return hit;
}

float getScreenSpaceShadows(
    vec2 positionScreenXy,
    vec3 positionView,
    float depth,
#ifdef LOD_MOD_ACTIVE
    float depthLod,
#endif
    float skylight,
    bool hasSss,
    inout float sssDepth
) {
    // Dithering for ray offset
    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);

    // Slightly randomise ray direction to create soft shadows
    vec2 hash = hash2(gl_FragCoord.xy);
    vec3 rayDir
        = normalize(viewLightDir + 0.03 * uniformSphereSample(hash));

#ifdef LOD_MOD_ACTIVE

    bool raymarchCombinedDepth = lengthSquared(positionView)
        < sqr(far + 64.0); // heuristic of 4 chunks overlap
    bool hit;

    /*
    #ifdef MC_GL_KHR_shader_subgroup
    // Using subgroup ops, we make sure that if any fragments in a warp are
    raymarching the
    // combined depth buffer, they all do, to avoid divergent branches.
    raymarchCombinedDepth = subgroupAny(raymarchCombinedDepth);
    #endif
    */

    if (raymarchCombinedDepth) {
        hit = raymarchShadow(
            combinedDepthTex,
            combinedProjectionMatrix,
            combinedProjectionMatrixInverse,
            vec3(positionScreenXy, depth),
            positionView,
            rayDir,
            hasSss,
            dither,
            sssDepth
        );
    } else {
        hit = raymarchShadow(
            lodDepthTex,
            lodProjectionMatrix,
            lodProjectionMatrixInverse,
            vec3(positionScreenXy, depthLod),
            screenToViewSpace(
                lodProjectionMatrixInverse,
                vec3(positionScreenXy, depthLod),
                true
            ),
            rayDir,
            hasSss,
            dither,
            sssDepth
        );
    }
#else
    bool hit = raymarchShadow(
        depthtex1,
        gbufferProjection,
        gbufferProjectionInverse,
        vec3(positionScreenXy, depth),
        positionView,
        viewLightDir,
        hasSss,
        dither,
        sssDepth
    );
#endif

    return float(!hit) * getLightmapLightLeakPrevention(skylight);
}

#endif // INCLUDE_LIGHTING_DIRECT_LIGHTING_SSRT

#include "/lib/brdf/specular.glsl"
#include "/lib/util/lodMod.glsl"
#if !defined INCLUDE_POST_PURKINJE_SHIFT
#define INCLUDE_POST_PURKINJE_SHIFT

// Purkinje effect: mesopic shift toward rod (scotopic) peak sensitivity.
// https://en.wikipedia.org/wiki/Purkinje_effect
vec3 purkinjeShiftTransform(vec3 rgb, vec2 lightLevels) {
#if !(defined purkinjeShift && defined WORLD_OVERWORLD)
    return rgb;
#else
    float purkinjeIntensity = 0.05 * purkinjeShiftIntensity;
    purkinjeIntensity = purkinjeIntensity
        - purkinjeIntensity * smoothstep(-0.12, -0.06, sunDir.y)
            * lightLevels.y; // No purkinje shift in daylight
    purkinjeIntensity *= clamp01(
        1.0 - lightLevels.x
    ); // Reduce purkinje intensity in blocklight
    purkinjeIntensity *= clamp01(
        0.3 + 0.7 * cube(max(lightLevels.y, eyeSkylight))
    ); // Reduce purkinje intensity underground

    if (purkinjeIntensity < eps) {
        return rgb;
    }

    const vec3 purkinjeTint = vec3(
        purkinjeShiftR,
        purkinjeShiftG,
        purkinjeShiftB
    ) * rec709ToWorkingColor;
    const vec3 rodResponse
        = vec3(7.15e-5, 4.81e-1, 3.28e-1) * rec709ToWorkingColor;

    vec3 xyz = rgb * workingToXyzColor;

    vec3 scotopicLuminance
        = xyz * (1.33 * (1.0 + (xyz.y + xyz.z) / xyz.x) - 1.68);

    float purkinje = dot(rodResponse, scotopicLuminance * xyzToWorkingColor);

    rgb = mix(
        rgb,
        purkinje * purkinjeTint,
        exp2(-rcp(purkinjeIntensity) * purkinje)
    );

    return max0(rgb);
#endif
}

#endif // INCLUDE_POST_PURKINJE_SHIFT
#include "/lib/atmos/sky.glsl"

#if !defined INCLUDE_SURFACE_EDGE_HIGHLIGHT
#define INCLUDE_SURFACE_EDGE_HIGHLIGHT

#include "/lib/util/encoding.glsl"
#include "/lib/util/spaceConversion.glsl"

// MC Dungeons-inspired edge highlight effect

bool hasEdgeHighlight(vec3 normal) {
    // Returns true for faces pointing along an axis
    return abs(dot(abs(normal), vec3(1.0)) - 1.0) < 0.1;
}

float edgeHighlightCheck(
    vec3 offset,
    vec3 centerPos,
    vec3 centerNormal,
    float centerDepth,
    float rcp_NoV,
    vec2 depthGradient
) {
    // Calculate sample position in screen space
    vec3 samplePos = sceneToViewSpace(centerPos + offset);
    samplePos
        = viewToScreenSpace(combinedProjectionMatrix, samplePos, true);

    // Sample depth and gbuffer data
    ivec2 texel = ivec2(samplePos.xy * viewRes * taauViewportScale);
    float sampleDepth = texelFetch(combinedDepthTex, texel, 0).x;
    float sampleData = texelFetch(colortex1, texel, 0).z;

    // Test for depth discontinuity
    sampleDepth = linearizeDepthFast(sampleDepth);
    float expectedDepth
        = centerDepth + dot(depthGradient, samplePos.xy - uv);
    float depthEdge = float(
        abs(sampleDepth - expectedDepth) > 0.25 * rcp_NoV
        && expectedDepth < sampleDepth
    );

    // Test for normal discontinuity
    vec3 sampleNormal = decodeUnitVector(unpackUnorm2x8(sampleData));
    float normalEdge = float(
        abs(dot(centerNormal, sampleNormal)) < 0.99
        && dot(sampleNormal, normalize(offset)) > 0.01
    );

    return (depthEdge + normalEdge) * float(clamp01(samplePos) == samplePos)
        * float(
               hasEdgeHighlight(sampleNormal) || centerDepth < sampleDepth
        );
}

float getEdgeHighlight(
    vec3 scenePos,
    vec3 worldNormal,
    float depth,
    uint materialMask
) {
    // Size of one block pixel in world-space
    const float pixelSize = rcp(edgeHighlightScale);

    // Calculate tangent and bitangent
    mat3 tbn = getTbnMatrix(worldNormal) * pixelSize;

    float depthLinear = linearizeDepthFast(depth);
    vec2 depthGradient = vec2(dFdx(depthLinear), dFdy(depthLinear));

    float rcp_NoV = abs(rcp(dot(normalize(scenePos), worldNormal)));

    // Check for an edge in 5 directions around the sample point
    float highlight = edgeHighlightCheck(
        tbn[0],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        -tbn[0],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        tbn[1],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        -tbn[1],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );
    highlight += edgeHighlightCheck(
        tbn[2],
        scenePos,
        worldNormal,
        depthLinear,
        rcp_NoV,
        depthGradient
    );

    return clamp01(float(hasEdgeHighlight(worldNormal)) * highlight);
}

#endif // INCLUDE_SURFACE_EDGE_HIGHLIGHT
#include "/lib/brdf/material.glsl"
#define LUSTER_INCLUDE_RAIN_PUDDLES
#include "/lib/surface/rain.glsl"
#undef LUSTER_INCLUDE_RAIN_PUDDLES
#include "/lib/util/bicubic.glsl"
#include "/lib/util/spaceConversion.glsl"

void bilateralUpscaleSample(
    sampler2D dataSampler,
    sampler2D depthSampler,
    ivec2 baseTexel,
    out vec4 data00,
    out vec4 data10,
    out vec4 data01,
    out vec4 data11,
    out float depth00,
    out float depth10,
    out float depth01,
    out float depth11
) {
    ivec2 p10 = baseTexel + ivec2(1, 0);
    ivec2 p01 = baseTexel + ivec2(0, 1);
    ivec2 p11 = baseTexel + ivec2(1, 1);

    data00 = texelFetch(dataSampler, baseTexel, 0);
    data10 = texelFetch(dataSampler, p10, 0);
    data01 = texelFetch(dataSampler, p01, 0);
    data11 = texelFetch(dataSampler, p11, 0);

    depth00 = texelFetch(depthSampler, baseTexel, 0).x;
    depth10 = texelFetch(depthSampler, p10, 0).x;
    depth01 = texelFetch(depthSampler, p01, 0).x;
    depth11 = texelFetch(depthSampler, p11, 0).x;
}

vec4 bilateralUpscaleResolve(
    vec4 data00,
    vec4 data10,
    vec4 data01,
    vec4 data11,
    float depth00,
    float depth10,
    float depth01,
    float depth11,
    vec2 f,
    mat4 projectionMatrixInverse,
    float currentLinZ,
    float depthWeightScale
) {
#define depthWeight(reversedDepth) \
    exp2( \
        -depthWeightScale \
        * abs( \
            screenToViewSpaceDepth( \
                projectionMatrixInverse, \
                1.0 - reversedDepth \
            ) \
            - currentLinZ \
        ) \
    )
    float w00 = depthWeight(depth00) * (1.0 - f.x) * (1.0 - f.y);
    float w10 = depthWeight(depth10) * (f.x - f.x * f.y);
    float w01 = depthWeight(depth01) * (f.y - f.x * f.y);
    float w11 = depthWeight(depth11) * (f.x * f.y);
#undef depthWeight

    float weightSum = w00 + w10 + w01 + w11;

    if (abs(weightSum) > eps) {
        return (data00 * w00 + data10 * w10 + data01 * w01 + data11 * w11)
            * rcp(weightSum);
    }

    return data00;
}
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"

#if defined WORLD_OVERWORLD
#include "/lib/atmos/clouds/utility/sampling.glsl"
#if defined blockyClouds
#if !defined INCLUDE_ATMOS_SKY_BLOCKY_CLOUDS
#define INCLUDE_ATMOS_SKY_BLOCKY_CLOUDS

#include "/lib/atmos/air/atmosphere.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

// Blocky volumetric clouds

const float blockyCloudsAltitudeL0 = blockyCloudsAltitude;
const float blockyCloudsAltitudeL1 = blockyCloudsAltitude2;
const float blockyCloudLayerThickness = blockyCloudsThickness;

float blockyCloudsExtinctionCoeff
    = mix(0.66, 1.0, smoothstep(0.0, 0.3, abs(sunDir.y)));
float blockyCloudsScatteringCoeff = blockyCloudsExtinctionCoeff;

float blockyCloudsPhaseSingle(
    float cosTheta
) { // Single scattering phase function
    return 0.7 * kleinNishinaPhase(cosTheta, 2600.0) // forwards lobe
        + 0.3 * henyeyGreensteinPhase(cosTheta, -0.2); // backwards lobe
}

float blockyCloudsPhaseMulti(
    float cosTheta,
    vec3 g
) { // Multiple scattering phase function
    return 0.65 * henyeyGreensteinPhase(cosTheta, g.x) // forwards lobe
        + 0.10 * henyeyGreensteinPhase(cosTheta, g.y) // forwards peak
        + 0.25 * henyeyGreensteinPhase(cosTheta, -g.z); // backwards lobe
}

float textureSoft(sampler2D sampler, vec2 coord, float softness) {
    vec2 res = vec2(textureSize(sampler, 0));

    coord = coord * res + 0.5;
    vec2 i, f = modf(coord, i);

    f = smoothstep(
        0.5 - softness,
        0.5 + softness,
        f
    ); // the closer the borders are to 0.5, the sharper the cloud edge
    coord = i * rcp(res) + rcp(res);

    vec4 samples = textureGather(sampler, coord, 3);
    vec4 weights = vec4(
        f.y - f.x * f.y,
        f.x * f.y,
        f.x - f.x * f.y,
        1.0 - f.x - f.y + f.x * f.y
    );

    return dot(samples, weights);
}

float blockyCloudDensityProfile(
    vec3 worldPos,
    float altitudeFraction,
    float layerOffset
) {
    const float windAngle = blockyCloudsWindAngle * degree;
    const vec2 windVelocity
        = blockyCloudsWindSpeed * vec2(cos(windAngle), sin(windAngle));

    const float roundness
        = 0.5 * blockyCloudsRoundness; // Controls the roundness of the clouds
    const float sharpness = 0.5
        * blockyCloudsSharpness; // Controls the sharpness of the cloud edges

    // Adjust position

    worldPos.xz = abs(worldPos.xz + 3000.0 + layerOffset);
    worldPos.xz += windVelocity * worldAge;

    // Minecraft cloud noise

    float density = textureSoft(
        depthtex2,
        worldPos.xz * rcp(blockyCloudsSize * 5000),
        roundness
    );

    // Adjust density
    density *= linearStep(0.0, roundness, altitudeFraction);
    density *= linearStep(0.0, roundness, 1.0 - altitudeFraction);
    density = linearStep(sharpness, 1.0 - sharpness, density);

    return clamp01(density) * blockyCloudsDensity;
}

float blockyCloudsOpticalDepth(
    vec3 rayOrigin,
    vec3 rayDir,
    float layerAltitude,
    float layerOffset,
    float dither,
    const uint stepCount
) {
    const float stepGrowth = 1.2;

    float stepLength = blockyCloudLayerThickness / float(stepCount); // m

    vec3 rayPos = rayOrigin;
    vec4 rayStep = vec4(rayDir, 1.0) * stepLength;

    float opticalDepth = 0.0;

    for (uint i = 0u; i < stepCount; ++i, rayPos += rayStep.xyz) {
        rayStep *= stepGrowth;
        vec3 worldPos = rayPos + rayStep.xyz * dither;
        float altitudeFraction = clamp01(
            (worldPos.y - layerAltitude) * rcp(blockyCloudLayerThickness)
        );

        opticalDepth
            += blockyCloudDensityProfile(worldPos, altitudeFraction, layerOffset)
            * rayStep.w;
    }

    return opticalDepth;
}

vec2 blockyCloudsScattering(
    float density,
    float lightOpticalDepth,
    float skyOpticalDepth,
    float groundOpticalDepth,
    float stepTransmittance,
    float cosTheta,
    float bouncedLight
) {
    vec2 scattering = vec2(0.0);

    float scatterAmount = blockyCloudsScatteringCoeff;
    float extinctAmount = blockyCloudsExtinctionCoeff;

    float powder = 5.0 * (1.0 - exp2(-8.0 * density));

    float scatteringIntegralTimesDensity
        = (1.0 - stepTransmittance) / blockyCloudsExtinctionCoeff;

    float phase = blockyCloudsPhaseSingle(cosTheta);
    vec3 phaseG = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + lightOpticalDepth));

    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatterAmount
            * exp(-extinctAmount * lightOpticalDepth) * phase;
        scattering.x += scatterAmount
            * exp(-extinctAmount * groundOpticalDepth) * isotropicPhase
            * bouncedLight;
        scattering.y += scatterAmount
            * exp(-extinctAmount * skyOpticalDepth) * isotropicPhase;

        scatterAmount *= 0.5;
        extinctAmount *= 0.5;
        phaseG *= 0.8;

        phase = blockyCloudsPhaseMulti(cosTheta, phaseG);
    }

    return scattering * scatteringIntegralTimesDensity * powder;
}

vec4 raymarchBlockyClouds(
    vec3 worldStartPos,
    vec3 worldEndPos,
    bool sky,
    float layerAltitude,
    float dither
) {
    const uint primarySteps = blockyCloudsPrimarySteps;
    const uint lightSteps = blockyCloudsLightSteps;
    const float maxRayLength = 512;
    const float minTransmittance = 0.075;

    // ---------------------
    //   Raymarching Setup
    // ---------------------

    vec3 worldDir = worldEndPos - worldStartPos;

    float lengthSq = lengthSquared(worldDir);
    float norm = inversesqrt(lengthSq);
    float rayLength = lengthSq * norm;
    worldDir *= norm;

    float distanceToLowerPlane
        = (layerAltitude - eyeAltitude) / worldDir.y;
    float distanceToUpperPlane
        = (layerAltitude + blockyCloudLayerThickness - eyeAltitude)
        / worldDir.y;
    float distanceToVolumeStart, distanceToVolumeEnd;

    if (eyeAltitude < layerAltitude) {
        // Below volume
        distanceToVolumeStart = distanceToLowerPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? -1.0 : distanceToUpperPlane;
    } else if (eyeAltitude < layerAltitude + blockyCloudLayerThickness) {
        // Inside volume
        distanceToVolumeStart = 0.0;
        distanceToVolumeEnd = worldDir.y < 0.0
            ? distanceToLowerPlane
            : distanceToUpperPlane;
    } else {
        // Above volume
        distanceToVolumeStart = distanceToUpperPlane;
        distanceToVolumeEnd
            = worldDir.y < 0.0 ? distanceToLowerPlane : -1.0;
    }

    if (distanceToVolumeEnd < 0.0) {
        return vec4(vec3(0.0), 1.0);
    }

    rayLength = sky ? distanceToVolumeEnd : rayLength;
    rayLength
        = clamp(rayLength - distanceToVolumeStart, 0.0, maxRayLength);

    float stepLength = rayLength * rcp(float(primarySteps));

    vec3 worldStep = worldDir * stepLength;
    vec3 worldPos = worldStartPos
        + worldDir * (distanceToVolumeStart + stepLength * dither);

    // ------------------
    //   Lighting Setup
    // ------------------

    vec3 scattering = vec3(0.0);
    float transmittance = 1.0;

    float lightDither
        = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);

    bool moonlit = sunDir.y < -0.06;

    vec3 lightDir = moonlit ? moonDir : sunDir;

    vec3 lightColor = moonlit ? moonColor : sunColor;
    lightColor *= atmosphereTransmittance(lightDir.y, planetRadius + 1e3);
    lightColor *= 1.5 - 0.5 * smoothstep(0.0, 0.15, abs(sunDir.y));
    lightColor *= 1.0 - rainStrength;

    float cosTheta = dot(worldDir, lightDir);
    float bouncedLight = blockyCloudsBottomlight;

    mat2x3 lightColors = mat2x3(lightColor, ambientColor);

    float distanceSum = 0.0;
    float distanceWeightSum = 0.0;

#ifdef blockyCloudsLayer2
    // Offset upper layer so it isn't identical to the below
    float layerOffset
        = abs(layerAltitude - blockyCloudsAltitudeL1) < 0.5 ? 3000.0 : 0.0;
#else
    const float layerOffset = 0.0;
#endif

    // --------------------
    //   Raymarching Loop
    // --------------------

    for (uint i = 0u; i < primarySteps; ++i, worldPos += worldStep) {
        if (transmittance < minTransmittance) {
            break;
        }

        float altitudeFraction
            = (worldPos.y - layerAltitude) * rcp(blockyCloudLayerThickness);

        float density
            = blockyCloudDensityProfile(worldPos, altitudeFraction, layerOffset);
        if (density < eps) {
            continue;
        }

        float stepOpticalDepth
            = density * blockyCloudsExtinctionCoeff * stepLength;
        float stepTransmittance = exp(-stepOpticalDepth);

        float lightOpticalDepth = blockyCloudsOpticalDepth(
            worldPos,
            lightDir,
            layerAltitude,
            layerOffset,
            lightDither,
            lightSteps
        );
        float groundOpticalDepth
            = blockyCloudLayerThickness * altitudeFraction;
        float skyOpticalDepth
            = blockyCloudLayerThickness * (1.0 - altitudeFraction);

        scattering
            += lightColors
            * blockyCloudsScattering(
                   density,
                   lightOpticalDepth,
                   skyOpticalDepth,
                   groundOpticalDepth,
                   stepTransmittance,
                   cosTheta,
                   bouncedLight
            )
            * transmittance * mix(0.8, 1.25, cubicSmooth(altitudeFraction));

        transmittance *= stepTransmittance;

        // Update distance to cloud
        float distanceToSample = distance(cameraPosition, worldPos);
        distanceSum += distanceToSample * density;
        distanceWeightSum += density;
    }

    // Remap the transmittance so that minTransmittance is 0
    float cloudsTransmittance
        = linearStep(minTransmittance, 1.0, transmittance);

    // Distance fade
    float distanceFade = distanceWeightSum == 0.0
        ? 1.0
        : exp(-0.002 * distanceSum / distanceWeightSum);

#ifdef blockyCloudsAtmosphericScattering
    scattering
        *= distanceFade * mix(vec3(1.0, 0.66, 0.50), vec3(1.0), distanceFade);
#else
    scattering *= distanceFade;
#endif
    scattering *= blockyCloudsBrightness;

    transmittance = mix(1.0, transmittance, distanceFade);

    return vec4(scattering, transmittance);
}

#endif // INCLUDE_ATMOS_SKY_BLOCKY_CLOUDS

#endif
#endif

#if defined cloudShadows
#define LUSTER_INCLUDE_CLOUD_SHADOWS
#if defined(LUSTER_INCLUDE_CLOUD_SHADOWS)
// Cloud-shadow projection and sampling.
#if !defined INCLUDE_LIGHT_CLOUD_SHADOWS
#define INCLUDE_LIGHT_CLOUD_SHADOWS

#include "/lib/atmos/clouds/utility/constants.glsl"
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
#endif // INCLUDE_LIGHTING_CLOUD_SHADOWS
#endif

#if defined(LUSTER_INCLUDE_DIRECTIONAL_LIGHTMAPS)
// Directional lightmap modulation.
#if !defined INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS
#define INCLUDE_LIGHT_DIRECTIONAL_LIGHTMAPS

// Based on Ninjamike's implementation in shaderLABS #snippets

vec2 getDirectionalLightmaps(vec3 positionScene, vec3 normal) {
    vec2 lightmapMul = vec2(1.0);

    vec2 lightmapGradient;
    vec3 lightmapDir;
    mat2x3 posGradient = mat2x3(dFdx(positionScene), dFdy(positionScene));

    // Blocklight

    lightmapGradient = vec2(dFdx(lightLevels.x), dFdy(lightLevels.x));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.x = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.x, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.x = mix(
            1.0,
            lightmapMul.x,
            sqr(linearStep(0.03, 0.30, lightLevels.x))
        );
    }

    // Skylight

    lightmapGradient = vec2(dFdx(lightLevels.y), dFdy(lightLevels.y));
    lightmapDir = posGradient * lightmapGradient;

    if (lengthSquared(lightmapGradient) > 1e-12) {
        lightmapMul.y = (clamp01(dot(normalize(lightmapDir), normal) + 0.8)
                              * directionalLightmapsIntensity
                          + (1.0 - directionalLightmapsIntensity))
            // Clamp the renormalization: near-zero lightmaps would
            // otherwise boost noise up to ~1000x (fireflies in caves)
            * inversesqrt(sqrt(max(lightLevels.y, 0.0625)) + eps);

        // Fade the effect out where the lightmap is nearly zero: the
        // gradient is quantized/noisy there and would speckle dark areas.
        lightmapMul.y = mix(
            1.0,
            lightmapMul.y,
            sqr(linearStep(0.03, 0.30, lightLevels.y))
        );
    }

    return lightmapMul;
}

#endif // INCLUDE_LIGHTING_DIRECTIONAL_LIGHTMAPS
#endif

#if defined(LUSTER_INCLUDE_HANDHELD_LIGHT)
// Handheld light source data and evaluation.
#if !defined INCLUDE_LIGHT_HANDHELD_LIGHT
#define INCLUDE_LIGHT_HANDHELD_LIGHT

#define HANDHELD_LIGHT_COLORS
#if handheldLightMode == handheldLightColored
const vec3 handheldEmitterLightColor[48] = vec3[48](
    vec3(1.00, 1.00, 1.00) * 12.0, // Strong white light
    vec3(1.00, 1.00, 1.00) * 6.0, // Medium white light
    vec3(1.00, 1.00, 1.00) * 1.0, // Weak white light
    vec3(1.00, 0.55, 0.27) * 14.0, // Strong golden light
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.57, 0.30) * 6.0, // Weak golden light
    vec3(1.00, 0.18, 0.10) * 5.0, // Redstone components
    vec3(1.00, 0.38, 0.10) * 7.0, // Lava
    vec3(1.00, 0.45, 0.10) * 9.0, // Medium orange light
    vec3(1.00, 0.63, 0.15) * 4.0, // Brewing stand
    vec3(1.00, 0.57, 0.30) * 12.0, // Medium golden light
    vec3(0.45, 0.73, 1.00) * 6.0, // Soul lights
    vec3(0.45, 0.73, 1.00) * 14.0, // Beacon
    vec3(0.75, 1.00, 0.83) * 3.0, // Sculk
    vec3(0.75, 1.00, 0.83) * 1.0, // End portal frame
    vec3(0.60, 0.10, 1.00) * 2.5, // Pink glow
    vec3(0.75, 1.00, 0.50) * 1.0, // Sea pickle
    vec3(1.00, 0.50, 0.25) * 4.0, // Nether plants
    vec3(1.00, 0.57, 0.30) * 8.0, // Medium golden light
    vec3(1.00, 0.65, 0.30) * 8.0, // Ochre froglight
    vec3(0.86, 1.00, 0.44) * 8.0, // Verdant froglight
    vec3(0.75, 0.44, 1.00) * 8.0, // Pearlescent froglight
    vec3(0.60, 0.10, 1.00) * 2.0, // Enchanting table
    vec3(0.75, 0.44, 1.00) * 4.0, // Amethyst cluster
    vec3(0.75, 0.44, 1.00) * 4.0, // Calibrated sculk sensor
    vec3(0.75, 1.00, 0.83) * 6.0, // Active sculk sensor
    vec3(1.00, 0.18, 0.10) * 3.3, // Redstone block
    vec3(1.00, 0.50, 0.25) * 3.0, // Open eyeblossom
    vec3(0.85, 1.3, 1.0) * 3.9, // Copper torch and lanterns
    vec3(1.00, 0.57, 0.30) * 8.0, // Copper Bulbs
    vec3(0.60, 0.10, 1.00) * 12.0, // Nether portal
    vec3(0.0), // End portal
    // Colors for modded light sources (block IDs 64-79)
    vec3(1.00, 1.00, 1.00) * 10.0, // 32 - White       (block 64)
    vec3(0.85, 0.85, 0.85) *  9.0, // 33 - Light Gray  (block 65)
    vec3(0.55, 0.55, 0.55) *  8.0, // 34 - Gray        (block 66)
    vec3(0.20, 0.20, 0.22) *  6.0, // 35 - Black       (block 67)
    vec3(0.55, 0.35, 0.20) *  8.0, // 36 - Brown       (block 68)
    vec3(1.00, 0.10, 0.10) * 10.0, // 37 - Red         (block 69)
    vec3(1.00, 0.45, 0.10) * 10.0, // 38 - Orange      (block 70)
    vec3(1.00, 0.95, 0.20) * 10.0, // 39 - Yellow      (block 71)
    vec3(0.55, 1.00, 0.20) * 10.0, // 40 - Lime        (block 72)
    vec3(0.15, 1.00, 0.20) * 10.0, // 41 - Green       (block 73)
    vec3(0.15, 0.95, 1.00) * 10.0, // 42 - Cyan        (block 74)
    vec3(0.45, 0.75, 1.00) * 10.0, // 43 - Light Blue  (block 75)
    vec3(0.15, 0.30, 1.00) * 10.0, // 44 - Blue        (block 76)
    vec3(0.55, 0.15, 1.00) * 10.0, // 45 - Purple      (block 77)
    vec3(1.00, 0.20, 0.90) * 10.0, // 46 - Magenta     (block 78)
    vec3(1.00, 0.55, 0.85) * 10.0  // 47 - Pink        (block 79)
);
#endif // handheldLightingMode == handheldLightingColored

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 getHandheldLightColor(int handItemId, int heldItemLightValue) {
#if handheldLightMode == handheldLightColored
    const int firstEmitterId = 10032;
    const int emitterCount = 48;
    int emitterIndex = handItemId - firstEmitterId;

    if (emitterIndex >= 0 && emitterIndex < emitterCount) {
        return handheldEmitterLightColor[emitterIndex];
    }
#endif

    return (blocklightColor * blocklightScale * rcp(15.0))
        * heldItemLightValue;
}

float getHandheldLightFalloff(vec3 scenePos, float ao) {
    float falloff = lift(rcp(dot(scenePos, scenePos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * 1.00;
}

vec3 getHandheldLight(vec3 scenePos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scenePos += relativeEyePosition;
#endif

    vec3 lightColor = max(
        getHandheldLightColor(heldItemId, heldBlockLightValue),
        getHandheldLightColor(heldItemId2, heldBlockLightValue2)
    );

    float falloff = getHandheldLightFalloff(scenePos, ao);

    return lightColor * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
#endif

#undef LUSTER_INCLUDE_CLOUD_SHADOWS
#endif

void main() {
#if LUSTER_D4_PASS == 1 && !defined useSeparateEntityDraws
    colortex3Clear = vec4(0.0);
#endif

    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Sample textures

    float depth = texelFetch(combinedDepthTex, texel, 0).x;
    vec4 gbufferData0 = texelFetch(colortex1, texel, 0);
#if defined normalMapping || defined specularMapping
    vec4 gbufferData1 = texelFetch(colortex2, texel, 0);
#endif
#if LUSTER_D4_PASS == 1 && !defined useSeparateEntityDraws
    vec4 overlays = texelFetch(colortex3, texel, 0);
#endif

    // Check for LoD terrain

#ifdef LOD_MOD_ACTIVE
    float depthMc = texelFetch(depthtex1, texel, 0).x;
    float depthLod = texelFetch(lodDepthTexShading, texel, 0).x;
    bool isLod = isLodTerrain(depthMc, depthLod);
#else
    const bool isLod = false;
#define depthMc depth
#endif

    // Space conversions

    bool isHand;
    fixHandDepth(depthMc, isHand);

    vec3 positionView = screenToViewSpace(
        combinedProjectionMatrixInverse,
        vec3(uv, depth),
        true
    );
    vec3 positionScene = viewToSceneSpace(positionView);
    vec3 positionWorld = positionScene + cameraPosition;
    vec3 directionWorld
        = normalize(positionScene - gbufferModelViewInverse[3].xyz);

    // Shared stochastic offset used by cloud lighting. Animated IGN so

#if LUSTER_D4_PASS == 2
    float dither = interleavedGradientNoise(vec2(texel), frameCounter);
#endif

#if LUSTER_D4_PASS == 2 && defined WORLD_OVERWORLD
    // Atmosphere

    vec3 atmosphere = atmosphereScattering(
        directionWorld,
        sunColor,
        sunDir,
        moonColor,
        moonDir,
        /* useKleinNishinaPhase */ depth == 1.0
    );

    // Read clouds/aurora/crepuscular rays

    float cloudsApparentDistance;
    vec4 cloudsAndAurora
        = readCloudsAndAurora(uv, cloudsApparentDistance);

    // Blocky clouds

#ifdef blockyClouds
    vec3 worldStartPos = gbufferModelViewInverse[3].xyz + cameraPosition;
    vec3 worldEndPos = positionWorld;

    vec4 blockyCloudLayer = raymarchBlockyClouds(
        worldStartPos,
        worldEndPos,
        depth == 1.0,
        blockyCloudsAltitudeL0,
        dither
    );

#ifdef blockyCloudsLayer2
    float visibility = pow4(blockyCloudLayer.a);
    vec4 blockyCloudsL2 = raymarchBlockyClouds(
        worldStartPos,
        worldEndPos,
        depth == 1.0,
        blockyCloudsAltitudeL1,
        dither
    );
    blockyCloudLayer.rgb += blockyCloudsL2.xyz * visibility;
    blockyCloudLayer.a *= mix(1.0, blockyCloudsL2.a, visibility);
#endif

    float newAlpha = sqr(sqr(blockyCloudLayer.a));
    blockyCloudLayer.rgb
        += atmosphere * (1.0 - newAlpha) * (blockyCloudLayer.a - newAlpha);
    blockyCloudLayer.a = newAlpha;
#endif
#endif

    if (depth == 1.0) { // Sky
#if LUSTER_D4_PASS == 1
        // Lighting pass: sky is drawn in the compose pass.
        fragmentColor = vec3(0.0);
#else
#if defined WORLD_OVERWORLD
        fragmentColor = drawSky(
            directionWorld,
            atmosphere,
            cloudsAndAurora,
            cloudsApparentDistance
        );
#else
        fragmentColor = drawSky(directionWorld);
#endif

        // Apply blocky clouds
#if defined WORLD_OVERWORLD && defined blockyClouds
        fragmentColor = fragmentColor * blockyCloudLayer.w + blockyCloudLayer.xyz;
#endif

        // Apply common fog
        vec4 fog = commonFog(far, true, directionWorld * far);
        fragmentColor = mix(fog.rgb, fragmentColor.rgb, fog.a);

        // Apply purkinje shift
        fragmentColor = purkinjeShiftTransform(fragmentColor, vec2(0.0, 1.0));
#endif
    } else { // Terrain
#if LUSTER_D4_PASS == 1
        // Sample ambient occlusion a while before using it (latency hiding)

        vec2 halfResPos = gl_FragCoord.xy * (0.5 / taauViewportScale) - 0.5;

        ivec2 i = ivec2(halfResPos);
        vec2 f = fract(halfResPos);

        // Sampled early for latency hiding - resolved further down once
        // this fragment's own linear depth (linZ) is available.
        vec4 aoData00, aoData10, aoData01, aoData11;
        float aoDepth00, aoDepth10, aoDepth01, aoDepth11;
        bilateralUpscaleSample(
            colortex6,
            colortex14,
            i,
            aoData00, aoData10, aoData01, aoData11,
            aoDepth00, aoDepth10, aoDepth01, aoDepth11
        );

        // Unpack gbuffer data

        mat4x2 data = mat4x2(
            unpackUnorm2x8(gbufferData0.x),
            unpackUnorm2x8(gbufferData0.y),
            unpackUnorm2x8(gbufferData0.z),
            unpackUnorm2x8(gbufferData0.w)
        );

        vec3 albedo = vec3(data[0], data[1].x);
        uint materialMask = uint(255.0 * data[1].y);
        vec3 flatNormal = decodeUnitVector(data[2]);
        vec2 lightLevels = data[3];

#if LUSTER_D4_PASS == 1 && !defined useSeparateEntityDraws
        uint overlayId = uint(255.0 * overlays.a);
        albedo = overlayId == 0u ? albedo + overlays.rgb
                                  : albedo; // enchantment glint
        albedo = overlayId == 1u && !isHand
            ? 2.0 * albedo * overlays.rgb
            : albedo; // damage overlay
#endif

        // Get material and normal

        Material material = materialFrom(
            albedo,
            materialMask,
            positionWorld,
            flatNormal,
            lightLevels
        );

        vec3 normal = flatNormal;
        bool parallaxShadow = false;

#ifdef LOD_MOD_ACTIVE
        if (!isLod) {
#endif

#ifdef normalMapping
            normal = decodeUnitVector(gbufferData1.xy);
#endif

#ifdef specularMapping
            vec4 specularMap = vec4(
                unpackUnorm2x8(gbufferData1.z),
                unpackUnorm2x8(gbufferData1.w)
            );
            decodeSpecularMap(specularMap, material, parallaxShadow);
#elif defined normalMapping
            parallaxShadow = gbufferData1.z >= 0.5;
#endif

#ifdef LOD_MOD_ACTIVE
        }
#endif

        // Rain puddles

#if defined WORLD_OVERWORLD && defined rainPuddles
        if (wetness > eps && biomeMayRain > eps) {
            bool puddle = getRainPuddles(
                positionWorld,
                flatNormal,
                lightLevels,
                material.porosityAmount,
                materialMask,
                normal,
                material.albedo,
                material.f0,
                material.roughness,
                material.ssrMultiplier
            );
        }
#endif

#if defined WORLD_OVERWORLD && defined porosity
        if (wetness > eps && material.porosityAmount > eps) {
            material.albedo = applyWetPorosityDarkening(
                material.albedo,
                material.porosityAmount,
                wetness * max0(biomeMayRain)
            );
        }
#endif

        // Upscale ambient occlusion

        float linZ = screenToViewSpaceDepth(
            combinedProjectionMatrixInverse,
            depth
        );

        vec4 ambientUpscaled = bilateralUpscaleResolve(
            aoData00, aoData10, aoData01, aoData11,
            aoDepth00, aoDepth10, aoDepth01, aoDepth11,
            f,
            combinedProjectionMatrixInverse,
            linZ,
            10.0
        );

        float ao = ambientUpscaled.x;
        float ambientSss = ambientUpscaled.y;

        vec3 bentNormal;
        bentNormal.xy = ambientUpscaled.zw * 2.0 - 1.0;
        bentNormal.z
            = sqrt(clamp01(1.0 - dot(bentNormal.xy, bentNormal.xy)));
        bentNormal = mat3(gbufferModelViewInverse) * bentNormal;

        // Sense check bent normal
        if (dot(bentNormal, normal) < eps) {
            bentNormal = normal;
        }

        // No AO/bent normal on hand
        if (isHand) {
            ao = 1.0;
            bentNormal = normal;
        }

        // Calculate lighting dot products

        float NoL = dot(normal, lightDir);
        float NoV = clamp01(dot(normal, -directionWorld));
        float LoV = dot(lightDir, -directionWorld);
        float halfwayNorm = inversesqrt(2.0 * LoV + 2.0);
        float NoH = (NoL + NoV) * halfwayNorm;
        float LoH = LoV * halfwayNorm + halfwayNorm;

        // Cloud shadows

#if defined WORLD_OVERWORLD && defined cloudShadows
        float cloudShadowMask = getCloudShadows(colortex8, positionScene);
#else
        const float cloudShadowMask = 1.0;
#endif

        // Shadows

#if defined WORLD_OVERWORLD || defined WORLD_END
        vec3 shadows = vec3(0.0);
        float shadowDistanceFade = 1.0;
        float sssDepth = 0.0;

        if (NoL > 1e-3 || material.sssAmount > 1e-3) {
            // Calculate near shadows
            vec3 shadowNear = vec3(0.0);
            float shadowDistant = 0.0;
            float sssDepthNear = 0.0;
            float sssDepthDistant = 0.0;

#ifdef shadow
            shadowNear = getFilteredShadows(
                positionScene,
                flatNormal,
                lightLevels.y,
                cloudShadowMask,
                material.sssAmount,
                shadowDistanceFade,
                sssDepthNear
            );
#endif

            // Calculate distant shadows
            if (shadowDistanceFade >= eps) {
#ifdef shadowSsrt
                shadowDistant = getScreenSpaceShadows(
                    uv,
                    positionView,
                    depth,
#ifdef LOD_MOD_ACTIVE
                    depthLod,
#endif
                    lightLevels.y,
                    material.sssAmount > eps,
                    sssDepthDistant
                );
#else
                shadowDistant = getLightmapShadows(lightLevels.y);
#endif
            }

            shadows = mix(
                shadowNear,
                vec3(shadowDistant),
                clamp01(shadowDistanceFade)
            );

            sssDepth = mix(
                sssDepthNear,
                sssDepthDistant,
                clamp01(shadowDistanceFade)
            );

#if defined pom && defined pomShadow \
    && (defined specularMapping || defined normalMapping)
            shadows *= float(!parallaxShadow);
#endif

        }
#else
        const vec3 shadows = vec3(1.0);
        const float shadowDistanceFade = 1.0;
        const float sssDepth = 0.0;
#endif

#ifdef hBasisSkylight
        vec3 skyIrradiance = hBasisIntensity
            * evaluateHBasisIrradiance(hSky, bentNormal);
#else
        vec3 skyIrradiance = hBasisIntensity * ambientColor;
#endif

        fragmentColor = getDiffuseLight(
            material,
            positionScene,
            normal,
            flatNormal,
            shadows,
            lightLevels,
            ao,
            ambientSss,
            sssDepth,
#ifdef cloudShadows
            cloudShadowMask,
#endif
#ifdef shadowSsrt
            0.0,
#else
            shadowDistanceFade,
#endif
            NoL,
            NoV,
            NoH,
            LoV,
            skyIrradiance
        );

#ifdef ssptEnabled
        {

            // d5SsptAccumulate and a-trous filtered by d6SsptFilter.

            vec3 ssptLight = max0(texture(colortex17, uv).rgb);

            // diffuse modulation by albedo and metal diffuse amount. SSPT

            ssptLight *= material.albedo;
            ssptLight *= mix(1.0, metalDiffuseAmount, float(material.isMetal));

            // clouds physically, and traced sky arrives pre-darkened by the

            fragmentColor += ssptLight;
        }
#endif

        // Specular highlight

#if defined WORLD_OVERWORLD || defined WORLD_END
        fragmentColor
            += getSpecularHighlight(material, NoL, NoV, NoH, LoV, LoH)
            * lightColor * shadows * cloudShadowMask * ao;
#endif
#else

        fragmentColor = texelFetch(colortex0, texel, 0).rgb;

        mat4x2 compData = mat4x2(
            unpackUnorm2x8(gbufferData0.x),
            unpackUnorm2x8(gbufferData0.y),
            unpackUnorm2x8(gbufferData0.z),
            unpackUnorm2x8(gbufferData0.w)
        );

        vec3 compAlbedo = vec3(compData[0], compData[1].x);
        uint materialMask = uint(255.0 * compData[1].y);
        vec3 flatNormal = decodeUnitVector(compData[2]);
        vec2 lightLevels = compData[3];

        Material material = materialFrom(
            compAlbedo,
            materialMask,
            positionWorld,
            flatNormal,
            lightLevels
        );

        vec3 normal = flatNormal;

#ifdef LOD_MOD_ACTIVE
        if (!isLod) {
#endif

#ifdef normalMapping
            normal = decodeUnitVector(gbufferData1.xy);
#endif

#ifdef specularMapping
            vec4 compSpecularMap = vec4(
                unpackUnorm2x8(gbufferData1.z),
                unpackUnorm2x8(gbufferData1.w)
            );
            bool compParallax = false;
            decodeSpecularMap(compSpecularMap, material, compParallax);
#endif

#ifdef LOD_MOD_ACTIVE
        }
#endif

        // Specular reflections

#if defined environmentReflections || defined skyReflections
        if (material.ssrMultiplier > eps) {
            mat3 tbn = getTbnMatrix(normal);

            fragmentColor += getSpecularReflections(
                material,
                tbn,
                vec3(uv, depth),
                positionView,
                positionWorld,
                normal,
                flatNormal,
                directionWorld,
                directionWorld * tbn,
                lightLevels.y,
                false
            );
        }
#endif
        // Edge highlight

#ifdef edgeHighlight
        fragmentColor *= 1.0
            + 0.5
                * getEdgeHighlight(
                    positionScene,
                    flatNormal,
                    depth,
                    materialMask
                );
#endif

        // Apply fog

        float viewDistance = length(positionView);

#ifdef borderFog
#if defined WORLD_OVERWORLD
        vec3 horizonDir = normalize(
            vec3(directionWorld.xz, min(directionWorld.y, -0.1)).xzy
        );
        vec3 horizonColor = texture(colortex4, projectSky(horizonDir)).rgb;

        float horizonFactor
            = linearStep(0.1, 1.0, exp(-75.0 * sqr(sunDir.y + 0.0496)));
        horizonFactor = clamp01(horizonFactor + step(0.01, rainStrength));
        horizonFactor = max(
            horizonFactor,
            dampen(linearStep(0.15, 0.05, directionWorld.y))
        );

        vec3 borderFogColor
            = mix(atmosphere, horizonColor, sqr(horizonFactor))
            * (1.0 - biomeCave);
#else
        vec3 borderFogColor
            = texture(colortex4, projectSky(directionWorld)).rgb;
#endif

        float borderFogFactor = borderFogFactor(positionScene, directionWorld);
        fragmentColor = mix(borderFogColor, fragmentColor, borderFogFactor);
#endif

        vec4 fog = commonFog(viewDistance, false, positionScene);
        fragmentColor = fragmentColor * fog.a + fog.rgb;

#if defined WORLD_OVERWORLD
        // Apply clouds in front of terrain

#ifdef blockyClouds
        fragmentColor = fragmentColor * blockyCloudLayer.w + blockyCloudLayer.xyz;
#else
        if (sqr(cloudsApparentDistance) < lengthSquared(positionView)) {
            fragmentColor
                = fragmentColor * cloudsAndAurora.w + cloudsAndAurora.xyz;
        }
#endif

        // Apply rainbows in front of terrain

#ifdef rainbows
        fragmentColor = drawRainbows(
            fragmentColor,
            directionWorld,
            min(viewDistance,
                mix(cloudsApparentDistance,
                    1e6,
                    linearStep(1.0, 0.95, cloudsAndAurora.w)))
        );
#endif
#endif

        // Apply purkinje shift

        fragmentColor = purkinjeShiftTransform(fragmentColor, lightLevels);
// end LUSTER_D4_PASS terrain split
#endif
    }
}
