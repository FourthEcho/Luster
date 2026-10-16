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

#if !defined INCLUDE_SKY_SKY
#define INCLUDE_SKY_SKY

#include "/lib/util/color.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/fastMath.glsl"
#include "/lib/util/random.glsl"

#if defined WORLD_OVERWORLD || defined WORLD_END
#if !defined INCLUDE_SKY_STARS
#define INCLUDE_SKY_STARS

// Stars based on https://www.shadertoy.com/view/Md2SR3

vec3 unstable_star_field(vec2 coord, float star_threshold) {
    const float min_temp = 4500.0;
    const float max_temp = 8500.0;

    vec4 noise = hash4(coord);

    float star = linear_step(star_threshold, 1.0, noise.x);
    star = pow16(star) * starsIntensity;

    float temp = mix(min_temp, max_temp, noise.y);
    vec3 color = blackbody(temp);

    const float twinkle_speed = 2.0;
    float twinkle_amount = noise.z;
    float twinkle_offset = tau * noise.w;
    star *= 1.0
        - twinkle_amount
            * cos(frameTimeCounter * twinkle_speed + twinkle_offset);

    return star * color;
}

// Stabilizes the star field by sampling at the four neighboring integer
// coordinates and interpolating
vec3 stable_star_field(vec2 coord, float star_threshold) {
    coord = abs(coord) + 33.3 * step(0.0, coord);
    vec2 i, f = modf(coord, i);

    f.x = cubic_smooth(f.x);
    f.y = cubic_smooth(f.y);

    return unstable_star_field(i + vec2(0.0, 0.0), star_threshold) * (1.0 - f.x)
        * (1.0 - f.y)
        + unstable_star_field(i + vec2(1.0, 0.0), star_threshold) * f.x
        * (1.0 - f.y)
        + unstable_star_field(i + vec2(0.0, 1.0), star_threshold) * f.y
        * (1.0 - f.x)
        + unstable_star_field(i + vec2(1.0, 1.0), star_threshold) * f.x * f.y;
}

vec3 draw_stars(vec3 ray_dir, float galaxy_luminance) {
    // Adjust star threshold so that brightest stars appear first
#if defined WORLD_OVERWORLD
    float star_threshold = 1.0
        - 0.05 * starsCoverage * smoothstep(-0.2, 0.05, -sun_dir.y)
        - 0.5 * cube(galaxy_luminance);
#else
    float star_threshold = 1.0 - 0.008 * starsCoverage;
#endif

    // Project ray direction onto the plane
    vec2 coord = ray_dir.xy * rcp(abs(ray_dir.z) + length(ray_dir.xy))
        + 41.21 * sign(ray_dir.z);
    coord *= 600.0;

    return stable_star_field(coord, star_threshold);
}

#endif // INCLUDE_SKY_STARS

#endif

//----------------------------------------------------------------------------//
#if defined WORLD_OVERWORLD

#include "/lib/brdf/fresnel.glsl"
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#define LUSTER_INCLUDE_LIGHT_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_LIGHT_COLOR
#define LUSTER_INCLUDE_WEATHER_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_WEATHER_COLOR
#if !defined INCLUDE_MISC_LIGHTNING_FLASH
#define INCLUDE_MISC_LIGHTNING_FLASH

#ifdef lightningFlash
uniform float lightning_flash_iris;
#define LIGHTNING_FLASH_UNIFORM lightning_flash_iris
#else
#define LIGHTNING_FLASH_UNIFORM 0.0
#endif

const float lightning_flash_intensity = 4.0;

#endif // INCLUDE_MISC_LIGHTNING_FLASH
#include "/lib/sky/atmosphere.glsl"
#include "/lib/sky/projection.glsl"
#include "/lib/sky/rainbow.glsl"
#include "/lib/util/geometry.glsl"

#if defined PROGRAM_DEFERRED0
#include "/lib/sky/clouds.glsl"

#if defined crepuscularRays && !defined blockyClouds
#include "/lib/sky/crepuscularRays.glsl"
#endif
#endif

