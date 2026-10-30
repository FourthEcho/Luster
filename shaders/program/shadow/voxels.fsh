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

in vec3 cageNormal;
in vec3 worldPos;
flat in vec3 tint;

uniform int frameCounter, frameTime;
uniform float viewWidth, viewHeight;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowProjection, shadowProjectionInverse;
uniform mat4 shadowModelView, shadowModelViewInverse;

layout(location = 0) out vec3 shadowcolor0Out;

#include "/lib/light/direct/distortion.glsl"
#include "/lib/util/color.glsl"
void main() {
#if defined WORLD_NETHER
    discard;
#endif

    RayJob ray = RayJob(
        worldPos - worldOffset - 0.01f * cageNormal, // Ray origin
        mat3(shadowModelViewInverse) * vec3(0.0f, 0.0f, -1.0f), // Ray direction
        vec3(0.0f),
        vec3(0.0f),
        vec3(0.0f),
        false
    );

    rayConstraint = ivec3(ray.origin);
    traceRay(ray);

    if (!ray.resultHit) {
        discard;
    }

    vec4 baseColor = vec4(ray.resultColor, 1.0f);

    shadowcolor0Out = mix(vec3(1.0), baseColor.rgb * tint, baseColor.a);
    shadowcolor0Out
        = 0.25 * srgbEotfInv(shadowcolor0Out) * rec709ToWorkingColor;
    shadowcolor0Out *= step(baseColor.a, 1.0 - rcp(255.0));
}
