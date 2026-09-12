#if !defined INCLUDE_POST_PROCESSING_REINHARD
#define INCLUDE_POST_PROCESSING_REINHARD

vec3 tonemap_reinhard(vec3 rgb) { return rgb / (rgb + 1.0); }

#endif // INCLUDE_POST_PROCESSING_REINHARD
