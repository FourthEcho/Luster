#if !defined INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT
#define INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT

// ============================================================================
//  Screen-space path traced emission + indirect lighting
// ----------------------------------------------------------------------------

#include "/include/lighting/colors/blocklight_color.glsl"
#include "/include/lighting/handheld_lighting.glsl"
#include "/include/lighting/cloud_shadows.glsl"
#include "/include/lighting/direct_lighting/distortion.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"
#include "/include/surface/material.glsl"
#include "/include/sky/projection.glsl"

// ----------------------------------------------------------------------------
// Resolution bookkeeping
// ----------------------------------------------------------------------------
//  The SSPT chain runs in colortex17/18/19/20 allocated at half resolution
//  (size.buffer.* = 0.5 0.5, same convention as the AO buffers colortex6/14).
//  A pass bound to those buffers sees gl_FragCoord in buffer texels while
//  uv still spans the whole screen, so gbuffer fetches remap as:
//      gbuffer texel = uv * view_res * taau_render_scale
//  (No bufferScale const here: d5/d6 own theirs; this file traces at
//  full gbuffer texels via view_res * taau_render_scale.)

// ----------------------------------------------------------------------------
/* DITHER */
// ----------------------------------------------------------------------------
// (hash22 below is the only dither hash used.)

#define HASHSCALE3 vec3(0.1031, 0.1030, 0.0973)
vec2 hash22(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ----------------------------------------------------------------------------
/* COSINE HEMISPHERE SAMPLING */
// ----------------------------------------------------------------------------

vec3 genUnitVector(vec2 p) {
    p.x *= tau; p.y = p.y * 2.0 - 1.0;
    return vec3(cos(p.x) * sqrt(1.0 - p.y * p.y),
                sin(p.x) * sqrt(1.0 - p.y * p.y),
                p.y);
}

// Lambertian BRDF sampling without a tangent frame (Malley's method).
// Deals with the rare case where cosineVector == (0,0,0).
// http://www.amietia.com/lambertnotangent.html
vec3 cosineVector(vec3 vector, vec2 xy) {
    vec3 cosine_vector = vector + genUnitVector(xy);
    float len_sq = dot(cosine_vector, cosine_vector);
    return len_sq > 0.0 ? cosine_vector * inversesqrt(len_sq) : vector;
}

// ----------------------------------------------------------------------------
/* SCREENSPACE RAYTRACER */
// ----------------------------------------------------------------------------
//  Two variants, switchable with ssptFullRangeRT.
//  Returns vec3(screen uv, depth) on hit, vec3(1.1) on miss.
//  Hits use a 10% relative view-depth threshold, checked in view space
//  so DH combined-depth and normal projections both work.

vec3 rayHit(vec3 screen_pos) {
    float depth_sample = texelFetch(
        TRACE_DEPTH,
        ivec2(screen_pos.xy * view_res * taau_render_scale),
        0
    ).x;

    if (depth_sample >= screen_pos.z) return vec3(1.1); // no occlusion yet

    float hit_view_depth = screen_to_view_space_depth(TRACE_PROJ_INV, depth_sample);
    float ray_view_depth = screen_to_view_space_depth(TRACE_PROJ_INV, screen_pos.z);

    float dist = abs(hit_view_depth - ray_view_depth) / max(abs(ray_view_depth), 1e-6);

    return dist <= 0.1 ? vec3(screen_pos.xy, depth_sample) : vec3(1.1);
}

#ifdef ssptFullRangeRT
//  Works fully in screenspace. Potentially every pixel can be hit. Needs a
//  lot more iterations for results of similar quality.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint max_steps = 16;

    float ray_length = ((position.z + direction.z * far * sqrt(3.0)) > -sqrt(3.0) * near)
                      ? (-sqrt(3.0) * near - position.z) / direction.z : far * sqrt(3.0);

    vec3 screen_position = view_to_screen_space(TRACE_PROJ, position, true);
    vec3 end_position = position + direction * ray_length;
    vec3 end_screen_position = view_to_screen_space(TRACE_PROJ, end_position, true);

    vec3 screen_direction = normalize(end_screen_position - screen_position);
        screen_direction.xy = normalize(screen_direction.xy);

    vec3 max_length = (step(0.0, screen_direction) - screen_position) / screen_direction;
    float step_mult = min_of(max_length);
    vec3 screen_vector = screen_direction * step_mult / float(max_steps);

    vec3 screen_pos = screen_position
        + screen_direction * max_of(view_pixel_size * pi);

    if (clamp01(screen_pos.xy) == screen_pos.xy) {
        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;
    }

        screen_pos += screen_vector * noise;

    for (uint i = 0; i < max_steps; ++i) {
        if (clamp01(screen_pos.xy) != screen_pos.xy) break;

        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;

        screen_pos += screen_vector;
    }

    return vec3(1.1);
}
#else
//  Short range variant (default). Traces a bounded view-space
//  distance and rescales the step vector so the ray ends on-screen.
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint max_steps = 10;
    const float step_size = tau / float(max_steps);

    vec3 step_vector = direction * step_size;

    vec3 end_position = position + step_vector * float(max_steps);
    vec3 end_screen_position = view_to_screen_space(TRACE_PROJ, end_position, true);

    vec2 max_pos_xy = max(abs(end_screen_position.xy * 2.0 - 1.0), vec2(1.0));
    float step_mult = min_of(rcp(max_pos_xy));
        step_vector *= step_mult;

    // closest texel iteration
    vec3 sample_pos = position;

        sample_pos += step_vector / 6.0;
    vec3 screen_pos = view_to_screen_space(TRACE_PROJ, sample_pos, true);

    if (clamp01(screen_pos.xy) == screen_pos.xy) {
        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;
    }

        sample_pos += step_vector * noise;

    for (uint i = 0; i < max_steps; ++i) {
        vec3 screen_pos = view_to_screen_space(TRACE_PROJ, sample_pos, true);
            sample_pos += step_vector;
        if (clamp01(screen_pos.xy) != screen_pos.xy) break;

        vec3 hit = rayHit(screen_pos);
        if (hit.z < 1.0) return hit;
    }

    return vec3(1.1);
}
#endif

