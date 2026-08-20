#!/usr/bin/env python3
"""Deterministically build the original low-poly GLB candidate asset set."""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
OUTPUT = ROOT / "assets/original/3d"
MODEL_DIR = OUTPUT / "models"
TEXTURE_DIR = OUTPUT / "textures"
MANIFEST_PATH = OUTPUT / "manifest.json"
GENERATOR_VERSION = 5
GLB_FORMAT_VERSION = 1

COLORS = {
    "skin": (0.78, 0.52, 0.32, 1.0),
    "cloth_green": (0.08, 0.27, 0.18, 1.0),
    "cloth_blue": (0.08, 0.21, 0.36, 1.0),
    "cloth_red": (0.48, 0.14, 0.11, 1.0),
    "cloth_dark": (0.055, 0.075, 0.082, 1.0),
    "leather": (0.27, 0.14, 0.065, 1.0),
    "metal": (0.62, 0.68, 0.66, 1.0),
    "grass": (0.15, 0.30, 0.14, 1.0),
    "road": (0.34, 0.27, 0.17, 1.0),
    "stone": (0.31, 0.34, 0.32, 1.0),
    "stone_dark": (0.16, 0.19, 0.19, 1.0),
    "wood": (0.34, 0.18, 0.075, 1.0),
    "pine": (0.075, 0.23, 0.14, 1.0),
    "pine_light": (0.14, 0.34, 0.18, 1.0),
    "shrub": (0.16, 0.35, 0.14, 1.0),
    "herb": (0.30, 0.58, 0.34, 1.0),
    "herb_cut": (0.32, 0.42, 0.20, 1.0),
    "plaster": (0.60, 0.58, 0.49, 1.0),
    "roof": (0.25, 0.24, 0.22, 1.0),
    "qi_green": (0.22, 0.86, 0.52, 1.0),
    "qi_blue": (0.24, 0.62, 0.88, 1.0),
    "qi_violet": (0.58, 0.38, 0.82, 1.0),
    "qi_gold": (0.92, 0.68, 0.24, 1.0),
    "stone_moss": (0.16, 0.26, 0.20, 1.0),
    "stone_warm": (0.43, 0.28, 0.14, 1.0),
    "beast_stone": (0.43, 0.47, 0.43, 1.0),
    "beast_dark": (0.23, 0.28, 0.27, 1.0),
    "beast_moss": (0.24, 0.39, 0.29, 1.0),
    "beast_warm": (0.62, 0.37, 0.15, 1.0),
}

EMISSIVE_COLORS = {"qi_green", "qi_blue", "qi_violet", "qi_gold"}


def _align(value: int, alignment: int = 4) -> int:
    return (value + alignment - 1) // alignment * alignment


def _png_rgba(width: int, height: int, pixels: bytes) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    scanlines = b"".join(
        b"\x00" + pixels[row * width * 4 : (row + 1) * width * 4]
        for row in range(height)
    )
    return (
        signature
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(scanlines, 9))
        + chunk(b"IEND", b"")
    )


def _palette_png() -> bytes:
    names = list(COLORS)
    pixels = bytearray()
    for y in range(4):
        for x in range(4):
            color = COLORS[names[(y * 4 + x) % len(names)]]
            pixels.extend(round(channel * 255.0) for channel in color)
    return _png_rgba(4, 4, bytes(pixels))


def _white_png() -> bytes:
    return _png_rgba(2, 2, bytes([255, 255, 255, 255] * 4))


