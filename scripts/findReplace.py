"""
Find and replace text in every shader file, setting file, and language file.

Usage (run from the Luster-main root):
python3 scripts/findReplace.py
"""

import os

find = input("find: ")
replace = input("replace with: ")
directory = input("directory (default: shaders): ").strip() or "shaders"

extensions = {".glsl", ".fsh", ".vsh", ".csh", ".properties", ".lang", ".json"}

if not find:
    raise SystemExit("nothing to find")

for root, _, files in os.walk(directory):
    for name in files:
        if os.path.splitext(name)[1] not in extensions:
            continue
        path = os.path.join(root, name)

        # newline="" keeps line endings and the trailing newline exactly as they were
        with open(path, "r", encoding="utf-8", newline="") as file:
            content = file.read()

        if find in content:
            with open(path, "w", encoding="utf-8", newline="") as file:
                file.write(content.replace(find, replace))
            print(f"updated {path}")
