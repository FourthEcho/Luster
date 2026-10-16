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
#if !defined INCLUDE_CAMERA_CAMERA
#define INCLUDE_CAMERA_CAMERA

// Reference setup: every triangle factor is normalized to these, so the
// shipped defaults reproduce the pre-physical look exactly.
const float camera_reference_fstops = 3.2;
const float camera_reference_shutter = 60.0; // 1/60 s
const float camera_reference_iso = 100.0;

// Focal length in millimetres from the vertical FOV and the sensor height
// (sensor width shared across axes, height derived from aspect ratio).
float camera_sensor_height_mm(float aspect_ratio) {
    return float(camSensorWidth) / max(aspect_ratio, 1e-4);
}

float camera_focal_length_mm(float projection_11, float aspect_ratio) {
    float sensor_h = camera_sensor_height_mm(aspect_ratio);
    return 0.5 * sensor_h * projection_11;
}

// Thin-lens circle of confusion as a fraction of screen height:
// CoC = (f^2 / N) * |1/S - 1/D|, distances in metres.
float camera_coc_height_fraction(
    float focal_mm,
    float sensor_h,
    float focus_m,
    float dist_m
) {
    float coc_mm = focal_mm * focal_mm / max(camFstops, 1e-4)
        * abs(1.0 / (focus_m * 1000.0) - 1.0 / (dist_m * 1000.0));
    return coc_mm / max(sensor_h, 1e-4);
}

// Shutter trail factor relative to the 60Hz reference capture.
float camera_shutter_trail_factor() {
    return camera_reference_shutter / float(camShutterSpeed);
}

// Closed-triangle exposure factor: t * ISO / N^2, normalized to the
// reference setup, times the EV compensation dial.
float camera_exposure_triangle_factor() {
    float t = camera_shutter_trail_factor();
    float iso = float(camIso) / camera_reference_iso;
    float n = camera_reference_fstops / max(camFstops, 1e-4);
    return t * iso * n * n * exp2(camExposureCompensation);
}

#endif // INCLUDE_CAMERA_CAMERA

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0;

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform float near, far;

uniform float aspectRatio;
uniform float centerDepthSmooth;

uniform int frameCounter;

uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#include "/lib/misc/lodModSupport.glsl"
// Radial chromatic dispersion

vec3 apply_chromatic_dispersion(
    sampler2D color_sampler,
    vec2 uv,
    vec3 color,
    float coc_radius,
    float strength,
    vec2 clamp_max,
    float render_scale
) {
    vec2 center_offset = uv - 0.5;
    vec2 chromatic_scale = sign(center_offset) * sqrt(abs(center_offset));
    chromatic_scale *= vec2(1.0, view_pixel_size.x / view_pixel_size.y);

    vec2 spectral_offset = chromatic_scale * coc_radius * strength;

    color.r = textureLod(
        color_sampler,
        clamp(vec2(uv - spectral_offset), vec2(0.0), clamp_max) * render_scale,
        0
    ).r;
    color.b = textureLod(
        color_sampler,
        clamp(vec2(uv + spectral_offset), vec2(0.0), clamp_max) * render_scale,
        0
    ).b;

    return color;
}
#include "/lib/util/random.glsl"
#include "/lib/util/sampling.glsl"
#include "/lib/util/spaceConversion.glsl"

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

#ifndef dof
    scene_color = texelFetch(colortex0, texel, 0).rgb;
    return;
#endif

    float depth = texelFetch(depthtex0, texel, 0).x;

#ifdef LOD_MOD_ACTIVE
    float depth_lod = texelFetch(lod_depth_tex, texel, 0).x;

    if (is_lod_terrain(depth, depth_lod)) {
        depth = view_to_screen_space_depth(
            gbufferProjection,
            screen_to_view_space_depth(lod_projection_matrix_inverse, depth_lod)
        );
    }
#endif

    if (depth < hand_depth) {
        scene_color = texelFetch(colortex0, texel, 0).rgb;
        return;
    };

    // Calculate vogel disk rotation
    float theta = texelFetch(noisetex, texel & 511, 0).b;
    theta = r1(frameCounter, theta);
    theta *= tau;


    vec2 CoC;

    float dist_lin = max(
        abs(screen_to_view_space_depth(gbufferProjectionInverse, depth)),
        eps
    );
    float focus_lin = dofFocus < 0.0
        ? max(
              abs(screen_to_view_space_depth(
                  gbufferProjectionInverse,
                  centerDepthSmooth
              )),
              eps
          )
        : max(abs(dofFocus), eps);
    float sensor_h = camera_sensor_height_mm(aspectRatio);
    float focal_mm
        = camera_focal_length_mm(gbufferProjection[1][1], aspectRatio);
    float coc = min(
        camera_coc_height_fraction(focal_mm, sensor_h, focus_lin, dist_lin),
        dofMaxRadius
    );
    // coc is a fraction of screen height: for circular bokeh in UV space
    // the horizontal radius must be divided by the aspect ratio
    CoC = coc * vec2(rcp(aspectRatio), 1.0);

    scene_color = vec3(0.0);

    for (int i = 0; i < dofSamples; ++i) {
        vec2 offset = vogel_disc_sample(i, dofSamples, theta);
        scene_color
            += textureLod(
                   colortex0,
                   clamp(
                       vec2(uv + offset * CoC),
                       vec2(0.0),
                       vec2(
                           1.0 - 2.0 * view_pixel_size * rcp(taau_render_scale)
                       )
                   ) * taau_render_scale,
                   0
            )
                   .rgb;
    }

    scene_color *= rcp(dofSamples);

#ifdef chromaticDispersion
    // Chromatic dispersion: radial spectral fringing scaled by the circle


    scene_color = apply_chromatic_dispersion(
        colortex0,
        uv,
        scene_color,
        length(CoC),
        chromaticDispersionStrength * 0.1,
        vec2(1.0 - 2.0 * view_pixel_size * rcp(taau_render_scale)),
        taau_render_scale
    );
#endif
}
