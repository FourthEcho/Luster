#if !defined INCLUDE_LIGHTING_VOXEL_EMITTER_TABLE
#define INCLUDE_LIGHTING_VOXEL_EMITTER_TABLE

/*
  ============================================================================
  Voxel-light emitter color + intensity table
  ----------------------------------------------------------------------------
  Mirror of ph_lights.json, hardcoded as a GLSL function so the voxelize
  vertex/fragment shaders can look up the color and intensity for a given
  material_mask (the per-block ID stored in mc_Entity.x - 10000 by
  shadow.vsh / gbuffers_terrain.vsh).

  The ph_lights.json format is:
    STRONG_WHITE_LIGHT_ID `*10032`  -> color #ffffff, intensity 257
    MEDIUM_WHITE_LIGHT_ID `*10033`  -> color #ffffff, intensity 128
    WEAK_WHITE_LIGHT_ID   `*10034`  -> color #ffffff, intensity 10
    STRONG_GOLDEN_LIGHT_ID`*10035`  -> color #ff8c44, intensity 300
    MEDIUM_GOLDEN_LIGHT_ID`*10036`  -> color #ff914c, intensity 171
    WEAK_GOLDEN_LIGHT_ID  `*10037`  -> color #ff914c, intensity 128
    REDSTONE_COMPONENTS_ID`*10038`  -> color #ff2d19, intensity 107
    LAVA_ID               `*10039`  -> color #ff6019, intensity 150
    MEDIUM_ORANGE_LIGHT_ID`*10040`  -> color #ff7219, intensity 193
    BREWING_STAND_ID      `*10041`  -> color #ffa026, intensity 86
    JACK_O_LANTERN_ID     `*10042`  -> color #ff914c, intensity 257 (bright_golden)
    SOUL_LIGHTS_ID        `*10043`  -> color #72baff, intensity 128
    BEACON_ID             `*10044`  -> color #72baff, intensity 300
    END_PORTAL_FRAME_ID   `*10045`  -> color #bfffd3, intensity 21
    SCULK_ID              `*10046`  -> color #bfffd3, intensity 64
    PINK_GLOW_ID          `*10047`  -> color #9919ff, intensity 53
    SEA_PICKLE_ID         `*10048`  -> color #bfff7f, intensity 21
    NETHER_PLANTS_ID      `*10049`  -> color #ff7f3f, intensity 86
    CANDLES_ID            `*10050`  -> color #ff914c, intensity 171
    OCHRE_FROGLIGHT_ID    `*10051`  -> color #ffa54c, intensity 171
    VERDANT_FROGLIGHT_ID  `*10052`  -> color #dbff70, intensity 171
    PEARLESCENT_FROGLIGHT_ID`*10053`-> color #bf70ff, intensity 171
    ENCHANTING_TABLE_ID   `*10054`  -> color #9919ff, intensity 43
    AMETHYST_CLUSTER_ID   `*10055`  -> color #bf70ff, intensity 86
    CALIBRATED_SCULK_SENSOR_ID`*10056` -> color #bf70ff, intensity 86
    ACTIVE_SCULK_SENSOR_ID`*10057`  -> color #bfffd3, intensity 128
    REDSTONE_BLOCK_ID     `*10058`  -> color #ff2d19, intensity 71
    OPEN_EYEBLOSSOM_ID    `*10059`  -> color #ff7f3f, intensity 64
    COPPER_LIGHTS_ID      `*10060`  -> color #a6fec4, intensity 83
    COPPER_BULBS_ID       `*10061`  -> color #ff914c, intensity 171
    NETHER_PORTAL_ID      `*10062`  -> color #9919ff, intensity 257
    END_PORTAL_ID         `*10063`  -> (none in table; treat as no emission)

  Hex colors are decoded to linear RGB by dividing by 255 and applying
  sRGB EOTF.  Intensity is normalized by 256 so a value of 257 maps to ~1.0.

  Returns vec3(0) if the material_mask is not in the emitter range.
  ============================================================================
*/

const uint VOXEL_EMITTER_MASK_MIN = 32u;  // mc_Entity.x == 10032
const uint VOXEL_EMITTER_MASK_MAX = 63u;  // mc_Entity.x == 10063

bool is_voxel_emitter(uint material_mask) {
    return material_mask >= VOXEL_EMITTER_MASK_MIN
        && material_mask <= VOXEL_EMITTER_MASK_MAX;
}

