<br><br>

<h1 align="center">Luster Shaders</h1>

<p align="center">A gameplay-focused Minecraft shader pack with a custom Luster rendering architecture, expanded indirect lighting, procedural volumetric clouds, weather simulation, and an Apple OpenGL 4.1 compatibility target.</p>

![Screenshot](docs/images/rainbow.png)

## About

Luster is a substantial source-level fork of Photon Shaders by SixthSurge. Photon is the upstream rendering foundation; Luster is an actively modified shaderpack with additional rendering systems, new data resources, reorganized lighting paths, expanded cloud simulation, and a different compatibility target.

The current upstream Photon project describes its core feature set as a revamped sky, lighting and water system; layered cloud types; an immersive weather system; voxel colored lighting; screen-space reflections; volumetric fog; soft shadows; GTAO; camera effects; TAA/FXAA/CAS; temporal upscaling; and LabPBR support. Luster retains and extends much of that foundation rather than treating the GUI as a cosmetic layer. Every major setting documented below is backed by an active shader path in the current pack.

Upstream reference: https://github.com/sixthsurge/photon

## Mac compatibility

Luster is built around a conservative OpenGL 4.1 rendering target, which is particularly important on macOS where the system OpenGL implementation does not provide the newer OpenGL 4.3/4.6 feature set commonly assumed by modern shaderpacks.

The core Luster pipeline therefore avoids compute-shader dependencies and keeps its main rendering work in vertex, fragment, and compatibility-friendly GLSL stages. Optional features are conditionally compiled so a feature that requires a specific Iris or renderer capability does not become a mandatory requirement for every platform.

The Mac profile is also intentionally conservative: it disables the optional colored-light/voxel backend used by the higher-end profiles while retaining the main atmospheric, water, material, anti-aliasing, and post-processing systems.

The goal is not to make every optional effect identical across every GPU. The goal is to provide a reliable baseline across Nvidia, AMD, Intel, and Apple systems while keeping the rendering architecture within the OpenGL 4.1-era feature envelope.

## Luster features added and expanded beyond Photon

The following comparison is based on the current SixthSurge Photon `main` branch and its current shader settings, rather than an old Photon release. Photon already contains sophisticated volumetric cloud scattering, powder effects, multiple-scattering phase functions, layered clouds, a weather field, voxel colored lighting, GTAO, volumetric fog, SSR, TAAU, POM, and water effects. Luster's extensions are therefore described specifically where the current Luster source adds another algorithm, resource, control path, or rendering stage.

### Indirect Lighting

Luster has a dedicated indirect-lighting subsystem rather than treating indirect illumination as a fixed ambient term.

**SSGI** is a multi-pass screen-space global-illumination pipeline. It supports configurable radius, ray steps, bounce count, temporal accumulation, temporal weighting, and a spatial filter. The current pipeline uses dedicated intermediate targets for accumulated bounce radiance and temporal history, and it rejects incompatible history using depth information before blending it back into the scene.

SSGI is injected into diffuse lighting as actual indirect radiance. It is therefore different from simply raising ambient light or skylight intensity. The bounce setting can request additional screen-space bounces, while the temporal path reduces the amount of visible noise at the cost of greater history sensitivity.

**LPV / volumetric lighting** remains a separate path. Luster keeps the distinction between screen-space indirect light and volumetric light propagation clear: SSGI provides screen-space diffuse bounce light, while LPV/voxel infrastructure handles volumetric propagation where the selected renderer supports it.

### Image-Based Lighting (IBL)

Luster adds a dedicated OpenGL 4.1-compatible IBL implementation in `include/lighting/ibl.glsl`.

The diffuse path estimates sky/environment irradiance with cosine-weighted hemisphere sampling. The specular path uses visible-normal GGX importance sampling and an environment BRDF integration path. The implementation also includes multi-scatter compensation so rough and glossy materials do not lose excessive energy during specular integration.

IBL is a master feature toggle in the current GUI. Its surface controls are:

