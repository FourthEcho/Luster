#if !defined INCLUDE_LIGHTING_VOXEL_ATLAS
#define INCLUDE_LIGHTING_VOXEL_ATLAS

/*
  ============================================================================
  Voxel colored-light atlas
  ----------------------------------------------------------------------------
  A clipmap centered on the player.  The grid is 128 x 64 x 128 voxels
  (X by Y by Z), each voxel covering VOXEL_LIGHT_VOXEL_SIZE world blocks
  (default 1.0; raising it to 2.0 halves the atlas cost at the expense of
  blurrier light).

  The volume is stored as a 2D texture atlas rather than a real sampler3D
  because we write to it via rasterization (rasterization writes to 2D
  framebuffer attachments, not 3D images).  Z-slices are tiled into a grid:
  16 columns x 8 rows = 128 tiles, each tile being 128 x 64 texels.
  Final atlas dimensions: 2048 x 512.

  Re-centering: rather than tracking the player every frame (which would make
  the whole volume visibly swim when the player moves slowly), the grid origin
  is snapped to voxel-size increments.  The re-snap is triggered only when the
  player crosses VOXEL_LIGHT_RESNAP_THRESHOLD voxels worth of distance.  This
  is implemented via a host-side uniform (voxel_grid_origin) that Iris updates
  through a custom uniform expression in shaders.properties.

  Sampling: trilinear interpolation across the Z axis is approximated by
  sampling the two neighboring Z-slices and lerping.  Hardware bilinear
  filtering handles the within-slice XY interpolation.
  ============================================================================
*/

// --- Grid dimensions --------------------------------------------------------

const int   VOXEL_GRID_DIM_X       = 128;
const int   VOXEL_GRID_DIM_Y       = 64;
const int   VOXEL_GRID_DIM_Z       = 128;

const int   VOXEL_ATLAS_TILE_COLS  = 16; // tiles per atlas row
const int   VOXEL_ATLAS_TILE_ROWS  = 8;  // tiles per atlas column  (16*8 = 128 Z-slices)

const int   VOXEL_ATLAS_WIDTH      = VOXEL_ATLAS_TILE_COLS * VOXEL_GRID_DIM_X; // 2048
const int   VOXEL_ATLAS_HEIGHT     = VOXEL_ATLAS_TILE_ROWS * VOXEL_GRID_DIM_Y; // 512

// World-space size of one voxel.  Tunable perf knob: doubling this halves
// effective resolution but quarters the propagation cost.  Defined in
// settings.glsl so the user can adjust it.
#ifndef VOXEL_LIGHT_VOXEL_SIZE
#define VOXEL_LIGHT_VOXEL_SIZE 1.0
#endif

// Player must move this many voxels before the grid re-snaps.  Larger = less
// swimming but more stale voxels while moving.
#ifndef VOXEL_LIGHT_RESNAP_THRESHOLD
#define VOXEL_LIGHT_RESNAP_THRESHOLD 8
#endif

// Half-extent of the grid in world blocks (so the grid covers [-half, +half)
// around voxel_grid_origin + grid_half).
const float VOXEL_GRID_HALF_X = 0.5 * float(VOXEL_GRID_DIM_X) * VOXEL_LIGHT_VOXEL_SIZE;
const float VOXEL_GRID_HALF_Y = 0.5 * float(VOXEL_GRID_DIM_Y) * VOXEL_LIGHT_VOXEL_SIZE;
const float VOXEL_GRID_HALF_Z = 0.5 * float(VOXEL_GRID_DIM_Z) * VOXEL_LIGHT_VOXEL_SIZE;

// cameraPosition is a standard Iris uniform declared by every host program
// that uses world-space coordinates (voxelize.fsh, c0_vl.fsh, d4, gbuffers,
// etc.).  We do NOT redeclare it here to avoid "redefinition" errors in
// glslang — the host program's declaration is sufficient.

// Compute the world-space corner of voxel (0, 0, 0).  The grid is centered
// on the player and snaps to voxel-size multiples of VOXEL_LIGHT_RESNAP_THRESHOLD
// to prevent the volume from swimming when the player moves slowly.
//
// NB: This was previously a custom uniform in shaders.properties, but Iris's
// custom uniform expression parser doesn't support floor() — so we compute
// it here in GLSL instead, where floor() IS available.
vec3 get_voxel_grid_origin() {
    float snap = VOXEL_LIGHT_VOXEL_SIZE * float(VOXEL_LIGHT_RESNAP_THRESHOLD);
    vec3 snapped = floor(cameraPosition / snap) * snap;
    return snapped - vec3(VOXEL_GRID_HALF_X, VOXEL_GRID_HALF_Y, VOXEL_GRID_HALF_Z);
}

// Convenience macro so existing code that references voxel_grid_origin
// continues to work.  Evaluated once per call site.
#define voxel_grid_origin (get_voxel_grid_origin())

// --- World -> atlas coordinate transforms -----------------------------------

