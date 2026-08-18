/*
--------------------------------------------------------------------------------

  Luster Shaders

  program/gbuffers_weather:
  Handle rain and snow particles

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

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

// Daily random wind direction — same source as foliage (see
// include/weather/core.glsl), declared locally to avoid pulling in
// the full weather/core.glsl (which would require world_age, biome_*,
// time_sunrise, etc. uniforms that this vertex shader doesn't have).
//
// Driven by the weather_wind_angle uniform defined in shaders.properties:
//   uniform.float.weather_wind_angle = (worldDay % 8) * 0.7853981633974483
uniform float weather_wind_angle;

vec2 weather_wind_direction() {
    return vec2(cos(weather_wind_angle), sin(weather_wind_angle));
}

void main() {
    uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy
        + gl_TextureMatrix[0][3].xy;

    tint = gl_Color;

    vec3 view_pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

#ifdef SLANTED_RAIN
    const float rain_tilt_amount = 0.25;

    // Select a stable daily wind direction from the current world-day phase.
    // Snow uses the same particle shader so it gets the same lean for free.
    vec2 rain_tilt_dir = weather_wind_direction();
    vec2 rain_tilt_offset = rain_tilt_amount * rain_tilt_dir;

    vec3 scene_pos = transform(gbufferModelViewInverse, view_pos);
    vec3 world_pos = scene_pos + cameraPosition;

    float tilt_wave = 0.7 + 0.3 * sin(dot(world_pos, vec3(5.0)));
    scene_pos.xz -= rain_tilt_offset * tilt_wave * scene_pos.y;

    view_pos = transform(gbufferModelView, scene_pos);
#endif

    vec4 clip_pos = project(gl_ProjectionMatrix, view_pos);

#if defined TAA && defined TAAU
    clip_pos.xy = clip_pos.xy * taau_render_scale
        + clip_pos.w * (taau_render_scale - 1.0);
    clip_pos.xy += taa_offset * clip_pos.w;
#elif defined TAA
    clip_pos.xy += taa_offset * clip_pos.w * 0.66;
#endif

    gl_Position = clip_pos;
}
