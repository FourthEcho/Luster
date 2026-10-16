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

#if !defined INCLUDE_LIGHTING_BSDF_SPECULAR_LIGHTING
#define INCLUDE_LIGHTING_BSDF_SPECULAR_LIGHTING

#include "/lib/brdf/fresnel.glsl"
#define LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/light/colors.glsl"
#undef LUSTER_INCLUDE_MOON_PHASE_COLOR
#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/geometry.glsl"
#include "/lib/sky/projection.glsl"
#include "/lib/material/material.glsl"
#include "/lib/util/bicubic.glsl"
#include "/lib/util/dithering.glsl"
#include "/lib/util/random.glsl"
#include "/lib/util/sampling.glsl"
#include "/lib/util/spaceConversion.glsl"

#if defined WORLD_OVERWORLD
#include "/lib/fog/overworld/analytic.glsl"
#endif

// Microfacet distribution & geometry (GGX/Smith). Kept with the specular
// https://www.gdcvault.com/play/1024478/PBR-Diffuse-Lighting-for-GGX
float distribution_ggx(float NoH_sq, float alpha_sq) {
    // Clamp: a perfect mirror (alpha = 0) gives 0/0 = NaN at NoH = 1
    alpha_sq = max(alpha_sq, 1e-6);
    return alpha_sq / (pi * sqr(1.0 - NoH_sq + NoH_sq * alpha_sq));
}

float v1_smith_ggx(float cos_theta, float alpha_sq) {
    return 1.0
        / (cos_theta
           + sqrt((-cos_theta * alpha_sq + cos_theta) * cos_theta + alpha_sq));
}

float v2_smith_ggx(float NoL, float NoV, float alpha_sq) {
    float ggx_l = NoV * sqrt((-NoL * alpha_sq + NoL) * NoL + alpha_sq);
    float ggx_v = NoL * sqrt((-NoV * alpha_sq + NoV) * NoV + alpha_sq);
    return 0.5 / (ggx_l + ggx_v);
}

// Merged from /lib/brdf/raytracer.glsl (single consumer: raymarch_depth_buffer
// used by trace_specular_ray below).
#if defined SSRT_LOD
#define SSRT_DEPTH_SAMPLER lod_depth_tex_shading
#define SSRT_PROJECTION_MATRIX lod_projection_matrix
#define SSRT_PROJECTION_MATRIX_INVERSE lod_projection_matrix_inverse
#else
#define SSRT_DEPTH_SAMPLER combined_depth_tex
#define SSRT_PROJECTION_MATRIX combined_projection_matrix
#define SSRT_PROJECTION_MATRIX_INVERSE combined_projection_matrix_inverse
#endif

bool raymarch_depth_buffer(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_dir,
    float dither,
    uint intersection_step_count,
    uint refinement_step_count,
    out vec3 ray_pos
) {
    if (view_dir.z > 0.0 && view_dir.z >= -view_pos.z) {
        return false;
    }

    vec3 screen_dir = normalize(
        view_to_screen_space(SSRT_PROJECTION_MATRIX, view_pos + view_dir, true)
        - screen_pos
    );

    float ray_length = min_of(
        abs(sign(screen_dir) - screen_pos) / max(abs(screen_dir), eps)
    );

    float step_length = ray_length * rcp(float(intersection_step_count));

    vec3 ray_step = screen_dir * step_length;
    ray_pos
        = screen_pos + dither * ray_step + length(view_pixel_size) * screen_dir;

    float depth_tolerance = max(
        abs(ray_step.z) * 3.0,
        0.02 / sqr(view_pos.z)
    ); // from DrDesten <3

    bool hit = false;

    // Intersection loop

    for (int i = 0; i < intersection_step_count; ++i, ray_pos += ray_step) {
#ifdef LOD_MOD_ACTIVE
        if (ray_pos.z < 0.0) {
            continue;
        }
#endif
        if (clamp01(ray_pos) != ray_pos) {
            return false;
        }

        float depth = texelFetch(
                          SSRT_DEPTH_SAMPLER,
                          ivec2(ray_pos.xy * view_res * taau_render_scale),
                          0
        )
                          .x;

        if (depth < ray_pos.z
            && abs(depth_tolerance - (ray_pos.z - depth)) < depth_tolerance) {
            hit = true;
            break;
        }
    }

    if (!hit) {
        return false;
    }

    // Refinement loop

    float final_depth;

    for (int i = 0; i < refinement_step_count; ++i) {
        ray_step *= 0.5;

        float depth = texelFetch(
                          SSRT_DEPTH_SAMPLER,
                          ivec2(ray_pos.xy * view_res * taau_render_scale),
                          0
        )
                          .x;

        if (depth < ray_pos.z
            && abs(depth_tolerance - (ray_pos.z - depth)) < depth_tolerance) {
            ray_pos -= ray_step;
        } else {
            ray_pos += ray_step;
        }

        final_depth = depth;
    }

    // No intersection if the binary search landed on a sky pixel or a hand
    // pixel
    return hand_depth < final_depth && final_depth < 1.0;
}

