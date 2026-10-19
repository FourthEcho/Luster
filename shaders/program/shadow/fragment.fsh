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

#if defined COLORWHEEL
layout(location = 0) out vec4 shadowcolor0Out;
#else
layout(location = 0) out vec3 shadowcolor0Out;
#endif

/* RENDERTARGETS: 0 */

in vec2 uv;

flat in uint materialMask;
flat in vec3 tint;


#ifdef waterCaustics
in vec3 scenePos;
#endif

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
in vec2 atlasTileCoord;
in float pomViewDistance;
flat in vec2 atlasTileOffset;
flat in vec2 atlasTileScale;
flat in mat3 tbn;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D tex;
uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
uniform sampler2D normals;
#endif

uniform vec3 cameraPosition;

uniform float near;
uniform float far;

uniform float frameTimeCounter;
uniform float rainStrength;

uniform vec2 taaOffset;
uniform vec3 lightDir;

#include "/lib/surface/water.glsl"

// waterAbsorption.glsl (inlined: consumers air/simple + shadow fragment)

#if !defined INCLUDE_FOG_WATER_ABSORPTION
#define INCLUDE_FOG_WATER_ABSORPTION

#include "/lib/util/color.glsl"

vec3 biomeWaterCoeff(vec3 biomeWaterTint) {
    const float densityScale = 0.15;
    const float biomeColorContribution = 0.33;

    const vec3 baseAbsorptionCoeff
        = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
        * rec709ToWorkingColor;
    const vec3 forestAbsorptionCoeff
        = -densityScale * log(vec3(0.1245, 0.1797, 0.7108));

#ifdef biomeWaterColor
    vec3 biomeAbsorptionCoeff = -densityScale * log(biomeWaterTint + eps)
        - forestAbsorptionCoeff;

    return max0(
        baseAbsorptionCoeff
        + biomeAbsorptionCoeff * biomeColorContribution
    );
#else
    return baseAbsorptionCoeff;
#endif
}

#endif // INCLUDE_FOG_WATER_ABSORPTION
#include "/lib/util/color.glsl"
#include "/lib/util/encoding.glsl"

#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
#include "/lib/surface/parallax.glsl"
#endif

const float airN = 1.000293; // for 0°C and 1 atm
const float waterN = 1.333; // for 20°C

const vec3 waterAbsorptionCoeff
    = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
    * rec709ToWorkingColor;
const vec3 waterScatteringCoeff = vec3(waterScattering);
const vec3 waterExtinctionCoeff
    = waterAbsorptionCoeff + waterScatteringCoeff;

const float distanceThroughWater = 5.0; // m

// using the built-in GLSL refract() seems to cause NaNs on Intel drivers, but
// with this function, which does the exact same thing, it's fine
vec3 refractSafe(vec3 I, vec3 N, float eta) {
    float NoI = dot(N, I);
    float k = 1.0 - eta * eta * (1.0 - NoI * NoI);
    if (k < 0.0) {
        return vec3(0.0);
    } else {
        return eta * I - (eta * NoI + sqrt(k)) * N;
    }
}

float getWaterCaustics() {
#ifndef waterCaustics
    return 1.0;
#else
    // TBN matrix for a face pointing directly upwards
    const mat3 tbn = mat3(-1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0);

    const bool flowingWater = false;
    const vec2 flowDir = vec2(0.0);

    vec3 worldPos = scenePos + cameraPosition;

    vec2 coord = -worldPos.xz;
    vec3 normal
        = tbn
        * getWaterNormal(
              worldPos,
              tbn[2],
              coord,
              flowDir,
              1.0 - rainStrength,
              flowingWater
        );

    vec3 oldPos = worldPos;
    vec3 newPos = worldPos
        + refractSafe(lightDir, normal, airN / waterN)
            * (distanceThroughWater * waterCausticsIntensity);

    float oldArea
        = lengthSquared(dFdx(oldPos)) * lengthSquared(dFdy(oldPos));
    float newArea
        = lengthSquared(dFdx(newPos)) * lengthSquared(dFdy(newPos));

    if (oldArea == 0.0 || newArea == 0.0) {
        return 1.0;
    }

    return 0.25 * inversesqrt(oldArea / newArea);
#endif
}

