void modify_light(inout Light light, vec3 world_pos) {
    if (light.index < 0) {
#if HANDHELD_LIGHTING_MODE == HANDHELD_LIGHTING_OFF
        light.color = vec3(0.0);
#else
        light.color *= HANDHELD_LIGHTING_INTENSITY;
#endif
    } else {
        light.color *= BLOCKLIGHT_I;
    }
}