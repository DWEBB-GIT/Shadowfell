"""Bake the whole world's ground from data/world_map.json.

Writes data/terrain/world.bin: heights, walkable ground and surface/zone codes
on a 4 m grid, cut into 128 m tiles (33 x 33 samples, edges shared), each
tile zlib-compressed so the game unpacks only the tiles near a player.

world.bin: header "SFW1", version, x0, z0, cell, sea floor (f32 x4), tile
cells, tiles across, tiles down (u32 x3); then per tile (row by row) the byte
offset and length of its blob (0, 0 = open sea). A blob unpacks to 33 x 33
int16 heights (in 5 cm steps above -50 m, stored as differences along x then
along z), 33 x 33 walk bytes (255 = open ground, below 128 = blocked) and
33 x 33 info bytes (low 4 bits surface, high 4 bits zone index).
Also writes data/terrain/water.json (sea level, river ribbons, lakes) and a
preview picture to tools/world/preview.png (not kept in git).

    python3 tools/world/bake_world.py

Needs numpy, scipy and pillow. The game reads the output; it never runs this.

How the ground is shaped (Dan's rules: zones are walkable pockets with high
ground between, joined by a few set routes; Act 1 is enclosed and confined):
- the world: land from the coast and islands; each zone has a base height
  from its biome; zone borders rise into high ground; painted rock, snow and
  volcanic outlines and the peaks are mountains; the Greyspine (spine) and the
  Northwall are ridges; rough outcrops break up big open zones; routes cut
  walkable passes through all of it.
- Act 1 (inside world.act1Box): the detailed layout. Pockets and road
  corridors are walkable, everything else is zone-themed high ground; named
  ranges are mountains; the River Bracken and the Mere block except at fords.
"""
import json
import os
import struct
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CELL = 4.0
TILE = 32  # cells per tile side (128 m)
SEA_FLOOR = -12.0

# zone surface codes (the low 4 bits of a sample's info byte; the game colours by them)
SURF = {"sea": 0, "meadow": 1, "marsh": 2, "downs": 3, "blackwood": 4, "rock": 5, "moor": 6,
        "sand": 7, "farmland": 8, "forest": 9, "snow": 10, "desert": 11, "ash": 12,
        "swamp": 13, "jungle": 14, "haunted": 15}
BIOME = {  # zone biome -> (base height m, surface)
    "temperate": (6, "meadow"), "shore": (3, "sand"), "farmland": (8, "farmland"),
    "forest": (10, "forest"), "marsh": (2, "marsh"), "swamp": (1.5, "swamp"),
    "moor": (22, "moor"), "haunted": (14, "haunted"), "rocky": (30, "rock"),
    "desert": (12, "desert"), "sandy": (4, "sand"), "jungle": (8, "jungle"),
    "snow": (45, "snow"), "volcanic": (35, "ash"),
}
ACT1_REGION = {  # region -> (base height, high ground rise, surface)
    "bracken_vale": (4, 16, "meadow"), "stillwater": (2.5, 7, "marsh"),
    "sallow_downs": (20, 14, "downs"), "blackwood": (16, 15, "blackwood"),
    "hallow_cut": (44, 22, "rock"), "barrow_fields": (34, 14, "moor"),
}
ROUTE_HALF = {"road": 9, "track": 7, "tunnel": 5}


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def load():
    with open(os.path.join(ROOT, "data", "world_map.json")) as f:
        return json.load(f)


