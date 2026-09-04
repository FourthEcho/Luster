#if !defined INCLUDE_FOG_OVERWORLD_MIST
#define INCLUDE_FOG_OVERWORLD_MIST

// ---- Mist mode sentinels (also defined in settings.glsl for Iris) ----
#ifndef MIST_MODE_OFF
#define MIST_MODE_OFF      0
#define MIST_MODE_BASIC    1
#define MIST_MODE_ADVANCED 2
#endif

#if MIST_MODE != MIST_MODE_OFF

// Returns the scalar mist density at world_pos.
// Two-octave hierarchical noise with a curl-advected wind offset gives
// organic wisps rather than the blobby single-octave value3D used by Kappa.
float mist_density(vec3 world_pos) {
    // Slow horizontal drift — two independent directions for each octave
    vec2 wind0 = vec2(frameTimeCounter * 0.004,  frameTimeCounter * 0.0025);
    vec2 wind1 = vec2(frameTimeCounter * 0.0068, frameTimeCounter * 0.0041);

    float n0 = texture(noisetex, world_pos.xz * 0.008 + wind0).w;
    float n1 = texture(noisetex, world_pos.xz * 0.022 + wind1).w;
    float noise = n0 * 0.7 + n1 * 0.3;

    float altitude = world_pos.y;

    // Exponential falloff above sea level, hard cap at MIST_ALTITUDE.
    // wetness thickens the layer — after rain, evaporation raises mist density.
    float alt_above_sea = altitude - (SEA_LEVEL + MIST_SEA_LEVEL_BIAS);
    float envelope = exp2(-max0(alt_above_sea) * MIST_FALLOFF_RATE);
    envelope *= sqr(1.0 - linear_step(
        float(MIST_ALTITUDE) - 12.0,
        float(MIST_ALTITUDE),
        altitude
    ));
    envelope *= 1.0 + 0.4 * wetness;

    return linear_step(0.35, 0.75, noise) * envelope * MIST_DENSITY;
}

// Density-varying phase function.
// Thin wisps (low density) scatter forward (high g); dense patches scatter
// more isotropically (low g). A small backscatter lobe gives the faint
// corona glow around the sun seen through real mist.
float mist_phase(float cos_theta, float local_density) {
    float g = mix(0.75, 0.40, clamp01(local_density * 8.0));
    return 0.8 * henyey_greenstein_phase(cos_theta, g)
         + 0.2 * henyey_greenstein_phase(cos_theta, -0.1);
}

#if MIST_MODE == MIST_MODE_ADVANCED
// Short shadow ray toward the sun to compute mist self-shadowing OD.
// Only fired when the sun is near the horizon (where self-shadowing matters)
// and local density is non-trivial — free on clear days.
// Also multiplies by cloud shadows above the mist layer, which Kappa omits.
float mist_shadow_od(vec3 world_pos, float local_density) {
    if (local_density < 0.01 || sun_dir.y > 0.3) return 0.0;

    const int   steps     = MIST_SHADOW_STEPS;
    const float step_size = 10.0;

    float od = 0.0;
    vec3  pos = world_pos;

    for (int i = 0; i < steps; ++i, pos += light_dir * step_size) {
        if (pos.y > float(MIST_ALTITUDE)) break;
        od += mist_density(pos) * step_size;
    }

#ifdef CLOUD_SHADOWS
    od *= get_cloud_shadows(colortex8, world_pos - cameraPosition);
#endif

    return od;
}
#endif // MIST_MODE_ADVANCED

#endif // MIST_MODE != MIST_MODE_OFF
#endif // INCLUDE_FOG_OVERWORLD_MIST
