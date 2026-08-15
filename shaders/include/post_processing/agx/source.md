# AgX reference

Implementation basis: `dmnsgn/glsl-tone-map/agx.glsl` (MIT), which cites the Blender/EaryChow, Filament and Three.js implementations. Luster adapts the reference to its linear Rec.2020 working space by performing the required Rec.2020 <-> linear sRGB conversions around the AgX image-formation transform.

Upstream: https://github.com/dmnsgn/glsl-tone-map/blob/main/agx.glsl
Blender/AgX source lineage: https://github.com/blender/blender/tree/main/release/datafiles/colormanagement
