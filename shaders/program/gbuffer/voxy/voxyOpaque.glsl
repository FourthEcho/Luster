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
#include "/lib/util/encoding.glsl"

layout(location = 0) out vec4 gbuffer_data_0;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    // Get base properties

    vec3 base_color = parameters.sampledColour.rgb * parameters.tinting.rgb;

    // from Cortex
    vec3 normal = vec3(
                      uint((parameters.face >> 1) == 2),
                      uint((parameters.face >> 1) == 0),
                      uint((parameters.face >> 1) == 1)
                  )
        * (float(int(parameters.face) & 1) * 2.0 - 1.0);

    uint material_mask = max(parameters.customId - 10000u, 0u);

    // Encode gbuffer data

    gbuffer_data_0.x = pack_unorm_2x8(base_color.rg);
    gbuffer_data_0.y = pack_unorm_2x8(
        base_color.b,
        clamp01(float(material_mask) * rcp(255.0))
    );
    gbuffer_data_0.z = pack_unorm_2x8(encode_unit_vector(normal));
    gbuffer_data_0.w = pack_unorm_2x8(parameters.lightMap);
}
