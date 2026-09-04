#if !defined INCLUDE_UTILITY_ENCODING
#define INCLUDE_UTILITY_ENCODING

// Returns +-1
vec2 sign_non_zero(vec2 v) {
    return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

// http://jcgt.org/published/0003/02/01/
vec2 encode_unit_vector(vec3 v) {
    // Project the sphere onto the octahedron, and then onto the xy plane
    vec2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + abs(v.z)));

    // Reflect the folds of the lower hemisphere over the diagonals
    p = v.z <= 0.0 ? ((1.0 - abs(p.yx)) * sign_non_zero(p)) : p;

    // Scale to [0, 1]
    return 0.5 * p + 0.5;
}

vec3 decode_unit_vector(vec2 e) {
    // Scale to [-1, 1]
    e = 2.0 * e - 1.0;

    // Extract Z component
    vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));

    // Reflect the folds of the lower hemisphere over the diagonals
    if (v.z < 0) {
        v.xy = (1.0 - abs(v.yx)) * sign_non_zero(v.xy);
    }

    return normalize(v);
}

// The following functions are from
// https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/packing.glsl

float pack_unorm_2x4(vec2 xy) {
    return dot(floor(15.0 * xy + 0.5), vec2(1.0 / 255.0, 16.0 / 255.0));
}

float pack_unorm_2x4(float x, float y) { return pack_unorm_2x4(vec2(x, y)); }

float pack_unorm_2x8(vec2 v) {
    return dot(floor(255.0 * v + 0.5), vec2(1.0 / 65535.0, 256.0 / 65535.0));
}

float pack_unorm_2x8(float x, float y) { return pack_unorm_2x8(vec2(x, y)); }

vec2 unpack_unorm_2x8(float pack) {
    vec2 xy;
    xy.x = modf((65535.0 / 256.0) * pack, xy.y);
    return xy * vec2(256.0 / 255.0, 1.0 / 255.0);
}

// Pack 4 unsigned normalized numbers into a uint32_t with arbitrary precision
// per channel

// Split one value to be encoded as 16 bit unorm into two values to be encoded
// as 8 bit unorm
vec2 split_2x8(float x) {
    uint i = uint(x * 65535.0);
    uint lower = i & 255u;
    uint upper = i >> 8u;

    return vec2(float(lower) * rcp(255.0), float(upper) * rcp(255.0));
}

float unsplit_2x8(vec2 v) {
    uint lower = uint(v.x * 255.0);
    uint upper = uint(v.y * 255.0);
    uint i = lower | (upper << 8);

    return float(i) * rcp(65535.0);
}

#endif // INCLUDE_UTILITY_ENCODING
