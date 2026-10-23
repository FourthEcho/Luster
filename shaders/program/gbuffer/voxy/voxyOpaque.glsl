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
#include "/lib/util/encode.glsl"

layout(location = 0) out vec4 gbufferData0;

void voxy_emitFragment(VoxyFragmentParams params) {
    // Get base properties

    vec3 baseColor = params.sampledColour.rgb * params.tinting.rgb;

    // from Cortex
    vec3 normal = vec3(
                      uint((params.face >> 1) == 2),
                      uint((params.face >> 1) == 0),
                      uint((params.face >> 1) == 1)
                  )
        * (float(int(params.face) & 1) * 2.0 - 1.0);

    uint materialMask = max(params.customId - 10000u, 0u);

    // Encode gbuffer data

    gbufferData0.x = packUnorm2x8(baseColor.rg);
    gbufferData0.y = packUnorm2x8(
        baseColor.b,
        clamp01(float(materialMask) * rcp(255.0))
    );
    gbufferData0.z = packUnorm2x8(encodeUnitVector(normal));
    gbufferData0.w = packUnorm2x8(params.lightMap);
}
