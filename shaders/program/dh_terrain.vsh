/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/dh_terrain:
  Distant Horizons terrain

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 light_levels;
out vec3 scene_pos;
out vec3 normal;
out vec3 color;

flat out uint material_mask;

// ------------
//   Distant Horizons built-ins
// ------------
// Iris injects `dhMaterialId` as a vertex attribute when Distant Horizons
// is active. We declare it here so static validation succeeds even when
// the DH injection path is not present. At runtime Iris's own declaration
// takes precedence (declarations are idempotent). Note: `flat` is not
// allowed on vertex inputs (per-vertex attributes don't interpolate), so
// we use the plain `in` qualifier.
in int dhMaterialId;

// DH material-ID enum. Iris defines these when DH support is enabled; we
// provide fallbacks so the file compiles in their absence.
#ifndef DH_BLOCK_AIR
#define DH_BLOCK_AIR 0
#endif
#ifndef DH_BLOCK_GRASS
#define DH_BLOCK_GRASS 13
#endif
#ifndef DH_BLOCK_DIRT
#define DH_BLOCK_DIRT 1
#endif
#ifndef DH_BLOCK_STONE
#define DH_BLOCK_STONE 2
#endif
#ifndef DH_BLOCK_DEEPSLATE
#define DH_BLOCK_DEEPSLATE 4
#endif
#ifndef DH_BLOCK_NETHER_STONE
#define DH_BLOCK_NETHER_STONE 3
#endif
#ifndef DH_BLOCK_SAND
#define DH_BLOCK_SAND 5
#endif
#ifndef DH_BLOCK_WOOD
#define DH_BLOCK_WOOD 6
#endif
#ifndef DH_BLOCK_METAL
#define DH_BLOCK_METAL 7
#endif
#ifndef DH_BLOCK_LAVA
#define DH_BLOCK_LAVA 8
#endif
#ifndef DH_BLOCK_ILLUMINATED
#define DH_BLOCK_ILLUMINATED 9
#endif
#ifndef DH_BLOCK_LEAVES
#define DH_BLOCK_LEAVES 10
#endif
#ifndef DH_BLOCK_WATER
#define DH_BLOCK_WATER 11
#endif
#ifndef DH_BLOCK_SNOW
#define DH_BLOCK_SNOW 12
#endif

// ------------
//   Uniforms
// ------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 dhProjection;
uniform vec3 cameraPosition;
uniform vec2 taa_offset;

void main() {
    light_levels = linear_step(
        vec2(1.0 / 32.0),
        vec2(31.0 / 32.0),
        (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy
    );
    color = gl_Color.rgb;
    normal = mat3(gbufferModelViewInverse)
        * (mat3(gl_ModelViewMatrix) * gl_Normal);

    // Set material mask based on dhMaterialId
    switch (dhMaterialId) {
        case DH_BLOCK_LEAVES:
            material_mask = 5; // Leaves
            break;

        case DH_BLOCK_GRASS:
        case DH_BLOCK_DIRT:
        case DH_BLOCK_STONE:
        case DH_BLOCK_DEEPSLATE:
        case DH_BLOCK_NETHER_STONE:
            material_mask = 6; // Dirts, stones, deepslate and netherrack
            break;

        case DH_BLOCK_SAND:
            if (color.r > color.b * 2.0) {
                material_mask = 9; // Red sand
            } else {
                material_mask = 7; // Sand
            }
            break;

        case DH_BLOCK_WOOD:
            material_mask = 10; // Woods
            break;

        case DH_BLOCK_METAL:
            material_mask = 12; // Metals
            break;

        case DH_BLOCK_LAVA:
            material_mask = 39; // Lava
            break;

        case DH_BLOCK_ILLUMINATED:
            material_mask = 36; // Other light sources
            break;

        default:
            material_mask = 0;
            break;
    }

    vec3 camera_offset = fract(cameraPosition);

    vec3 pos = gl_Vertex.xyz;
    pos = floor(pos + camera_offset + 0.5) - camera_offset;
    pos = transform(gl_ModelViewMatrix, pos);

    scene_pos = transform(gbufferModelViewInverse, pos);

    vec4 clip_pos = dhProjection * vec4(pos, 1.0);

#if defined TAA && defined TAAU
    clip_pos.xy = clip_pos.xy * taau_render_scale
        + clip_pos.w * (taau_render_scale - 1.0);
    clip_pos.xy += taa_offset * clip_pos.w;
#elif defined TAA
    clip_pos.xy += taa_offset * clip_pos.w * 0.66;
#endif

    gl_Position = clip_pos;
}