// Convert a continuous voxel coordinate (i.e. world position relative to the
// grid origin, scaled by 1/voxel_size) to the atlas UV for a given integer
// Z slice.  Wrap-around in X and Y is intentionally NOT applied: positions
// outside [0, DIM) should fall off the edge of the atlas, which is the
// desired behavior (the propagation pass will simply not light them).
vec2 voxel_coord_to_atlas_uv(vec3 voxel_coord, int z_slice) {
    int slice = z_slice % VOXEL_GRID_DIM_Z;
    if (slice < 0) slice += VOXEL_GRID_DIM_Z;

    int col = slice % VOXEL_ATLAS_TILE_COLS;
    int row = slice / VOXEL_ATLAS_TILE_COLS;

    vec2 tile_offset = vec2(float(col) * float(VOXEL_GRID_DIM_X),
                            float(row) * float(VOXEL_GRID_DIM_Y));

    vec2 texel_pos = voxel_coord.xy + 0.5;

    return (tile_offset + texel_pos)
         / vec2(float(VOXEL_ATLAS_WIDTH), float(VOXEL_ATLAS_HEIGHT));
}

// Convert a world-space position to a continuous voxel coordinate relative
// to the current grid origin.  Caller is responsible for bounds-checking.
vec3 world_to_voxel_coord(vec3 world_pos) {
    return (world_pos - voxel_grid_origin) / VOXEL_LIGHT_VOXEL_SIZE;
}

// Convert an atlas UV (from a fragment shader writing into the atlas) back
// to world space.  Used by debug overlays and the voxelize pass for emitter
// culling.
vec3 atlas_uv_to_world(vec2 atlas_uv) {
    vec2 texel_pos = atlas_uv * vec2(float(VOXEL_ATLAS_WIDTH),
                                     float(VOXEL_ATLAS_HEIGHT));

    int col = int(floor(texel_pos.x / float(VOXEL_GRID_DIM_X)));
    int row = int(floor(texel_pos.y / float(VOXEL_GRID_DIM_Y)));

    vec2 in_tile = vec2(
        texel_pos.x - float(col) * float(VOXEL_GRID_DIM_X),
        texel_pos.y - float(row) * float(VOXEL_GRID_DIM_Y)
    );

    int slice = row * VOXEL_ATLAS_TILE_COLS + col;

    return voxel_grid_origin
         + vec3(in_tile.x, in_tile.y, float(slice)) * VOXEL_LIGHT_VOXEL_SIZE;
}

// Returns true if the world position is inside the voxel grid bounds.
bool is_inside_voxel_grid(vec3 world_pos) {
    vec3 local = world_pos - voxel_grid_origin;
    return all(greaterThanEqual(local, vec3(0.0)))
        && all(lessThan(local, vec3(
               float(VOXEL_GRID_DIM_X) * VOXEL_LIGHT_VOXEL_SIZE,
               float(VOXEL_GRID_DIM_Y) * VOXEL_LIGHT_VOXEL_SIZE,
               float(VOXEL_GRID_DIM_Z) * VOXEL_LIGHT_VOXEL_SIZE)));
}

// --- Atlas sampling ---------------------------------------------------------

// Samplers for the two ping-pong atlas textures.  These are declared here so
// every program that includes this file gets them; unused declarations are
// harmless (the GLSL linker will drop them if no read is performed).
uniform sampler2D colortex19;  // voxel atlas A
uniform sampler2D colortex20;  // voxel atlas B

// Trilinear sample of a voxel atlas at a world-space point.  Bilinear
// filtering handles within-slice XY interpolation; we manually blend the
// two neighboring Z slices.
vec3 sample_voxel_atlas_trilinear(sampler2D atlas, vec3 world_pos) {
    vec3 voxel_coord = world_to_voxel_coord(world_pos);

    float z_f = voxel_coord.z;
    int   z_i = int(floor(z_f));
    float z_frac = z_f - float(z_i);

    vec2 uv0 = voxel_coord_to_atlas_uv(voxel_coord, z_i);
    vec2 uv1 = voxel_coord_to_atlas_uv(voxel_coord, z_i + 1);

    vec3 s0 = texture(atlas, uv0).rgb;
    vec3 s1 = texture(atlas, uv1).rgb;

    return mix(s0, s1, z_frac);
}

// Final, ready-to-use voxel light color at a world-space point.
// Returns (color * intensity) propagated through the voxel grid, or vec3(0)
// if the point is outside the grid.
//
// After the propagation chain:
//   voxelize (deferred8)   -> colortex19
//   propagate step 0 (d9)  -> colortex20  (reads colortex19)
//   propagate step 1 (d10) -> colortex19  (reads colortex20)
//   propagate step 2 (d11) -> colortex20  (reads colortex19)
//   ...
// The final result depends on whether VOXEL_LIGHT_PROPAGATION_STEPS is odd
// or even.  This function picks the right buffer automatically.
#if (VOXEL_LIGHT_PROPAGATION_STEPS % 2) == 0
#define VOXEL_LIGHT_FINAL_ATLAS colortex19
#else
#define VOXEL_LIGHT_FINAL_ATLAS colortex20
#endif

vec3 get_voxel_light_color(vec3 world_pos) {
    if (!is_inside_voxel_grid(world_pos)) {
        return vec3(0.0);
    }
    return sample_voxel_atlas_trilinear(VOXEL_LIGHT_FINAL_ATLAS, world_pos);
}

#endif // INCLUDE_LIGHTING_VOXEL_ATLAS