class Grid:
    def __init__(self, x0, z0, nx, nz):
        self.x0, self.z0, self.nx, self.nz = x0, z0, nx, nz
        self.X = x0 + np.arange(nx) * CELL
        self.Z = z0 + np.arange(nz) * CELL

    def px(self, p, off=(0, 0)):
        return ((p[0] + off[0] - self.x0) / CELL, (p[1] + off[1] - self.z0) / CELL)

    def polys(self, polys, off=(0, 0)):
        im = Image.new("L", (self.nx, self.nz), 0)
        d = ImageDraw.Draw(im)
        for poly in polys:
            d.polygon([self.px(p, off) for p in poly], fill=255)
        return np.asarray(im) > 0

    def lines(self, lines, off=(0, 0)):
        im = Image.new("L", (self.nx, self.nz), 0)
        d = ImageDraw.Draw(im)
        for line in lines:
            pts = [self.px(p, off) for p in line]
            if len(pts) == 1:
                d.point(pts, fill=255)
            else:
                d.line(pts, fill=255, width=1)
        return np.asarray(im) > 0

    def dist_to(self, mask):
        """metres from every sample to the nearest set sample"""
        if not mask.any():
            return np.full(mask.shape, 1e6)
        return ndi.distance_transform_edt(~mask) * CELL

    def sdist(self, inside):
        """signed metres: positive inside the mask, negative outside"""
        return ndi.distance_transform_edt(inside) * CELL - ndi.distance_transform_edt(~inside) * CELL

    def circle_dist(self, cx, cz):
        return np.hypot(self.X[None, :] - cx, self.Z[:, None] - cz)


def noise(shape, scale_cells, seed):
    """smooth value noise in about -1..1 with features `scale_cells` across"""
    rng = np.random.default_rng(seed)
    cz = max(2, int(shape[0] / scale_cells) + 3)
    cx = max(2, int(shape[1] / scale_cells) + 3)
    coarse = rng.uniform(-1, 1, (cz, cx))
    big = ndi.zoom(coarse, (shape[0] / (cz - 3) + 0.01, shape[1] / (cx - 3) + 0.01), order=3)
    return np.clip(big[: shape[0], : shape[1]], -1.2, 1.2)


def fbm(shape, scale_cells, seed, octaves=3):
    out = np.zeros(shape)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += noise(shape, max(2, scale_cells / (2 ** o)), seed + o) * amp
        total += amp
        amp *= 0.5
    return out / total


def densify(line, step):
    out = []
    for a, b in zip(line, line[1:]):
        n = max(1, int(np.hypot(b[0] - a[0], b[1] - a[1]) / step))
        out += [[a[0] + (b[0] - a[0]) * t / n, a[1] + (b[1] - a[1]) * t / n] for t in range(n)]
    return out + [line[-1]]


def island_poly(isl):
    if isl.get("poly"):
        return isl["poly"]
    x, z = isl["at"]
    r = isl["r"]
    return [[x + r * np.cos(a), z + r * np.sin(a)] for a in np.linspace(0, 2 * np.pi, 24, endpoint=False)]


