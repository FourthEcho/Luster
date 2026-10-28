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

#if !defined INCLUDE_BRDF_MATERIAL
#define INCLUDE_BRDF_MATERIAL

#include "/lib/academy/matrices.glsl"
#include "/lib/util/color.glsl"

const float airN = 1.000293; // for 0°C and 1 atm
const float waterN = 1.333; // for 20°C

struct Material {
    vec3 albedo;
    vec3 emission;
    vec3 f0;
    vec3 f82; // hardcoded metals only
    float roughness;
    float sssAmount;
    float sheenAmount; // sss "sheen" for tall grass
    float porosityAmount;
    float ssrMultiplier;
    bool isMetal;
    bool isHardcodedMetal;
};

const Material waterMaterial = Material(
    vec3(0.0),
    vec3(0.0),
    vec3(0.02),
    vec3(0.0),
    0.002,
    1.0,
    0.0,
    0.0,
    1.0,
    false,
    false
);


#if defined sssUseMaps || defined porosityUseMaps
// LabPBR 1.1 and 1.2+ use the same specular-blue channel layout:
// 0-64 = porosity, 65-255 = subsurface scattering. Both ranges are linear.
void decodeLabPbrSubsurfaceAndPorosity(vec4 specularMap, inout Material material) {
    // LabPBR assigns blue-channel porosity/SSS data to dielectrics only.
    if (specularMap.g < 229.5 / 255.0) {
        float blueValue = specularMap.b * 255.0;
        bool hasSssRegion = blueValue >= 64.5;

#ifdef sssUseMaps
        // 65 encodes 0% SSS; 255 encodes 100% SSS.
        if (hasSssRegion) {
            material.sssAmount = clamp((blueValue - 65.0) / 190.0, 0.0, 1.0);
#ifdef sssSheen
            material.sheenAmount = 1.0;
#endif
        }
#endif

#ifdef porosityUseMaps
#if porosityMode == porosityMaps
        // LabPBR Only: no hardcoded fallback when blue is zero or reserved for SSS.
        material.porosityAmount = hasSssRegion
            ? 0.0
            : clamp(blueValue / 64.0, 0.0, 1.0) * porosityStrength;
#else
        // Hardcoded + LabPBR: the map overrides hardcoded porosity whenever
        // blue encodes porosity (including an explicit value of zero). When
        // blue encodes SSS, retain the hardcoded porosity fallback because
        // the shared channel carries no porosity value for that texel.
        if (!hasSssRegion) {
            material.porosityAmount = clamp(blueValue / 64.0, 0.0, 1.0)
                * porosityStrength;
        }
#endif
#endif
    }
}
#endif