// ----------------------
//   Specular Highlight
// ----------------------

// GGX spherical area light approximation from Horizon: Zero Dawn
// https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa
float get_NoH_squared(float NoL, float NoV, float LoV, float light_radius) {
    float radius_cos = cos(light_radius);
    float radius_tan = tan(light_radius);

    // Early out if R falls within the disc​
    float RoL = 2.0 * NoL * NoV - LoV;
    if (RoL >= radius_cos) {
        return 1.0;
    }

    float r_over_length_t
        = radius_cos * radius_tan * inversesqrt(1.0 - RoL * RoL);
    float not_r = r_over_length_t * (NoV - RoL * NoL);
    float vot_r = r_over_length_t * (2.0 * NoV * NoV - 1.0 - RoL * LoV);

    // Calculate dot(cross(N, L), V). This could already be calculated and
    // available.​
    float triple = sqrt(
        clamp01(1.0 - NoL * NoL - NoV * NoV - LoV * LoV + 2.0 * NoL * NoV * LoV)
    );

    // Do one Newton iteration to improve the bent light Direction​
    float NoB_r = r_over_length_t * triple,
          VoB_r = r_over_length_t * (2.0 * triple * NoV);
    float NoL_vt_r = NoL * radius_cos + NoV + not_r,
          LoV_vt_r = LoV * radius_cos + 1.0 + vot_r;
    float p = NoB_r * LoV_vt_r, q = NoL_vt_r * LoV_vt_r, s = VoB_r * NoL_vt_r;
    float x_num = q * (-0.5 * p + 0.25 * VoB_r * NoL_vt_r);
    float x_denom = p * p + s * ((s - 2.0 * p))
        + NoL_vt_r
            * ((NoL * radius_cos + NoV) * LoV_vt_r * LoV_vt_r
               + q * (-0.5 * (LoV_vt_r + LoV * radius_cos) - 0.5));
    float two_x_1 = 2.0 * x_num / (x_denom * x_denom + x_num * x_num);
    float sin_theta = two_x_1 * x_denom;
    float cos_theta = 1.0 - two_x_1 * x_num;
    not_r
        = cos_theta * not_r + sin_theta * NoB_r; // use new T to update not_r​
    vot_r
        = cos_theta * vot_r + sin_theta * VoB_r; // use new T to update vot_r​

    // Calculate (N.H)^2 based on the bent light direction​
    float new_NoL = NoL * radius_cos + not_r;
    float new_LoV = LoV * radius_cos + vot_r;
    float NoH = NoV + new_NoL;
    float HoH = 2.0 * new_LoV + 2.0;

    return clamp01(NoH * NoH / HoH);
}

