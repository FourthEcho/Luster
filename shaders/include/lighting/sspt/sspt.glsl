#if !defined INCLUDE_LIGHTING_SSPT
#define INCLUDE_LIGHTING_SSPT

// ============================================================================
//  Luster SSPT — screen-space path traced emission and colored lighting
// ----------------------------------------------------------------------------
//  This is the tracing stage of the SSPT chain (trace -> accumulate ->
//  filter; see program/d4_sspt.fsh, d5_sspt_accumulate.fsh and
//  d6_sspt_filter.fsh for the reconstruction stages).
//
//  Each shaded pixel casts cosine-weighted diffuse rays into the depth
//  buffer and gathers two contributions at the ray hits:
//    - material emission, rebuilt from the gbuffer and labPBR specular maps
//    - one bounce of shadowed sun/moon light, tinted by the hit albedo
//    - one bounce of the held light source (torch etc.), same falloff and
//      color the primary pass uses, tinted by the hit albedo
//  Rays are drawn from a Lambertian lobe and weighted with the
//  renormalized Hammon diffuse BRDF (E. Hammon, "PBR Diffuse Lighting for
//  GGX+Renormalized Burley", GDC 2017). Sample positions come from the R2
//  low-discrepancy sequence (Roberts et al.) with a per-pixel, per-frame
//  Cranley-Patterson rotation, so temporal accumulation converges without
//  repeating the same ray set.
//
//  Out of scope by design: skylight bounce. The SH_SKYLIGHT pass owns
//  ambient diffuse; gathering sky light here would double-count it.
//
//  Buffer geometry: the chain renders into colortex17-20 at the resolution
//  selected by indirectResReduction. Passes bound to those buffers receive
//  gl_FragCoord in buffer texels while uv still spans the whole screen, so
//  every gbuffer fetch remaps as
//      gbuffer_texel = uv * view_res * taau_render_scale
//  and hit positions recovered from screen space use the same scale.
//
//  Required uniforms (declared by the including program before this file):
//    colortex1, colortex2, depth via SSPT_DEPTH_SAMPLER,
//    gbufferModelView, cameraPosition, view_res, view_pixel_size,
//    taau_render_scale, near, far, frameCounter
//  Required macros (defined by the including program before this file):
//    SSPT_DEPTH_SAMPLER              - depth buffer to trace against
//    SSPT_PROJECTION_MATRIX          - projection matrix (DH-aware: combined)
//    SSPT_PROJECTION_MATRIX_INVERSE  - its inverse
// ============================================================================

#include "/include/lighting/colors/blocklight_color.glsl"
#include "/include/lighting/handheld_lighting.glsl"
#include "/include/lighting/cloud_shadows.glsl"
#include "/include/lighting/shadows/distortion.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"
#include "/include/surface/material.glsl"

// ----------------------------------------------------------------------------
// Hit-surface data
// ----------------------------------------------------------------------------

// One unpacked gbuffer hit. The packing is the one d4_deferred_shading
// writes into colortex1: two 2x8 unorm pairs for albedo, one for the
// material mask, an octahedral flat normal, and the light levels.
struct sspt_hit_data {
    vec3 albedo;
    vec3 scene_normal;
    vec2 light_levels;
    uint mask;
};