* Diffuse IBL sample count
* Diffuse IBL intensity
* Specular IBL sample count
* Specular IBL intensity

Volumetric fog has a separate, smaller IBL sample budget because the fog renderer can tolerate fewer environment samples than surface shading. This path uses the same sky/environment representation but is intentionally kept lower cost.

IBL is not a replacement for direct sun, moon, blocklight, or skylight. It is an environmental indirect-lighting contribution that is combined with those direct sources and with material-dependent reflection behavior.

### Anisotropic Filtering

Luster contains a dedicated anisotropic texture-filtering helper in `include/utility/anisotropic_filter.glsl`.

The system exposes an anisotropy level and prefers the host's hardware texture filtering when that path is available. The shader also contains a derivative-based GLSL fallback for cases where the requested filtering cannot be provided by the host path.

This primarily improves texture stability on surfaces viewed at shallow angles, including terrain, roads, roofs, long walls, and PBR normal/material maps.

### Expanded cloud data and noise resources

Photon's current cloud implementation already uses layered volumetric clouds, 3D Worley detail volumes, a 2D gradient-Perlin helper, a 2D curl construction derived from that gradient, and temporal/cloud upscaling controls. Luster goes further by adding dedicated precomputed 3D data resources:

* `perlin_3d.dat` — a tileable multi-octave 3D improved-Perlin field used for volumetric cloud mass shaping.
* `curl_3d.dat` — a 3D vector field used to warp cloud coordinates and introduce coherent turbulent deformation.
* `blue_noise_3d.dat` — a 3D blue-noise field used for cloud raymarch dithering and temporal sample distribution.
* Existing 3D Worley volumes remain available for cellular and erosion detail.

The result is a larger separation of responsibilities: Perlin handles broad coherent mass, Worley provides cellular erosion/detail, curl supplies turbulent spatial warping, and blue noise distributes raymarch samples without requiring another full-resolution buffer.

### Cloud lighting upgrades

Photon already contains sophisticated cloud scattering. Its current cloud common code includes single- and multi-scattering phase functions and a powder effect, and its Cumulus scattering loop includes direct extinction, ground illumination, a simple upper-layer/sky contribution, and repeated scattering falloff. Luster does not claim those ideas as new; the Luster upgrade is the additional structure layered around them.

Luster's cloud lighting adds a dedicated `CLOUDS_LIGHTING_BOUNCES` control and a shared `clouds_internal_bounce_light()` model. The enabled bounces are not a repeated fixed multiplier. Each bounce changes with:

* Cloud height within the layer
* Local cloud density
* Optical depth toward the light
* Light/view angular relationship
* Edge proximity
* Progressive attenuation as bounce order increases

The model therefore behaves approximately as:

```text
Bounce 0 = direct sunlight
Bounce 1 = direct light after cloud extinction
Bounce 2 = density-feedback bounce
Bounce 3 = weaker, more diffuse density-feedback bounce
...
```

while changing the coefficients with height and angle instead of multiplying the same factor repeatedly.

Luster also separates several pieces of the cloud interior response that were previously bundled into simpler terms:

* **Core attenuation** darkens optically thick interiors using light optical depth and local density.
* **Ground ambient weighting** increases the influence of warm lower-boundary fill toward the bottom of the cloud.
* **Sky ambient weighting** increases upper-layer ambient contribution toward the cloud top.
* **Silver lining** boosts thin, forward-facing cloud edges.
* **Powder response** increases transmission/scattering near thin boundaries and forward-facing regions.
* **Multi-bounce phase response** makes later internal contributions more diffuse than the direct-light lobe.

The intended visual result is the familiar progression from a bright thin edge, through a warm/gray transition, into a cool mid-density body and finally a dark high-optical-depth core.

### Storm and convective cloud expansion

The existing Cumulus Congestus module is expanded with a storm-aware weather field. Storm intensity affects cloud height, vertical development, density, and anvil growth.

