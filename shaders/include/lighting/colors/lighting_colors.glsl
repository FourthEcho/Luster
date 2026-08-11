#if !defined INCLUDE_LIGHTING_COLORS_LIGHTING_COLORS
#define INCLUDE_LIGHTING_COLORS_LIGHTING_COLORS

#include "/include/utility/color.glsl"

// Built-in color mapping for handheld lighting (HANDHELD_LIGHTING_MODE
// HANDHELD_LIGHTING_COLORED). The item IDs below are the custom item IDs
// assigned in item.properties (10032-10063). Colors and intensities match the
// default lights in ph_lights.json, so handheld lighting stays consistent with
// the flood fill colored lighting without requiring the Colored Lights mod.
//
// To customize the colors or brightnesses, edit the tables below. Colors are
// stored in sRGB and are converted to working color space at lookup time;
// brightnesses are the light intensities from ph_lights.json scaled to [0, 1].

const vec3 lighting_colors[32] = vec3[32](
    vec3(1.000, 1.000, 1.000), // 10032 Strong white light - sea lantern, nether star
    vec3(1.000, 1.000, 1.000), // 10033 Medium white light - end rod
    vec3(1.000, 1.000, 1.000), // 10034 Weak white light - glow lichen
    vec3(1.000, 0.549, 0.267), // 10035 Strong golden light - glowstone, lantern
    vec3(1.000, 0.569, 0.298), // 10036 Medium golden light - torch, campfire
    vec3(1.000, 0.569, 0.298), // 10037 Weak golden light - glow berries
    vec3(1.000, 0.176, 0.098), // 10038 Redstone components - redstone torch
    vec3(1.000, 0.376, 0.098), // 10039 Lava - lava bucket
    vec3(1.000, 0.447, 0.098), // 10040 Medium orange light - fire, shroomlight
    vec3(1.000, 0.627, 0.149), // 10041 Brewing stand
    vec3(1.000, 0.569, 0.298), // 10042 Bright golden light - jack o' lantern
    vec3(0.447, 0.729, 1.000), // 10043 Soul lights - soul fire, soul torch
    vec3(0.447, 0.729, 1.000), // 10044 Beacon
    vec3(0.749, 1.000, 0.827), // 10045 End portal frame - ender eye
    vec3(0.749, 1.000, 0.827), // 10046 Sculk - sculk, sculk sensor, catalyst
    vec3(0.600, 0.098, 1.000), // 10047 Pink glow - spawner, dragon head
    vec3(0.749, 1.000, 0.498), // 10048 Sea pickle
    vec3(1.000, 0.498, 0.247), // 10049 Nether plants - crimson/warped fungus
    vec3(1.000, 0.569, 0.298), // 10050 Candles
    vec3(1.000, 0.647, 0.298), // 10051 Ochre froglight
    vec3(0.859, 1.000, 0.439), // 10052 Verdant froglight
    vec3(0.749, 0.439, 1.000), // 10053 Pearlescent froglight
    vec3(0.600, 0.098, 1.000), // 10054 Enchanting table
    vec3(0.749, 0.439, 1.000), // 10055 Amethyst cluster
    vec3(0.749, 0.439, 1.000), // 10056 Calibrated sculk sensor
    vec3(0.749, 1.000, 0.827), // 10057 Active sculk sensor
    vec3(1.000, 0.176, 0.098), // 10058 Redstone block
    vec3(1.000, 0.498, 0.247), // 10059 Open eyeblossom
    vec3(0.651, 0.996, 0.769), // 10060 Copper torch, copper lanterns
    vec3(1.000, 0.569, 0.298), // 10061 Copper bulbs
    vec3(0.600, 0.098, 1.000), // 10062 Nether portal
    vec3(1.000, 1.000, 1.000)  // 10063 End portal, end gateway
);

const float lighting_brightnesses[32] = float[32](
    1.000, // 10032 Strong white light
    0.502, // 10033 Medium white light
    0.039, // 10034 Weak white light
    1.000, // 10035 Strong golden light
    0.671, // 10036 Medium golden light
    0.502, // 10037 Weak golden light
    0.420, // 10038 Redstone components
    0.588, // 10039 Lava
    0.757, // 10040 Medium orange light
    0.337, // 10041 Brewing stand
    1.000, // 10042 Bright golden light
    0.502, // 10043 Soul lights
    1.000, // 10044 Beacon
    0.082, // 10045 End portal frame
    0.251, // 10046 Sculk
    0.208, // 10047 Pink glow
    0.082, // 10048 Sea pickle
    0.337, // 10049 Nether plants
    0.671, // 10050 Candles
    0.671, // 10051 Ochre froglight
    0.671, // 10052 Verdant froglight
    0.671, // 10053 Pearlescent froglight
    0.169, // 10054 Enchanting table
    0.337, // 10055 Amethyst cluster
    0.337, // 10056 Calibrated sculk sensor
    0.502, // 10057 Active sculk sensor
    0.278, // 10058 Redstone block
    0.251, // 10059 Open eyeblossom
    0.325, // 10060 Copper torch, copper lanterns
    0.671, // 10061 Copper bulbs
    1.000, // 10062 Nether portal
    1.000  // 10063 End portal, end gateway
);

float get_lighting_brightness(int item_id) {
    int index = item_id - 10032;
    if (index < 0 || index >= 32) {
        return 0.0;
    }
    return lighting_brightnesses[index];
}

vec3 get_lighting_color(int item_id) {
    int index = item_id - 10032;
    if (index < 0 || index >= 32) {
        return vec3(0.0);
    }
    return from_srgb(lighting_colors[index]);
}

#endif // INCLUDE_LIGHTING_COLORS_LIGHTING_COLORS
