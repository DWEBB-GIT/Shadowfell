"""Make the new map's heightmap and ground map from Dan's painted map.

Reads source/biome-control.png (Dan's map, one colour per kind of ground) and
source/height-reference.png (his shaded relief, used only for the shape of
the peaks), both 1024 x 1536 at 2 m a pixel. Writes, beside this script:

- heightmap.png: 16-bit greyscale, black = heightmap.json `min`, white = `max`
  (metres; sea level is 0). Edit it in any image editor that keeps 16 bits.
- ground.png: the kind of ground everywhere, in the GROUND colours below.
  Paint it with those exact colours to change the ground.
- heightmap.json: the height range and scale.

Only Dan's drawing is used (Dan, 2026-10-28): no old towns, roads or zones.
Trees and bridges are not ground: forest is plain grass, and water runs on
under bridges and docks. Buildings drawn on the map (flats.json) are levelled
so they can be built on. Then bake it into the game:

    python3 tools/world/new_map/make_heightmap.py
    python3 tools/world/new_map/bake_new_map.py

Needs numpy, scipy and pillow.
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
PX = 2.0  # metres per pixel

# Dan's painted colours -> kind of ground (found by clustering his map)
PAINT = [
    ((38, 82, 41), "grass"),  # forest: trees come later, the ground is grass
    ((149, 189, 38), "grass"), ((248, 201, 118), "path"),
    ((92, 94, 113), "mountain"), ((215, 238, 247), "snow"),
    ((250, 192, 76), "desert"), ((202, 134, 92), "redrock_low"),
    ((208, 81, 52), "redrock"), ((137, 63, 49), "redrock_high"),
    ((149, 135, 168), "haunted"),
    ((1, 58, 109), "sea"), ((37, 131, 180), "water"), ((5, 174, 237), "water"),
    ((112, 210, 243), "shallows"),  # surf round the coast; ice in the snow
]
# kind -> height of open ground there (m), and its colour in ground.png
GROUND = {
    "grass": (3.0, (120, 176, 60)), "path": (3.0, (214, 190, 120)),
    "mountain": (34.0, (104, 104, 118)), "snow": (16.0, (222, 236, 244)),
    "desert": (2.5, (236, 186, 92)), "redrock_low": (8.0, (200, 132, 90)),
    "redrock": (16.0, (198, 84, 54)), "redrock_high": (22.0, (138, 66, 50)),
    "haunted": (4.0, (120, 108, 140)), "water": (-2.0, (30, 140, 200)),
    "sea": (-8.0, (10, 60, 110)),
}
KINDS = list(GROUND)
HIGH = {"mountain", "redrock", "redrock_high", "snow"}  # where the peaks' detail goes


def main():
    bio = np.asarray(Image.open(os.path.join(HERE, "source", "biome-control.png")).convert("RGB")).astype(np.float32)
    shade = np.asarray(Image.open(os.path.join(HERE, "source", "height-reference.png")).convert("L")).astype(np.float32) / 255
    ny, nx = bio.shape[:2]
    pal = np.array([c for c, _ in PAINT], np.float32)
    near = np.argmin(((bio[:, :, None, :] - pal[None, None]) ** 2).sum(-1), -1)
    names = [k for _, k in PAINT]
    north_ice = np.zeros((ny, nx), bool)
    kind = np.zeros((ny, nx), np.int16)
    for i, k in enumerate(names):
        if k == "shallows":
            continue
        kind[near == i] = KINDS.index(k)
    # pale blue is ice in the snowy north, surf everywhere else
    pale = near == names.index("shallows")
    snow_near = ndi.uniform_filter((near == names.index("snow")).astype(np.float32), 61) > 0.15
    north_ice = pale & snow_near
    kind[north_ice] = KINDS.index("snow")
    kind[pale & ~north_ice] = KINDS.index("water")
    # small painted bits (houses, towers, palms, signs) take the ground round them
    kind = majority(kind, 5)
    for k in ("mountain", "redrock_high", "redrock", "redrock_low", "snow"):
        m = kind == KINDS.index(k)
        lab, n = ndi.label(m)
        if n:
            size = ndi.sum(m, lab, np.arange(1, n + 1))
            small = np.isin(lab, np.nonzero(size < 140)[0] + 1)
            kind[small] = -1
    fill_from_neighbours(kind)
    # roofs, ships and carts are painted in the red rock's colours: red rock
    # standing alone in green land or water is a building or a ship, so it
    # takes that ground (in the desert it is a real outcrop and stays)
    red = np.isin(kind, [KINDS.index(k) for k in ("redrock_low", "redrock", "redrock_high")])
    lab, n = ndi.label(red)
    for i, sl in enumerate(ndi.find_objects(lab)):
        sl = tuple(slice(max(0, s.start - 4), s.stop + 4) for s in sl)
        blob = lab[sl] == i + 1
        if blob.sum() > 3000:
            continue
        ring = ndi.binary_dilation(blob, iterations=3) & ~red[sl]
        if ring.sum() and ring.sum() > 0.6 * (ndi.binary_dilation(blob, iterations=3) & ~blob).sum():
            k = np.bincount(kind[sl][ring]).argmax()
            if KINDS[k] != "desert":
                kind[sl][blob] = k

    # water runs on under bridges and docks
    wet = np.isin(kind, [KINDS.index("water"), KINDS.index("sea")])
    closed = ndi.binary_closing(wet, structure=disk(5), iterations=1) & ~wet
    kind[closed & (kind != KINDS.index("mountain"))] = KINDS.index("water")
    wet = np.isin(kind, [KINDS.index("water"), KINDS.index("sea")])

    # buildings drawn on the map are levelled
    with open(os.path.join(HERE, "flats.json")) as f:
        flats = json.load(f)["flats"]
    yy, xx = np.mgrid[0:ny, 0:nx]
    flat_ids = np.full((ny, nx), -1, np.int16)
    for i, fl in enumerate(flats):
        cx, cy, rx, ry = fl["oval"]
        d = np.hypot((xx - cx) / rx, (yy - cy) / ry)
        inside = (d < 1) & ~wet
        kind[inside] = KINDS.index(fl["ground"])
        flat_ids[inside] = i

    base = np.array([GROUND[k][0] for k in KINDS], np.float32)[kind]
    height = ndi.gaussian_filter(base, 3.0)
    high = ndi.gaussian_filter(np.isin(kind, [KINDS.index(k) for k in HIGH]).astype(np.float32), 4)
    detail = ndi.gaussian_filter(shade - ndi.gaussian_filter(shade, 6), 1.2)
    height += high * detail * 60
    # the open sea falls away from the coast
    d_land = ndi.distance_transform_edt(wet) * PX
    sea = kind == KINDS.index("sea")
    height = np.where(sea, np.minimum(height, -2 - np.minimum(d_land, 200) / 25), height)
    height = np.where(wet, np.minimum(height, -1.5), height)
    # land comes down to the water's edge
    d_wet = ndi.distance_transform_edt(~wet) * PX
    coast = np.clip(d_wet / 16, 0, 1)
    height = np.where(wet, height, np.maximum(0.6, 0.6 + (height - 0.6) * np.minimum(1, coast + high * 0.6)))
    # level each flat at the height of its own middle
    for i, fl in enumerate(flats):
        m = flat_ids == i
        if m.any():
            lv = float(np.median(height[m]))
            cx, cy, rx, ry = fl["oval"]
            d = np.hypot((xx - cx) / rx, (yy - cy) / ry)
            w = np.clip((1.15 - d) / 0.3, 0, 1) * ~wet
            height = height + (max(lv, 1.0) - height) * w

    lo, hi = float(np.floor(height.min())), float(np.ceil(height.max()))
    q = np.clip((height - lo) / (hi - lo) * 65535, 0, 65535).round().astype(np.uint16)
    Image.fromarray(q).save(os.path.join(HERE, "heightmap.png"))
    rgb = np.array([GROUND[k][1] for k in KINDS], np.uint8)[kind]
    Image.fromarray(rgb).save(os.path.join(HERE, "ground.png"))
    with open(os.path.join(HERE, "heightmap.json"), "w") as f:
        json.dump({"_about": "heightmap.png: black = min, white = max, in metres above the sea (0). metresPerPixel: the map's scale.",
                   "min": lo, "max": hi, "metresPerPixel": PX, "width": nx, "height": ny}, f, indent=2)
    print("heightmap %d x %d, %.0f .. %.0f m" % (nx, ny, lo, hi))


def disk(r):
    y, x = np.mgrid[-r: r + 1, -r: r + 1]
    return x * x + y * y <= r * r


def majority(kind, size):
    """each pixel takes the kind most common round it"""
    best = np.zeros(kind.shape, np.float32)
    out = kind.copy()
    for k in np.unique(kind):
        c = ndi.uniform_filter((kind == k).astype(np.float32), size)
        better = c > best
        out[better] = k
        best[better] = c[better]
    return out


def fill_from_neighbours(kind):
    hole = kind < 0
    if hole.any():
        _, (ii, jj) = ndi.distance_transform_edt(hole, return_indices=True)
        kind[hole] = kind[ii[hole], jj[hole]]


if __name__ == "__main__":
    main()
