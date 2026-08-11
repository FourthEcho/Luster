<br><br>

<h1 align = "center">Luster</h1>

<p align = "center">A gameplay-focused shader pack for Minecraft, forked from <a href="https://github.com/sixthsurge/photon">Photon</a> by SixthSurge — rebuilt for Iris on macOS/OpenGL 4.1 core profile</p>

![Screenshot](docs/images/rainbow.png)

## About this fork

Luster is a credited fork of Photon Shaders, adapted specifically to run well under Apple's OpenGL 4.1 compatibility constraints (no compute shaders, macOS's 16-sampler limit). On top of the macOS porting work, this fork carries a number of original systems and rewrites not present in upstream Photon:

* **Screen-space ray-marched RTAO** — a from-scratch ambient occlusion implementation, wired into the deferred AO pass, alongside GTAO and SSAO
* **GPU cubemap reflections** with temporal confidence accumulation and continuous camera-delta confidence decay, layered on top of Photon's SSR
* **Reflections/specular pipeline overhaul** — environment and sky reflections, and roughness-aware SSR, including a ported `fresnel_lazanyi_2019` conductor Fresnel term
* **SSS/porosity fallback pipeline** — falls back from labPBR maps to hardcoded per-block values when resource packs don't provide them
* **Screen-space colored block lighting** — Poisson-disk gather with temporal accumulation and glass tint recoloring, replacing the geometry-shader-based approach (Iris loads geometry shaders by file existence, so the old approach couldn't simply be disabled)
* **Full lang/UI audit** — corrected Iris-format `option.`/`value.` entries, fixed several enum display bugs, and reorganized multiple settings screens (Materials, IBL, Lighting, Reflections, Rain, Clouds)
* Numerous dead-code removals and sampler-budget fixes to stay under macOS's OpenGL 4.1 texture unit ceiling

## Installation

* Luster is built for [Iris](https://irisshaders.dev/download); OptiFine is not the target platform for this fork
* Once Iris is installed, place the downloaded zip file in your `.minecraft/shaderpacks` folder

### Downloads
* [Latest commit](https://github.com/shashankpgowda/Luster/archive/refs/heads/main.zip)

## Features

* Fully revamped sky, lighting and water
* Detailed clouds with many layers and cloud types
* Immersive weather system providing different skies each day
* Voxel-based colored lighting (enabled with Ultra profile, requires Iris)
* Screen-space reflections, GPU cubemap reflections, and screen-space ray-marched RTAO
* Volumetric fog
* Soft shadows with variable-size penumbras
* Detailed ambient occlusion (RTAO, GTAO, SSAO)
* Camera effects: bloom, depth of field, motion blur
* Much improved image quality with TAA, FXAA and CAS
* Advanced temporal upscaling (disabled by default) for low end devices
* Extensive settings menu allowing you to customize every aspect of the shader
* Full labPBR resource pack support, with hardcoded fallback values where resource packs don't provide SSS/porosity maps

## Compatibility

### GPU vendors
* Nvidia
* AMD
* Intel
* **Apple Metal (macOS)** — this is the primary target platform for this fork, running through Iris on the OpenGL 4.1 compatibility profile

### Shader loaders
* Iris - version 1.5 and above
* OptiFine is not actively supported by this fork

### Special mod support
* [Distant Horizons](https://www.curseforge.com/minecraft/mc-mods/distant-horizons)
* [Voxy](https://modrinth.com/mod/voxy)

## Known issues / in progress

* `CLOUDS_DAILY_WEATHER` is referenced in `shaders.properties` but has no GLSL implementation yet
* Rain sky flashing and cloud temporal reprojection ghosting (colortex11/12 history buffers) are known unresolved issues
* Four-mode reflection system (Off/SSR/WSR/SSR+WSR) is planned but not yet implemented

## Acknowledgments

Luster is built on top of Photon Shaders by SixthSurge. All of Photon's original acknowledgments apply to the shared codebase:

* Menu translations:
  * [NakiriRuri](https://github.com/NakiriRuri) and [OrzMiku](https://github.com/Orzmiku) - Chinese Simplified (China; Mandarin)
  * [ChunghwaMC](https://github.com/ChunghwaMC) - Chinese Traditional (Taiwan; Mandarin)
  * [Jmayk](https://github.com/Jmayk-dev) - Italian
  * [Timtaran](https://github.com/Timtaran) - Russian
  * [shihyeon](https://github.com/shihyeon) - Korean
  * [DVRKHz](https://github.com/DVRKHz) - Spanish
  * [Patatagod69](https://github.com/PatataNL) - Dutch
  * sincerity - Estonian
* [Emin](https://github.com/EminGT) - Shadow bias method from [Complementary Reimagined](https://www.complementary.dev/shaders/) (fully fixes peter panning and light leaking underground!)
* [DrDesten](https://github.com/DrDesten) - Depth tolerance calculation for SSR (helps to prevent false reflections)
* [Jessie](https://github.com/Jessie-LC) - f0 and f82 values for labPBR hardcoded metals
* [Sledgehammer Games](https://www.sledgehammergames.com/) - Bloom downsampling method used in Call of Duty Advanced Warfare (described [here](http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare))
* http://momentsingrapics.de/ - Blue noise texture
* [NASA Scientific Visualization Studio](https://svs.gsfc.nasa.gov/4851) - Galaxy image

## Original Photon showcase videos

<div align = "center">
	<a href="http://www.youtube.com/watch?feature=player_embedded&v=vxE_CVeU8Rs" target="_blank"><img src="http://img.youtube.com/vi/vxE_CVeU8Rs/0.jpg" border="0"/></a>
	<p> by iambeen
	<br><br>
</div>

<div align = "center">
	<a href="http://www.youtube.com/watch?feature=player_embedded&v=gMLFZMBK-ZQ" target="_blank"><img src="http://img.youtube.com/vi/gMLFZMBK-ZQ/0.jpg" border="0"/></a>
	<p> by CosmicNexus
	<br><br>
</div>

<div align = "center">
	<a href="http://www.youtube.com/watch?feature=player_embedded&v=_aSmM7jg9Nw" target="_blank"><img src="http://img.youtube.com/vi/_aSmM7jg9Nw/0.jpg" border="0"/></a>
	<p> by VIPUL
	<br><br>
</div>

## Community

This is a personal fork maintained by [shashankpgowda](https://github.com/shashankpgowda). For questions or issues specific to this fork, please open an issue on this repository.

For the original Photon Shaders project, see [sixthsurge/photon](https://github.com/sixthsurge/photon) and their [Discord server](https://discord.gg/ngEW66HScd).