def bake_world(M, g):
    """heights, block (0 walkable .. 1 blocked), surface and zone over the whole world"""
    W, T = M["world"], M["terrain"]
    shape = (g.nz, g.nx)
    land = g.polys([W["coast"]] + [island_poly(i) for i in W["islands"]])
    zones = W["zones"]
    zid = np.full(shape, -1, np.int16)
    for k, z in enumerate(zones):
        if z.get("poly"):
            zid[g.polys([z["poly"]]) & land] = k
    bx, bz, bw, bh = W["act1Box"]
    box = np.zeros(shape, bool)
    i0, j0 = int((bx - g.x0) / CELL), int((bz - g.z0) / CELL)
    box[j0: j0 + int(bh / CELL) + 1, i0: i0 + int(bw / CELL) + 1] = True
    bracken = next(k for k, z in enumerate(zones) if z["id"] == "bracken")
    zid[box & land & (zid < 0)] = bracken
    # land in no zone takes the nearest zone's
    known = zid >= 0
    _, (ii, jj) = ndi.distance_transform_edt(~known, return_indices=True)
    zid = np.where(land, zid[ii, jj], -1)

    base = np.zeros(shape)
    surf = np.zeros(shape, np.uint8)
    for k, z in enumerate(zones):
        h, s = BIOME.get(z["biome"], (6, "meadow"))
        base[zid == k] = h
        surf[zid == k] = SURF[s]
    for isl in W["islands"]:  # islands keep their painted biome
        m = g.polys([island_poly(isl)])
        h, s = BIOME.get(isl["biome"], (6, "meadow"))
        base[m] = h
        surf[m] = SURF[s]
    base = ndi.gaussian_filter(base, 18)
    ter = T["terrain"]
    forest = g.polys(ter.get("forest", []))
    moor = g.polys(ter.get("moor", []))
    surf[forest & land] = SURF["forest"]
    surf[moor & land] = SURF["moor"]
    base += ndi.gaussian_filter(moor * 8.0, 6)
    base += fbm(shape, 150, 11) * 6 + fbm(shape, 30, 21) * 2

    d_sea = g.dist_to(~land)
    d_land = g.dist_to(land)

    # routes and the clearings round settlements and landmarks stay open
    route_open = np.zeros(shape)
    for r in W["routes"]:
        if r["kind"] == "boat":
            continue
        hw = ROUTE_HALF.get(r["kind"], 7)
        d = g.dist_to(g.lines([r["line"]]))
        route_open = np.maximum(route_open, 1 - smoothstep(hw, hw + 14, d))
    spots = [s["at"] for s in W["settlements"]] + [l["at"] for l in W["landmarks"]]
    # every settlement has a track to the nearest route
    pts = np.array([p for r in W["routes"] if r["kind"] != "boat" for p in densify(r["line"], 16)])
    spurs = []
    for st in W["settlements"]:
        k = np.argmin(np.hypot(pts[:, 0] - st["at"][0], pts[:, 1] - st["at"][1]))
        spurs.append([st["at"], pts[k].tolist()])
    d = g.dist_to(g.lines(spurs))
    route_open = np.maximum(route_open, 1 - smoothstep(5, 16, d))
    d_spot = g.dist_to(g.lines([[p] for p in spots]))
    spot_open = 1 - smoothstep(45, 70, d_spot)
    opened = np.maximum(route_open, spot_open)

    # zone borders rise into high ground
    border = np.full(shape, 1e6)
    for k in range(len(zones)):
        inside = zid == k
        if not inside.any():
            continue
        other = land & (zid != k)
        d = g.dist_to(other)
        border = np.where(inside, d, border)
    b_border = 1 - smoothstep(14, 34, border)
    rise = b_border * (26 + fbm(shape, 40, 31) * 6)

    # mountains: painted rock/snow/volcanic outlines, peaks, the spine and the Northwall
    mount = g.polys(ter.get("rock", []) + ter.get("snow", []) + ter.get("volcanic", []))
    snowy = g.polys(ter.get("snow", []))
    volc = g.polys(ter.get("volcanic", []))
    d_in = ndi.distance_transform_edt(mount) * CELL
    b_mount = smoothstep(0, 20, d_in)
    m_h = smoothstep(0, 40, d_in) * (34 + np.minimum(d_in, 400) * 0.12) * (1 + fbm(shape, 25, 41) * 0.25)
    peaks = np.zeros(shape)
    for x, z, kind in T["peaks"]:
        h, r = {"s": (90, 75), "v": (80, 70)}.get(kind, (65, 60))
        ci, cj = int((x - g.x0) / CELL), int((z - g.z0) / CELL)
        n = int(r / CELL) + 1
        a0, a1 = max(0, cj - n), min(g.nz, cj + n + 1)
        c0, c1 = max(0, ci - n), min(g.nx, ci + n + 1)
        if a0 >= a1 or c0 >= c1:
            continue
        d = np.hypot(g.X[None, c0:c1] - x, g.Z[a0:a1, None] - z)
        cone = h * np.clip(1 - d / r, 0, 1) ** 1.4
        peaks[a0:a1, c0:c1] = np.maximum(peaks[a0:a1, c0:c1], cone)
    ridge_lines = [W["spine"], W["northwall"]] + ([W["ribs"]["line"]] if W.get("ribs") else [])
    d_ridge = g.dist_to(g.lines(ridge_lines))
    ridge = (1 - smoothstep(10, 70, d_ridge)) * (85 + fbm(shape, 30, 51) * 15)
    b_peak = smoothstep(12, 30, peaks)
    b_ridge = 1 - smoothstep(30, 50, d_ridge)

    # rough outcrops break up big open zones, away from routes and settlements
    out_n = fbm(shape, 40, 61, octaves=4)
    b_out = smoothstep(0.14, 0.26, out_n) * smoothstep(50, 110, border)
    out_h = b_out * (12 + out_n * 10)

    # rivers: shallow beds, blocked except where a route fords them
    d_riv = g.dist_to(g.lines([r["line"] for r in W["rivers"]]))
    carve = 2.5 * (1 - smoothstep(5, 12, d_riv))
    b_riv = 1 - smoothstep(5, 7, d_riv)

    keep = 1 - opened
    keep_r = 1 - route_open
    height = base + (rise + m_h * keep + peaks * keep + ridge * keep_r + out_h) * keep - carve
    block = np.maximum.reduce([b_border, b_mount, b_peak, b_ridge * np.ones(shape), b_out, b_riv]) * keep
    block = np.maximum(block, b_ridge * keep_r)
    # the coast: land eases down to a beach; the sea floor falls away
    coast_k = smoothstep(0, 140, d_sea)
    height = np.where(land, 0.8 + (height - 0.8) * coast_k, -2 - np.minimum(d_land, 250) / 25)
    block = np.where(land & (height > 0.25), block, 1.0)
    surf[(land & (d_sea < 18)) & (surf != SURF["snow"])] = SURF["sand"]
    rocky = (m_h * keep > 18) | (peaks * keep > 20) | (ridge * keep_r > 30)
    surf[rocky & land] = SURF["rock"]
    surf[(snowy | ((peaks > 60) & rocky)) & land] = SURF["snow"]
    surf[volc & land] = SURF["ash"]
    surf[~land] = SURF["sea"]
    zone = np.where(zid < 0, 0, zid).astype(np.uint8)
    return height, block, surf, zone, box


