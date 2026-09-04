#if !defined INCLUDE_MISC_MATERIAL
#define INCLUDE_MISC_MATERIAL

#include "/include/post_processing/aces/matrices.glsl"
#include "/include/utility/color.glsl"

const float air_n = 1.000293; // for 0°C and 1 atm
const float water_n = 1.333; // for 20°C

struct Material {
    vec3 albedo;
    vec3 emission;
    vec3 f0;
    vec3 f82; // hardcoded metals only
    float roughness;
    float sss_amount;
    float sheen_amount; // SSS "sheen" for tall grass
    float porosity;
    float ssr_multiplier;
    bool is_metal;
    bool is_hardcoded_metal;
};

const Material water_material = Material(
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

#if TEXTURE_FORMAT == TEXTURE_FORMAT_LAB
void decode_specular_map(vec4 specular_map, inout Material material) {
    // Measured complex refractive indices (n, k) for hardcoded metals.
    // n = real part (stored in f0), k = extinction coefficient (stored in f82).
    // Values sampled at sRGB primaries (R≈700nm, G≈546nm, B≈436nm).
    // Sources: Palik "Handbook of Optical Constants", refractiveindex.info.
    const vec3[] metal_n = vec3[](
        vec3(2.9114, 2.9497, 2.7743), // Iron
        vec3(0.1431, 0.3740, 1.4400), // Gold
        vec3(1.0970, 0.8795, 0.5237), // Aluminum
        vec3(3.1071, 3.1812, 2.3230), // Chrome
        vec3(0.2140, 0.9300, 1.1000), // Copper
        vec3(1.9100, 1.8300, 1.4400), // Lead
        vec3(2.3757, 2.0847, 1.8453), // Platinum
        vec3(0.1550, 0.1160, 0.1390)  // Silver
    );
    const vec3[] metal_k = vec3[](
        vec3(3.0893, 2.9318, 2.7670), // Iron
        vec3(3.9800, 2.3880, 1.6030), // Gold
        vec3(6.7942, 6.2875, 5.3000), // Aluminum
        vec3(3.3314, 3.3291, 3.1350), // Chrome
        vec3(3.9100, 2.5900, 2.3600), // Copper
        vec3(3.5100, 3.4000, 3.1800), // Lead
        vec3(4.2655, 3.7153, 3.1365), // Platinum
        vec3(4.8200, 3.1160, 2.1440)  // Silver
    );

    material.roughness = sqr(1.0 - specular_map.r);

    // ---- Emission ----
    // labPBR encodes emission strength in the specular alpha channel.
    // Convention used by resource packs:
    //   alpha == 1.0  -> this texel has no labPBR emission data
    //                    (fall back to whatever the hardcoded mask set)
    //   alpha <  1.0  -> emission multiplier, brightness = albedo * alpha
    // When the texel declares an emission multiplier it overrides the
    // hardcoded emission rather than combining with it, so a resource pack
    // can fully describe its own emissive surfaces. EMISSION_STRENGTH has
    // already been applied to the hardcoded emission inside material_from,
    // so we apply it to the map emission too here.
    float has_emission_map = step(specular_map.a, 254.5 / 255.0);
    // labPBR 1.3: alpha 1/255..254/255 encodes emission; remap to 0..1
    float emission_value = (specular_map.a * 255.0 - 1.0) / 254.0;
    vec3 map_emission = material.albedo * emission_value * EMISSION_STRENGTH;
    material.emission = mix(
        material.emission,
        map_emission,
        has_emission_map
    );

    if (specular_map.g < 229.5 / 255.0) {
        // Dielectrics
        material.f0 = max(material.f0, specular_map.g);

        // ---- SSS (Subsurface Scattering) ----
        // labPBR stores SSS in the upper half of specular.b (> 64/255).
        // We only read it when the SSS master toggle is on — when SSS is
        // off, no map searching and no hardcoded values are used, so
        // sss_amount stays at 0 and no SSS rendering happens.
#ifdef SSS
        float has_sss = step(64.5 / 255.0, specular_map.b);
        material.sss_amount = max(
            material.sss_amount,
            linear_step(64.0 / 255.0, 1.0, specular_map.b * has_sss)
        );
#else
        // SSS off: has_sss is always 0 so the porosity calculation below
        // uses the full specular.b range (no SSS region to subtract).
        const float has_sss = 0.0;
#endif

        // ---- Porosity ----
        // labPBR stores porosity in the lower half of specular.b
        // (0..64/255). When a non-zero B channel is present at this texel
        // we trust the pack and let it fully override the hardcoded mask
        // porosity. POROSITY_STRENGTH is applied to the map value so the
        // user can globally tame the effect.
#ifdef POROSITY
        float map_porosity = linear_step(
            0.0,
            64.0 / 255.0,
            max0(specular_map.b - specular_map.b * has_sss)
        );
        // Detect "this texel actually carries labPBR data" (B != 0)
        // vs "vanilla texture with B == 0" (fall back to hardcoded).
        float has_porosity_data = step(0.5 / 255.0, specular_map.b);
        material.porosity = mix(
            material.porosity,
            map_porosity * POROSITY_STRENGTH,
            has_porosity_data
        );
#endif
    } else if (specular_map.g < 237.5 / 255.0) {
        // Hardcoded metals
        uint metal_id = clamp(uint(255.0 * specular_map.g) - 230u, 0u, 7u);

        material.f0 = metal_n[metal_id];
        material.f82 = metal_k[metal_id];
        material.is_metal = true;
        material.is_hardcoded_metal = true;
    } else {
        // Albedo metal
        material.f0 = material.albedo;
        material.is_metal = true;
    }

    material.ssr_multiplier = step(
        0.01,
        (material.f0.x
         - material.f0.x * material.roughness * SSR_ROUGHNESS_THRESHOLD)
    ); // based on Kneemund's method
}
#elif TEXTURE_FORMAT == TEXTURE_FORMAT_OLD
void decode_specular_map(vec4 specular_map, inout Material material) {
    material.roughness = sqr(1.0 - specular_map.r);
    material.is_metal = specular_map.g > 0.5;
    material.f0 = material.is_metal ? material.albedo : material.f0;

    // Old format encodes emission directly in specular.b. Same override
    // semantics as labPBR: a non-zero emission value from the pack wins
    // over the hardcoded mask emission. EMISSION_STRENGTH has already
    // been applied to the hardcoded emission inside material_from.
    float has_emission_map = step(0.5 / 255.0, specular_map.b);
    vec3 map_emission = material.albedo * specular_map.b * EMISSION_STRENGTH;
    material.emission = mix(
        material.emission,
        map_emission,
        has_emission_map
    );

    material.ssr_multiplier = step(
        0.01,
        (material.f0.x
         - material.f0.x * material.roughness * SSR_ROUGHNESS_THRESHOLD)
    ); // based on Kneemund's method
}
#endif

void decode_specular_map(
    vec4 specular_map,
    inout Material material,
    out bool parallax_shadow
) {
    parallax_shadow = false;
#if defined POM && defined POM_SHADOW
    parallax_shadow = specular_map.a >= 0.5;
    specular_map.a = fract(specular_map.a * 2.0);
#endif
    decode_specular_map(specular_map, material);
}

Material material_from(
    vec3 albedo_srgb,
    uint material_mask,
    vec3 world_pos,
    vec3 normal,
    inout vec2 light_levels
) {
    vec3 block_pos = fract(world_pos);

    // Create material with default values

    Material material;
    material.albedo = srgb_eotf_inv(albedo_srgb) * rec709_to_rec2020;
    material.emission = vec3(0.0);
    material.f0 = vec3(0.02);
    material.f82 = vec3(0.0);
    material.roughness = 1.0;
    material.sss_amount = 0.0;
    material.sheen_amount = 0.0;
    material.porosity = 0.0;
    material.ssr_multiplier = 0.0;
    material.is_metal = false;
    material.is_hardcoded_metal = false;

    // Hardcoded materials for specific blocks
    // Using binary split search to minimise branches per fragment (TODO:
    // measure impact)

    vec3 hsl = rgb_to_hsl(albedo_srgb);
    vec3 albedo_sqrt = sqrt(material.albedo);

    if (material_mask < 32u) { // 0-32
        if (material_mask < 16u) { // 0-16
            if (material_mask < 8u) { // 0-8
                if (material_mask < 4u) { // 0-4
                    if (material_mask < 2u) { // 0-2
                        if (material_mask == 0u) { // 2
#ifdef HARDCODED_SPECULAR
                            // Default
                            float smoothness
                                = 0.33 * smoothstep(0.2, 0.6, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef POROSITY
                            // Stone-like default: slightly porous so rain
                            // can darken it a touch.
                            material.porosity = 0.15;
#endif
                        } else { // 3
                            // Water
                        }
                    } else { // 2-4
                        if (material_mask == 2u) { // 2
#ifdef HARDCODED_SSS
                            // Small plants
                            material.sss_amount = 0.5;
                            material.sheen_amount = 1.0;
#endif
                        } else { // 3
#ifdef HARDCODED_SSS
                            // Tall plants (lower half)
                            material.sss_amount = 0.5;
                            material.sheen_amount = 1.0;
#endif
                        }
                    }
                } else { // 4-8
                    if (material_mask < 6u) { // 4-6
                        if (material_mask == 4u) { // 4
#ifdef HARDCODED_SSS
                            // Tall plants (upper half)
                            material.sss_amount = 0.5;
                            material.sheen_amount = 1.0;
#endif
                        } else { // 5
// Leaves
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = 0.5 * smoothstep(0.16, 0.5, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.sheen_amount = 0.5;
#endif

#ifdef HARDCODED_SSS
                            material.sss_amount = 1.0;
#endif
                        }
                    } else { // 6-8
                        if (material_mask == 6u) { // 6
#ifdef POROSITY
                            // Ground / dirt-like (coarse dirt, podzol,
                            // rooted dirt, etc.). Noticeably porous so rain
                            // puddles here darken heavily and the surface
                            // stays wet longer.
                            material.porosity = 0.6;
#endif
                        } else { // 7
// Sand
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = 0.8 * linear_step(0.81, 0.96, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef POROSITY
                            // Sand & sandstone are very porous — water
                            // percolates through them easily. Puddles will
                            // hardly form, instead the surface darkens.
                            material.porosity = 0.85;
#endif
                        }
                    }
                }
            } else { // 8-16
                if (material_mask < 12u) { // 8-12
                    if (material_mask < 10u) { // 8-10
                        if (material_mask == 8u) { // 8
// Ice
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = pow4(linear_step(0.4, 0.8, hsl.z)) * 0.6;
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.ssr_multiplier = 1.0;
#endif

#ifdef HARDCODED_SSS
                            // Strong SSS
                            material.sss_amount = 0.75;
#endif
                        } else { // 9
// Red sand, birch planks
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = 0.4 * linear_step(0.61, 0.85, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef POROSITY
                            // Red sand is highly porous; birch planks are
                            // only slightly porous. We pick a middle ground.
                            material.porosity = 0.45;
#endif
                        }
                    } else { // 10-12
                        if (material_mask == 10u) { // 10
// Oak, jungle and acacia planks, granite and diorite
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = 0.5 * linear_step(0.4, 0.8, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
#endif
#ifdef POROSITY
                            // Planks and soft stone — moderately porous.
                            material.porosity = 0.35;
#endif
                        } else { // 11
// Obsidian, nether bricks
#ifdef HARDCODED_SPECULAR
                            float smoothness = linear_step(0.02, 0.4, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.ssr_multiplier = 1.0;
#endif
                        }
                    }
                } else { // 12-16
                    if (material_mask < 14u) { // 12-14
                        if (material_mask == 12u) { // 12
// Metals
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = sqrt(linear_step(0.1, 0.9, hsl.z));
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.04);
                            material.f0 = material.albedo;
                            material.is_metal = true;
                            material.ssr_multiplier = 1.0;
#endif
                        } else { // 13
// Gems
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = sqrt(linear_step(0.1, 0.9, hsl.z));
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.04);
                            material.f0 = vec3(0.25);
                            material.ssr_multiplier = 1.0;
#endif
                        }
                    } else { // 14-16
                        if (material_mask == 14u) { // 14
#ifdef HARDCODED_SSS
                            // Strong SSS
                            material.sss_amount = 0.6;
#endif
#ifdef POROSITY
                            // Snow, sponges and other strong-SSS organic
                            // blocks are typically very porous.
                            material.porosity = 0.7;
#endif
                        } else { // 15
#ifdef HARDCODED_SSS
                            // Weak SSS
                            material.sss_amount = 0.1;
#endif
#ifdef POROSITY
                            // Weak-SSS organic: mildly porous.
                            material.porosity = 0.3;
#endif
                        }
                    }
                }
            }
        } else { // 16-32
            if (material_mask < 24u) { // 16-24
                if (material_mask < 20u) { // 16-20
                    if (material_mask < 18u) { // 16-18
                        if (material_mask == 16u) { // 16
#ifdef HARDCODED_EMISSION
                            // Chorus plant
                            material.emission
                                = 0.25 * albedo_sqrt * pow4(hsl.z);
#endif
                        } else { // 17
#ifdef HARDCODED_SPECULAR
                            // End stone
                            float smoothness
                                = 0.4 * linear_step(0.61, 0.85, hsl.z);
                            material.roughness = sqr(1.0 - smoothness);
                            material.f0 = vec3(0.02);
                            material.ssr_multiplier = 1.0;
#endif
                        }
                    } else { // 18-20
                        if (material_mask == 18u) { // 18
// Metals
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = sqrt(linear_step(0.1, 0.9, hsl.z));
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.04);
                            material.f0 = material.albedo;
                            material.is_metal = true;
                            material.ssr_multiplier = 1.0;
#endif
                        } else { // 19
// Warped stem
#ifdef HARDCODED_EMISSION
                            float emission_amount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(block_pos.yz, 1.0 - block_pos.yz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.x))
                            );
                            float blue = isolate_hue(hsl, 200.0, 60.0);
                            material.emission
                                = albedo_sqrt * hsl.y * blue * emission_amount;
#endif
                        }
                    }
                } else { // 20-24
                    if (material_mask < 22u) { // 20-22
                        if (material_mask == 20u) { // 20
// Warped stem
#ifdef HARDCODED_EMISSION
                            float emission_amount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(block_pos.xz, 1.0 - block_pos.xz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.y))
                            );
                            float blue = isolate_hue(hsl, 200.0, 60.0);
                            material.emission
                                = albedo_sqrt * hsl.y * blue * emission_amount;
#endif
                        } else { // 21
// Warped stem
#ifdef HARDCODED_EMISSION
                            float emission_amount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(block_pos.xy, 1.0 - block_pos.xy),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.z))
                            );
                            float blue = isolate_hue(hsl, 200.0, 60.0);
                            material.emission
                                = albedo_sqrt * hsl.y * blue * emission_amount;
#endif
                        }
                    } else { // 22-24
                        if (material_mask == 22u) { // 22
// Warped hyphae
#ifdef HARDCODED_EMISSION
                            float blue = isolate_hue(hsl, 200.0, 60.0);
                            material.emission = albedo_sqrt * hsl.y * blue;
#endif
                        } else { // 23
// Crimson stem
#ifdef HARDCODED_EMISSION
                            float emission_amount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(block_pos.yz, 1.0 - block_pos.yz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.x))
                            );
                            material.emission = albedo_sqrt
                                * linear_step(0.33, 0.5, hsl.z)
                                * emission_amount;
#endif
                        }
                    }
                }
            } else { // 24-32
                if (material_mask < 28u) { // 24-28
                    if (material_mask < 26u) { // 24-26
                        if (material_mask == 24u) { // 24
// Crimson stem
#ifdef HARDCODED_EMISSION
                            float emission_amount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(block_pos.xz, 1.0 - block_pos.xz),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.y))
                            );
                            material.emission = albedo_sqrt
                                * linear_step(0.33, 0.5, hsl.z)
                                * emission_amount;
#endif
                        } else { // 25
// Crimson stem
#ifdef HARDCODED_EMISSION
                            float emission_amount = mix(
                                1.0,
                                float(any(lessThan(
                                    vec4(block_pos.xy, 1.0 - block_pos.xy),
                                    vec4(rcp(16.0) - 1e-3)
                                ))),
                                step(0.5, abs(normal.z))
                            );
                            material.emission = albedo_sqrt
                                * linear_step(0.33, 0.5, hsl.z)
                                * emission_amount;
#endif
                        }
                    } else { // 26-28
                        if (material_mask == 26u) { // 26
// Crimson hyphae
#ifdef HARDCODED_EMISSION
                            material.emission
                                = albedo_sqrt * linear_step(0.33, 0.5, hsl.z);
#endif
                        } else { // 27
// Copper
#ifdef HARDCODED_SPECULAR
                            vec3 hsl = rgb_to_hsl(albedo_srgb);

                            material.roughness = 0.5;
                            material.f0 = vec3(0.01);
                            material.ssr_multiplier = 1.0;

                            // Check oxidized parts (blue-green hues)
                            float is_oxidized = step(
                                0.25,
                                max(
                                    isolate_hue(hsl, 120.0, 90.0), // Green
                                                                   // range
                                    isolate_hue(hsl, 180.0, 60.0) // Blue range
                                )
                            );
                            if (is_oxidized > 0.5) {
                                material.roughness = 0.7;
                                material.f0 = vec3(0.015);
                                material.ssr_multiplier = 1.0;
                            }
#endif
                        }
                    }
                } else { // 28-32
                    if (material_mask < 30) { // 28-30
                        if (material_mask == 28u) { // 28
// Copper
#ifdef HARDCODED_SPECULAR
                            vec3 hsl = rgb_to_hsl(albedo_srgb);

                            material.roughness = 0.5;
                            material.f0 = vec3(0.01);
                            material.ssr_multiplier = 1.0;

                            // Check oxidized parts (blue-green hues)
                            float is_oxidized = step(
                                0.25,
                                max(
                                    isolate_hue(hsl, 120.0, 90.0), // Green
                                                                   // range
                                    isolate_hue(hsl, 180.0, 60.0) // Blue range
                                )
                            );
                            if (is_oxidized > 0.5) {
                                material.roughness = 0.7;
                                material.f0 = vec3(0.015);
                                material.ssr_multiplier = 1.0;
                            }
#endif
                        } else { // 29
// Wood
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = 0.25 * linear_step(0.4, 0.8, hsl.z);
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.4);
                            material.f0 = vec3(0.03);
#endif
#ifdef POROSITY
                            // Wood is moderately porous along the grain,
                            // but we use a flat value for simplicity.
                            material.porosity = 0.3;
#endif
                        }
                    } else { // 30-32
                        if (material_mask == 30u) { // 30
#ifdef HARDCODED_SPECULAR
                            float smoothness
                                = 0.25 * linear_step(0.4, 0.8, hsl.z);
                            material.roughness
                                = max(sqr(1.0 - smoothness), 0.4);
                            material.f0 = vec3(0.03);
#endif
#ifdef POROSITY
                            // Wood-derived (signs etc.) — same porosity
                            // family as logs.
                            material.porosity = 0.3;
#endif
                        } else { // 31
                        }
                    }
                }
            }
        }
    } else if (material_mask < 64u) { // 32-64
        if (material_mask < 48u) { // 32-48
            if (material_mask < 40u) { // 32-40
                if (material_mask < 36u) { // 32-36
                    if (material_mask < 34u) { // 32-34
                        if (material_mask == 32u) { // 32
#ifdef HARDCODED_EMISSION
                            // Strong white light
                            material.emission = 1.00 * albedo_sqrt
                                * (0.1 + 0.9 * cube(hsl.z));
#endif
                        } else { // 33
#ifdef HARDCODED_EMISSION
                            // Medium white light
                            material.emission = 0.66 * albedo_sqrt
                                * linear_step(0.75, 0.9, hsl.z);
#endif
                        }
                    } else { // 34-36
                        if (material_mask == 34u) { // 34
#ifdef HARDCODED_EMISSION
                            // Weak white light
                            material.emission
                                = 0.2 * albedo_sqrt * (0.1 + 0.9 * pow4(hsl.z));
#endif
                        } else { // 35
#ifdef HARDCODED_EMISSION
                            // Strong golden light
                            material.emission = 0.85 * albedo_sqrt * hsl.z
                                * linear_step(0.4,
                                              0.6,
                                              0.2 * hsl.y + 0.55 * hsl.z);
#endif
                        }
                    }
                } else { // 36-40
                    if (material_mask < 38u) { // 36-38
                        if (material_mask == 36u) { // 36
#ifdef HARDCODED_EMISSION
                            // Medium golden light
                            material.emission = 0.85 * albedo_sqrt
                                * linear_step(0.78, 0.85, hsl.z);
#endif
                        } else { // 37
#ifdef HARDCODED_EMISSION
                            // Weak golden light
                            float blue = isolate_hue(hsl, 200.0, 30.0);
                            material.emission = 0.8 * albedo_sqrt
                                * linear_step(0.47,
                                              0.50,
                                              0.2 * hsl.y + 0.5 * hsl.z
                                                  + 0.1 * blue);
#endif
                        }
                    } else { // 38-40
                        if (material_mask == 38u) { // 38
#ifdef HARDCODED_EMISSION
                            // Redstone components
                            vec3 ap1 = material.albedo * rec2020_to_ap1_unlit;
                            float l = 0.5 * (min_of(ap1) + max_of(ap1));
                            float redness = ap1.r * rcp(ap1.g + ap1.b);
                            material.emission = 0.33 * material.albedo
                                * step(0.45, redness * l);
#endif
                        } else { // 39
#ifdef HARDCODED_EMISSION
                            // Lava
                            material.emission = 2.0 * albedo_sqrt
                                * (0.2 + 0.8 * isolate_hue(hsl, 30.0, 15.0))
                                * step(0.4, hsl.y) * hsl.z;
#endif
                        }
                    }
                }
            } else { // 40-48
                if (material_mask < 44u) { // 40-44
                    if (material_mask < 42u) { // 40-42
                        if (material_mask == 40u) { // 40
#ifdef HARDCODED_EMISSION
                            // Medium orange emissives
                            material.emission = 0.60 * albedo_sqrt
                                * (0.1 + 0.9 * cube(hsl.z));
#endif
                        } else { // 41
#ifdef HARDCODED_EMISSION
                            // Brewing stand
                            material.emission = 0.85 * albedo_sqrt
                                * linear_step(0.77, 0.85, hsl.z);
#endif
                        }
                    } else { // 42-44
                        if (material_mask == 42u) { // 42
#ifdef HARDCODED_EMISSION
                            // Jack o' Lantern
                            material.emission
                                = 0.80 * albedo_sqrt * step(0.73, 0.8 * hsl.z);
#endif
                        } else { // 43
#ifdef HARDCODED_EMISSION
                            // Soul lights
                            float blue = isolate_hue(hsl, 200.0, 30.0);
                            material.emission = 0.66 * albedo_sqrt
                                * linear_step(0.8, 1.0, blue + hsl.z);
#endif
                        }
                    }
                } else { // 44-48
                    if (material_mask < 46u) { // 44-46
                        if (material_mask == 44u) { // 44
#ifdef HARDCODED_EMISSION
                            // Beacon
                            material.emission = step(0.2, hsl.z) * albedo_sqrt
                                * step(max_of(abs(block_pos - 0.5)), 0.4);
#endif
                        } else { // 45
#ifdef HARDCODED_EMISSION
                            // End portal frame
                            material.emission = 0.33 * material.albedo
                                * isolate_hue(hsl, 120.0, 50.0);
#endif
                        }
                    } else { // 46-48
                        if (material_mask == 46u) { // 46
#ifdef HARDCODED_EMISSION
                            // Sculk
                            material.emission = 0.2 * material.albedo
                                * isolate_hue(hsl, 200.0, 40.0)
                                * smoothstep(0.5, 0.7, hsl.z)
                                * (1.0
                                   - linear_step(
                                       0.0,
                                       20.0,
                                       distance(world_pos, cameraPosition)
                                   ));
#endif
                        } else { // 47
#ifdef HARDCODED_EMISSION
                            // Pink glow
                            material.emission
                                = vec3(0.75) * isolate_hue(hsl, 310.0, 50.0);
#endif
                        }
                    }
                }
            }
        } else { // 48-64
            if (material_mask < 56u) { // 48-56
                if (material_mask < 52u) { // 48-52
                    if (material_mask < 50u) { // 48-50
                        if (material_mask == 48u) { // 48
                            material.emission = 0.5 * albedo_sqrt
                                * linear_step(0.5, 0.6, hsl.z);
                        } else { // 49
#ifdef HARDCODED_EMISSION
                            // Nether mushrooms
                            material.emission = 0.80 * albedo_sqrt
                                * step(0.73, 0.1 * hsl.y + 0.7 * hsl.z);
#endif
                        }
                    } else { // 50-52
                        if (material_mask == 50u) { // 50
#ifdef HARDCODED_EMISSION
                            // Candles
                            material.emission
                                = vec3(0.2) * pow4(clamp01(block_pos.y * 2.0));
#endif
                        } else { // 51
#ifdef HARDCODED_EMISSION
                            // Ochre froglight
                            material.emission = 0.40 * albedo_sqrt
                                * (0.1 + 0.9 * cube(hsl.z));
#endif
                        }
                    }
                } else { // 52-56
                    if (material_mask < 54u) { // 52-54
                        if (material_mask == 52u) { // 52
#ifdef HARDCODED_EMISSION
                            // Verdant froglight
                            material.emission = 0.40 * albedo_sqrt
                                * (0.1 + 0.9 * cube(hsl.z));
#endif
                        } else { // 53
#ifdef HARDCODED_EMISSION
                            // Pearlescent froglight
                            material.emission = 0.40 * albedo_sqrt
                                * (0.1 + 0.9 * cube(hsl.z));
#endif
                        }
                    } else { // 54-56
                        if (material_mask == 54u) { // 54

                        } else { // 55
#ifdef HARDCODED_EMISSION
                            // Amethyst cluster
                            material.emission
                                = vec3(0.20) * (0.1 + 0.9 * hsl.z);
#endif
                        }
                    }
                }
            } else { // 56-64
                if (material_mask < 60u) { // 56-60
                    if (material_mask < 58u) { // 56-58
                        if (material_mask == 56u) { // 56
#ifdef HARDCODED_EMISSION
                            // Calibrated sculk sensor
                            material.emission = 0.2 * material.albedo
                                * isolate_hue(hsl, 200.0, 40.0)
                                * smoothstep(0.5, 0.7, hsl.z)
                                * (1.0
                                   - linear_step(
                                       0.0,
                                       20.0,
                                       distance(world_pos, cameraPosition)
                                   ));
                            material.emission += vec3(0.20)
                                * (0.1 + 0.9 * hsl.z)
                                * step(0.5,
                                       isolate_hue(hsl, 270.0, 50.0)
                                           + 0.55 * hsl.z);
#endif
                        } else { // 57
#ifdef HARDCODED_EMISSION
                            // Active sculk sensor
                            material.emission
                                = vec3(0.20) * (0.1 + 0.9 * hsl.z);
#endif
                        }
                    } else { // 58-60
                        if (material_mask == 58u) { // 58
#ifdef HARDCODED_EMISSION
                            // Redstone block
                            material.emission = 0.33 * albedo_sqrt;
#endif
                        } else { // 59
                            // Open eyeblossom

#ifdef HARDCODED_SSS
                            material.sss_amount = 0.5;
                            material.sheen_amount = 1.0;
#endif

#ifdef HARDCODED_EMISSION
                            // Redstone block
                            material.emission
                                = 0.9 * albedo_sqrt * step(0.5, hsl.y);
#endif
                        }
                    }
                } else { // 60-64
                    if (material_mask < 62u) { // 60-62
                        if (material_mask == 60u) { // 60
#ifdef HARDCODED_EMISSION
                            // Copper torch and lanterns
                            material.emission = 0.05 * albedo_sqrt;
#endif
                        } else { // 61
#ifdef HARDCODED_EMISSION
                            // Medium golden light
                            float orange_yellow = max(
                                isolate_hue(hsl, 30.0, 15.0),
                                max(isolate_hue(hsl, 45.0, 15.0),
                                    isolate_hue(hsl, 60.0, 15.0))
                            );

                            if (orange_yellow > 0.5 && hsl.z > 0.65) {
                                material.emission = 0.85 * albedo_sqrt
                                    * linear_step(0.3, 0.7, hsl.z)
                                    * orange_yellow;
                            } else {
                                material.emission = vec3(0.0);
                            }
#endif
                        }
                    } else { // 62-64
                        if (material_mask == 62u) { // 62
                            // Nether portal
                            material.emission = vec3(1.0);
                        } else { // 63
                            // End portal
                            material.emission = vec3(1.0);
                        }
                    }
                }
            }
        }
    }

    if (64u <= material_mask && material_mask < 80u) {
// Stained glass, honey and slime
#ifdef HARDCODED_SPECULAR
        material.f0 = vec3(0.04);
        material.roughness = 0.1;
        material.ssr_multiplier = 1.0;
#endif

#ifdef HARDCODED_SSS
        material.sss_amount = 0.5;
#endif

#ifdef POROSITY
        // Honey and slime are technically porous in the sense that they
        // absorb water, but for visual puddle purposes they shouldn't
        // darken — leave porosity at 0 for these.
#endif
    }

    // ---- Apply global multipliers to the hardcoded values ----
    // EMISSION_STRENGTH scales the hardcoded mask emission (so the user
    // can globally tame or boost emissive blocks even when no resource
    // pack specular map is bound). When a labPBR specular map is later
    // decoded by decode_specular_map(), the map value will fully override
    // this scaled hardcoded value where the pack declares an emissive
    // texel.
    material.emission *= EMISSION_STRENGTH;

#ifdef POROSITY
    // POROSITY_STRENGTH scales the hardcoded porosity. Same override
    // semantics as above: when a labPBR map declares porosity for a texel
    // it wins over the hardcoded value.
    material.porosity *= POROSITY_STRENGTH;
#else
    // If the user disables the POROSITY define, no wetness modulation
    // should happen at all — nuke it to zero.
    material.porosity = 0.0;
#endif

    return material;
}

#endif // INCLUDE_MISC_MATERIAL
