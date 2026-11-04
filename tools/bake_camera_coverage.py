"""Bake conservative orthographic coverage bands from the native static map meshes.

Run export_camera_coverage.gd first. The runtime JSON is camera metadata only.
"""
import argparse
from functools import cache
from itertools import groupby
import json
from math import ceil, floor
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CELLS_PER_UNIT = 16
SAMPLES = 8
SCALE = CELLS_PER_UNIT * SAMPLES
OUTPUT = ROOT / "game/camera/outdoor_coverage.json"


@cache
def _page_alpha(path):
    with Image.open(ROOT / path.removeprefix("res://")) as texture:
        return texture.convert("RGBA").getchannel("A")


@cache
def _alpha(path, region):
    alpha = _page_alpha(path)
    if not region:
        return alpha
    x, y, width, height = region
    return alpha.crop((x, y, x + width, y + height))


def _texture(texture):
    return texture[0], tuple(map(int, texture[1]))


@cache
def _opaque(texture, box):
    return _alpha(*texture).crop(box).getextrema()[0] >= 192


def _opaque_triangles(albedo, motion, copies, values):
    texture = _texture(albedo) if albedo else None
    size = _alpha(*texture).size if texture else (1, 1)
    unsafe = []
    for destination, source in copies:
        x, y, w, h = map(int, source)
        if not _opaque(_texture(motion), (x, y, x+w, y+h)):
            unsafe.append(destination)
    for i in range(0, len(values), 12):
        x0, y0, u0, v0, x1, y1, u1, v1, x2, y2, u2, v2 = values[i:i+12]
        u_min, v_min = min(u0, u1, u2), min(v0, v1, v2)
        u_max, v_max = max(u0, u1, u2), max(v0, v1, v2)
        if any(u_max*256 >= x and u_min*256 < x+w and v_max*256 >= y and v_min*256 < y+h
               for x, y, w, h in unsafe):
            continue
        if texture:
            width, height = size
            # Include both neighbouring texels used by a linear sample.
            box = (
                max(0, min(width-1, floor(u_min*width-0.5))),
                max(0, min(height-1, floor(v_min*height-0.5))),
                max(1, min(width, ceil(u_max*width-0.5)+1)),
                max(1, min(height, ceil(v_max*height-0.5)+1)),
            )
            if not _opaque(texture, box):
                continue
        yield ((x0, y0), (x1, y1), (x2, y2))


def bake(source):
    metadata = {}
    for area, surfaces in source.items():
        triangles = [triangle for surface in surfaces for triangle in _opaque_triangles(*surface)]
        xs, ys = zip(*(point for triangle in triangles for point in triangle))
        left = floor(min(xs)*CELLS_PER_UNIT)-1
        bottom = floor(min(ys)*CELLS_PER_UNIT)-1
        width = ceil(max(xs)*CELLS_PER_UNIT)+1-left
        height = ceil(max(ys)*CELLS_PER_UNIT)+1-bottom
        image = Image.new("L", (width*SAMPLES, height*SAMPLES))
        draw = ImageDraw.Draw(image)
        for triangle in triangles:
            draw.polygon([(x*SCALE-left*SAMPLES, y*SCALE-bottom*SAMPLES) for x, y in triangle], fill=255)
        full = image.resize((width, height), Image.Resampling.BOX).tobytes()
        rows = []
        for y in range(height):
            ends = []
            x = 0
            for opaque, run in groupby(full[y*width:(y+1)*width], lambda pixel: pixel == 255):
                end = x + sum(1 for _ in run)
                if opaque:
                    ends.extend((x, end))
                x = end
            rows.append(ends)
        assert any(rows), f"No opaque coverage in area {area}"
        metadata[area] = [[left, bottom], rows]
    return json.dumps(metadata, separators=(",", ":")) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    intermediate = ROOT / "tools/generated/camera_coverage_source.json"
    result = bake(json.loads(intermediate.read_text(encoding="utf-8")))
    if args.check:
        assert OUTPUT.read_text(encoding="utf-8") == result, "Rebake outdoor camera coverage"
    else:
        OUTPUT.write_text(result, encoding="utf-8")
    print("CAMERA_COVERAGE_BAKED: 14 native scene projections; plaza and beach share one grid")


if __name__ == "__main__":
    main()