def bake_act1(M, g, height, block, surf, box):
    """overwrite the Act 1 box with the detailed layout, blended at its edge"""
    W, A = M["world"], M["act1"]
    off = W["act1Offset"]
    bx, bz, bw, bh = W["act1Box"]
    j0, i0 = int((bz - g.z0) / CELL), int((bx - g.x0) / CELL)
    nz, nx = int(bh / CELL) + 1, int(bw / CELL) + 1
    sub = Grid(bx, bz, nx, nz)
    shape = (nz, nx)
    regions = A["regions"]
    rid = np.full(shape, -1, np.int16)
    for k, r in enumerate(regions):
        rid[sub.polys([r["poly"]], off)] = k
    _, (ii, jj) = ndi.distance_transform_edt(rid < 0, return_indices=True)
    rid = rid[ii, jj]
    base = np.zeros(shape)
    rise_h = np.zeros(shape)
    s = np.zeros(shape, np.uint8)
    for k, r in enumerate(regions):
        b, h, sf = ACT1_REGION.get(r["id"], (6, 14, "meadow"))
        base[rid == k] = b
        rise_h[rid == k] = h
        s[rid == k] = SURF[sf]
    base = ndi.gaussian_filter(base, 10)
    rise_h = ndi.gaussian_filter(rise_h, 6)
    base += fbm(shape, 40, 71) * 1.6 + fbm(shape, 10, 81) * 0.5
    for hl in A["hills"]:
        d = sub.circle_dist(hl["at"][0] + off[0], hl["at"][1] + off[1])
        base += hl["h"] * np.exp(-((d / (hl["r"] * 0.6)) ** 2))

    # walkable pockets and road corridors
    walk = np.zeros(shape)
    for p in A["pockets"]:
        if "poly" in p:
            sd = sub.sdist(sub.polys([p["poly"]], off))
        elif "ellipse" in p:
            cx, cz, rx, rz = p["ellipse"]
            dx = (sub.X[None, :] - cx - off[0]) / rx
            dz = (sub.Z[:, None] - cz - off[1]) / rz
            sd = (1 - np.sqrt(dx * dx + dz * dz)) * min(rx, rz)
        else:
            sd = p["r"] - sub.circle_dist(p["at"][0] + off[0], p["at"][1] + off[1])
        walk = np.maximum(walk, smoothstep(-6, 6, sd))
    road_d = np.full(shape, 1e6)
    for r in A["roads"]:
        hw = A["corridor"].get(r["kind"], 10)
        d = sub.dist_to(sub.lines([r["line"]], off))
        walk = np.maximum(walk, 1 - smoothstep(hw - 6, hw + 6, d))
        if r["kind"] != "intro":
            road_d = np.minimum(road_d, d)
    for r in W["routes"]:  # the world's routes leave Act 1 by these
        if r["kind"] == "boat":
            continue
        d = sub.dist_to(sub.lines([r["line"]]))
        walk = np.maximum(walk, 1 - smoothstep(6, 18, d))
        road_d = np.minimum(road_d, d)
    # POIs always stand on reachable ground
    poi_d = sub.dist_to(sub.lines([[[p["at"][0] + off[0], p["at"][1] + off[1]]] for p in A["pois"]]))
    walk = np.maximum(walk, 1 - smoothstep(10, 22, poi_d))
    blk = 1 - walk
    h = base + blk * rise_h * (0.75 + fbm(shape, 12, 91) * 0.35)
    # named ranges
    for m in A["mountains"]:
        d = sub.dist_to(sub.lines([m["line"]], off))
        w = m["w"]
        k = 1 - smoothstep(w * 0.25, w * 0.75, d)
        h += k * (55 + fbm(shape, 15, 101) * 12) * (1 - walk)
        blk = np.maximum(blk, (1 - smoothstep(w * 0.3, w * 0.5, d)) * (1 - (walk > 0.95)))
        s[(k > 0.4) & (walk < 0.5)] = SURF["rock"]
    # water: the river and streams carve beds; the river and the mere block
    water = {"rivers": [], "lakes": []}
    for wt in A["water"]:
        if wt["kind"] == "lake":
            cx, cz = wt["center"][0] + off[0], wt["center"][1] + off[1]
            dx = (sub.X[None, :] - cx) / wt["rx"]
            dz = (sub.Z[:, None] - cz) / wt["rz"]
            e = np.sqrt(dx * dx + dz * dz)
            k = 1 - smoothstep(0.85, 1.0, e)
            level = float(np.median(h[(e > 1.0) & (e < 1.15)])) - 0.6
            h = h * (1 - k) + (level - 3.0) * k
            blk = np.maximum(blk, 1 - smoothstep(0.9, 0.97, e))
            water["lakes"].append({"id": wt["id"], "name": wt["name"], "center": [cx, cz], "rx": wt["rx"], "rz": wt["rz"], "level": round(level, 2)})
            continue
        line = [[p[0] + off[0], p[1] + off[1]] for p in wt["line"]]
        d = sub.dist_to(sub.lines([line]))
        half = wt["width"] / 2
        depth = 2.4 if wt["kind"] == "river" else 1.1
        bed = 1 - smoothstep(half - 1, half + 3, d)
        water["rivers"].append({"id": wt["id"], "name": wt["name"], "width": wt["width"], "line": line, "depth": depth})
        h = h - depth * bed
        if wt["kind"] == "river":
            ford = 1 - smoothstep(3, 6, road_d)
            blk = np.maximum(blk, (1 - smoothstep(half - 2, half, d)) * (1 - ford))
    # blend into the world at the box edge (60 m)
    ei = np.minimum(np.arange(nx), np.arange(nx)[::-1]) * CELL
    ej = np.minimum(np.arange(nz), np.arange(nz)[::-1]) * CELL
    edge = np.minimum(ei[None, :], ej[:, None])
    a = smoothstep(0, 60, edge)
    wh = height[j0: j0 + nz, i0: i0 + nx]
    wb = block[j0: j0 + nz, i0: i0 + nx]
    ws = surf[j0: j0 + nz, i0: i0 + nx]
    land = wh > 0.25
    hh = np.where(land, wh * (1 - a) + h * a, wh)
    # Act 1 is enclosed by its own high ground, and the world's zone border
    # rises just outside the box; the routes are open on both sides
    bb = np.where(land, blk, 1.0)
    height[j0: j0 + nz, i0: i0 + nx] = hh
    block[j0: j0 + nz, i0: i0 + nx] = bb
    surf[j0: j0 + nz, i0: i0 + nx] = np.where(land & (a > 0.5), s, ws)
    return water