const float sun_luminance = rcp(
    cone_angle_to_solid_angle(sun_angular_radius)
); // luminance of sun disk
const float moon_luminance = 10.0; // luminance of moon disk

vec3 draw_sun(vec3 ray_dir) {
    float nu = dot(ray_dir, sun_dir);

    // Limb darkening model from
    // http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
    const vec3 alpha = vec3(0.429, 0.522, 0.614);
    float center_to_edge = max0(sun_angular_radius - fast_acos(clamp(nu, -1.0, 1.0)));
    vec3 limb_darkening
        = pow(vec3(1.0 - sqr(1.0 - center_to_edge)), 0.5 * alpha);

    return sun_luminance * sun_color * step(0.0, center_to_edge)
        * limb_darkening;
}

vec4 draw_moon(vec3 ray_dir) {
    const vec3 lit_color
        = vec3(moonR, moonG <= 0.03 ? 0.0 : moonG - 0.03, moonB);
    const vec3 glow_color
        = vec3(moonR <= 0.05 ? 0.0 : moonR - 0.05, moonG, moonB);

    // Cut out the moon disc.
    float MoV = dot(ray_dir, moon_dir);
    if (MoV < cos(moon_angular_radius)) {
        return vec4(0.0);
    }

    // Find distance from center to edge.
    float dist = clamp01(fast_acos(clamp(MoV, -1.0, 1.0)) / moon_angular_radius);

    // Transform the coordinate space such that z is parallel to moon_dir
    vec3 tangent = abs(moon_dir.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), moon_dir));
    vec3 bitangent = normalize(cross(tangent, moon_dir));
    mat3 tbn = mat3(tangent, bitangent, moon_dir);

    // Vector from ray dir to moon dir.
    vec2 offset = ((ray_dir - moon_dir) * tbn).xy;
    offset = fract(offset + 0.5);

    vec3 noise = texture(noisetex, 2.0 * offset).xyz;
    float moon_texture
        = pow1d5(noise.x) * 0.75 + 0.6 * cube(noise.y) - 0.1 * noise.z;

    // Find the distance to the moon if it were 1 unit away, and its normal.
    float moon_dist
        = intersect_sphere(-moon_dir, ray_dir, moon_angular_radius).x;
    vec3 moon_normal = normalize(ray_dir * moon_dist - moon_dir);

    // Get light direction which orbits around moon. Anchored to the fixed
    // moon frame so the phase terminator does not swim with the view ray.
    float light_angle = 0.125 * tau * float(moonPhase);
    vec3 left_dir = abs(moon_dir.y) == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), moon_dir));
    vec3 light_dir = cos(light_angle) * -moon_dir + sin(light_angle) * left_dir;
    float moon_shadow = dampen(max0(dot(moon_normal, light_dir)));

    float edge_glow = sqr(sqr(sqr(dist)));

    vec3 color = max(moon_shadow * lit_color * (1.0 + 4.0 * edge_glow),
                     0.5 * glow_color * (0.1 + 0.1 * edge_glow))
        * (0.2 + 0.8 * moon_texture);
    color = moon_luminance * sqr(color);
    return vec4(color, 1.0);
}

#ifdef galaxy
vec3 draw_galaxy(vec3 ray_dir, out float galaxy_luminance) {
    const vec3 galaxy_tint = vec3(0.75, 0.66, 1.0) * galaxyIntensity;

    float galaxy_intensity = 0.05 + 1.0 * linear_step(-0.1, 0.25, -sun_dir.y);

    float lon = atan(ray_dir.x, ray_dir.z);
    float lat = fast_acos(clamp(-ray_dir.y, -1.0, 1.0));

    vec3 galaxyColor
        = texture(galaxy_sampler, vec2(lon * rcp(tau) + 0.5, lat * rcp(pi)))
              .rgb;

    galaxyColor = srgb_eotf_inv(galaxyColor) * rec709_to_working_color;

    galaxyColor *= galaxy_intensity * galaxy_tint;

    galaxy_luminance = dot(galaxyColor, luminance_weights);

    galaxyColor = mix(vec3(galaxy_luminance), galaxyColor, 2.0);

    return max0(galaxyColor);
}
#endif

