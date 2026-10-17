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

#if !defined INCLUDE_UTILITY_GEOMETRY
#define INCLUDE_UTILITY_GEOMETRY

#include "/lib/util/fastMath.glsl"

// Sphere/AABB intersection methods from https://www.scratchapixel.com

// Returns +-1
vec3 signNonZero(vec3 v) {
    return vec3(
        v.x >= 0.0 ? 1.0 : -1.0,
        v.y >= 0.0 ? 1.0 : -1.0,
        v.z >= 0.0 ? 1.0 : -1.0
    );
}

// from https://ebruneton.github.io/precomputedAtmosphericScattering/
vec2 intersectSphere(float mu, float r, float sphereRadius) {
    float discriminant = r * r * (mu * mu - 1.0) + sqr(sphereRadius);

    if (discriminant < 0.0) {
        return vec2(-1.0);
    }

    discriminant = sqrt(discriminant);
    return -r * mu + vec2(-discriminant, discriminant);
}

vec2 intersectSphere(vec3 rayOrigin, vec3 rayDir, float sphereRadius) {
    float b = dot(rayOrigin, rayDir);
    float discriminant
        = sqr(b) - dot(rayOrigin, rayOrigin) + sqr(sphereRadius);

    if (discriminant < 0.0) {
        return vec2(-1.0);
    }

    discriminant = sqrt(discriminant);
    return -b + vec2(-discriminant, discriminant);
}

vec2 intersectSphericalShell(
    float mu,
    float r,
    float innerSphereRadius,
    float outerSphereRadius
) {
    vec2 innerSphereDists = intersectSphere(mu, r, innerSphereRadius);
    vec2 outerSphereDists = intersectSphere(mu, r, outerSphereRadius);

    bool innerSphereIntersected = innerSphereDists.y >= 0.0;
    bool outerSphereIntersected = outerSphereDists.y >= 0.0;

    if (!outerSphereIntersected) {
        return vec2(-1.0);
    }

    vec2 dists;
    dists.x = innerSphereIntersected && innerSphereDists.x < 0.0
        ? innerSphereDists.y
        : max0(outerSphereDists.x);
    dists.y = innerSphereIntersected && innerSphereDists.x > 0.0
        ? innerSphereDists.x
        : outerSphereDists.y;

    return dists;
}

vec2 intersectSphericalShell(
    vec3 rayOrigin,
    vec3 rayDir,
    float innerSphereRadius,
    float outerSphereRadius
) {
    vec2 innerSphereDists
        = intersectSphere(rayOrigin, rayDir, innerSphereRadius);
    vec2 outerSphereDists
        = intersectSphere(rayOrigin, rayDir, outerSphereRadius);

    bool innerSphereIntersected = innerSphereDists.y >= 0.0;
    bool outerSphereIntersected = outerSphereDists.y >= 0.0;

    if (!outerSphereIntersected) {
        return vec2(-1.0);
    }

    vec2 dists;
    dists.x = innerSphereIntersected && innerSphereDists.x < 0.0
        ? innerSphereDists.y
        : max0(outerSphereDists.x);
    dists.y = innerSphereIntersected && innerSphereDists.x > 0.0
        ? innerSphereDists.x
        : outerSphereDists.y;

    return dists;
}

vec2 intersectCylindricalShell(
    vec3 rayOrigin,
    vec3 rayDir,
    float innerCylinderRadius,
    float outerCylinderRadius
) {
    float lenO = length(rayOrigin.xz);
    float rlenD = rcpLength(rayDir.xz);

    float t1 = (innerCylinderRadius - lenO) * rlenD;
    float t2 = (outerCylinderRadius - lenO) * rlenD;

    return vec2(t1, t2);
}

#endif // INCLUDE_UTILITY_GEOMETRY