def river_levels(water, height, g, M):
    """world rivers too, and a level along every river (its banks, less a little)"""
    for r in M["world"]["rivers"]:
        water["rivers"].append({"id": r["name"].lower().replace(" ", "_"), "name": r["name"], "width": 10, "line": r["line"], "depth": 2.5})
    for r in water["rivers"]:
        pts = []
        line = r["line"]
        for a, b in zip(line, line[1:]):
            n = max(1, int(np.hypot(b[0] - a[0], b[1] - a[1]) / 8))
            for t in range(n):
                pts.append([a[0] + (b[0] - a[0]) * t / n, a[1] + (b[1] - a[1]) * t / n])
        pts.append(line[-1])
        out = []
        for x, z in pts:
            i, j = int(round((x - g.x0) / CELL)), int(round((z - g.z0) / CELL))
            if 0 <= i < g.nx and 0 <= j < g.nz:
                win = height[max(0, j - 4): j + 5, max(0, i - 4): i + 5]
                lv = float(np.percentile(win, 70)) - 0.5
            else:
                lv = 0.0
            out.append([round(x, 1), round(z, 1), round(max(lv, 0.05), 2)])
        # water never runs uphill: levels fall along the flow
        for k in range(1, len(out)):
            out[k][2] = min(out[k][2], out[k - 1][2])
        r["points"] = out
        del r["line"]
    return water