vec3 get_specular_highlight(
    Material material,
    float NoL,
    float NoV,
    float NoH,
    float LoV,
    float LoH
) {
    const float specular_max_value
        = 4.0; // Maximum value imposed on specular highlight to prevent it from
               // overloading bloom

#if defined WORLD_OVERWORLD
    const float sun_angular_radius = sunAngularRadius * degree;
    const float moon_angular_radius = moonAngularRadius * degree;
    float light_radius
        = (sunAngle < 0.5) ? sun_angular_radius : moon_angular_radius;

    // No specular highlight on a new moon
    if (sunAngle > 0.5 && moonPhase == 4) {
        return vec3(0.0);
    }
#else
    const float light_radius = sunAngularRadius * degree;
#endif

    vec3 fresnel;
    if (material.is_hardcoded_metal) {
        fresnel = fresnel_conductor(LoH, material.f0, material.f82);
    } else if (material.is_metal) {
        fresnel = fresnel_schlick(LoH, material.albedo);
    } else {
        fresnel = fresnel_dielectric(LoH, material.f0.x);
    }

    if (NoL <= eps) {
        return vec3(0.0);
    }
    if (all(lessThan(fresnel, vec3(1e-2)))) {
        return vec3(0.0);
    }

    vec3 albedo_tint
        = mix(vec3(1.0), material.albedo, float(material.is_hardcoded_metal));

    float NoH_squared = get_NoH_squared(NoL, NoV, LoV, light_radius);
    float alpha_squared = material.roughness * material.roughness;

    float d = distribution_ggx(NoH_squared, alpha_squared);
    float v = v2_smith_ggx(max(NoL, 1e-2), max(NoV, 1e-2), alpha_squared);

    return min((NoL * d * v) * fresnel * albedo_tint, vec3(specular_max_value));
}

// ------------------------
//   Specular Reflections
// ------------------------

vec3 sample_ggx_vndf(vec3 viewer_dir, vec2 alpha, vec2 hash) {
    /*
        // from https://jcgt.org/published/0007/04/01/paper.pdf: "Sampling the
    GGX distribution of visible normals"

        // Section 3.2: transforming the view direction to the hemisphere
    configuration viewer_dir = normalize(vec3(alpha * viewer_dir.xy,
    viewer_dir.z));

        // Section 4.1: orthonormal basis (with special case if cross product is
    zero) float len_sq = length_squared(viewer_dir.xy); vec3 T1 = (len_sq > 0) ?
    vec3(-viewer_dir.y, viewer_dir.x, 0) * inversesqrt(len_sq) : vec3(1.0, 0.0,
    0.0); vec3 T2 = cross(viewer_dir, T1);

        // Section 4.2: parameterization of the projected area
        float r = sqrt(hash.x);
        float phi = 2.0 * pi * hash.y;
        float t1 = r * cos(phi);
        float t2 = r * sin(phi);
        float s = 0.5 + 0.5 * viewer_dir.z;

        t2 = (1.0 - s) * sqrt(1.0 - t1 * t1) + s * t2;

        // Section 4.3: reprojection onto hemisphere
        vec3 normal = t1 * T1 + t2 * T2 + sqrt(max0(1.0 - t1 * t1 - t2 * t2)) *
    viewer_dir;

        // Section 3.4: transforming the normal back to the ellipsoid
    configuration normal = normalize(vec3(alpha * normal.xy, max0(normal.z)));

        return normal;
    /*/
    // Improved GGX importance sampling function by zombye
    // https://ggx-research.github.io/publication/2023/06/09/publication-ggx.html

    // Transform viewer direction to the hemisphere configuration
    viewer_dir = normalize(vec3(alpha * viewer_dir.xy, viewer_dir.z));

    // Sample a reflection direction off the hemisphere
    const float tau = 6.2831853; // 2 * pi
    float phi = tau * hash.x;
    float cos_theta = fma(1.0 - hash.y, 1.0 + viewer_dir.z, -viewer_dir.z);
    float sin_theta = sqrt(clamp(1.0 - cos_theta * cos_theta, 0.0, 1.0));
    vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sin_theta, cos_theta);

    // Evaluate halfway direction
    // This gives the normal on the hemisphere
    vec3 halfway = reflected + viewer_dir;

    // Transform the halfway direction back to hemiellispoid configuation
    // This gives the final sampled normal
    return normalize(vec3(alpha * halfway.xy, halfway.z));
    //*/
}

