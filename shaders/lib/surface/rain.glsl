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

#if !defined INCLUDE_SURFACE_RAIN_RIPPLES
#define INCLUDE_SURFACE_RAIN_RIPPLES

#ifdef rainRipples
// Use a rain_ prefix to avoid collisions with other hash helpers.
float rainHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 rainHash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// coord: world-space surface position (meters). time: seconds.
vec3 rainRippleNormal(vec2 coord, float time) {
    const float cellDensity = 5.0; // ~20 cm cells at world scale
    const int maxRadius = 1;
    const float waveFrequency = 21.0; // ~30 cm ring wavelength
    const float h = 1e-2;

    vec2 uv = coord * cellDensity;
    vec2 p0 = floor(uv);
    vec2 circles = vec2(0.0);

    for (int j = -maxRadius; j <= maxRadius; ++j) {
        for (int i = -maxRadius; i <= maxRadius; ++i) {
            vec2 pi = p0 + vec2(i, j);
            vec2 p = pi + rainHash22(pi);

            float t = fract(0.9 * time + rainHash12(pi));
            vec2 v = p - uv;
            // Hardened normalize: a drop centered exactly on the fragment
            // would divide by zero (undefined -> NaN poison).
            vec2 dir = v / max(length(v), 1e-4);

            float d = length(v) - float(maxRadius + 1) * t;
            float d1 = d - h;
            float d2 = d + h;
            float envelope1 = smoothstep(-0.6, -0.3, d1) * smoothstep(0.0, -0.3, d1);
            float envelope2 = smoothstep(-0.6, -0.3, d2) * smoothstep(0.0, -0.3, d2);
            float p1 = sin(waveFrequency * d1) * envelope1;
            float p2 = sin(waveFrequency * d2) * envelope2;
            float decay = (1.0 - t) * (1.0 - t);
            circles += 0.5 * dir * ((p2 - p1) / (2.0 * h) * decay);
        }
    }
    circles /= float((maxRadius * 2 + 1) * (maxRadius * 2 + 1));

    vec3 n = vec3(circles, sqrt(max(1.0 - dot(circles, circles), 0.0)));
    return n;
}
#endif // rainRipples

#endif // INCLUDE_SURFACE_RAIN_RIPPLES

#ifdef LUSTER_INCLUDE_RAIN_PUDDLES
#if !defined INCLUDE_SURFACE_RAIN_PUDDLES
#define INCLUDE_SURFACE_RAIN_PUDDLES


float getRippleHeight(vec2 coord) {
    const float rippleFrequency = 0.3;
    const float rippleSpeed = 0.1;
    const vec2 rippleDir0 = vec2(3.0, 4.0) / 5.0;
    const vec2 rippleDir1 = vec2(-5.0, -12.0) / 13.0;

    float rippleNoise1
        = texture(
              noisetex,
              coord * rippleFrequency
                  + frameTimeCounter * rippleSpeed * rippleDir0
        )
              .y;
    float rippleNoise2
        = texture(
              noisetex,
              coord * rippleFrequency
                  + frameTimeCounter * rippleSpeed * rippleDir1
        )
              .y;

    return mix(rippleNoise1, rippleNoise2, 0.5);
}

// Keep puddles limited to biomes where rain is possible.
float getPuddleWeatherFactor() {
    return biomeMayRain;
}

float getPuddleNoise(vec3 worldPos, vec3 flatNormal, vec2 lightLevels) {
    const float puddleFrequency = 0.025;

    float puddle = texture(noisetex, worldPos.xz * puddleFrequency).w;

    float weatherFactor = getPuddleWeatherFactor();

    // wetness is the host-smoothed rain amount, gated by biome.
    puddle = linearStep(0.45, 0.55, puddle) * wetness * weatherFactor
        * step(0.99, flatNormal.y);

    // Require sky visibility and suppress puddles near strong blocklight.
    puddle *= (1.0 - cube(lightLevels.x))
        * linearStep(14.0 / 15.0, 1.0, lightLevels.y);

    // Apply user-controlled puddle intensity slider.
    puddle *= rainPuddlesIntensity;

    return puddle;
}