class GlbBuilder:
    def __init__(self, name: str) -> None:
        self.name = name
        self.binary = bytearray()
        self.document: dict = {
            "asset": {
                "version": "2.0",
                "generator": f"godot-pal original-lowpoly-v{GLB_FORMAT_VERSION}",
            },
            "scene": 0,
            "scenes": [{"name": name, "nodes": []}],
            "nodes": [],
            "meshes": [],
            "materials": [],
            "bufferViews": [],
            "accessors": [],
            "buffers": [{"byteLength": 0}],
        }
        self.materials: dict[str, int] = {}
        self._install_texture()

    def _install_texture(self) -> None:
        png = _white_png()
        view = self.add_view(png)
        self.document["images"] = [
            {"name": "original_material_base", "mimeType": "image/png", "bufferView": view}
        ]
        self.document["samplers"] = [
            {
                "magFilter": 9728,
                "minFilter": 9728,
                "wrapS": 33071,
                "wrapT": 33071,
            }
        ]
        self.document["textures"] = [
            {"name": "original_material_base", "sampler": 0, "source": 0}
        ]

    def add_view(self, payload: bytes, target: int | None = None) -> int:
        offset = _align(len(self.binary))
        if offset > len(self.binary):
            self.binary.extend(b"\x00" * (offset - len(self.binary)))
        self.binary.extend(payload)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(payload)}
        if target is not None:
            view["target"] = target
        self.document["bufferViews"].append(view)
        return len(self.document["bufferViews"]) - 1

    def accessor(
        self,
        values: list,
        component_type: int,
        type_name: str,
        target: int | None = None,
        minimum: list[float] | None = None,
        maximum: list[float] | None = None,
    ) -> int:
        formats = {5123: "H", 5125: "I", 5126: "f"}
        component_format = formats[component_type]
        flattened: list[float | int] = []
        for value in values:
            if isinstance(value, (tuple, list)):
                flattened.extend(value)
            else:
                flattened.append(value)
        payload = struct.pack("<" + component_format * len(flattened), *flattened)
        view = self.add_view(payload, target)
        result: dict = {
            "bufferView": view,
            "componentType": component_type,
            "count": len(values),
            "type": type_name,
        }
        if minimum is not None:
            result["min"] = minimum
        if maximum is not None:
            result["max"] = maximum
        self.document["accessors"].append(result)
        return len(self.document["accessors"]) - 1

    def material(self, color_name: str) -> int:
        if color_name in self.materials:
            return self.materials[color_name]
        color = COLORS[color_name]
        material = {
            "name": color_name,
            "pbrMetallicRoughness": {
                "baseColorFactor": list(color),
                "baseColorTexture": {"index": 0, "texCoord": 0},
                "metallicFactor": 0.25 if color_name == "metal" else 0.0,
                "roughnessFactor": 0.72,
            },
        }
        if color_name in EMISSIVE_COLORS:
            material["emissiveFactor"] = [
                min(channel * 0.7, 1.0) for channel in color[:3]
            ]
        self.document["materials"].append(material)
        index = len(self.document["materials"]) - 1
        self.materials[color_name] = index
        return index

    def primitive(
        self,
        positions: list[tuple[float, float, float]],
        normals: list[tuple[float, float, float]],
        indices: list[int],
        color_name: str,
        joints: list[tuple[int, int, int, int]] | None = None,
        weights: list[tuple[float, float, float, float]] | None = None,
    ) -> dict:
        mins = [min(position[axis] for position in positions) for axis in range(3)]
        maxs = [max(position[axis] for position in positions) for axis in range(3)]
        attributes = {
            "POSITION": self.accessor(
                positions, 5126, "VEC3", 34962, mins, maxs
            ),
            "NORMAL": self.accessor(normals, 5126, "VEC3", 34962),
            "TEXCOORD_0": self.accessor(
                [(0.125, 0.125)] * len(positions), 5126, "VEC2", 34962
            ),
        }
        if joints is not None and weights is not None:
            attributes["JOINTS_0"] = self.accessor(joints, 5123, "VEC4", 34962)
            attributes["WEIGHTS_0"] = self.accessor(weights, 5126, "VEC4", 34962)
        component = 5123 if max(indices, default=0) < 65536 else 5125
        return {
            "attributes": attributes,
            "indices": self.accessor(indices, component, "SCALAR", 34963),
            "material": self.material(color_name),
            "mode": 4,
        }

    def write(self, path: Path) -> dict:
        self.document["buffers"][0]["byteLength"] = len(self.binary)
        json_bytes = json.dumps(
            self.document, ensure_ascii=True, separators=(",", ":"), sort_keys=True
        ).encode("utf-8")
        json_bytes += b" " * (_align(len(json_bytes)) - len(json_bytes))
        binary = bytes(self.binary)
        binary += b"\x00" * (_align(len(binary)) - len(binary))
        total = 12 + 8 + len(json_bytes) + 8 + len(binary)
        payload = (
            b"glTF"
            + struct.pack("<II", 2, total)
            + struct.pack("<I4s", len(json_bytes), b"JSON")
            + json_bytes
            + struct.pack("<I4s", len(binary), b"BIN\x00")
            + binary
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return {
            "path": path.relative_to(ROOT).as_posix(),
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "mesh_count": len(self.document["meshes"]),
            "material_count": len(self.document["materials"]),
        }


def cuboid(
    center: tuple[float, float, float],
    size: tuple[float, float, float],
) -> tuple[list, list, list]:
    cx, cy, cz = center
    hx, hy, hz = (component * 0.5 for component in size)
    faces = [
        ((1, 0, 0), [(hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz)]),
        ((-1, 0, 0), [(-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz), (-hx, -hy, -hz)]),
        ((0, 1, 0), [(-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz)]),
        ((0, -1, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz)]),
        ((0, 0, 1), [(hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz), (-hx, -hy, hz)]),
        ((0, 0, -1), [(-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz), (hx, -hy, -hz)]),
    ]
    positions: list = []
    normals: list = []
    indices: list[int] = []
    for normal, corners in faces:
        start = len(positions)
        positions.extend((cx + x, cy + y, cz + z) for x, y, z in corners)
        normals.extend([normal] * 4)
        indices.extend([start, start + 1, start + 2, start, start + 2, start + 3])
    return positions, normals, indices


