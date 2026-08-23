/*
(included by final.fsh)

const int colortex0Format  = R11F_G11F_B10F; // full res    | vanilla sun and moon (skytextured -> d4), scene color (d4 -> temporal), bloom tiles (c5 -> c14), final color (c14 -> final)
const int colortex1Format  = RGBA16;         // full res    | gbuffer data 0 (solid -> c1), TAAU min color for AABB clipping (c3 -> c4)
const int colortex2Format  = RGBA16;         // full res    | gbuffer data 1 (solid -> c1), TAAU max color for AABB clipping (c3 -> c4)
const int colortex3Format  = RGBA8;          // full res    | OF damage overlay/enchantment glint (solid -> d4), refraction data (translucent -> c1), bloomy fog amount (c1 -> c14)
const int colortex4Format  = RGBA16F;        // 192x108     | sky map + light colors/environment irradiance (d0 -> c1)
const int colortex5Format  = RGBA16F;        // full res    | scene history (always)
const int colortex6Format  = RGBA16;         // quarter res | ambient occlusion history (always), fog transmittance (c0 -> c1 +flip) 
const int colortex7Format  = RGB16F;         // quarter res | fog scattering (always)
const int colortex8Format  = RGB8;           // 256x256     | cloud coverage map and shadow map (p0 -> c1)
const int colortex9Format  = RGBA16F;        // clouds res  | low-res clouds (d1 -> d2)
const int colortex10Format = RG16F;          // clouds res  | low-res clouds apparent distance and indirect scattering (d1 -> d2)
const int colortex11Format = RGBA16F;        // full res    | clouds history (always)
const int colortex12Format = RGB16F;         // full res    | clouds pixel age, apparent distance, indirect scattering (always)
const int colortex13Format = RGBA16F;        // full res    | rendered translucent layer (translucent -> c1)
const int colortex14Format = RG16F;          // quarter res | ambient occlusion history data (always)
const int colortex15Format = R32F;           // full res    | LoD combined depth buffer (d1 -> c2)

const bool colortex0Clear  = true;
const bool colortex1Clear  = false;
const bool colortex2Clear  = false;
const bool colortex3Clear  = true;
const bool colortex4Clear  = false;
const bool colortex5Clear  = false;
const bool colortex6Clear  = false;
const bool colortex7Clear  = false;
const bool colortex8Clear  = false;
const bool colortex9Clear  = false;
const bool colortex10Clear = false;
const bool colortex11Clear = false;
const bool colortex12Clear = false;
const bool colortex13Clear = true;
const bool colortex14Clear = false;
const bool colortex15Clear = false;

const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex13ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 shadowcolor0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

#ifdef VOXY
// Ty Cortex for the extra color textures!
const int colortex16Format = RGBA16; // Voxy water gbuffer data
const bool colortex16Clear = true;
const vec4 colortex16ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif

// RSM (reflective shadow map) single-bounce GI, quarter resolution.
// colortex17 is written twice per frame: raw gather output (deferred5 ->
// deferred6), then reused for the denoised result (deferred7 -> composite1).
// colortex18/19 are persistent temporal history buffers (flipped in
// deferred6, see shaders.properties).
#ifdef RSM_GI
const int colortex17Format = RGBA16F; // quarter res | RSM GI: raw gather (d5 -> d6), denoised GI (d7 -> c1); .a = receiver depth
const int colortex18Format = RGBA16F; // quarter res | RSM GI: temporally accumulated irradiance + receiver depth (persistent)
const int colortex19Format = RG16F;   // quarter res | RSM GI history data: 1 - depth, pixel age (persistent)

const bool colortex17Clear = false;
const bool colortex18Clear = false;
const bool colortex19Clear = false;

// Spatial reuse uses live GLSL reservoirs in a single quarter-resolution
// deferred pass. colortex21 is the scratch/output target; colortex17 remains the
// denoised RSM GI input so there is no sampler/render-target feedback loop.
const int colortex21Format = RGBA16F; // quarter res | reservoir-selected spatial-reuse output
const bool colortex21Clear = false;

// VPL data captured by the shadow pass (MRT with shadowcolor0):
//   .rgb = unscaled linear surface albedo
//   .a   = pack_unorm_2x8(encode_unit_vector(world-space normal))
const int shadowcolor1Format = RGBA16;
const vec4 shadowcolor1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif

#ifdef IBL_TEMPORAL_ACCUMULATION
// Persistent IBL diffuse history — full-res RGBA16F, not cleared.
// Stores previous-frame diffuse irradiance to allow temporal EMA
// without resampling from scratch. Full res so no scaling needed;
// reuses existing full-res history sampling (like colortex5).
const int colortex20Format = RGBA16F;
const bool colortex20Clear  = false;
#endif
*/
