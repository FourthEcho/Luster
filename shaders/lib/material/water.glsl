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

#if !defined INCLUDE_MATERIAL_WATER
#define INCLUDE_MATERIAL_WATER

#include "/lib/util/spaceConversion.glsl"
#include "/lib/material/rain.glsl"

float gerstner_wave(
    vec2 coord,
    vec2 wave_dir,
    float t,
    float noise,
    float wavelength
) {
    // Gerstner wave function from Belmu in #snippets, modified
    const float g = 9.8;

    float k = tau / wavelength;
    float w = sqrt(g * k);

    float x = w * t - k * (dot(wave_dir, coord) + noise);

    return sqr(sin(x) * 0.5 + 0.5);
}

void water_waves_setup(
    bool flowing_water,
    vec2 flow_dir,
    out vec2 wave_dir,
    out mat2 wave_rot,
    out float t
) {
    const float wave_speed_still = 0.5 * waterWaveSpeedStill;
    const float wave_speed_flowing = 0.7 * waterWaveSpeedFlowing;
    const float wave_angle = 30.0 * degree;

    t = (flowing_water ? wave_speed_flowing : wave_speed_still)
        * frameTimeCounter;

    wave_dir
        = flowing_water ? flow_dir : vec2(cos(wave_angle), sin(wave_angle));
    wave_rot = flowing_water
        ? mat2(1.0)
        : mat2(
              cos(golden_angle),
              sin(golden_angle),
              -sin(golden_angle),
              cos(golden_angle)
          );
}
float get_water_height(vec2 coord, vec2 wave_dir, mat2 wave_rot, float t) {
    // Parameters

    // Gerstner waves
    const float wave_frequency = 0.7 * waterWaveFrequency;
    const float persistence = 0.5 * waterWavePersistence;
    const float lacunarity = 1.7 * waterWaveLacunarity;

    // Noise
    const float noise_frequency = 0.007;


    const float noise_strength = 2.0 * waterWavesNoiseStrength;

    // Height variation
    const float height_variation_frequency = 0.001;
    const float min_height = 0.4;
    const float height_variation_scale = 2.0;
    const float height_variation_offset = -0.5;
    const float height_variation_scroll_speed = 0.1;


    const float amplitude_normalization_factor = (1.0 - persistence)
        / (1.0 - pow(persistence, float(waterWaveIterations)));

    // Sample noise textures first (latency hiding)

    float[waterWaveIterations] wave_noise;
    vec2 noise_coord = (coord + vec2(0.0, 0.25 * t)) * noise_frequency;
    for (uint i = 0u; i < waterWaveIterations; ++i) {
        wave_noise[i] = texture(noisetex, noise_coord).y;
        noise_coord *= 2.5;
    }

#ifdef waterWavesHeightVariation
    float height_variation_noise
        = texture(
              noisetex,
              (coord + vec2(0.0, height_variation_scroll_speed * t))
                  * height_variation_frequency
        )
              .y;
#endif

    // Calculate wave height

    float height = 0.0;
    float amplitude_sum = 0.0;

    float wave_length = 1.0;
    float amplitude = 1.0;
    float frequency = wave_frequency;

    for (uint i = 0u; i < waterWaveIterations; ++i) {
        height += gerstner_wave(
                      coord * frequency,
                      wave_dir,
                      t,
                      wave_noise[i] * noise_strength,
                      wave_length
                  )
            * amplitude;

        amplitude *= persistence;
        frequency *= lacunarity;
        wave_length *= 1.5;

        wave_dir *= wave_rot;
    }

#ifdef waterWavesHeightVariation
    height *= max(
        min_height,
        height_variation_noise * height_variation_scale
            + height_variation_offset
    );
#endif

    return height * amplitude_normalization_factor;
}

vec3 get_water_normal(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 coord,
    vec2 flow_dir,
    float skylight,
    bool flowing_water
) {
    vec2 wave_dir;
    mat2 wave_rot;
    float t;
    water_waves_setup(flowing_water, flow_dir, wave_dir, wave_rot, t);

    const float h = 0.1;
    float wave0 = get_water_height(coord, wave_dir, wave_rot, t);
    float wave1 = get_water_height(coord + vec2(h, 0.0), wave_dir, wave_rot, t);
    float wave2 = get_water_height(coord + vec2(0.0, h), wave_dir, wave_rot, t);

#if defined WORLD_OVERWORLD
    float normal_influence = flowing_water
        ? 0.1
        : mix(0.01, 0.04 + 0.15 * rainStrength, dampen(skylight));
#else
    float normal_influence = 0.04;
#endif
    float grazing_fade = smoothstep(
        0.0,
        0.15,
        abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
    ); // prevent noise when looking horizontally
    normal_influence *= grazing_fade;
    normal_influence *= waterWaveStrength;

    // Luster-style wave normal (matches Luster exactly; note this tilts
    // towards the slope rather than away from it).
    vec3 normal = vec3(wave1 - wave0, wave2 - wave0, h);
    normal.xy *= normal_influence;

#ifdef rainRipples


    float rain_ripple_mask
        = float(!flowing_water) * rainStrength * smoothstep(0.85, 1.0, skylight);

    if (rain_ripple_mask > 0.001) {
        // Analytic ring normals (Eclipse-style, see rain.glsl):
        // no finite differences needed.
        vec2 ripple_gradient
            = rain_ripple_normal(coord, frameTimeCounter).xy;
        float ripple_influence
            = 0.30 * rainRippleStrength * rain_ripple_mask * grazing_fade;

        normal.xy += ripple_gradient * ripple_influence;
    }
#endif

    return normalize(normal);
}

