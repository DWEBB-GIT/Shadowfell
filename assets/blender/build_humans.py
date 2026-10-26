"""
Shadowfell modular humans.

Builds the male and female player bodies on one shared, Mixamo-named
skeleton and exports each as glTF binary, with every swappable part as its
own skinned mesh:

    assets/models/human_male.glb
    assets/models/human_female.glb
    assets/models/human_parts.json   (which part fills which slot, and what it hides)

Run headless with:
    blender --background --python assets/blender/build_humans.py
Add `-- --preview <dir>` to also render a posed line-up of outfits to <dir>.

Conventions (the game code relies on these):
  * 1 Blender unit = 1 metre. Bodies stand on Z=0 in a T-pose and face
    Blender -Y (+Z "forward" in Godot), as Mixamo characters do.
  * Bones carry Mixamo's names ("mixamorig:Hips"; Godot imports them as
    "mixamorig_Hips"), so Mixamo animations retarget onto the skeleton with
    Godot's humanoid bone map.
  * Every part is lofted from rings, and each ring carries its own bone
    weights, so armour built from the body's rings bends exactly as the body
    under it does.
  * Colour lives in the per-corner colour attribute "Col". M_Base is painted
    by vertex colour; M_Skin and M_Hair are near-white and tinted in game, so
    skin tone and hair colour can change per character.
"""
import json
import math
import os
import random
import sys

import bpy  # must be imported before bmesh when running as a Python module
import bmesh
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))

rng = random.Random(1997)
SQ2 = math.sqrt(2.0)
UP = Vector((0, 0, 1))
SIDE = Vector((1, 0, 0))
FRONT = Vector((0, -1, 0))

MATS = ["M_Base", "M_Skin", "M_Hair"]

# ---------------------------------------------------------------- palette
P = {
    "linen": (0.52, 0.47, 0.38),
    "cloth": (0.24, 0.22, 0.18),
    "cloth_dark": (0.15, 0.14, 0.12),
    "rag": (0.33, 0.30, 0.25),
    "robe": (0.13, 0.12, 0.15),
    "robe_trim": (0.27, 0.21, 0.32),
    "cloak": (0.17, 0.20, 0.15),
    "cloak_dark": (0.10, 0.10, 0.11),
    "cloak_red": (0.30, 0.09, 0.08),
    "leather": (0.32, 0.21, 0.12),
    "leather_dark": (0.19, 0.12, 0.08),
    "fur": (0.28, 0.25, 0.21),
    "mail": (0.37, 0.38, 0.40),
    "steel": (0.54, 0.55, 0.56),
    "steel_dark": (0.31, 0.32, 0.34),
    "iron": (0.22, 0.22, 0.23),
    "brass": (0.55, 0.42, 0.20),
    "eye": (0.05, 0.04, 0.04),
    "lips": (0.46, 0.27, 0.24),
    "black": (0.03, 0.03, 0.03),
}
WHITE = (1.0, 1.0, 1.0)
SKIN = ("M_Skin", WHITE)
HAIR = ("M_Hair", WHITE)


def base(c):
    return ("M_Base", P[c])


# --------------------------------------------------------------- skeleton
SPINE = {"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"}


def bone(n, s=0):
    if n in SPINE:
        return "mixamorig:" + n
    return "mixamorig:" + ("Left" if s > 0 else "Right") + n


def wt(s=0, **kw):
    """Bone weights for one side: wt(1, Arm=.5, ForeArm=.5)."""
    return {bone(k, s): v for k, v in kw.items()}


FINGERS = {  # joint offsets from the hand, for the left hand (x mirrors)
    "Thumb": [(.020, -.030, -.010), (.045, -.055, -.015), (.068, -.070, -.015), (.088, -.080, -.015)],
    "Index": [(.080, -.025, 0), (.107, -.025, 0), (.130, -.025, 0), (.150, -.025, 0)],
    "Middle": [(.085, 0, 0), (.115, 0, 0), (.140, 0, 0), (.162, 0, 0)],
    "Ring": [(.080, .020, 0), (.105, .020, 0), (.127, .020, 0), (.147, .020, 0)],
    "Pinky": [(.072, .038, 0), (.093, .038, 0), (.110, .038, 0), (.125, .038, 0)],
}


def bone_tree():
    """(bone, parent) in Mixamo's order."""
    t = [(bone(a), bone(b) if b else None) for a, b in (
        ("Hips", None), ("Spine", "Hips"), ("Spine1", "Spine"), ("Spine2", "Spine1"),
        ("Neck", "Spine2"), ("Head", "Neck"), ("HeadTop_End", "Head"))]
    for s in (1, -1):
        t += [(bone("Shoulder", s), bone("Spine2")), (bone("Arm", s), bone("Shoulder", s)),
              (bone("ForeArm", s), bone("Arm", s)), (bone("Hand", s), bone("ForeArm", s))]
        for f in FINGERS:
            for i in range(1, 5):
                parent = bone("Hand", s) if i == 1 else bone(f"Hand{f}{i - 1}", s)
                t.append((bone(f"Hand{f}{i}", s), parent))
    for s in (1, -1):
        t += [(bone("UpLeg", s), bone("Hips")), (bone("Leg", s), bone("UpLeg", s)),
              (bone("Foot", s), bone("Leg", s)), (bone("ToeBase", s), bone("Foot", s)),
              (bone("Toe_End", s), bone("ToeBase", s))]
    return t


TREE = bone_tree()
BONES = [b for b, _ in TREE]
BI = {b: i for i, b in enumerate(BONES)}

BODIES = {
    # s: height scale; sh: shoulder joint x; upper/fore: arm lengths; hip: hip joint x;
    # arm: limb girth; hand: hand size
    "male": dict(sex="male", s=1.0, sh=.180, upper=.280, fore=.260, hip=.095, arm=1.0, hand=1.0),
    "female": dict(sex="female", s=.955, sh=.163, upper=.262, fore=.245, hip=.100, arm=.86, hand=.9),
}


def joints(B):
    s = B["s"]
    J = {}
    for n, z in (("Hips", .98), ("Spine", 1.07), ("Spine1", 1.18), ("Spine2", 1.29),
                 ("Neck", 1.49), ("Head", 1.58), ("HeadTop_End", 1.81)):
        J[bone(n)] = Vector((0, 0, z * s))
    az = 1.44 * s
    for si in (1, -1):
        hx = B["sh"] + B["upper"] + B["fore"]
        J[bone("Shoulder", si)] = Vector((.05 * si, 0, az))
        J[bone("Arm", si)] = Vector((B["sh"] * si, 0, az))
        J[bone("ForeArm", si)] = Vector(((B["sh"] + B["upper"]) * si, 0, az))
        J[bone("Hand", si)] = Vector((hx * si, 0, az))
        k = B["hand"]
        for f, offs in FINGERS.items():
            for i, (dx, dy, dz) in enumerate(offs):
                J[bone(f"Hand{f}{i + 1}", si)] = Vector(((hx + dx * k) * si, dy * k, az + dz * k))
        x = B["hip"] * si
        J[bone("UpLeg", si)] = Vector((x, 0, .93 * s))
        J[bone("Leg", si)] = Vector((x, -.01, .51 * s))
        J[bone("Foot", si)] = Vector((x, .02, .09 * s))
        J[bone("ToeBase", si)] = Vector((x, -.09 * s, .02))
        J[bone("Toe_End", si)] = Vector((x, -.17 * s, .02))
    return J


