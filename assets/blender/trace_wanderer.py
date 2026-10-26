"""
The Wanderer, traced from Dan's concept sheet (reference/character_sheet.png).

Every ring of the model is measured off the sheet: its width from the front
view's silhouette and its depth from the side view's, at that height, so the
model's outline is the sheet's outline. The texture is the sheet's own
painting, projected from the front, side and back views onto whatever each
view can see. The model stands in the sheet's stance (arms hanging, feet
apart) on a Mixamo-named skeleton.

    blender --background --python assets/blender/trace_wanderer.py
writes assets/models/wanderer_male.glb and assets/blender/wanderer_male.blend.
"""
import colorsys
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_humans as bh  # noqa: E402
import texture_humans as tx  # noqa: E402

SHEET = os.path.join(HERE, "reference", "character_sheet.png")
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
GROUND = 453.3  # the sheet row the figures stand on
PX = 175.8  # sheet pixels per metre
# view: (left, top, right, bottom) on the sheet, the figure's axis on the sheet
VIEWS = {"front": ((300, 120, 480, 470), 392), "side": ((470, 120, 610, 470), 533),
         "back": ((595, 120, 755, 470), 675)}
HEAD_SHIFT = {"front": 2.9, "back": 3.9}  # sheet pixels the head sits right of the body's axis
BG = np.array([0.069, 0.088, 0.104])

UP = Vector((0, 0, 1))


# ------------------------------------------------------------- the sheet
def load_sheet():
    img = bpy.data.images.load(SHEET)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1, :, :3].astype(np.float64)  # top row first, sRGB


class Sheet:
    def __init__(self):
        self.px = load_sheet()
        self.masks = {}
        for view, ((x0, y0, x1, y1), _) in VIEWS.items():
            c = self.px[y0:y1, x0:x1]
            m = np.sqrt(((c - BG) ** 2).sum(-1)) > 0.03
            for row in m:  # close pinholes
                idx = np.where(row)[0]
                for a, b in zip(idx, idx[1:]):
                    if b - a <= 3:
                        row[a:b] = True
            self.masks[view] = m

    def spans(self, view, z):
        """The silhouette's runs across one row at height z, in metres from the figure's axis
        (front: +x is screen right; side: + is the figure's front)."""
        (x0, y0, x1, y1), axis = VIEWS[view]
        y = int(round(GROUND - z * PX)) - y0
        out = []
        for yy in (y - 1, y, y + 1):  # three rows, merged
            row = self.masks[view][min(max(yy, 0), y1 - y0 - 1)]
            inside = False
            for x in range(len(row) + 1):
                on = x < len(row) and row[x]
                if on and not inside:
                    s, inside = x, True
                elif not on and inside:
                    inside = False
                    if x - s >= 2:
                        out.append(((s + x0 - axis) / PX, (x + x0 - axis) / PX))
        out.sort()
        merged = []
        for a, b in out:
            if merged and a <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(b, merged[-1][1]))
            else:
                merged.append((a, b))
        return merged

    def around(self, view, z, x):
        """The run at height z that holds (or is nearest to) x."""
        sp = self.spans(view, z)
        return min(sp, key=lambda s: 0 if s[0] <= x <= s[1] else min(abs(s[0] - x), abs(s[1] - x)))

    def axis(self, view, z):
        """Where the figure's axis is on the sheet at height z: the head sits a little off
        the body's axis in the front and back views, so the face lands where it is painted
        (front: midway between the painted eyes at 388.8 and 401; back: the skull's centre)."""
        t = np.clip((np.asarray(z) - 1.55) / .03, 0, 1)
        return VIEWS[view][1] + HEAD_SHIFT.get(view, 0.0) * t

    def colour(self, view, u, z):
        """Bilinear sRGB colour at a point of a view (u across, as in spans)."""
        sx = self.axis(view, z) + u * PX - .5
        sy = GROUND - z * PX - .5
        x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
        fx, fy = (sx - x0)[..., None], (sy - y0)[..., None]
        h, w = self.px.shape[:2]
        g = lambda yy, xx: self.px[np.clip(yy, 0, h - 1), np.clip(xx, 0, w - 1)]
        return ((g(y0, x0) * (1 - fx) + g(y0, x0 + 1) * fx) * (1 - fy)
                + (g(y0 + 1, x0) * (1 - fx) + g(y0 + 1, x0 + 1) * fx) * fy)

    def inside(self, view, u, z):
        (x0, y0, x1, y1), _ = VIEWS[view]
        sx = np.round(self.axis(view, z) + u * PX).astype(int) - x0
        sy = np.round(GROUND - z * PX).astype(int) - y0
        ok = (sx >= 0) & (sx < x1 - x0) & (sy >= 0) & (sy < y1 - y0)
        out = np.zeros(len(sx), bool)
        out[ok] = self.masks[view][sy[ok], sx[ok]]
        return out