def reachable(walk, g, start):
    lab, _ = ndi.label(walk)
    i, j = int((start[0] - g.x0) / CELL), int((start[1] - g.z0) / CELL)
    return lab == lab[j, i]


def main():
    M = load()
    W = M["world"]
    sx, sz = W["sizeX"], W["sizeZ"]
    g = Grid(-sx / 2, W["originZ"] - sz / 2, int(sx / CELL) + 1, int(sz / CELL) + 1)
    height, block, surf, zone, box = bake_world(M, g)
    water = bake_act1(M, g, height, block, surf, box)
    water = river_levels(water, height, g, M)
    water["sea"] = 0.0
    walk = np.clip(1 - block, 0, 1)
    walk_b = (walk * 255).round().astype(np.uint8)
    hq = np.clip((height + 50) * 20, 0, 65535).round().astype(np.int32)  # 5 cm steps
    info = (surf & 15) | (zone.astype(np.uint8) << 4)

    tx = (g.nx - 1 + TILE - 1) // TILE
    tz = (g.nz - 1 + TILE - 1) // TILE
    n = TILE + 1
    blobs, index = [], []
    pos = 0
    for j in range(tz):
        for i in range(tx):
            a0, c0 = j * TILE, i * TILE
            hs = np.full((n, n), hq.min(), np.int32)
            ws = np.zeros((n, n), np.uint8)
            fs = np.zeros((n, n), np.uint8)
            hb = hq[a0: a0 + n, c0: c0 + n]
            hs[: hb.shape[0], : hb.shape[1]] = hb
            ws[: hb.shape[0], : hb.shape[1]] = walk_b[a0: a0 + n, c0: c0 + n]
            fs[: hb.shape[0], : hb.shape[1]] = info[a0: a0 + n, c0: c0 + n]
            if ws.max() == 0 and (hs.astype(float) / 20 - 50).max() < -1.0:
                index.append((0, 0))  # open sea: the game uses a flat sea floor
                continue
            # heights as differences of differences (smooth ground packs small)
            dx = np.diff(hs, axis=1, prepend=0)
            dd = np.diff(dx, axis=0, prepend=0)
            raw = dd.astype("<i2").tobytes() + ws.tobytes() + fs.tobytes()
            blob = zlib.compress(raw, 9)
            index.append((pos, len(blob)))
            blobs.append(blob)
            pos += len(blob)
    header = struct.pack("<4sIffffIII", b"SFW1", 1, g.x0, g.z0, CELL, SEA_FLOOR, TILE, tx, tz)
    head_len = len(header) + 8 * len(index)
    out = os.path.join(ROOT, "data", "terrain")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "world.bin"), "wb") as f:
        f.write(header)
        for p, l in index:
            f.write(struct.pack("<II", p + head_len if l else 0, l))
        for b in blobs:
            f.write(b)
    water["_about"] = "Baked by tools/world/bake_world.py from world_map.json: the sea level, every river as points [x, z, water level], and lakes. Do not edit by hand."
    with open(os.path.join(out, "water.json"), "w") as f:
        json.dump(water, f, separators=(",", ":"))

    # checks: every Act 1 POI, settlement and landmark on walkable ground the start can reach
    off = W["act1Offset"]
    start = [205 + off[0], 314 + off[1]]
    reach = reachable(walk > 0.5, g, start)
    missing = []
    spots = [(p["name"], [p["at"][0] + off[0], p["at"][1] + off[1]]) for p in M["act1"]["pois"]]
    spots += [(s["name"], s["at"]) for s in W["settlements"] if s["zone"] != "bracken"]
    spots += [(l["name"], l["at"]) for l in W["landmarks"]]
    for name, (x, z) in spots:
        i, j = int(round((x - g.x0) / CELL)), int(round((z - g.z0) / CELL))
        win = reach[max(0, j - 6): j + 7, max(0, i - 6): i + 7]
        if not win.any():
            missing.append(name)
    print("tiles %d x %d, %d with land, %.2f MB" % (tx, tz, len(blobs), (head_len + pos) / 1e6))
    print("walkable %.0f%% of land, %d places not reachable on foot from the Last Cart:" % (100 * (walk > 0.5).sum() / max(1, (height > 0.25).sum()), len(missing)))
    for m in missing:
        print("  -", m)

    # preview: walkable ground light, high ground shaded by height, sea blue
    if "--no-preview" not in sys.argv:
        hn = np.clip(height / 120, 0, 1)
        rgb = np.zeros(height.shape + (3,), np.uint8)
        rgb[..., 0] = (70 + 120 * hn).astype(np.uint8)
        rgb[..., 1] = (80 + 100 * hn).astype(np.uint8)
        rgb[..., 2] = (60 + 90 * hn).astype(np.uint8)
        wk = walk > 0.5
        rgb[wk] = (np.array([150, 170, 100]) * (0.85 + 0.15 * reach[wk, None])).astype(np.uint8)
        rgb[wk & ~reach] = (170, 120, 90)
        rgb[height <= 0.25] = (40, 70, 100)
        Image.fromarray(rgb).resize((g.nx // 2, g.nz // 2)).save(os.path.join(ROOT, "tools", "world", "preview.png"))


if __name__ == "__main__":
    main()
