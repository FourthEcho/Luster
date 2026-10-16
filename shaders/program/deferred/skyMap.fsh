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

layout(location = 0) out vec3 sky_map;

/* RENDERTARGETS: 4 */

in vec2 uv;

flat in vec3 ambient_color;
flat in vec3 light_color;

#if defined WORLD_OVERWORLD
flat in vec3 sun_color;
flat in vec3 moon_color;
flat in vec3 sky_color;

flat in float aurora_amount;
flat in mat2x3 aurora_colors;

flat in float rainbow_amount;

#include "/lib/sky/clouds/parameters.glsl"
flat in CloudsParameters clouds_params;

#include "/lib/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D colortex6; // 3D bubbly worley noise
#define SAMPLER_WORLEY_BUBBLY colortex6
uniform sampler3D colortex7; // 3D swirley worley noise
#define SAMPLER_WORLEY_SWIRLEY colortex7
uniform sampler3D cumulusCurl;
#define SAMPLER_CUMULUS_CURL cumulusCurl

#if defined WORLD_OVERWORLD && defined galaxy
uniform sampler2D colortex13;
#define galaxy_sampler colortex13
#endif

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D depthtex1;

uniform sampler2D colortex8; // cloud shadow map

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float desert_sandstorm;
uniform float blindness;
uniform float darknessFactor;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float world_age;
uniform float eye_skylight;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float biome_cave;
uniform float biome_may_snow;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0

#ifdef cloudsCumulusPrecomputeLocalCoverage
#define CLOUDS_USE_LOCAL_COVERAGE_MAP
#endif

#if defined WORLD_OVERWORLD
#include "/lib/fog/overworld/analytic.glsl"
#include "/lib/sky/aurora.glsl"
#endif

#include "/lib/sky/projection.glsl"
#include "/lib/sky/sky.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    if (texel.x == sky_map_res.x) { // Store lighting colors
        sky_map = vec3(0.0);
        switch (texel.y) {
            case 0:
                sky_map = light_color;
                break;

            case 1:
                sky_map = ambient_color;
                break;
        }
    } else { // Draw sky map
        vec3 ray_dir = unproject_sky(uv);

        sky_map = draw_sky(ray_dir);

#if defined WORLD_OVERWORLD
        // Apply analytic fog over sky
        mat2x3 fog = air_fog_analytic(
            cameraPosition,
            cameraPosition + ray_dir,
            true,
            eye_skylight,
            1.0
        );
        sky_map = sky_map * fog[1] + fog[0];
#endif
    }
}
