## Style guide

### Naming conventions
- All functions, variables, constants, custom uniforms and files should be named
  in `camelCase` (e.g. `getSpecularReflections`, `biomeWaterTint`,
  `waterFogSimple.glsl`).
- Word segments inside identifiers and file names get shortened to the pack's
  canonical forms, in camelCase and SCREAMING_SNAKE segments alike:
  `Coefficient(s)` → `Coef(s)`, `Lighting` → `Light`, `Resolution` → `Res`,
  `Parameter(s)` → `Param(s)`, `Threshold` → `Thresh`,
  `Accumulation`/`Accumulated` → `Accum` (e.g. `waterAbsorptionCoef`,
  `INCLUDE_LIGHT_`-style guards, `_PARAMS`).
- Comments, `.lang` display values, and `profile.`/`screen.`/`sliders=` value
  strings stay normal English — only identifiers, macros, guards, and file
  names get shortened.
- Structs should be named in `PascalCase` (e.g. `Material`, `OverworldFogParams`).
- Macros should be named in `SCREAMING_SNAKE_CASE` (There are some macros that
  pretend to be functions and are named like functions; going forward I think
  we should avoid this.)

### Loader-bound names (never rename)
- Program and config file names: `gbuffers_*`, `dh_*` programs, `voxy.json`,
  `lang/*.lang` locale file names, etc.
- The prefixes `clrwl_`, `voxy_`, `sclrwl_`, `scl_`, `at_` (e.g. `at_tangent`,
  `at_midBlock`), `dh_`, `mc_`, `gl_`, `world0_` and any other uniforms the
  loader injects itself.
- Iris-reserved names: `shadowMapResolution`, `noiseTextureResolution`, and the
  `oldLighting` directive (and other directives parsed by the loader).
- Option ids, `screen.*`/`profile.*` keys and `option.*` lang keys must stay in
  sync — rename them together or not at all.

### Shader-option registration
- Boolean options must be checked at least once via `#ifdef`/`#ifndef`, or Iris
  won't list the toggle on the settings screen. References inside a combined
  plain `#if defined A && defined B` do not count — add an empty
  `#ifdef NAME` / `#endif` reference next to it when the type-switch needs the
  combined form.

### Comment style
- Full sentences, capitalized, with a space or line break before the text.
- Explain intent and why, not just what. Keep one-off notes directly above the
  code they describe.
- Nested or block-level rule transitions (e.g. a directive that switches the
  layout of the code after it) get a short note above, not trailing.

### Code formatting
- Ideally, auto-format your code using `clang-format`. Format is set by the
  root `.clang-format` file (`clang-format` 17 or newer is required for
  `PenaltyIndentedWhitespace`, `RemoveSemicolon`, and a few other keys).
- Otherwise, just try to make it look like the other code (4-space indentation,
  80-char limit, 4-space continuation indent, attached braces, one statement
  per line). I periodically auto-format everything so it doesn't matter too
  much. `IndentPPDirectives: None` — preprocessor lines stay flush-left, also
  inside functions.
