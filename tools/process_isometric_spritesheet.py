#!/usr/bin/env python3
"""Convert a flat-magenta ImageGen 3x4 sheet into a strict 48x64 runtime sheet."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from process_isometric_environment import quantize_rgba, remove_key_spill


FRAME_SIZE = (48, 64)
GRID_SIZE = (3, 4)


def is_key_pixel(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return (
        red > 70
        and blue > 70
        and red > green * 1.35
        and blue > green * 1.35
        and abs(red - blue) < 95
    )


def largest_component(cell: Image.Image) -> Image.Image:
    width, height = cell.size
    pixels = cell.load()
    foreground = [
        [not is_key_pixel(pixels[x, y]) for x in range(width)]
        for y in range(height)
    ]
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if not foreground[y][x] or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while stack:
                px, py = stack.pop()
                component.append((px, py))
                for nx, ny in (
                    (px - 1, py),
                    (px + 1, py),
                    (px, py - 1),
                    (px, py + 1),
                ):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and foreground[ny][nx]
                        and (nx, ny) not in seen
                    ):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            components.append(component)
    if not components:
        raise ValueError("sheet cell contains no foreground subject")
    component = max(components, key=len)
    xs = [point[0] for point in component]
    ys = [point[1] for point in component]
    bounds = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    mask = Image.new("L", (width, height), 0)
    mask_pixels = mask.load()
    for x, y in component:
        mask_pixels[x, y] = 255
    result = cell.convert("RGBA")
    result.putalpha(mask)
    return result.crop(bounds)


def process(source_path: Path, output_path: Path, preview_path: Path) -> None:
    source = Image.open(source_path).convert("RGB")
    subjects: list[Image.Image] = []
    for row in range(GRID_SIZE[1]):
        for column in range(GRID_SIZE[0]):
            x0 = round(column * source.width / GRID_SIZE[0])
            x1 = round((column + 1) * source.width / GRID_SIZE[0])
            y0 = round(row * source.height / GRID_SIZE[1])
            y1 = round((row + 1) * source.height / GRID_SIZE[1])
            subjects.append(largest_component(source.crop((x0, y0, x1, y1))))

    max_width = max(subject.width for subject in subjects)
    max_height = max(subject.height for subject in subjects)
    scale = min(40 / max_width, 58 / max_height)
    sheet = Image.new(
        "RGBA",
        (FRAME_SIZE[0] * GRID_SIZE[0], FRAME_SIZE[1] * GRID_SIZE[1]),
        (0, 0, 0, 0),
    )
    for index, subject in enumerate(subjects):
        size = (
            max(1, round(subject.width * scale)),
            max(1, round(subject.height * scale)),
        )
        subject = subject.resize(size, Image.Resampling.BOX)
        subject = quantize_rgba(remove_key_spill(subject), 32)
        frame = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
        frame.alpha_composite(
            subject,
            ((FRAME_SIZE[0] - subject.width) // 2, FRAME_SIZE[1] - 1 - subject.height),
        )
        sheet.alpha_composite(
            frame,
            ((index % GRID_SIZE[0]) * FRAME_SIZE[0], (index // GRID_SIZE[0]) * FRAME_SIZE[1]),
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, optimize=True)
    sheet.resize(
        (sheet.width * 4, sheet.height * 4), Image.Resampling.NEAREST
    ).save(preview_path, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("preview", type=Path)
    args = parser.parse_args()
    process(args.source, args.output, args.preview)


if __name__ == "__main__":
    main()