// Per-channel wet-porosity darkening with saturating reflectance.
vec3 applyWetPorosityDarkening(vec3 albedo, float porosityAmount, float wetnessFactor) {
#ifndef porosity
    return albedo;
#else
    // Maximum absorbed fraction per internal bounce, scaled by porosityAmount.
    // effect self-limiting on already-dark surfaces.
    vec3 k = 0.7 * porosityAmount * sqrt(albedo);

    // KM saturating-absorption: R_wet = (1-k)*R / (1 - k*R)
    vec3 wetAlbedo = (1.0 - k) * albedo / max(vec3(1e-4), 1.0 - k * albedo);

    return mix(albedo, wetAlbedo, wetnessFactor * porosityAmount);
#endif
}

bool getRainPuddles(
    vec3 worldPos,
    vec3 flatNormal,
    vec2 lightLevels,
    float porosityAmount,
    uint materialMask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness,
    inout float ssrMultiplier
) {
#ifndef rainPuddles
    return false;
#endif

    const float puddleF0 = 0.02;
    const float puddleRoughness = 0.002;
    const float puddleDarkeningFactor = 0.33;
    const float puddleDarkeningFactorPorous = 0.67;

    // Skip leaves entirely — puddles on leaves look wrong since the
    // canopy should be shedding water, not pooling it.
    if (materialMask == MATERIAL_LEAVES) {
        return false;
    }

    // Negative sentinels identify dimensions or biomes where water cannot reach.
    if (wetness < 0.0 || biomeMayRain < 0.0) {
        return false;
    }

    float puddle = getPuddleNoise(worldPos, flatNormal, lightLevels);

    if (puddle < eps) {
        return false;
    }

    // Porous materials darken more and retain less surface water.
    albedo *= 1.0 - puddleDarkeningFactorPorous * porosityAmount * puddle;
    puddle *= 1.0 - porosityAmount;
    albedo *= 1.0 - puddleDarkeningFactor * puddle;

    // Replace material with puddle material
    f0 = max(f0, mix(f0, vec3(puddleF0), puddle));
    roughness = puddleRoughness;
    ssrMultiplier = max(ssrMultiplier, puddle);

    // Blend the same rain-ring normals used by open water into wet areas.
    const float h = 0.1;
#ifdef rainRipples
    // Shared analytic rings; puddle coverage keeps dry land unaffected.
    vec3 rippleNormal = vec3(
        rainRippleNormal(worldPos.xz, frameTimeCounter).xy,
        1.0
    );
#else
    float ripple0 = getRippleHeight(worldPos.xz);
    float ripple1 = getRippleHeight(worldPos.xz + vec2(h, 0.0));
    float ripple2 = getRippleHeight(worldPos.xz + vec2(0.0, h));
    vec3 rippleNormal = vec3(ripple1 - ripple0, ripple2 - ripple0, h);
#endif
#ifdef rainRipples
    // Same strength convention as open water so one slider drives both.
    float rippleGain = 0.30 * rainRippleStrength;
#else
    float rippleGain = 0.05;
#endif
    rippleNormal.xy
        *= rippleGain
        * smoothstep(
               0.0,
               0.1,
               abs(dot(flatNormal, normalize(worldPos - cameraPosition)))
        );
    rippleNormal = normalize(rippleNormal);
    rippleNormal = rippleNormal.xzy; // convert to world space

    normal = mix(normal, flatNormal, puddle);
    normal = mix(normal, rippleNormal, puddle * rainStrength);
    normal = normalizeSafe(normal);

    return true;
}

#endif // INCLUDE_SURFACE_RAIN_PUDDLES
#endif // LUSTER_INCLUDE_RAIN_PUDDLES
