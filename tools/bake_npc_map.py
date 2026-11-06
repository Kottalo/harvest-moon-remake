"""Bake top-down walkable silhouettes from the existing location geometry."""
import argparse
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
TILE = 160
COLUMNS = 8


def bake():
    areas = json.loads((ROOT / "game/world/location_catalog.json").read_text(encoding="utf-8"))
    atlas = Image.new("RGBA", (COLUMNS*TILE, ((len(areas)+COLUMNS-1)//COLUMNS)*TILE))
    metadata = {}
    for index, (area, info) in enumerate(areas.items()):
        source = json.loads((ROOT / info["source_json"][6:]).read_text(encoding="utf-8"))
        triangles = []
        for surface in source["surfaces"]:
            vertices = surface["vertices"]
            for i, flags in enumerate(surface["primitive_flags"]):
                if flags & 0xE080 == 0:
                    face = vertices[i*9:i*9+9]
                    triangles.append(list(zip(face[0::3], face[2::3])))
        assert triangles, info["slug"]
        xs, zs = zip(*(point for triangle in triangles for point in triangle))
        edge = max(max(xs)-min(xs), max(zs)-min(zs), 0.1)*1.10
        left = (max(xs)+min(xs)-edge)/2
        top = (max(zs)+min(zs)-edge)/2
        mask = Image.new("RGBA", (TILE,TILE))
        draw = ImageDraw.Draw(mask)
        for triangle in triangles:
            draw.polygon([((x-left)*TILE/edge,(z-top)*TILE/edge) for x,z in triangle], fill="#426858")
        x, y = (index%COLUMNS)*TILE, (index//COLUMNS)*TILE
        atlas.paste(mask, (x,y))
        metadata[area] = {"tile":[x,y,TILE,TILE], "bounds":[left,top,edge]}
    return atlas, metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    atlas, metadata = bake()
    payload = io.BytesIO()
    atlas.save(payload, format="PNG")
    folder = ROOT / "game/npc"
    outputs = {
        folder/"npc_map_atlas.png": payload.getvalue(),
        folder/"npc_map_shapes.json": (json.dumps(metadata,separators=(",",":"))+"\n").encode(),
    }
    for path, data in outputs.items():
        if args.check:
            assert path.read_bytes()==data, path
        else:
            path.write_bytes(data)
    print(f"NPC_MAP_ATLAS_OK: {len(metadata)} walkable silhouettes")


if __name__ == "__main__":
    main()