// Unpack one gbuffer record fetched from colortex1 into its albedo,
// material mask, scene normal and lightmap levels.
sspt_hit_data sspt_unpack_hit(vec4 gbuffer_data) {
    sspt_hit_data hit;

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
// Sample generation
// ----------------------------------------------------------------------------
// The hash family from David Hoskins ("Hash without sine") — inexpensive,
// stable across GPUs (no sin()), and plenty for jitter duty. Luster's
// random.glsl ships it; the R2 sequence below lives there as well.

// Cosine-weighted hemisphere sample about +Z (Malley's method: a uniform
// disk point pushed onto the hemisphere has exactly the cosine density).
vec3 sspt_cosine_direction(vec3 surface_normal, vec2 xi) {
    float radius = sqrt(xi.x);
    float angle = tau * xi.y;

    vec3 lobe = vec3(
        radius * cos(angle),
        radius * sin(angle),
        sqrt(max0(1.0 - xi.x))
    );

    // Orthonormal tangent frame around the normal; the reference axis is
    // picked by the dominant normal component to avoid a degenerate cross.
    vec3 reference
        = abs(surface_normal.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(reference, surface_normal));
    vec3 bitangent = cross(surface_normal, tangent);

    return lobe.x * tangent + lobe.y * bitangent + lobe.z * surface_normal;
}

// ----------------------------------------------------------------------------
// Screen-space ray marching
// ----------------------------------------------------------------------------
// Rays walk the combined (DH-aware) depth buffer in short steps. A depth
// sample counts as a hit when it lies in front of the ray and its view
// depth is within 10% of the ray's view depth there — the relative test
// keeps grazing surfaces from shadowing themselves while rejecting
// everything that clearly occludes the ray. The comparison runs in view
// space so both the DH combined depth and the plain gbuffer projection
// behave identically.

// Depth buffer sample at a full-resolution screen position.
float sspt_depth_at(vec2 screen_uv) {
    return texelFetch(
        SSPT_DEPTH_SAMPLER,
        ivec2(screen_uv * view_res * taau_render_scale),
        0
    ).x;
}

// Hit test for one marched screen-space sample: the depth sample must
// sit in front of the ray and within 10% of its view depth (see the
// section comment above for why the comparison runs in view space).
bool sspt_find_hit(vec3 screen_pos, out vec3 hit) {
    float sample_depth = sspt_depth_at(screen_pos.xy);

    if (sample_depth >= screen_pos.z) return false;

    float ray_view_depth = abs(
        screen_to_view_space_depth(SSPT_PROJECTION_MATRIX_INVERSE, screen_pos.z)
    );
    float sample_view_depth = abs(
        screen_to_view_space_depth(SSPT_PROJECTION_MATRIX_INVERSE, sample_depth)
    );

    if (abs(sample_view_depth - ray_view_depth) > 0.1 * ray_view_depth) return false;

    hit = vec3(screen_pos.xy, sample_depth);
    return true;
}

#ifdef ssptFullRangeRT
// Long-range mode: the ray is clipped against the near plane and the scene
// bounding sphere, projected once, then marched in screen space. Every
// on-screen pixel is reachable — at the cost of much longer rays that need
// more samples to converge.
bool sspt_march(vec3 view_pos, vec3 view_dir, float jitter, out vec3 hit) {
    const int step_count = 20;

    // Points behind the camera would mirror across the screen, so the ray
    // end is pulled back to the near plane whenever it crosses it.
    float end_distance = far * sqrt(3.0);
    if (view_pos.z + view_dir.z * end_distance > -near) {
        end_distance = (-near - view_pos.z) / view_dir.z;
    }

    vec3 start_screen = view_to_screen_space(SSPT_PROJECTION_MATRIX, view_pos, true);
    vec3 end_screen = view_to_screen_space(
        SSPT_PROJECTION_MATRIX, view_pos + view_dir * end_distance, true
    );
    vec3 travel = end_screen - start_screen;

    // Give up when the whole ray stays within a single buffer texel.
    if (max_of(abs(travel.xy) * view_res * taau_render_scale) < 1.0) return false;

    // Stop at the viewport border instead of marching off-screen. The
    // guard keeps axis-aligned rays from dividing by zero.
    vec2 delta = mix(travel.xy, vec2(1e-7), lessThan(abs(travel.xy), vec2(1e-7)));
    vec2 border_t = (step(0.0, delta) - start_screen.xy) / delta;
    float t_exit = min(min1(border_t.x), min1(border_t.y));

    vec3 step_screen = travel * (t_exit / float(step_count));
    vec3 screen_pos = start_screen + step_screen * (0.5 + jitter);

    for (int i = 0; i < step_count; ++i) {
        if (clamp01(screen_pos.xy) != screen_pos.xy) return false;
        if (sspt_find_hit(screen_pos, hit)) return true;
        screen_pos += step_screen;
    }

    return false;
}

#else
// Short-range mode (default): the ray marches a bounded view-space
// distance — enough to reach the emitters the falloff window can still
// see — projecting every step. Cheaper and far less noisy than long
// range, but blind to light sources outside its reach.
bool sspt_march(vec3 view_pos, vec3 view_dir, float jitter, out vec3 hit) {
    const int step_count = 12;
    const float march_length = tau; // view-space reach, in blocks

    vec3 step_view = view_dir * (march_length / float(step_count));

    // If the projected far end falls well outside the viewport, shorten the
    // march proportionally so the steps concentrate where hits are possible.
    vec3 end_screen = view_to_screen_space(
        SSPT_PROJECTION_MATRIX, view_pos + step_view * float(step_count), true
    );
    vec2 end_ndc = end_screen.xy * 2.0 - 1.0;
    step_view *= rcp(max(max(abs(end_ndc.x), abs(end_ndc.y)), 1.0));

    // Start half a step in, dithered, so the first sample does not sit on
    // the shading point itself.
    vec3 sample_view = view_pos + step_view * (0.5 + jitter);

    for (int i = 0; i < step_count; ++i) {
        vec3 screen_pos = view_to_screen_space(SSPT_PROJECTION_MATRIX, sample_view, true);
        sample_view += step_view;

        if (clamp01(screen_pos.xy) != screen_pos.xy) return false;
        if (sspt_find_hit(screen_pos, hit)) return true;
    }

    return false;
}
#endif

// ----------------------------------------------------------------------------
// Hit emission
// ----------------------------------------------------------------------------
// The hit surface's emission is rebuilt on demand instead of being read
// from a dedicated buffer: material_from() covers every hardcoded emissive
// block, and the labPBR specular map folds pack-provided emission in. The
// result is pre-scaled by emission_scale — the same factor the primary
// shading pass applies — so a bounced emitter and a directly viewed one
// agree on brightness.

vec3 sspt_hit_emission(sspt_hit_data hit, ivec2 hit_texel, vec3 hit_view_pos) {
    vec3 hit_world_pos = view_to_scene_space(hit_view_pos) + cameraPosition;

    vec2 light_levels = hit.light_levels;
    Material hit_material = material_from(
        hit.albedo, hit.mask, hit_world_pos, hit.scene_normal, light_levels
    );

    // Hardcoded contribution, saved before the specular map can override it.
    vec3 hardcoded_emission = hit_material.emission;

#ifdef SPECULAR_MAPPING
    vec4 specular_pack = texelFetch(colortex2, hit_texel, 0);
    vec4 map = vec4(
        unpack_unorm_2x8(specular_pack.z),
        unpack_unorm_2x8(specular_pack.w)
    );
    decode_specular_map(map, hit_material);
#endif

#if SSPT_EMISSION_MODE == SSPT_EMISSION_HARDCODED
    return hardcoded_emission * emission_scale * SSPT_INTENSITY;
#else // SSPT_EMISSION_LABPBR
    // Full material emission: hardcoded fallback plus the labPBR map, with
    // the user multiplier for pack-provided emission. Where the pack
    // declares no emissive texel, decode leaves the hardcoded value in
    // place, so this branch also covers vanilla correctly.
    return hit_material.emission * emission_scale * SSPT_INTENSITY * SSPT_LABPBR_EMISSION;
#endif
}

// ----------------------------------------------------------------------------
// Hit direct light (sun bounce)
// ----------------------------------------------------------------------------

#if defined SHADOW && !defined WORLD_NETHER

// Sun radiance, evaluated locally so the trace pass does not drag in the
// full atmosphere include chain. Same evaluation as the primary shading
// path's light colors (include/lighting/colors/light_color.glsl).
vec3 sspt_sun_radiance() {
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
        from_srgb(vec3(SUN_NR, SUN_NG, SUN_NB)),
        from_srgb(vec3(SUN_MR, SUN_MG, SUN_MB)),
        time_sunrise
    );
    user_tint = mix(user_tint, from_srgb(vec3(SUN_ER, SUN_EG, SUN_EB)), time_sunset);

    return exposure * tint * user_tint;
}

