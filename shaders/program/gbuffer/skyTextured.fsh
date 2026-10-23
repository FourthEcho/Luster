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

layout(location = 0) out vec3 fragColor;

/* RENDERTARGETS: 0 */

// The vanilla sun and moon textures are not rendered. The shader sun and
// moon are drawn from deferred11 in lib/atmos/sky.glsl instead.
void main() {
    fragColor = vec3(0.0);
}

