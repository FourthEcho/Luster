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

#if !defined INCLUDE_SURFACE_WATER
#define INCLUDE_SURFACE_WATER

#include "/lib/util/spaceConversion.glsl"
#include "/lib/surface/rain.glsl"

float gerstnerWave(
    vec2 coord,
    vec2 waveDir,
    float t,
    float noise,
    float wavelength
) {
    // Gerstner wave function from Belmu in #snippets, modified
    const float g = 9.8;

    float k = tau / wavelength;
    float w = sqrt(g * k);

    float x = w * t - k * (dot(waveDir, coord) + noise);

    return sqr(sin(x) * 0.5 + 0.5);
}

void waterWavesSetup(
    bool flowingWater,
    vec2 flowDir,
    out vec2 waveDir,
    out mat2 waveRot,
    out float t
) {
    const float waveSpeedStill = 0.5 * waterWaveSpeedStill;
    const float waveSpeedFlowing = 0.7 * waterWaveSpeedFlowing;
    const float waveAngle = 30.0 * degree;

    t = (flowingWater ? waveSpeedFlowing : waveSpeedStill)
        * frameTimeCounter;

    waveDir
        = flowingWater ? flowDir : vec2(cos(waveAngle), sin(waveAngle));
    waveRot = flowingWater
        ? mat2(1.0)
        : mat2(
              cos(goldenAngle),
              sin(goldenAngle),
              -sin(goldenAngle),
              cos(goldenAngle)
          );
}
float getWaterHeight(vec2 coord, vec2 waveDir, mat2 waveRot, float t) {
    // Parameters

    // Gerstner waves
    const float waveFrequency = 0.7 * waterWaveFrequency;
    const float persistence = 0.5 * waterWavePersistence;
    const float lacunarity = 1.7 * waterWaveLacunarity;

    // Noise
    const float noiseFrequency = 0.007;


    const float noiseStrength = 2.0 * waterWavesNoiseStrength;

    // Height variation
    const float heightVariationFrequency = 0.001;
    const float minHeight = 0.4;
    const float heightVariationScale = 2.0;
    const float heightVariationOffset = -0.5;
    const float heightVariationScrollSpeed = 0.1;


    const float amplitudeNormalizationFactor = (1.0 - persistence)
        / (1.0 - pow(persistence, float(waterWaveIterations)));

    // Sample noise textures first (latency hiding)

    float[waterWaveIterations] waveNoise;
    vec2 noiseCoord = (coord + vec2(0.0, 0.25 * t)) * noiseFrequency;
    for (uint i = 0u; i < waterWaveIterations; ++i) {
        waveNoise[i] = texture(noisetex, noiseCoord).y;
        noiseCoord *= 2.5;
    }

#ifdef waterWavesHeightVariation
    float heightVariationNoise
        = texture(
              noisetex,
              (coord + vec2(0.0, heightVariationScrollSpeed * t))
                  * heightVariationFrequency
        )
              .y;
#endif

    // Calculate wave height

    float height = 0.0;
    float amplitudeSum = 0.0;

    float waveLength = 1.0;
    float amplitude = 1.0;
    float frequency = waveFrequency;

    for (uint i = 0u; i < waterWaveIterations; ++i) {
        height += gerstnerWave(
                      coord * frequency,
                      waveDir,
                      t,
                      waveNoise[i] * noiseStrength,
                      waveLength
                  )
            * amplitude;

        amplitude *= persistence;
        frequency *= lacunarity;
        waveLength *= 1.5;

        waveDir *= waveRot;
    }

#ifdef waterWavesHeightVariation
    height *= max(
        minHeight,
        heightVariationNoise * heightVariationScale
            + heightVariationOffset
    );
#endif

    return height * amplitudeNormalizationFactor;
}

vec3 getWaterNormal(
    vec3 worldPos,
    vec3 flatNormal,
    vec2 coord,
    vec2 flowDir,
    float skylight,
    bool flowingWater
) {
    vec2 waveDir;
    mat2 waveRot;
    float t;
    waterWavesSetup(flowingWater, flowDir, waveDir, waveRot, t);

    const float h = 0.1;
    float wave0 = getWaterHeight(coord, waveDir, waveRot, t);
    float wave1 = getWaterHeight(coord + vec2(h, 0.0), waveDir, waveRot, t);
    float wave2 = getWaterHeight(coord + vec2(0.0, h), waveDir, waveRot, t);

#if defined WORLD_OVERWORLD
    float normalInfluence = flowingWater
        ? 0.1
        : mix(0.01, 0.04 + 0.15 * rainStrength, dampen(skylight));
#else
    float normalInfluence = 0.04;
#endif
    float grazingFade = smoothstep(
        0.0,
        0.15,
        abs(dot(flatNormal, normalize(worldPos - cameraPosition)))
    ); // prevent noise when looking horizontally
    normalInfluence *= grazingFade;
    normalInfluence *= waterWaveStrength;

    // Luster-style wave normal (matches Luster exactly; note this tilts
    // towards the slope rather than away from it).
    vec3 normal = vec3(wave1 - wave0, wave2 - wave0, h);
    normal.xy *= normalInfluence;

#ifdef rainRipples


    float rainRippleMask
        = float(!flowingWater) * rainStrength * smoothstep(0.85, 1.0, skylight);

    if (rainRippleMask > 0.001) {
        // Analytic ring normals 
        // no finite differences needed.
        vec2 rippleGradient
            = rainRippleNormal(coord, frameTimeCounter).xy;
        float rippleInfluence
            = 0.30 * rainRippleStrength * rainRippleMask * grazingFade;

        normal.xy += rippleGradient * rippleInfluence;
    }
#endif

    return normalize(normal);
}

