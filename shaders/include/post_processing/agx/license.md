# AGX License

## Primary Implementation: bWFuanVzYWth/AgX (Minimal AgX in GLSL, WITHOUT LUT)

- Source: https://github.com/bWFuanVzYWth/AgX
- License: MIT (as per upstream, 2024 Ralle321)
- Files derived: `agx.glsl` core sigmoid `agx_curve3` + inset/outset matrices

## Additional References (MIT)

- EaryChow/AgX_LUT_Gen (Blender AgX LUT generation) — https://github.com/EaryChow/AgX_LUT_Gen — used by Blender 4.0+, port via Allen Pestaluky `earychow-agx-simplified.glsl` (MIT-compatible) for log-space formulation
- Google Filament `ToneMapper.cpp` AgX — https://github.com/google/filament/blob/main/filament/src/ToneMapper.cpp — Apache 2.0, matrices adapted
- Three.js `tonemapping_pars_fragment.glsl.js` AgX — https://github.com/mrdoob/three.js/blob/dev/src/renderers/shaders/ShaderChunk/tonemapping_pars_fragment.glsl.js — MIT, AgXInsetMatrix/AgXOutsetMatrix values
- dmnsgn/glsl-tone-map `agx.glsl` — https://github.com/dmnsgn/glsl-tone-map/blob/main/agx.glsl — MIT, glue and `agxGolden`/`agxPunchy` presets
- Godot `servers/rendering/renderer_rd/shaders/effects/tonemap.glsl` — https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/effects/tonemap.glsl — MIT, `tonemap_agx` log formulation

This compilation is provided under MIT. See each upstream repository for full license text.

## MIT License Text (bWFuanVzYWth/AgX, glsl-tone-map, three.js, Godot portions)

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