At strong convection, the module can extend above the main cloud tower and generate a thinner, horizontally spreading anvil region. The storm logic is driven by the weather field rather than requiring a dedicated storm texture.

This is deliberately structured as a procedural cloud modifier so future storm lifecycle states can evolve the existing Cumulus/Congestus/anvil modules instead of consuming a new texture for every storm type.

### Dedicated cloud coverage map

Luster keeps a dedicated cloud/weather coverage map path and uses it to avoid repeatedly rebuilding local coverage information inside the primary cloud raymarch.

The current Cumulus path can read local coverage from `colortex8`, and the coverage pipeline can generate the local cloud field independently of cloud-shadow rendering. This separates large-scale weather/coverage information from high-frequency volumetric detail.

### Weather-field controls

Luster exposes a weather field with independently controllable temperature, humidity, and wind biases plus variation speeds. It also exposes weather advection strength, weather cell scale, and storm feedback.

These controls modify the underlying spatial weather state used by the cloud system. They are not merely post-process color controls.

The storm feedback term can reinforce convective cloud development, advection moves the weather field through world space, and cell scale changes the spatial size of weather structures.

This architecture also gives Luster a clean foundation for the planned storm lifecycle generator: formation, growth, mature convection, dissipation, and remnant anvil states can be represented as procedural state layered on top of the existing weather field and cloud modules.

### Ambient Occlusion expansion

Photon's current baseline exposes GTAO. Luster retains SSAO/GTAO and adds **RTAO** as an additional screen-space mode.

The RTAO path marches view-space rays against scene depth using a cosine-weighted, golden-ratio hemisphere sample set, checks each step for an occluder in front of the ray within reach, and exits early on the first valid hit with a smooth distance falloff. RTAO has independent step-count and radius controls and can be selected as the active shader AO mode. Photon does not currently implement an RTAO mode.

### Moon-phase separation

Luster separates moon-phase influence into three independent systems:

* **Night Lighting** — controls moon-phase impact on direct nighttime lighting.
* **Night Atmosphere** — controls moon-phase impact on atmospheric brightness.
* **Reflections** — controls moon-phase contribution to reflected moonlight.

The three systems can therefore be tuned independently instead of treating moon phase as one global brightness multiplier.

### Fog and atmospheric expansion

Luster's atmospheric system exposes dedicated Rayleigh and Mie controls, including weather and biome-specific Rayleigh density/color states, multiple time-of-day Mie densities, falloff controls, cave/border/bloomy fog, colored light shafts, and volumetric fog smoothing controls.

The current `FOG_SMOOTHING` feature controls volumetric sampling/reconstruction behavior. It should not be described as a full Gaussian denoiser: the current pipeline still reconstructs from the half-resolution volumetric fog buffers through its existing filter stage. A future depth-aware temporal/bilateral fog filter can build on that foundation.

### Water expansion

Luster retains the existing volumetric water system and exposes wave/displacement controls, absorption/scattering, edge highlights, caustics, Snell's window, refraction, biome water color, water texture controls, and rain-puddle modes.

Rain puddles have three modes—Off, Puddles, and Everywhere—with a separate intensity control. The earlier rain-ripple experiment is not part of the current Luster shaderpack.

### Depth of field and Distance Blur

Luster uses one post-processing mode selector with three states:

* Off
* Depth of Field
* Distance Blur

The selected mode determines which blur path is compiled and used. Depth of Field uses focus distance, intensity, and sample count. Distance Blur uses its own intensity and start-distance controls and is not a second name for DOF.

### Anti-aliasing and temporal reconstruction

Luster includes TAA, TAA variance clipping, TAAU, FXAA, CAS-style sharpening, and cloud temporal upscaling. Cloud history handling has additional rejection logic around stale or invalid reprojection so the volumetric cloud renderer does not have to rely entirely on scene TAA to hide temporal instability.

### Output color modes

The final output pipeline supports:

* sRGB
* Rec. 2020
* Display P3
* DCI-P3
* Adobe RGB

