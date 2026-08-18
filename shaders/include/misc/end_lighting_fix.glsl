#if !defined INCLUDE_MISC_END_LIGHTING_FIX
#define INCLUDE_MISC_END_LIGHTING_FIX

// Restore OptiFine End sun-direction conventions after the global conversion.

#if defined WORLD_END && !defined IS_IRIS
#define light_dir view_sun_dir
#define sun_dir view_sun_dir

uniform vec3 view_sun_dir;
#endif

#endif // INCLUDE_MISC_END_LIGHTING_FIX