// Moon radiance. Moon-phase albedo influence is intentionally not applied:
// the bounce uses the raw moon color.
vec3 sspt_moon_radiance() {
    float night_boost = 1.0 + 0.33 * rcp(clamp01(1.25 * max(-sun_dir.y, 0.1)));
    float exposure = 0.66 * MOON_I * moon_phase_brightness * night_boost;
    return exposure * from_srgb(vec3(MOON_R, MOON_G, MOON_B));
}

// Shadowed sun/moon light at the traced hit, ready to be tinted by the
// surface albedo: one hardware-filtered comparison tap on shadowtex1,
// stained-glass transmission from shadowcolor0, and cloud shadows — the
// same chain the PCSS filter applies for primary shading. Skylight is
// deliberately absent (owned by SH_SKYLIGHT, see header).
vec3 sspt_hit_direct_light(sspt_hit_data hit, vec3 hit_view_pos) {
    vec3 hit_scene_pos = view_to_scene_space(hit_view_pos);
    vec3 direct = vec3(0.0);

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
            vec3 radiance = sunAngle < 0.5 ? sspt_sun_radiance() : sspt_moon_radiance();
            direct = radiance * (visibility * NoL);

#ifdef SHADOW_COLOR
            if (!outside_shadow_map) {
                // Sunlight passing through stained glass picks up the glass tint.
                // Fully blocked hits skip this block via visibility, so this
                // only colors transmitted light.
                ivec2 shadow_texel = ivec2(shadow_coords.xy * vec2(textureSize(shadowtex0, 0)));
                float blocker_depth = texelFetch(shadowtex0, shadow_texel, 0).x;
                vec3 transmission = texelFetch(shadowcolor0, shadow_texel, 0).rgb;
                direct *= mix(vec3(1.0), 4.0 * transmission, step(blocker_depth, shadow_coords.z));
            }
#endif

#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
            direct *= get_cloud_shadows(colortex8, hit_scene_pos);
#endif
        }
    }

