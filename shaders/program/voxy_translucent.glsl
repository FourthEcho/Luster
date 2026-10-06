#include "/include/fog/overworld/parameters.glsl"
#include "/include/global.glsl"

#ifdef SHADOW
#undef SHADOW
#endif

#ifdef HANDHELD_LIGHTING
#undef HANDHELD_LIGHTING
#endif

#ifdef SHADOW_SSRT
#undef SHADOW_SSRT
#endif

uniform float desert_sandstorm;

// simple_fog needs fogColor, Voxy patch doesn't expose it by default
uniform vec3 fogColor;
uniform sampler2D depthtex1;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 sun_dir;
uniform vec3 light_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float near;
uniform float far;
uniform float eyeAltitude;
uniform float eye_skylight;
uniform float rainStrength;
uniform float blindness;
uniform float darknessFactor;
uniform float time_noon;
uniform float nightVision;
uniform float sunAngle;

uniform int isEyeInWater;
uniform int moonPhase;
uniform int frameCounter;

// Declared for water_normal.glsl / rain_ripples.glsl, which sample noise
// and animate by frame in every TU that includes them.
uniform sampler2D noisetex;
uniform float frameTimeCounter;

// Declared for the cave-fog path, which scales density by biome_cave in
// every TU that includes it.
uniform float biome_cave;

vec3 ambient_color;
vec3 light_color;

#ifdef WORLD_OVERWORLD
// Unused
OverworldFogParameters fog_params;
#endif

#define TEMPORAL_REPROJECTION

#include "/include/fog/simple_fog.glsl"
#include "/include/lighting/bsdf/diffuse_lighting.glsl"
#include "/include/lighting/direct_lighting/pcss.glsl"
#include "/include/lighting/bsdf/specular_lighting.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/misc/material_masks.glsl"
#include "/include/surface/material.glsl"
#include "/include/surface/water_normal.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

#ifdef CLOUD_SHADOWS
#include "/include/lighting/cloud_shadows.glsl"
#endif

layout(location = 0) out vec4 fragment_color;
layout(
    location = 1
) out vec4 gbuffer_data; // albedo, block ID, flat normal, light levels

/*
struct VoxyFragmentParameters {
    vec4 sampledColour;
    vec2 tile;
    vec2 uv;
    uint face;
    uint modelId;
    vec2 lightMap;
    vec4 tinting;
    uint customId; // Same as iris's modelId
};
*/