// ----------------------------------------------------------------------------
/* HIT SURFACE DATA — Luster-main gbuffer unpack (kept for the bounce path) */
// ----------------------------------------------------------------------------
//  The packing is the one d4_deferred_shading writes into colortex1: two
//  2x8 unorm pairs for albedo, one for the material mask, an octahedral
//  flat normal, and the light levels.

struct HitData {
    vec3 albedo;
    vec3 scene_normal;
    vec2 light_levels;
    uint mask;
};

HitData unpackHit(vec4 gbuffer_data) {
    HitData hit;

    hit.albedo = vec3(
        unpack_unorm_2x8(gbuffer_data.x),
        unpack_unorm_2x8(gbuffer_data.y).x
    );
    hit.mask = uint(255.0 * unpack_unorm_2x8(gbuffer_data.y).y);
    hit.scene_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data.z));
    hit.light_levels = unpack_unorm_2x8(gbuffer_data.w);

    return hit;
}

// ----------------------------------------------------------------------------
/* HIT SURFACE EMISSION — material path */
// ----------------------------------------------------------------------------
//  material_from() reconstructs hardcoded emission from the gbuffer, while
//  the shared global emission decoder supplies resource-pack map emission.
//  The same global curve/intensity controls both direct lighting and SSPT,
//  while SSPT_INTENSITY remains the path-level bounce multiplier.

vec3 hitEmission(vec4 hit_data_0, ivec2 hit_texel, vec3 hit_view_pos) {
    vec3 hit_albedo = vec3(
        unpack_unorm_2x8(hit_data_0.x),
        unpack_unorm_2x8(hit_data_0.y).x
    );
    uint hit_mask = uint(255.0 * unpack_unorm_2x8(hit_data_0.y).y);
    vec3 hit_scene_normal = decode_unit_vector(unpack_unorm_2x8(hit_data_0.z));
    vec2 hit_light_levels = unpack_unorm_2x8(hit_data_0.w);

    // world position for position-dependent hardcoded emission
    vec3 hit_world_pos = view_to_scene_space(hit_view_pos) + cameraPosition;

    Material hit_material = material_from(
        hit_albedo,
        hit_mask,
        hit_world_pos,
        hit_scene_normal,
        hit_light_levels
    );

#ifdef HARDCODED_EMISSION
    decode_emission(vec4(0.0), hit_material);
#else
    vec4 hit_specular_map = texelFetch(colortex2, hit_texel, 0);
    vec4 map = vec4(
        unpack_unorm_2x8(hit_specular_map.z),
        unpack_unorm_2x8(hit_specular_map.w)
    );
    decode_emission(map, hit_material);
#endif

    // Match the primary Luster-style emissive response: the emitter's
    // own albedo modulates its emitted source radiance. This keeps bright
    // emissive blocks from becoming an independent white-hot HDR pool when
    // SSPT is enabled, while preserving the source texture detail.
    return hit_material.emission * hit_material.albedo
        * emission_scale * SSPT_INTENSITY;
}

