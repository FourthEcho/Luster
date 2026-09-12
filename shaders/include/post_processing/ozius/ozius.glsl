#if !defined INCLUDE_POST_PROCESSING_OZIUS
#define INCLUDE_POST_PROCESSING_OZIUS

#include "/include/utility/color.glsl"

// Tonemapping operator made by Zombye for his old shader pack Ozius
// It was given to me by Jessie
vec3 tonemap_ozius(vec3 rgb) {
    const vec3 a = vec3(0.46, 0.46, 0.46);
    const vec3 b = vec3(0.60, 0.60, 0.60);

    rgb *= 1.6;

    vec3 cr = mix(vec3(dot(rgb, luminance_weights_ap1)), rgb, 0.5) + 1.0;

    rgb = pow(rgb / (1.0 + rgb), a);
    return pow(rgb * rgb * (-2.0 * rgb + 3.0), cr / b);
}

#endif // INCLUDE_POST_PROCESSING_OZIUS
