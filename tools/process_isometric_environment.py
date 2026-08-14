#!/usr/bin/env python3
"""Build strict isometric ground tiles and prop sprites from ImageGen sources."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


GROUND_TILE_SIZE = (32, 16)
GROUND_GRID_SIZE = (4, 1)
PROP_GRID_SIZE = (2, 2)
PROP_SPECS = (
    ("pine_tree.png", (72, 88)),
    ("fence_down_right.png", (72, 40)),
    ("fence_down_left.png", (72, 40)),
    ("roadside_shop.png", (128, 88)),
)


def is_key_pixel(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return (
        red > 50
        and blue > 50
        and red > green * 1.25
        and blue > green * 1.25
        and abs(red - blue) < 115
    )


def largest_component(cell: Image.Image) -> Image.Image:
    width, height = cell.size
    rgba = cell.convert("RGBA")
    pixels = rgba.load()
    foreground = [
        [
            pixels[x, y][3] > 16 and not is_key_pixel(pixels[x, y][:3])
            for x in range(width)
        ]
        for y in range(height)
    ]
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if not foreground[y][x] or (x, y) in seen:
                continue
            component: list[tuple[int, int]] = []
            stack = [(x, y)]
            seen.add((x, y))
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
        raise ValueError("source cell contains no foreground subject")
    component = max(components, key=len)
    xs = [point[0] for point in component]
    ys = [point[1] for point in component]
    bounds = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    mask = Image.new("L", (width, height), 0)
    mask_pixels = mask.load()
    for x, y in component:
        mask_pixels[x, y] = 255
    result = rgba
    result.putalpha(mask)
    return result.crop(bounds)


def quantize_rgba(image: Image.Image, colors: int) -> Image.Image:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
    rgb = image.convert("RGB").quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
    ).convert("RGB")
    result = rgb.convert("RGBA")
    result.putalpha(alpha)
    return result


def remove_key_spill(image: Image.Image) -> Image.Image:
    result = image.convert("RGBA")
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            is_magenta_spill = (
                red > green * 1.3
                and blue > green * 1.3
                and abs(red - blue) < 105
            )
            spill = max(0, min(red, blue) - green)
            if is_magenta_spill and spill > 10:
                red = max(green, red - spill)
                blue = max(green, blue - spill)
            pixels[x, y] = (red, green, blue, alpha)
    return result


def _cell(source: Image.Image, column: int, row: int, grid: tuple[int, int]) -> Image.Image:
    x0 = round(column * source.width / grid[0])
    x1 = round((column + 1) * source.width / grid[0])
    y0 = round(row * source.height / grid[1])
    y1 = round((row + 1) * source.height / grid[1])
    return source.crop((x0, y0, x1, y1))


def process_ground(source_path: Path, output_path: Path, preview_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    atlas = Image.new(
        "RGBA",
        (GROUND_TILE_SIZE[0] * GROUND_GRID_SIZE[0], GROUND_TILE_SIZE[1]),
        (0, 0, 0, 0),
    )
    diamond = Image.new("L", GROUND_TILE_SIZE, 0)
    ImageDraw.Draw(diamond).polygon(((15, 0), (31, 7), (16, 15), (0, 8)), fill=255)
    for column in range(GROUND_GRID_SIZE[0]):
        subject = largest_component(_cell(source, column, 0, GROUND_GRID_SIZE))
        texture = subject.resize(GROUND_TILE_SIZE, Image.Resampling.NEAREST)
        texture = quantize_rgba(remove_key_spill(texture), 20)
        texture.putalpha(diamond)
        atlas.alpha_composite(texture, (column * GROUND_TILE_SIZE[0], 0))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output_path, optimize=True)
    atlas.resize((atlas.width * 6, atlas.height * 6), Image.Resampling.NEAREST).save(
        preview_path,
        optimize=True,
    )


def process_props(source_path: Path, output_directory: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    output_directory.mkdir(parents=True, exist_ok=True)
    for index, (file_name, canvas_size) in enumerate(PROP_SPECS):
        subject = largest_component(_cell(
            source,
            index % PROP_GRID_SIZE[0],
            index // PROP_GRID_SIZE[0],
            PROP_GRID_SIZE,
        ))
        maximum_size = (canvas_size[0] - 4, canvas_size[1] - 3)
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
        canvas.save(output_directory / file_name, optimize=True)
        canvas.resize(
            (canvas.width * 4, canvas.height * 4),
            Image.Resampling.NEAREST,
        ).save(output_directory / file_name.replace(".png", "_preview.png"), optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ground-source", type=Path, required=True)
    parser.add_argument("--ground-output", type=Path, required=True)
    parser.add_argument("--ground-preview", type=Path, required=True)
    parser.add_argument("--props-source", type=Path, required=True)
    parser.add_argument("--props-output", type=Path, required=True)
    arguments = parser.parse_args()
    process_ground(
        arguments.ground_source,
        arguments.ground_output,
        arguments.ground_preview,
    )
    process_props(arguments.props_source, arguments.props_output)


if __name__ == "__main__":
    main()