def cone(
    center: tuple[float, float, float], radius: float, height: float, segments: int = 8
) -> tuple[list, list, list]:
    cx, cy, cz = center
    positions: list = []
    normals: list = []
    indices: list[int] = []
    for index in range(segments):
        angle_a = math.tau * index / segments
        angle_b = math.tau * (index + 1) / segments
        start = len(positions)
        a = (cx + math.cos(angle_a) * radius, cy - height * 0.5, cz + math.sin(angle_a) * radius)
        b = (cx + math.cos(angle_b) * radius, cy - height * 0.5, cz + math.sin(angle_b) * radius)
        top = (cx, cy + height * 0.5, cz)
        nx = math.cos((angle_a + angle_b) * 0.5)
        nz = math.sin((angle_a + angle_b) * 0.5)
        positions.extend([a, b, top])
        normals.extend([(nx, radius / height, nz)] * 3)
        indices.extend([start, start + 1, start + 2])
    bottom = len(positions)
    positions.append((cx, cy - height * 0.5, cz))
    normals.append((0, -1, 0))
    for index in range(segments):
        angle_a = math.tau * index / segments
        angle_b = math.tau * (index + 1) / segments
        start = len(positions)
        positions.extend(
            [
                (cx + math.cos(angle_b) * radius, cy - height * 0.5, cz + math.sin(angle_b) * radius),
                (cx + math.cos(angle_a) * radius, cy - height * 0.5, cz + math.sin(angle_a) * radius),
            ]
        )
        normals.extend([(0, -1, 0), (0, -1, 0)])
        indices.extend([bottom, start, start + 1])
    return positions, normals, indices


def octahedron(
    center: tuple[float, float, float],
    size: tuple[float, float, float],
) -> tuple[list[tuple], list[tuple], list[int]]:
    """Build a flat-shaded faceted volume for readable low-poly creatures."""
    cx, cy, cz = center
    hx, hy, hz = (component * 0.5 for component in size)
    vertices = [
        (cx, cy + hy, cz),
        (cx, cy - hy, cz),
        (cx - hx, cy, cz),
        (cx + hx, cy, cz),
        (cx, cy, cz - hz),
        (cx, cy, cz + hz),
    ]
    faces = [
        (0, 4, 3), (0, 3, 5), (0, 5, 2), (0, 2, 4),
        (1, 3, 4), (1, 5, 3), (1, 2, 5), (1, 4, 2),
    ]
    positions: list[tuple] = []
    normals: list[tuple] = []
    indices: list[int] = []
    for face in faces:
        start = len(positions)
        a, b, c = (vertices[index] for index in face)
        ab = tuple(b[axis] - a[axis] for axis in range(3))
        ac = tuple(c[axis] - a[axis] for axis in range(3))
        nx = ab[1] * ac[2] - ab[2] * ac[1]
        ny = ab[2] * ac[0] - ab[0] * ac[2]
        nz = ab[0] * ac[1] - ab[1] * ac[0]
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        normal = (nx / length, ny / length, nz / length)
        positions.extend([a, b, c])
        normals.extend([normal] * 3)
        indices.extend([start, start + 1, start + 2])
    return positions, normals, indices


def quat(axis: tuple[float, float, float], angle: float) -> tuple[float, float, float, float]:
    half = angle * 0.5
    sine = math.sin(half)
    return (axis[0] * sine, axis[1] * sine, axis[2] * sine, math.cos(half))