# ------------------------------------------------------------- skeleton
def joints():
    """The sheet's stance, measured: shoulders at 1.42, elbows at 1.20, wrists at 0.95;
    knees 0.20 out at 0.50, ankles 0.245 out at 0.11."""
    J = {}
    for n, z, y in (("Hips", .98, 0), ("Spine", 1.07, 0), ("Spine1", 1.18, 0), ("Spine2", 1.29, 0),
                    ("Neck", 1.52, .01), ("Head", 1.62, .02), ("HeadTop_End", 1.84, .02)):
        J[bh.bone(n)] = Vector((0, y, z))
    for s in (1, -1):
        J[bh.bone("Shoulder", s)] = Vector((.05 * s, 0, 1.44))
        J[bh.bone("Arm", s)] = Vector((.21 * s, 0, 1.42))
        J[bh.bone("ForeArm", s)] = Vector((.275 * s, 0, 1.20))
        hand = Vector((.35 * s, -.01, .95))
        J[bh.bone("Hand", s)] = hand
        d = (hand - J[bh.bone("ForeArm", s)]).normalized()
        for f, side in (("Thumb", -.03), ("Index", -.02), ("Middle", 0), ("Ring", .015), ("Pinky", .03)):
            for i, along in enumerate((.06, .085, .105, .125) if f != "Thumb" else (.02, .04, .06, .08)):
                J[bh.bone(f"Hand{f}{i + 1}", s)] = hand + d * along + Vector((0, side, 0))
        J[bh.bone("UpLeg", s)] = Vector((.10 * s, 0, .93))
        J[bh.bone("Leg", s)] = Vector((.20 * s, -.01, .50))
        J[bh.bone("Foot", s)] = Vector((.245 * s, .02, .11))
        J[bh.bone("ToeBase", s)] = Vector((.265 * s, -.08, .03))
        J[bh.bone("Toe_End", s)] = Vector((.28 * s, -.16, .03))
    return J


def segments(J):
    """Each deforming bone as a line from its joint to its child's."""
    child = {}
    for b, p in bh.TREE:
        if p:
            child.setdefault(p, b)
    prefer = {bh.bone("Hips"): bh.bone("Spine"), bh.bone("Spine2"): bh.bone("Neck")}
    for s in (1, -1):
        prefer[bh.bone("Hand", s)] = bh.bone("HandMiddle1", s)
    out = {}
    for b, _ in bh.TREE:
        c = prefer.get(b, child.get(b))
        out[b] = (J[b], J[c] if c else J[b] + (J[b] - J[[p for x, p in bh.TREE if x == b][0]]).normalized() * .04)
    return out


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


