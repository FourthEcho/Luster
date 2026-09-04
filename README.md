<div align="center">

# Luster

**A cinematic, gameplay-focused shader pack for Minecraft**
Atmosphere · lighting · clouds · water · image quality — built with Iris and macOS/Apple Silicon in mind.

[![Iris](https://img.shields.io/badge/loader-Iris-6b5ce7?style=flat-square)](https://irisshaders.dev/)
[![License](https://img.shields.io/badge/license-see%20LICENSE-blue?style=flat-square)](./LICENSE)
[![Discord](https://img.shields.io/badge/discord-Photon%20community-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/ngEW66HScd)

[Download](#installation) · [Features](#features) · [Compatibility](#compatibility) · [Configuration](#configuration) · [Issues](https://github.com/shashankpgowda/Luster/issues)

<img src="docs/images/scenery.png" alt="Luster shader pack screenshot" width="800">

</div>

---

## About

Luster is a heavily reworked shader pack built on the [Photon](https://github.com/sixthsurge/photon) codebase by SixthSurge. It's designed around modular rendering systems rather than a single visual gimmick — dynamic atmosphere, layered volumetric clouds, configurable lighting and reflections, detailed water, labPBR material support, temporal reconstruction, and a full post-processing stack — all exposed through Iris' in-game settings menu.

A dedicated **Mac Compatible** profile makes Luster one of the few shader packs built to actually run well on Apple Silicon through Iris' OpenGL 4.1 compatibility path.

## Features

- **Lighting** — sun/moon/block/Nether/End lighting, optional voxel-based colored lighting, Directional Ambient Lighting, RSM for Sun Bounce GI, multiple shadow paths (PCF + screen-space), SSAO/GTAO
- **Sky & atmosphere** — dynamic Rayleigh/Mie scattering, biome and weather-aware color, aurora, stars, galaxy, rainbows, god rays, and advanced Mist shading.
- **Clouds** — Cumulus, AltoCumulus, Cumulus Congestus, Cirrus/Cirrocumulus, noctilucent, and optional blocky clouds, independently tunable per layer, with up to 16× temporal upscaling
- **Water & materials** — physically-inspired absorption/scattering, procedural waves, parallax, caustics, Snell's window, biome-colored water, rain puddles, POM, subsurface scattering, full labPBR support
- **Reflections** — environment, sky, and screen-space reflections, roughness-aware, tuned separately for water and other materials
- **Fog & volumetrics** — full atmospheric fog per biome, colored volumetric light shafts, cave/border fog, dedicated Nether and End fog paths
- **Post-processing** — TAA/FXAA/CAS, TAAU, bloom, DOF, motion blur, vignette, Purkinje shift, multiple exposure modes, ACES and AGX tonemapping, full color grading

Not every feature is enabled on every profile — the in-game settings menu is the source of truth for what's available on your hardware and shader loader.

## Profiles

| Profile | Focus |
|---|---|
| **Low** | Reduced-cost rendering for lower-end hardware |
| **Medium** | Balanced quality and performance |
| **High** | Higher-quality shadows, reflections, clouds, AO, and lighting |
| **Ultra** | Maximum available quality and sampling |
| **Mac Compatible** | Conservative feature set tuned for macOS / Apple Silicon |

*Mac Compatible* disables the more hardware- or platform-sensitive features while keeping the core lighting, atmosphere, water, reflection, shadow, cloud, and post-processing pipeline intact.

## Installation

1. Install [Iris](https://irisshaders.dev/) for your Minecraft version — Luster does **not** support OptiFine.
2. [Download the latest Luster archive](#).
3. Drop the `.zip` into `.minecraft/shaderpacks`.
4. In Minecraft: **Video Settings → Shader Packs → Luster**.
5. Start on **Mac Compatible**, **Medium**, or **High** depending on your hardware, then tune from there.

## Compatibility

**GPU vendors:** Nvidia · AMD · Intel · Apple Silicon (via Iris' OpenGL compatibility path)

**Shader loader:** Iris only

**Mod support:** [Distant Horizons](https://www.curseforge.com/minecraft/mc-mods/distant-horizons) · [Voxy](https://modrinth.com/mod/voxy)

Some features are conditional on shader loader, Minecraft version, GPU, and selected profile.

## Configuration

Settings are organized into: **World** (weather, moon phase, foliage) · **Lighting** (colored lights, IBL, shadows, AO) · **Sky** (atmosphere, clouds, stars, aurora) · **Fog** (scattering, volumetrics, biome variants) · **Materials** (PBR, POM, SSS, reflections) · **Water** (waves, caustics, puddles) · **Post-Processing** (exposure, AA, bloom, grading) · **Misc** and **Mods**.

## Development

Luster is actively developed. The source tree is organized into reusable modules under `shaders/include/`, rendering programs under `shaders/program/`, and world-specific passes under the `world*` directories. Bug reports and Luster-specific issues go in the [issue tracker](https://github.com/shashankpgowda/Luster/issues). Colored Lights is NOT mac supporte yet.

## Acknowledgements

Luster is built on substantially reworked code from [Photon](https://github.com/sixthsurge/photon) by SixthSurge. Original Photon credits and licenses are retained in the project.

- Menu translations: **NakiriRuri** & **OrzMiku** (Chinese, Simplified) · **ChunghwaMC** (Chinese, Traditional) · **Jmayk** (Italian) · **Timtaran** (Russian) · **shihyeon** (Korean) · **DVRKHz** (Spanish) · **Patatagod69** (Dutch) · **sincerity** (Estonian)
- **Emin** — shadow bias method from Complementary Reimagined
- **DrDesten** — depth tolerance calculation for SSR
- **Jessie** — f0/f82 values for labPBR hardcoded metals
- **Sledgehammer Games** — bloom downsampling technique from *Call of Duty: Advanced Warfare*
- [momentsingraphics.de](https://momentsingraphics.de/) — blue noise texture
- **NASA Scientific Visualization Studio** — galaxy image

See the included `LICENSE` files for full attribution and licensing terms.

## Community

Luster is a personal shader pack project maintained by [FourthEcho](https://github.com/FourthEcho).

- [Issues](https://github.com/shashankpgowda/Luster/issues)
- [Luster Discord](https://discord.gg/Q9n4WMVSK)
- [Upstream: Photon](https://github.com/sixthsurge/photon)

<div align="center">
<sub>Luster · Minecraft Shader Pack</sub>
</div>