def quat_multiply(
    first: tuple[float, float, float, float],
    second: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    """Compose two unit quaternions for deterministic animation poses."""
    ax, ay, az, aw = first
    bx, by, bz, bw = second
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def arm_pose(side: int, lowered: float = 1.02, swing: float = 0.0) -> tuple[float, float, float, float]:
    """Return a relaxed arm pose; side is -1 for left and +1 for right."""
    z_angle = lowered if side < 0 else -lowered
    return quat_multiply(quat((0, 0, 1), z_angle), quat((1, 0, 0), swing))


def forearm_pose(side: int, bend: float = 0.24) -> tuple[float, float, float, float]:
    z_angle = bend if side < 0 else -bend
    return quat((0, 0, 1), z_angle)


BONES = [
    ("hips", -1, (0.0, 1.03, 0.0)),
    ("spine", 0, (0.0, 0.34, 0.0)),
    ("head", 1, (0.0, 0.48, 0.0)),
    ("upper_arm_l", 1, (-0.31, 0.25, 0.0)),
    ("lower_arm_l", 3, (-0.34, 0.0, 0.0)),
    ("upper_arm_r", 1, (0.31, 0.25, 0.0)),
    ("lower_arm_r", 5, (0.34, 0.0, 0.0)),
    ("upper_leg_l", 0, (-0.15, -0.12, 0.0)),
    ("lower_leg_l", 7, (0.0, -0.43, 0.0)),
    ("foot_l", 8, (0.0, -0.38, -0.07)),
    ("upper_leg_r", 0, (0.15, -0.12, 0.0)),
    ("lower_leg_r", 10, (0.0, -0.43, 0.0)),
    ("foot_r", 11, (0.0, -0.38, -0.07)),
]


def _global_bone_positions(scale: float = 1.0) -> list[tuple[float, float, float]]:
    result: list[tuple[float, float, float]] = []
    for _name, parent, translation in BONES:
        local = tuple(component * scale for component in translation)
        if parent < 0:
            result.append(local)
        else:
            parent_position = result[parent]
            result.append(tuple(parent_position[axis] + local[axis] for axis in range(3)))
    return result


def _animation_specs() -> dict[str, tuple[list[float], dict[str, list[tuple]]]]:
    identity = quat((1, 0, 0), 0.0)
    left_rest = arm_pose(-1)
    right_rest = arm_pose(1)
    left_forearm = forearm_pose(-1)
    right_forearm = forearm_pose(1)
    return {
        "idle": (
            [0.0, 0.5, 1.0],
            {
                "spine": [quat((0, 0, 1), -0.035), quat((0, 0, 1), 0.035), quat((0, 0, 1), -0.035)],
                "upper_arm_l": [arm_pose(-1, 1.02, 0.05), arm_pose(-1, 1.05, -0.05), arm_pose(-1, 1.02, 0.05)],
                "lower_arm_l": [left_forearm, forearm_pose(-1, 0.28), left_forearm],
                "upper_arm_r": [arm_pose(1, 1.02, -0.05), arm_pose(1, 1.05, 0.05), arm_pose(1, 1.02, -0.05)],
                "lower_arm_r": [right_forearm, forearm_pose(1, 0.28), right_forearm],
            },
        ),
        "run": (
            [0.0, 0.25, 0.5, 0.75, 1.0],
            {
                "upper_leg_l": [quat((1, 0, 0), 0.72), identity, quat((1, 0, 0), -0.72), identity, quat((1, 0, 0), 0.72)],
                "upper_leg_r": [quat((1, 0, 0), -0.72), identity, quat((1, 0, 0), 0.72), identity, quat((1, 0, 0), -0.72)],
                "upper_arm_l": [arm_pose(-1, 0.92, -0.58), left_rest, arm_pose(-1, 0.92, 0.58), left_rest, arm_pose(-1, 0.92, -0.58)],
                "lower_arm_l": [left_forearm] * 5,
                "upper_arm_r": [arm_pose(1, 0.92, 0.58), right_rest, arm_pose(1, 0.92, -0.58), right_rest, arm_pose(1, 0.92, 0.58)],
                "lower_arm_r": [right_forearm] * 5,
            },
        ),
        "attack": (
            [0.0, 0.18, 0.42, 0.7],
            {
                "spine": [identity, quat((0, 1, 0), -0.32), quat((0, 1, 0), 0.28), identity],
                "upper_arm_l": [left_rest, arm_pose(-1, 0.82, 0.28), arm_pose(-1, 0.9, -0.22), left_rest],
                "lower_arm_l": [left_forearm] * 4,
                "upper_arm_r": [right_rest, arm_pose(1, 0.42, -1.5), arm_pose(1, 0.62, 0.62), right_rest],
                "lower_arm_r": [right_forearm, arm_pose(1, 0.18, -0.55), arm_pose(1, 0.2, 0.32), right_forearm],
            },
        ),
        "cast": (
            [0.0, 0.3, 0.65, 1.0],
            {
                "upper_arm_l": [left_rest, arm_pose(-1, 0.38, -1.18), arm_pose(-1, 0.5, -0.48), left_rest],
                "lower_arm_l": [left_forearm, forearm_pose(-1, 0.08), forearm_pose(-1, 0.12), left_forearm],
                "upper_arm_r": [right_rest, arm_pose(1, 0.38, -1.18), arm_pose(1, 0.5, -0.48), right_rest],
                "lower_arm_r": [right_forearm, forearm_pose(1, 0.08), forearm_pose(1, 0.12), right_forearm],
                "spine": [identity, quat((1, 0, 0), -0.12), quat((1, 0, 0), 0.08), identity],
            },
        ),
        "hit": (
            [0.0, 0.12, 0.35],
            {
                "spine": [identity, quat((1, 0, 0), 0.38), identity],
                "head": [identity, quat((1, 0, 0), -0.25), identity],
                "upper_arm_l": [left_rest, arm_pose(-1, 0.78, 0.24), left_rest],
                "lower_arm_l": [left_forearm] * 3,
                "upper_arm_r": [right_rest, arm_pose(1, 0.78, 0.24), right_rest],
                "lower_arm_r": [right_forearm] * 3,
            },
        ),
        "death": (
            [0.0, 0.45, 1.0],
            {
                "hips": [identity, quat((0, 0, 1), 0.55), quat((0, 0, 1), 1.48)],
                "spine": [identity, quat((1, 0, 0), 0.25), quat((1, 0, 0), 0.5)],
                "upper_arm_l": [left_rest, arm_pose(-1, 0.78, 0.18), arm_pose(-1, 0.58, 0.28)],
                "lower_arm_l": [left_forearm] * 3,
                "upper_arm_r": [right_rest, arm_pose(1, 0.78, -0.18), arm_pose(1, 0.58, -0.28)],
                "lower_arm_r": [right_forearm] * 3,
            },
        ),
    }


def build_humanoid(name: str, palette: dict[str, str], scale: float = 1.0) -> dict:
    builder = GlbBuilder(name)
    globals_ = _global_bone_positions(scale)
    for index, (bone_name, parent, translation) in enumerate(BONES):
        node = {
            "name": bone_name,
            "translation": [component * scale for component in translation],
        }
        children = [child for child, spec in enumerate(BONES) if spec[1] == index]
        if children:
            node["children"] = children
        builder.document["nodes"].append(node)
    primitives: list[dict] = []
    parts = [
        (0, globals_[0], (0.46 * scale, 0.24 * scale, 0.26 * scale), palette["cloth"]),
        (1, (globals_[1][0], globals_[1][1] + 0.15 * scale, 0.0), (0.56 * scale, 0.52 * scale, 0.28 * scale), palette["cloth"]),
        (2, (globals_[2][0], globals_[2][1] + 0.13 * scale, 0.0), (0.3 * scale, 0.3 * scale, 0.28 * scale), "skin"),
        (3, (globals_[3][0] - 0.17 * scale, globals_[3][1], 0.0), (0.34 * scale, 0.14 * scale, 0.15 * scale), palette["cloth"]),
        (4, (globals_[4][0] - 0.17 * scale, globals_[4][1], 0.0), (0.34 * scale, 0.12 * scale, 0.13 * scale), "skin"),
        (5, (globals_[5][0] + 0.17 * scale, globals_[5][1], 0.0), (0.34 * scale, 0.14 * scale, 0.15 * scale), palette["cloth"]),
        (6, (globals_[6][0] + 0.17 * scale, globals_[6][1], 0.0), (0.34 * scale, 0.12 * scale, 0.13 * scale), "skin"),
        (7, (globals_[7][0], globals_[7][1] - 0.2 * scale, 0.0), (0.18 * scale, 0.4 * scale, 0.2 * scale), palette["legs"]),
        (8, (globals_[8][0], globals_[8][1] - 0.18 * scale, 0.0), (0.16 * scale, 0.36 * scale, 0.18 * scale), palette["legs"]),
        (9, (globals_[9][0], globals_[9][1] - 0.04 * scale, -0.08 * scale), (0.18 * scale, 0.12 * scale, 0.32 * scale), "leather"),
        (10, (globals_[10][0], globals_[10][1] - 0.2 * scale, 0.0), (0.18 * scale, 0.4 * scale, 0.2 * scale), palette["legs"]),
        (11, (globals_[11][0], globals_[11][1] - 0.18 * scale, 0.0), (0.16 * scale, 0.36 * scale, 0.18 * scale), palette["legs"]),
        (12, (globals_[12][0], globals_[12][1] - 0.04 * scale, -0.08 * scale), (0.18 * scale, 0.12 * scale, 0.32 * scale), "leather"),
    ]
    for joint, center, size, material in parts:
        positions, normals, indices = cuboid(center, size)
        joints = [(joint, 0, 0, 0)] * len(positions)
        weights = [(1.0, 0.0, 0.0, 0.0)] * len(positions)
        primitives.append(builder.primitive(positions, normals, indices, material, joints, weights))
    builder.document["meshes"].append({"name": f"{name}_mesh", "primitives": primitives})
    mesh_node = len(builder.document["nodes"])
    builder.document["nodes"].append({"name": "character_mesh", "mesh": 0, "skin": 0})
    builder.document["scenes"][0]["nodes"] = [0, mesh_node]
    inverse_matrices = []
    for x, y, z in globals_:
        inverse_matrices.append(
            (1.0, 0.0, 0.0, 0.0,
             0.0, 1.0, 0.0, 0.0,
             0.0, 0.0, 1.0, 0.0,
             -x, -y, -z, 1.0)
        )
    inverse_accessor = builder.accessor(inverse_matrices, 5126, "MAT4")
    builder.document["skins"] = [
        {
            "name": "shared_humanoid_rig",
            "inverseBindMatrices": inverse_accessor,
            "skeleton": 0,
            "joints": list(range(len(BONES))),
        }
    ]
    animations = []
    bone_indices = {bone[0]: index for index, bone in enumerate(BONES)}
    for animation_name, (times, tracks) in _animation_specs().items():
        input_accessor = builder.accessor(
            times, 5126, "SCALAR", minimum=[min(times)], maximum=[max(times)]
        )
        samplers = []
        channels = []
        for bone_name, rotations in tracks.items():
            output_accessor = builder.accessor(rotations, 5126, "VEC4")
            samplers.append(
                {"input": input_accessor, "output": output_accessor, "interpolation": "LINEAR"}
            )
            channels.append(
                {
                    "sampler": len(samplers) - 1,
                    "target": {"node": bone_indices[bone_name], "path": "rotation"},
                }
            )
        animations.append(
            {"name": animation_name, "samplers": samplers, "channels": channels}
        )
    builder.document["animations"] = animations
    record = builder.write(MODEL_DIR / f"{name}.glb")
    record.update(
        {
            "kind": "rigged_character",
            "bones": [bone[0] for bone in BONES],
            "animations": list(_animation_specs()),
            "triangle_count": sum(len(primitive[2]) // 3 for primitive in [cuboid(part[1], part[2]) for part in parts]),
        }
    )
    return record


def build_static(name: str, parts: list[tuple[str, tuple]]) -> dict:
    builder = GlbBuilder(name)
    primitives = []
    triangle_count = 0
    for shape, spec in parts:
        if shape == "box":
            center, size, material = spec
            geometry = cuboid(center, size)
        elif shape == "cone":
            center, radius, height, material = spec
            geometry = cone(center, radius, height)
        elif shape == "octahedron":
            center, size, material = spec
            geometry = octahedron(center, size)
        else:
            raise ValueError(f"unknown shape {shape}")
        positions, normals, indices = geometry
        triangle_count += len(indices) // 3
        primitives.append(builder.primitive(positions, normals, indices, material))
    builder.document["meshes"].append({"name": f"{name}_mesh", "primitives": primitives})
    builder.document["nodes"].append({"name": name, "mesh": 0})
    builder.document["scenes"][0]["nodes"] = [0]
    record = builder.write(MODEL_DIR / f"{name}.glb")
    record.update({"kind": "static_module", "triangle_count": triangle_count})
    return record


def static_specs() -> dict[str, list[tuple[str, tuple]]]:
    return {
        "weapon_straight_sword": [
            ("box", ((0.0, 0.48, 0.0), (0.055, 0.9, 0.018), "metal")),
            ("box", ((0.0, -0.02, 0.0), (0.28, 0.055, 0.06), "metal")),
            ("box", ((0.0, -0.2, 0.0), (0.075, 0.32, 0.075), "leather")),
        ],
        "weapon_iron_staff": [
            ("box", ((0.0, 0.55, 0.0), (0.08, 1.8, 0.08), "wood")),
            ("cone", ((0.0, 1.5, 0.0), 0.18, 0.32, "metal")),
            ("box", ((0.0, -0.38, 0.0), (0.12, 0.16, 0.12), "metal")),
        ],
        "ground_grass": [("box", ((0.0, -0.08, 0.0), (4.0, 0.16, 4.0), "grass"))],
        "road_stone": [
            ("box", ((0.0, -0.045, 0.0), (4.0, 0.09, 1.4), "road")),
            ("box", ((-1.2, 0.015, 0.0), (0.5, 0.05, 0.45), "stone")),
            ("box", ((0.15, 0.015, 0.18), (0.65, 0.05, 0.5), "stone_dark")),
            ("box", ((1.25, 0.015, -0.12), (0.55, 0.05, 0.4), "stone")),
        ],
        "rocks_cluster": [
            ("box", ((-0.28, 0.22, 0.0), (0.55, 0.44, 0.48), "stone")),
            ("box", ((0.22, 0.15, 0.12), (0.42, 0.3, 0.38), "stone_dark")),
            ("box", ((0.05, 0.1, -0.3), (0.34, 0.2, 0.3), "stone")),
        ],
        "pine_tree": [
            ("box", ((0.0, 1.05, 0.0), (0.28, 2.1, 0.28), "wood")),
            ("cone", ((0.0, 1.35, 0.0), 1.0, 1.55, "pine")),
            ("cone", ((0.0, 2.0, 0.0), 0.78, 1.4, "pine_light")),
            ("cone", ((0.0, 2.62, 0.0), 0.52, 1.2, "pine")),
        ],
        "pine_tree_young": [
            ("box", ((0.0, 0.62, 0.0), (0.2, 1.24, 0.2), "wood")),
            ("cone", ((0.0, 0.92, 0.0), 0.62, 1.0, "pine_light")),
            ("cone", ((0.0, 1.38, 0.0), 0.42, 0.85, "pine")),
        ],
        "mountain_shrub": [
            ("cone", ((-0.25, 0.38, 0.0), 0.48, 0.75, "shrub")),
            ("cone", ((0.22, 0.32, 0.12), 0.42, 0.65, "pine_light")),
            ("cone", ((0.0, 0.28, -0.22), 0.36, 0.58, "shrub")),
        ],
        "fanqing_grass": [
            ("cone", ((-0.22, 0.28, 0.02), 0.14, 0.56, "herb")),
            ("cone", ((0.2, 0.25, 0.1), 0.13, 0.50, "herb")),
            ("cone", ((0.02, 0.34, -0.14), 0.16, 0.68, "herb")),
            ("cone", ((-0.08, 0.22, 0.22), 0.12, 0.44, "pine_light")),
            ("cone", ((0.24, 0.18, -0.18), 0.11, 0.36, "pine_light")),
        ],
        "fanqing_grass_cut": [
            ("box", ((-0.16, 0.07, 0.02), (0.1, 0.14, 0.1), "herb_cut")),
            ("box", ((0.14, 0.06, 0.08), (0.1, 0.12, 0.1), "herb_cut")),
            ("box", ((0.0, 0.08, -0.12), (0.11, 0.16, 0.11), "herb_cut")),
        ],
        "wood_fence": [
            ("box", ((-0.9, 0.55, 0.0), (0.16, 1.1, 0.16), "wood")),
            ("box", ((0.9, 0.55, 0.0), (0.16, 1.1, 0.16), "wood")),
            ("box", ((0.0, 0.68, 0.0), (2.0, 0.13, 0.13), "wood")),
            ("box", ((0.0, 0.36, 0.0), (2.0, 0.13, 0.13), "leather")),
        ],
        "roadside_hut": [
            ("box", ((0.0, 1.0, 0.0), (2.8, 2.0, 2.2), "plaster")),
            ("box", ((0.0, 2.12, 0.0), (3.3, 0.24, 2.65), "roof")),
            ("box", ((0.0, 0.75, -1.13), (0.68, 1.5, 0.12), "wood")),
            ("box", ((-0.85, 1.25, -1.13), (0.55, 0.55, 0.12), "cloth_blue")),
        ],
        "qi_eating_whelp": [
            ("octahedron", ((0.0, 0.72, 0.02), (1.28, 1.02, 1.62), "beast_stone")),
            ("octahedron", ((0.0, 0.76, -0.92), (0.92, 0.82, 0.88), "beast_moss")),
            ("box", ((0.0, 0.52, -1.16), (0.52, 0.24, 0.34), "beast_dark")),
            ("box", ((-0.38, 0.25, -0.38), (0.25, 0.5, 0.3), "beast_dark")),
            ("box", ((0.38, 0.25, -0.38), (0.25, 0.5, 0.3), "beast_dark")),
            ("box", ((-0.38, 0.25, 0.42), (0.25, 0.5, 0.3), "beast_dark")),
            ("box", ((0.38, 0.25, 0.42), (0.25, 0.5, 0.3), "beast_dark")),
            ("cone", ((-0.22, 1.04, -0.72), 0.13, 0.34, "beast_warm")),
            ("cone", ((0.22, 1.04, -0.72), 0.13, 0.34, "beast_warm")),
            ("cone", ((-0.28, 1.18, 0.2), 0.16, 0.48, "qi_green")),
            ("cone", ((0.0, 1.28, 0.35), 0.2, 0.62, "qi_green")),
            ("cone", ((0.3, 1.14, 0.15), 0.15, 0.44, "qi_green")),
            ("box", ((-0.17, 0.73, -1.15), (0.1, 0.1, 0.05), "qi_green")),
            ("box", ((0.17, 0.73, -1.15), (0.1, 0.1, 0.05), "qi_green")),
        ],
        "stone_spitter": [
            ("octahedron", ((0.0, 0.76, 0.05), (1.38, 1.12, 1.76), "beast_warm")),
            ("octahedron", ((0.0, 0.84, -1.0), (1.02, 0.9, 0.92), "beast_stone")),
            ("box", ((0.0, 0.56, -1.32), (0.66, 0.28, 0.45), "beast_dark")),
            ("box", ((-0.38, 0.24, -0.34), (0.25, 0.48, 0.3), "beast_dark")),
            ("box", ((0.38, 0.24, -0.34), (0.25, 0.48, 0.3), "beast_dark")),
            ("box", ((-0.38, 0.24, 0.46), (0.25, 0.48, 0.3), "beast_dark")),
            ("box", ((0.38, 0.24, 0.46), (0.25, 0.48, 0.3), "beast_dark")),
            ("cone", ((0.0, 1.27, -0.05), 0.28, 0.72, "qi_blue")),
            ("cone", ((-0.32, 1.12, 0.3), 0.18, 0.48, "beast_stone")),
            ("cone", ((0.32, 1.12, 0.3), 0.18, 0.48, "beast_stone")),
            ("cone", ((-0.34, 1.34, 0.5), 0.18, 0.58, "qi_blue")),
            ("cone", ((0.34, 1.34, 0.5), 0.18, 0.58, "qi_blue")),
            ("box", ((-0.2, 0.85, -1.28), (0.11, 0.11, 0.05), "qi_blue")),
            ("box", ((0.2, 0.85, -1.28), (0.11, 0.11, 0.05), "qi_blue")),
        ],
        "spirit_gnawer": [
            ("octahedron", ((0.0, 0.84, 0.0), (1.42, 1.26, 1.82), "beast_dark")),
            ("octahedron", ((0.0, 0.94, -1.04), (0.98, 0.94, 0.9), "beast_moss")),
            ("box", ((0.0, 0.58, -1.36), (0.58, 0.26, 0.42), "qi_violet")),
            ("box", ((-0.4, 0.26, -0.38), (0.27, 0.52, 0.32), "beast_moss")),
            ("box", ((0.4, 0.26, -0.38), (0.27, 0.52, 0.32), "beast_moss")),
            ("box", ((-0.4, 0.26, 0.46), (0.27, 0.52, 0.32), "beast_moss")),
            ("box", ((0.4, 0.26, 0.46), (0.27, 0.52, 0.32), "beast_moss")),
            ("cone", ((0.0, 1.43, -0.18), 0.3, 0.86, "qi_violet")),
            ("cone", ((-0.34, 1.25, 0.24), 0.22, 0.62, "qi_violet")),
            ("cone", ((0.34, 1.25, 0.24), 0.22, 0.62, "qi_violet")),
            ("box", ((-0.19, 0.91, -1.32), (0.12, 0.12, 0.05), "qi_green")),
            ("box", ((0.19, 0.91, -1.32), (0.12, 0.12, 0.05), "qi_green")),
        ],
        "qi_eating_stone_beast": [
            ("octahedron", ((0.0, 1.18, 0.1), (2.7, 2.15, 3.25), "beast_stone")),
            ("octahedron", ((0.0, 1.28, -1.82), (1.95, 1.72, 1.58), "beast_moss")),
            ("box", ((0.0, 0.72, -2.36), (1.18, 0.46, 0.66), "beast_warm")),
            ("box", ((-0.76, 0.38, -0.72), (0.48, 0.76, 0.58), "beast_stone")),
            ("box", ((0.76, 0.38, -0.72), (0.48, 0.76, 0.58), "beast_stone")),
            ("box", ((-0.76, 0.38, 0.88), (0.48, 0.76, 0.58), "beast_stone")),
            ("box", ((0.76, 0.38, 0.88), (0.48, 0.76, 0.58), "beast_stone")),
            ("cone", ((-0.48, 1.92, -1.76), 0.26, 0.95, "qi_gold")),
            ("cone", ((0.48, 1.92, -1.76), 0.26, 0.95, "qi_gold")),
            ("cone", ((0.0, 2.08, -0.15), 0.4, 1.15, "beast_warm")),
            ("cone", ((-0.66, 1.78, 0.55), 0.3, 0.82, "beast_warm")),
            ("cone", ((0.66, 1.78, 0.55), 0.3, 0.82, "beast_warm")),
            ("box", ((-0.36, 1.28, -2.3), (0.18, 0.18, 0.07), "qi_green")),
            ("box", ((0.36, 1.28, -2.3), (0.18, 0.18, 0.07), "qi_green")),
        ],
        "lantern_array_pillar_lit": [
            ("box", ((0.0, 0.18, 0.0), (1.25, 0.36, 1.25), "stone_dark")),
            ("box", ((0.0, 0.48, 0.0), (0.9, 0.34, 0.9), "stone")),
            ("box", ((0.0, 1.45, 0.0), (0.62, 1.62, 0.62), "stone_moss")),
            ("box", ((0.0, 2.32, 0.0), (0.92, 0.22, 0.92), "stone")),
            ("cone", ((0.0, 2.72, 0.0), 0.38, 0.78, "qi_green")),
            ("box", ((0.0, 1.42, -0.33), (0.24, 0.68, 0.06), "qi_gold")),
        ],
        "lantern_array_pillar_spent": [
            ("box", ((0.0, 0.18, 0.0), (1.25, 0.36, 1.25), "stone_dark")),
            ("box", ((0.0, 0.48, 0.0), (0.9, 0.34, 0.9), "stone")),
            ("box", ((-0.12, 1.35, 0.0), (0.58, 1.4, 0.58), "stone_dark")),
            ("box", ((0.18, 2.02, 0.08), (0.66, 0.28, 0.66), "stone_warm")),
            ("box", ((0.0, 1.35, -0.3), (0.2, 0.52, 0.05), "stone_warm")),
        ],
        "lantern_core": [
            ("cone", ((0.0, 0.5, 0.0), 0.46, 1.0, "qi_green")),
            ("box", ((0.0, 0.5, 0.0), (0.18, 1.15, 0.18), "qi_gold")),
        ],
        "foundation_altar": [
            ("box", ((0.0, 0.16, 0.0), (3.2, 0.32, 3.2), "stone_dark")),
            ("box", ((0.0, 0.4, 0.0), (2.5, 0.2, 2.5), "stone")),
            ("box", ((0.0, 0.54, 0.0), (1.6, 0.12, 1.6), "stone_moss")),
            ("cone", ((-0.72, 0.88, -0.72), 0.14, 0.58, "qi_gold")),
            ("cone", ((0.72, 0.88, -0.72), 0.14, 0.58, "qi_green")),
            ("cone", ((-0.72, 0.88, 0.72), 0.14, 0.58, "qi_green")),
            ("cone", ((0.72, 0.88, 0.72), 0.14, 0.58, "qi_gold")),
        ],
    }


def main() -> int:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    palette = _palette_png()
    (TEXTURE_DIR / "original_lowpoly_palette.png").write_bytes(palette)
    records = [
        build_humanoid(
            "humanoid_base",
            {"cloth": "cloth_green", "legs": "cloth_dark"},
            1.0,
        ),
        build_humanoid(
            "humanoid_variant",
            {"cloth": "cloth_blue", "legs": "leather"},
            0.97,
        ),
        build_humanoid(
            "mountain_raider",
            {"cloth": "cloth_red", "legs": "cloth_dark"},
            1.05,
        ),
    ]
    for name, parts in static_specs().items():
        records.append(build_static(name, parts))
    palette_record = {
        "path": (TEXTURE_DIR / "original_lowpoly_palette.png").relative_to(ROOT).as_posix(),
        "bytes": len(palette),
        "sha256": hashlib.sha256(palette).hexdigest(),
        "dimensions": [4, 4],
        "kind": "palette_texture",
    }
    manifest = {
        "schema_version": 1,
        "generator_version": GENERATOR_VERSION,
        "tool": "Python standard library procedural GLB generator",
        "minimum_python": "3.9",
        "coordinate_system": "+Y up, meters, forward -Z, foot origin y=0",
        "camera_reference": "yaw 45deg, elevation 35.264deg, orthographic size 12",
        "shared_bones": [bone[0] for bone in BONES],
        "required_animations": list(_animation_specs()),
        "assets": records + [palette_record],
    }
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"ok": True, "asset_count": len(manifest["assets"])}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
