#if !defined INCLUDE_LIGHTING_IBL
#define INCLUDE_LIGHTING_IBL

#include "/include/sky/projection.glsl"

const int ibl_sample_count = IBL_SAMPLES;

// Cosine-weighted low-discrepancy sample direction in the local frame of the
// sampling hemisphere (z = hemisphere axis).
//
// Stratified radii + golden angle azimuth produce a low-discrepancy disc
// pattern; projecting it onto the hemisphere distributes directions with a
// cosine distribution, matching the Lambertian diffuse BRDF
vec3 get_ibl_local_sample(int sample_index, int sample_count, float rotation) {
    float radius = sqrt((float(sample_index) + 0.5) / float(sample_count));
    float azimuth = float(sample_index) * 2.4 + rotation;

    vec2 disc = radius * vec2(cos(azimuth), sin(azimuth));

    return vec3(disc, sqrt(max0(1.0 - dot(disc, disc))));
}

// Diffuse image based lighting.
//
// Instead of compressing the sky map into low frequency spherical harmonics
// (which washes out the sun disk, clouds, aurora and the horizon gradient),
// directly integrate it over the hemisphere around the bent normal using
// cosine-weighted sampling.
//
// The half_pi scale factor keeps the brightness consistent with the previous
// spherical harmonics implementation, which underestimated true irradiance by
// the same amount
vec3 get_ibl_irradiance(vec3 bent_normal, float ao) {
    vec3 up = vec3(0.0, 1.0, 0.0);

    if (abs(dot(up, bent_normal)) > 0.99) {
        up = vec3(1.0, 0.0, 0.0);
    }

    vec3 tangent = normalize(cross(up, bent_normal));
    vec3 bitangent = cross(bent_normal, tangent);

    // Slowly rotate the sample pattern so temporal accumulation with TAA
    // converges to the true irradiance
    float rotation = 0.05 * frameTimeCounter;

    vec3 irradiance = vec3(0.0);

    for (int sample_index = 0; sample_index < ibl_sample_count;
         ++sample_index) {
        vec3 local_dir
            = get_ibl_local_sample(sample_index, ibl_sample_count, rotation);
        vec3 sample_dir = local_dir.z * bent_normal + local_dir.x * tangent
            + local_dir.y * bitangent;

        irradiance += texture(colortex4, project_sky(sample_dir)).rgb;
    }

    irradiance *= half_pi / float(ibl_sample_count);

    // The bent normal already accounts for occlusion directionally; scaling by
    // AO approximates the visibility cone used by the previous implementation
    irradiance *= ao;

    return irradiance;
}

#endif // INCLUDE_LIGHTING_IBL