vec2 get_water_parallax_coord(
    vec3 tangent_dir,
    vec2 coord,
    vec2 flow_dir,
    bool flowing_water
) {
    const int step_count = 4;
    const float parallax_depth = 0.2;

    vec2 wave_dir;
    mat2 wave_rot;
    float t;
    water_waves_setup(flowing_water, flow_dir, wave_dir, wave_rot, t);

    vec2 ray_step = tangent_dir.xy * rcp(-tangent_dir.z) * parallax_depth
        * rcp(float(step_count));

    float depth_value = get_water_height(coord, wave_dir, wave_rot, t);
    float depth_march = 0.0;
    float depth_previous;

    while (depth_march < depth_value) {
        coord += ray_step;
        depth_previous = depth_value;
        depth_value = get_water_height(coord, wave_dir, wave_rot, t);
        depth_march += rcp(float(step_count));
    }

    // Interpolation step

    float depth_before = depth_previous - depth_march + rcp(float(step_count));
    float depth_after = depth_value - depth_march;

    return mix(
        coord,
        coord - ray_step,
        depth_after / (depth_after - depth_before)
    );
}


#ifdef LUSTER_INCLUDE_WATER_SURFACE_MATERIAL
#include "/lib/material/material.glsl"
#include "/lib/fog/simpleFog.glsl"
#include "/lib/util/color.glsl"
Material get_water_material(
    vec3 direction_world,
    vec3 normal,
    float layer_dist,
    out float alpha
) {
    Material material = water_material;
    alpha = 0.01;

    // Water texture

#if waterTexture == waterTextureHighlight \
    || waterTexture == waterTextureHighlightUnderground
    vec4 base_color = read_tex_anisotropic_or_plain(gtexture, uv);


    float texture_highlight = dampen(
        0.5 * sqr(linear_step(0.63, 1.0, base_color.r)) + 0.03 * base_color.r
    ) * waterTextureIntensity;
#if waterTexture == waterTextureHighlightUnderground
    texture_highlight *= 1.0 - cube(linear_step(0.0, 0.5, light_levels.y));
#endif

    material.albedo
        = clamp01(0.5 * exp(-2.0 * water_absorption_coeff) * texture_highlight);
    material.roughness += 0.3 * texture_highlight;
    alpha += texture_highlight;
#elif waterTexture == waterTextureVanilla
    vec4 base_color = read_tex_anisotropic_or_plain(gtexture, uv) * tint;
    material.albedo = srgb_eotf_inv(base_color.rgb * base_color.a)
        * rec709_to_working_color;
    alpha = base_color.a;
#endif

    // Water edge highlight

#ifdef waterEdgeHighlight
    float dist = layer_dist * max(abs(direction_world.y), eps);

#if waterTexture == waterTextureHighlight \
    || waterTexture == waterTextureHighlightUnderground
    float edge_highlight
        = cube(max0(1.0 - 2.0 * dist)) * (1.0 + 8.0 * texture_highlight);
#else
    float edge_highlight = cube(max0(1.0 - 2.0 * dist));
#endif
    edge_highlight *= waterEdgeHighlightIntensity * max0(normal.y)
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

vec4 water_absorption_approx(
    vec4 color,
    float sss_depth,
    float layer_dist,
    float LoV,
    float NoV,
    float cloud_shadows
) {


    // We blend the biome tint toward neutral grey (0.5) by the inverse of


    vec3 biome_water_color = srgb_eotf_inv(tint.rgb) * rec709_to_working_color;
    biome_water_color = mix(
        vec3(dot(biome_water_color, luminance_weights)),
        biome_water_color,
        biomeWaterColorIntensity
    );
    vec3 absorption_coeff = biome_water_coeff(biome_water_color);
    float dist = layer_dist * float(isEyeInWater != 1 || NoV >= 0.0);

    mat2x3 water_fog = water_fog_simple(
        light_color * cloud_shadows,
        ambient_color,
        absorption_coeff,
        light_levels,
        dist,
        -LoV,
        sss_depth
    );

    float brightness_control = 1.0 - exp(-0.33 * layer_dist);
    brightness_control *= max(light_levels.x, light_levels.y);

    return vec4(
        color.rgb
            + water_fog[0] * (1.0 + 6.0 * sqr(water_fog[1]))
                * brightness_control,
        1.0 - water_fog[1].x
    );
}
#endif

#endif // INCLUDE_MATERIAL_WATER
