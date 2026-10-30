/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.

    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file
    or here: https://rre36.com/copyright-license

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#if !defined INCLUDE_LIGHT_HANDHELD_LIGHT
#ifndef LUSTER_DISABLE_HANDHELD_LIGHT

#define INCLUDE_LIGHT_HANDHELD_LIGHT

#define LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/weather/colors.glsl"
#undef LUSTER_INCLUDE_BLOCKLIGHT_COLOR
#include "/lib/light/emission.glsl"

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 getHandheldLightColor(int handItemId, int heldItemLightValue) {
    int emitterIndex = handItemId - firstHandheldEmitterId;

    if (emitterIndex >= 0 && emitterIndex < handheldEmitterCount) {
        return handheldEmitterLightColor[emitterIndex];
    }

    return (blocklightColor * blocklightScale * rcp(15.0))
        * heldItemLightValue;
}

float getHandheldLightFalloff(vec3 scenePos, float ao) {
    float falloff = lift(rcp(dot(scenePos, scenePos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff);
}

vec3 getHandheldLight(vec3 scenePos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scenePos += relativeEyePosition;
#endif

    vec3 lightColor = max(
        getHandheldLightColor(heldItemId, heldBlockLightValue),
        getHandheldLightColor(heldItemId2, heldBlockLightValue2)
    );

    float falloff = getHandheldLightFalloff(scenePos, ao);

    return lightColor * falloff;
}

#endif // LUSTER_DISABLE_HANDHELD_LIGHT
#endif // INCLUDE_LIGHT_HANDHELD_LIGHT
