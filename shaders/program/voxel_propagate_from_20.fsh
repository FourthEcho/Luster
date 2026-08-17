/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/voxel_propagate_from_20:
  Voxel colored lights — Phase 3 (propagation), read colortex20 -> write colortex19

  Mirror of voxel_propagate_from_19.fsh with source and destination swapped.

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 atlas_out;
/* RENDERTARGETS: 19 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

// cameraPosition is needed by get_voxel_grid_origin() in atlas.glsl
// (used to center the voxel grid on the player).
uniform vec3 cameraPosition;

// colortex20 (source) and voxel_grid_origin are declared by
// include/lighting/voxel/atlas.glsl, which we include below.

// ------------
//   Includes
// ------------

#include "/include/lighting/voxel/atlas.glsl"

#ifndef VOXEL_LIGHT_PROPAGATION_ATTENUATION
#define VOXEL_LIGHT_PROPAGATION_ATTENUATION 0.5
#endif

const float PROPAGATION_FACTOR = VOXEL_LIGHT_PROPAGATION_ATTENUATION;

void main() {
    vec2 atlas_uv = gl_FragCoord.xy * rcp(vec2(float(VOXEL_ATLAS_WIDTH),
                                                float(VOXEL_ATLAS_HEIGHT)));
    vec3 atlas_world = atlas_uv_to_world(atlas_uv);
    vec3 voxel_coord = world_to_voxel_coord(atlas_world);
    ivec3 ivoxel = ivec3(floor(voxel_coord));

    if (any(lessThan(ivoxel, ivec3(0)))
     || any(greaterThanEqual(ivoxel, ivec3(VOXEL_GRID_DIM_X,
                                            VOXEL_GRID_DIM_Y,
                                            VOXEL_GRID_DIM_Z)))) {
        atlas_out = vec4(0.0);
        return;
    }

    vec3 here = texture(colortex20,
        voxel_coord_to_atlas_uv(vec3(ivoxel), ivoxel.z)).rgb;

    vec3 neighbor_sum = vec3(0.0);

    {
        ivec3 n = ivec3(ivoxel.x + 1, ivoxel.y, ivoxel.z);
        if (n.x < VOXEL_GRID_DIM_X) {
            neighbor_sum += texture(colortex20,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    {
        ivec3 n = ivec3(ivoxel.x - 1, ivoxel.y, ivoxel.z);
        if (n.x >= 0) {
            neighbor_sum += texture(colortex20,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y + 1, ivoxel.z);
        if (n.y < VOXEL_GRID_DIM_Y) {
            neighbor_sum += texture(colortex20,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y - 1, ivoxel.z);
        if (n.y >= 0) {
            neighbor_sum += texture(colortex20,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y, ivoxel.z + 1);
        if (n.z < VOXEL_GRID_DIM_Z) {
            neighbor_sum += texture(colortex20,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }
    {
        ivec3 n = ivec3(ivoxel.x, ivoxel.y, ivoxel.z - 1);
        if (n.z >= 0) {
            neighbor_sum += texture(colortex20,
                voxel_coord_to_atlas_uv(vec3(n), n.z)).rgb;
        }
    }

    vec3 propagated = neighbor_sum * PROPAGATION_FACTOR;

    // Use max() instead of addition.  This prevents the exponential
    // accumulation that was causing the light to grow into a diffuse
    // blob over multiple propagation steps.
    atlas_out = vec4(max(here, propagated), 1.0);
}