void main() {
#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
    gl_FragDepth = gl_FragCoord.z;
#endif

#ifndef COLORWHEEL
    if (materialMask == 1) { // Water
#if defined PROGRAM_SHADOW_WATER || defined PROGRAM_SHADOW_FALLBACK
        vec3 biomeWaterTint = srgbEotfInv(tint) * rec709ToWorkingColor;
        vec3 absorptionCoeff = biomeWaterCoeff(biomeWaterTint);

        shadowcolor0Out = clamp(
            0.25 * exp(-absorptionCoeff * distanceThroughWater)
                * getWaterCaustics(),
            rcp(255.0) /* 0 is reserved */,
            1.0
        );
#endif
    } else {
#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)


        // the displaced UV, and push shadow depth away from the light by the

        vec2 pomShadowUv = uv;
        float pomShadowDz = 0.0;

        vec3 pomTangentDir = normalize(lightDir * tbn);
        bool pomValid = pomViewDistance < pomDistance
            && dot(tbn[0], tbn[0]) > 0.5 // at_tangent actually supplied
            && pomTangentDir.z > 0.1; // surface faces the light

        if (pomValid) {
            mat2 pomUvGradient = mat2(dFdx(uv), dFdy(uv));
            vec3 pomPrevRayPos;
            float pomHitDepth;

            pomShadowUv = getParallaxUv(
                pomTangentDir,
                pomUvGradient,
                pomViewDistance,
                0.0,
                pomPrevRayPos,
                pomHitDepth
            );

            float pomRelief = getPomWorldRelief(
                pomHitDepth,
                pomViewDistance
            );
            float pomRayDist = pomRelief * rcp(max(pomTangentDir.z, 0.15));
            pomShadowDz = 0.5 * shadowDepthScale
                * -shadowProjection[2][2] * pomRayDist;
        }

        vec4 baseColor = textureLod(tex, pomShadowUv, 0);
#else
        vec4 baseColor = textureLod(tex, uv, 0);
#endif
        if (baseColor.a < 0.1) {
            discard;
        }
#if defined pom && defined pomDepthWrite && !defined COLORWHEEL && (defined PROGRAM_SHADOW_SOLID || defined PROGRAM_SHADOW_CUTOUT)
        if (pomShadowDz == pomShadowDz) {
            gl_FragDepth = min(gl_FragCoord.z + max(pomShadowDz, 0.0), 0.999999);
        }
#endif

        shadowcolor0Out = mix(vec3(1.0), baseColor.rgb * tint, clamp01(baseColor.a * shadowColorIntensity));
        shadowcolor0Out
            = 0.25 * srgbEotfInv(shadowcolor0Out) * rec709ToWorkingColor;
        shadowcolor0Out *= step(baseColor.a, 1.0 - rcp(255.0));

    }
#else
    vec4 baseColor = textureLod(tex, uv, 0);
    vec2 lmcoord;
    float ao;
    vec4 overlayColor;

    clrwl_computeFragment(baseColor, baseColor, lmcoord, ao, overlayColor);
    baseColor.rgb = mix(baseColor.rgb, overlayColor.rgb, overlayColor.a);

    if (baseColor.a < 0.1) {
        discard;
    }

    vec3 outColor = mix(vec3(1.0), baseColor.rgb, baseColor.a);
    outColor = 0.25 * srgbEotfInv(outColor) * rec709ToWorkingColor;
    outColor *= step(baseColor.a, 1.0 - rcp(255.0));

    shadowcolor0Out = vec4(outColor, 1.0);
#endif
}
