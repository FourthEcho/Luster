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

layout(
    location = 0
) out vec4 gbufferData0; // albedo, block ID, flat normal, light levels

/* RENDERTARGETS: 1 */

#ifdef normalMapping
/* RENDERTARGETS: 1,2 */
#endif

#ifdef specularMapping
/* RENDERTARGETS: 1,2 */
#endif

in vec2 lightLevels;
in vec3 scenePos;
in vec3 normal;
in vec3 color;

flat in uint materialMask;

uniform vec2 viewPixelSize;
uniform int frameCounter;

#include "/lib/util/encode.glsl"
#include "/lib/util/random.glsl"

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform vec3 cameraPosition;
uniform float far;

mat3 getTbnMatrix(vec3 normal) {
    vec3 tangent = normal.y == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), normal));
    vec3 bitangent = normalize(cross(tangent, normal));
    return mat3(tangent, bitangent, normal);
}

void main() {
    // Clip to taau viewport

#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    // Overdraw fade

    float dhFadeStartDistance
        = max0(far - dhOverdrawDistance - dhOverdrawFadeLength);
    float dhFadeEndDistance = max0(far - dhOverdrawDistance);
    float viewDistance = length(scenePos);

    float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);
    float fade = smoothstep(
        dhFadeStartDistance,
        dhFadeEndDistance,
        viewDistance
    );

    if (dither > fade) {
        discard;
        return;
    }

#ifdef DISTANT_HORIZONS_TEXTURES
    // Iris provides this API when DH LOD block textures are available.
    // Match DH's texture tinting, and skip the synthetic noise fallback.
    if (dh_hasTexture()) {
        vec4 tile = dh_sampleTexture();
        vec3 adjustedColor =
            mix(color, clamp01(color * tile.rgb * 2.0), tile.a);
        gbufferData0.x = packUnorm2x8(adjustedColor.rg);
        gbufferData0.y = packUnorm2x8(
            adjustedColor.b,
            clamp01(float(materialMask) * rcp(255.0))
        );
        gbufferData0.z = packUnorm2x8(encodeUnitVector(normal));
        gbufferData0.w = packUnorm2x8(lightLevels);
        return;
    }
#endif

#ifdef noiseOnDhTerrain
    mat3 tbn = getTbnMatrix(normal);
    vec3 worldPos = scenePos + cameraPosition;
    vec2 noisePos = (worldPos * tbn).xy;

    float noise = texture(noisetex, noisePos.xy * 0.2).x;
    vec3 adjustedColor = clamp01(color * (noise * 0.25 + 0.85));
#else
    vec3 adjustedColor = color;
#endif

    gbufferData0.x = packUnorm2x8(adjustedColor.rg);
    gbufferData0.y = packUnorm2x8(
        adjustedColor.b,
        clamp01(float(materialMask) * rcp(255.0))
    );
    gbufferData0.z = packUnorm2x8(encodeUnitVector(normal));
    gbufferData0.w = packUnorm2x8(lightLevels);
}