# ------------------------------------------------------------------ mesh
def ring(cx, cf, rx, rf, z, n, p=2.4):
    """A superellipse ring round (cx, front cf) at height z; front is -y."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        x = cx + rx * math.copysign(abs(c) ** (2 / p), c)
        f = cf + rf * math.copysign(abs(s) ** (2 / p), s)
        pts.append(Vector((x, -f, z)))
    return pts


class Builder:
    """Lofts traced rings into parts, choosing each face's material from the sheet's colour there."""

    def __init__(self, sheet):
        self.sheet = sheet
        self.parts = []

    def look(self, part, centre, normal):
        if part not in ("Head", "Arms", "Hands"):
            return bh.base("cloth")
        view = "front" if normal.y < -.3 else ("back" if normal.y > .3 else "side")
        u = {"front": abs(centre.x), "back": -abs(centre.x), "side": -centre.y}[view]
        r, g, b = self.sheet.colour(view, np.array([u]), np.array([centre.z]))[0]
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        skin = .02 < h < .11 and .28 < s < .72 and v > .38
        if part == "Head":
            return bh.SKIN if skin and centre.z < 1.76 else bh.HAIR
        return bh.SKIN if skin else bh.base("leather")

    def loft(self, name, part, rows, caps=(True, True)):
        """rows: rings of points, all one length."""
        p = bh.Part(name, smooth=False)
        grid = [[p._vert(pt, {}) for pt in row] for row in rows]
        n = len(rows[0])
        cen = [sum(row, Vector()) / n for row in rows]
        for k in range(len(rows) - 1):
            ref = (cen[k] + cen[k + 1]) / 2
            for i in range(n):
                j = (i + 1) % n
                vs = [grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]]
                c = sum((v.co for v in vs), Vector()) / 4
                p._face(vs, self.look(part, c, (c - ref).normalized()), ref, 0, None)
        for end, k, other in ((caps[0], 0, 1), (caps[1], -1, -2)):
            if end:
                c = cen[k]
                p._face(grid[k], self.look(part, c, (c - cen[other]).normalized()), cen[other], 0, None)
        self.parts.append((p, part))
        return p


def build(sheet):
    B = Builder(sheet)
    S = sheet
    lerp = lambda a, b, t: a + (b - a) * t

    def side_run(z, at=0.0):
        return S.around("side", z, at)

    def limb(z, x, prev, maxw):
        """The limb's run near x at height z as (|centre|, half width); where the silhouette
        merges or breaks up there, the ring above stands in."""
        a, b = S.around("front", z, x)
        c, h = abs((a + b) / 2), (b - a) / 2
        if prev and (abs(c - prev[0]) > .05 or h > prev[1] * 1.6 or h < prev[1] * .5) or h > maxw:
            return prev
        return c, max(h, .02)

    def zs(a, b, step):
        n = max(1, int(round((b - a) / step)))
        return [a + (b - a) * i / n for i in range(n + 1)]

    # head: the front view's width (less the ears) and the side view's profile. The profile's
    # front edge is the nose; the rest of the face sits back from it, and only the middle
    # of the ring comes forward to meet it.
    nose = lambda z: .02 * math.exp(-((z - 1.655) / .022) ** 2)
    rows = [ring(0, .015, .056, .056, z, 20, 2.0) for z in (1.53, 1.56)]  # the neck, down into the scarf
    for z in zs(1.585, 1.83, .0125):
        a, b = S.around("front", z, 0)
        half = max(.02, (b - a) / 2)
        if 1.635 < z < 1.725:
            half = min(half, .088)  # the ears stand out of the outline here
        f0, f1 = side_run(z, .05)
        f0 = max(f0, -.075)  # not the hood hanging behind the neck
        if z < 1.635:  # the beard narrows to the chin; the scarf's outline is wider
            t = (z - 1.585) / .05
            half = min(half, lerp(.058, .082, t))
            f0, f1 = max(f0, lerp(-.02, -.06, t)), min(f1, .15)
        face = f1 - nose(z)
        pts = ring(0, (f0 + face) / 2, half, (face - f0) / 2, z, 20, 2.3)
        for q in pts:
            q.y -= nose(z) * max(0.0, 1 - abs(q.x) / .03)
        rows.append(pts)
    B.loft("Head", "Head", rows, caps=(False, True))
    for s in (1, -1):  # ears
        ez, ef = 1.672, .03
        rows = [ring(s * (.088 + dx), ef + df, .006, rf, z, 6, 2.0) for z, dx, df, rf in
                ((1.645, .004, -.004, .010), (1.665, .010, 0, .016), (1.69, .012, -.004, .016),
                 (1.705, .006, -.008, .009))]
        B.loft(f"Ear{s}", "Head", rows)

    # the scarf over the shoulders, up to the chin
    rows = []
    for z, half in ((1.44, .205), (1.47, .205), (1.50, .20), (1.53, .185), (1.55, .16), (1.563, .135),
                    (1.575, .11)):
        f0, f1 = side_run(z)
        rows.append(ring(0, (f0 + f1) / 2, half, (f1 - f0) / 2, z, 16, 2.6))
    B.loft("Cowl", "Torso", rows, caps=(False, False))

    # tunic from the hem to the shoulders; the cape behind takes the back 3 cm
    rows, dep = [], None
    for z in zs(.64, 1.44, .04)[::-1]:  # top down, so the hem follows the waist
        if z >= 1.20:
            half, cx = .18 + (z - 1.20) * .1, 0.0
        elif z >= .98:
            a, b = S.around("front", z, 0)
            half = (b - a) / 2
        else:  # the skirt's flaps, leaving out the hands beside them
            sp = [s for s in S.spans("front", z) if abs((s[0] + s[1]) / 2) < .27]
            a, b = min(s[0] for s in sp), max(s[1] for s in sp)
            half = min((b - a) / 2, .275)
        f0, f1 = side_run(z)
        f0, f1 = max(f0, -.215), min(f1, .215)
        if dep:  # no sudden steps: the sheet's cape hem and hands confuse the side view
            f0, f1 = max(f0, dep[0] - .015), min(max(f1, dep[1] - .015), dep[1] + .015)
        dep = f0, f1
        back = f0 + (.03 if z < 1.40 else .0)
        rows.append(ring(0, (back + f1) / 2, half, (f1 - back) / 2, z, 16, 2.6))
    B.loft("Tunic", "Torso", rows[::-1], caps=(False, False))

    # the cape: a curved slab down the back
    rows = []
    for z, half in ((1.44, .17), (1.30, .19), (1.10, .195), (.90, .21), (.74, .245), (.63, .24)):
        f0, _ = side_run(z)
        wrap = lambda pts, h=half: [q + Vector((0, -.07 * (q.x / h) ** 2, 0)) for q in pts]
        rows.append(wrap(ring(0, f0 + .014, half, .012, z, 16, 2.0)))
    B.loft("Cape", "Cape", rows)

    for s in (1, -1):
        # pauldron: a dome over the shoulder
        rows = [ring(s * cx, 0, rx, rf, z, 10, 2.2) for z, cx, rx, rf in
                ((1.535, .205, .03, .045), (1.51, .22, .062, .085), (1.47, .228, .072, .10),
                 (1.42, .235, .07, .10), (1.37, .245, .064, .09), (1.33, .25, .058, .08))]
        B.loft(f"Pauldron{s}", "Arms", rows)
        # upper arm, then the measured forearm and bracer, then the hand
        rows, prev = [], None
        for z in [1.40 - i * .04 for i in range(12)]:
            if z >= 1.20:
                t = (1.40 - z) / .20
                prev = cx, half = lerp(.235, .272, t), .062
            else:
                prev = cx, half = limb(z, s * .3, prev, .085)
            rows.append(ring(s * cx, 0, half, half * .92, z, 8, 2.3))
        B.loft(f"Arm{s}", "Arms", rows, caps=(False, False))
        rows = []
        for z in [.955 - i * .03 for i in range(7)]:
            prev = cx, half = limb(z, s * .34, prev, .07)
            rows.append(ring(s * cx, -.005, half, half * .75, z, 8, 2.3))
        B.loft(f"Hand{s}", "Hands", rows, caps=(False, True))
        # leg: under the tunic, then the measured knee cops and boots
        rows, prev, dep = [], None, None
        for z in [.78 - i * .04 for i in range(17)]:
            if z > .62:
                prev = cx, half = lerp(.17, .13, (z - .64) / .14), .095
            else:
                prev = cx, half = limb(z, s * .2, prev, .11)
            f0, f1 = side_run(z, -.02)
            if dep and abs((f1 - f0) / 2 - dep[1]) > .03:
                f0, f1 = dep[0] - dep[1], dep[0] + dep[1]
            dep = (f0 + f1) / 2, min(.11, (f1 - f0) / 2)
            rows.append(ring(s * cx, dep[0], half, dep[1], z, 10, 2.4))
        B.loft(f"Leg{s}", "Legs", rows, caps=(False, False))
        # boot foot: horizontal slices, toe to heel from the side view
        rows = []
        for z in (.13, .10, .065, .03, .005):
            prev = cx, half = limb(z, s * .27, prev, .09)
            f0, f1 = side_run(z, 0)
            f0, f1 = max(f0, -.19), min(f1, .16)
            rows.append(ring(s * cx, (f0 + f1) / 2, half, (f1 - f0) / 2, z, 10, 3.0))
        B.loft(f"Foot{s}", "Feet", rows, caps=(False, True))
    return B


# ------------------------------------------------------------ assembling
PART_BONES = {
    "Head": ["Head", "Neck"],
    "Torso": ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Shoulder", "UpLeg"],
    "Cape": ["Hips", "Spine", "Spine1", "Spine2", "UpLeg"],
    "Arms": ["Shoulder", "Arm", "ForeArm", "Hand"],
    "Hands": ["Hand"],
    "Legs": ["Hips", "UpLeg", "Leg", "Foot"],
    "Feet": ["Foot", "ToeBase"],
}


def weigh(obj, part, segs):
    names = []
    for n in PART_BONES[part]:
        names += [bh.bone(n)] if n in bh.SPINE else [bh.bone(n, 1), bh.bone(n, -1)]
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        ds = []
        for n in names:
            if n not in bh.SPINE and ("Left" in n) != (p.x > 0):
                continue
            ds.append((seg_dist(p, *segs[n]), n))
        ds.sort()
        ws = [(1 / (d * d + 1e-4) ** 2, n) for d, n in ds[:2]]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            if w / tot > .02:
                obj.vertex_groups[n].add([v.index], w / tot, "REPLACE")


def project(sheet, D, objs):
    """The sheet's painting, from whichever views can see each texel (sRGB, SIZE*SIZE x 3)."""
    m = D["data"][:, 2] > 0
    p = D["pos"][m] * 2 - np.array([1.0, 1.0, 0.0])
    n = D["nrm"][m] * 2 - 1
    p[:, 0] = np.abs(p[:, 0])  # mirrored halves share texels: paint from the left side
    n[:, 0] = np.abs(n[:, 0])
    deps = bpy.context.evaluated_depsgraph_get()
    scene = bpy.context.scene
    views = {"front": (Vector((0, -1, 0)), p[:, 0]), "back": (Vector((0, 1, 0)), -p[:, 0]),
             "side": (Vector((1, 0, 0)), -p[:, 1])}
    total = np.zeros((len(p), 3))
    weight = np.zeros(len(p))
    loose = np.zeros((len(p), 3))
    lw = np.zeros(len(p))
    for view, (toward, u) in views.items():
        facing = np.clip(n @ np.array(toward), 0, 1) ** 4 + 1e-3  # a little of every view, for the tops of things
        col = sheet.colour(view, u, p[:, 2])
        inside = sheet.inside(view, u, p[:, 2])
        seen = np.zeros(len(p), bool)
        for i in np.nonzero((facing > .01) & inside)[0]:
            q = Vector(p[i])
            hit, loc, *_ = scene.ray_cast(deps, q + toward * 2, -toward)
            seen[i] = hit and (loc - q).length < .012
        w = facing * seen
        total += col * w[:, None]
        weight += w
        loose += col * (facing * inside)[:, None]
        lw += facing * inside
    out = np.where((weight > 1e-3)[:, None], total / np.maximum(weight, 1e-3)[:, None],
                   loose / np.maximum(lw, 1e-3)[:, None])
    full = np.full((len(m), 3), .1)
    full[m] = out
    return full, m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sheet = Sheet()
    J = joints()
    arm = bh.make_armature(J)
    bh.MATSET[:] = [bpy.data.materials.new(name) for name in bh.MATS]
    B = build(sheet)
    segs = segments(J)
    objs = []
    for p, part in B.parts:
        obj = p.to_object(arm)
        weigh(obj, part, segs)
        objs.append(obj)
    # the face gets the most texels, then the hands
    tx.DENSITY.update({"Head": 3.0, "Ear1": 3.0, "Ear-1": 3.0, "Hand1": 1.5, "Hand-1": 1.5})
    tx.unwrap(objs)
    D = tx.bake(objs)
    rgb, m = project(sheet, D, objs)
    # the sheet is already lit; lift it so the game's own light lands near the sheet's look
    rgb = np.clip(rgb, 0, 1) ** .8
    # skin and hair: divide out their usual colour so the game can tint them
    cls = np.rint(D["data"][:, 2] * 64).astype(int) - 1
    base = {}
    for name in ("skin", "hair"):
        k = (cls == bh.CLASSES.index(name)) & m
        if k.any():
            base[name] = np.median(rgb[k], 0)
            rgb[k] = np.clip(rgb[k] / base[name] * .9, 0, 1)
    print("tints:", {k: v.round(3).tolist() for k, v in base.items()})
    img = bpy.data.images.new("wanderer_male_diffuse", tx.SIZE, tx.SIZE, alpha=False)
    px = np.ones((tx.SIZE * tx.SIZE, 4), np.float32)
    px[:, :3] = rgb
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(HERE, "wanderer_male_diffuse.png")
    img.file_format = "PNG"
    img.save()
    tx.apply(bh.MATSET, img)
    bh.export(os.path.join(OUT, "wanderer_male.glb"))
    for mat, name in ((bh.MATSET[1], "skin"), (bh.MATSET[2], "hair")):
        if name in base:
            tx.tint(mat, tuple((base[name] / .9) ** 2.2) + (1,), copy=False)
    print("tris:", sum(len(f.vertices) - 2 for o in objs for f in o.data.polygons))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "wanderer_male.blend"))
    return arm, objs


if __name__ == "__main__":
    main()
