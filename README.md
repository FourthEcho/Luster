<div align="center">

# Luster

**A cinematic, gameplay-focused shader pack for Minecraft**
Atmosphere · lighting · clouds · water · image quality — built with Iris and macOS/Apple Silicon in mind.

[![Iris](https://img.shields.io/badge/loader-Iris-6b5ce7?style=flat-square)](https://irisshaders.dev/)
[![License](https://img.shields.io/badge/license-see%20LICENSE-blue?style=flat-square)](./LICENSE)
[![Discord](https://discord.com/channels/1543406509000491098/1543406509923377247)

[Download](#installation) · [Features](#features) · [Compatibility](#compatibility) · [Configuration](#configuration) · [Issues](https://github.com/shashankpgowda/Luster/issues)

<img src="docs/images/scenery.png" alt="Luster shader pack screenshot" width="800">

</div>

---

## About

(WIP) Luster is a heavily reworked shader pack built on the [Photon](https://github.com/sixthsurge/photon) codebase by SixthSurge. It's designed around modular rendering systems rather than a single visual gimmick — dynamic atmosphere, layered volumetric clouds, configurable lighting and reflections, detailed water, labPBR material support, temporal reconstruction, and a full post-processing stack — all exposed through Iris' in-game settings menu.

## Features

* Dynamic Rayleigh, Mie, ozone, and mist-based atmosphere
* Biome- and weather-aware sky colors
* Aurora, stars, galaxy, rainbows, god rays, and advanced mist shading
* Multiple detailed volumetric cloud types including Cumulus, AltoCumulus, Cumulus Congestus, Cirrus, Cirrocumulus, and noctilucent clouds
* Independently configurable cloud layers with temporal upscaling
* Sun, moon, block, Nether, and End lighting
* Screen Space Path Tracing
* Directional Ambient Lighting
* Multiple shadow rendering paths including PCF and screen-space shadows
* Detailed ambient occlusion(GTAO)
* Physically-inspired water absorption and scattering
* Procedural water waves and biome-colored water
* Parallax mapping and POM
* Water caustics and Snell's window
* Rain puddles and subsurface scattering
* Full labPBR material support
* Environment, sky, and screen-space reflections
* Roughness-aware reflections for water and other materials
* Full atmospheric fog with biome-aware rendering
* Colored volumetric light shafts
* Cave, border, Nether, and End fog
* TAA, FXAA, and CAS
* Temporal upscaling with TAAU
* Purkinje shift
* ACES and AGX tonemapping
* Full color grading controls
* Bloom
* Depth of field
* Motion blur
* Vignette
* Multiple exposure modes
* Lens flare
* Extensive in-game configuration through Iris' shader settings
* Low, Medium, High, Ultra profiles
* Distant Horizons and Voxy compatibility

Not every feature is enabled on every profile — the in-game settings menu is the source of truth for what's available on your hardware and shader loader.

## Profiles

| Profile | Focus |
|---|---|
| **Low** | Reduced-cost rendering for lower-end hardware |
| **Medium** | Balanced quality and performance |
| **High** | Higher-quality shadows, reflections, clouds, AO, and lighting |
| **Ultra** | Maximum available quality and sampling |

## Installation

1. Install [Iris](https://irisshaders.dev/) for your Minecraft version — Luster does **not** support OptiFine.
2. [Download the latest Luster archive](#).
3. Drop the `.zip` into `.minecraft/shaderpacks`.
4. In Minecraft: **Video Settings → Shader Packs → Luster**.
5. Start on **Medium**, or **High** depending on your hardware, then tune from there.

## Compatibility

**GPU vendors:** Nvidia · AMD · Intel · Apple Silicon 

**Shader loader:** Iris only

**Mod support:** [Distant Horizons](https://www.curseforge.com/minecraft/mc-mods/distant-horizons) · [Voxy](https://modrinth.com/mod/voxy)

Some features are conditional on shader loader, Minecraft version, GPU, and selected profile.

## Configuration

Settings are organized into: **World** · **Lighting** · **Atmospherics and Fog** · **Materials** · **Post-Processing** · **Camera** · **Misc**.

## Development

Luster is actively developed. The source tree is organized into reusable modules under `shaders/include/`, rendering programs under `shaders/program/`, and world-specific passes under the `world*` directories. Bug reports and Luster-specific issues go in the [issue tracker](https://github.com/shashankpgowda/Luster/issues). 

## Acknowledgements

Luster is built on substantially reworked code from [Photon](https://github.com/sixthsurge/photon) by SixthSurge. Original Photon credits and licenses are retained in the project.

See the included `LICENSE` files for full attribution and licensing terms.

## Community

Luster is a personal shader pack project maintained by [FourthEcho](https://github.com/FourthEcho).

- [Issues](https://github.com/shashankpgowda/Luster/issues)
- [Luster Discord](https://discord.gg/Q9n4WMVSK)
- [Upstream: Photon](https://github.com/sixthsurge/photon)

<div align="center">
<sub>Luster · Minecraft Shader Pack</sub>
</div>
