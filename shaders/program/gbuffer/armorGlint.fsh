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

layout(location = 0) out vec4 fragColor;

#if MC_VERSION > 12111
/* RENDERTARGETS: 13 */
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

#if defined COLORWHEEL
	vec4 color = texture(gtexture, uv, lodBias);
	vec2 lmcoord;
	float ao;
	vec4 overlayColor;

	clrwl_computeFragment(color, color, lmcoord, ao, overlayColor);
	color.rgb = mix(color.rgb, overlayColor.rgb, overlayColor.a);

	vec3 armorGlint = color.rgb;
#else
    vec3 armorGlint = texture(gtexture, uv, lodBias).rgb;
#endif

fragColor.rgb = (srgbEotfInv(armorGlint) * rec709ToWorkingColor)
    * 1.00;
fragColor.a = 0.0;
}
