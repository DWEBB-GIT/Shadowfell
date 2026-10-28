"""
Shadowfell spell effect shapes.

Builds the abstract shapes the spell effects are made of (slash arcs,
shockwave walls, ground cracks, claw tears, speed streaks, aura columns, a
ward plate, bolts, a dome, a rune circle, a hammer of light, a storm
spiral, grasping roots, a curse sigil, chains, a starburst, a halo and a
pillar of light) and exports each as glTF binary into assets/models/fx/. These are
effect shapes, not characters, creatures or props: those are modelled by
hand.

Run headless with either:
    blender --background --python assets/blender/build_fx.py
or, with the bpy module installed (pip install bpy):
    python assets/blender/build_fx.py

Conventions (game/systems/fx.gd relies on these):
  * 1 Blender unit = 1 metre; every shape is about 1 m across so the game
    scales it (data/spell_fx.json). Forward is Blender -Y (+Z in the game).
  * No colour of its own: the "Col" attribute is greyscale brightness, 1 at
    the hot edge, 0 where the shape fades out. The game draws the shapes
    additively and tints them per spell, so black reads as transparent and
    one shape serves every school of magic.
"""
import math
import os
import random

import bpy  # must be imported before bmesh when running as a Python module
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "models", "fx"))
os.makedirs(OUT, exist_ok=True)