Color-space selection is independent of the artistic color-grading controls.

## Rendering systems

### Lighting

The lighting pipeline separates direct sources, environmental lighting, and indirect contributions. Direct sources include sun, moon, blocklight, skylight, cave lighting, Nether/End lighting, and material-dependent light interaction. Indirect contributions can come from IBL, SSGI, and volumetric/voxel lighting paths.

### Shadows

The current shadow system supports shadow maps, software PCF, colored shadows, variable penumbra/soft shadows, entity and block-entity shadows, cloud shadows, pixelated shadow options, and configurable shadow distance/resolution.

PCF is intentionally a simple On/Off setting in the current GUI. When enabled, Luster uses the software PCF path. `PCF Sample Quality` is a separate quality multiplier for the software filter and is placed at the end of the Shadows screen.

### Reflections

Luster retains screen-space reflections and roughness-aware reflection controls while integrating the specular IBL path. Screen-space information and environment information can therefore contribute to the final reflection according to material roughness and the active rendering modes.

### Materials and PBR

The material system supports normal/specular mapping, LabPBR-oriented material properties, parallax occlusion mapping, directional lightmaps, emission/specular handling, porosity, subsurface scattering, and SSS sheen.

POM exposes depth, distance, sample count, shadow sampling, and related controls. Anisotropic filtering is available as a separate texture-reconstruction feature.

### Clouds

The current cloud layer system contains:

* Cumulus
* Cumulus Congestus
* Altocumulus
* Cirrus
* Cirrocumulus controls within the Cirrus layer
* Noctilucent Clouds
* Optional blocky/Minecraft-style clouds

Each layer has its own density, coverage, altitude/thickness, size, detail, wind, and sampling controls where applicable. Cumulus, Congestus, and Altocumulus also expose primary ray steps, lighting steps, and ambient steps.

### Atmospheric effects

The sky and atmosphere system includes Rayleigh and Mie scattering, rain desaturation, atmospheric saturation boost, aurora support, stars, galaxy rendering, rainbows, End sun effects, sky-ground contribution, and crepuscular rays.

## GUI and settings

The current Luster GUI is driven directly by `shaders.properties` and mirrors the actual settings present in the shaderpack.

### World

**Weather**

* Random Weather Variation
* Biome Weather Variation
* Temperature Bias
* Humidity Bias
* Wind Bias
* Temperature Variation Speed
* Humidity Variation Speed
* Wind Variation Speed

**World controls**

* Vegetation and leaf waving
* Edge highlighting
* Slanted rain
* Rain opacity
* Moon-phase controls
* Desert sandstorm intensity
* End glow
* Snow opacity

### Lighting

**Indirect Lighting**

* SSGI
* SSGI Intensity
* SSGI Radius
* SSGI Ray Steps
* SSGI Bounces
* SSGI Temporal Weight
* SSGI Filter Radius

**IBL**

* IBL
* IBL Samples
* IBL Intensity
* Specular IBL Samples
* Specular IBL Intensity

**Light Sources**

* Sun color and intensity
* Moon color and intensity
* Blocklight color and intensity
* Skylight intensity
* Shading strength
* Cave lighting and falloff
* Nether lighting
* End lighting and ambient lighting

**Shadows**

* Shadows
* Software PCF
* SSRT Shadows
* SSRT Shadow Steps
* Colored Shadows
* Penumbra
* Entity Shadows
* Block Entity Shadows
* Cloud Shadows
* Pixelated Shadows
* Shadow Resolution
* Shadow Distance
* Penumbra Scale
* PCF Sample Quality

**Ambient Occlusion**

* Vanilla AO
* Shader AO mode
* SSAO steps/radius
* GTAO steps/radius
* RTAO steps/radius

### Sky

**Aurora**

* Aurora mode controls
* Brightness
* Frequency
* Cloud lighting
* Ground lighting

**Clouds**

