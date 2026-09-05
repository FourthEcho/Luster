#if !defined INCLUDE_CAMERA_LENS_FLARE
#define INCLUDE_CAMERA_LENS_FLARE

// ---------------------------------------------------------------------------
//   Lens flare: ghosts + halo
//
//   Architecture follows Kappa's lens passes (bright blurred source, mirrored
//   ghost march with chromatic spacing, halo ring, additive-back), rewritten
//   for this pipeline: no extra programs or buffers exist here, so the
//   smallest bloom tiles stand in for Kappa's bokeh buffer (pre-blurred
//   full-frame bright content), ghosts march with bicubic taps, and the
//   result composites pre-tonemap in the grading pass.
//
//   Kept from our own design (Kappa has no analogue):
//    * ghosts track the true projected sun and fade when it leaves the
//      frame or drops below the horizon, instead of firing blindly;
//    * rain/storm dimming and an energy-bounded output that cannot blow
//      the frame out no matter how bright the source is.
//
//   Requires from the including program: colortex0 (bloom tiles) +
//   colortex5 samplers, view_pixel_size + aspectRatio uniforms, and sun_dir,
//   gbufferProjection, gbufferModelView, rainStrength uniforms.
// ---------------------------------------------------------------------------

#ifdef LENS_FLARE
// Blurred bright source: bloom tile 2 is the full frame downsampled into a
// small tile, i.e. pre-blurred bright content like Kappa's bokeh buffer.
// Threshold is subtractive so sub-threshold sky contributes exactly zero.
vec3 lens_flare_source(vec2 screen_uv) {
#ifdef BLOOM
    const float tile_scale = 0.5 * exp2(-2.0);
    const vec2 tile_offset = vec2(1.0 - exp2(-2.0), 0.0);
    vec2 tile_uv = clamp(screen_uv, vec2(0.0), vec2(1.0)) * tile_scale
        + tile_offset;
    vec3 c = bicubic_filter(colortex0, tile_uv).rgb;
#else
    vec3 c = texture(colortex5, clamp(screen_uv, vec2(0.0), vec2(1.0))).rgb;
#endif
    return max0(c - LENS_FLARE_THRESHOLD);
}

// Project the sun into screen UV; facing fades to 0 as the sun drops
// below the horizon or swings behind the camera.
vec2 lens_flare_sun_uv(out float facing) {
    vec3 view_sun = mat3(gbufferModelView) * sun_dir;
    vec4 clip = gbufferProjection * vec4(view_sun * 100.0, 1.0);
    vec2 sun_uv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
    facing = smoothstep(0.05, -0.15, view_sun.z)
        * smoothstep(-0.12, 0.02, sun_dir.y);
    return sun_uv;
}

// Ghost chain mirrored around frame center, marched outward with growing
// per-channel spacing so red/green/blue separate down the chain. Center
// weight keeps ghosts strongest mid-frame and kills edge smear.
vec3 lens_flare_ghosts(vec2 uv) {
    vec2 mirror = 1.0 - uv;
    vec2 axis = (vec2(0.5) - mirror) * LENS_FLARE_SPACING;

    vec3 acc = vec3(0.0);
    for (int i = 1; i <= LENS_FLARE_GHOSTS; ++i) {
        float fi = float(i);
        vec2 base = mirror + axis * fi;
        if (clamp01(base) != base) {
            continue;
        }
        vec3 ghost;
        ghost.r = lens_flare_source(base + axis * 0.01 * fi).r;
        ghost.g = lens_flare_source(base).g;
        ghost.b = lens_flare_source(base - axis * 0.01 * fi).b;

        float edge = 1.0 - smoothstep(0.0, 0.75, length(base - 0.5));
        acc += ghost * (edge * edge) / (1.0 + fi * 0.5);
    }

    return acc;
}

#ifdef LENS_FLARE_HALO
// Halo ring around the sun position: gaussian annulus sampled
// chromatically, widened/narrowed by the width control.
vec3 lens_flare_halo(vec2 uv, vec2 sun_uv) {
    vec2 huv = uv - sun_uv;
    huv.x *= aspectRatio;
    float dist = length(huv);
    vec2 dir = huv / max(dist, 1e-4);

    float ring = exp(
        -pow(
            (dist / max(LENS_FLARE_HALO_RADIUS, 1e-4) - 1.0)
                / max(LENS_FLARE_HALO_WIDTH, 0.05),
            2.0
        )
    );
    if (ring < 1e-4) {
        return vec3(0.0);
    }

    vec2 base = sun_uv + dir * LENS_FLARE_HALO_RADIUS
        * vec2(1.0 / aspectRatio, 1.0);
    vec3 halo;
    halo.r = lens_flare_source(base + dir * 0.004).r;
    halo.g = lens_flare_source(base).g;
    halo.b = lens_flare_source(base - dir * 0.004).b;

    return halo * ring;
}
#endif

vec3 get_lens_flare(vec2 uv) {
    float facing;
    vec2 sun_uv = lens_flare_sun_uv(facing);
    if (facing < 1e-4) {
        return vec3(0.0);
    }

    vec3 flare = lens_flare_ghosts(uv);
#ifdef LENS_FLARE_HALO
    flare += lens_flare_halo(uv, sun_uv);
#endif

    // Storms and night haze kill flare faster than the sun itself dims
    flare *= facing * (1.0 - rainStrength * 0.9);

    // Energy-bounded output: soft-compress the brightest channel so the
    // ghost stack can never blow the frame out no matter how bright the
    // source is. Intensity scales the knee, not a raw multiplier.
    float brightest = max(max(flare.r, flare.g), max(flare.b, 1e-4));
    flare *= (1.0 - exp(-brightest * LENS_FLARE_INTENSITY * 0.02))
        / brightest;

    return flare;
}
#endif

#endif // INCLUDE_CAMERA_LENS_FLARE
