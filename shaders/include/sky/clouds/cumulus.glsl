#if !defined INCLUDE_SKY_CLOUDS_CUMULUS
#define INCLUDE_SKY_CLOUDS_CUMULUS

// 1st layer: volumetric cumulus/stratocumulus/stratus clouds
// Cauliflower shaping via curl-advected billowy/wispy erosion (inspired by Alpha Piscium
// detailNoiseB/W, height curves, but renamed textures for Luster and tuned for Mac - no compute).

#include "common.glsl"
#include "coverage_map.glsl"

// altitude_fraction := 0 at the bottom of the cloud layer and 1 at the top
float clouds_cumulus_altitude_shaping(float density, float altitude_fraction) {
    if (clouds_params.l0_cumulus_stratus_blend > eps) {
        density = mix(
            density,
            clamp01(
                density
                * dampen(
                    clamp01(2.0 * altitude_fraction)
                    * linear_step(0.0, 0.1, altitude_fraction)
                    * linear_step(0.0, 0.6, 1.0 - altitude_fraction)
                )
            ),
            clouds_params.l0_cumulus_stratus_blend
        );
    }
    density -= smoothstep(0.2, 1.0, altitude_fraction)
        * (0.6 - 0.3 * clouds_params.l0_cumulus_stratus_blend);
    density *= smoothstep(0.0, 0.2, altitude_fraction);
    return density;
}

// ------------------------------------------------------------------
// Alpha Piscium exact helpers - verbatim
// ------------------------------------------------------------------

// Height curves fitted by Alpha Piscium to concentrate billowy/wispy erosion in mid/upper cloud
// b_i coefficients from composite9.csh
float ap_heightCurveWisp(vec4 xs) {
    const float a0 = -1.755622;
    const vec4 as = vec4(3.6801126, -163.09651, 320.59657, -163.29147);
    const float a5 = 0.01273534;
    return exp2(dot(as, xs) + a0) + a5;
}
float ap_heightCurveBillowy(vec4 xs) {
    const float a0 = -2.8940248;
    const vec4 as = vec4(20.938597, -83.765418, 114.27168, -53.99707);
    return exp2(dot(as, xs) + a0);
}

// Exact frequencies from Alpha defaults (all SETTING 0.0)
const float AP_LOW_BASE_FREQ       = 1.0;  // exp2(0)
const float AP_LOW_CURL_FREQ       = 1.0;  // exp2(0)
const float AP_LOW_BILLOWY_FREQ    = 0.5;  // exp2(-1)
const float AP_LOW_BILLOWY_CURL    = 0.5;  // exp2(-1)
const float AP_HIGH_BILLOWY_FREQ   = 1.0;  // exp2(0)
const float AP_HIGH_BILLOWY_CURL   = 1.0;  // exp2(0)
const float AP_LOW_WISPS_FREQ      = 1.0;  // exp2(0)
const float AP_LOW_WISPS_CURL      = 1.0;  // exp2(0)

float ap_detailNoiseB(vec3 pos, vec3 curl) {
    vec3 lowFreqPos = pos + curl * AP_LOW_BILLOWY_CURL;
    lowFreqPos *= AP_LOW_BILLOWY_FREQ;
    float lowFreq = texture(cumulus_detail1, lowFreqPos * 0.004).x;
    vec3 highFreqPos = pos + curl * AP_HIGH_BILLOWY_CURL;
    highFreqPos *= AP_HIGH_BILLOWY_FREQ;
    float highFreq = texture(cumulus_detail2, highFreqPos * 0.008).x;
    return cube(1.0 - lowFreq) * 0.6 + sqr(0.5 - highFreq) * 0.5;
}
float ap_detailNoiseW(vec3 pos) {
    pos *= 0.5;
    pos *= AP_LOW_WISPS_FREQ;
    return texture(cumulus_detail2, pos * 0.008).x;
}
vec3 ap_detailCurlNoise(vec3 pos) {
    pos *= 0.5;
    pos *= AP_LOW_CURL_FREQ;
    return texture(cumulus_curl, pos * 0.004).xyz * 2.0 - 1.0;
}

