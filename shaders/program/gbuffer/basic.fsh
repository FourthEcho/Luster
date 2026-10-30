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

layout(location = 0) out vec4 sceneColor;
layout(
    location = 1
) out vec4 gbufferData0; // albedo, block ID, flat normal, light levels
layout(
    location = 2
) out vec4 gbufferData1; // detailed normal, specular map (optional)
#ifdef ssptEnabled
layout(
    location = 3
) out vec4 emissionRadiance; // zeroed: basic geometry never emits
#endif

/* RENDERTARGETS: 0,1,2 */

#ifdef ssptEnabled
/* RENDERTARGETS: 0,1,2,22 */
#endif

flat in vec2 lightLevels;
flat in vec4 tint;

// ------------
//   Uniforms
// ------------

uniform vec2 viewRes;
uniform vec2 viewPixelSize;

uniform int renderStage;
uniform float frameTimeCounter;

#include "/lib/util/color.glsl"
#include "/lib/util/encode.glsl"

const vec3 normal = vec3(0.0, 1.0, 0.0);

// gbuffers_basic is abused by mods for rendering overlays and the like, for now

// This shader and vanilla are still both affected by Z-fighting in some areas,


float fixupTranslucent(float alpha) {
    return mix(alpha * 0.25, alpha, step(0.9, alpha));
}

void main() {
#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    // I have yet to see anything render something transparent but we assume it
    // can happen.
    if (tint.a < 0.1) {
        discard;
    }

    vec4 baseColor = tint;
    vec2 adjustedLightLevels = lightLevels;

#if defined PROGRAM_GBUFFERS_LINE && boxMode != boxModeNone
    if (renderStage == MC_RENDER_STAGE_OUTLINE) {
#if boxMode == boxModeColor
        baseColor.rgb = vec3(boxColorR, boxColorG, boxColorB);
#else // boxModeRainbow
        vec2 uv = gl_FragCoord.xy * viewPixelSize;
        baseColor.rgb = hsvToRgb(
            vec3(fract(uv.y + uv.x * uv.y + frameTimeCounter * 0.1), 1.0, 1.0)
        );
#endif

        adjustedLightLevels.x
            = clamp01(adjustedLightLevels.x + boxEmission);
    }
#endif

    sceneColor.rgb = srgbEotfInv(baseColor.rgb) * rec709ToWorkingColor;
    // see note in function
    sceneColor.a = fixupTranslucent(tint.a);

    if (renderStage == MC_RENDER_STAGE_OUTLINE) {
        sceneColor.rgb *= 1.0 + boxEmission;
    }

    vec2 encodedNormal = encodeUnitVector(normal);

#ifdef ssptEnabled
    // This pass overwrites colortex1 with mask-0 geometry that never
    // emits; zero the bake so SSPT hits here cannot read stale emission
    // from whatever wrote the texel before.
    emissionRadiance = vec4(0.0);
#endif

    gbufferData0.x = packUnorm2x8(baseColor.rg);
    gbufferData0.y = packUnorm2x8(baseColor.b, 0.0);
    gbufferData0.z = packUnorm2x8(encodeUnitVector(normal));
    gbufferData0.w = packUnorm2x8(adjustedLightLevels);

#ifdef normalMapping
    gbufferData1.xy = encodedNormal;
#endif

#ifdef specularMapping
    const vec4 specularMap = vec4(0.0);
    gbufferData1.z = packUnorm2x8(specularMap.xy);
    gbufferData1.w = packUnorm2x8(specularMap.zw);
#endif
}