vec3 get_sky_reflection(vec3 ray_dir, float skylight, vec3 hit_pos) {
#if defined WORLD_OVERWORLD
    bool hit_sky
        = false; // clamp01(hit_pos.xy) == hit_pos.xy && hit_pos.z >= 1.0;
    float skylight_falloff
        = hit_sky ? 1.0 : pow12(linear_step(0.0, 0.75, skylight));
    vec3 reflection = bicubic_filter(colortex4, project_sky(ray_dir)).rgb
        * skylight_falloff;
#else
    vec3 reflection = texture(colortex4, project_sky(ray_dir)).rgb;
#endif

#ifdef moonPhaseReflections
    // Only shape the reflected sky's moon contribution at night
    if (sunAngle > 0.5) {
        reflection = apply_moon_phase_influence(
            reflection,
            moonPhaseReflectionsIntensity * moonPhaseInfluenceIntensity,
            1.00,
            1.00
        );
    }
#endif

    return reflection;
}

vec3 trace_specular_ray(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 world_pos,
    vec3 ray_dir,
    float dither,
    float skylight,
    uint intersection_step_count,
    uint refinement_step_count,
    int mip_level
) {
    vec3 view_dir = mat3(gbufferModelView) * ray_dir;

#ifdef environmentReflections
    vec3 hit_pos;
    bool hit = raymarch_depth_buffer(
        screen_pos,
        view_pos,
        view_dir,
        dither,
        intersection_step_count,
        refinement_step_count,
        hit_pos
    );
#else
    const bool hit = false;
    const vec3 hit_pos = vec3(0.0);
#endif

#ifdef skyReflections
    vec3 sky_reflection = get_sky_reflection(ray_dir, skylight, hit_pos);
#else
    const vec3 sky_reflection = vec3(0.0);
#endif

    if (hit) {
        float border_attenuation_factor
            = mix(0.01, eps, pow4(clamp01(1.0 - gbufferModelViewInverse[2].y)));
        float border_attenuation = (hit_pos.x * hit_pos.y - hit_pos.x)
            * (hit_pos.x * hit_pos.y - hit_pos.y);
        border_attenuation = dampen(
            linear_step(0.0, border_attenuation_factor, border_attenuation)
        );

        vec3 hit_pos_view = screen_to_view_space(
            SSRT_PROJECTION_MATRIX_INVERSE,
            hit_pos,
            false
        );
        vec3 hit_pos_scene = view_to_scene_space(hit_pos_view);

        vec2 hit_uv_prev
            = reproject_scene_space(hit_pos_scene, false, false).xy;
        if (clamp01(hit_uv_prev) != hit_uv_prev) {
            return sky_reflection;
        }

        vec3 reflection = textureLod(colortex5, hit_uv_prev, mip_level).rgb;

        vec3 fog_scattering_previous = texture(colortex7, hit_uv_prev).rgb;

#if defined WORLD_OVERWORLD
#ifdef vl


        // the direction of the sun then the fog would be shadowed by the hit

        float fog_shadow = hit ? 1.0 - sqr(max0(dot(light_dir, ray_dir))) : 1.0;
#else
        const float fog_shadow = 1.0;
#endif

        // Apply analytic fog in reflection
        mat2x3 analytic_fog = air_fog_analytic(
            world_pos,
            hit_pos_scene + cameraPosition,
            false,
            eye_skylight,
            fog_shadow
        );

        reflection = max0(reflection - fog_scattering_previous);
        reflection = reflection * analytic_fog[1] + analytic_fog[0];
#endif

        return mix(sky_reflection, reflection, border_attenuation);
    } else {
        // SSR miss falls back to sky.
        return sky_reflection;
    }
}