* Temporal Upscaling
* Scale
* Aerial Perspective Boost
* Cloud Lighting Bounces
* Cumulus
* Altocumulus
* Cumulus Congestus
* Cirrus/Cirrocumulus
* Noctilucent Clouds
* Blocky Clouds

**Stars**

* Enabled
* Intensity
* Coverage

**Crepuscular Rays**

* Enabled
* Intensity
* Horizon sample count
* Zenith sample count

**Sky controls**

* Vanilla Sun
* Vanilla Moon
* Sun Angular Radius
* Moon Angular Radius
* Sky-Ground Contribution
* Galaxy
* Galaxy Intensity
* Rainbows
* End Sun Effect
* Atmospheric Rain Desaturation
* Atmospheric Saturation Boost

### Fog

* Volumetric Fog
* Overworld Fog Intensity
* Border Fog
* Cave Fog
* Bloomy Fog
* Bloomy Fog Intensity
* Fog Smoothing Radius
* Colored Light Shafts
* Rayleigh density/color/falloff
* Weather and biome-specific Rayleigh states
* Time-of-day and weather-specific Mie density/falloff
* Volumetric-light render scale
* LPV/volumetric lighting controls

### Materials

* Normal Mapping
* Specular Mapping
* POM
* Texture/material settings
* Hardcoded specular/emission/SSS modes
* Anisotropic filtering
* Porosity
* Subsurface scattering
* SSS Sheen
* Directional Lightmaps
* Reflections
* Refraction

### Water

**Waves**

* Water Waves
* Wave Iterations
* Wave Strength
* Wave Frequency
* Still/Flowing Speed
* Persistence
* Lacunarity
* Noise Strength
* Water Parallax
* Water Displacement
* Height variation

**Water fog coefficients**

* Absorption RGB
* Water scattering
* Underwater absorption RGB
* Underwater scattering

**Surface effects**

* Water Edge Highlight
* Water Caustics
* Snell's Window
* Water Texture
* Biome Water Color
* Water Refraction
* Rain Puddles

### Post-Processing

**Color Grading**

* Tonemapping
* Brightness
* Contrast
* Saturation
* White Balance
* Orange/Teal/Green saturation controls
* Green hue shift
* Purkinje Shift

**Exposure**

* Auto Exposure
* Bias
* Minimum and maximum exposure
* Adaptation speeds
* Manual exposure
* Screen-brightness assist
* Histogram bins
* Histogram target

**Anti-Aliasing**

* TAA
* Variance clipping
* FXAA
* TAAU
* TAAU Render Scale
* CAS
* CAS intensity

**Other post-processing**

* Bloom
* Depth of Field / Distance Blur
* Motion Blur
* Vignette

### Miscellaneous

* Debug view and debug sampler
* Distance-view controls and distance-view method
* White World
* Fancy Nether Portal
* Custom Sky
* Custom Sky Brightness
* Enchantment Glint Brightness
* Tonemap Comparison
* Dithered Translucency Fallback
* Handheld lighting mode and intensity
* Debug box overlay (mode, line width, color, emission)
* Texture format and material mapping mode

### Mods

* Distant Horizons
* Photonics compatibility
* Optional Voxy-related compatibility paths where supported by the current shader source

## GUI language support

The current shaderpack ships localized GUI files for:

* English (`en_US`)
* Chinese Simplified (`zh_CN`)
* Chinese Traditional (`zh_TW`)
* Estonian (`et_EE`)
* Italian (`it_IT`)
* Korean (`ko_KR`)
* Dutch (`nl_NL`)
* Russian (`ru_RU`)
* Spanish/Mexico (`es_MX`)

English is the canonical reference language. Every option exposed through `shaders.properties` has an English label and comment. Other locales provide translated text where available and English fallback text where a translation has not been supplied.

## Profiles

The current profiles are Low, Medium, High, Ultra, and Mac.

**Low** prioritizes compatibility and low shader cost, with reduced shadow, cloud, POM, SSAO, reflection, and volumetric sampling.