float clouds_cumulus_density(vec3 pos) {
    // DEBUG: bypass all cumulus sampling to test black screen - if sky still black, issue is not here
    // return 0.0; // uncomment to disable cumulus entirely
    float r = length(pos);

#if defined CLOUDS_USE_LOCAL_COVERAGE_MAP
    vec2 coverage_map_uv = project_clouds_cumulus_coverage_map(pos);
    if (r < clouds_cumulus_radius || r > clouds_cumulus_top_radius
        || clamp01(coverage_map_uv) != coverage_map_uv) {
        return 0.0;
    }
    float density = texture(colortex8, coverage_map_uv).z;
#else
    if (r < clouds_cumulus_radius || r > clouds_cumulus_top_radius) {
        return 0.0;
    }
    float density = clouds_cumulus_local_coverage(pos.xz);
#endif

    float altitude_fraction
        = (r - clouds_cumulus_radius) * clouds_params.l0_altitude_scale;

    density = clouds_cumulus_altitude_shaping(density, altitude_fraction);

    if (density < eps) {
        return 0.0;
    }

#if !defined PROGRAM_PREPARE
    const float wind_angle = CLOUDS_CUMULUS_WIND_ANGLE * degree;
    const vec2 wind_velocity
        = CLOUDS_CUMULUS_WIND_SPEED * vec2(cos(wind_angle), sin(wind_angle));

    vec3 wind = vec3(wind_velocity * world_age, 0.0).xzy;
    pos.xz += cameraPosition.xz * CLOUDS_SCALE + wind.xz;

    // Keep Luster worley detail as base (Alpha also has coverage worley but we keep both)
    float worley_0
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.2 * wind) * 0.0009).x;
    float worley_1
        = texture(SAMPLER_WORLEY_SWIRLEY, (pos + 0.4 * wind) * 0.005).x;

#else
    const float worley_0 = 0.5;
    const float worley_1 = 0.5;
#endif

    float detail_fade = 0.20 * smoothstep(0.85, 1.0, 1.0 - altitude_fraction)
        - 0.35 * smoothstep(0.05, 0.5, altitude_fraction) + 0.6;

    density -= clouds_params.l0_detail_weights.x * sqr(worley_0)
        * dampen(clamp01(1.0 - density));
    density -= clouds_params.l0_detail_weights.y * sqr(worley_1)
        * dampen(clamp01(1.0 - density)) * detail_fade;

    if (density < 0.02) { // Alpha CU_BASE_DENSITY_THRESHOLD
        // Still apply final sharpening below
        density = max0(density);
        density = lift(
            density,
            mix(clouds_params.l0_edge_sharpening.x,
                clouds_params.l0_edge_sharpening.y,
                altitude_fraction)
        );
        density *= 0.1 + 0.9 * smoothstep(0.2, 0.7, altitude_fraction);
        return density;
    }

#if !defined PROGRAM_PREPARE
    // ------------------------------------------------------------------
    // Alpha Piscium billowy/wispy - tuned for Luster scale to avoid black screen
    // Original Alpha uses linear_step erosion which is too aggressive at Luster's
    // density range (kills all). Use softer subtractive erosion like Luster's
    // previous worley but with Alpha's exact noise + height curves.
    // ------------------------------------------------------------------
    float x1 = altitude_fraction;
    float x2 = x1 * x1;
    float x3 = x1 * x2;
    float x4 = x1 * x3;
    vec4 xs = vec4(x1, x2, x3, x4);

    vec3 curlPos = pos;
    curlPos.y *= 1.3;
    vec3 detailCurl = ap_detailCurlNoise(curlPos);
    detailCurl *= 0.2 + 0.3 * sqr(altitude_fraction);
    const float CU_BASE_DENSITY_THRESHOLD = 0.02;
    detailCurl *= linear_step(mix(CU_BASE_DENSITY_THRESHOLD, 1.0, pow5(1.0 - altitude_fraction)), 0.0, density);

    float detail1Billowy = ap_detailNoiseB(pos, detailCurl);
    float bottomDetail = 1.0 - detail1Billowy * smoothstep(0.1, 0.0, altitude_fraction) * 0.6; // tuned 2.0->0.6 to keep base
    float hc3 = ap_heightCurveBillowy(xs);
    float covSqrt = sqrt(clamp01(clouds_params.l0_coverage.y));
    covSqrt = mix(0.707, covSqrt, 0.5);
    detail1Billowy *= hc3 * 0.4; // scaled down vs Alpha (was 1.0)
    // Softer erosion: subtractive, not linear_step kill
    float billowyErosion = detail1Billowy * covSqrt * 0.6;
    density = max0(density - billowyErosion * dampen(clamp01(1.0 - density)));

    float detail1Wisp = ap_detailNoiseW(pos + detailCurl * 2.0 * AP_LOW_WISPS_CURL);
    detail1Wisp = sqr(detail1Wisp) * 0.5; // softer
    detail1Wisp *= covSqrt;
    float hc2 = ap_heightCurveWisp(xs);
    detail1Wisp *= hc2 * 0.5;
    float wispErosion = detail1Wisp * 0.35 * detail_fade;
    density = max0(density - wispErosion * dampen(clamp01(1.0 - density)));

    // Keep Alpha edge sharpen but toned down
    float hardEdgeBlend = linear_step(0.0, 0.3, altitude_fraction);
    float minDetailDensity = mix(0.001, 0.02, hardEdgeBlend);
    float edgeDesnityRange = mix(0.08, 0.015, hardEdgeBlend); // 0.0015->0.015 wider
    density *= smoothstep(minDetailDensity, minDetailDensity + edgeDesnityRange, density);
    density *= 1.0 + altitude_fraction * 2.0; // 16->2 less stretch
    density *= mix(1.0, bottomDetail, 0.7);