vec3 get_specular_reflections(
    Material material,
    mat3 tbn_matrix,
    vec3 screen_pos,
    vec3 view_pos,
    vec3 world_pos,
    vec3 normal,
    vec3 flat_normal,
    vec3 world_dir,
    vec3 tangent_dir,
    float skylight,
    bool is_water
) {
    vec3 albedo_tint
        = material.is_hardcoded_metal ? material.albedo : vec3(1.0);

    float alpha_squared = material.roughness * material.roughness;
    float dither = r1(
        frameCounter,
        texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b
    );

#ifdef LOD_MOD_ACTIVE
    // Convert screen depth to combined depth
    screen_pos = view_to_screen_space(SSRT_PROJECTION_MATRIX, view_pos, true);
#endif

#if defined ssrRoughnessSupport && defined specularMapping
    if (!is_water) { // Rough reflection
        float mip_level
            = min(8.0 * (1.0 - pow8(1.0 - material.roughness)), 5.0);

        vec3 reflection = vec3(0.0);

        for (int i = 0; i < ssrRayCount; ++i) {
            vec2 hash;
            hash.x = interleaved_gradient_noise(
                gl_FragCoord.xy,
                frameCounter * ssrRayCount + i
            );
            hash.y = interleaved_gradient_noise(
                gl_FragCoord.xy + vec2(97.0, 23.0),
                frameCounter * ssrRayCount + i
            );

            vec3 microfacet_normal = tbn_matrix
                * sample_ggx_vndf(-tangent_dir, vec2(material.roughness), hash);
            vec3 ray_dir = reflect(world_dir, microfacet_normal);

            float NoL = dot(normal, ray_dir);
            if (NoL < eps) {
                continue;
            }

            vec3 radiance = trace_specular_ray(
                screen_pos,
                view_pos,
                world_pos,
                ray_dir,
                dither,
                skylight,
                ssrIntersectionStepsRough,
                ssrRefinementSteps,
                int(mip_level)
            );

            float NoV = max(1e-2, dot(flat_normal, -world_dir));
            float MoV = max(1e-2, dot(microfacet_normal, -world_dir));

            // Microfacet Fresnel takes V.H (MoV), not the geometric NoV
            vec3 fresnel;
            if (material.is_hardcoded_metal) {
                fresnel = fresnel_conductor(MoV, material.f0, material.f82);
            } else if (material.is_metal) {
                fresnel = fresnel_schlick(MoV, material.albedo);
            } else {
                fresnel = fresnel_dielectric(MoV, material.f0.x);
            }

            float v1 = v1_smith_ggx(NoV, alpha_squared);
            float v2 = v2_smith_ggx(NoL, NoV, alpha_squared);

            reflection += radiance * fresnel * (2.0 * NoL * v2 / v1);
        }

        reflection *= albedo_tint * rcp(float(ssrRayCount));
        if (any(isnan(reflection))) {
            reflection = vec3(0.0); // don't reflect NaNs
        }
        return reflection * material.ssr_multiplier;
    }
#else
    // Fade reflection when rough reflections are disabled
    if (material.roughness > 0.05) {
        material.f0 *= 1.0 - sqr(material.roughness);
        material.ssr_multiplier = sqr(1.0 - material.roughness);
    }
#endif

    // Mirror-like reflections

    vec3 ray_dir = reflect(world_dir, normal);

    float NoL = dot(normal, ray_dir);
    float NoV = clamp01(dot(normal, -world_dir));

    if (NoL < eps) {
        return vec3(0.0);
    }

    vec3 fresnel;
    if (material.is_hardcoded_metal) {
        fresnel = fresnel_conductor(NoV, material.f0, material.f82);
    } else if (material.is_metal) {
        fresnel = fresnel_schlick(NoV, material.albedo);
    } else {
        fresnel = fresnel_dielectric(NoV, material.f0.x);
    }

    float v1 = v1_smith_ggx(NoV, alpha_squared);
    float v2 = v2_smith_ggx(NoL, NoV, alpha_squared);

    vec3 reflection = trace_specular_ray(
        screen_pos,
        view_pos,
        world_pos,
        ray_dir,
        dither,
        skylight,
        ssrIntersectionStepsSmooth,
        ssrRefinementSteps,
        0
    );
    reflection *= albedo_tint * fresnel;

    if (any(isnan(reflection))) {
        reflection = vec3(0.0); // don't reflect NaNs
    }

    return reflection * material.ssr_multiplier;
}

#endif // INCLUDE_LIGHTING_BSDF_SPECULAR_LIGHTING
