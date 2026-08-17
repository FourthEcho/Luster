/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/voxel_propagate_from_19:
  Voxel colored lights — Phase 3 (propagation), read colortex19 -> write colortex20

  Reads 6-axis neighbors from the source atlas and propagates light outward
  with per-step attenuation.  Each invocation of this program represents one
  floodfill iteration.

  This is the "from 19" variant: source = colortex19, dest = colortex20.
  The matching "from 20" variant (voxel_propagate_from_20.fsh) does the
  reverse, enabling ping-pong across multiple propagation steps:
    deferred8  (voxelize)        : scatter into colortex19
    deferred9  (propagate 19->20): step 0, result in colortex20
    deferred10 (propagate 20->19): step 1, result in colortex19
    deferred11 (propagate 19->20): step 2, result in colortex20
    ...
  The final result ends up in colortex19 if VOXEL_LIGHT_PROPAGATION_STEPS is
  even, colortex20 if odd (see atlas.glsl's VOXEL_LIGHT_FINAL_ATLAS macro).

  Occlusion: prototype uses NO occlusion (light propagates freely through
  solid blocks).  This is the cheapest option and is fine for early
  prototyping.  A future iteration can sample shadowtex0 / shadowcolor0 to
  test whether a voxel is inside a solid block and zero out its contribution.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 atlas_out;
/* RENDERTARGETS: 20 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

// cameraPosition is needed by get_voxel_grid_origin() in atlas.glsl
// (used to center the voxel grid on the player).
uniform vec3 cameraPosition;

// colortex19 (source) and voxel_grid_origin are declared by
// include/lighting/voxel/atlas.glsl, which we include below.

// ------------
//   Includes
// ------------

#include "/include/lighting/voxel/atlas.glsl"

// Per-step attenuation.  Each propagation step multiplies the propagated
// radiance by this factor, so light decays exponentially with distance from
// its source.  0.5 gives a soft ~7-voxel radius at 8 steps; raise for
// tighter falloff, lower for farther reach.
#ifndef VOXEL_LIGHT_PROPAGATION_ATTENUATION
#define VOXEL_LIGHT_PROPAGATION_ATTENUATION 0.5
#endif

// Fraction of the neighbour's radiance that propagates INTO the current
// voxel per step.  Conceptually: 1/6 of each neighbor's "outflow" lands in
// the current voxel (since light spreads uniformly to 6 neighbors).  We
// fold this into the attenuation above.
// Per-step propagation factor.  Each neighbour contributes this fraction
// of its radiance to the current voxel.  With 0.5, light at distance 1 is
// 50% of source, distance 2 is 25%, distance 3 is 12.5% — visible and
// falls off naturally.  We do NOT divide by 6 (the number of neighbours)
// because that makes the propagation too dim to see.
const float PROPAGATION_FACTOR = VOXEL_LIGHT_PROPAGATION_ATTENUATION;

void main() {
    // Convert gl_FragCoord (in atlas texel coords) to voxel coordinate.
    vec2 atlas_uv = gl_FragCoord.xy * rcp(vec2(float(VOXEL_ATLAS_WIDTH),
                                                float(VOXEL_ATLAS_HEIGHT)));
    vec3 atlas_world = atlas_uv_to_world(atlas_uv);
    vec3 voxel_coord = world_to_voxel_coord(atlas_world);
    ivec3 ivoxel = ivec3(floor(voxel_coord));

    // Reject fragments outside the grid (shouldn't happen since the atlas
    // is sized to the grid, but guard anyway).
    if (any(lessThan(ivoxel, ivec3(0)))
     || any(greaterThanEqual(ivoxel, ivec3(VOXEL_GRID_DIM_X,
                                            VOXEL_GRID_DIM_Y,
                                            VOXEL_GRID_DIM_Z)))) {
        atlas_out = vec4(0.0);
        return;
    }

    // Sample the 6 face-neighbors.  Each neighbor lives in either the same
    // Z-slice or an adjacent one (for +Z / -Z).  We sample via continuous
    // atlas UV using voxel_coord_to_atlas_uv() so wrap-around across tile
    // boundaries is handled correctly.

    // Current voxel's value (preserved — emitter radiance should persist
    // across propagation steps so light sources stay bright).
    vec3 here = texture(colortex19,
        voxel_coord_to_atlas_uv(vec3(ivoxel), ivoxel.z)).rgb;

    // Neighbours in +X, -X, +Y, -Y, +Z, -Z.  Each is wrapped via the atlas
    // layout function (Z wrap-around handled by voxel_coord_to_atlas_uv).
    vec3 neighbor_sum = vec3(0.0);

    // +X
    {
        ivec3 n = ivec3(ivoxel.x + 1, ivoxel.y, ivoxel.z);
        if (n.x < VOXEL_GRID_DIM_X) {
            neighbor_sum += texture(colortex19,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    // -X
    {
        ivec3 n = ivec3(ivoxel.x - 1, ivoxel.y, ivoxel.z);
        if (n.x >= 0) {
            neighbor_sum += texture(colortex19,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    // +Y
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y + 1, ivoxel.z);
        if (n.y < VOXEL_GRID_DIM_Y) {
            neighbor_sum += texture(colortex19,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    // -Y
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y - 1, ivoxel.z);
        if (n.y >= 0) {
            neighbor_sum += texture(colortex19,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    // +Z (wraps around to next slice)
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y, ivoxel.z + 1);
        if (n.z < VOXEL_GRID_DIM_Z) {
            neighbor_sum += texture(colortex19,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    // -Z (wraps around to previous slice)
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y, ivoxel.z - 1);
        if (n.z >= 0) {
            neighbor_sum += texture(colortex19,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }

    vec3 propagated = neighbor_sum * PROPAGATION_FACTOR;

    // Use max() instead of addition.  This prevents the exponential
    // accumulation that was causing the light to grow into a diffuse
    // blob over multiple propagation steps.  With max():
    //   - Emitter voxels keep their full radiance (here > propagated)
    //   - Non-emitter voxels receive only the propagated term
    //   - No double-counting of energy across steps
    atlas_out = vec4(max(here, propagated), 1.0);
}
