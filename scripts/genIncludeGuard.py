"""
Generate or update the file-level include guard of a shader include file.

Usage (run from the Luster-main root):
python3 scripts/genIncludeGuard.py lib/example.glsl [GUARD_NAME]

The guard name defaults to INCLUDE_ + the path below shaders/ (without the leading "lib/" and the
extension), converted to SCREAMING_SNAKE_CASE. For example lib/brdf/fresnel.glsl becomes
INCLUDE_BRDF_FRESNEL and lib/util/fastMath.glsl becomes INCLUDE_UTIL_FAST_MATH. Pass GUARD_NAME to
use a different name.

The guard goes after the license header comment and wraps the rest of the file. Section guards
inside the file (e.g. INCLUDE_LIGHT_CLOUD_SHADOWS) are never touched.
"""

import os
import re
import sys


def derive_guard(path_from_shaders_dir):
    path = os.path.splitext(path_from_shaders_dir)[0].replace("\\", "/")
    if path.startswith("lib/"):
        path = path[len("lib/"):]
    path = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", path)  # camelCase -> camel_Case
    return "INCLUDE_" + re.sub(r"[^A-Za-z0-9]+", "_", path).upper()


def first_code_index(lines):
    """Index of the first line that is not blank, a // comment or part of a /* */ comment."""
    in_block = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if in_block:
            if "*/" in stripped:
                in_block = False
            continue
        if stripped == "" or stripped.startswith("//"):
            continue
        if stripped.startswith("/*"):
            if "*/" not in stripped:
                in_block = True
            continue
        return i
    return len(lines)


def update_guard(path_from_shaders_dir, guard=None, shaders_dir="shaders"):
    """Add or rename the file-level guard. Returns the guard name that is now in the file."""
    path_absolute = os.path.join(shaders_dir, path_from_shaders_dir)
    guard = guard or derive_guard(path_from_shaders_dir)

    with open(path_absolute, "r", encoding="utf-8", newline="") as f:
        content = f.read()

    lines = content.split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # trailing newline, added back on write

    # last non-blank line
    last = len(lines) - 1
    while last >= 0 and lines[last].strip() == "":
        last -= 1

    start = first_code_index(lines)
    existing = None
    if start + 1 < len(lines):
        m = re.fullmatch(r"#if !defined (\w+)", lines[start].strip())
        if m and lines[start + 1].strip() == f"#define {m.group(1)}":
            existing = m.group(1)

    if existing:
        if last < 0 or lines[last].strip() != f"#endif // {existing}":
            raise RuntimeError(
                f"{path_absolute}: found guard {existing} but the last line is not "
                f"'#endif // {existing}'. Fix it by hand first."
            )
        lines[start] = f"#if !defined {guard}"
        lines[start + 1] = f"#define {guard}"
        lines[last] = f"#endif // {guard}"
    else:
        lines.insert(start, f"#if !defined {guard}")
        lines.insert(start + 1, f"#define {guard}")
        lines.insert(start + 2, "")
        while lines and lines[-1].strip() == "":
            lines.pop()
        lines.append("")
        lines.append(f"#endif // {guard}")

    with open(path_absolute, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines) + "\n")

    return guard


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    name = update_guard(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    print(f"{sys.argv[1]}: {name}")