// ----------------------------------------------------------------------------
/* HIT DIRECT LIGHT — sun/moon + handheld bounce */
// ----------------------------------------------------------------------------
//  Shadowed sun/moon light at the traced hit, tinted by the hit albedo (one
//  hardware-filtered shadowtex1 tap, stained-glass transmission, cloud
//  shadows), plus the held light source evaluated at the hit with the exact
//  falloff/color of the primary pass. Skylight stays out (owned by the
//  traced sky / bent-cone ambient, never by the bounce itself).
//  The sun/moon part needs shadow maps (Overworld/End with SHADOW); the
//  handheld part is independent of shadows and worlds, so a held torch
//  bounces everywhere — Nether included, in both NORMAL and COLORED modes
//  (get_handheld_light_color resolves the mode internally).

#if defined SHADOW && !defined WORLD_NETHER
#define DIRECT_SUN_BOUNCE 1
#endif
#ifdef HANDHELD_LIGHTING
#define DIRECT_HANDHELD_BOUNCE 1
#endif
// Skylight bounce: the hit surface's own sky exposure (light_levels.y),
// sampled directionally from the live sky map at the hit normal. Always
// on under SSPT (no separate toggle) -- this is what lets light passing
// through a cave opening bounce off the sunlit wall onto its neighbors
// instead of just lighting the one surface directly under the hole.
// (Pixel-level sky for escaped rays is gathered separately in
// traceIndirect; there is no SH skylight term left to own it.)
#define DIRECT_SKY_BOUNCE 1

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE

// Sun radiance, evaluated locally so the trace pass does not drag in the
// full atmosphere include chain. Same evaluation as the primary shading
// path's light colors (include/lighting/colors/light_color.glsl).
#ifdef DIRECT_SUN_BOUNCE
vec3 sunRadiance() {
    float blue_hour = linear_step(0.05, 1.0, exp(-190.0 * sqr(sun_dir.y + 0.09604)));
    float exposure = 7.0 * SUN_I
                   * (1.0 + 0.5 * (time_sunset + time_sunrise) + 40.0 * blue_hour);

    vec3 tint = mix(
        vec3(1.0),
        vec3(1.05, 0.84, 0.93) * 1.2,
        sqr(pulse(sun_dir.y, 0.17, 0.40))
    );
    tint *= mix(vec3(1.0), vec3(0.95, 0.80, 1.0), blue_hour);

    vec3 user_tint = mix(
        from_display(vec3(SUN_NR, SUN_NG, SUN_NB)),
        from_display(vec3(SUN_MR, SUN_MG, SUN_MB)),
        time_sunrise
    );
    user_tint = mix(user_tint, from_display(vec3(SUN_ER, SUN_EG, SUN_EB)), time_sunset);

    return exposure * tint * user_tint;
}

// Moon radiance. Moon-phase albedo influence is intentionally not applied:
// the bounce uses the raw moon color.
vec3 moonRadiance() {
    float night_boost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sun_dir.y, 0.1)));
    float exposure = 0.66 * MOON_I * moon_phase_brightness * night_boost;
    return exposure * from_display(vec3(MOON_R, MOON_G, MOON_B));
}
#endif // DIRECT_SUN_BOUNCE