#if textureFormat == textureFormatLab12Plus || textureFormat == textureFormatLab11
void decodeSpecularMap(vec4 specularMap, inout Material material) {
#ifdef specularAuxOnly
#if defined sssUseMaps || defined porosityUseMaps
    decodeLabPbrSubsurfaceAndPorosity(specularMap, material);
#endif
#else
    // Full LabPBR specular-map decoding.
    // Measured complex refractive indices. Sources: Palik "Handbook of Optical Constants", refractiveindex.info.
    const vec3[] metalN = vec3[](
        vec3(2.9114, 2.9497, 2.7743), // Iron
        vec3(0.1431, 0.3740, 1.4400), // Gold
        vec3(1.0970, 0.8795, 0.5237), // Aluminum
        vec3(3.1071, 3.1812, 2.3230), // Chrome
        vec3(0.2140, 0.9300, 1.1000), // Copper
        vec3(1.9100, 1.8300, 1.4400), // Lead
        vec3(2.3757, 2.0847, 1.8453), // Platinum
        vec3(0.1550, 0.1160, 0.1390)  // Silver
    );
    const vec3[] metalK = vec3[](
        vec3(3.0893, 2.9318, 2.7670), // Iron
        vec3(3.9800, 2.3880, 1.6030), // Gold
        vec3(6.7942, 6.2875, 5.3000), // Aluminum
        vec3(3.3314, 3.3291, 3.1350), // Chrome
        vec3(3.9100, 2.5900, 2.3600), // Copper
        vec3(3.5100, 3.4000, 3.1800), // Lead
        vec3(4.2655, 3.7153, 3.1365), // Platinum
        vec3(4.8200, 3.1160, 2.1440)  // Silver
    );

    material.roughness = sqr(1.0 - specularMap.r);

    // ---- Emission ----
#ifdef hardcodedEmission
    // Built-in emission was populated by materialFrom().
#else
    float hasEmissionMap = step(specularMap.a, 254.5 / 255.0);
    float emissionValue = specularMap.a * (255.0 / 254.0);
    // Unmapped texels do not fall back to hardcoded emission.
    material.emission = material.albedo * emissionValue * hasEmissionMap;
#endif
    material.emission = pow(
        max(material.emission, vec3(0.0)),
        vec3(globalEmissionCurve)
    );
    material.emission *= globalEmissionIntensity;

    if (specularMap.g < 229.5 / 255.0) {
        // Dielectrics
        material.f0 = max(material.f0, specularMap.g);

#if defined sssUseMaps || defined porosityUseMaps
        decodeLabPbrSubsurfaceAndPorosity(specularMap, material);
#endif
    } else if (specularMap.g < 237.5 / 255.0) {
        // Hardcoded metals
        uint metalId = clamp(uint(255.0 * specularMap.g) - 230u, 0u, 7u);

        material.f0 = metalN[metalId];
        material.f82 = metalK[metalId];
        material.isMetal = true;
        material.isHardcodedMetal = true;
    } else {
        // Albedo metal
        material.f0 = material.albedo;
        material.isMetal = true;
    }
    material.ssrMultiplier = step(
        0.01,
        (material.f0.x
         - material.f0.x * material.roughness * ssrRoughnessThresh)
    ); // based on Kneemund's method
#endif
}
#endif

void decodeSpecularMap(
    vec4 specularMap,
    inout Material material,
    out bool parallaxShadow
) {
    parallaxShadow = false;
#if defined pom && defined pomShadow
    parallaxShadow = specularMap.a >= 0.5;
    specularMap.a = fract(specularMap.a * 2.0);
#endif
    decodeSpecularMap(specularMap, material);
}