rng = random.Random(2026)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Shape:
    """Vertices with a brightness each, joined into faces."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.glow = {}

    def v(self, x, y, z, glow):
        vert = self.bm.verts.new((x, y, z))
        self.glow[vert] = max(0.0, min(1.0, glow))
        return vert

    def face(self, *verts):
        f = self.bm.faces.new(verts)
        for loop in f.loops:
            g = self.glow[loop.vert]
            loop[self.col] = (g, g, g, 1.0)
        return f

    def strip(self, rows):
        """Join rows of vertices (each row the same length) into quads."""
        for a, b in zip(rows, rows[1:]):
            for i in range(len(a) - 1):
                self.face(a[i], a[i + 1], b[i + 1], b[i])

    def export(self, name):
        reset_scene()
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        me.color_attributes.active_color = me.color_attributes["Col"]
        mat = bpy.data.materials.new("M_Fx")
        me.materials.append(mat)
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(OUT, name + ".glb"),
            export_format="GLB",
            export_vertex_color="ACTIVE",
            export_all_vertex_colors=False,
            export_yup=True,
            export_apply=True,
            export_materials="EXPORT",
            export_extras=False,
            export_cameras=False,
            export_lights=False,
        )
        print("exported", name)


def ease(t):
    return t * t * (3 - 2 * t)


def build_arc():
    """A crescent of a swing, lying flat: 150 degrees around the front, 1 m
    out. The blade's path runs from the right (tail, faded) to the left
    (head, hottest); the outer edge is the hot cutting edge."""
    s = Shape()
    segs, rings = 28, 4
    span = math.radians(150)
    rows = []
    for j in range(rings + 1):
        row = []
        for i in range(segs + 1):
            u = i / segs  # 0 tail .. 1 head
            a = -span / 2 + span * u
            # thickest just behind the head, thin at both ends: a crescent
            width = 0.42 * math.sin(math.pi * min(1.0, u * 1.15)) + 0.02
            r = 1.0 - width * (j / rings)
            along = ease(u) ** 1.4 * (1 - ease(max(0.0, (u - 0.93) / 0.07)) * 0.6)
            edge = (1 - j / rings) ** 1.6
            # Blender -Y is forward; positive angle sweeps to the left (+X)
            row.append(s.v(math.sin(a) * r, -math.cos(a) * r, 0, along * edge))
        rows.append(row)
    s.strip(rows)
    s.export("fx_arc")


def build_wave():
    """A shockwave wall: a ring 1 m across, 0.4 m high, hot at the ground,
    with a ragged top that fades out."""
    s = Shape()
    segs = 40
    rows = []
    heights = [0.0, 0.12, 0.26, 0.4]
    jag = [rng.uniform(0.7, 1.3) for _ in range(segs)]
    jag.append(jag[0])
    for j, h in enumerate(heights):
        row = []
        for i in range(segs + 1):
            a = 2 * math.pi * i / segs
            z = h * (jag[i] if j == len(heights) - 1 else 1)
            r = 1.0 + 0.06 * (j / (len(heights) - 1))
            row.append(s.v(math.cos(a) * r, math.sin(a) * r, z, (1 - j / (len(heights) - 1)) ** 1.3))
        rows.append(row)
    s.strip(rows)
    s.export("fx_wave")


def build_crack():
    """A star of jagged ground cracks out to 1 m, hot at the middle."""
    s = Shape()
    arms = 7
    for k in range(arms):
        a0 = 2 * math.pi * k / arms + rng.uniform(-0.25, 0.25)
        length = rng.uniform(0.7, 1.0)
        steps = 5
        rows = [[], []]
        a = a0
        x = y = 0.0
        pts = []
        for i in range(steps + 1):
            t = i / steps
            d = 0.12 + length * t
            a += rng.uniform(-0.28, 0.28) if i else 0
            pts.append((math.cos(a) * d, math.sin(a) * d, t))
        for i, (x, y, t) in enumerate(pts):
            nx, ny = (pts[min(i + 1, steps)][0] - pts[max(i - 1, 0)][0], pts[min(i + 1, steps)][1] - pts[max(i - 1, 0)][1])
            n = math.hypot(nx, ny) or 1
            w = 0.07 * (1 - t) + 0.008
            px, py = -ny / n * w, nx / n * w
            g = (1 - t) ** 0.8
            rows[0].append(s.v(x + px, y + py, 0, g))
            rows[1].append(s.v(x - px, y - py, 0, g))
        s.strip(rows)
    s.export("fx_crack")


def build_claws():
    """Three parallel tears in the air, standing up and facing you from the
    front: the mark of a wound torn open (Rend)."""
    s = Shape()
    for k in (-1, 0, 1):
        rows = [[], [], []]
        steps = 8
        for i in range(steps + 1):
            t = i / steps
            # a slight curve, down-left to up-right
            x = -0.45 + 0.9 * t + k * 0.16
            z = -0.5 + 1.0 * t + 0.12 * math.sin(math.pi * t) * -1
            w = 0.07 * math.sin(math.pi * t) + 0.005
            g = math.sin(math.pi * t) ** 0.6
            rows[0].append(s.v(x - w * 0.7, 0, z + w * 0.7, 0))
            rows[1].append(s.v(x, 0, z, g))
            rows[2].append(s.v(x + w * 0.7, 0, z - w * 0.7, 0))
        s.strip(rows)
    s.export("fx_claws")


def build_streak():
    """A speed streak trailing behind a charge: two crossed tapered ribbons
    (one flat, one upright, so it reads from the isometric camera), 1 m
    long, hot at the front (origin) and gone at the tail (+Y)."""
    s = Shape()
    steps = 10
    for flat in (True, False):
        rows = [[], [], []]
        for i in range(steps + 1):
            t = i / steps
            y = t  # behind is +Y
            w = 0.5 * (1 - t) ** 0.7 + 0.02
            g = (1 - t) ** 1.5
            for side, row in zip((-1, 0, 1), rows):
                if flat:
                    row.append(s.v(side * w, y, 0, 0 if side else g))
                else:
                    row.append(s.v(0, y, side * w * 0.8, 0 if side else g))
        s.strip(rows)
    s.export("fx_streak")


def build_aura():
    """A column of rising fire around a body: an open cylinder 1 m across and
    1 m high, hot at the feet, licking up into flame tongues that fade."""
    s = Shape()
    segs = 24
    levels = 5
    tongues = [rng.uniform(0.55, 1.25) for _ in range(segs)]
    tongues.append(tongues[0])
    rows = []
    for j in range(levels + 1):
        t = j / levels
        row = []
        for i in range(segs + 1):
            a = 2 * math.pi * i / segs
            # tongues: every other vertex rises higher at the top
            lift = tongues[i] if i % 2 == 0 else 0.6
            z = t * (1.0 if j < levels else lift)
            r = 1.0 - 0.25 * t
            row.append(s.v(math.cos(a) * r, math.sin(a) * r, z, (1 - t) ** 1.2))
        rows.append(row)
    s.strip(rows)
    s.export("fx_aura")


def build_ward():
    """A faceted ward plate standing in front of you: a slice of a sphere,
    120 degrees wide, low-poly so its facets catch the eye, with a hot rim
    and a faint middle."""
    s = Shape()
    cols, rows_n = 6, 4
    az = math.radians(120)
    rows = []
    for j in range(rows_n + 1):
        e = math.radians(-25 + 85 * j / rows_n)
        row = []
        for i in range(cols + 1):
            a = -az / 2 + az * i / cols
            r = 1.0
            x = math.sin(a) * math.cos(e) * r
            y = -math.cos(a) * math.cos(e) * r
            z = math.sin(e) * r + 0.25
            rim = max(abs(i / cols - 0.5) * 2, abs(j / rows_n - 0.5) * 2)
            row.append(s.v(x, y, z, 0.18 + 0.82 * rim ** 2.5))
        rows.append(row)
    s.strip(rows)
    s.export("fx_ward")


def _stroke(s, pts, w, glow=1.0, plane="xz"):
    """A thin glowing line through `pts` (2D points in the given plane),
    hot along its middle and dark at its two edges."""
    rows = [[], [], []]
    n = len(pts)
    for i, (a, b) in enumerate(pts):
        pa = pts[max(i - 1, 0)]
        pb = pts[min(i + 1, n - 1)]
        da, db = pb[0] - pa[0], pb[1] - pa[1]
        d = math.hypot(da, db) or 1
        na, nb = -db / d * w, da / d * w
        g = glow(i / max(1, n - 1)) if callable(glow) else glow
        for side, row in zip((-1, 0, 1), rows):
            u, v = a + na * side, b + nb * side
            x, y, z = (u, 0, v) if plane == "xz" else (u, v, 0) if plane == "xy" else (0, u, v)
            row.append(s.v(x, y, z, 0 if side else g))
    s.strip(rows)


def _circle(cx, cy, r, n=32, a0=0.0, span=2 * math.pi):
    return [(cx + math.cos(a0 + span * i / n) * r, cy + math.sin(a0 + span * i / n) * r) for i in range(n + 1)]


def build_bolt():
    """A spell bolt in flight: a pointed glowing head at the origin facing
    forward (-Y) with a wavering wisp tail 1 m long behind it, made of two
    crossed ribbons so it reads from above and from the side."""
    s = Shape()
    steps = 14
    for flat in (True, False):
        rows = [[], [], []]
        for i in range(steps + 1):
            t = i / steps
            y = -0.22 + 1.22 * t
            # the head: a fat teardrop over the first fifth, then a thin tail
            if t < 0.2:
                w = 0.2 * math.sin(math.pi * t / 0.2 * 0.85) + 0.01
                g = 1.0
            else:
                w = 0.09 * (1 - t) ** 0.6 + 0.01
                g = (1 - (t - 0.2) / 0.8) ** 1.4 * 0.8
            wob = 0.06 * math.sin(t * 11) * t
            for side, row in zip((-1, 0, 1), rows):
                if flat:
                    row.append(s.v(side * w + wob, y, 0, 0 if side else g))
                else:
                    row.append(s.v(0, y, side * w + wob, 0 if side else g))
        s.strip(rows)
    s.export("fx_bolt")


def build_dome():
    """A faceted shield bubble over a body: a low-poly half sphere 1 m
    across, its rim at the ground hot and its facets flickering faintly."""
    s = Shape()
    segs, levels = 10, 4
    rows = []
    shimmer = [[rng.uniform(0, 0.25) for _ in range(segs)] for _ in range(levels + 1)]
    for j in range(levels + 1):
        e = (math.pi / 2) * j / levels * 0.97
        row = []
        for i in range(segs + 1):
            a = 2 * math.pi * i / segs + (0.5 * j * 2 * math.pi / segs)
            g = 0.18 + 0.8 * (1 - j / levels) ** 3 + shimmer[j][i % segs]
            row.append(s.v(math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e), g))
        rows.append(row)
    s.strip(rows)
    s.export("fx_dome")


def build_runes():
    """A circle of runes on the ground, 1 m out: two hot rings with twelve
    angular glyphs between them."""
    s = Shape()
    _stroke(s, _circle(0, 0, 0.96, 48), 0.035, plane="xy")
    _stroke(s, _circle(0, 0, 0.62, 40), 0.022, 0.8, plane="xy")
    glyphs = 12
    for k in range(glyphs):
        a = 2 * math.pi * k / glyphs
        cx, cy = math.cos(a) * 0.79, math.sin(a) * 0.79
        tx, ty = -math.sin(a), math.cos(a)  # along the ring
        rx, ry = math.cos(a), math.sin(a)  # out from the middle
        for _ in range(rng.randint(2, 3)):
            p0 = (rng.uniform(-0.07, 0.07), rng.uniform(-0.1, 0.1))
            p1 = (rng.uniform(-0.07, 0.07), rng.uniform(-0.1, 0.1))
            pts = [(cx + tx * u + rx * v, cy + ty * u + ry * v) for u, v in (p0, p1)]
            _stroke(s, pts, 0.014, 0.9, plane="xy")
    s.export("fx_runes")


def build_hammer():
    """A hammer of light, standing on its striking face at the origin: a
    block head and a long haft above it, as two crossed outlines so it
    shows from any side. The edges are hot, the middle a faint fill."""
    s = Shape()
    for plane in ("xz", "yz"):
        head = [(-0.42, 0.0), (0.42, 0.0), (0.42, 0.34), (-0.42, 0.34), (-0.42, 0.0)]
        haft = [(-0.06, 0.34), (-0.06, 1.15), (0.06, 1.15), (0.06, 0.34)]
        _stroke(s, head, 0.04, plane=plane)
        _stroke(s, haft, 0.03, 0.85, plane=plane)
        # a faint fill across the head
        rows = []
        for j in range(3):
            row = []
            for i in range(5):
                u, v = -0.4 + 0.2 * i, 0.02 + 0.15 * j
                g = 0.35 + 0.3 * (j == 0)
                row.append(s.v(u, 0, v, g) if plane == "xz" else s.v(0, u, v, g))
            rows.append(row)
        s.strip(rows)
    s.export("fx_hammer")


def build_spiral():
    """A spinning storm on the ground: three curved blades sweeping out from
    the middle to 1 m, hot along their leading edge."""
    s = Shape()
    for k in range(3):
        a0 = 2 * math.pi * k / 3
        rows = [[], [], []]
        steps = 16
        for i in range(steps + 1):
            t = i / steps
            r = 0.2 + 0.8 * t
            a = a0 + 2.2 * t
            w = 0.16 * math.sin(math.pi * t) + 0.01
            g = math.sin(math.pi * min(1, t * 1.2)) ** 0.7
            for side, row in zip((-1, 0, 1), rows):
                rr = r + side * w
                row.append(s.v(math.cos(a) * rr, math.sin(a) * rr, 0, g if side < 0 else g * 0.5 if side == 0 else 0))
        s.strip(rows)
    s.export("fx_spiral")


def build_vines():
    """Grasping roots: seven tendrils rising from a ring 0.8 m out, curling
    in and over toward the middle, thick and hot at the root, thin at the
    tip. Each is two crossed ribbons so it reads from above."""
    s = Shape()
    n = 7
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.2, 0.2)
        h = rng.uniform(0.75, 1.0)
        curl = rng.uniform(0.5, 0.75)
        twist = rng.uniform(-0.5, 0.5)
        steps = 10
        for cross in (False, True):
            rows = [[], [], []]
            for i in range(steps + 1):
                t = i / steps
                r = 0.8 - curl * t ** 1.6
                aa = a + twist * t
                x, y = math.cos(aa) * r, math.sin(aa) * r
                z = h * math.sin(t * math.pi * 0.6) / math.sin(math.pi * 0.6)
                w = 0.07 * (1 - t) ** 0.8 + 0.008
                g = 1.0 - 0.5 * t
                if cross:
                    ox, oy, oz = 0, 0, w
                else:
                    ox, oy, oz = -math.sin(aa) * w, math.cos(aa) * w, 0
                for side, row in zip((-1, 0, 1), rows):
                    row.append(s.v(x + ox * side, y + oy * side, z + oz * side, 0 if side else g))
            s.strip(rows)
    s.export("fx_vines")


def build_sigil():
    """A curse sigil, standing up and facing you: a ring, an inverted
    triangle inside it, a slit eye at its heart and three spikes out."""
    s = Shape()
    _stroke(s, _circle(0, 0, 0.9, 40), 0.035)
    tri = [(math.cos(a) * 0.86, math.sin(a) * 0.86) for a in (math.pi / 2 + math.pi, math.pi / 2 + math.pi + 2.094, math.pi / 2 + math.pi + 4.189)]
    tri = [(x, -y) for x, y in tri]
    _stroke(s, tri + [tri[0]], 0.025, 0.85)
    eye = [(math.cos(a) * 0.22, math.sin(a) * 0.09) for a in [2 * math.pi * i / 20 for i in range(21)]]
    _stroke(s, eye, 0.02, 0.9)
    _stroke(s, [(0, -0.07), (0, 0.07)], 0.03)
    for a in (-math.pi / 2, math.pi / 6, 5 * math.pi / 6):
        _stroke(s, [(math.cos(a) * 0.92, math.sin(a) * 0.92), (math.cos(a) * 1.15, math.sin(a) * 1.15)], 0.025, lambda t: 1 - t)
    s.export("fx_sigil")


def build_chains():
    """A hanging chain of light, 1 m long from the origin up: seven oval
    links, each turned a quarter to the last, fading toward the top."""
    s = Shape()
    links = 7
    for k in range(links):
        cz = 0.07 + k * 0.145
        oval = [(math.cos(a) * 0.05, cz + math.sin(a) * 0.09) for a in [2 * math.pi * i / 14 for i in range(15)]]
        g = 1 - 0.7 * k / links
        _stroke(s, oval, 0.014, g, plane="xz" if k % 2 == 0 else "yz")
    s.export("fx_chains")


def build_burst():
    """A starburst standing up and facing you: twelve spikes of uneven
    length out to 1 m from a hot middle (a hit, a puff, a flare)."""
    s = Shape()
    n = 12
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.12, 0.12)
        length = rng.uniform(0.55, 1.0)
        w = 0.07 if k % 2 == 0 else 0.045
        tip = (math.cos(a) * length, math.sin(a) * length)
        l = (math.cos(a + 1.5) * w, math.sin(a + 1.5) * w)
        r = (math.cos(a - 1.5) * w, math.sin(a - 1.5) * w)
        c = s.v(0, 0, 0, 1.0)
        s.face(c, s.v(l[0], 0, l[1], 0.9), s.v(tip[0], 0, tip[1], 0.0))
        s.face(c, s.v(tip[0], 0, tip[1], 0.0), s.v(r[0], 0, r[1], 0.9))
    s.export("fx_burst")


def build_halo():
    """A flat ring 1 m out with eight bright beads on it: a halo, a ring of
    motes over a sleeper's head, the stars of a stun."""
    s = Shape()
    _stroke(s, _circle(0, 0, 1.0, 40), 0.02, 0.5, plane="xy")
    for k in range(8):
        a = 2 * math.pi * k / 8
        cx, cy = math.cos(a), math.sin(a)
        c = s.v(cx, cy, 0, 1.0)
        pts = [(cx + math.cos(b) * 0.09, cy + math.sin(b) * 0.09) for b in [math.pi / 2 * i for i in range(5)]]
        vs = [s.v(x, y, 0, 0.0) for x, y in pts]
        for i in range(4):
            s.face(c, vs[i], vs[i + 1])
    s.export("fx_halo")


def build_pillar():
    """A column of light: an open tube 1 m across and 1 m high, hot at the
    foot and fading to nothing at the top, with soft bright ribs down it."""
    s = Shape()
    segs, levels = 16, 6
    rows = []
    for j in range(levels + 1):
        t = j / levels
        row = []
        for i in range(segs + 1):
            a = 2 * math.pi * i / segs
            rib = 0.75 + 0.25 * (i % 2)
            row.append(s.v(math.cos(a), math.sin(a), t, rib * (1 - t) ** 1.1))
        rows.append(row)
    s.strip(rows)
    s.export("fx_pillar")


BUILDERS = [build_arc, build_wave, build_crack, build_claws, build_streak, build_aura, build_ward,
            build_bolt, build_dome, build_runes, build_hammer, build_spiral, build_vines,
            build_sigil, build_chains, build_burst, build_halo, build_pillar]

if __name__ == "__main__":
    for b in BUILDERS:
        b()