vec3 hitDirectLight(HitData hit, vec3 hit_view_pos) {
    vec3 hit_scene_pos = view_to_scene_space(hit_view_pos);
    vec3 sun_moon_direct = vec3(0.0);
    vec3 indirect_direct = vec3(0.0);

#ifdef DIRECT_SUN_BOUNCE
    // Sun/moon contribution: conditional, so a sunless hit (facing away,
    // fully shadowed, deep cave) still falls through to the handheld term
    // below instead of earlying out.
    vec3 light_dir_world = sunAngle < 0.5 ? sun_dir : moon_dir;

    float NoL = dot(hit.scene_normal, light_dir_world);
    if (NoL > 0.0) {
        vec3 bias = get_shadow_bias(hit_scene_pos, hit.scene_normal, NoL, hit.light_levels.y);
        vec3 shadow_view_pos = transform(shadowModelView, hit_scene_pos + bias);
        vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);
        vec3 shadow_coords = distort_shadow_space(shadow_clip_pos) * 0.5 + 0.5;

        bool outside_shadow_map = any(lessThan(shadow_coords, vec3(0.0)))
                               || any(greaterThan(shadow_coords, vec3(1.0)));

        float visibility = outside_shadow_map ? 1.0 : texture(shadowtex1, shadow_coords);
        if (visibility > 0.0) {
            vec3 radiance = sunAngle < 0.5 ? sunRadiance() : moonRadiance();
            sun_moon_direct = radiance * (visibility * NoL);

#ifdef SHADOW_COLOR
            if (!outside_shadow_map) {
                // Sunlight passing through stained glass picks up the glass tint.
                ivec2 shadow_texel = ivec2(shadow_coords.xy * vec2(textureSize(shadowtex0, 0)));
                float blocker_depth = texelFetch(shadowtex0, shadow_texel, 0).x;
                vec3 transmission = texelFetch(shadowcolor0, shadow_texel, 0).rgb;
                sun_moon_direct *= mix(vec3(1.0), 4.0 * transmission, step(blocker_depth, shadow_coords.z));
            }
#endif

#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
            sun_moon_direct *= get_cloud_shadows(colortex8, hit_scene_pos);
#endif
        }
    }
#endif // DIRECT_SUN_BOUNCE

#ifdef DIRECT_SKY_BOUNCE
    // Skylight bounce: the hit surface's own sky exposure, sampled
    // directionally from the live sky map (same map H_BASIS_SKYLIGHT's
    // projection samples) at the hit's flat normal. No shadow/occlusion
    // tap needed -- light_levels.y already encodes the block-light-engine's
    // sky visibility at the hit, and the directional sample means a hit
    // facing away from open sky still gets a dim/tinted contribution
    // rather than a flat ambient add.
    vec3 sky_radiance = texture(colortex4, project_sky(hit.scene_normal)).rgb;
    indirect_direct += sky_radiance * hit.light_levels.y;
#endif // DIRECT_SKY_BOUNCE

#ifdef DIRECT_HANDHELD_BOUNCE
    // Held light source as traced bounce light: evaluated at the hit with
    // the exact falloff and color the primary pass uses
    // (get_handheld_lighting expects a camera-relative position, which is
    // what hit_scene_pos is; the NORMAL vs COLORED mode is resolved inside
    // get_handheld_light_color). AO passes as 1.0 — the hit's own occlusion
    // is unknown here and the path throughput already shapes the result.
    // No shadow tap: bare falloff, like the primary pass.
    indirect_direct += get_handheld_lighting(hit_scene_pos, 1.0);
#endif

    // SUN_I/MOON_I own the direct sun/moon bounce radiance;
    // SSPT_INTENSITY scales the indirect paths below, so every
    // contribution is counted exactly once.
    return hit.albedo * (sun_moon_direct + indirect_direct * SSPT_INTENSITY);
}

#endif // defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE

// ----------------------------------------------------------------------------
/* HAMMON DIFFUSE BRDF */
// ----------------------------------------------------------------------------

float fresnelSchlickInverse(float f0, float VoH) {
    return 1.0 - clamp01(f0 + (1.0 - f0) * pow5(1.0 - VoH));
}

float diffuseHammon(vec3 normal, vec3 viewDir, vec3 lightDir, float roughness) {
    float n_dot_l = max0(dot(normal, lightDir));

    if (n_dot_l <= 0.0) return 0.0;

    float n_dot_v = max0(dot(normal, viewDir));
    float l_dot_v = max0(dot(lightDir, viewDir));

    vec3 halfway = normalize(viewDir + lightDir);
    float n_dot_h = max0(dot(normal, halfway));

    float facing = l_dot_v * 0.5 + 0.5;

    float single_rough = facing * (0.9 - 0.4 * facing)
                       * ((0.5 + n_dot_h) * rcp(max(n_dot_h, 0.02)));
    float single_smooth = 1.05 * fresnelSchlickInverse(0.0, n_dot_l)
                        * fresnelSchlickInverse(0.0, max0(n_dot_v));

    float single = clamp01(mix(single_smooth, single_rough, roughness) * rcp_pi);
    float multi = 0.1159 * roughness;

    return clamp01((multi + single) * n_dot_l);
}

// Clamped Hammon diffuse BRDF, normalized by the cosine lobe the ray was
// drawn from. Used as the multibounce path weight.
float brdfWeight(vec3 normal, vec3 incoming, vec3 outgoing) {
    return clamp(
        diffuseHammon(normal, incoming, outgoing, 1.0)
            / clamp01(dot(outgoing, normal) * rcp_pi),
        0.0, half_pi
    );
}