def make_armature(J):
    data = bpy.data.armatures.new("Armature")
    obj = bpy.data.objects.new("Armature", data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    children = {}
    for b, p in TREE:
        children.setdefault(p, []).append(b)
    prefer = {bone("Hips"): bone("Spine"), bone("Spine2"): bone("Neck")}
    for s in (1, -1):
        prefer[bone("Hand", s)] = bone("HandMiddle1", s)
    eb = {}
    for b, p in TREE:
        e = data.edit_bones.new(b)
        e.head = J[b]
        kids = children.get(b)
        if kids:
            e.tail = J[prefer.get(b, kids[0])]
        elif p:
            d = J[b] - J[p]
            e.tail = J[b] + d.normalized() * max(.03, min(.06, d.length))
        if (e.tail - e.head).length < 1e-4:
            e.tail = e.head + UP * .03
        if p:
            e.parent = eb[p]
        eb[b] = e
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


# ------------------------------------------------------------------ rings
def R(c, rx, ry, w, f=0.0, b=0.0, d=None, **kw):
    r = {"c": Vector(c), "rx": rx, "ry": ry, "w": w, "f": f, "b": b, "d": d}
    r.update(kw)
    return r


def grow(rings, d, dy=None, f=0.0, look=None, **kw):
    out = []
    for r in rings:
        n = dict(r)
        n["c"] = r["c"].copy()
        n["rx"] = r["rx"] + d
        n["ry"] = r["ry"] + (d if dy is None else dy)
        n["f"] = r["f"] + f
        n.update(kw)
        out.append(n)
    return out


def lerp(a, b, t):
    return a + (b - a) * t


def blend_w(a, b, t):
    if callable(a) or callable(b):
        return a if t < .5 else b
    out = {}
    for k, v in a.items():
        out[k] = out.get(k, 0) + v * (1 - t)
    for k, v in b.items():
        out[k] = out.get(k, 0) + v * t
    return out


def ring_at(rings, axis, val):
    """A ring part way along a loft (axis 0 = x, 2 = z), every value interpolated."""
    for a, b in zip(rings, rings[1:]):
        va, vb = a["c"][axis], b["c"][axis]
        if va != vb and (va - val) * (vb - val) <= 0:
            t = (val - va) / (vb - va)
            r = dict(a)
            r.update(c=a["c"].lerp(b["c"], t), rx=lerp(a["rx"], b["rx"], t), ry=lerp(a["ry"], b["ry"], t),
                     f=lerp(a["f"], b["f"], t), b=lerp(a["b"], b["b"], t), w=blend_w(a["w"], b["w"], t))
            return r
    near = min(rings, key=lambda r: abs(r["c"][axis] - val))
    r = dict(near)
    c = near["c"].copy()
    c[axis] = val
    r["c"] = c
    return r


def ring_point(r, u, v, t):
    u = r.get("u", u)
    v = r.get("v", v)
    ct, st = math.cos(t), math.sin(t)
    off = u * (ct * r["rx"]) + v * (st * r["ry"])
    if r["f"] and st > 0:
        off += v * (r["f"] * st * st)
    if r["b"] and st < 0:
        off -= v * (r["b"] * st * st)
    p = r["c"] + off
    if r["d"]:
        p = p + r["d"](ct, st)
    return p, ct, st


def front_y(r, x, n=8):
    """Where the front of a body ring (u=X, v=FRONT) is at a given |x|."""
    pts = [ring_point(r, SIDE, FRONT, 2 * math.pi * i / n)[0] for i in range(n)]
    x = abs(x) + r["c"].x
    best = None
    for a, b in zip(pts, pts[1:] + pts[:1]):
        if a.y < r["c"].y and b.y < r["c"].y + 1e-6 and (a.x - x) * (b.x - x) <= 0 and a.x != b.x:
            t = (x - a.x) / (b.x - a.x)
            y = lerp(a.y, b.y, t)
            slope = math.atan2(b.y - a.y, b.x - a.x)
            if best is None or y < best[0]:
                best = (y, slope)
    return best


def shoulders_w(base_w, k=.8):
    """Body ring weights that hand the sides over to the collarbones."""
    def f(ct, st):
        a = max(0.0, ct) ** 2 * k
        b = max(0.0, -ct) ** 2 * k
        out = {n: v * (1 - a - b) for n, v in base_w.items()}
        out[bone("Shoulder", 1)] = a
        out[bone("Shoulder", -1)] = b
        return out
    return f


def skirt_w(a, base_w=None):
    """A skirt hangs from the hips and is dragged a little by each thigh."""
    base_w = base_w or wt(Hips=1)

    def f(ct, st):
        out = {n: v * (1 - a) for n, v in base_w.items()}
        out[bone("UpLeg", 1)] = a * (.5 + .5 * ct)
        out[bone("UpLeg", -1)] = a * (.5 - .5 * ct)
        return out
    return f


# ------------------------------------------------------------------- part
def get_material(name, tint=None):
    key = name if tint is None else f"{name}.{tint}"
    mat = bpy.data.materials.get(key)
    if mat:
        return mat
    mat = bpy.data.materials.new(key)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    out = attr.outputs["Color"]
    if tint is not None:
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(out, mul.inputs["A"])
        mul.inputs["B"].default_value = tint
        out = mul.outputs["Result"]
    nt.links.new(out, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    return mat


class Part:
    """One skinned mesh, built from lofts that carry their own weights."""

    def __init__(self, name, smooth=True):
        self.name = name
        self.smooth = smooth
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.dl = self.bm.verts.layers.deform.verify()

    def _vert(self, p, w):
        v = self.bm.verts.new(p)
        dv = v[self.dl]
        total = sum(w.values())
        for b, x in w.items():
            if x > 1e-4:
                dv[BI[b]] = x / total
        return v

    def _face(self, verts, look, ref, var, smooth):
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - ref) < 0:
            f.normal_flip()
        mat, color = look
        f.material_index = MATS.index(mat)
        k = 1.0 + rng.uniform(-var, var)
        c = tuple(max(0.0, min(1.0, ch * k)) for ch in color) + (1.0,)
        for loop in f.loops:
            loop[self.col] = c
        f.smooth = self.smooth if smooth is None else smooth
        return f

    def loft(self, rings, look, u=SIDE, v=FRONT, n=8, caps=(True, True), var=.06, phase=0.0,
             skip=None, smooth=None):
        """Join rings into a tube. look is (material, colour) or look(k, i) for
        the face between ring k and k+1 at segment i."""
        lk = look if callable(look) else (lambda k, i: look)
        grid = []
        for r in rings:
            row = []
            for i in range(n):
                p, ct, st = ring_point(r, u, v, phase + 2 * math.pi * i / n)
                row.append(self._vert(p, r["w"](ct, st) if callable(r["w"]) else r["w"]))
            grid.append(row)
        for k in range(len(rings) - 1):
            ref = (rings[k]["c"] + rings[k + 1]["c"]) * .5
            for i in range(n):
                if skip and skip(k, i):
                    continue
                self._face([grid[k][i], grid[k][(i + 1) % n], grid[k + 1][(i + 1) % n], grid[k + 1][i]],
                           lk(k, i), ref, var, smooth)
        if caps[0]:
            self._face(grid[0], lk(0, -1), rings[1]["c"], var, smooth)
        if caps[1]:
            self._face(grid[-1], lk(len(rings) - 2, -1), rings[-2]["c"], var, smooth)
        return [v for row in grid for v in row]

    def box(self, c, half, w, look, rot=None, taper=1.0, var=.06, smooth=False):
        """An axis-aligned box (half sizes x, y, z), optionally rotated (degrees XYZ) about its centre."""
        c = Vector(c)
        hx, hy, hz = half
        rings = [R(c - UP * hz, hx * SQ2, hy * SQ2, w), R(c + UP * hz, hx * SQ2 * taper, hy * SQ2 * taper, w)]
        verts = self.loft(rings, look, n=4, phase=math.pi / 4, var=var, smooth=smooth)
        if rot:
            m = (Matrix.Rotation(math.radians(rot[2]), 3, "Z") @ Matrix.Rotation(math.radians(rot[1]), 3, "Y")
                 @ Matrix.Rotation(math.radians(rot[0]), 3, "X"))
            bmesh.ops.rotate(self.bm, verts=verts, cent=c, matrix=m)
        return verts

    def tube(self, pts, radii, weights, look, n=4, phase=math.pi / 4, up=UP, caps=(True, True), var=.06,
             smooth=None, flat=1.0):
        """A tube along any path; each ring faces along the path."""
        rings = []
        for i, p in enumerate(pts):
            a = pts[max(0, i - 1)]
            b = pts[min(len(pts) - 1, i + 1)]
            axis = (b - a).normalized()
            u = (up - axis * up.dot(axis)).normalized()
            v = axis.cross(u)
            rings.append(R(p, radii[i] * flat, radii[i], weights[i], u=u, v=v))
        return self.loft(rings, look, n=n, phase=phase, caps=caps, var=var, smooth=smooth)

    def to_object(self, arm):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        if "Col" in me.color_attributes:
            me.color_attributes.active_color = me.color_attributes["Col"]
            me.color_attributes.render_color_index = me.color_attributes.find("Col")
        for m in MATS:
            me.materials.append(get_material(m))
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        for b in BONES:
            obj.vertex_groups.new(name=b)
        obj.parent = arm
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        return obj


# ------------------------------------------------------------- body rings
class Body:
    """Ring sets for one body; the body parts and every armour piece use them."""

    def __init__(self, key):
        self.B = B = BODIES[key]
        self.key = key
        self.male = B["sex"] == "male"
        self.s = B["s"]
        self.J = joints(B)

    def z(self, z):
        return z * self.s

    def torso(self):
        if self.male:
            rows = [(.92, .150, .100, 0, .010, wt(Hips=1)),
                    (1.02, .138, .093, 0, 0, wt(Hips=.5, Spine=.5)),
                    (1.13, .145, .098, .006, 0, wt(Spine=.5, Spine1=.5)),
                    (1.25, .160, .107, .012, .006, wt(Spine1=.4, Spine2=.6)),
                    (1.36, .172, .108, .008, .012, wt(Spine2=1)),
                    (1.44, .160, .088, 0, 0, shoulders_w(wt(Spine2=1))),
                    (1.49, .062, .058, 0, 0, wt(Spine2=.3, Neck=.7))]
        else:
            rows = [(.92, .158, .104, 0, .012, wt(Hips=1)),
                    (1.02, .122, .084, 0, 0, wt(Hips=.5, Spine=.5)),
                    (1.13, .128, .087, .004, 0, wt(Spine=.5, Spine1=.5)),
                    (1.25, .142, .096, .036, .004, wt(Spine1=.4, Spine2=.6)),
                    (1.35, .150, .097, .022, .010, wt(Spine2=1)),
                    (1.43, .146, .080, 0, 0, shoulders_w(wt(Spine2=1))),
                    (1.48, .052, .050, 0, 0, wt(Spine2=.3, Neck=.7))]
        return [R((0, 0, self.z(z)), rx, ry, w, f, b) for z, rx, ry, f, b, w in rows]

    def pelvis(self):
        if self.male:
            rows = [(1.00, .145, .095), (.90, .165, .105), (.80, .120, .085)]
        else:
            rows = [(1.00, .140, .092), (.90, .175, .112), (.80, .125, .088)]
        ws = [wt(Hips=1), wt(Hips=1), skirt_w(.3)]
        return [R((0, 0, self.z(z)), rx, ry, w) for (z, rx, ry), w in zip(rows, ws)]

    def _leg_line(self, si, a, b, z):
        A, Bj = self.J[bone(a, si)], self.J[bone(b, si)]
        t = (A.z - z) / (A.z - Bj.z)
        return A.lerp(Bj, t)

    def thigh(self, si):
        r = [.085, .083, .070, .054] if self.male else [.090, .086, .068, .050]
        ws = [wt(si, Hips=.5, UpLeg=.5), wt(si, UpLeg=.85, Hips=.15), wt(si, UpLeg=1), wt(si, UpLeg=.5, Leg=.5)]
        out = []
        for z, rr, w in zip((.93, .83, .68, .52), r, ws):
            z = self.z(z)
            out.append(R(self._leg_line(si, "UpLeg", "Leg", z), rr, rr * 1.05, w))
        return out

    def shin(self, si):
        r = [.054, .056, .044, .036] if self.male else [.050, .052, .040, .032]
        ws = [wt(si, UpLeg=.5, Leg=.5), wt(si, Leg=1), wt(si, Leg=1), wt(si, Leg=.6, Foot=.4)]
        out = []
        for z, rr, w, b in zip((.52, .44, .28, .12), r, ws, (0, .012, .004, 0)):
            z = self.z(z)
            out.append(R(self._leg_line(si, "Leg", "Foot", z), rr, rr, w, b=b))
        return out

    def foot(self, si):
        k = 1.0 if self.male else .92
        x = self.B["hip"] * si
        rows = [(.055, .045, .033, .040, wt(si, Foot=1)),
                (.005, .060, .044, .058, wt(si, Foot=.7, Leg=.3)),
                (-.075, .035, .047, .034, wt(si, Foot=.5, ToeBase=.5)),
                (-.155, .024, .040, .022, wt(si, ToeBase=1))]
        return [R((x, y * k, zc), rx * k, rz, w) for y, zc, rx, rz, w in rows]

    def _arm_at(self, si, dx):
        a = self.J[bone("Arm", si)]
        return Vector((a.x + si * dx, 0, a.z))

    def upper_arm(self, si):
        k = self.B["arm"]
        rows = [(-.07, .046, .054, wt(si, Shoulder=.6, Arm=.4)),
                (.01, .053, .052, wt(si, Arm=.8, Shoulder=.2)),
                (.14, .047, .045, wt(si, Arm=1)),
                (self.B["upper"], .040, .040, wt(si, Arm=.5, ForeArm=.5))]
        return [R(self._arm_at(si, dx), rx * k, ry * k, w) for dx, rx, ry, w in rows]

    def forearm(self, si):
        k = self.B["arm"]
        up, fo = self.B["upper"], self.B["fore"]
        rows = [(up, .040, .040, wt(si, Arm=.5, ForeArm=.5)),
                (up + .08, .043, .042, wt(si, ForeArm=1)),
                (up + fo - .06, .033, .030, wt(si, ForeArm=1)),
                (up + fo - .01, .028, .026, wt(si, ForeArm=.5, Hand=.5))]
        return [R(self._arm_at(si, dx), rx * k, ry * k, w) for dx, rx, ry, w in rows]

    def hand(self, si):
        """Palm and finger block: box rings (use n=4, phase pi/4) along x."""
        k = self.B["hand"]
        h = self.J[bone("Hand", si)]
        rows = [(-.012, .015, .032, wt(si, Hand=1)),
                (.075, .016, .042, wt(si, Hand=.5, HandMiddle1=.5)),
                (.120, .013, .040, wt(si, HandMiddle1=.3, HandMiddle2=.7)),
                (.158, .009, .035, wt(si, HandMiddle3=1))]
        return [R((h.x + si * dx * k, .004, h.z - .004), hz * k * SQ2, hy * k * SQ2, w) for dx, hz, hy, w in rows]

    def thumb(self, si):
        k = self.B["hand"]
        pts = [self.J[bone(f"HandThumb{i}", si)] for i in range(1, 5)]
        radii = [r * k for r in (.013, .012, .010, .008)]
        ws = [wt(si, HandThumb1=1), wt(si, HandThumb1=.3, HandThumb2=.7),
              wt(si, HandThumb2=.3, HandThumb3=.7), wt(si, HandThumb3=1)]
        return pts, radii, ws

    HEADS = {
        # z, rx, ry, y offset, front bulge  (neck, neck top, jaw, mouth, eyes, brow, crown, cap)
        ("male", "A"): [(.080, .094, .006), (.087, .100, .004), (.086, .099, .006)],
        ("male", "B"): [(.074, .092, .004), (.083, .098, .004), (.083, .098, .006)],
        ("male", "C"): [(.085, .096, .006), (.090, .101, .004), (.089, .101, .012)],
        ("female", "A"): [(.072, .088, .005), (.082, .095, .004), (.082, .094, .005)],
        ("female", "B"): [(.078, .090, .005), (.084, .096, .003), (.083, .095, .004)],
        ("female", "C"): [(.070, .088, .006), (.081, .094, .004), (.081, .094, .008)],
    }
    JAWS = {("male", "A"): (.068, .076), ("male", "B"): (.062, .072), ("male", "C"): (.076, .080),
            ("female", "A"): (.060, .068), ("female", "B"): (.066, .072), ("female", "C"): (.055, .066)}

    def head(self, variant):
        sex = self.B["sex"]
        neck = .052 if self.male else .046
        jaw = self.JAWS[(sex, variant)]
        mid = self.HEADS[(sex, variant)]
        top = (.067, .082) if self.male else (.064, .078)
        cap = (.030, .038) if self.male else (.028, .036)
        nw = wt(Neck=.4, Head=.6)
        rows = [(1.45, neck, neck, .012, 0, wt(Neck=1)),
                (1.535, neck * .96, neck * .96, .012, 0, nw),
                (1.545, jaw[0], jaw[1], -.010, 0, wt(Head=1)),
                (1.600, mid[0][0], mid[0][1], -.004, mid[0][2], wt(Head=1)),
                (1.665, mid[1][0], mid[1][1], 0, mid[1][2], wt(Head=1)),
                (1.730, mid[2][0], mid[2][1], .004, mid[2][2], wt(Head=1)),
                (1.790, top[0], top[1], .008, 0, wt(Head=1)),
                (1.818, cap[0], cap[1], .010, 0, wt(Head=1))]
        return [R((0, y, self.z(z)), rx, ry, w, f) for z, rx, ry, y, f, w in rows]

    def head_envelope(self):
        """The biggest of the heads, ring by ring: hair and helmets fit over it."""
        heads = [self.head(v) for v in "ABC"]
        out = []
        for rings in zip(*heads):
            r = dict(rings[0])
            r["rx"] = max(x["rx"] for x in rings)
            r["ry"] = max(x["ry"] for x in rings)
            r["f"] = max(x["f"] for x in rings)
            out.append(r)
        return out


def flat_bottom(verts, z=0.0):
    for v in verts:
        if v.co.z < z:
            v.co.z = z


# ------------------------------------------------------------ body parts
def build_body(b: Body, add):
    """add(name, part, slot, hides=(), variant=None) registers a finished part."""
    # torso: smallclothes on the female chest
    p = Part("Torso")
    if b.male:
        p.loft(b.torso(), SKIN, var=.04)
    else:
        p.loft(b.torso(), lambda k, i: base("linen") if k in (2, 3) else SKIN, var=.04)
    add(p, "body")

    p = Part("Arms_Upper")
    for si in (1, -1):
        p.loft(b.upper_arm(si), SKIN, u=UP, n=6, var=.04)
    add(p, "body")

    p = Part("Arms_Lower")
    for si in (1, -1):
        p.loft(b.forearm(si), SKIN, u=UP, n=6, var=.04)
    add(p, "body")

    p = Part("Hands")
    for si in (1, -1):
        p.loft(b.hand(si), SKIN, u=UP, n=4, phase=math.pi / 4, var=.04, smooth=False)
        p.tube(*b.thumb(si), SKIN, var=.04, smooth=False)
    add(p, "body")

    p = Part("Legs_Upper")
    p.loft(b.pelvis(), base("linen"), var=.05)
    for si in (1, -1):
        p.loft(b.thigh(si), SKIN, var=.04)
    add(p, "body")

    p = Part("Legs_Lower")
    for si in (1, -1):
        p.loft(b.shin(si), SKIN, var=.04)
    add(p, "body")

    p = Part("Feet")
    for si in (1, -1):
        flat_bottom(p.loft(b.foot(si), SKIN, u=SIDE, v=UP, n=6, var=.04, smooth=False))
    add(p, "body")

    for variant in "ABC":
        build_face(b, variant, add)
    build_hair(b, add)
    build_beards(b, add)


def build_face(b: Body, variant, add):
    p = Part(f"Face_{variant}")
    rings = b.head(variant)
    p.loft(rings, SKIN, var=.035)
    hw = wt(Head=1)
    mouth, eyes, brow = rings[3], rings[4], rings[5]
    ez, mz = eyes["c"].z, mouth["c"].z
    for sx in (1, -1):
        y, slope = front_y(eyes, .033)
        rz = -math.degrees(slope) * sx
        p.box((sx * .033, y - .001, ez + .002), (.011, .004, .0055), hw, base("eye"), rot=(0, 0, rz))
        # brows take the hair colour
        yb, sb = front_y(ring_at(rings, 2, ez + b.z(.024)), .034)
        p.box((sx * .034, yb - .002, ez + b.z(.024)), (.016, .004, .0035), hw, HAIR,
              rot=(0, 0, -math.degrees(sb) * sx))
        # ears
        p.box((sx * (eyes["rx"] + .004), eyes["c"].y + .006, ez - .008), (.006, .016, .022), hw, SKIN,
              rot=(0, 0, sx * 8))
    # nose
    nz = (ez + mz) * .5 + .006
    ny = front_y(ring_at(rings, 2, nz), 0)[0]
    nose = [R((0, ny + .006, nz), .011, .022, hw), R((0, ny - .018, nz - .008), .007, .008, hw)]
    p.loft(nose, SKIN, u=SIDE, v=UP, n=4, phase=math.pi / 4, smooth=False)
    # mouth
    my = front_y(mouth, 0)[0]
    p.box((0, my, mz - .002), (.016 if b.male else .014, .003, .0032), hw, base("lips"))
    add(p, "face", variant=variant)


def _hair_rings(b: Body, m, levels, front_line, w=None):
    env = b.head_envelope()
    eye_z = env[4]["c"].z
    rings = []
    for z in levels:
        z = b.z(z)
        r = ring_at(env, 2, max(z, eye_z))
        r["c"] = Vector((r["c"].x, r["c"].y, z))
        r = grow([r], m)[0]
        lift = max(0.0, b.z(front_line) - z)
        r["d"] = (lambda lf: (lambda ct, st: UP * (lf * max(0.0, st) ** 1.5)))(lift)
        r["w"] = w or wt(Head=1)
        rings.append(r)
    top = env[-1]
    rings.append(R(top["c"] + UP * (m + .004), top["rx"] * .5, top["ry"] * .5, wt(Head=1)))
    return rings


def hair_cap(p: Part, b: Body, m=.014, bottom=1.625, front_line=1.75, look=HAIR):
    levels = [bottom, (bottom + 1.735) / 2, 1.735, 1.79]
    p.loft(_hair_rings(b, m, levels, front_line), look, var=.10, smooth=False)


def build_hair(b: Body, add):
    p = Part("Hair_Short")
    hair_cap(p, b)
    add(p, "hair", variant="Short")

    p = Part("Hair_Cropped")
    hair_cap(p, b, m=.007, bottom=1.66, front_line=1.765)
    add(p, "hair", variant="Cropped")

    z = b.z
    p = Part("Hair_Long")
    hair_cap(p, b, m=.015)
    curl = lambda ct, st: FRONT * (ct * ct * .035)
    rows = [(1.74, .085, .080, .03, wt(Head=1)), (1.62, .108, .088, .022, wt(Head=1)),
            (1.50, .100, .086, .018, wt(Head=.5, Neck=.5)), (1.38, .128, .092, .014, wt(Neck=.4, Spine2=.6)),
            (1.28, .134, .084, .010, wt(Spine2=1))]
    p.loft([R((0, y, z(zz)), rx, ry, w, d=curl) for zz, y, rx, ry, w in rows], HAIR, var=.10, smooth=False)
    add(p, "hair", variant="Long")

    p = Part("Hair_Ponytail")
    hair_cap(p, b)
    pts = [Vector((0, .095, z(1.71))), Vector((0, .128, z(1.63))), Vector((0, .140, z(1.52))),
           Vector((0, .135, z(1.40)))]
    p.tube(pts, [.030, .025, .019, .010],
           [wt(Head=1), wt(Head=1), wt(Head=.5, Neck=.5), wt(Neck=.5, Spine2=.5)], HAIR, n=6, phase=0,
           up=FRONT, var=.10, smooth=False)
    add(p, "hair", variant="Ponytail")

    p = Part("Hair_Bun")
    hair_cap(p, b)
    c = Vector((0, .100, z(1.765)))
    p.loft([R(c + UP * .04, .018, .018, wt(Head=1)), R(c + UP * .012, .044, .040, wt(Head=1)),
            R(c - UP * .022, .040, .036, wt(Head=1)), R(c - UP * .040, .015, .015, wt(Head=1))],
           HAIR, var=.10, smooth=False)
    add(p, "hair", variant="Bun")


def build_beards(b: Body, add):
    env = b.head_envelope()
    jaw, mouth = env[2], env[3]
    hw = wt(Head=1)
    front = lambda k, i: i in (1, 2) or (k == 0)  # n=8: faces 0..3 are the front half

    def beard(name, grow_by, chin):
        p = Part(name, smooth=False)
        rings = [R(jaw["c"] + FRONT * .045 - UP * chin, .030, .022, hw)] if chin else []
        rings += grow([jaw, mouth], grow_by)
        for r in rings:
            r["w"] = hw
        p.loft(rings, HAIR, caps=(bool(chin), False), var=.10,
               skip=lambda k, i: not (0 <= i <= 3) or (k == len(rings) - 2 and i in (1, 2)))
        my = front_y(mouth, 0)[0]
        for sx in (1, -1):
            p.box((sx * .016, my - .004, mouth["c"].z + .006), (.016, .005, .004), hw, HAIR, rot=(0, 0, sx * 14))
        return p

    add(beard("Beard_Full", .012, b.z(.04)), "beard", variant="Full")
    add(beard("Beard_Short", .005, 0), "beard", variant="Short")
    p = Part("Beard_Moustache", smooth=False)
    my = front_y(mouth, 0)[0]
    for sx in (1, -1):
        p.box((sx * .017, my - .004, mouth["c"].z + .006), (.017, .005, .0045), hw, HAIR, rot=(0, 0, sx * 14))
    add(p, "beard", variant="Moustache")


# ----------------------------------------------------------------- armour
def trim_look(main, trim, rows):
    return lambda k, i: base(trim) if k in rows else base(main)


def sleeves(p, b, d, look, lower=False, upto=None, flat=False):
    for si in (1, -1):
        rings = grow(b.upper_arm(si), d)
        if lower:
            fa = grow(b.forearm(si), d)
            rings += fa[1:]
            rings[-1]["rx"] += .008
            rings[-1]["ry"] += .008
        elif upto:
            rings.append(grow([ring_at(b.forearm(si), 0, b._arm_at(si, upto).x)], d)[0])
        p.loft(rings, look if callable(look) else look, u=UP, n=6, caps=(False, False), var=.07,
               smooth=False if flat else None)


def chest_shell(b, d, f=0.0, collar=True):
    rings = grow(b.torso()[:6], d, f=f)
    if collar:
        neck = b.torso()[6]
        rings.append(R(neck["c"] - UP * .005, neck["rx"] + .028, neck["ry"] + .024, neck["w"]))
    return rings


def skirt(b, rows):
    return [R((0, 0, b.z(z)), rx, ry, skirt_w(a)) for z, rx, ry, a in rows]


def build_chest(b: Body, add):
    t = Part("Chest_Cloth")  # robe
    rings = skirt(b, [(.60, .19, .13, .6), (.74, .185, .125, .5), (.86, .172, .116, .25)])
    rings += chest_shell(b, .012)
    last = len(rings) - 2
    t.loft(rings, trim_look("robe", "robe_trim", (0, last)), caps=(False, True), var=.06)
    sleeves(t, b, .013, lambda k, i: base("robe_trim") if k == 5 else base("robe"), lower=True)
    add(t, "chest", variant="cloth", hides=["Torso", "Arms_Upper", "Arms_Lower"])

    t = Part("Chest_Leather")  # jerkin over a linen shirt
    rings = skirt(b, [(.80, .172, .118, .35), (.86, .168, .115, .25)]) + chest_shell(b, .014)
    belt = 2  # the band from the skirt into the waist ring
    t.loft(rings, lambda k, i: base("linen") if k == len(rings) - 2 else
           base("leather_dark") if k == belt else base("leather"), caps=(False, True), var=.08)
    sleeves(t, b, .009, base("linen"), upto=.03)
    add(t, "chest", variant="leather", hides=["Torso", "Arms_Upper"])

    t = Part("Chest_Mail")  # hauberk
    rings = skirt(b, [(.72, .182, .122, .5), (.86, .170, .115, .3)]) + chest_shell(b, .016)
    t.loft(rings, lambda k, i: base("leather_dark") if k == 0 else base("mail"), caps=(False, True), var=.16)
    sleeves(t, b, .013, base("mail"), upto=.05)
    add(t, "chest", variant="mail", hides=["Torso", "Arms_Upper"])

    t = Part("Chest_Plate", smooth=False)  # cuirass with faulds and rerebraces
    rings = skirt(b, [(.80, .184, .126, .3), (.88, .176, .121, .2)]) + chest_shell(b, .024, f=.01)
    t.loft(rings, lambda k, i: base("steel_dark") if k in (0, 2) else base("steel"), caps=(False, True), var=.05)
    sleeves(t, b, .018, base("steel"), upto=.02, flat=True)
    add(t, "chest", variant="plate", hides=["Torso", "Arms_Upper"])


def legs_shell(p, b, d, look_pelvis, look_thigh, look_shin, dt=None, ds=None, cuff=.004, flat=None):
    p.loft(grow(b.pelvis(), d), look_pelvis, var=.08, smooth=flat)
    for si in (1, -1):
        p.loft(grow(b.thigh(si), dt if dt is not None else d), look_thigh, caps=(False, False), var=.08,
               smooth=flat)
        shin = grow(b.shin(si), ds if ds is not None else d)
        shin[-1]["rx"] += cuff
        shin[-1]["ry"] += cuff
        p.loft(shin, look_shin, caps=(False, False), var=.08, smooth=flat)


def knee_box(p, b, si, look, size=(.032, .012, .036), out=.064):
    k = b._leg_line(si, "UpLeg", "Leg", b.z(.52))
    p.box((k.x, k.y - out, k.z), size, wt(si, UpLeg=.5, Leg=.5), look)


def build_legs(b: Body, add):
    hides = ["Legs_Upper", "Legs_Lower"]
    p = Part("Legs_Cloth")
    legs_shell(p, b, .010, base("cloth"), base("cloth"), base("cloth"))
    add(p, "legs", variant="cloth", hides=hides)

    p = Part("Legs_Leather")
    legs_shell(p, b, .011, base("leather_dark"), base("leather"), base("leather"))
    for si in (1, -1):
        knee_box(p, b, si, base("leather_dark"), size=(.03, .008, .032), out=.062)
    add(p, "legs", variant="leather", hides=hides)

    p = Part("Legs_Mail")
    legs_shell(p, b, .012, base("leather_dark"), base("mail"), base("mail"))
    add(p, "legs", variant="mail", hides=hides)

    p = Part("Legs_Plate")
    legs_shell(p, b, .012, base("mail"), base("steel"), base("steel"), dt=.018, ds=.018, flat=False)
    for si in (1, -1):
        knee_box(p, b, si, base("steel_dark"), size=(.038, .016, .040), out=.07)
    add(p, "legs", variant="plate", hides=hides)


def build_feet(b: Body, add):
    def boot(name, d, look, shaft, sole="leather_dark", flat=False, cap=None):
        p = Part(name, smooth=not flat)
        for si in (1, -1):
            foot = grow(b.foot(si), d)
            flat_bottom(p.loft(foot, lambda k, i: base(sole) if i in (4,) else look, u=SIDE, v=UP, n=6,
                               var=.07, smooth=False))
            if shaft:
                shin = b.shin(si)
                rings = [grow([ring_at(shin, 2, b.z(z))], d + .004)[0] for z in shaft]
                rings[-1]["rx"] += .008
                rings[-1]["ry"] += .008
                p.loft(rings, look, caps=(False, False), var=.07)
            if cap:
                toe = foot[-1]["c"]
                p.box((toe.x, toe.y + .01, .03), (.04, .03, .026), wt(si, ToeBase=1), base(cap))
        return p

    add(boot("Feet_Cloth", .006, base("rag"), (.10, .17), sole="cloth_dark"), "feet", variant="cloth",
        hides=["Feet"])
    add(boot("Feet_Leather", .010, base("leather"), (.10, .22, .34)), "feet", variant="leather", hides=["Feet"])
    add(boot("Feet_Mail", .010, base("leather_dark"), (.10, .22, .36), cap="iron"), "feet", variant="mail",
        hides=["Feet"])
    add(boot("Feet_Plate", .013, base("steel"), (.10, .22, .32), sole="iron", flat=True), "feet",
        variant="plate", hides=["Feet"])


def build_hands(b: Body, add):
    def glove(name, d, look, cuff=None, studs=None, flat=True):
        p = Part(name, smooth=not flat)
        for si in (1, -1):
            p.loft(grow(b.hand(si), d * SQ2), look, u=UP, n=4, phase=math.pi / 4, var=.06, smooth=False)
            pts, radii, ws = b.thumb(si)
            p.tube(pts, [r + d for r in radii], ws, look, var=.06, smooth=False)
            if cuff:
                fa = b.forearm(si)
                x0 = b._arm_at(si, b.B["upper"] + b.B["fore"] - cuff[0]).x
                x1 = b._arm_at(si, b.B["upper"] + b.B["fore"] - .005).x
                rings = [grow([ring_at(fa, 0, x0)], cuff[1])[0], grow([ring_at(fa, 0, x1)], cuff[2])[0]]
                p.loft(rings, look, u=UP, n=6, caps=(False, False), var=.06, smooth=False)
            if studs:
                h = b.J[bone("Hand", si)]
                p.box((h.x + si * .08 * b.B["hand"], .004, h.z + .02 * b.B["hand"]), (.012, .036, .006),
                      wt(si, Hand=.5, HandMiddle1=.5), base(studs))
        return p

    add(glove("Hands_Cloth", .004, base("rag"), cuff=(.04, .006, .006)), "hands", variant="cloth", hides=["Hands"])
    add(glove("Hands_Leather", .006, base("leather"), cuff=(.07, .016, .008)), "hands", variant="leather",
        hides=["Hands"])
    add(glove("Hands_Mail", .006, base("leather_dark"), cuff=(.06, .012, .008), studs="iron"), "hands",
        variant="mail", hides=["Hands"])
    add(glove("Hands_Plate", .009, base("steel"), cuff=(.08, .022, .010)), "hands", variant="plate",
        hides=["Hands"])


def build_wrists(b: Body, add):
    def bracer(name, d, look, flat=False, band=None):
        p = Part(name, smooth=not flat)
        for si in (1, -1):
            fa = b.forearm(si)
            up, fo = b.B["upper"], b.B["fore"]
            xs = [up + .09, up + fo * .62, up + fo - .03]
            rings = [grow([ring_at(fa, 0, b._arm_at(si, x).x)], d)[0] for x in xs]
            p.loft(rings, (lambda k, i: base(band) if k == 1 else look) if band else look, u=UP, n=6,
                   caps=(False, False), var=.07)
        return p

    add(bracer("Wrists_Cloth", .006, base("rag")), "wrists", variant="cloth")
    add(bracer("Wrists_Leather", .010, base("leather"), band="leather_dark"), "wrists", variant="leather")
    add(bracer("Wrists_Mail", .010, base("mail")), "wrists", variant="mail")
    add(bracer("Wrists_Plate", .013, base("steel"), flat=True), "wrists", variant="plate")


def build_waist(b: Body, add):
    torso = b.torso()

    def belt(name, d, look, buckle, z0=.975, z1=1.025, pouch=None, tail=None):
        p = Part(name, smooth=False)
        rings = [grow([ring_at(torso, 2, b.z(z))], d)[0] for z in (z0, z1)]
        for r in rings:
            r["w"] = wt(Hips=1)
        p.loft(rings, look, var=.06)
        zc = (rings[0]["c"].z + rings[1]["c"].z) / 2
        fy = front_y(ring_at(rings, 2, zc), 0)[0]
        if buckle:
            p.box((0, fy - .002, zc), (.022, .005, .019), wt(Hips=1), base(buckle))
        if pouch:
            p.box((.11, fy + .03, zc - .045), (.03, .02, .035), wt(Hips=1), base(pouch), rot=(0, 0, 25))
        if tail:
            p.box((.09, fy + .02, zc - .09), (.022, .008, .09), wt(Hips=.6, LeftUpLeg=.4) if False else
                  {bone("Hips"): .6, bone("UpLeg", 1): .4}, base(tail), rot=(0, 0, 20))
        return p

    add(belt("Waist_Cloth", .022, base("robe_trim"), None, tail="robe_trim"), "waist", variant="cloth")
    add(belt("Waist_Leather", .026, base("leather_dark"), "brass", pouch="leather"), "waist", variant="leather")
    add(belt("Waist_Mail", .028, base("leather_dark"), "iron", pouch="leather_dark"), "waist", variant="mail")
    add(belt("Waist_Plate", .034, base("leather_dark"), "steel", z0=.965, z1=1.035), "waist", variant="plate")


def build_shoulders(b: Body, add):
    def pad(p, si, look, size, lames=0, rim=None):
        a = b.J[bone("Arm", si)]
        k = 1.0 if b.male else .9
        lx, ly, lz = size
        flat = lambda ct, st: UP * (max(0.0, -ct) * lx * .9)
        rows = [(-.06, .45, wt(si, Shoulder=.6, Arm=.4)), (-.01, 1.0, wt(si, Shoulder=.4, Arm=.6)),
                (.06, .95, wt(si, Arm=.85, Shoulder=.15)), (.10 * k, .7, wt(si, Arm=1))]
        rings = [R((a.x + si * dx * k, 0, a.z + lz), lx * m, ly * m, w, d=flat) for dx, m, w in rows]
        p.loft(rings, (lambda kk, i: base(rim) if kk == 2 else look) if rim else look, u=UP, n=8, var=.06,
               smooth=False)
        for j in range(lames):
            dz = -.035 * (j + 1)
            p.box((a.x + si * (.11 + .015 * j) * k, 0, a.z + lz + dz), (.022, ly * .95, .018),
                  wt(si, Arm=1), look, rot=(0, si * 35, 0))

    p = Part("Shoulders_Cloth")  # mantle
    torso = b.torso()
    collar = torso[6]
    rings = [R(collar["c"], collar["rx"] + .03, collar["ry"] + .026, collar["w"]),
             R((0, 0, b.z(1.43)), b.B["sh"] + .05, .135, shoulders_w(wt(Spine2=1), .9)),
             R((0, 0, b.z(1.33)), b.B["sh"] + .075, .150, shoulders_w(wt(Spine2=1), .9))]
    p.loft(rings[::-1], lambda k, i: base("robe_trim") if k == 0 else base("cloak"), caps=(False, True), var=.08)
    add(p, "shoulders", variant="cloth")

    for name, look, size, lames, rim in (("leather", base("leather"), (.068, .072, .03), 0, "leather_dark"),
                                         ("mail", base("mail"), (.074, .078, .028), 1, "leather_dark"),
                                         ("plate", base("steel"), (.082, .086, .034), 2, "steel_dark")):
        p = Part(f"Shoulders_{name.title()}", smooth=False)
        for si in (1, -1):
            pad(p, si, look, size, lames, rim)
        add(p, "shoulders", variant=name)


def build_back(b: Body, add):
    def cloak(name, colour, rows, trim=None):
        p = Part(name)
        wrap = lambda ct, st: FRONT * (ct * ct * .07)
        rings = [R((0, y, b.z(z)), rx, .009, w, d=wrap) for z, y, rx, w in rows]
        last = len(rings) - 2
        p.loft(rings, (lambda k, i: base(trim) if k == last else base(colour)) if trim else base(colour),
               var=.08)
        return p

    long_rows = [(1.47, .110, .150, wt(Spine2=1)), (1.30, .150, .190, wt(Spine2=.7, Spine1=.3)),
                 (1.00, .172, .210, wt(Spine=.5, Hips=.5)), (.75, .198, .222, skirt_w(.2)),
                 (.55, .228, .232, skirt_w(.3))]
    add(cloak("Back_Cloth", "cloak", long_rows), "back", variant="cloth")
    add(cloak("Back_Leather", "fur", [(1.48, .105, .170, wt(Spine2=1)), (1.36, .140, .215, wt(Spine2=1)),
                                      (1.18, .158, .225, wt(Spine2=.4, Spine1=.6))]), "back", variant="leather")
    add(cloak("Back_Mail", "cloak_dark", long_rows, trim="robe_trim"), "back", variant="mail")
    add(cloak("Back_Plate", "cloak_red", long_rows, trim="brass"), "back", variant="plate")


def build_head(b: Body, add):
    env = b.head_envelope()
    z = b.z

    def shell(d, zs, extra=0.0):
        rings = []
        for zz in zs:
            r = grow([ring_at(env, 2, z(zz))], d + extra * max(0.0, zz - 1.70))[0]
            r["w"] = wt(Head=1)
            rings.append(r)
        return rings

    # hood: open face, draped over the shoulders
    p = Part("Head_Cloth")
    drape = [R((0, .01, z(1.42)), .17, .13, shoulders_w(wt(Spine2=1), .6)),
             R((0, .012, z(1.49)), .078, .076, wt(Spine2=.4, Neck=.6))]
    rings = drape + shell(.022, (1.545, 1.60, 1.665, 1.73, 1.79))
    rings.append(R(env[-1]["c"] + UP * .028 + Vector((0, .03, 0)), .03, .045, wt(Head=1)))
    hole = {2, 3, 4}
    p.loft(rings, base("cloak"), caps=(False, True), var=.08, smooth=False,
           skip=lambda k, i: k in hole and i in (1, 2))
    add(p, "head", variant="cloth", hides=["Hair"])

    # leather cap
    p = Part("Head_Leather", smooth=False)
    rings = _hair_rings(b, .024, [1.66, 1.70, 1.745, 1.79], 1.70)
    p.loft(rings, lambda k, i: base("leather_dark") if k == 0 else base("leather"), var=.08)
    add(p, "head", variant="leather", hides=["Hair"])

    # iron cap with a nasal over a mail aventail
    p = Part("Head_Mail", smooth=False)
    cap = shell(.026, (1.70, 1.745, 1.79))
    cap.insert(0, grow([cap[0]], .012)[0])
    cap[0]["c"] = cap[0]["c"] - UP * .008
    cap.append(R(env[-1]["c"] + UP * .03, .035, .042, wt(Head=1)))
    p.loft(cap, lambda k, i: base("steel_dark") if k == 0 else base("iron"), var=.06)
    fy = front_y(cap[1], 0)[0]
    p.box((0, fy - .004, cap[1]["c"].z - .05), (.008, .005, .045), wt(Head=1), base("iron"))
    av = [R((0, .015, z(1.43)), .15, .12, shoulders_w(wt(Spine2=1), .6)),
          R((0, .012, z(1.50)), .082, .080, wt(Spine2=.3, Neck=.7))] + shell(.03, (1.56, 1.63, 1.705))
    p.loft(av, base("mail"), caps=(False, False), var=.16, skip=lambda k, i: k in (2, 3) and i in (1, 2))
    add(p, "head", variant="mail", hides=["Hair"])

    # great helm: closed, with an eye slit
    p = Part("Head_Plate", smooth=False)
    rings = [R((0, .012, z(1.47)), .09, .09, wt(Neck=.6, Spine2=.4))]
    rings += shell(.032, (1.55, 1.62, 1.66, 1.69, 1.75, 1.80))
    rings.append(R(env[-1]["c"] + UP * .035, .04, .05, wt(Head=1)))
    p.loft(rings, lambda k, i: base("black") if k == 3 and i in (1, 2) else base("steel"), var=.05)
    top = rings[-1]["c"]
    p.box((0, top.y, top.z + .006), (.006, .07, .012), wt(Head=1), base("steel_dark"))
    add(p, "head", variant="plate", hides=["Hair", "Beard", "Face"])


# ----------------------------------------------------------------- export
def build_human(key):
    b = Body(key)
    arm = make_armature(b.J)
    parts = {}

    def add(p, slot, variant=None, hides=()):
        obj = p.to_object(arm)
        parts[obj.name] = {"slot": slot, "variant": variant, "hides": list(hides),
                           "tris": sum(len(f.vertices) - 2 for f in obj.data.polygons), "obj": obj}

    build_body(b, add)
    build_head(b, add)
    build_shoulders(b, add)
    build_back(b, add)
    build_chest(b, add)
    build_wrists(b, add)
    build_hands(b, add)
    build_waist(b, add)
    build_legs(b, add)
    build_feet(b, add)
    return arm, parts


def export(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_yup=True,
        export_apply=True,
        export_skins=True,
        export_animations=False,
        export_materials="EXPORT",
        export_extras=False,
        export_cameras=False,
        export_lights=False,
    )


def organise(parts):
    """Sort parts into one collection per slot for the .blend, showing only a
    plain body (Face_A, Hair_Short) until a collection is switched on."""
    scene = bpy.context.scene
    shown = {"Face_A", "Hair_Short"}
    for name, info in parts.items():
        cname = info["slot"].title()
        col = bpy.data.collections.get(cname)
        if col is None:
            col = bpy.data.collections.new(cname)
            scene.collection.children.link(col)
        obj = info["obj"]
        scene.collection.objects.unlink(obj)
        col.objects.link(obj)
        if info["slot"] in ("face", "hair", "beard") and name not in shown:
            obj.hide_set(True)
            obj.hide_render = True
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.name not in ("Body", "Face", "Hair", "Beard"):
            lc.hide_viewport = True


def godot_name(b):
    return b.replace(":", "_")


def manifest(parts):
    m = {"skeleton": "mixamorig", "bones": [godot_name(b) for b in BONES],
         "hand_bones": {"main": godot_name(bone("Hand", -1)), "off": godot_name(bone("Hand", 1))},
         "body": [], "looks": {}, "armour": {}}
    for name, info in parts.items():
        if info["slot"] == "body":
            m["body"].append(name)
        elif info["slot"] in ("face", "hair", "beard"):
            m["looks"].setdefault(info["slot"], {})[info["variant"]] = name
        else:
            m["armour"].setdefault(info["slot"], {})[info["variant"]] = {"part": name, "hides": info["hides"]}
    return m


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    os.makedirs(OUT, exist_ok=True)
    shared = None
    for key in ("male", "female"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        rng.seed(1997)
        arm, parts = build_human(key)
        path = os.path.join(OUT, f"human_{key}.glb")
        export(path)
        # an editable copy for working on by hand in Blender
        organise(parts)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, f"human_{key}.blend"))
        tris = {n: i["tris"] for n, i in parts.items()}
        print(f"{key}: {len(parts)} parts, {sum(tris.values())} tris in all -> {path}")
        for n, t in tris.items():
            print(f"   {n:18s} {t}")
        shared = manifest(parts)
    shared["bodies"] = {"male": "human_male", "female": "human_female"}
    with open(os.path.join(OUT, "human_parts.json"), "w") as fh:
        json.dump(shared, fh, indent=1)
    if preview:
        import preview_humans
        preview_humans.render(preview)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    main()
