<br>

<h1 align="center">Luster</h1>

<p align="center">
  A cinematic, gameplay-focused shader pack for Minecraft with a strong emphasis on atmosphere, lighting, clouds, water, and image quality.<br>
  Designed with macOS / Apple Silicon and Iris compatibility in mind.
</p>

<p align="center">
  <a href="https://irisshaders.dev/">Iris</a> ·
  <a href="https://github.com/shashankpgowda/Luster">Source</a> ·
  <a href="https://github.com/shashankpgowda/Luster/issues">Issues</a>
</p>

<p align="center">
  <img src="docs/images/rainbow.png" alt="Luster shader pack screenshot">
</p>

About

Luster is a heavily reworked shader pack based on the Photon codebase by SixthSurge. It focuses on a polished Minecraft presentation while retaining a large amount of user control through Iris' shader settings system.

The pack is built around modular rendering systems rather than a single visual gimmick: dynamic atmosphere and weather, layered volumetric clouds, configurable lighting and reflections, detailed water, material support, temporal reconstruction, and a broad post-processing stack.

Luster also includes a dedicated Mac Compatible profile for systems using Iris on macOS.

Highlights

Lighting

Configurable sun, moon, block-light, Nether, End, and handheld lighting

Optional colored lighting with a voxel-based light volume

Image-Based Lighting (IBL) for diffuse and specular environment illumination

Temporal accumulation for IBL

Configurable cloud lighting and volumetric light propagation

Multiple shadow paths, including PCF and screen-space shadow tracing

Pixelated shadow controls, entity shadows, block-entity shadows, and cloud shadows

SSAO and GTAO ambient occlusion

Independent moon-phase influence for night lighting, atmosphere, and reflections

Sky & Atmosphere

Dynamic atmospheric scattering with configurable Rayleigh and Mie parameters

Biome/weather-aware atmospheric color controls

Dynamic weather variation

Aurora effects

Sun and moon rendering controls, including angular radius

Stars and galaxy controls

Rainbows and End-specific sun effects

Crepuscular / god-ray lighting

Clouds

Multiple cloud families can be mixed and tuned independently:

Cumulus

AltoCumulus

Cumulus Congestus

Cirrus / Cirrocumulus

Noctilucent clouds

Optional Minecraft-style Blocky Clouds

Cloud rendering includes per-layer density, coverage, altitude, thickness, detail, wind, lighting, ambient steps, and other controls. Cloud rendering also has temporal upscaling up to 16× plus aerial-perspective and cloud-lighting controls.

Water & Materials

Physically-inspired water absorption and scattering controls

Water waves with configurable procedural displacement

Water parallax options

Water caustics

Edge highlights

Snell's window

Biome-colored water

Refraction

Rain puddles, including an Everywhere mode

Directional lightmaps

Parallax Occlusion Mapping (POM)

Subsurface scattering and sheen controls

Porosity controls

labPBR material support

Anisotropic filtering options

Reflections

Environment reflections

Sky reflections

Screen-space reflections with configurable ray count and intersection/refinement steps

Roughness-aware reflection support

Separate reflection controls for water and other materials

Fog & Volumetrics

Overworld atmospheric fog

Rayleigh and Mie scattering controls

Rain, arid, snowy, taiga, jungle, and swamp atmospheric variants

Fog smoothing

Border and cave fog

Bloomy fog

Colored light shafts through air fog

Water, Nether, and End volumetric fog paths

Configurable volumetric light propagation

Post-Processing

TAA

FXAA

CAS sharpening

Temporal upscaling (TAAU)

Bloom

Depth of field

Distance blur

Motion blur

Vignette

Purkinje shift

Manual, simple, and histogram exposure modes

Color grading controls for brightness, contrast, saturation, white balance, and color-channel adjustments

Multiple tone-mapping operators, including ACES and AgX variants

Optional dithered translucency fallback

Profiles

Luster includes five quality profiles:

Profile

Focus

Low

Reduced-cost rendering for lower-end hardware

