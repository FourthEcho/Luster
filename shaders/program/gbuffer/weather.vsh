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

flat out vec4 tint;

// ------------
//   Uniforms
// ------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;

uniform int frameCounter;

uniform vec2 taa_offset;
uniform vec2 view_pixel_size;

void main() {
    uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy
        + gl_TextureMatrix[0][3].xy;

    tint = gl_Color;

    vec3 view_pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

#ifdef slantedRain
    const float rain_tilt_amount = 0.25;
    const float rain_tilt_angle = 30.0 * degree;
    const vec2 rain_tilt_offset
        = rain_tilt_amount * vec2(cos(rain_tilt_angle), sin(rain_tilt_angle));

    vec3 scene_pos = transform(gbufferModelViewInverse, view_pos);
    vec3 world_pos = scene_pos + cameraPosition;

    float tilt_wave = 0.7 + 0.3 * sin(dot(world_pos, vec3(5.0)));
    scene_pos.xz -= rain_tilt_offset * tilt_wave * scene_pos.y;

    view_pos = transform(gbufferModelView, scene_pos);
#endif

    vec4 clip_pos = project(gl_ProjectionMatrix, view_pos);

#if defined taa && defined taau
    clip_pos.xy = clip_pos.xy * taau_render_scale
        + clip_pos.w * (taau_render_scale - 1.0);
    clip_pos.xy += taa_offset * clip_pos.w;
#elif defined taa
    clip_pos.xy += taa_offset * clip_pos.w * 0.66;
#endif

    gl_Position = clip_pos;
}