#ifdef HANDHELD_LIGHTING
    // Held light source as traced bounce light: evaluated at the hit with
    // the exact falloff and color the primary pass uses
    // (get_handheld_lighting expects a camera-relative position, which is
    // what hit_scene_pos is). AO passes as 1.0 — the hit's own occlusion
    // is unknown here and the path throughput already shapes the result.
    // No shadow tap: bare falloff, like the primary pass. Joins `direct`
    // so it picks up the hit-albedo tint and SSPT_INTENSITY below, keeping
    // bounced torchlight in agreement with bounced sunlight.
    direct += get_handheld_lighting(hit_scene_pos, 1.0);
#endif

    return hit.albedo * (direct * SSPT_INTENSITY);
}

#endif // defined SHADOW && !defined WORLD_NETHER

// ----------------------------------------------------------------------------
// Diffuse BRDF and path weighting
// ----------------------------------------------------------------------------

// Renormalized diffuse for GGX+ (E. Hammon, "PBR Diffuse Lighting for GGX +
// Renormalized Burley", GDC 2017). At roughness 1 it serves as the path
// throughput between diffuse bounces, keeping multibounce energy honest.
float sspt_hammon_diffuse(vec3 normal, vec3 view_dir, vec3 light_dir, float roughness) {
    float NoL = dot(normal, light_dir);
    if (NoL <= 0.0) return 0.0;
    NoL = max0(NoL);

    float NoV = max0(dot(normal, view_dir));
    float LoV = max0(dot(light_dir, view_dir));

    vec3 halfway = normalize(view_dir + light_dir);
    float NoH = max0(dot(normal, halfway));

    float facing = 0.5 + 0.5 * LoV;

    float rough_lobe = facing * (0.9 - 0.4 * facing)
                     * ((0.5 + NoH) * rcp(max(NoH, 0.02)));
    float smooth_lobe = 1.05
                      * (1.0 - pow5(1.0 - NoL))
                      * (1.0 - pow5(1.0 - NoV));

    float single = rcp_pi * clamp01(mix(smooth_lobe, rough_lobe, roughness));
    float multi = 0.1159 * roughness;

    return clamp01((single + multi) * NoL);
}

// Throughput of one diffuse hop: the renormalized Hammon BRDF divided by
// the cosine-lobe density the ray was drawn from. Clamped so rare grazing
// samples cannot introduce fireflies.
float sspt_hop_weight(vec3 normal_view, vec3 incoming, vec3 outgoing) {
    float brdf = sspt_hammon_diffuse(normal_view, incoming, outgoing, 1.0);
    float lobe_density = clamp01(dot(outgoing, normal_view) * rcp_pi);
    return clamp(brdf * rcp(max(lobe_density, eps)), 0.0, half_pi);
}