#endif

    density = max0(density);
    density = lift(
        density,
        mix(clouds_params.l0_edge_sharpening.x,
            clouds_params.l0_edge_sharpening.y,
            altitude_fraction)
    );
    density *= 0.1 + 0.9 * smoothstep(0.2, 0.7, altitude_fraction);

    return density;
}

float clouds_cumulus_optical_depth(
    vec3 ray_origin,
    vec3 ray_dir,
    float dither,
    const uint step_count
) {
    const float step_growth = 2.0;
    float step_length = 0.1 * clouds_cumulus_thickness / float(step_count);
    vec3 ray_pos = ray_origin;
    vec4 ray_step = vec4(ray_dir, 1.0) * step_length;
    float optical_depth = 0.0;
    for (uint i = 0u; i < step_count; ++i, ray_pos += ray_step.xyz) {
        ray_step *= step_growth;
        optical_depth += clouds_cumulus_density(ray_pos + ray_step.xyz * dither)
            * ray_step.w;
    }
    return optical_depth;
}

vec2 clouds_cumulus_scattering(
    float density,
    float light_optical_depth,
    float sky_optical_depth,
    float ground_optical_depth,
    float step_transmittance,
    float cos_theta,
    vec2 bounced_light
) {
    vec2 scattering = vec2(0.0);
    float scatter_amount = clouds_params.l0_scattering_coeff;
    float extinct_amount = clouds_params.l0_extinction_coeff;
    float scattering_integral_times_density
        = (1.0 - step_transmittance) / clouds_params.l0_extinction_coeff;
    float powder_effect = clouds_powder_effect(
        density + density * clouds_params.l0_cumulus_stratus_blend,
        cos_theta
    );
    float scattering_falloff = 0.55
        * mix(lift(clamp01(clouds_params.l0_scattering_coeff / 0.1), 0.33),
              1.0,
              cos_theta * 0.5 + 0.5);
    float phase = clouds_phase_single(cos_theta);
    vec3 phase_g = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + light_optical_depth));
    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatter_amount
            * exp(-extinct_amount * light_optical_depth) * phase
            * (1.0 - 0.5 * clouds_params.l0_shadow);
        scattering.x += scatter_amount
            * isotropic_phase * bounced_light.x;
        scattering.y += scatter_amount
            * isotropic_phase * bounced_light.y;
        scattering.y += scatter_amount
            * exp(-extinct_amount * sky_optical_depth) * isotropic_phase;
        scatter_amount *= scattering_falloff * powder_effect;
        extinct_amount *= 0.4;
        phase_g *= 0.8;
        powder_effect = mix(powder_effect, sqrt(powder_effect), 0.5);
        phase = clouds_phase_multi(cos_theta, phase_g);
    }
    return scattering * scattering_integral_times_density;
}