Material materialFrom(
    vec3 albedoSrgb,
    uint materialMask,
    vec3 worldPos,
    vec3 normal,
    inout vec2 lightLevels
) {
    vec3 blockPos = fract(worldPos);

    // Create material with default values

    Material material;
    material.albedo = srgbEotfInv(albedoSrgb) * rec709ToWorkingColor;
    material.emission = vec3(0.0);
    material.f0 = vec3(0.02);
    material.f82 = vec3(0.0);
    material.roughness = 1.0;
    material.sssAmount = 0.0;
    material.sheenAmount = 0.0;
    material.porosityAmount = 0.0;
    material.ssrMultiplier = 0.0;
    material.isMetal = false;
    material.isHardcodedMetal = false;

    // Hardcoded materials for specific blocks


    vec3 hsv = rgbToHsv(albedoSrgb);
    vec3 albedoSqrt = sqrt(material.albedo);

    if (materialMask < 32u) { // 0-32
        if (materialMask < 16u) { // 0-16
            if (materialMask < 8u) { // 0-8
                if (materialMask < 4u) { // 0-4
                    if (materialMask < 2u) { // 0-2
                        if (materialMask == 0u) { // 2
#ifdef hardcodedSpecular
                            // Default
                            float smoothness
                                = 0.33 * smoothstep(0.2, 0.6, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef hardcodedPorosity
                            // Stone-like default: slightly porous so rain
                            // can darken it a touch.
                            material.porosityAmount = 0.15;
#endif
                        } else { // 3
                            // Water
                        }
                    } else { // 2-4
                        if (materialMask == 2u) { // 2
#ifdef hardcodedSss
                            // Small plants
                            material.sssAmount = 0.5;
                            material.sheenAmount = 1.0;
#endif
                        } else { // 3
#ifdef hardcodedSss
                            // Tall plants (lower half)
                            material.sssAmount = 0.5;
                            material.sheenAmount = 1.0;
#endif
                        }
                    }
                } else { // 4-8
                    if (materialMask < 6u) { // 4-6
                        if (materialMask == 4u) { // 4
#ifdef hardcodedSss
                            // Tall plants (upper half)
                            material.sssAmount = 0.5;
                            material.sheenAmount = 1.0;
#endif
                        } else { // 5
// Leaves
#ifdef hardcodedSpecular
                            float smoothness
                                = 0.5 * smoothstep(0.16, 0.5, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.sheenAmount = 0.5;
#endif

#ifdef hardcodedSss
                            material.sssAmount = 1.0;
#endif
                        }
                    } else { // 6-8
                        if (materialMask == 6u) { // 6
#ifdef hardcodedPorosity


                            material.porosityAmount = 0.6;
#endif
                        } else { // 7
// Sand
#ifdef hardcodedSpecular
                            float smoothness
                                = 0.8 * linearStep(0.81, 0.96, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef hardcodedPorosity


                            material.porosityAmount = 0.85;
#endif
                        }
                    }
                }
            } else { // 8-16
                if (materialMask < 12u) { // 8-12
                    if (materialMask < 10u) { // 8-10
                        if (materialMask == 8u) { // 8
// Ice
#ifdef hardcodedSpecular
                            float smoothness
                                = pow4(linearStep(0.4, 0.8, hsv.z)) * 0.6;
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.ssrMultiplier = 1.0;
#endif

#ifdef hardcodedSss
                            // Strong sss
                            material.sssAmount = 0.75;
#endif
                        } else { // 9
// Red sand, birch planks
#ifdef hardcodedSpecular
                            float smoothness
                                = 0.4 * linearStep(0.61, 0.85, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef hardcodedPorosity
                            // Red sand is highly porous; birch planks are
                            // only slightly porous. We pick a middle ground.
                            material.porosityAmount = 0.45;
#endif
                        }
                    } else { // 10-12
                        if (materialMask == 10u) { // 10
// Oak, jungle and acacia planks, granite and diorite
#ifdef hardcodedSpecular
                            float smoothness
                                = 0.5 * linearStep(0.4, 0.8, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef hardcodedPorosity
                            // Planks and soft stone — moderately porous.
                            material.porosityAmount = 0.35;
#endif
                        } else { // 11
// Obsidian, nether bricks
#ifdef hardcodedSpecular
                            float smoothness = linearStep(0.02, 0.4, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.ssrMultiplier = 1.0;
#endif
                        }
                    }
                } else { // 12-16
                    if (materialMask < 14u) { // 12-14
                        if (materialMask == 12u) { // 12
// Metals
#ifdef hardcodedSpecular
                            float smoothness
                                = sqrt(linearStep(0.1, 0.9, hsv.z));
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.04);
                            material.f0 = material.albedo;
                            material.isMetal = true;
                            material.ssrMultiplier = 1.0;
#endif
                        } else { // 13
// Gems
#ifdef hardcodedSpecular
                            float smoothness
                                = sqrt(linearStep(0.1, 0.9, hsv.z));
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.04);
                            material.f0 = vec3(0.25);
                            material.ssrMultiplier = 1.0;
#endif
                        }
                    } else { // 14-16
                        if (materialMask == 14u) { // 14
#ifdef hardcodedSss
                            // Strong sss
                            material.sssAmount = 0.6;
#endif
#ifdef hardcodedPorosity
                            // Snow, sponges and other strong-sss organic
                            // blocks are typically very porous.
                            material.porosityAmount = 0.7;
#endif
                        } else { // 15
#ifdef hardcodedSss
                            // Weak sss
                            material.sssAmount = 0.1;
#endif
#ifdef hardcodedPorosity
                            // Weak-sss organic: mildly porous.
                            material.porosityAmount = 0.3;
#endif
                        }
                    }
                }
            }
        } else { // 16-32
            if (materialMask < 24u) { // 16-24
                if (materialMask < 20u) { // 16-20
                    if (materialMask < 18u) { // 16-18
                        if (materialMask == 16u) { // 16
#ifdef hardcodedEmission
                            // Chorus plant
                            material.emission
                                = 0.25 * albedoSqrt * pow4(hsv.z);
#endif
                        } else { // 17
#ifdef hardcodedSpecular
                            // End stone
                            float smoothness
                                = 0.4 * linearStep(0.61, 0.85, hsv.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.ssrMultiplier = 1.0;
#endif
                        }
                    } else { // 18-20
                        if (materialMask == 18u) { // 18
// Metals
#ifdef hardcodedSpecular
                            float smoothness
                                = sqrt(linearStep(0.1, 0.9, hsv.z));
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.04);
                            material.f0 = material.albedo;
                            material.isMetal = true;
                            material.ssrMultiplier = 1.0;
#endif
                        } else { // 19
// Warped stem
#ifdef hardcodedEmission
                            float emissionAmount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(blockPos.yz, 1.0 - blockPos.yz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.x))
                            );
                            float blue = isolateHue(hsv, 200.0, 60.0);
                            material.emission
                                = albedoSqrt * hsv.y * blue * emissionAmount;
#endif
                        }
                    }
                } else { // 20-24
                    if (materialMask < 22u) { // 20-22
                        if (materialMask == 20u) { // 20
// Warped stem
#ifdef hardcodedEmission
                            float emissionAmount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(blockPos.xz, 1.0 - blockPos.xz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.y))
                            );
                            float blue = isolateHue(hsv, 200.0, 60.0);
                            material.emission
                                = albedoSqrt * hsv.y * blue * emissionAmount;
#endif
                        } else { // 21
// Warped stem
#ifdef hardcodedEmission
                            float emissionAmount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(blockPos.xy, 1.0 - blockPos.xy),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.z))
                            );
                            float blue = isolateHue(hsv, 200.0, 60.0);
                            material.emission
                                = albedoSqrt * hsv.y * blue * emissionAmount;
#endif
                        }
                    } else { // 22-24
                        if (materialMask == 22u) { // 22
// Warped hyphae
#ifdef hardcodedEmission
                            float blue = isolateHue(hsv, 200.0, 60.0);
                            material.emission = albedoSqrt * hsv.y * blue;
#endif
                        } else { // 23
// Crimson stem
#ifdef hardcodedEmission
                            float emissionAmount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(blockPos.yz, 1.0 - blockPos.yz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.x))
                            );
                            material.emission = albedoSqrt
                                * linearStep(0.33, 0.5, hsv.z)
                                * emissionAmount;
#endif
                        }
                    }
                }
            } else { // 24-32
                if (materialMask < 28u) { // 24-28
                    if (materialMask < 26u) { // 24-26
                        if (materialMask == 24u) { // 24
// Crimson stem
#ifdef hardcodedEmission
                            float emissionAmount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(blockPos.xz, 1.0 - blockPos.xz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.y))
                            );
                            material.emission = albedoSqrt
                                * linearStep(0.33, 0.5, hsv.z)
                                * emissionAmount;
#endif
                        } else { // 25
// Crimson stem
#ifdef hardcodedEmission
                            float emissionAmount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(blockPos.xy, 1.0 - blockPos.xy),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.z))
                            );
                            material.emission = albedoSqrt
                                * linearStep(0.33, 0.5, hsv.z)
                                * emissionAmount;
