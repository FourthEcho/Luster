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

out vec2 uv;

#ifdef colorGrading
  #if gradeWhiteBalance != 6500
flat out mat3 white_balance_matrix;
  #endif
#endif

#include "/lib/academy/utility.glsl"
#include "/lib/util/color.glsl"

void main() {
    uv = gl_MultiTexCoord0.xy;

#ifdef colorGrading
  #if gradeWhiteBalance != 6500
    vec3 src_xyz = blackbody(float(gradeWhiteBalance)) * rec2020_to_xyz;
    vec3 dst_xyz = blackbody(6500.0) * rec2020_to_xyz;
    white_balance_matrix = get_chromatic_adaptation_matrix(src_xyz, dst_xyz);
  #endif
#endif

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