Medium

Balanced quality and performance

High

Higher-quality shadows, reflections, clouds, AO, and lighting

Ultra

Maximum available quality and sampling

Mac Compatible

Conservative feature set intended for macOS / Apple Silicon

The Mac Compatible profile intentionally disables some of the more hardware-intensive or platform-sensitive features while keeping the main lighting, atmosphere, water, reflection, shadow, cloud, and post-processing pipeline available.

Compatibility

Shader loader

Iris — supported and recommended

OptiFine — not supported by Luster

Platforms

Nvidia

AMD

Intel

Apple Silicon / macOS through Iris' OpenGL compatibility path

Mod support

Distant Horizons

Voxy

Some features are conditional on the shader loader, Minecraft version, GPU, or selected profile. The in-game settings menu is the authoritative source for features available in a given configuration.

Installation

Install Iris for your Minecraft version.

Download the latest Luster shader pack archive.

Place the .zip in your .minecraft/shaderpacks folder.

In Minecraft, open Video Settings → Shader Packs and select Luster.

Start with the Mac Compatible, Medium, or High profile depending on your hardware and adjust individual settings from there.

Latest download

Download the latest Luster source archive

Rendering notes

Luster is intentionally modular and exposes many of its systems directly through the shader configuration menu. Several expensive features are optional and are not enabled by every profile.

Notably, Luster does not currently advertise the removed RSM/indirect-lighting and ReSTIR spatial-reuse pipeline as an active feature. The current lighting stack instead centers on direct lighting, voxel-based colored light propagation, IBL, shadows, AO, reflections, and volumetric lighting.

Configuration

The main settings are organized into:

World — weather, moon-phase influence, foliage, rain, snow, and world effects

Lighting — colored lights, IBL, light sources, shadows, and AO

Sky — atmosphere, clouds, stars, aurora, sun/moon, rainbows, and sky effects

Fog — atmospheric scattering, volumetrics, fog smoothing, shafts, and biome variants

Materials — PBR, POM, directional lightmaps, SSS, reflections, and refraction

Water — waves, fog, caustics, refraction, edge effects, and rain puddles

Post-Processing — exposure, AA, upscaling, bloom, DOF, motion blur, vignette, and color grading

Misc — debugging and additional visual controls

Mods — integration settings for supported mods

Development

Luster is actively developed as a shaderpack project. The source tree is organized into reusable modules under shaders/include/, with rendering programs under shaders/program/ and world-specific passes under the world* directories.

Bug reports and implementation issues specific to Luster should be opened in the repository's issue tracker.

Credits & Acknowledgements

Luster contains substantially reworked shader code based on the Photon shader pack by SixthSurge. Original Photon credits and applicable licenses are retained in the project.

Additional acknowledgements include:

NakiriRuri and OrzMiku — Simplified Chinese menu translation

ChunghwaMC — Traditional Chinese menu translation

Jmayk — Italian menu translation

Timtaran — Russian menu translation

shihyeon — Korean menu translation

DVRKHz — Spanish menu translation

Patatagod69 — Dutch menu translation

sincerity — Estonian menu translation

Emin — Shadow bias method from Complementary Reimagined

DrDesten — Depth tolerance calculation for SSR

Jessie — f0 and f82 values for labPBR hardcoded metals

Sledgehammer Games — Bloom downsampling method used in Call of Duty: Advanced Warfare

momentsingraphics.de — Blue noise texture

NASA Scientific Visualization Studio — Galaxy image

Please see the included LICENSE files and in-tree attribution/license documents for applicable licensing information.

Community

Luster is a personal shaderpack project maintained by shashankpgowda.

Luster repository: https://github.com/shashankpgowda/Luster

Issues: https://github.com/shashankpgowda/Luster/issues

Upstream Photon: https://github.com/sixthsurge/photon

Photon Discord: https://discord.gg/ngEW66HScd

<p align="center"><sub>Luster • Minecraft Shader Pack</sub></p>