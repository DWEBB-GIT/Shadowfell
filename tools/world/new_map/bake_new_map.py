"""Bake the new map (Dan, 2026-10-28) into the game's terrain format.

Reads heightmap.png, heightmap.json and ground.png beside this script (made
by make_heightmap.py, or touched up by hand) and writes data/terrain/new_map/:

- world.bin: the same tiles as data/terrain/world.bin (see bake_world.py),
  on a 4 m grid centred on 0, 0 (2 x 3 km at 2 m a pixel)
- water.json: the sea at 0 (the river and lakes are ground below it)
- ground.png: ground.png's colours, which the game paints the ground with
- map.jpg: Dan's top-down map, for the world map and the minimap
- map.json: the map's size and where the player starts

Hand edits from the World dock's brushes (data/terrain/new_map/sculpt.json)
are put back on top, so baking again keeps them.

    python3 tools/world/new_map/bake_new_map.py

The game uses this map when Project Settings > shadowfell/world/map is "new"
(the World dock's Map picker sets it).
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import bake_world as bw  # noqa: E402

OUT = os.path.join(bw.ROOT, "data", "terrain", "new_map")
START_PX = (645, 690)  # the river town, in map pixels
# ground.png colour -> surface (bake_world.SURF; the game draws trees and rocks by it)
SURFACE = {
    (120, 176, 60): "meadow", (214, 190, 120): "sand", (104, 104, 118): "rock",
    (222, 236, 244): "snow", (236, 186, 92): "desert", (200, 132, 90): "desert",
    (198, 84, 54): "rock", (138, 66, 50): "rock", (120, 108, 140): "haunted",
    (30, 140, 200): "sea", (10, 60, 110): "sea",
}
STEEP = (0.55, 0.85)  # rise per metre: walkable below the first, blocked above the second


def main():
    meta = json.load(open(os.path.join(HERE, "heightmap.json")))
    hm = np.asarray(Image.open(os.path.join(HERE, "heightmap.png"))).astype(np.float64)
    if hm.ndim == 3:
        hm = hm[..., 0]
    top = 65535.0 if hm.max() > 255 else 255.0
    hm = meta["min"] + hm / top * (meta["max"] - meta["min"])
    ground = np.asarray(Image.open(os.path.join(HERE, "ground.png")).convert("RGB"))
    px = meta["metresPerPixel"]
    ny, nx = hm.shape
    sx, sz = nx * px, ny * px
    C = bw.CELL
    g = bw.Grid(-sx / 2, -sz / 2, int(sx / C) + 1, int(sz / C) + 1)
    # sample the heightmap at every grid point (pixel centres sit half a pixel in)
    ci = (g.X - g.x0) / px - 0.5
    cj = (g.Z - g.z0) / px - 0.5
    J, I = np.meshgrid(cj, ci, indexing="ij")
    height = ndi.map_coordinates(hm, [J, I], order=1, mode="nearest")
    gi = np.clip(np.round(I).astype(int), 0, nx - 1)
    gj = np.clip(np.round(J).astype(int), 0, ny - 1)
    cols = np.array(list(SURFACE), np.int32)
    names = list(SURFACE.values())
    near = np.argmin(((ground[gj, gi][:, :, None, :].astype(np.int32) - cols[None, None]) ** 2).sum(-1), -1)
    surf = np.array([bw.SURF[names[k]] for k in range(len(names))], np.uint8)[near]

    dz, dx = np.gradient(height, C)
    slope = np.hypot(dx, dz)
    block = bw.smoothstep(STEEP[0], STEEP[1], slope)
    block = np.where(height > 0.25, block, 1.0)
    surf[height <= 0.25] = bw.SURF["sea"]
    bw.apply_sculpt(g, height, block, surf, os.path.join(OUT, "sculpt.json"))
    walk = np.clip(1 - block, 0, 1)
    zone = np.zeros(height.shape, np.uint8)
    tx, tz, n, size = bw.write_world(os.path.join(OUT, "world.bin"), g, height, walk, surf, zone)

    with open(os.path.join(OUT, "water.json"), "w") as f:
        json.dump({"_about": "Baked by tools/world/new_map/bake_new_map.py: the sea is at 0; the river and lakes are ground below it. Do not edit by hand.",
                   "sea": 0.0, "rivers": [], "lakes": []}, f, separators=(",", ":"))
    shutil.copyfile(os.path.join(HERE, "ground.png"), os.path.join(OUT, "ground.png"))
    Image.open(os.path.join(HERE, "source", "build-map.png")).convert("RGB").save(os.path.join(OUT, "map.jpg"), quality=88)
    start = [round(g.x0 + (START_PX[0] + 0.5) * px, 1), round(g.z0 + (START_PX[1] + 0.5) * px, 1)]
    with open(os.path.join(OUT, "map.json"), "w") as f:
        json.dump({"_about": "The new map (Dan, 2026-10-28), baked by tools/world/new_map/bake_new_map.py. x0/z0: the north-west corner in metres; sizeX/sizeZ: its size; start: where the player starts [x, z].",
                   "x0": g.x0, "z0": g.z0, "sizeX": sx, "sizeZ": sz, "start": start}, f, indent=2)
    land = height > 0.25
    print("new map %.0f x %.0f m: tiles %d x %d, %d with land, %.2f MB; walkable %.0f%% of land; start %s"
          % (sx, sz, tx, tz, n, size / 1e6, 100 * (walk > 0.5).sum() / max(1, land.sum()), start))


if __name__ == "__main__":
    main()