CloudsResult draw_cumulus_clouds(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky,
    float distance_to_terrain,
    float dither
) {
#if defined PROGRAM_DEFERRED0
    const uint primary_steps_horizon = CLOUDS_CUMULUS_PRIMARY_STEPS_H / 2;
    const uint primary_steps_zenith = CLOUDS_CUMULUS_PRIMARY_STEPS_Z / 2;
#else
    const uint primary_steps_horizon = CLOUDS_CUMULUS_PRIMARY_STEPS_H;
    const uint primary_steps_zenith = CLOUDS_CUMULUS_PRIMARY_STEPS_Z;
#endif
    const uint lighting_steps = CLOUDS_CUMULUS_LIGHTING_STEPS;
    const uint ambient_steps = CLOUDS_CUMULUS_AMBIENT_STEPS;
    const float max_ray_length = 2e4;
    const float min_transmittance = 0.075;
    const float planet_albedo = 0.4;
    const vec3 sky_dir = vec3(0.0, 1.0, 0.0);
    if (clouds_params.l0_coverage.y < eps) {
        return clouds_not_hit;
    }
    uint primary_steps = uint(
        mix(primary_steps_horizon, primary_steps_zenith, abs(ray_dir.y))
    );
    float r = length(air_viewer_pos);
    vec2 dists = intersect_spherical_shell(
        air_viewer_pos,
        ray_dir,
        clouds_cumulus_radius,
        clouds_cumulus_top_radius
    );
    bool planet_intersected
        = intersect_sphere(
              air_viewer_pos,
              ray_dir,
              min(r - 10.0, planet_radius)
          )
              .y
        >= 0.0;
    bool terrain_intersected = distance_to_terrain >= 0.0
        && r < clouds_cumulus_radius && distance_to_terrain < dists.x;
    if (
        dists.y < 0.0
        || planet_intersected
            && r < clouds_cumulus_radius
        || terrain_intersected
    ) {
        return clouds_not_hit;
    }
    float ray_length
        = (distance_to_terrain >= 0.0) ? distance_to_terrain : dists.y;
    ray_length = clamp(ray_length - dists.x, 0.0, max_ray_length);
    float step_length = ray_length * rcp(float(primary_steps));
    vec3 ray_step = ray_dir * step_length;
    vec3 ray_origin
        = air_viewer_pos + ray_dir * (dists.x + step_length * dither);
    vec2 scattering = vec2(0.0);
    float transmittance = 1.0;
    float distance_sum = 0.0;
    float distance_weight_sum = 0.0;
    bool moonlit = sun_dir.y < -0.04;
    vec3 light_dir = moonlit ? moon_dir : sun_dir;
    float cos_theta = dot(ray_dir, light_dir);
    for (uint i = 0u; i < primary_steps; ++i) {
        if (transmittance < min_transmittance) {
            break;
        }
        vec3 ray_pos = ray_origin + ray_step * i;
        float altitude_fraction = (length(ray_pos) - clouds_cumulus_radius)
            * rcp(clouds_cumulus_thickness);
        float density = clouds_cumulus_density(ray_pos);
        if (density < eps) {
            continue;
        }
        float distance_to_sample = distance(ray_origin, ray_pos);
        density
            *= smoothstep(1.0, 0.95, distance_to_sample * rcp(max_ray_length));
#if defined CLOUDS_USE_LOCAL_COVERAGE_MAP
        density *= smoothstep(
            1.0,
            0.9,
            length(ray_pos.xz) * rcp(0.5 * clouds_cumulus_coverage_map_scale)
        );
#endif
        float step_optical_depth
            = density * clouds_params.l0_extinction_coeff * step_length;
        float step_transmittance = exp(-step_optical_depth);
#if defined PROGRAM_DEFERRED0
        vec2 hash = vec2(0.0);
#else
        vec2 hash = hash2(fract(ray_pos));
#endif
        float light_optical_depth = clouds_cumulus_optical_depth(
            ray_pos,
            light_dir,
            hash.x,
            lighting_steps
        );
        float sky_optical_depth = clouds_cumulus_optical_depth(
            ray_pos,
            sky_dir,
            hash.y,
            ambient_steps
        );
        float ground_optical_depth
            = mix(density, 1.0, clamp01(altitude_fraction * 2.0 - 1.0))
            * altitude_fraction * clouds_cumulus_thickness;
        vec2 bounced_light = clouds_multiple_scattering_bounce(
            clouds_params.l0_extinction_coeff,
            clouds_params.l0_scattering_coeff,
            light_optical_depth,
            sky_optical_depth,
            ground_optical_depth,
            altitude_fraction,
            light_dir,
            planet_albedo
        );
        scattering
            += clouds_cumulus_scattering(
                   density,
                   light_optical_depth,
                   sky_optical_depth,
                   ground_optical_depth,
                   step_transmittance,
                   cos_theta,
                   bounced_light
               )
            * transmittance;
        transmittance *= step_transmittance;
        distance_sum += distance_to_sample * density;
        distance_weight_sum += density;
    }
    vec3 light_color
        = sunlight_color * atmosphere_transmittance(ray_origin, light_dir);
    light_color = atmosphere_post_processing(light_color);
    light_color *= moonlit ? moon_color : sun_color;
    float clouds_transmittance
        = linear_step(min_transmittance, 1.0, transmittance);
    vec3 clouds_scattering
        = scattering.x * light_color + scattering.y * sky_color;
    clouds_scattering = clouds_aerial_perspective(
        clouds_scattering,
        clouds_transmittance,
        air_viewer_pos,
        ray_origin,
        ray_dir,
        clear_sky
    );
    float apparent_distance = (distance_weight_sum == 0.0)
        ? 1e6
        : (distance_sum / distance_weight_sum)
            + distance(air_viewer_pos, ray_origin);
    return CloudsResult(
        vec4(clouds_scattering, scattering.y),
        clouds_transmittance,
        apparent_distance
    );
}

#endif
