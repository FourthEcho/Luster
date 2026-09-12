#if !defined INCLUDE_SURFACE_REFRACTION
#define INCLUDE_SURFACE_REFRACTION

// Screen-space refraction kit (consumer: c1_blend_layers; refract_safe is
// also shared with the shadow pass for water caustics).
//
// Documented design, following the converged real-time recipe:
//   - Snell direction at a single air -> medium interface, following the
//     pbr-book "Specular Reflection and Transmission" Refract() convention
//     (relative IOR; entering a denser medium, so total internal reflection
//     cannot trigger — refract_safe's zero branch is dead-but-safe here).
//   - Slab thickness offset (Filament `thin` transmission model) with
//     Beer-Lambert handled separately by water_absorption_approx (Filament's
//     applyVolumeAttenuation equivalent).
//   - Roughness blur as an N-tap cone gather around the Snell direction.
//     Filament/three.js map roughness to a transmission-mip LOD via
//     roughness * clamp(ior * 2 - 2); colortex0 carries no mip chain, so the
//     same lobe is sampled directly. Lobe-broadening theory: Walter et al.
//     2007 "Microfacet Models for Refraction through Rough Surfaces";
//     real-time lobe approx: de Rousiers et al. 2011 "Real-Time Rough
//     Refraction".
//   - Spectral dispersion as 3 taps at staggered IOR (Arnold's Abbe-number
//     dispersion, simplified to fixed water-like spread).
//
// Data layout of refraction_data (colortex3): xy = world normal x in
// [-1, 1] mapped to [0, 1] (z is rebuilt as sqrt(1 - x^2 - y^2); all
// producers write unit normals), zw = 16-bit surface roughness for the
// blur term.
//
// Requires: split_2x8/unsplit_2x8 from "/include/utility/encoding.glsl",
// max0() from "/include/global.glsl". All functions take explicit
// parameters so passes without the material system can use this file.

#include "/include/utility/encoding.glsl"

// Slab IOR (mirrors air_n/water_n in "/include/surface/material.glsl").
const float refraction_ior_air = 1.000293; // for 0°C and 1 atm
const float refraction_ior_water = 1.333; // for 20°C

// using the built-in GLSL refract() seems to cause NaNs on Intel drivers, but
// with this function, which does the exact same thing, it's fine
vec3 refract_safe(vec3 I, vec3 N, float eta) {
    float NoI = dot(N, I);
    float k = 1.0 - eta * eta * (1.0 - NoI * NoI);
    if (k < 0.0) {
        return vec3(0.0);
    } else {
        return eta * I - (eta * NoI + sqrt(k)) * N;
    }
}

void decode_refraction_data(
    vec4 data,
    out vec3 normal,
    out float roughness
) {
    float nx = unsplit_2x8(data.xy) * 2.0 - 1.0;
    normal = vec3(nx, 0.0, sqrt(max0(1.0 - nx * nx)));
    roughness = unsplit_2x8(data.zw);
}

// Filament/three.js applyIorToRoughness: an IOR of 1.0 means no microfacet
// refraction regardless of roughness; 1.5+ gives the full effect.
float refraction_roughness_scale(float roughness, float ior) {
    return roughness * clamp(ior * 2.0 - 2.0, 0.0, 1.0);
}

// 4-tap rotated Poisson disc, radius ~1 UV unit (scaled by the caller).
const vec2 refraction_poisson[4] = vec2[4](
    vec2(-0.94201624, -0.39906216),
    vec2(0.94558609, -0.76844717),
    vec2(-0.09418410, 0.92938870),
    vec2(0.34495938, 0.29387760)
);

// Center + Poisson averaged fetch for one spectral channel. center_uv and
// radius_uv are full-res UVs; render_scale maps into the (possibly
// TAAU-downscaled) scene buffer.
vec3 refraction_blur(
    sampler2D scene_sampler,
    vec2 center_uv,
    float radius_uv,
    float render_scale
) {
    vec3 sum = texture(scene_sampler, center_uv * render_scale).rgb;
    for (int i = 0; i < 4; ++i) {
        vec2 tap = clamp(
            center_uv + refraction_poisson[i] * radius_uv,
            vec2(0.0),
            vec2(1.0)
        );
        sum += texture(scene_sampler, tap * render_scale).rgb;
    }
    return sum * 0.2;
}

#endif // INCLUDE_SURFACE_REFRACTION