#endif
                        }
                    } else { // 26-28
                        if (materialMask == 26u) { // 26
// Crimson hyphae
#ifdef hardcodedEmission
                            material.emission
                                = albedoSqrt * linearStep(0.33, 0.5, hsv.z);
#endif
                        } else { // 27
// Copper
#ifdef hardcodedSpecular
                            vec3 hsv = rgbToHsv(albedoSrgb);

                            material.roughness = 0.5;
                            material.f0 = vec3(0.01);
                            material.ssrMultiplier = 1.0;

                            // Check oxidized parts (blue-green hues)
                            float isOxidized = step(
                                0.25,
                                max(
                                    isolateHue(hsv, 120.0, 90.0), // Green
                                                                   // range
                                    isolateHue(hsv, 180.0, 60.0) // Blue range
                                )
                            );
                            if (isOxidized > 0.5) {
                                material.roughness = 0.7;
                                material.f0 = vec3(0.015);
                                material.ssrMultiplier = 1.0;
                            }
#endif
                        }
                    }
                } else { // 28-32
                    if (materialMask < 30) { // 28-30
                        if (materialMask == 28u) { // 28
// Copper
#ifdef hardcodedSpecular
                            vec3 hsv = rgbToHsv(albedoSrgb);

                            material.roughness = 0.5;
                            material.f0 = vec3(0.01);
                            material.ssrMultiplier = 1.0;

                            // Check oxidized parts (blue-green hues)
                            float isOxidized = step(
                                0.25,
                                max(
                                    isolateHue(hsv, 120.0, 90.0), // Green
                                                                   // range
                                    isolateHue(hsv, 180.0, 60.0) // Blue range
                                )
                            );
                            if (isOxidized > 0.5) {
                                material.roughness = 0.7;
                                material.f0 = vec3(0.015);
                                material.ssrMultiplier = 1.0;
                            }
#endif
                        } else { // 29
// Wood
#ifdef hardcodedSpecular
                            float smoothness
                                = 0.25 * linearStep(0.4, 0.8, hsv.z);
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.4);
                            material.f0 = vec3(0.03);
#endif
#ifdef hardcodedPorosity
                            // Wood is moderately porous along the grain,
                            // but we use a flat value for simplicity.
                            material.porosityAmount = 0.3;
#endif
                        }
                    } else { // 30-32
                        if (materialMask == 30u) { // 30
#ifdef hardcodedSpecular
                            float smoothness
                                = 0.25 * linearStep(0.4, 0.8, hsv.z);
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.4);
                            material.f0 = vec3(0.03);
#endif
#ifdef hardcodedPorosity
                            // Wood-derived (signs etc.) — same porosityAmount
                            // family as logs.
                            material.porosityAmount = 0.3;
#endif
                        } else { // 31
                        }
                    }
                }
            }
        }
    } else if (materialMask < 64u) { // 32-64
        if (materialMask < 48u) { // 32-48
            if (materialMask < 40u) { // 32-40
                if (materialMask < 36u) { // 32-36
                    if (materialMask < 34u) { // 32-34
                        if (materialMask == 32u) { // 32
#ifdef hardcodedEmission
                            // Strong white light
                            material.emission = 1.00 * albedoSqrt
                                * (0.1 + 0.9 * cube(hsv.z));
#endif
                        } else { // 33
#ifdef hardcodedEmission
                            // Medium white light
                            material.emission = 0.66 * albedoSqrt
                                * linearStep(0.75, 0.9, hsv.z);
#endif
                        }
                    } else { // 34-36
                        if (materialMask == 34u) { // 34
#ifdef hardcodedEmission
                            // Weak white light
                            material.emission
                                = 0.2 * albedoSqrt * (0.1 + 0.9 * pow4(hsv.z));
#endif
                        } else { // 35
#ifdef hardcodedEmission
                            // Strong golden light
                            material.emission = 0.85 * albedoSqrt * hsv.z
                                * linearStep(0.4,
                                              0.6,
                                              0.2 * hsv.y + 0.55 * hsv.z);
#endif
                        }
                    }
                } else { // 36-40
                    if (materialMask < 38u) { // 36-38
                        if (materialMask == 36u) { // 36
#ifdef hardcodedEmission
                            // Medium golden light
                            material.emission = 0.85 * albedoSqrt
                                * linearStep(0.78, 0.85, hsv.z);
#endif
                        } else { // 37
#ifdef hardcodedEmission
                            // Weak golden light
                            float blue = isolateHue(hsv, 200.0, 30.0);
                            material.emission = 0.8 * albedoSqrt
                                * linearStep(0.47,
                                              0.50,
                                              0.2 * hsv.y + 0.5 * hsv.z
                                                  + 0.1 * blue);
#endif
                        }
                    } else { // 38-40
                        if (materialMask == 38u) { // 38
#ifdef hardcodedEmission
                            // Redstone components
                            vec3 ap1 = material.albedo * workingToAp1Unlit;
                            float l = 0.5 * (minOf(ap1) + maxOf(ap1));
                            float redness = ap1.r * rcp(max(ap1.g + ap1.b, 1e-4));
                            material.emission = 0.33 * material.albedo
                                * step(0.45, redness * l);
#endif
                        } else { // 39
#ifdef hardcodedEmission
                            // Lava
                            material.emission = 2.0 * albedoSqrt
                                * (0.2 + 0.8 * isolateHue(hsv, 30.0, 15.0))
                                * step(0.4, hsv.y) * hsv.z;
#endif
                        }
                    }
                }
            } else { // 40-48
                if (materialMask < 44u) { // 40-44
                    if (materialMask < 42u) { // 40-42
                        if (materialMask == 40u) { // 40
#ifdef hardcodedEmission
                            // Medium orange emissives
                            material.emission = 0.60 * albedoSqrt
                                * (0.1 + 0.9 * cube(hsv.z));
#endif
                        } else { // 41
#ifdef hardcodedEmission
                            // Brewing stand
                            material.emission = 0.85 * albedoSqrt
                                * linearStep(0.77, 0.85, hsv.z);
#endif
                        }
                    } else { // 42-44
                        if (materialMask == 42u) { // 42
#ifdef hardcodedEmission
                            // Jack o' Lantern
                            material.emission
                                = 0.80 * albedoSqrt * step(0.73, 0.8 * hsv.z);
#endif
                        } else { // 43
#ifdef hardcodedEmission
                            // Soul lights
                            float blue = isolateHue(hsv, 200.0, 30.0);
                            material.emission = 0.66 * albedoSqrt
                                * linearStep(0.8, 1.0, blue + hsv.z);
#endif
                        }
                    }
                } else { // 44-48
                    if (materialMask < 46u) { // 44-46
                        if (materialMask == 44u) { // 44
#ifdef hardcodedEmission
                            // Beacon
                            material.emission = step(0.2, hsv.z) * albedoSqrt
                                * step(maxOf(abs(blockPos - 0.5)), 0.4);
#endif
                        } else { // 45
#ifdef hardcodedEmission
                            // End portal frame
                            material.emission = 0.33 * material.albedo
                                * isolateHue(hsv, 120.0, 50.0);
#endif
                        }
                    } else { // 46-48
                        if (materialMask == 46u) { // 46
#ifdef hardcodedEmission
                            // Sculk
                            material.emission = 0.2 * material.albedo
                                * isolateHue(hsv, 200.0, 40.0)
                                * smoothstep(0.5, 0.7, hsv.z)
                                * (1.0
                                   - linearStep(
                                       0.0,
                                       20.0,
                                       distance(worldPos, cameraPosition)
                                   ));
#endif
                        } else { // 47
#ifdef hardcodedEmission
                            // Pink glow
                            material.emission
                                = vec3(0.75) * isolateHue(hsv, 310.0, 50.0);
#endif
                        }
                    }
                }
            }
        } else { // 48-64
            if (materialMask < 56u) { // 48-56
                if (materialMask < 52u) { // 48-52
                    if (materialMask < 50u) { // 48-50
                        if (materialMask == 48u) { // 48
                            material.emission = 0.5 * albedoSqrt
                                * linearStep(0.5, 0.6, hsv.z);
                        } else { // 49
#ifdef hardcodedEmission
                            // Nether mushrooms
                            material.emission = 0.80 * albedoSqrt
                                * step(0.73, 0.1 * hsv.y + 0.7 * hsv.z);
#endif
                        }
                    } else { // 50-52
                        if (materialMask == 50u) { // 50
#ifdef hardcodedEmission
                            // Candles
                            material.emission
                                = vec3(0.2) * pow4(clamp01(blockPos.y * 2.0));
#endif
                        } else { // 51
#ifdef hardcodedEmission
                            // Ochre froglight
                            material.emission = 0.40 * albedoSqrt
                                * (0.1 + 0.9 * cube(hsv.z));
#endif
                        }
                    }
                } else { // 52-56
                    if (materialMask < 54u) { // 52-54
                        if (materialMask == 52u) { // 52
#ifdef hardcodedEmission
                            // Verdant froglight
                            material.emission = 0.40 * albedoSqrt
                                * (0.1 + 0.9 * cube(hsv.z));
#endif
                        } else { // 53
#ifdef hardcodedEmission
                            // Pearlescent froglight
                            material.emission = 0.40 * albedoSqrt
                                * (0.1 + 0.9 * cube(hsv.z));
#endif
                        }
                    } else { // 54-56
                        if (materialMask == 54u) { // 54
#ifdef hardcodedEmission
                            // Enchanting table
                            material.emission
                                = vec3(0.20) * (0.1 + 0.9 * hsv.z);
#endif
                        } else { // 55
#ifdef hardcodedEmission
                            // Amethyst cluster
                            material.emission
                                = vec3(0.20) * (0.1 + 0.9 * hsv.z);
#endif
                        }
                    }
                }
            } else { // 56-64
                if (materialMask < 60u) { // 56-60
                    if (materialMask < 58u) { // 56-58
                        if (materialMask == 56u) { // 56
#ifdef hardcodedEmission
                            // Calibrated sculk sensor
                            material.emission = 0.2 * material.albedo
                                * isolateHue(hsv, 200.0, 40.0)
                                * smoothstep(0.5, 0.7, hsv.z)
                                * (1.0
                                   - linearStep(
                                       0.0,
                                       20.0,
                                       distance(worldPos, cameraPosition)
                                   ));
                            material.emission += vec3(0.20)
                                * (0.1 + 0.9 * hsv.z)
                                * step(0.5,
                                       isolateHue(hsv, 270.0, 50.0)
                                           + 0.55 * hsv.z);
#endif
                        } else { // 57
#ifdef hardcodedEmission
                            // Active sculk sensor
                            material.emission
                                = vec3(0.20) * (0.1 + 0.9 * hsv.z);
#endif
                        }
                    } else { // 58-60
                        if (materialMask == 58u) { // 58
#ifdef hardcodedEmission
                            // Redstone block
                            material.emission = 0.33 * albedoSqrt;
#endif
                        } else { // 59
                            // Open eyeblossom

#ifdef hardcodedSss
                            material.sssAmount = 0.5;
                            material.sheenAmount = 1.0;
#endif

#ifdef hardcodedEmission
                            // Open eyeblossom
                            material.emission
                                = 0.9 * albedoSqrt * step(0.5, hsv.y);
#endif
                        }
                    }
                } else { // 60-64
                    if (materialMask < 62u) { // 60-62
                        if (materialMask == 60u) { // 60
#ifdef hardcodedEmission


                            material.emission = vec3(0.55, 1.00, 0.70)
                                * linearStep(0.50, 0.70, hsv.z);
#endif
                        } else { // 61
#ifdef hardcodedEmission


                            material.emission = 0.85 * albedoSqrt
                                * linearStep(0.3, 0.7, hsv.z);
#endif
                        }
                    } else { // 62-64
                        if (materialMask == 62u) { // 62
                            // Nether portal: the texture is the glow, so
                            // emit its purple hue (was flat white)
                            material.emission = albedoSqrt;
                        } else { // 63
                            // End portal: near-black starfield, so albedo
                            // alone would go dark — pale starlight instead
                            material.emission = vec3(0.65, 0.85, 1.00);
                        }
                    }
                }
            }
        }
    }

    if (64u <= materialMask && materialMask < 80u) {
// Stained glass, honey and slime
#ifdef hardcodedEmission


        // 80+, handled below by the specular/sss terms, not here.)
        material.emission = albedoSqrt * linearStep(0.40, 0.60, hsv.z);
#endif
#ifdef hardcodedSpecular
        material.f0 = vec3(0.04);
        material.roughness = 0.1;
        material.ssrMultiplier = 1.0;
#endif

#ifdef hardcodedSss
        material.sssAmount = 0.5;
#endif

    }
    // Global curve and intensity are applied when the specular map is decoded.

#ifdef porosity


    material.porosityAmount *= porosityStrength;
#else
    // If the user disables the porosity define, no wetness modulation
    // should happen at all — nuke it to zero.
    material.porosityAmount = 0.0;
#endif

    return material;
}

#endif // INCLUDE_BRDF_MATERIAL