vec3 draw_sky(
    vec3 ray_dir,
    vec3 atmosphere,
    vec4 clouds_and_aurora,
    float clouds_apparent_distance
) {
    vec3 sky = vec3(0.0);

#if defined shadow
    // Trick to make stars rotate with sun and moon
    mat3 rot = (sunAngle < 0.5)
        ? mat3(shadowModelViewInverse)
        : mat3(
              -shadowModelViewInverse[0].xyz,
              shadowModelViewInverse[1].xyz,
              -shadowModelViewInverse[2].xyz
          );

    vec3 celestial_dir = ray_dir * rot;
#else
    vec3 celestial_dir = ray_dir;
#endif

    // Galaxy

#ifdef galaxy
    float galaxy_luminance;
    sky += draw_galaxy(celestial_dir, galaxy_luminance);
#else
    const float galaxy_luminance = 0.0;
#endif

    // Sun, moon stars

#if defined PROGRAM_DEFERRED11
    vec3 skytextured_output
        = texelFetch(colortex0, ivec2(gl_FragCoord.xy), 0).rgb;
    sky += skytextured_output;

#ifdef stars
    // Stars
    float stars_visibility
        = clamp01(1.0 - dot(skytextured_output, vec3(0.33) * 256.0));
    sky += draw_stars(celestial_dir, galaxy_luminance) * stars_visibility;
#endif

#ifndef vanillaSun
    // Shader sun
    sky += draw_sun(ray_dir);
#endif

#ifndef vanillaMoon
    // Shader moon
    vec4 moon = draw_moon(ray_dir);
    sky *= 1.0 - moon.a;
    sky += moon.rgb;
#endif
#endif

    // Atmosphere

    sky *= atmosphere_transmittance(ray_dir.y, planet_radius)
        * (1.0 - rainStrength);
#if defined desertSandstorm && defined sandstormSky


    sky *= sandstorm_transmittance(ray_dir.y);
#endif
    sky += atmosphere;

    // Clouds, aurora, crepuscular rays

    sky *= clouds_and_aurora.a; // Transmittance
    sky += clouds_and_aurora.rgb; // Scattering

    // Rainbow

    sky = draw_rainbows(
        sky,
        ray_dir,
        mix(clouds_apparent_distance,
            1e6,
            linear_step(1.0, 0.95, clouds_and_aurora.w))
    );

    // Cave sky fix

#if !defined PROGRAM_DEFERRED0
    // Fade lower part of sky into cave fog color when underground so that the
    // sky isn't visible beyond the render distance
    float underground_sky_fade
        = biome_cave * smoothstep(-0.1, 0.1, 0.4 - ray_dir.y);
    sky = mix(sky, vec3(0.0), underground_sky_fade);
#endif

    return sky;
}

#if defined PROGRAM_DEFERRED0
vec4 get_clouds_and_aurora(
    vec3 ray_dir,
    vec3 clear_sky,
    out float clouds_apparent_distance
) {
    clouds_apparent_distance = 1e6;

    ivec2 texel = ivec2(gl_FragCoord.xy);
    texel.x = texel.x % (sky_map_res.x - 4);

    float dither = interleaved_gradient_noise(vec2(texel));

    // Clouds

#ifndef blockyClouds
    const vec3 air_viewer_pos = vec3(0.0, planet_radius, 0.0);
    CloudsResult result
        = draw_clouds(air_viewer_pos, ray_dir, clear_sky, -1.0, dither);

    // Lightning flash
    result.scattering.rgb += LIGHTNING_FLASH_UNIFORM * lightning_flash_intensity
        * result.scattering.a;
#else
    CloudsResult result = clouds_not_hit;
#endif

    clouds_apparent_distance = result.apparent_distance;

    // Aurora

    vec3 aurora = draw_aurora(ray_dir, dither);

    vec4 clouds_and_aurora = vec4(
        result.scattering.xyz + aurora * result.transmittance,
        result.transmittance
    );

    // Crepuscular rays (sky-map ambient path only)

#if defined crepuscularRays && !defined blockyClouds
    vec4 crepuscular_rays
        = draw_crepuscular_rays(colortex8, ray_dir, false, dither);
    clouds_and_aurora *= crepuscular_rays.w;
    clouds_and_aurora.rgb += crepuscular_rays.xyz;
#endif

    return clouds_and_aurora;
}

