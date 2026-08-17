#if !defined INCLUDE_SKY_CLOUDS_COVERAGE_MAP
#define INCLUDE_SKY_CLOUDS_COVERAGE_MAP

// Dedicated weather/cloud coverage map. Channel Z of colortex8 stores this field while X/Y hold cloud shadow data.
// Distance covered by the cumulus coverage map on each axis (m^2)
const float clouds_cumulus_coverage_map_scale = 1.5e5;

const float clouds_coverage_map_distortion = 0.8;

vec4 clouds_weather_field(vec2 world_xz) {
    vec2 p = world_xz * 0.00000135;
    p += vec2(world_age * 0.000000035, -world_age * 0.000000021);

    vec4 large = texture(noisetex, p);
    vec4 medium = texture(noisetex, p * 0.43 + vec2(0.173, 0.417));

    float coverage = clamp(0.62 * large.x + 0.38 * medium.w, 0.0, 1.0);
    float humidity = clamp(0.55 * large.w + 0.45 * medium.x, 0.0, 1.0);
    float convection = clamp(0.55 * medium.y + 0.45 * large.z, 0.0, 1.0);
    float storm = smoothstep(0.48, 0.82, coverage * 0.60 + humidity * 0.40);
    storm *= smoothstep(0.42, 0.86, convection);
    storm = clamp(storm * 1.18, 0.0, 1.0);

    return vec4(coverage, humidity, convection, storm);
}

float clouds_cumulus_local_coverage(vec2 pos) {
    const float wind_angle = CLOUDS_CUMULUS_WIND_ANGLE * degree;
    const vec2 wind_velocity
        = CLOUDS_CUMULUS_WIND_SPEED * vec2(cos(wind_angle), sin(wind_angle));

    pos += cameraPosition.xz * CLOUDS_SCALE;
    pos += wind_velocity * world_age;

    // Sample noise
    vec2 p1 = (0.000002 / CLOUDS_CUMULUS_SIZE) * pos;
    vec2 p2 = (0.000027 / CLOUDS_CUMULUS_SIZE) * pos;
    vec2 noise = vec2(
        texture(noisetex, p1).x, // cloud coverage
        texture(noisetex, p2).w // cloud shape
    );

    // Compute cumulus coverage
    float coverage_cu = 0.0, coverage_st = 0.0;

    if (clouds_params.l0_cumulus_stratus_blend < 1.0 - eps) {
        coverage_cu = mix(
            clouds_params.l0_coverage.x,
            clouds_params.l0_coverage.y,
            noise.x
        );
        coverage_cu = linear_step(1.0 - coverage_cu, 1.0, noise.y);
    }

    // Compute stratus coverage
    if (clouds_params.l0_cumulus_stratus_blend > eps) {
        coverage_st = cubic_smooth(linear_step(
            0.9 - clouds_params.l0_coverage.x,
            1.0,
            2.0 * noise.x * clouds_params.l0_coverage.y
        ));
        coverage_st = 0.5 * coverage_st
            + 1.0 * coverage_st * linear_step(0.3, 0.6, noise.y);
        coverage_st = coverage_st / (coverage_st + 1.0);
    }

    vec4 weather_field = clouds_weather_field(pos);
    float weather_coverage = mix(0.60, 1.18, weather_field.x);
    float moisture = mix(0.72, 1.20, weather_field.y);

    return clamp01(mix(
        coverage_cu,
        coverage_st,
        clouds_params.l0_cumulus_stratus_blend
    ) * weather_coverage * moisture);
}

vec2 project_clouds_cumulus_coverage_map(vec3 pos) {
    // Scale position
    vec2 coverage_map_uv
        = pos.xz * rcp(0.5 * clouds_cumulus_coverage_map_scale);

    // Distort so that clouds closer to the player are higher resolution
    coverage_map_uv /= clouds_coverage_map_distortion * length(coverage_map_uv)
        + (1.0 - clouds_coverage_map_distortion);

    // Scale to [0, 1]
    coverage_map_uv = coverage_map_uv * 0.5 + 0.5;

    return coverage_map_uv;
}

float render_clouds_cumulus_coverage_map(vec2 uv) {
    // Get clouds position
    vec2 pos = uv * 2.0 - 1.0;
    pos *= (1.0 - clouds_coverage_map_distortion)
        / (1.0 - length(pos) * clouds_coverage_map_distortion);
    pos *= 0.5 * clouds_cumulus_coverage_map_scale;

    return clouds_cumulus_local_coverage(pos);
}

#endif // INCLUDE_SKY_CLOUDS_COVERAGE_MAP
