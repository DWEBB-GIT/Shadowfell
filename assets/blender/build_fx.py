"""
Shadowfell spell effect shapes.

Builds the abstract shapes the spell effects are made of (slash arcs,
shockwave walls, ground cracks, claw tears, speed streaks, aura columns, a
ward plate) and exports each as glTF binary into assets/models/fx/. These are
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


BUILDERS = [build_arc, build_wave, build_crack, build_claws, build_streak, build_aura, build_ward]

if __name__ == "__main__":
    for b in BUILDERS:
        b()
