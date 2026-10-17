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

#if !defined INCLUDE_SKY_CLOUDS_COVERAGE_MAP
#define INCLUDE_SKY_CLOUDS_COVERAGE_MAP

// Distance covered by the cumulus coverage map on each axis (m^2)
const float cloudsCumulusCoverageMapScale = 1.5e5;

const float cloudsCoverageMapDistortion = 0.8;

float cloudsCumulusLocalCoverage(vec2 pos) {
    const float windAngle = cloudsCumulusWindAngle * degree;
    const vec2 windVelocity
        = cloudsCumulusWindSpeed * vec2(cos(windAngle), sin(windAngle));

    pos += cameraPosition.xz * cloudsScale;
    pos += windVelocity * worldAge;

    // Sample noise
    vec2 p1 = (0.000002 / cloudsCumulusSize) * pos;
    vec2 p2 = (0.000027 / cloudsCumulusSize) * pos;
    vec2 noise = vec2(
        texture(noisetex, p1).x, // cloud coverage
        texture(noisetex, p2).w // cloud shape
    );

    // Compute cumulus coverage
    float coverageCu = 0.0, coverageSt = 0.0;

    if (cloudsParams.l0CumulusStratusBlend < 1.0 - eps) {
        coverageCu = mix(
            cloudsParams.l0Coverage.x,
            cloudsParams.l0Coverage.y,
            noise.x
        );
        coverageCu = linearStep(1.0 - coverageCu, 1.0, noise.y);
    }

    // Compute stratus coverage
    if (cloudsParams.l0CumulusStratusBlend > eps) {
        coverageSt = cubicSmooth(linearStep(
            0.9 - cloudsParams.l0Coverage.x,
            1.0,
            2.0 * noise.x * cloudsParams.l0Coverage.y
        ));
        coverageSt = 0.5 * coverageSt
            + 1.0 * coverageSt * linearStep(0.3, 0.6, noise.y);
        coverageSt = coverageSt / (coverageSt + 1.0);
    }

    return mix(
        coverageCu,
        coverageSt,
        cloudsParams.l0CumulusStratusBlend
    );
}

vec2 projectCloudsCumulusCoverageMap(vec3 pos) {
    // Scale position
    vec2 coverageMapUv
        = pos.xz * rcp(0.5 * cloudsCumulusCoverageMapScale);

    // Distort so that clouds closer to the player are higher resolution
    coverageMapUv /= cloudsCoverageMapDistortion * length(coverageMapUv)
        + (1.0 - cloudsCoverageMapDistortion);

    // Scale to [0, 1]
    coverageMapUv = coverageMapUv * 0.5 + 0.5;

    return coverageMapUv;
}

float renderCloudsCumulusCoverageMap(vec2 uv) {
    // Get clouds position
    vec2 pos = uv * 2.0 - 1.0;
    pos *= (1.0 - cloudsCoverageMapDistortion)
        / (1.0 - length(pos) * cloudsCoverageMapDistortion);
    pos *= 0.5 * cloudsCumulusCoverageMapScale;

    return cloudsCumulusLocalCoverage(pos);
}

#endif // INCLUDE_SKY_CLOUDS_COVERAGE_MAP
