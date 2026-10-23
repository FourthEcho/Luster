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

layout(location = 0) out vec4 damageOverlay;

#ifdef useSeparateEntityDraws
#if MC_VERSION >= 260300
/* RENDERTARGETS: 3 */
#else
/* RENDERTARGETS: 0 */
#endif
#else
/* RENDERTARGETS: 3 */
#endif

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform vec2 taaOffset;
uniform vec2 viewPixelSize;

const float lodBias = log2(taauViewportScale);

#include "/lib/util/color.glsl"

void main() {
#if defined taa && defined taau
    vec2 coord = gl_FragCoord.xy * viewPixelSize * rcp(taauViewportScale);
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    damageOverlay = texture(gtexture, uv, lodBias);

#if defined COLORWHEEL
	vec2 lmcoord;
	float ao;
	vec4 overlayColor;

	clrwl_computeFragment(damageOverlay, damageOverlay, lmcoord, ao, overlayColor);
	damageOverlay.rgb = mix(damageOverlay.rgb, overlayColor.rgb, overlayColor.a);
#endif

    if (damageOverlay.a < 0.1) {
        discard;
    }

#if defined useSeparateEntityDraws && MC_VERSION < 260300
    damageOverlay.rgb
        = 0.5 * srgbEotfInv(2.0 * damageOverlay.rgb) * rec709ToWorkingColor;
    damageOverlay.a = 1.0;
#else
    // Old overlay handling
    // alpha of 1 <=> block breaking overlay
    damageOverlay.a = 1.0 / 255.0;
#endif
}