Material get_water_material(
    vec4 sampled_color,
    vec4 tint,
    vec3 dir_world,
    vec3 normal,
    vec2 light_levels,
    float layer_dist,
    out float alpha
) {
    Material material = water_material;
    alpha = 0.01;

    // Water texture

#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT \
    || WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    float texture_highlight = dampen(
        0.5 * sqr(linear_step(0.63, 1.0, sampled_color.r))
        + 0.03 * sampled_color.r
    );
#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    texture_highlight *= 1.0 - cube(linear_step(0.0, 0.5, light_levels.y));
#endif

    sampled_color *= tint;
    material.albedo
        = clamp01(0.5 * exp(-2.0 * water_absorption_coeff) * texture_highlight);
    material.roughness += 0.3 * texture_highlight;
    alpha += texture_highlight;
#elif WATER_TEXTURE == WATER_TEXTURE_VANILLA
    sampled_color *= tint;
    material.albedo = srgb_eotf_inv(sampled_color.rgb * sampled_color.a)
        * rec709_to_working_color;
    alpha = sampled_color.a;
#endif

    // Water edge highlight

#ifdef WATER_EDGE_HIGHLIGHT
    float dist = layer_dist * max(abs(dir_world.y), eps);

#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT \
    || WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    float edge_highlight
        = cube(max0(1.0 - 2.0 * dist)) * (1.0 + 8.0 * texture_highlight);
#else
    float edge_highlight = cube(max0(1.0 - 2.0 * dist));
#endif
    edge_highlight *= WATER_EDGE_HIGHLIGHT_INTENSITY * max0(normal.y)
        * (1.0 - 0.5 * sqr(light_levels.y));
    ;

    material.albedo += 0.1 * edge_highlight
        / mix(1.0,
              max(dot(ambient_color, luminance_weights), 0.5),
              light_levels.y);
    material.albedo = clamp01(material.albedo);
    alpha += edge_highlight;
#endif

    return material;
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);

    // Discard if vanilla opaque geometry is in front of this fragment, so
    // Voxy translucent doesn't paint over vanilla entities/glints in
    // colortex13. Compares against this fragment's own depth: opaque
    // behind the fragment (lakebed under water) must keep rendering.
    float vanilla_opaque_depth
        = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).x;
    if (vanilla_opaque_depth < gl_FragCoord.z
        && vanilla_opaque_depth < 1.0) {
        discard;
    }

    // Get the depth of the solid layer behind this fragment (used for edge
    // highlight effect)

    float lod_depth_behind
        = texelFetch(vxDepthTexOpaque, ivec2(gl_FragCoord.xy), 0).x;

    // Get direct light color. Surface ambient uses the precomputed baked
    // ambient that the sky shader publishes to colortex4(191, 1), the
    // same term the deferred path uses, so Voxy translucents match the
    // rest of the world.
    light_color = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
    ambient_color = texelFetch(colortex4, ivec2(191, 1), 0).rgb;

    // Get base properties

    vec4 base_color = parameters.sampledColour * parameters.tinting;

    // from Cortex
    vec3 normal = vec3(
                      uint((parameters.face >> 1) == 2),
                      uint((parameters.face >> 1) == 0),
                      uint((parameters.face >> 1) == 1)
                  )
        * (float(int(parameters.face) & 1) * 2.0 - 1.0);

    // Apply the baked sky ambient published to colortex4(191, 1). This
    // matches the deferred non-skylight path so Voxy translucents stay
    // consistent with the rest of the forward-shaded world.
    ambient_color *= clamp01(parameters.lightMap.y);

    uint material_mask = max(parameters.customId - 10000u, 0u);

    // Get position

    vec3 pos_screen = vec3(coord, gl_FragCoord.z);
    vec3 pos_view = screen_to_view_space(vxProjInv, pos_screen, true);
    vec3 pos_scene = view_to_scene_space(pos_view);

    vec3 dir_world = normalize(pos_scene - gbufferModelViewInverse[3].xyz);

    // Get distance to the solid layer behind this fragment

    vec3 back_pos_view
        = screen_to_view_space(vxProjInv, vec3(coord, lod_depth_behind), true);
    float layer_dist = distance(pos_view, back_pos_view);

    // Get material

    Material material;
    float alpha = 0.0;

    if (material_mask == MATERIAL_WATER) {
        material = get_water_material(
            parameters.sampledColour,
            parameters.tinting,
            dir_world,
            normal,
            parameters.lightMap,
            layer_dist,
            alpha
        );
    } else {
        vec2 unused = parameters.lightMap;
        material = material_from(
            base_color.rgb,
            material_mask,
            pos_scene + cameraPosition,
            normal,
            unused
        );
        alpha = base_color.a;
    }

    // Encode water data

    if (material_mask == MATERIAL_WATER) {
        gbuffer_data.x = pack_unorm_2x8(parameters.tinting.rg);
        gbuffer_data.y = pack_unorm_2x8(parameters.tinting.b, alpha);
        gbuffer_data.z = pack_unorm_2x8(encode_unit_vector(normal));
        gbuffer_data.w = pack_unorm_2x8(parameters.lightMap);
    } else {
        gbuffer_data = vec4(0.0);
    }

    // Early exit if albedo is zero

    if (max_of(material.albedo * alpha) < eps) {
        fragment_color = vec4(0.0);
        return;
    }

    // Forward shading

    float NoL = dot(normal, light_dir);
    float NoV = clamp01(dot(normal, -dir_world));
    float LoV = dot(light_dir, -dir_world);
    float halfway_norm = inversesqrt(2.0 * LoV + 2.0);
    float NoH = (NoL + NoV) * halfway_norm;
    float LoH = LoV * halfway_norm + halfway_norm;

    vec3 shadows = vec3(pow8(parameters.lightMap.y)); // Fake shadow
#define sss_depth 0.0
#define shadow_distance_fade 0.0

#ifdef CLOUD_SHADOWS
    float cloud_shadows = get_cloud_shadows(colortex8, pos_scene);
    shadows *= cloud_shadows;
#endif

    fragment_color.rgb = get_diffuse_lighting(
        material,
        pos_scene,
        normal,
        normal,
        shadows,
        parameters.lightMap,
        1.0, // AO
        0.0, // Ambient SSS
        sss_depth,
#ifdef CLOUD_SHADOWS
        cloud_shadows,
#endif
        shadow_distance_fade,
        NoL,
        NoV,
        NoH,
        LoV,
        ambient_color
    );
    fragment_color.a = alpha;

    // Apply fog

    vec4 fog = common_fog(length(pos_scene), false, pos_scene);
    fragment_color.rgb = fragment_color.rgb * fog.a + fog.rgb;
}
