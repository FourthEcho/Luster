#if !defined INCLUDE_PROGRAM_GI_BOUNCE
#define INCLUDE_PROGRAM_GI_BOUNCE

// ============================================================================
//  Bounce shader — trace one cosine ray per pixel, sample the previous
//  bounce's output at the hit, multiply by the hit surface's albedo, and
//  write the result into the next bounce's input buffer.
//
//  Parameters (set by the wrapper .fsh in world0/world1/world-1):
//    BOUNCE_PASS  = 1, 2, 3 or 4
//
//  Buffer flow:
//    bounce1: reads colortex18 (last frame's accumulated) writes colortex17
//    bounce2: reads colortex17 (bounce1's output)   writes colortex17 (flip)
//    bounce3: reads colortex17 (bounce2's output)   writes colortex17 (flip)
//    bounce4: reads colortex17 (bounce3's output)   writes colortex17 (flip)
//
//  Each bounce also:
//    * samples the sky map (colortex4) on ray miss, so sky radiance flows
//      into the bounce chain naturally
//    * modulates the result by the hit pixel's albedo — the final bounce
//      output is "radiance leaving the surface after N bounces"
//    * applies skylight gating from the lightmap so enclosed spaces don't
//      get free sky light
// ============================================================================

#include "/include/global.glsl"

// ----------------------------------------------------------------------------
//   Uniforms
//
//   NB: these MUST be declared before the includes below — space_conversion,
//   light_color and the GI shared helpers reference them at global scope, and
//   GLSL requires declaration before use.
// ----------------------------------------------------------------------------

#if BOUNCE_PASS == 1
  #define BOUNCE_INPUT_SAMPLER  colortex18
  uniform sampler2D colortex18; // last frame's accumulated GI
#else
  #define BOUNCE_INPUT_SAMPLER  colortex17
  uniform sampler2D colortex17; // previous bounce's output (this frame)
#endif

uniform sampler2D colortex1;  // gbuffer data 0 (albedo, normals, lightmaps)
uniform sampler2D colortex2;  // gbuffer data 1 (detailed normal, specular)
uniform sampler2D colortex4;  // sky map + light colors
uniform sampler2D colortex5;  // TAA scene history — used for sky-miss fallback

uniform sampler2D noisetex;
uniform sampler2D depthtex1; // fallback combined_depth_tex when no LoD mod

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

// Needed by ibl.glsl / light_color.glsl / atmosphere.glsl
uniform float rainStrength;
uniform float sunAngle;
uniform int moonPhase;
uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform float time_sunrise;
uniform float time_sunset;

layout(location = 0) out vec4 bounce_out;

/* RENDERTARGETS: 17 */

in vec2 uv;

// ----------------------------------------------------------------------------
//   Includes
// ----------------------------------------------------------------------------

#define TEMPORAL_REPROJECTION

#include "/include/lighting/ibl/ibl.glsl"
#include "/include/lighting/colors/light_color.glsl"
#include "/program/gi/shared.glsl"

// Cosine-weighted sample of the sky map at the given world direction,
// gated by skylight so enclosed pixels don't get free sky light.
vec3 gi_sample_sky(vec3 world_dir, float skylight) {
    vec3 sky = get_ibl_sky_irradiance(world_dir, hash2(vec3(uv * 255.0, frameCounter)), 4);
    return sky * skylight;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 full_texel = gi_full_res_texel();

    // Bail on sky pixels and on hand layer.
    float depth = gi_read_depth(full_texel);
    if (depth >= 1.0 || depth < hand_depth) {
        bounce_out = vec4(0.0);
        return;
    }

    // Reconstruct view-space position from the depth.
    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    // Surface attributes at the receiver.
    vec3 normal_scene = gi_read_scene_normal(full_texel);
    vec3 normal_view = normalize(mat3(gbufferModelView) * normal_scene);
    vec2 light_levels = gi_read_light_levels(full_texel);
    float skylight = clamp01(light_levels.y);

    // Stochastic per-pixel dither (R2 sequence + blue noise). The bounce
    // shader needs a fresh sample every frame so the temporal accumulate
    // pass can average bounce noise across frames.
    float dither = texelFetch(noisetex, texel & 511, 0).b;
    dither = r1(frameCounter, dither);

    vec2 hash = hash2(vec3(uv * view_res, frameCounter));
    vec3 ray_view = gi_cosine_sample_hemisphere(normal_view, hash);
    ray_view = normalize(ray_view);

    vec3 hit_uv;
    bool hit = gi_raymarch(screen_pos, view_pos, ray_view, dither, hit_uv);

    vec3 radiance = vec3(0.0);
    if (hit) {
        // Sample previous bounce's output at the hit UV. The hit position
        // is in quarter-res UV space because that's where the GI passes run.
        // The bounce buffer (colortex17) is already at quarter-res so a
        // direct texture() sample at hit_uv.xy works.
        vec3 prev_radiance = texture(BOUNCE_INPUT_SAMPLER, hit_uv.xy).rgb;
        prev_radiance = max0(prev_radiance);

        // Modulate by the hit surface's albedo — this is the path the
        // radiance takes through that surface. The hit pixel may have
        // albedo 0 (e.g. water in some material configs), in which case
        // the bounce ends here.
        ivec2 hit_full_texel = ivec2(hit_uv.xy * view_res * taau_render_scale);
        vec3 hit_albedo = gi_read_albedo(hit_full_texel);
        radiance = prev_radiance * hit_albedo;

        // Apply the cosine-weighted BRDF (Lambertian: brdf = albedo / pi,
        // but cosine sampling cancels the 1/pi so we just multiply by
        // the albedo above and let the BRDF scaling happen in accumulate).
    } else {
        // Sky miss — sample the live sky map and apply skylight gating.
        // The sky irradiance is fetched from the IBL environment, which is
        // already updated every frame in d0_sky_map.
        vec3 ray_world = normalize(mat3(gbufferModelViewInverse) * ray_view);
        radiance = gi_sample_sky(ray_world, skylight);

#if BOUNCE_PASS == 1
        // First bounce: when the ray misses, also blend in the previous
        // frame's accumulated output so temporal continuity isn't lost on
        // disocclusion. This is the "use TAA's history" trick — the GI
        // history buffer reads what TAA already wrote into colortex5.
        // This avoids a hard pop when the camera moves into a new area.
        vec3 taa_history = max0(texture(colortex5, hit_uv.xy).rgb);
        float history_weight = 0.25 * (1.0 - skylight);
        radiance = mix(radiance, taa_history, history_weight);
#endif
    }

    // Write the bounce radiance. Alpha is unused by subsequent bounces;
    // accumulate writes the pixel age into colortex18's alpha separately.
    bounce_out = vec4(max0(radiance), 1.0);
}

#endif // INCLUDE_PROGRAM_GI_BOUNCE
