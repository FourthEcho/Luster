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

#if !defined INCLUDE_LIGHTING_DIRECT_LIGHTING_COMMON
#define INCLUDE_LIGHTING_DIRECT_LIGHTING_COMMON

// Fade from close shadows (shadow maps) to distant shadows (lightmap or SSRT)
float getShadowDistanceFade(vec3 scenePos, vec3 shadowScreenPos) {
    float effectiveShadowDistance = min(shadowDistance, far);
    return linearStep(
        0.1,
        1.0,
        pow32(
            max(maxOf(abs(shadowScreenPos.xy * 2.0 - 1.0)),
                lengthSquared(scenePos) * rcp(sqr(effectiveShadowDistance)))
        )
    );
}

// Fake, lightmap-based shadows for outside of the shadow range or when shadows
// are disabled
float getLightmapShadows(float skylight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skylight);
}

// Prevents light leaking in caves by cancelling out sunlight in very low
// skylight
float getLightmapLightLeakPrevention(float skylight) {
    return smoothstep(0.0 / 15.0, 2.0 / 15.0, skylight);
}

#endif // INCLUDE_LIGHTING_DIRECT_LIGHTING_COMMON
