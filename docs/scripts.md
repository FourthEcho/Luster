# Scripts

Utility scripts in `scripts/`. Run from the repo root unless noted otherwise.

---

## find_replace.py

Find and replace a string across all shader files (`.glsl`, `.fsh`, `.vsh`, `.csh`) in a directory.

```
python3 scripts/find_replace.py
```

Prompts for:
- `find` — string to search for
- `replace with` — replacement string
- `directory` — root directory to search recursively

---

## gen_include_guard.py

Adds or updates an include guard for a file under `shaders/include/`. The guard name is derived from the file path (e.g. `include/fog/overworld/constants.glsl` → `INCLUDE_FOG_OVERWORLD_CONSTANTS`).

```
python3 scripts/gen_include_guard.py include/fog/overworld/constants.glsl
```

Argument is the path relative to `shaders/`.

---

## gen_slider_values.py

Generates a formatted slider value list for use in `settings.glsl` option definitions.

```
python3 scripts/gen_slider_values.py
```

Prompts for:
- `start` — first value
- `end` — last value
- `step` — increment
- `decimal places` — formatting precision

Outputs a `[...]` list ready to paste into a `SLIDERFLAGS` or similar setting definition.

---

## rename_include.py

Renames a shader file and updates all `#include` references to it across the entire `shaders/` tree.

```
python3 scripts/rename_include.py include/old_name.glsl include/new_name.glsl
```

Both arguments are paths relative to `shaders/`. Run from the repo root.
