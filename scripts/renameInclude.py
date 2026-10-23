"""
Rename or move an include file and update everything that points at it.

Usage (run from the Luster-main root):
python3 scripts/renameInclude.py lib/util/color.glsl lib/util/colour.glsl

Paths are relative to shaders/. This will:
  1. move the file (creating folders as needed)
  2. update every  #include "/old/path"  in shaders/ to the new path
  3. update the file-level include guard in the moved file (see genIncludeGuard.py)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from genIncludeGuard import update_guard

EXTENSIONS = {".glsl", ".fsh", ".vsh", ".csh", ".json", ".properties"}

if len(sys.argv) != 3:
    sys.exit(__doc__)

path_old = sys.argv[1].replace("\\", "/").lstrip("/")
path_new = sys.argv[2].replace("\\", "/").lstrip("/")
path_old_from_root = f"shaders/{path_old}"
path_new_from_root = f"shaders/{path_new}"

# Rename file

if not os.path.isfile(path_old_from_root):
    raise RuntimeError(f"{path_old_from_root} is not a file")
if os.path.exists(path_new_from_root):
    raise RuntimeError(f"{path_new_from_root} already exists")

os.makedirs(os.path.dirname(path_new_from_root), exist_ok=True)
os.rename(path_old_from_root, path_new_from_root)

# Update includes (exact quoted path, so lib/util/color.glsl never matches lib/util/colorGrade.glsl)

old_include = f'#include "/{path_old}"'
new_include = f'#include "/{path_new}"'

for root, _, files in os.walk("shaders"):
    for name in files:
        if os.path.splitext(name)[1] not in EXTENSIONS:
            continue
        path = os.path.join(root, name)

        with open(path, "r", encoding="utf-8", newline="") as file:
            content = file.read()

        if old_include in content:
            with open(path, "w", encoding="utf-8", newline="") as file:
                file.write(content.replace(old_include, new_include))
            print(f"updated include in {path}")

# Update guard

if path_new.endswith(".glsl"):
    try:
        print(f"guard: {update_guard(path_new)}")
    except RuntimeError as error:
        print(f"warning: guard not updated: {error}")
