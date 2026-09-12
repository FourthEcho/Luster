#if !defined INCLUDE_UTILITY_SAMPLING
#define INCLUDE_UTILITY_SAMPLING

vec2 vogel_disc_sample(int step_index, int step_count, float rotation) {
    const float golden_angle = 2.4;

    float r = sqrt(step_index + 0.5) / sqrt(float(step_count));
    float theta = step_index * golden_angle + rotation;

    return r * vec2(cos(theta), sin(theta));
}

vec3 uniform_sphere_sample(vec2 hash) {
    hash.x *= tau;
    hash.y = 2.0 * hash.y - 1.0;
    return vec3(
        vec2(sin(hash.x), cos(hash.x)) * sqrt(1.0 - hash.y * hash.y),
        hash.y
    );
}

// Smootherstep-filtered texture lookup.
// https://iquilezles.org/www/articles/texture/texture.htm
vec4 smooth_filter(sampler2D sampler, vec2 coord) {
    vec2 res = vec2(textureSize(sampler, 0));

    coord = coord * res + 0.5;

    vec2 i, f = modf(coord, i);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    coord = i + f;

    coord = (coord - 0.5) / res;
    return texture(sampler, coord);
}

// https://amietia.com/lambertnotangent.html
#endif // INCLUDE_UTILITY_SAMPLING
