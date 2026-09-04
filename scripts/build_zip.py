#!/usr/bin/env python3
"""Build a distributable Luster shader-pack archive."""

from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


DEFAULT_FILES = ("LICENSE", "README.md")


def build_archive(project_root: Path, output_path: Path) -> None:
    """Write the distributable project files to output_path."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with ZipFile(output_path, "w", compression=ZIP_DEFLATED) as archive:
        for relative_path in DEFAULT_FILES:
            source_path = project_root / relative_path
            if source_path.is_file():
                archive.write(source_path, relative_path)

        shaders_path = project_root / "shaders"
        for source_path in sorted(shaders_path.rglob("*")):
            if source_path.is_file():
                archive.write(source_path, source_path.relative_to(project_root))


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=project_root / "dist" / "Luster.zip",
        help="output archive path (default: dist/Luster.zip)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project_root = Path(__file__).resolve().parent.parent
    output_path = args.output.resolve()
    build_archive(project_root, output_path)
    print(f"Built {output_path}")


if __name__ == "__main__":
    main()