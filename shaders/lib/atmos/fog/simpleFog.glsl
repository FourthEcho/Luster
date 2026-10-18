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

#if !defined INCLUDE_FOG_SIMPLE_FOG
#define INCLUDE_FOG_SIMPLE_FOG

#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/atmos/fog/water/waterAbsorption.glsl"
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/atmos/projection.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/phaseFunctions.glsl"

const float lavaFogStart = 0.33;
const float lavaFogDensity = 1.0;
const vec3 lavaFogColor = gamutExpand(fromDisplay(vec3(0.839, 0.373, 0.075))) * 2.0;

const float snowFogStart = 0.5;
const float snowFogDensity = 1.0;
const vec3 snowFogColor = gamutExpand(fromDisplay(vec3(0.957, 0.988, 0.988))) * 0.3;

const float caveFogStart = 1.0;
// caveFogIntensity scales the cave fog density. At 1.0 it matches the
// previous hardcoded density of 0.0033; at 0 cave fog is invisible.
const float caveFogDensity = 0.0033 * caveFogIntensity;
const vec3 caveFogColor = vec3(0.033);

const float blindnessFogStart = 2.0;
const float blindnessFogDensity = 1.0;

const float darknessFogStart = 8.0;
const float darknessFogDensity = 2.0;


float netherFogDensity(vec3 worldPos) {
    const float falloffStart = 64.0;
    const float falloffHalfLife = 7.0;
    const float mul = -rcp(falloffHalfLife);
    const float add = -mul * falloffStart;
    float density = exp2(min(worldPos.y * mul + add, 0.0));
    density *= linearStep(0.0, 64.0, worldPos.y);
    return density;
}

vec3 getNetherFogColor() {
#ifdef netherUseBiomeColor
    vec3 color = srgbEotfInv(clamp(fogColor, 0.0, 1.0)) * rec709ToWorkingColor;
    color /= max(dot(color, luminanceWeights), eps);
    return mix(vec3(1.0), color, netherS);
#else
    return gamutExpand(fromDisplay(vec3(netherR, netherG, netherB)));
#endif
}

float sphericalFog(
    float viewDist,
    float fogStartDistance,
    float fogDensity
) {
    return exp2(-fogDensity * max0(viewDist - fogStartDistance));
}

float borderFogFactor(vec3 scenePos, vec3 worldDir) {
#ifndef LOD_MOD_ACTIVE
    float fog = cubicLength(scenePos.xz) / far;


    fog = exp2(-(8.0 * borderFogIntensity) * pow8(fog));
    float verticalCutoffDistance = far;
#else
    float fog = length(scenePos.xz) / float(lodRenderDistance);
    fog = exp2(-(2.4 * borderFogIntensity) * sqr(fog));
#endif

#if defined WORLD_OVERWORLD || defined WORLD_END
    fog = mix(fog, 1.0, 0.75 * dampen(linearStep(0.0, 0.2, worldDir.y)));
#endif

#ifndef LOD_MOD_ACTIVE
    float verticalCutoff = linearStep(-verticalCutoffDistance, -verticalCutoffDistance + 16.0, scenePos.y);
    fog *= verticalCutoff;
#endif

    return fog;
}

vec4 commonFog(float viewDist, const bool sky, vec3 scenePos) {
    vec4 fog = vec4(vec3(0.0), 1.0);

    // Lava fog
    float lavaFog = sphericalFog(
        viewDist,
        lavaFogStart,
        lavaFogDensity * float(isEyeInWater == 2)
    );
    fog.rgb += lavaFogColor - lavaFogColor * lavaFog;
    fog.a *= lavaFog;

    // Powdered snow fog
    float snowFog = sphericalFog(
        viewDist,
        snowFogStart,
        snowFogDensity * float(isEyeInWater == 3)
    );
    fog.rgb += snowFogColor - snowFogColor * snowFog;
    fog.a *= snowFog;

    // Blindness fog
    fog *= mix(
        1.0,
        sphericalFog(
            viewDist,
            blindnessFogStart,
            blindness * blindnessFogDensity
        ),
        blindness
    );

    // Darkness fog
    fog *= mix(
        1.0,
        sphericalFog(
            viewDist,
            darknessFogStart,
            darknessFactor * darknessFogDensity
        ),
        darknessFactor
    );

#if defined WORLD_OVERWORLD && defined caveFog
    // Cave fog
    float caveFogFactor = sphericalFog(
        viewDist,
        caveFogStart,
        caveFogDensity * biomeCave * float(!sky)
    );
    fog.rgb += caveFogColor - caveFogColor * caveFogFactor;
    fog.a *= caveFogFactor;
#endif

#if defined WORLD_NETHER && !defined vl
    float netherFog = sphericalFog(
        viewDist,
        0.0,
        0.01 * netherFogDensity(scenePos + cameraPosition)
    );
    vec3 netherColor = getNetherFogColor() * netherI;
    fog.rgb += netherColor - netherColor * netherFog;
    fog.a *= netherFog;
#endif

    return fog;
}

// Calculates the alpha component only
// Water fog

const vec3 waterAbsorptionCoeff
    = vec3(waterAbsorptionR, waterAbsorptionG, waterAbsorptionB)
    * rec709ToWorkingColor;

// Simple water fog applied behind water or when volumetric fog is disabled
mat2x3 waterFogSimple(
    vec3 lightColor,
    vec3 ambientColor,
    vec3 absorptionCoeff,
    vec2 lightLevels,
    float dist,
    float LoV,
    float sssDepth
) {
    float skylightFactor = cube(lightLevels.y);

    vec3 scatteringCoeff = vec3(waterScattering);
    vec3 extinctionCoeff = scatteringCoeff + absorptionCoeff;

    // Multiple scattering approximation from Jessie
    vec3 scatteringAlbedo = scatteringCoeff / extinctionCoeff;
    vec3 multipleScatteringFactor = 0.84 * scatteringAlbedo;
    vec3 multipleScatteringEnergy
        = multipleScatteringFactor / (1.0 - multipleScatteringFactor);

    // Minimum distance so that water is always easily visible
    dist = max(dist, 2.0 - 1.0 * skylightFactor);

    vec3 lightAmbient = ambientColor * lightLevels.y;
    lightAmbient
        += 1.41 * blocklightColor * blocklightScale * sqr(lightLevels.x);

    vec3 transmittance = exp(-extinctionCoeff * dist);

    vec3 scattering = lightColor * exp(-extinctionCoeff * sssDepth)
        * smoothstep(0.0, 0.25, lightLevels.y); // direct lighting
    scattering *= 0.7 * henyeyGreensteinPhase(LoV, 0.4)
        + 0.3 * isotropicPhase; // phase function for direct lighting
    scattering += lightAmbient * isotropicPhase; // ambient lighting
    scattering *= (1.0 - transmittance) * scatteringCoeff
        / extinctionCoeff; // scattering integral
    scattering *= 1.0 + multipleScatteringEnergy; // multiple scattering

    return mat2x3(scattering, transmittance);
}

#endif // INCLUDE_FOG_SIMPLE_FOG
