#!/usr/bin/env python3
"""
Build Luster-main.zip from this repo and atomically replace the
deployed copy in the Minecraft shaderpacks folder, so Iris never
sees a half-written zip (avoids holding the file open mid-write).

Usage: python3 scripts/build_zip.py [path/to/shaderpacks]
Defaults to the standard shaderpacks directory for your OS.
"""
import os
import platform
import shutil
import sys
import zipfile
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
INCLUDE = ["shaders", "LICENSE", "README.md"]
IGNORE_NAMES = {".DS_Store"}


def default_shaderpacks_dir() -> Path:
    system = platform.system()
    home = Path.home()
    if system == "Darwin":
        return home / "Library" / "Application Support" / "minecraft" / "shaderpacks"
    if system == "Windows":
        appdata = os.environ.get("APPDATA", str(home / "AppData" / "Roaming"))
        return Path(appdata) / ".minecraft" / "shaderpacks"
    # Linux and everything else
    return home / ".minecraft" / "shaderpacks"


def build_zip(shaderpacks_dir: Path) -> Path:
    shaderpacks_dir.mkdir(parents=True, exist_ok=True)
    target_zip = shaderpacks_dir / "Luster-main.zip"
    tmp_zip = shaderpacks_dir / ".Luster-main.tmp.zip"

    if tmp_zip.exists():
        tmp_zip.unlink()

    with zipfile.ZipFile(tmp_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        for item in INCLUDE:
            src = REPO_DIR / item
            if src.is_file():
                zf.write(src, arcname=item)
            elif src.is_dir():
                for path in src.rglob("*"):
                    if path.is_file() and path.name not in IGNORE_NAMES:
                        zf.write(path, arcname=str(path.relative_to(REPO_DIR)))

    shutil.move(str(tmp_zip), str(target_zip))
    return target_zip


def main() -> None:
    shaderpacks_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else default_shaderpacks_dir()
    target_zip = build_zip(shaderpacks_dir)
    print(f"Built {target_zip} from {REPO_DIR}")


if __name__ == "__main__":
    main()