// sRGB 0..255 -> linear 0..1
vec3 srgb255_to_linear(vec3 c) {
    vec3 s = c * rcp(255.0);
    return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)),
               step(0.04045, s));
}

// Returns (color * intensity) for the given emitter material_mask, or vec3(0)
// if the mask is not an emitter.  The result is in linear light units
// suitable for additive blending into the voxel atlas.
vec3 get_voxel_emitter_radiance(uint material_mask) {
    vec3 color = vec3(0.0);
    float intensity = 0.0;

    switch (material_mask) {
        case 32u: color = vec3(255.0, 255.0, 255.0); intensity = 257.0; break; // strong_white
        case 33u: color = vec3(255.0, 255.0, 255.0); intensity = 128.0; break; // medium_white
        case 34u: color = vec3(255.0, 255.0, 255.0); intensity =  10.0; break; // weak_white
        case 35u: color = vec3(255.0, 140.0,  68.0); intensity = 300.0; break; // strong_golden
        case 36u: color = vec3(255.0, 145.0,  76.0); intensity = 171.0; break; // medium_golden
        case 37u: color = vec3(255.0, 145.0,  76.0); intensity = 128.0; break; // weak_golden
        case 38u: color = vec3(255.0,  45.0,  25.0); intensity = 107.0; break; // redstone_components
        case 39u: color = vec3(255.0,  96.0,  25.0); intensity = 150.0; break; // lava
        case 40u: color = vec3(255.0, 114.0,  25.0); intensity = 193.0; break; // medium_orange
        case 41u: color = vec3(255.0, 160.0,  38.0); intensity =  86.0; break; // brewing_stand
        case 42u: color = vec3(255.0, 145.0,  76.0); intensity = 257.0; break; // jack_o_lantern (bright_golden)
        case 43u: color = vec3(114.0, 186.0, 255.0); intensity = 128.0; break; // soul_lights
        case 44u: color = vec3(114.0, 186.0, 255.0); intensity = 300.0; break; // beacon
        case 45u: color = vec3(191.0, 255.0, 211.0); intensity =  21.0; break; // end_portal_frame
        case 46u: color = vec3(191.0, 255.0, 211.0); intensity =  64.0; break; // sculk
        case 47u: color = vec3(153.0,  25.0, 255.0); intensity =  53.0; break; // pink_glow
        case 48u: color = vec3(191.0, 255.0, 127.0); intensity =  21.0; break; // sea_pickle
        case 49u: color = vec3(255.0, 127.0,  63.0); intensity =  86.0; break; // nether_plants
        case 50u: color = vec3(255.0, 145.0,  76.0); intensity = 171.0; break; // candles (uses medium_golden)
        case 51u: color = vec3(255.0, 165.0,  76.0); intensity = 171.0; break; // ochre_froglight
        case 52u: color = vec3(219.0, 255.0, 112.0); intensity = 171.0; break; // verdant_froglight
        case 53u: color = vec3(191.0, 112.0, 255.0); intensity = 171.0; break; // pearlescent_froglight
        case 54u: color = vec3(153.0,  25.0, 255.0); intensity =  43.0; break; // enchanting_table
        case 55u: color = vec3(191.0, 112.0, 255.0); intensity =  86.0; break; // amethyst_cluster
        case 56u: color = vec3(191.0, 112.0, 255.0); intensity =  86.0; break; // calibrated_sculk_sensor
        case 57u: color = vec3(191.0, 255.0, 211.0); intensity = 128.0; break; // active_sculk_sensor
        case 58u: color = vec3(255.0,  45.0,  25.0); intensity =  71.0; break; // redstone_block
        case 59u: color = vec3(255.0, 127.0,  63.0); intensity =  64.0; break; // open_eyeblossom
        case 60u: color = vec3(166.0, 254.0, 196.0); intensity =  83.0; break; // copper_lights
        case 61u: color = vec3(255.0, 145.0,  76.0); intensity = 171.0; break; // copper_bulbs
        case 62u: color = vec3(153.0,  25.0, 255.0); intensity = 257.0; break; // nether_portal
        default:  return vec3(0.0);  // 63 (end_portal) and non-emitters
    }

    return srgb255_to_linear(color) * (intensity * rcp(256.0));
}

#endif // INCLUDE_LIGHTING_VOXEL_EMITTER_TABLE