**Medium** increases the main cloud, reflection, POM, and volumetric sampling while retaining a conservative feature set.

**High** enables significantly more advanced lighting, cloud, shadow, AO, and reflection paths.

**Ultra** enables the highest current sampling tiers, including the strongest cloud sampling, RTAO, extensive volumetric lighting, colored lighting, water effects, and the highest configured IBL quality.

**Mac** uses the Apple-oriented compatibility configuration, retaining the main rendering pipeline while disabling the optional colored-light/voxel backend and other expensive platform-sensitive features.

## Compatibility

### GPU vendors

* Nvidia
* AMD
* Intel
* Apple/macOS through the target OpenGL 4.1-compatible path

Actual feature availability can still vary with the graphics driver, Iris version, renderer, and optional capabilities. Platform-sensitive features are guarded in shader code where appropriate.

### Shader loader

* **Iris** is the primary supported shader loader.
* The current Luster development branch is not maintained as an OptiFine-first target.

### Special mod support

* [Distant Horizons](https://www.curseforge.com/minecraft/mc-mods/distant-horizons)
* [Voxy](https://modrinth.com/mod/voxy) where the corresponding compatibility path is available
* Photonics compatibility paths where supported

## Installation

1. Install [Iris](https://irisshaders.dev/download).
2. Place the Luster ZIP in `.minecraft/shaderpacks`.
3. Select Luster in the Iris shader-pack menu.
4. Start with the profile closest to your hardware, then tune individual settings as needed.

## Upstream comparison and attribution

Luster is based on Photon Shaders by SixthSurge. Photon remains the upstream project for inherited portions of the codebase, and its license and acknowledgments remain relevant to those portions.

Current Photon baseline reference:
https://github.com/sixthsurge/photon

Current Photon README:
https://github.com/sixthsurge/photon/blob/main/README.md

Current Photon cloud common implementation:
https://github.com/sixthsurge/photon/blob/main/shaders/include/sky/clouds/common.glsl

Current Photon Cumulus implementation:
https://github.com/sixthsurge/photon/blob/main/shaders/include/sky/clouds/cumulus.glsl

Current Photon shader GUI:
https://github.com/sixthsurge/photon/blob/main/shaders/shaders.properties

Photon's current README identifies its baseline cloud system, weather, voxel colored lighting, SSR, volumetric fog, GTAO, camera effects, TAA/FXAA/CAS, temporal upscaling, and LabPBR support.

The current Photon cloud source also confirms that Photon already has 2D gradient-based Perlin/curl helpers, 3D Worley detail textures, multiple-scattering phase functions, and powder effects. Luster's cloud documentation therefore treats those as inherited foundations and identifies the additional 3D Perlin/curl resources and the explicit height/density/angle-dependent internal bounce model as Luster upgrades.

Photon's current shadow/profile configuration still exposes software PCF, colored shadows, variable penumbra, GTAO, volumetric lighting, layered cloud controls, POM, SSR, and temporal upscaling. Luster's additional systems should therefore be understood as extensions of that baseline rather than replacements for it.

A direct source check against the current Photon `main` branch also confirms several Luster additions have no Photon counterpart at all, rather than being reworked versions of something Photon already had: Photon's moon-phase handling is a single `MOON_PHASE_AFFECTS_BRIGHTNESS` toggle rather than three independently tunable systems, its rain puddles are a plain on/off flag rather than a three-mode selector, and Photon currently has no RTAO mode, no anisotropic-filtering helper, no `perlin_3d`/`curl_3d` data resources, no dedicated IBL module, and no SSGI pipeline. None of this is meant to diminish Photon, whose sky, water, cloud, and shadow foundations Luster still relies on directly — it's meant to keep this document honest about which parts of the pack are genuinely new.

## Community

For Luster-specific development, issues, and feature work, use the Luster project repository and issue tracker.

For upstream Photon questions, use the SixthSurge Photon repository and its community channels.

## License

See the included `LICENSE` file for the applicable licensing and upstream attribution terms.
