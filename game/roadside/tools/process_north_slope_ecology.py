#!/usr/bin/env python3
"""Build the deterministic north-slope ecological TileSet atlases and props."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

from process_isometric_environment import (  # noqa: E402
    is_key_pixel,
    quantize_rgba,
    remove_key_spill,
)


TILE_SIZE = (32, 16)
PROP_GRID = (4, 2)
PROP_SPECS = (
    ("pine_young.png", (48, 72)),
    ("pine_mature.png", (72, 88)),
    ("shrub_dense.png", (48, 32)),
    ("shrub_sparse.png", (44, 36)),
    ("rocks_small.png", (40, 24)),
    ("rocks_large.png", (56, 36)),
    ("fallen_log.png", (64, 32)),
)


def source_cell(
    source: Image.Image,
    column: int,
    row: int,
    grid: tuple[int, int],
) -> Image.Image:
    left = round(column * source.width / grid[0])
    right = round((column + 1) * source.width / grid[0])
    top = round(row * source.height / grid[1])
    bottom = round((row + 1) * source.height / grid[1])
    return source.crop((left, top, right, bottom))


def all_foreground(cell: Image.Image) -> Image.Image:
    rgba = cell.convert("RGBA")
    pixels = rgba.load()
    points: list[tuple[int, int]] = []
    mask = Image.new("L", rgba.size, 0)
    mask_pixels = mask.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            broad_key = (
                red > 90
                and blue > 90
                and red > green * 1.14
                and blue > green * 1.14
                and abs(red - blue) < 145
            )
            if alpha > 16 and not is_key_pixel((red, green, blue)) and not broad_key:
                points.append((x, y))
                mask_pixels[x, y] = 255
    if not points:
        raise ValueError("source cell contains no foreground")
    bounds = (
        min(point[0] for point in points),
        min(point[1] for point in points),
        max(point[0] for point in points) + 1,
        max(point[1] for point in points) + 1,
    )
    rgba.putalpha(mask)
    return rgba.crop(bounds)


def strong_despill(image: Image.Image) -> Image.Image:
    result = remove_key_spill(image).convert("RGBA")
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and red > green * 1.12 and blue > green * 1.12:
                red = min(red, green + 12)
                blue = min(blue, green + 8)
                pixels[x, y] = (red, green, blue, alpha)
    return result


def strict_diamond_mask() -> Image.Image:
    mask = Image.new("L", TILE_SIZE, 0)
    ImageDraw.Draw(mask).polygon(((15, 0), (31, 7), (16, 15), (0, 8)), fill=255)
    return mask


def process_ground(
    existing_ground_path: Path,
    source_path: Path,
    output_path: Path,
    preview_path: Path,
) -> None:
    existing = Image.open(existing_ground_path).convert("RGBA")
    source = Image.open(source_path).convert("RGBA")
    atlas = Image.new("RGBA", (TILE_SIZE[0] * 8, TILE_SIZE[1]), (0, 0, 0, 0))
    atlas.alpha_composite(existing, (0, 0))
    diamond = strict_diamond_mask()
    for column in range(4):
        material = all_foreground(source_cell(source, column, 0, (4, 2)))
        material = material.resize(TILE_SIZE, Image.Resampling.NEAREST)
        material = strong_despill(quantize_rgba(strong_despill(material), 20))
        material.putalpha(diamond)
        atlas.alpha_composite(material, ((column + 4) * TILE_SIZE[0], 0))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output_path, optimize=True)
    atlas.resize((atlas.width * 5, atlas.height * 5), Image.Resampling.NEAREST).save(
        preview_path,
        optimize=True,
    )


def process_details(source_path: Path, output_path: Path, preview_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    atlas = Image.new("RGBA", (TILE_SIZE[0] * 6, TILE_SIZE[1]), (0, 0, 0, 0))
    for column in range(6):
        detail = all_foreground(source_cell(source, column, 1, (6, 2)))
        maximum_size = (20, 11)
        scale = min(maximum_size[0] / detail.width, maximum_size[1] / detail.height)
        resized_size = (
            max(1, round(detail.width * scale)),
            max(1, round(detail.height * scale)),
        )
        detail = detail.resize(resized_size, Image.Resampling.NEAREST)
        detail = strong_despill(quantize_rgba(strong_despill(detail), 12))
        tile = Image.new("RGBA", TILE_SIZE, (0, 0, 0, 0))
        tile.alpha_composite(
            detail,
            ((tile.width - detail.width) // 2, tile.height - 2 - detail.height),
        )
        atlas.alpha_composite(tile, (column * TILE_SIZE[0], 0))
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
        prop = all_foreground(source_cell(
            source,
            index % PROP_GRID[0],
            index // PROP_GRID[0],
            PROP_GRID,
        ))
        maximum_size = (canvas_size[0] - 4, canvas_size[1] - 3)
        scale = min(maximum_size[0] / prop.width, maximum_size[1] / prop.height)
        resized_size = (
            max(1, round(prop.width * scale)),
            max(1, round(prop.height * scale)),
        )
        prop = prop.resize(resized_size, Image.Resampling.NEAREST)
        prop = strong_despill(quantize_rgba(strong_despill(prop), 32))
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        canvas.alpha_composite(
            prop,
            ((canvas.width - prop.width) // 2, canvas.height - 1 - prop.height),
        )
        output_path = output_directory / file_name
        canvas.save(output_path, optimize=True)
        canvas.resize(
            (canvas.width * 4, canvas.height * 4),
            Image.Resampling.NEAREST,
        ).save(output_path.with_name(output_path.stem + "_preview.png"), optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing-ground", type=Path, required=True)
    parser.add_argument("--ground-source", type=Path, required=True)
    parser.add_argument("--ground-output", type=Path, required=True)
    parser.add_argument("--ground-preview", type=Path, required=True)
    parser.add_argument("--detail-output", type=Path, required=True)
    parser.add_argument("--detail-preview", type=Path, required=True)
    parser.add_argument("--props-source", type=Path, required=True)
    parser.add_argument("--props-output", type=Path, required=True)
    arguments = parser.parse_args()
    process_ground(
        arguments.existing_ground,
        arguments.ground_source,
        arguments.ground_output,
        arguments.ground_preview,
    )
    process_details(
        arguments.ground_source,
        arguments.detail_output,
        arguments.detail_preview,
    )
    process_props(arguments.props_source, arguments.props_output)


if __name__ == "__main__":
    main()