// ----------------------------------------------------------------------------
// INDIRECT TRACER
// ----------------------------------------------------------------------------
//  Returns emission + direct-light bounce for this pixel (raw,
//  noisy — temporal accumulation and the SVGF filter stabilize it
//  downstream). Emission uses a cubic distance falloff and the
//  clamped Hammon BRDF weight; the bounce carries no distance falloff
//  and is tinted by the hit albedo inside hitDirectLight. Multibounce
//  tints deeper hits with every intervening surface's albedo. Sky
//  ambient is NOT gathered here (no sky-on-escape): directional sky
//  belongs to the sky-map ambient term, so the two can never double-count.

vec3 traceIndirect(
    vec3 view_pos,
    vec3 scene_normal,
    vec2 dither,
    bool hand,
    out bool geometry_hit
) {
    vec3 view_normal = mat3(gbufferModelView) * scene_normal;

    vec3 emission = vec3(0.0);
    geometry_hit = false;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    vec3 bounce = vec3(0.0);
    // Candidate count for bounce normalization: bounce averages over
    // candidates like emission does, not over hits.
    float bounce_samples = 0.0;
#endif

    // R2-sequence constants: 1/rho and 1/rho^2 (plastic constant)
    const float a1 = 1.0 / 1.3247179572447460;
    const float a2 = a1 * a1;

    #if ssptBounces <= 1

    /* ------ SINGLE BOUNCE ------ */
    //  Every candidate is a cosine-lobe ray, stratified over pixel +
    //  frame + candidate index so temporal accumulation blends them.

    vec2 quasirandom_curr = 0.5 + fract(vec2(a1, a2) * float(frameCounter) + 0.5);

    vec2 noise_curr = hash22(gl_FragCoord.xy + float(frameCounter));

    for (uint i = 0; i < ssptSPP; ++i) {
        ++quasirandom_curr;
        noise_curr += hash22(
            vec2(gl_FragCoord.xy + vec2(cos(quasirandom_curr.x), sin(quasirandom_curr.y)))
        );

        vec2 vector_xy = fract(sqrt(2.0) * quasirandom_curr + noise_curr);

        // Cosine-candidate count lives here (not in the hit branch):
        // bounce must average over candidates like emission does, not
        // over hits (which overstates by 1/hit_rate, ~2x outdoors).
        // Matches the multibounce branch below and Kappa's /SPP.
        bounce_samples += 1.0;

        vec3 ray_direction = cosineVector(scene_normal, vector_xy);
            ray_direction = normalize(mat3(gbufferModelView) * ray_direction);

        if (dot(view_normal, ray_direction) < 0.0) ray_direction = -ray_direction;

        float brdf = brdfWeight(view_normal, -normalize(view_pos), ray_direction);

        vec3 hit_position = screenspaceRT(view_pos, ray_direction, dither.y);

        if (hit_position.z < 1.0) {
            geometry_hit = true;
            ivec2 hit_texel = ivec2(hit_position.xy * view_res * taau_render_scale);
            vec4 hit_data_0 = texelFetch(colortex1, hit_texel, 0);

            vec3 hit_view_pos = screen_to_view_space(TRACE_PROJ_INV, hit_position, true);

            // Cubic emission distance falloff.
            float emission_falloff = 1.0 - linear_step(
                ssptEmissionDistance * rcp_pi,
                ssptEmissionDistance,
                distance(hit_view_pos, view_pos)
            );
                emission_falloff = cube(emission_falloff);

            emission += hitEmission(hit_data_0, hit_texel, hit_view_pos)
                      * emission_falloff * brdf;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
            // Direct-light bounce: no distance falloff, BRDF-weighted.
            // (Counted per cosine candidate above, not per hit.)
            bounce += hitDirectLight(unpackHit(hit_data_0), hit_view_pos) * brdf;
#endif
        }
    }

    #else

    /* ------ MULTIBOUNCE (ssptBounces > 1) ------ */
    //  Each sample paths through up to ssptBounces surfaces. The running
    //  contribution (brdf-weighted, albedo-tinted) colors emission
    //  gathered on later bounces with every intervening surface's albedo.
    //  Sky escapes end the chain.

    for (uint i = 0; i < ssptSPP; ++i) {
        int frame_counter_new = frameCounter + int(i) * 31;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
        // Multibounce samples are all cosine-lobe: count every sample so
        // the shared normalization below reproduces the old average.
        bounce_samples += 1.0;
#endif

        vec2 quasirandom_curr = 0.5 + fract(vec2(a1, a2) * float(frame_counter_new) + 0.5);

        vec2 noise_curr = hash22(gl_FragCoord.xy + float(frame_counter_new));

        vec3 contribution = vec3(1.0);

        vec3 ray_direction = -normalize(view_pos);

        vec3 hit_normal = view_normal;
        vec3 hit_normal_scene = scene_normal;

        for (uint n = 0; n < ssptBounces; ++n) {
            ++quasirandom_curr;
            noise_curr += hash22(
                vec2(gl_FragCoord.xy + vec2(cos(quasirandom_curr.x), sin(quasirandom_curr.y)))
            );

            vec2 vector_xy = fract(sqrt(2.0) * quasirandom_curr + noise_curr);

            vec3 old_direction = ray_direction;

                ray_direction = cosineVector(hit_normal_scene, vector_xy);
                ray_direction = normalize(mat3(gbufferModelView) * ray_direction);

            if (dot(hit_normal, ray_direction) < 0.0) ray_direction = -ray_direction;

            vec3 hit_position = screenspaceRT(view_pos, ray_direction, dither.y);

            float brdf = brdfWeight(hit_normal, -old_direction, ray_direction);
                contribution *= brdf;

            if (hit_position.z < 1.0) {
                geometry_hit = true;
                ivec2 hit_texel = ivec2(hit_position.xy * view_res * taau_render_scale);
                vec4 hit_data_0 = texelFetch(colortex1, hit_texel, 0);

                vec3 hit_albedo = vec3(
                    unpack_unorm_2x8(hit_data_0.x),
                    unpack_unorm_2x8(hit_data_0.y).x
                );
                hit_normal_scene = decode_unit_vector(unpack_unorm_2x8(hit_data_0.z));
                hit_normal = mat3(gbufferModelView) * hit_normal_scene;

                vec3 hit_view_pos = screen_to_view_space(TRACE_PROJ_INV, hit_position, true);

                float emission_falloff = 1.0 - linear_step(
                    ssptEmissionDistance * rcp_pi,
                    ssptEmissionDistance,
                    distance(hit_view_pos, view_pos)
                );
                    emission_falloff = cube(emission_falloff);

                emission += hitEmission(hit_data_0, hit_texel, hit_view_pos)
                          * emission_falloff * contribution;

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
                // Direct-light bounce on every path vertex.
                bounce += hitDirectLight(unpackHit(hit_data_0), hit_view_pos)
                        * contribution;
#endif

                contribution *= hit_albedo; // colored bleed into deeper bounces
            } else {
                // miss: sky escape contributes no emission; stop the chain
                break;
            }
        }
    }

    #endif

    emission /= float(ssptSPP);

    // Filmic-style soft ceiling on gathered emission. Normalized emitters
    // are ~100x HDR (emission_scale x SSPT_INTENSITY), so an unsheltered
    // pool converges to 30-100+ near any lamp while the tonemap saturates
    // everything past ~2: an unsheltered pool blows out white and the
    // light's actual color never survives. Compress the hot tail so the
    // pool lands where hue is preserved (0.3 -> 0.27, 1.0 -> 0.75,
    // 9 -> 2.25, 50 -> 2.8), then a gentle chroma lift around its own
    // luminance so the tint reads through the tonemap without changing
    // brightness. Hue-preserving (luminance-anchored). Bounce lighting
    // below is separate and unaffected, as are directly viewed emitters
    // in the primary pass.
    float emission_luma = dot(max0(emission), luminance_weights);
    emission *= rcp(1.0 + emission_luma * rcp(8.0));
    float compressed_luma = dot(max0(emission), luminance_weights);
    emission = mix(vec3(compressed_luma), emission, 1.4);

#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    // Bounce averages over candidates, matching emission's normalization.
    if (bounce_samples > 0.5) bounce /= bounce_samples;
#endif

    emission *= float(!hand); // hand geometry gets no emission or sky
    // (hand keeps its direct-light bounce)

    // Hit emission is reconstructed with the same emission_scale the
    // primary shading pass applies, so a bounced photon and a directly
    // viewed emitter already agree on brightness — the values here are
    // final radiance, not raw.
#if defined DIRECT_SUN_BOUNCE || defined DIRECT_HANDHELD_BOUNCE || defined DIRECT_SKY_BOUNCE
    return emission + bounce;
#else
    return emission;
#endif
}

#endif // INCLUDE_LIGHTING_INDIRECT_LIGHTING_SSPT
