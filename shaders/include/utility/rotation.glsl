#if !defined INCLUDE_UTILITY_ROTATION
#define INCLUDE_UTILITY_ROTATION

mat2 get_rotation_matrix(float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return mat2(cosine, -sine, sine, cosine);
}

// Rotation matrix using Rodriguez's rotation formula
// https://math.stackexchange.com/questions/3233842/rotation-matrix-from-axis-angle-representation
mat3 get_rotation_matrix(vec3 axis, float cosine, float sine) {
    vec3 mul = axis - axis * cosine;
    vec3 add = axis * sine;
    vec3 axis_sq = axis * axis;
    vec3 diagonal = axis_sq + (cosine - cosine * axis_sq);

    return mat3(
        diagonal.x,
        axis.x * mul.y - add.z,
        axis.x * mul.z + add.y,
        axis.x * mul.y + add.z,
        diagonal.y,
        axis.y * mul.z - add.x,
        axis.x * mul.z - mul.y,
        axis.y * mul.z + add.x,
        diagonal.z
    );
}

mat3 get_rotation_matrix(vec3 axis, float angle) {
    return get_rotation_matrix(axis, cos(angle), sin(angle));
}

#endif // INCLUDE_UTILITY_ROTATION
