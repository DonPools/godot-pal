#!/usr/bin/env python3
"""Extract deterministic full and cut herb props from one ImageGen source sheet."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

from process_isometric_environment import (
    largest_component,
    quantize_rgba,
    remove_key_spill,
)


SPECS = (
    ("fanqing_grass.png", (48, 64)),
    ("fanqing_grass_cut.png", (48, 32)),
)


def source_cell(source: Image.Image, column: int) -> Image.Image:
    left = round(column * source.width / 2)
    right = round((column + 1) * source.width / 2)
    return source.crop((left, 0, right, source.height))


def process(source_path: Path, output_directory: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    output_directory.mkdir(parents=True, exist_ok=True)
    for column, (file_name, canvas_size) in enumerate(SPECS):
        subject = largest_component(source_cell(source, column))
        maximum_size = (canvas_size[0] - 4, canvas_size[1] - 4)
        scale = min(maximum_size[0] / subject.width, maximum_size[1] / subject.height)
        resized_size = (
            max(1, round(subject.width * scale)),
            max(1, round(subject.height * scale)),
        )
        subject = subject.resize(resized_size, Image.Resampling.NEAREST)
        subject = quantize_rgba(remove_key_spill(subject), 32)
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        canvas.alpha_composite(
            subject,
            ((canvas.width - subject.width) // 2, canvas.height - 1 - subject.height),
        )
        output_path = output_directory / file_name
        canvas.save(output_path, optimize=True)
        canvas.resize(
            (canvas.width * 4, canvas.height * 4),
            Image.Resampling.NEAREST,
        ).save(output_path.with_name(output_path.stem + "_preview.png"), optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    process(arguments.source, arguments.output)


if __name__ == "__main__":
    main()