vec3 draw_sky(vec3 ray_dir) {
    vec3 atmosphere = atmosphere_scattering(
        ray_dir,
        sun_color,
        sun_dir,
        moon_color,
        moon_dir,
        true
    );
    float clouds_apparent_distance;
    vec4 clouds_and_aurora
        = get_clouds_and_aurora(ray_dir, atmosphere, clouds_apparent_distance);
    return draw_sky(
        ray_dir,
        atmosphere,
        clouds_and_aurora,
        clouds_apparent_distance
    );
}
#endif

//----------------------------------------------------------------------------//
#elif defined WORLD_NETHER

vec3 draw_sky(vec3 ray_dir) { return ambient_color; }

//----------------------------------------------------------------------------//
#elif defined WORLD_END

#include "/lib/sky/atmosphere.glsl"

const float sun_solid_angle = cone_angle_to_solid_angle(sun_angular_radius);
const vec3 end_sun_color = vec3(1.0, 0.5, 0.25);

vec3 draw_sun(vec3 ray_dir) {
    float nu = dot(ray_dir, sun_dir);
    float r = fast_acos(clamp(nu, -1.0, 1.0));

    // Sun disk

    const vec3 alpha = vec3(0.6, 0.5, 0.4);
    float center_to_edge = max0(sun_angular_radius - r);
    vec3 limb_darkening
        = pow(vec3(1.0 - sqr(1.0 - center_to_edge)), 0.5 * alpha);
    vec3 sun_disk = limb_darkening * vec3(r < sun_angular_radius);

    // Solar flare effect

    // Transform the coordinate space such that z is parallel to sun_dir
    vec3 tangent = sun_dir.y == 1.0
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), sun_dir));
    vec3 bitangent = normalize(cross(tangent, sun_dir));
    mat3 rot = mat3(tangent, bitangent, sun_dir);

    // Vector from ray dir to sun dir
    vec2 q = ((ray_dir - sun_dir) * rot).xy;

    float theta = fract(
        linear_step(-pi, pi, atan(q.y, q.x)) + 0.015 * frameTimeCounter
        - 0.33 * r
    );

    float flare
        = texture(noisetex, vec2(theta, r - 0.025 * frameTimeCounter)).x;
    flare = pow5(flare) * exp(-25.0 * (r - sun_angular_radius));
    flare = r < sun_angular_radius ? 0.0 : flare;

    return end_sun_color * rcp(sun_solid_angle) * max0(sun_disk + 0.1 * flare);
}

vec3 draw_sky(vec3 ray_dir) {
    // Sky gradient

    float up_gradient
        = linear_step(0.0, 0.4, ray_dir.y) + linear_step(0.1, 0.8, -ray_dir.y);
    vec3 sky = ambient_color * mix(0.1, 0.04, up_gradient);
    float mie_phase = cornette_shanks_phase(dot(ray_dir, sun_dir), 0.6);
    sky += 0.1 * (ambient_color + 0.5 * end_sun_color) * mie_phase;

#if defined PROGRAM_DEFERRED11
    // Sun

#ifdef endSunEffect
    // Fixed End sun disk brightness


    sky += draw_sun(ray_dir) * 1.00;
#endif

    // Stars

    vec3 stars_fade
        = exp2(-0.1 * max0(1.0 - ray_dir.y) / max(ambient_color, eps))
        * linear_step(-0.2, 0.0, ray_dir.y);
    sky += draw_stars(ray_dir, 0.0).xzy * stars_fade;
#endif

    return sky;
}

#endif

#endif // INCLUDE_SKY_SKY