vec2 getWaterParallaxCoord(
    vec3 tangentDir,
    vec2 coord,
    vec2 flowDir,
    bool flowingWater
) {
    const int stepCount = 4;
    const float parallaxDepth = 0.2;

    vec2 waveDir;
    mat2 waveRot;
    float t;
    waterWavesSetup(flowingWater, flowDir, waveDir, waveRot, t);

    vec2 rayStep = tangentDir.xy * rcp(-tangentDir.z) * parallaxDepth
        * rcp(float(stepCount));

    float depthValue = getWaterHeight(coord, waveDir, waveRot, t);
    float depthMarch = 0.0;
    float depthPrevious;

    while (depthMarch < depthValue) {
        coord += rayStep;
        depthPrevious = depthValue;
        depthValue = getWaterHeight(coord, waveDir, waveRot, t);
        depthMarch += rcp(float(stepCount));
    }

    // Interpolation step

    float depthBefore = depthPrevious - depthMarch + rcp(float(stepCount));
    float depthAfter = depthValue - depthMarch;

    return mix(
        coord,
        coord - rayStep,
        depthAfter / (depthAfter - depthBefore)
    );
}


#ifdef LUSTER_INCLUDE_WATER_SURFACE_MATERIAL
#include "/lib/brdf/material.glsl"
#include "/lib/atmos/air/simple.glsl"
#include "/lib/util/color.glsl"
Material getWaterMaterial(
    vec3 directionWorld,
    vec3 normal,
    float layerDist,
    out float alpha
) {
    Material material = waterMaterial;
    alpha = 0.01;

    // Water texture

#if waterTexture == waterTextureHighlight \
    || waterTexture == waterTextureHighlightUnderground
    vec4 baseColor = readTexAnisotropicOrPlain(gtexture, uv);


    float textureHighlight = dampen(
        0.5 * sqr(linearStep(0.63, 1.0, baseColor.r)) + 0.03 * baseColor.r
    ) * waterTextureIntensity;
#if waterTexture == waterTextureHighlightUnderground
    textureHighlight *= 1.0 - cube(linearStep(0.0, 0.5, lightLevels.y));
#endif

    material.albedo
        = clamp01(0.5 * exp(-2.0 * waterAbsorptionCoeff) * textureHighlight);
    material.roughness += 0.3 * textureHighlight;
    alpha += textureHighlight;
#elif waterTexture == waterTextureVanilla
    vec4 baseColor = readTexAnisotropicOrPlain(gtexture, uv) * tint;
    material.albedo = srgbEotfInv(baseColor.rgb * baseColor.a)
        * rec709ToWorkingColor;
    alpha = baseColor.a;
#endif

    // Water edge highlight

#ifdef waterEdgeHighlight
    float dist = layerDist * max(abs(directionWorld.y), eps);

#if waterTexture == waterTextureHighlight \
    || waterTexture == waterTextureHighlightUnderground
    float edgeHighlightAmount
        = cube(max0(1.0 - 2.0 * dist)) * (1.0 + 8.0 * textureHighlight);
#else
    float edgeHighlightAmount = cube(max0(1.0 - 2.0 * dist));
#endif
    edgeHighlightAmount *= waterEdgeHighlightIntensity * max0(normal.y)
        * (1.0 - 0.5 * sqr(lightLevels.y));
    ;

    material.albedo += 0.1 * edgeHighlightAmount
        / mix(1.0,
              max(dot(ambientColor, luminanceWeights), 0.5),
              lightLevels.y);
    material.albedo = clamp01(material.albedo);
    alpha += edgeHighlightAmount;
#endif

    return material;
}

vec4 waterAbsorptionApprox(
    vec4 color,
    float sssDepth,
    float layerDist,
    float LoV,
    float NoV,
    float cloudShadowMask
) {


    // We blend the biome tint toward neutral grey (0.5) by the inverse of


    vec3 biomeWaterTint = srgbEotfInv(tint.rgb) * rec709ToWorkingColor;
    biomeWaterTint = mix(
        vec3(dot(biomeWaterTint, luminanceWeights)),
        biomeWaterTint,
        biomeWaterColorIntensity
    );
    vec3 absorptionCoeff = biomeWaterCoeff(biomeWaterTint);
    float dist = layerDist * float(isEyeInWater != 1 || NoV >= 0.0);

    mat2x3 waterFog = waterFogSimple(
        lightColor * cloudShadowMask,
        ambientColor,
        absorptionCoeff,
        lightLevels,
        dist,
        -LoV,
        sssDepth
    );

    float brightnessControl = 1.0 - exp(-0.33 * layerDist);
    brightnessControl *= max(lightLevels.x, lightLevels.y);

    return vec4(
        color.rgb
            + waterFog[0] * (1.0 + 6.0 * sqr(waterFog[1]))
                * brightnessControl,
        1.0 - waterFog[1].x
    );
}
#endif

#endif // INCLUDE_SURFACE_WATER