// Cubic falloff for gathered emission: emitters inside the inner radius
// contribute at full strength and fade out towards ssptEmissionDistance, so
// distant emitters hand over to fog instead of speckling from across the map.
float sspt_emission_falloff(float hit_distance) {
    float fade = 1.0 - linear_step(
        ssptEmissionDistance * rcp_pi,
        ssptEmissionDistance,
        hit_distance
    );
    return cube(fade);
}

// ----------------------------------------------------------------------------
// The gather
// ----------------------------------------------------------------------------

// Traces ssptSPP diffuse paths per pixel and returns the combined emission
// and colored sun-bounce radiance. Raw and noisy by design — d5 and the
// SVGF passes exist to fix exactly that.
vec3 sspt_gather_light(vec3 view_pos, vec3 scene_normal, float march_jitter, bool hand) {
    mat3 view_rotation = mat3(gbufferModelView);
    vec3 view_normal = view_rotation * scene_normal;

    vec3 gathered_emission = vec3(0.0);

#if defined SHADOW && !defined WORLD_NETHER
    vec3 gathered_bounce = vec3(0.0);
#endif

    // Per-pixel rotation of the R2 sequence, re-rolled every frame. The
    // sequence index keeps counting across frames, so the ray set refines
    // under temporal accumulation instead of repeating itself.
    vec2 sequence_rotation = hash2(vec3(gl_FragCoord.xy, float(frameCounter)));
    int sample_base = frameCounter * int(ssptSPP);

    for (int ray_index = 0; ray_index < int(ssptSPP); ++ray_index) {
        vec3 throughput = vec3(1.0);

        vec3 ray_origin = view_pos;
        vec3 incoming_view = -normalize(view_pos);

        vec3 surface_normal_scene = scene_normal;
        vec3 surface_normal_view = view_normal;

        for (int bounce = 0; bounce < int(ssptBounces); ++bounce) {
            vec2 xi = r2(
                sample_base + ray_index * int(ssptBounces) + bounce,
                sequence_rotation
            );

            vec3 ray_scene = sspt_cosine_direction(surface_normal_scene, xi);
            vec3 ray_view = view_rotation * ray_scene;

            vec3 hit;
            if (!sspt_march(ray_origin, ray_view, march_jitter, hit)) break;

            ivec2 hit_texel = ivec2(hit.xy * view_res * taau_render_scale);
            sspt_hit_data hit_data = sspt_unpack_hit(texelFetch(colortex1, hit_texel, 0));

            vec3 hit_view_pos = screen_to_view_space(
                SSPT_PROJECTION_MATRIX_INVERSE, hit, true
            );

            throughput *= sspt_hop_weight(surface_normal_view, incoming_view, ray_view);

            gathered_emission
                += sspt_hit_emission(hit_data, hit_texel, hit_view_pos)
                 * sspt_emission_falloff(distance(hit_view_pos, view_pos))
                 * throughput;

#if defined SHADOW && !defined WORLD_NETHER
            gathered_bounce += sspt_hit_direct_light(hit_data, hit_view_pos) * throughput;
#endif

#if ssptBounces > 1
            // Tint deeper hits with every surface the path crossed — the
            // colored light bleed that makes multibounce worth its cost.
            throughput *= hit_data.albedo;

            // Continue the path from the hit surface.
            ray_origin = hit_view_pos;
            incoming_view = -ray_view;
            surface_normal_scene = hit_data.scene_normal;
            surface_normal_view = view_rotation * hit_data.scene_normal;
#endif
        }
    }

    gathered_emission *= rcp(float(ssptSPP));

#if defined SHADOW && !defined WORLD_NETHER
    gathered_bounce *= rcp(float(ssptSPP));
#endif

    if (hand) gathered_emission = vec3(0.0); // hand geometry gathers nothing

#if defined SHADOW && !defined WORLD_NETHER
    return gathered_emission + gathered_bounce;
#else
    return gathered_emission;
#endif
}

#endif // INCLUDE_LIGHTING_SSPT
