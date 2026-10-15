"""
Shadowfall asset builder.

Builds every low-poly model used by the prototype in Blender and exports each
one as glTF binary (.glb, loaded by the browser build) and FBX (for a later
move to Unity).

Run headless with either:
    blender --background --python assets/blender/build_assets.py
or, with the bpy module installed (pip install bpy):
    python assets/blender/build_assets.py

Conventions (the game code relies on these):
  * 1 Blender unit = 1 metre. Models stand on Z=0 and face Blender -Y
    (which becomes +Z "forward" after glTF's Y-up conversion).
  * All colour lives in a per-corner colour attribute named "Col", with slight
    per-face variation for a hand-painted look. Meshes share one material,
    "M_Base"; anything that should glow uses "M_Glow".
  * Animated characters are split into parts whose object origin sits at the
    joint: Torso, Head, Arm_L, Arm_R, Leg_L, Leg_R, and a Weapon parented to
    Arm_R. The game animates these procedurally by name.
"""
import math
import os
import random
import sys

import bpy  # must be imported before bmesh when running as a Python module
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_GLB = os.path.normpath(os.path.join(HERE, "..", "models"))
OUT_FBX = os.path.normpath(os.path.join(HERE, "..", "fbx"))
os.makedirs(OUT_GLB, exist_ok=True)
os.makedirs(OUT_FBX, exist_ok=True)

rng = random.Random(1997)

# ---------------------------------------------------------------- palette
P = {
    "cloth": (0.20, 0.19, 0.16),
    "cloak": (0.17, 0.20, 0.15),
    "leather": (0.30, 0.20, 0.12),
    "leather_dark": (0.18, 0.12, 0.08),
    "skin": (0.62, 0.48, 0.38),
    "hair": (0.16, 0.12, 0.09),
    "steel": (0.52, 0.53, 0.54),
    "steel_dark": (0.30, 0.31, 0.33),
    "steel_bright": (0.70, 0.71, 0.70),
    "brass": (0.55, 0.42, 0.20),
    "ash": (0.42, 0.40, 0.36),
    "ash_dark": (0.27, 0.25, 0.23),
    "bone": (0.66, 0.62, 0.52),
    "rag": (0.24, 0.22, 0.18),
    "rust": (0.36, 0.20, 0.11),
    "iron": (0.22, 0.22, 0.23),
    "wood": (0.33, 0.23, 0.14),
    "wood_dark": (0.20, 0.14, 0.09),
    "wood_grey": (0.36, 0.33, 0.29),
    "stone": (0.42, 0.41, 0.38),
    "stone_dark": (0.28, 0.28, 0.27),
    "moss": (0.20, 0.27, 0.14),
    "pine": (0.11, 0.19, 0.12),
    "pine_dark": (0.08, 0.14, 0.09),
    "bark": (0.22, 0.16, 0.11),
    "parchment": (0.72, 0.64, 0.46),
    "cloth_red": (0.38, 0.12, 0.10),
    "candle": (0.85, 0.80, 0.64),
    "flame": (1.0, 0.70, 0.30),
    "eye": (0.75, 0.70, 0.45),
    "coin": (0.72, 0.58, 0.25),
    "glass": (0.30, 0.42, 0.36),
    "draught": (0.55, 0.12, 0.10),
    "grave_iron": (0.25, 0.26, 0.30),
    "black": (0.05, 0.05, 0.05),
    "fur": (0.26, 0.25, 0.23),
    "fur_dark": (0.15, 0.14, 0.13),
    "bone_old": (0.55, 0.52, 0.44),
    "robe": (0.12, 0.11, 0.13),
    "robe_trim": (0.25, 0.20, 0.30),
    "witchlight": (0.45, 0.85, 0.70),
    "blackwood": (0.10, 0.08, 0.07),
    "pine_black": (0.06, 0.11, 0.09),
    "pine_black2": (0.04, 0.08, 0.07),
    "lichen": (0.36, 0.40, 0.30),
}

# ------------------------------------------------------------ scene setup


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_material(name, emissive=False):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    if emissive:
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.65, 0.3, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.5
    return mat


class Builder:
    """Accumulates geometry for one mesh object, colouring faces as it goes."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.glow_faces = set()

    def _finish(self, geom_verts, color, var, glow=False):
        faces = set()
        for v in geom_verts:
            for f in v.link_faces:
                faces.add(f)
        for f in faces:
            k = 1.0 + rng.uniform(-var, var)
            # palette values are display (sRGB) colours; the exporter writes linear glTF colours
            c = tuple(max(0.0, min(1.0, ch * k)) for ch in color) + (1.0,)
            for loop in f.loops:
                loop[self.col] = c
            if glow:
                f.material_index = 1
            f.smooth = False

    def _xform(self, verts, size, loc, rot):
        m = Matrix.Translation(Vector(loc))
        if rot:
            m = m @ (
                Matrix.Rotation(math.radians(rot[2]), 4, "Z")
                @ Matrix.Rotation(math.radians(rot[1]), 4, "Y")
                @ Matrix.Rotation(math.radians(rot[0]), 4, "X")
            )
        m = m @ Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)

    def box(self, size, loc, color, rot=None, var=0.08, glow=False, taper=None):
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = res["verts"]
        if taper:  # scale the top face (z > 0) in x/y
            for v in verts:
                if v.co.z > 0:
                    v.co.x *= taper[0]
                    v.co.y *= taper[1]
        self._xform(verts, size, loc, rot)
        self._finish(verts, color, var, glow)
        return verts

    def cyl(self, r1, r2, depth, loc, color, segs=8, rot=None, var=0.08, glow=False):
        res = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segs,
            radius1=r1, radius2=r2, depth=depth,
        )
        verts = res["verts"]
        self._xform(verts, (1, 1, 1), loc, rot)
        self._finish(verts, color, var, glow)
        return verts

    def ball(self, r, loc, color, scale=(1, 1, 1), subdiv=1, rot=None, var=0.08, glow=False, jitter=0.0):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=r)
        verts = res["verts"]
        if jitter:
            for v in verts:
                v.co += Vector((rng.uniform(-jitter, jitter) for _ in range(3)))
        self._xform(verts, scale, loc, rot)
        self._finish(verts, color, var, glow)
        return verts

    def to_object(self, name, parent=None, location=(0, 0, 0)):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        if "Col" in me.color_attributes:
            me.color_attributes.active_color = me.color_attributes["Col"]
            me.color_attributes.render_color_index = me.color_attributes.find("Col")
        me.materials.append(get_material("M_Base"))
        me.materials.append(get_material("M_Glow", emissive=True))
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = location
        if parent:
            obj.parent = parent
        return obj


def empty(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    if parent:
        obj.parent = parent
    return obj


def part(name, parent, joint, fn):
    """Build a part whose origin is at `joint` (given in parent space)."""
    b = Builder()
    fn(b)
    return b.to_object(name, parent=parent, location=joint)


def export(name):
    glb = os.path.join(OUT_GLB, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=glb,
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
    try:
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(OUT_FBX, name + ".fbx"),
            apply_scale_options="FBX_SCALE_ALL",
            axis_forward="-Z",
            axis_up="Y",
            mesh_smooth_type="FACE",
            add_leaf_bones=False,
        )
    except Exception as exc:  # FBX is a convenience for Unity, not required
        print("FBX export failed for", name, exc)
    print("exported", name)


# ------------------------------------------------------------- characters


def build_warden():
    root = empty("Warden")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.17, 0.19, 0.48), (0, 0, -0.26), P["cloth"])          # thigh
            b.box((0.15, 0.17, 0.40), (0, 0.01, -0.66), P["leather_dark"])  # shin/boot
            b.box((0.16, 0.26, 0.10), (0, -0.05, -0.88), P["leather_dark"])  # foot
            b.box((0.18, 0.08, 0.14), (0, -0.09, -0.52), P["leather"])     # knee pad
        return part("Leg_" + side, root, (0.12 * s, 0, 0.93), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.42, 0.26, 0.24), (0, 0, 0.10), P["cloth"])                     # waist
        b.box((0.46, 0.28, 0.40), (0, 0, 0.42), P["leather"], taper=(1.12, 1.0))  # chest jerkin
        b.box((0.48, 0.30, 0.06), (0, 0, 0.18), P["leather_dark"])              # belt
        b.box((0.08, 0.04, 0.07), (0, -0.16, 0.18), P["brass"])                 # buckle
        b.box((0.10, 0.08, 0.16), (0.2, -0.08, 0.06), P["leather_dark"])        # pouch
        b.box((0.54, 0.10, 0.70), (0, 0.17, 0.22), P["cloak"], rot=(-6, 0, 0), taper=(0.75, 1))  # cloak
        b.box((0.16, 0.06, 0.62), (0.0, 0.18, 0.16), P["cloak"], rot=(-8, 0, 0))
        b.box((0.10, 0.16, 0.50), (-0.10, 0.14, 0.40), P["leather_dark"], rot=(0, 30, 0))  # scabbard strap
    t = part("Torso", root, (0, 0, 0.92), torso)

    def head(b):
        b.box((0.08, 0.08, 0.08), (0, 0, 0.03), P["skin"])                   # neck
        b.box((0.22, 0.24, 0.26), (0, 0, 0.19), P["skin"], taper=(0.92, 0.9))  # face
        b.box((0.30, 0.30, 0.24), (0, 0.04, 0.24), P["cloak"], taper=(0.75, 0.8))  # hood
        b.box((0.30, 0.10, 0.30), (0, 0.13, 0.14), P["cloak"])               # hood back
        b.box((0.20, 0.03, 0.03), (0, -0.12, 0.22), P["black"], var=0.0)    # eye shadow band
        b.box((0.24, 0.20, 0.08), (0, -0.01, 0.07), P["hair"])              # beard/collar shadow
    part("Head", t, (0, 0, 0.66), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.24, 0.26, 0.14), (0.02 * s, 0, 0.0), P["steel_dark"], var=0.05)  # pauldron
            b.box((0.12, 0.13, 0.32), (0, 0, -0.18), P["cloth"])            # upper arm
            b.box((0.12, 0.13, 0.30), (0, -0.01, -0.46), P["leather"])      # bracer
            b.box((0.10, 0.11, 0.10), (0, -0.01, -0.65), P["skin"])         # hand
        return part("Arm_" + side, t, (0.30 * s, 0, 0.56), fn)

    arm("L")
    ar = arm("R")

    def sword(b):
        b.box((0.04, 0.04, 0.16), (0, 0, 0.0), P["leather_dark"])          # grip
        b.box((0.24, 0.05, 0.04), (0, 0, 0.10), P["iron"])                 # crossguard
        b.ball(0.035, (0, 0, -0.10), P["iron"], subdiv=0)                  # pommel
        b.box((0.06, 0.015, 0.78), (0, 0, 0.51), P["steel"], var=0.12, taper=(0.5, 1))  # worn blade
        b.box((0.02, 0.02, 0.05), (0.03, 0, 0.46), P["rust"])              # nick in the blade
    # sword held in the hand, blade pointing forward (-Y)
    part("Weapon", ar, (0, -0.02, -0.66), sword).rotation_euler = (math.radians(80), 0, 0)
    export("warden")


def build_ghoul():
    root = empty("Ghoul")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.12, 0.13, 0.42), (0, 0.02, -0.22), P["ash"])
            b.box((0.10, 0.11, 0.38), (0, 0.06, -0.58), P["ash_dark"])
            b.box((0.12, 0.24, 0.07), (0, -0.04, -0.78), P["ash_dark"])
            b.box((0.16, 0.16, 0.20), (0, 0, -0.10), P["rag"])  # rag wrap
        return part("Leg_" + side, root, (0.11 * s, 0, 0.82), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.30, 0.20, 0.22), (0, 0, 0.08), P["rag"])
        b.box((0.36, 0.24, 0.40), (0, -0.04, 0.36), P["ash"], rot=(-18, 0, 0), taper=(1.1, 1))
        for i in range(4):  # ribs showing through
            b.box((0.30, 0.04, 0.03), (0, -0.18 + 0.03 * i, 0.26 + i * 0.07), P["bone"], rot=(-18, 0, 0))
        b.box((0.30, 0.10, 0.26), (0.05, 0.12, 0.42), P["rag"], rot=(-25, 8, 0))  # tattered back cloth
        b.box((0.16, 0.06, 0.30), (-0.08, 0.15, 0.20), P["rag"], rot=(-10, -10, 0))
    t = part("Torso", root, (0, 0, 0.80), torso)

    def head(b):
        b.box((0.18, 0.20, 0.22), (0, -0.04, 0.12), P["ash"], taper=(0.85, 0.9))
        b.box((0.14, 0.10, 0.06), (0, -0.10, 0.00), P["bone"])  # jaw
        b.box((0.04, 0.02, 0.025), (0.045, -0.14, 0.14), P["eye"], var=0.0, glow=True)
        b.box((0.04, 0.02, 0.025), (-0.045, -0.14, 0.14), P["eye"], var=0.0, glow=True)
        b.box((0.20, 0.18, 0.06), (0, 0.0, 0.24), P["hair"], var=0.2)
    part("Head", t, (0, -0.16, 0.58), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.09, 0.10, 0.38), (0, 0, -0.18), P["ash"])
            b.box((0.08, 0.09, 0.36), (0, 0, -0.52), P["ash_dark"])
            for k in range(3):  # long fingers / claws
                b.box((0.02, 0.02, 0.12), ((k - 1) * 0.03, -0.02, -0.75), P["bone"])
        return part("Arm_" + side, t, (0.22 * s, -0.08, 0.50), fn)

    arm("L")
    arm("R")
    export("ghoul")


def build_brute():
    root = empty("Brute")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.28, 0.30, 0.56), (0, 0, -0.30), P["ash_dark"])
            b.box((0.26, 0.28, 0.46), (0, 0.02, -0.80), P["iron"], var=0.12)  # greave
            b.box((0.28, 0.40, 0.14), (0, -0.07, -1.04), P["iron"])
            b.box((0.30, 0.18, 0.20), (0, -0.08, -0.50), P["rust"])            # knee plate
        return part("Leg_" + side, root, (0.22 * s, 0, 1.12), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.66, 0.42, 0.34), (0, 0, 0.14), P["rag"])
        b.box((0.86, 0.56, 0.72), (0, -0.02, 0.62), P["ash_dark"], rot=(-10, 0, 0), taper=(1.15, 1.05))
        b.box((0.80, 0.30, 0.54), (0, -0.20, 0.62), P["rust"], rot=(-10, 0, 0), var=0.15)  # rusted breastplate
        b.box((0.20, 0.10, 0.20), (0.18, -0.36, 0.72), P["iron"], rot=(-10, 0, 20))
        b.box((0.66, 0.20, 0.36), (0, 0.24, 0.92), P["ash_dark"], rot=(-25, 0, 0))  # hunched shoulders
        # chain collar with a grave bell hanging from it
        for i in range(8):
            a = i / 8 * math.tau
            b.box((0.08, 0.08, 0.05), (math.cos(a) * 0.34, math.sin(a) * 0.26 - 0.02, 1.02), P["iron"])
        b.cyl(0.10, 0.05, 0.16, (0.10, -0.36, 0.86), P["brass"], segs=8)
        b.ball(0.025, (0.10, -0.36, 0.76), P["iron"], subdiv=0)
        for i in range(5):  # grave-dirt rag skirt strips
            b.box((0.12, 0.05, 0.40), (-0.28 + i * 0.14, -0.22, -0.10), P["rag"], rot=(8, 0, rng.uniform(-6, 6)))
    t = part("Torso", root, (0, 0, 1.10), torso)

    def head(b):
        b.box((0.30, 0.32, 0.32), (0, -0.06, 0.12), P["ash"], taper=(0.9, 0.9))
        b.box((0.38, 0.38, 0.22), (0, -0.04, 0.24), P["iron"], var=0.1, taper=(0.85, 0.85))  # helm
        b.box((0.30, 0.04, 0.05), (0, -0.25, 0.16), P["black"], var=0.0)  # visor slit
        b.box((0.05, 0.02, 0.03), (0.07, -0.24, 0.16), P["eye"], var=0.0, glow=True)
        b.box((0.05, 0.02, 0.03), (-0.07, -0.24, 0.16), P["eye"], var=0.0, glow=True)
        b.cyl(0.03, 0.0, 0.18, (0.16, -0.02, 0.38), P["iron"], segs=4, rot=(0, 25, 0))  # broken spikes
        b.cyl(0.03, 0.0, 0.12, (-0.14, 0.02, 0.36), P["iron"], segs=4, rot=(0, -25, 0))
    part("Head", t, (0, -0.22, 1.08), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.40, 0.42, 0.26), (0.06 * s, 0, 0.0), P["iron"], var=0.12)  # pauldron
            b.box((0.20, 0.22, 0.52), (0, 0, -0.30), P["ash_dark"])
            b.box((0.22, 0.24, 0.44), (0, -0.02, -0.74), P["rust"])
            b.box((0.20, 0.22, 0.16), (0, -0.02, -1.02), P["ash"])
        return part("Arm_" + side, t, (0.54 * s, -0.02, 0.88), fn)

    arm("L")
    ar = arm("R")

    def cleaver(b):
        b.box((0.06, 0.06, 0.50), (0, 0, 0.10), P["wood_dark"])
        b.box((0.06, 0.32, 0.70), (0, -0.10, 0.62), P["iron"], var=0.15, taper=(1, 0.7))
        b.box((0.07, 0.06, 0.20), (0, -0.24, 0.70), P["rust"])
    part("Weapon", ar, (0, -0.02, -1.04), cleaver).rotation_euler = (math.radians(70), 0, 0)
    export("brute")


# ------------------------------------------------------------------ props


def build_cart():
    b = Builder()
    tilt = (0, 9, 0)  # sagging towards the lost wheel
    b.box((1.40, 2.60, 0.12), (0, 0, 0.70), P["wood"], rot=tilt)               # bed
    b.box((0.08, 2.60, 0.40), (0.68, 0, 0.94), P["wood_grey"], rot=tilt)       # side
    b.box((0.08, 1.30, 0.34), (-0.62, 0.62, 0.86), P["wood_grey"], rot=(0, 20, 6))  # broken side
    b.box((1.40, 0.08, 0.40), (0, 1.28, 0.94), P["wood_grey"], rot=tilt)       # back board
    for x in (-0.4, 0.0, 0.4):
        b.box((0.08, 2.5, 0.06), (x, 0, 0.78), P["wood_dark"], rot=tilt)
    b.box((0.10, 1.80, 0.10), (-0.25, -2.0, 0.40), P["wood_dark"], rot=(12, 0, 0))  # shafts
    b.box((0.10, 1.80, 0.10), (0.25, -2.0, 0.34), P["wood_dark"], rot=(16, 0, 3))
    b.box((1.70, 0.12, 0.12), (0, 0.6, 0.55), P["iron"], rot=tilt)             # axle
    # three wheels remain; the fourth is lost
    for (x, y, z) in ((0.82, 0.6, 0.48), (0.82, -0.8, 0.48), (-0.78, -0.8, 0.40)):
        b.cyl(0.48, 0.48, 0.08, (x, y, z), P["wood_dark"], segs=10, rot=(0, 90, 0))
        b.cyl(0.10, 0.10, 0.12, (x, y, z), P["iron"], segs=6, rot=(0, 90, 0))
    b.box((0.12, 0.12, 0.70), (-0.70, 0.6, 0.20), P["wood_dark"], rot=(0, 30, 0))  # broken axle stub
    # remaining cargo: an iron-banded chest with its lid forced
    b.box((0.60, 0.50, 0.36), (0.25, 0.4, 1.0), P["wood"], rot=tilt)
    b.box((0.62, 0.06, 0.38), (0.25, 0.18, 1.02), P["iron"], rot=tilt)
    b.box((0.60, 0.50, 0.06), (0.25, 0.7, 1.32), P["wood"], rot=(55, 9, 0))
    b.to_object("Cart")
    export("cart")


def build_crate(broken):
    b = Builder()
    if not broken:
        b.box((0.62, 0.62, 0.60), (0, 0, 0.30), P["wood"])
        for z in (0.08, 0.52):
            b.box((0.66, 0.66, 0.06), (0, 0, z), P["wood_dark"])
        b.to_object("Crate")
        export("crate")
    else:
        b.box((0.62, 0.62, 0.08), (0, 0, 0.04), P["wood"])
        b.box((0.62, 0.06, 0.40), (0, 0.30, 0.20), P["wood"])
        b.box((0.06, 0.62, 0.30), (0.30, 0, 0.15), P["wood"])
        b.box((0.60, 0.08, 0.06), (0.1, -0.5, 0.03), P["wood_dark"], rot=(0, 0, 30))
        b.box((0.50, 0.08, 0.06), (-0.4, -0.3, 0.03), P["wood_dark"], rot=(0, 0, -60))
        for i in range(4):  # spilled straw packing and an iron bar
            b.box((0.30, 0.08, 0.03), (rng.uniform(-0.4, 0.4), rng.uniform(-0.6, 0.0), 0.015), P["parchment"], rot=(0, 0, rng.uniform(0, 180)))
        b.box((0.40, 0.10, 0.08), (-0.1, -0.2, 0.04), P["grave_iron"], rot=(0, 0, 20))
        b.to_object("CrateBroken")
        export("crate_broken")


def build_wheel():
    b = Builder()
    b.cyl(0.48, 0.48, 0.08, (0, 0, 0.04), P["wood_dark"], segs=10)
    b.cyl(0.10, 0.10, 0.12, (0, 0, 0.06), P["iron"], segs=6)
    for i in range(5):
        b.box((0.06, 0.80, 0.04), (0, 0, 0.09), P["wood"], rot=(0, 0, i * 36))
    b.to_object("Wheel").rotation_euler = (0, 0, 0)
    export("wheel")


def build_shrine():
    b = Builder()
    b.box((1.6, 1.2, 0.20), (0, 0, 0.10), P["stone_dark"])                      # base step
    b.box((1.2, 0.9, 0.20), (0, 0.05, 0.30), P["stone"])
    b.box((0.80, 0.60, 1.20), (0, 0.15, 1.00), P["stone"], taper=(0.85, 0.85))  # pillar
    b.box((0.50, 0.12, 0.60), (0, -0.16, 1.15), P["stone_dark"])               # niche
    b.box((1.10, 0.90, 0.12), (0, 0.15, 1.66), P["stone_dark"])                # cap
    b.box((0.70, 0.60, 0.30), (0, 0.15, 1.85), P["stone"], taper=(0.3, 0.3))   # roof
    # a small worn carved figure, hands together
    b.box((0.18, 0.10, 0.34), (0, -0.18, 1.12), P["bone"], taper=(0.6, 0.8))
    b.ball(0.07, (0, -0.18, 1.34), P["bone"], subdiv=0)
    # signs of recent use: fresh candles, a bowl with an offering, cloth strips
    for (x, h) in ((-0.40, 0.18), (-0.28, 0.12), (0.34, 0.15), (0.45, 0.09)):
        b.cyl(0.035, 0.035, h, (x, -0.30, 0.40 + h / 2), P["candle"], segs=6)
        b.ball(0.03, (x, -0.30, 0.42 + h), P["flame"], scale=(0.7, 0.7, 1.4), subdiv=0, glow=True, var=0.0)
    b.cyl(0.14, 0.10, 0.08, (0.05, -0.36, 0.44), P["wood"], segs=8)             # offering bowl
    b.ball(0.06, (0.05, -0.36, 0.50), P["parchment"], subdiv=0)                 # bread
    for i, x in enumerate((-0.30, -0.1, 0.25)):
        b.box((0.06, 0.02, 0.40), (x, -0.13, 1.45), P["cloth_red"] if i != 1 else P["parchment"], rot=(4, 0, rng.uniform(-8, 8)))
    b.box((0.30, 0.30, 0.04), (-0.5, -0.45, 0.02), P["moss"])                   # moss
    b.to_object("Shrine")
    export("shrine")


def build_watch_post():
    b = Builder()
    # tower: square, broken jagged top
    b.box((4.2, 4.2, 0.6), (0, 0, 0.3), P["stone_dark"])
    b.box((3.6, 3.6, 7.5), (0, 0, 4.05), P["stone"], taper=(0.92, 0.92))
    b.box((3.9, 3.9, 0.4), (0, 0, 7.9), P["stone_dark"])
    for i, (x, y, h) in enumerate(((-1.6, -1.6, 1.4), (0.0, -1.7, 0.7), (1.6, -1.6, 1.0), (1.7, 0.2, 0.4), (-1.7, 0.0, 1.1), (-1.6, 1.6, 0.6))):
        b.box((0.7, 0.7, h), (x, y, 8.1 + h / 2), P["stone"])                 # crenellations, some fallen
    b.box((1.8, 0.4, 2.6), (0.6, 1.75, 6.0), P["black"], var=0.0)             # breach in the wall
    b.box((0.4, 0.2, 1.0), (0, -1.75, 5.0), P["black"], var=0.0)              # arrow slit
    b.box((0.4, 0.2, 1.0), (1.75, 0, 3.6), P["black"], var=0.0, rot=(0, 0, 90))
    b.box((1.2, 0.3, 2.0), (0, -1.75, 1.6), P["wood_dark"])                   # barred door
    b.box((1.4, 0.15, 0.15), (0, -1.95, 1.8), P["iron"])
    # curtain wall stubs and rubble
    b.box((6.0, 0.8, 2.6), (-4.8, -0.6, 1.3), P["stone"], rot=(0, 0, 4))
    b.box((2.5, 0.8, 1.4), (-8.2, -1.0, 0.7), P["stone_dark"], rot=(0, 0, 10))
    b.box((4.0, 0.8, 1.9), (4.0, 1.4, 0.95), P["stone"], rot=(0, 0, -12))
    for _ in range(14):
        s = rng.uniform(0.3, 0.9)
        b.ball(s, (rng.uniform(-3, 4), rng.uniform(-4.2, -2.4), s * 0.4), P["stone_dark"], scale=(1, 1, 0.6), subdiv=0, jitter=0.1)
    # broken timber hoarding at the top
    b.box((0.2, 0.2, 2.2), (1.9, -1.9, 7.0), P["wood_dark"], rot=(20, 0, 0))
    b.box((2.6, 0.2, 0.2), (0.4, -2.2, 7.6), P["wood_dark"], rot=(0, 18, 0))
    # torn banner, faded
    b.box((0.7, 0.05, 1.6), (-1.0, -1.85, 6.4), P["cloth_red"], var=0.2, rot=(0, 0, 4))
    b.to_object("WatchPost")
    export("watch_post")


def build_pine():
    b = Builder()
    b.cyl(0.18, 0.12, 1.6, (0, 0, 0.8), P["bark"], segs=6)
    for i, (r, h, z) in enumerate(((1.7, 2.0, 1.9), (1.35, 1.8, 3.0), (1.0, 1.6, 4.0), (0.6, 1.4, 4.9))):
        b.cyl(r, 0.05, h, (0, 0, z), P["pine"] if i % 2 == 0 else P["pine_dark"], segs=7, var=0.15)
    b.to_object("Pine")
    export("pine")


def build_dead_tree():
    b = Builder()
    b.cyl(0.26, 0.10, 4.2, (0, 0, 2.1), P["wood_grey"], segs=6)
    for (h, yaw, pitch, ln) in ((2.4, 30, 50, 1.6), (3.0, 160, 55, 1.3), (3.5, 260, 45, 1.1), (1.8, 210, 60, 1.2)):
        d = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0))
        c = Vector((0, 0, h)) + d * math.sin(math.radians(pitch)) * ln * 0.5 + Vector((0, 0, math.cos(math.radians(pitch)) * ln * 0.5))
        b.cyl(0.07, 0.02, ln, tuple(c), P["wood_grey"], segs=4, rot=(0, pitch, yaw))
    b.to_object("DeadTree")
    export("dead_tree")


def build_rock(variant):
    b = Builder()
    if variant == 0:
        b.ball(1.0, (0, 0, 0.35), P["stone"], scale=(1.2, 1.0, 0.75), subdiv=1, jitter=0.18, var=0.12)
        b.ball(0.35, (0.5, -0.4, 0.75), P["moss"], scale=(1.2, 1, 0.4), subdiv=0, jitter=0.05)
    else:
        b.ball(0.9, (0, 0, 0.6), P["stone_dark"], scale=(0.8, 0.7, 1.2), subdiv=1, jitter=0.15, var=0.12)
        b.ball(0.5, (0.7, 0.2, 0.25), P["stone"], scale=(1, 1, 0.7), subdiv=0, jitter=0.08)
    b.to_object("Rock%d" % variant)
    export("rock%d" % variant)


def build_gravestone(variant):
    b = Builder()
    if variant == 0:  # weathered stone slab, leaning
        b.box((0.50, 0.14, 0.80), (0, 0, 0.36), P["stone"], rot=(8, 4, 0), taper=(0.85, 1))
        b.box((0.30, 0.16, 0.10), (0, 0, 0.80), P["stone"], rot=(8, 4, 0))
        b.box((0.36, 0.02, 0.04), (0, -0.09, 0.55), P["stone_dark"], rot=(8, 4, 0))
    else:  # newer timber marker with a tiny bell, fresher than the road
        b.box((0.08, 0.08, 1.0), (0, 0, 0.5), P["wood"])
        b.box((0.46, 0.08, 0.08), (0, 0, 0.78), P["wood"])
        b.cyl(0.05, 0.025, 0.08, (0.17, -0.06, 0.68), P["brass"], segs=6)
        b.box((0.40, 0.60, 0.10), (0, 0.4, 0.04), P["wood_dark"])  # disturbed earth
    b.to_object("Grave%d" % variant)
    export("grave%d" % variant)


def build_ruin_wall():
    b = Builder()
    b.box((3.0, 0.6, 1.4), (0, 0, 0.7), P["stone"], var=0.12)
    b.box((1.2, 0.6, 0.6), (-0.9, 0, 1.7), P["stone"], var=0.12)
    b.box((0.6, 0.6, 0.4), (-1.2, 0, 2.2), P["stone_dark"])
    b.box((1.0, 0.7, 0.3), (1.0, -0.6, 0.15), P["stone_dark"], rot=(0, 10, 25))
    b.box((1.4, 0.2, 0.3), (0.4, -0.31, 1.25), P["moss"])
    b.to_object("RuinWall")
    export("ruin_wall")


def build_waymarker():
    b = Builder()
    b.box((0.40, 0.30, 1.30), (0, 0, 0.65), P["stone"], taper=(0.7, 0.7))
    b.box((0.30, 0.02, 0.40), (0, -0.16, 0.85), P["stone_dark"])
    b.to_object("Waymarker")
    export("waymarker")


def build_fence():
    b = Builder()
    for i, lean in enumerate((0, 8, -14, 0)):
        b.box((0.10, 0.10, 1.1), (i * 1.0 - 1.5, 0, 0.5), P["wood_grey"], rot=(lean, 0, 0))
    b.box((2.2, 0.06, 0.10), (-0.9, 0, 0.85), P["wood_grey"], rot=(0, 3, 0))
    b.box((1.2, 0.06, 0.10), (0.9, 0, 0.30), P["wood_grey"], rot=(0, -20, 0))
    b.to_object("Fence")
    export("fence")


# ------------------------------------------------------------------ items


def build_items():
    b = Builder()  # Watchman's Edge: cleaner blade, brass guard, watch sigil
    b.box((0.045, 0.045, 0.18), (0, 0, 0.0), P["leather"])
    b.box((0.30, 0.06, 0.05), (0, 0, 0.11), P["brass"])
    b.ball(0.04, (0, 0, -0.11), P["brass"], subdiv=0)
    b.box((0.065, 0.016, 0.86), (0, 0, 0.56), P["steel_bright"], var=0.04, taper=(0.4, 1))
    b.box((0.02, 0.018, 0.5), (0, 0, 0.42), P["steel_dark"], var=0.0)  # fuller
    b.to_object("WatchmansEdge")
    export("watchmans_edge")
    reset_scene()

    b = Builder()
    b.ball(0.12, (0, 0, 0.10), P["leather"], scale=(1, 1, 0.9), subdiv=1)
    b.cyl(0.05, 0.07, 0.06, (0, 0, 0.21), P["leather_dark"], segs=6)
    for i in range(4):
        b.cyl(0.04, 0.04, 0.012, (0.13 + i * 0.03, -0.05 + i * 0.02, 0.006 + 0.012 * (i % 2)), P["coin"], segs=8)
    b.to_object("CoinPurse")
    export("coin_purse")
    reset_scene()

    b = Builder()
    b.box((0.30, 0.22, 0.01), (0, 0, 0.005), P["parchment"], var=0.05)
    b.cyl(0.025, 0.025, 0.30, (0, 0.11, 0.025), P["parchment"], segs=6, rot=(0, 90, 0))
    b.box((0.2, 0.01, 0.003), (0, -0.03, 0.012), P["black"], var=0.0)
    b.box((0.06, 0.06, 0.012), (0.08, -0.07, 0.012), P["cloth_red"], var=0.0)  # wax seal
    b.to_object("Manifest")
    export("manifest")
    reset_scene()

    b = Builder()
    b.box((0.36, 0.14, 0.10), (0, 0, 0.05), P["grave_iron"], taper=(0.85, 0.75), var=0.05)
    b.box((0.36, 0.14, 0.10), (0.04, 0.12, 0.05), P["grave_iron"], taper=(0.85, 0.75), rot=(0, 0, 10), var=0.05)
    b.box((0.08, 0.005, 0.04), (0, -0.07, 0.06), P["bone"], var=0.0)  # stamped mark
    b.to_object("GraveIron")
    export("grave_iron")
    reset_scene()

    b = Builder()
    b.ball(0.08, (0, 0, 0.08), P["glass"], scale=(1, 1, 1.1), subdiv=1, var=0.03)
    b.ball(0.06, (0, 0, 0.07), P["draught"], subdiv=1, var=0.0, glow=False)
    b.cyl(0.025, 0.025, 0.08, (0, 0, 0.19), P["glass"], segs=6)
    b.cyl(0.03, 0.03, 0.03, (0, 0, 0.24), P["wood"], segs=6)
    b.to_object("Draught")
    export("draught")


def build_equipment():
    """Stand-alone item models: used for world drops and inventory icons."""
    b = Builder()  # the worn longsword on its own
    b.box((0.04, 0.04, 0.16), (0, 0, 0.0), P["leather_dark"])
    b.box((0.24, 0.05, 0.04), (0, 0, 0.10), P["iron"])
    b.ball(0.035, (0, 0, -0.10), P["iron"], subdiv=0)
    b.box((0.06, 0.015, 0.78), (0, 0, 0.51), P["steel"], var=0.12, taper=(0.5, 1))
    b.box((0.02, 0.02, 0.05), (0.03, 0, 0.46), P["rust"])
    b.to_object("WornSword")
    export("worn_sword")
    reset_scene()

    b = Builder()  # dented watch helm
    b.ball(0.16, (0, 0, 0.10), P["iron"], scale=(1, 1.05, 0.85), subdiv=1, var=0.1)
    b.cyl(0.19, 0.19, 0.03, (0, 0, 0.03), P["steel_dark"], segs=10)
    b.box((0.03, 0.05, 0.12), (0, -0.17, 0.02), P["steel_dark"])  # nasal
    b.box((0.06, 0.02, 0.05), (0.08, -0.12, 0.14), P["rust"], var=0.0)  # the dent
    b.to_object("WatchHelm")
    export("watch_helm")
    reset_scene()

    b = Builder()  # traveller's satchel
    b.box((0.36, 0.14, 0.26), (0, 0, 0.13), P["leather"], var=0.1)
    b.box((0.37, 0.15, 0.10), (0, -0.01, 0.24), P["leather_dark"], rot=(-12, 0, 0))  # flap
    b.box((0.05, 0.02, 0.06), (0, -0.09, 0.19), P["brass"], var=0.0)
    b.box((0.04, 0.02, 0.40), (0.15, 0.0, 0.40), P["leather_dark"], rot=(0, 25, 0))  # strap
    b.box((0.04, 0.02, 0.40), (-0.15, 0.0, 0.40), P["leather_dark"], rot=(0, -25, 0))
    b.to_object("Satchel")
    export("satchel")
    reset_scene()

    b = Builder()  # folded travelling clothes
    b.box((0.40, 0.30, 0.08), (0, 0, 0.04), P["cloth"], var=0.1)
    b.box((0.38, 0.28, 0.06), (0.01, 0.01, 0.11), P["cloak"], var=0.1)
    b.box((0.42, 0.06, 0.03), (0, -0.05, 0.155), P["leather_dark"])  # belt
    b.box((0.05, 0.03, 0.04), (0.06, -0.06, 0.16), P["brass"], var=0.0)
    b.to_object("Clothes")
    export("clothes")
    reset_scene()

    b = Builder()  # battered kite shield: face toward -Y, point at the bottom
    b.box((0.46, 0.06, 0.40), (0, 0, 0.20), P["wood"], var=0.12)                      # upper boards
    b.box((0.46, 0.06, 0.42), (0, 0, -0.21), P["wood"], var=0.12, taper=(0.12, 1.0), rot=(0, 180, 0))  # tapering to a point
    b.box((0.40, 0.02, 0.34), (0, -0.035, 0.18), P["leather"], var=0.1)               # hide facing
    b.box((0.40, 0.02, 0.36), (0, -0.035, -0.19), P["leather"], var=0.1, taper=(0.12, 1.0), rot=(0, 180, 0))
    b.box((0.48, 0.07, 0.04), (0, 0, 0.41), P["iron"])                                 # iron rim, top
    b.box((0.05, 0.03, 0.80), (0, -0.05, 0.0), P["iron"], taper=(0.5, 1.0))            # spine
    b.box((0.40, 0.03, 0.05), (0, -0.05, 0.14), P["iron"])                             # cross band
    b.ball(0.05, (0, -0.06, 0.14), P["steel_dark"], scale=(1, 0.6, 1), subdiv=1)       # boss
    b.box((0.06, 0.02, 0.10), (0.12, -0.05, -0.02), P["rust"], var=0.0)                # an old gouge
    b.box((0.05, 0.05, 0.22), (0, 0.05, 0.08), P["leather_dark"])                      # grip strap
    b.to_object("KiteShield")
    export("kite_shield")



def build_mara():
    """Mara Venn, the smith: same joint layout as the Warden so the rig animates her."""
    root = empty("Mara")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.16, 0.18, 0.48), (0, 0, -0.26), P["cloth"])
            b.box((0.15, 0.17, 0.40), (0, 0.01, -0.66), P["leather_dark"])
            b.box((0.16, 0.25, 0.10), (0, -0.05, -0.88), P["leather_dark"])
        return part("Leg_" + side, root, (0.11 * s, 0, 0.93), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.40, 0.25, 0.24), (0, 0, 0.10), P["cloth"])
        b.box((0.44, 0.27, 0.40), (0, 0, 0.42), P["cloth_red"], taper=(1.08, 1.0), var=0.12)  # work shirt
        b.box((0.42, 0.06, 0.72), (0, -0.15, 0.24), P["leather"], var=0.1)                   # smith's apron
        b.box((0.46, 0.29, 0.06), (0, 0, 0.18), P["leather_dark"])                            # belt
        b.box((0.06, 0.04, 0.22), (0.16, -0.17, 0.02), P["iron"])                             # tongs at the belt
        b.box((0.10, 0.10, 0.12), (-0.20, -0.06, 0.06), P["leather_dark"])                   # pouch
    t = part("Torso", root, (0, 0, 0.92), torso)

    def head(b):
        b.box((0.08, 0.08, 0.08), (0, 0, 0.03), P["skin"])
        b.box((0.21, 0.23, 0.25), (0, 0, 0.19), P["skin"], taper=(0.92, 0.9))
        b.box((0.24, 0.26, 0.10), (0, 0.02, 0.32), P["hair"])                                 # hair
        b.box((0.23, 0.08, 0.22), (0, 0.11, 0.22), P["hair"])
        b.ball(0.07, (0, 0.15, 0.30), P["hair"], subdiv=0)                                    # tied back
        b.box((0.24, 0.03, 0.04), (0, -0.12, 0.27), P["cloth_red"], var=0.0)                  # headband
        b.box((0.18, 0.03, 0.03), (0, -0.12, 0.21), P["black"], var=0.0)                      # eyes
    part("Head", t, (0, 0, 0.66), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.13, 0.14, 0.16), (0, 0, -0.04), P["cloth_red"])          # rolled sleeve
            b.box((0.11, 0.12, 0.30), (0, 0, -0.26), P["skin"])               # bare forearm
            b.box((0.12, 0.13, 0.16), (0, -0.01, -0.50), P["leather_dark"])   # heavy glove
            b.box((0.10, 0.11, 0.10), (0, -0.01, -0.64), P["leather_dark"])
        return part("Arm_" + side, t, (0.28 * s, 0, 0.56), fn)

    arm("L")
    ar = arm("R")

    def hammer(b):
        b.box((0.04, 0.04, 0.42), (0, 0, 0.12), P["wood"])                  # haft
        b.box((0.20, 0.08, 0.08), (0, 0, 0.34), P["iron"], var=0.05)         # head
    part("Weapon", ar, (0, -0.02, -0.66), hammer).rotation_euler = (math.radians(10), 0, 0)
    export("mara")


def build_forge_camp():
    b = Builder()  # anvil on a stump
    b.cyl(0.30, 0.34, 0.50, (0, 0, 0.25), P["wood_dark"], segs=8)
    b.box((0.26, 0.20, 0.12), (0, 0, 0.56), P["iron"], var=0.04)
    b.box((0.18, 0.14, 0.10), (0, 0, 0.66), P["iron"], var=0.04)
    b.box((0.62, 0.24, 0.14), (0, 0, 0.78), P["iron"], var=0.04, taper=(1.0, 1.0))
    b.box((0.18, 0.12, 0.08), (0.38, 0, 0.80), P["iron"], var=0.04, taper=(0.3, 0.6), rot=(0, 90, 0))  # horn
    b.to_object("Anvil")
    export("anvil")
    reset_scene()

    b = Builder()  # stone forge hearth with live coals and a bellows
    b.box((1.3, 1.0, 0.75), (0, 0, 0.375), P["stone"], var=0.12)
    b.box((1.1, 0.8, 0.08), (0, 0, 0.78), P["stone_dark"])
    for _ in range(9):
        b.ball(rng.uniform(0.07, 0.12), (rng.uniform(-0.35, 0.35), rng.uniform(-0.25, 0.25), 0.84), P["flame"], scale=(1, 1, 0.6), subdiv=0, glow=True, var=0.15)
    b.box((0.9, 0.7, 0.9), (0, 0.15, 1.30), P["stone_dark"], taper=(0.45, 0.45))   # hood
    b.box((0.30, 0.30, 0.90), (0, 0.15, 2.15), P["stone"], var=0.1)                  # chimney
    b.box((0.40, 0.55, 0.12), (0.85, 0.05, 0.55), P["leather"], rot=(0, -15, 0))      # bellows
    b.box((0.06, 0.06, 0.40), (1.05, 0.05, 0.62), P["wood"], rot=(0, -60, 0))
    b.to_object("Forge")
    export("forge")
    reset_scene()

    b = Builder()  # canvas awning on poles, with a rack of goods
    for (x, y) in ((-1.4, -1.0), (1.4, -1.0), (-1.4, 1.0), (1.4, 1.0)):
        b.box((0.10, 0.10, 2.3 if y > 0 else 2.0), (x, y, 1.15 if y > 0 else 1.0), P["wood_dark"])
    b.box((3.1, 2.4, 0.05), (0, 0, 2.15), P["parchment"], rot=(-8, 0, 0), var=0.15)  # canvas
    b.box((3.1, 0.05, 0.30), (0, -1.18, 1.92), P["parchment"], var=0.15)
    b.box((2.2, 0.10, 0.08), (0, 0.95, 1.4), P["wood"])                                # rack rail
    for i, x in enumerate((-0.8, -0.3, 0.2, 0.7)):
        b.box((0.05, 0.015, 0.75), (x, 0.88, 1.0), P["steel"], var=0.1, taper=(0.4, 1))   # blades on the rack
    b.box((0.9, 0.5, 0.45), (-0.9, 0.6, 0.225), P["wood"])                            # chest of stock
    b.box((0.92, 0.52, 0.06), (-0.9, 0.6, 0.47), P["wood_dark"])
    b.to_object("Awning")
    export("awning")


def build_shop_items():
    b = Builder()  # iron-studded gloves (pair)
    for x in (-0.09, 0.09):
        b.box((0.13, 0.20, 0.05), (x, 0, 0.025), P["leather_dark"])
        b.box((0.14, 0.10, 0.06), (x, 0.13, 0.03), P["iron"], var=0.05)       # cuff plate
        for k in range(3):
            b.box((0.025, 0.025, 0.02), (x - 0.04 + k * 0.04, -0.04, 0.06), P["steel"], var=0.0)
    b.to_object("IronGloves")
    export("iron_gloves")
    reset_scene()

    b = Builder()  # hobnailed boots
    for x in (-0.09, 0.09):
        b.box((0.12, 0.26, 0.08), (x, -0.04, 0.04), P["leather_dark"])
        b.box((0.12, 0.13, 0.24), (x, 0.04, 0.16), P["leather"])
        b.box((0.13, 0.14, 0.04), (x, 0.04, 0.27), P["leather_dark"])
    b.to_object("HobBoots")
    export("hob_boots")
    reset_scene()

    b = Builder()  # mail chausses, folded
    b.box((0.36, 0.26, 0.10), (0, 0, 0.05), P["steel_dark"], var=0.15)
    b.box((0.34, 0.24, 0.06), (0, 0.01, 0.12), P["steel"], var=0.15)
    b.box((0.38, 0.04, 0.03), (0, -0.12, 0.14), P["leather_dark"])
    b.to_object("MailChausses")
    export("mail_chausses")
    reset_scene()

    b = Builder()  # iron-faced kite shield: face toward -Y, point at the bottom
    b.box((0.48, 0.06, 0.42), (0, 0, 0.21), P["steel_dark"], var=0.08)
    b.box((0.48, 0.06, 0.44), (0, 0, -0.22), P["steel_dark"], var=0.08, taper=(0.12, 1.0), rot=(0, 180, 0))
    b.box((0.50, 0.07, 0.04), (0, 0, 0.43), P["brass"])
    b.box((0.05, 0.03, 0.84), (0, -0.05, 0.0), P["brass"], taper=(0.5, 1.0))
    b.box((0.42, 0.03, 0.05), (0, -0.05, 0.16), P["brass"])
    b.ball(0.055, (0, -0.06, 0.16), P["steel_bright"], scale=(1, 0.6, 1), subdiv=1)
    b.box((0.05, 0.05, 0.22), (0, 0.05, 0.08), P["leather_dark"])
    b.to_object("IronShield")
    export("iron_shield")


# ------------------------------------------------------------ the Blackwood


def build_hound():
    """Barrow hound: a lean grave-dog. Hind legs are Leg_L/R, forelegs Arm_L/R,
    so the same procedural walk drives all four."""
    root = empty("Hound")

    def hind(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.12, 0.20, 0.26), (0, 0.02, -0.12), P["fur"])
            b.box((0.07, 0.08, 0.26), (0, 0.06, -0.36), P["fur_dark"], rot=(-12, 0, 0))
            b.box((0.08, 0.14, 0.05), (0, -0.01, -0.50), P["fur_dark"])
        return part("Leg_" + side, root, (0.11 * s, 0.30, 0.55), fn)

    hind("L")
    hind("R")

    def torso(b):
        b.box((0.30, 0.80, 0.26), (0, -0.02, 0.02), P["fur"], var=0.1, taper=(1.0, 0.9))
        b.box((0.32, 0.34, 0.30), (0, -0.30, 0.06), P["fur_dark"])           # shoulders
        for i in range(5):  # ribs through the hide
            b.box((0.31, 0.03, 0.12), (0, -0.16 + i * 0.07, -0.06), P["bone_old"], var=0.0)
        for i in range(4):  # ridge of bristles
            b.cyl(0.03, 0.0, 0.10, (0, -0.30 + i * 0.16, 0.19), P["fur_dark"], segs=4, rot=(20, 0, 0))
        b.box((0.05, 0.05, 0.38), (0, 0.48, 0.0), P["fur_dark"], rot=(-60, 0, 0), taper=(0.4, 0.4))  # tail
    t = part("Torso", root, (0, 0, 0.58), torso)

    def head(b):
        b.box((0.20, 0.22, 0.20), (0, -0.06, 0.02), P["fur_dark"])
        b.box((0.14, 0.24, 0.12), (0, -0.26, -0.02), P["fur"], taper=(0.8, 0.8))  # muzzle
        b.box((0.12, 0.18, 0.04), (0, -0.25, -0.09), P["bone_old"])                # bared jaw
        b.cyl(0.04, 0.0, 0.12, (0.07, 0.0, 0.14), P["fur_dark"], segs=4, rot=(-15, 0, 0))  # ears
        b.cyl(0.04, 0.0, 0.12, (-0.07, 0.0, 0.14), P["fur_dark"], segs=4, rot=(-15, 0, 0))
        b.box((0.03, 0.02, 0.025), (0.05, -0.17, 0.06), P["eye"], var=0.0, glow=True)
        b.box((0.03, 0.02, 0.025), (-0.05, -0.17, 0.06), P["eye"], var=0.0, glow=True)
    part("Head", t, (0, -0.44, 0.12), head)

    def fore(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.10, 0.14, 0.28), (0, 0, -0.14), P["fur"])
            b.box((0.07, 0.08, 0.24), (0, -0.01, -0.38), P["fur_dark"])
            b.box((0.08, 0.14, 0.05), (0, -0.04, -0.51), P["fur_dark"])
        return part("Arm_" + side, t, (0.12 * s, -0.32, -0.03), fn)

    fore("L")
    fore("R")
    export("hound")


def build_archer():
    """Hollow archer: a skeleton in a rotted gambeson, bow in the left hand."""
    root = empty("Archer")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.07, 0.07, 0.42), (0, 0, -0.22), P["bone_old"])
            b.box((0.06, 0.06, 0.38), (0, 0.02, -0.60), P["bone"])
            b.box((0.10, 0.20, 0.05), (0, -0.04, -0.80), P["bone_old"])
            b.box((0.15, 0.15, 0.18), (0, 0, -0.08), P["rag"])
        return part("Leg_" + side, root, (0.10 * s, 0, 0.84), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.06, 0.06, 0.40), (0, 0.02, 0.22), P["bone_old"])            # spine
        b.box((0.26, 0.14, 0.14), (0, 0, 0.04), P["bone_old"])               # pelvis
        b.box((0.34, 0.22, 0.34), (0, 0, 0.40), P["rust"], taper=(1.1, 1))   # rotted gambeson
        for i in range(3):
            b.box((0.30, 0.03, 0.03), (0, -0.12, 0.30 + i * 0.08), P["bone"])  # ribs through the rents
        b.box((0.10, 0.10, 0.46), (0.06, 0.15, 0.40), P["leather_dark"], rot=(0, -20, 0))  # quiver
        for k in range(3):
            b.box((0.015, 0.015, 0.16), (0.02 + k * 0.03, 0.15, 0.70), P["wood"])
            b.box((0.03, 0.01, 0.05), (0.02 + k * 0.03, 0.15, 0.78), P["cloth_red"], var=0.0)
    t = part("Torso", root, (0, 0, 0.84), torso)

    def head(b):
        b.box((0.18, 0.20, 0.20), (0, -0.02, 0.12), P["bone"], taper=(0.9, 0.85))
        b.box((0.14, 0.10, 0.05), (0, -0.07, 0.00), P["bone_old"])            # jaw
        b.box((0.05, 0.02, 0.04), (0.045, -0.12, 0.13), P["black"], var=0.0)
        b.box((0.05, 0.02, 0.04), (-0.045, -0.12, 0.13), P["black"], var=0.0)
        b.box((0.02, 0.01, 0.02), (0.045, -0.13, 0.13), P["eye"], var=0.0, glow=True)
        b.box((0.02, 0.01, 0.02), (-0.045, -0.13, 0.13), P["eye"], var=0.0, glow=True)
        b.box((0.24, 0.24, 0.10), (0, 0.0, 0.22), P["iron"], var=0.1, taper=(0.7, 0.7))  # kettle helm
    part("Head", t, (0, -0.02, 0.60), head)

    def arm(side, bow):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.07, 0.07, 0.34), (0, 0, -0.17), P["bone_old"])
            b.box((0.06, 0.06, 0.32), (0, 0, -0.48), P["bone"])
            b.box((0.08, 0.08, 0.08), (0, 0, -0.67), P["bone_old"])
            if bow:  # a short recurve held upright in the fist
                b.box((0.04, 0.04, 0.12), (0, -0.02, -0.68), P["leather_dark"])
                b.box((0.035, 0.035, 0.46), (0, -0.04, -0.42), P["wood_dark"], rot=(-12, 0, 0))
                b.box((0.035, 0.035, 0.46), (0, -0.04, -0.94), P["wood_dark"], rot=(12, 0, 0))
                b.box((0.008, 0.008, 0.98), (0, 0.06, -0.68), P["parchment"], var=0.0)
        return part("Arm_" + side, t, (0.22 * s, 0, 0.52), fn)

    arm("L", True)
    arm("R", False)
    export("archer")


def build_seer():
    """Blackwood seer: a hooded grave-witch with a staff of witchlight."""
    root = empty("Seer")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.12, 0.14, 0.40), (0, 0, -0.30), P["robe"])
            b.box((0.10, 0.20, 0.06), (0, -0.04, -0.52), P["ash_dark"])
        return part("Leg_" + side, root, (0.10 * s, 0, 0.56), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.56, 0.48, 0.70), (0, 0, -0.12), P["robe"], var=0.06, taper=(0.62, 0.62))  # robe skirt
        b.box((0.58, 0.04, 0.06), (0, -0.23, -0.44), P["robe_trim"])
        b.box((0.38, 0.28, 0.44), (0, 0, 0.36), P["robe"], taper=(1.1, 1.0))
        b.box((0.44, 0.32, 0.10), (0, 0, 0.56), P["robe_trim"])                   # mantle
        for i in range(5):  # charms on a cord
            b.box((0.03, 0.02, 0.05), (-0.12 + i * 0.06, -0.16, 0.42 - abs(i - 2) * 0.03), P["bone"], var=0.0)
        b.cyl(0.04, 0.03, 0.08, (0.16, -0.10, 0.06), P["glass"], segs=6)          # vial at the belt
    t = part("Torso", root, (0, 0, 0.62), torso)

    def head(b):
        b.box((0.20, 0.22, 0.24), (0, -0.02, 0.12), P["ash"], taper=(0.85, 0.9))
        b.box((0.32, 0.34, 0.34), (0, 0.03, 0.18), P["robe"], taper=(0.45, 0.6))  # deep hood
        b.box((0.20, 0.04, 0.12), (0, -0.14, 0.08), P["black"], var=0.0)        # shadowed face
        b.box((0.04, 0.02, 0.025), (0.045, -0.165, 0.11), P["witchlight"], var=0.0, glow=True)
        b.box((0.04, 0.02, 0.025), (-0.045, -0.165, 0.11), P["witchlight"], var=0.0, glow=True)
    part("Head", t, (0, -0.02, 0.62), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.14, 0.16, 0.34), (0, 0, -0.16), P["robe"], taper=(1.2, 1.2))
            b.box((0.16, 0.18, 0.16), (0, 0, -0.38), P["robe_trim"])             # wide sleeve
            b.box((0.07, 0.08, 0.14), (0, -0.01, -0.50), P["ash"])
        return part("Arm_" + side, t, (0.24 * s, 0, 0.52), fn)

    arm("L")
    ar = arm("R")

    def staff(b):
        b.box((0.05, 0.05, 1.60), (0, 0, 0.30), P["blackwood"], var=0.1)
        b.box((0.16, 0.04, 0.04), (0, 0, 1.06), P["blackwood"], rot=(0, 30, 0))
        b.box((0.12, 0.04, 0.04), (0, 0, 1.00), P["blackwood"], rot=(0, -40, 0))
        b.ball(0.07, (0, 0, 1.16), P["witchlight"], subdiv=1, var=0.0, glow=True)
    part("Weapon", ar, (0, -0.02, -0.52), staff).rotation_euler = (math.radians(12), 0, 0)
    export("seer")


def build_blackwood_props():
    b = Builder()  # a black pine: taller, narrower and darker than the road's pines
    b.cyl(0.20, 0.10, 2.2, (0, 0, 1.1), P["blackwood"], segs=6)
    for i, (r, h, z) in enumerate(((1.45, 2.2, 2.4), (1.15, 2.0, 3.6), (0.85, 1.8, 4.7), (0.5, 1.6, 5.7))):
        b.cyl(r, 0.05, h, (0, 0, z), P["pine_black"] if i % 2 == 0 else P["pine_black2"], segs=6, var=0.12)
    b.box((0.5, 0.5, 0.2), (0.4, 0.3, 0.1), P["lichen"], rot=(0, 0, 30))
    b.to_object("BlackPine")
    export("black_pine")
    reset_scene()

    b = Builder()  # standing stone with a witchlight rune
    b.box((0.70, 0.50, 2.20), (0, 0, 1.0), P["stone_dark"], var=0.1, taper=(0.7, 0.8), rot=(3, -4, 0))
    b.box((0.30, 0.04, 0.40), (0, -0.26, 1.2), P["witchlight"], var=0.0, glow=True, rot=(3, -4, 0))
    b.box((0.76, 0.56, 0.30), (0, 0, 0.10), P["lichen"], var=0.15)
    b.to_object("StandingStone")
    export("standing_stone")
    reset_scene()

    b = Builder()  # a stretch of broken palisade
    for i in range(7):
        h = 1.6 + rng.uniform(-0.5, 0.4) if i not in (3, 4) else 0.7
        b.box((0.24, 0.24, h), (-1.2 + i * 0.4, 0, h / 2), P["wood_dark"], var=0.12, rot=(0, rng.uniform(-6, 6), 0))
        b.cyl(0.12, 0.0, 0.25, (-1.2 + i * 0.4, 0, h + 0.12), P["wood_dark"], segs=4)
    b.box((2.9, 0.10, 0.12), (0, 0.14, 1.0), P["wood"], rot=(0, 3, 0))
    b.to_object("Palisade")
    export("palisade")
    reset_scene()

    b = Builder()  # gnawed bones by the hound den
    for i in range(7):
        b.box((0.06, 0.06, 0.40), (rng.uniform(-0.5, 0.5), rng.uniform(-0.4, 0.4), 0.04), P["bone"], rot=(90, 0, rng.uniform(0, 180)))
    b.ball(0.12, (0.2, 0.1, 0.10), P["bone"], subdiv=1)
    b.to_object("BonePile")
    export("bone_pile")


def build_blackwood_items():
    b = Builder()  # rusted falchion, as the worn sword: grip at the origin, blade +Z
    b.box((0.04, 0.04, 0.16), (0, 0, 0.0), P["wood_dark"])
    b.box((0.20, 0.05, 0.04), (0, 0, 0.10), P["iron"])
    b.box((0.10, 0.02, 0.70), (0.02, 0, 0.47), P["rust"], var=0.15, taper=(1.3, 1))
    b.box((0.03, 0.022, 0.70), (-0.03, 0, 0.47), P["steel_dark"], var=0.1)
    b.to_object("RustedFalchion")
    export("rusted_falchion")
    reset_scene()

    b = Builder()  # warden's hauberk, laid flat
    b.box((0.50, 0.10, 0.62), (0, 0, 0.31), P["steel_dark"], var=0.12, taper=(1.15, 1))
    b.box((0.20, 0.09, 0.24), (0.33, 0, 0.48), P["steel_dark"], var=0.12, rot=(0, -30, 0))
    b.box((0.20, 0.09, 0.24), (-0.33, 0, 0.48), P["steel_dark"], var=0.12, rot=(0, 30, 0))
    b.box((0.18, 0.02, 0.18), (0, -0.06, 0.40), P["cloth_red"], var=0.0)
    b.box((0.06, 0.03, 0.10), (0, -0.075, 0.42), P["brass"], var=0.0)
    b.to_object("WardenHauberk")
    export("warden_hauberk")
    reset_scene()

    b = Builder()  # blackened sabatons
    for x in (-0.09, 0.09):
        b.box((0.13, 0.28, 0.09), (x, -0.04, 0.045), P["iron"], var=0.08)
        b.box((0.13, 0.13, 0.22), (x, 0.05, 0.16), P["black"], var=0.06)
        b.box((0.14, 0.06, 0.04), (x, -0.08, 0.10), P["steel_dark"])
    b.to_object("PlateSabatons")
    export("plate_sabatons")
    reset_scene()

    b = Builder()  # blackwood cleaver
    b.box((0.05, 0.05, 0.30), (0, 0, 0.04), P["blackwood"])
    b.box((0.16, 0.06, 0.05), (0, 0, 0.20), P["grave_iron"])
    b.box((0.18, 0.03, 0.62), (0.03, 0, 0.53), P["grave_iron"], var=0.1, taper=(1.2, 1))
    b.box((0.04, 0.035, 0.60), (-0.05, 0, 0.52), P["blackwood"])
    b.box((0.03, 0.01, 0.20), (0.06, -0.02, 0.60), P["witchlight"], var=0.0, glow=True)
    b.to_object("BlackwoodCleaver")
    export("blackwood_cleaver")
    reset_scene()

    b = Builder()  # rolled hound pelt
    b.box((0.40, 0.26, 0.10), (0, 0, 0.05), P["fur"], var=0.15)
    b.cyl(0.08, 0.08, 0.30, (0, 0.1, 0.12), P["fur_dark"], segs=6, rot=(0, 90, 0))
    b.box((0.04, 0.26, 0.04), (0.08, 0, 0.12), P["leather_dark"])
    b.to_object("HoundPelt")
    export("hound_pelt")


def build_loot_items():
    """Drops from the rarity loot tables: junk, hound meat, a rare helm, an epic blade."""
    b = Builder()  # cracked bone (junk)
    b.cyl(0.03, 0.025, 0.36, (0, 0, 0.03), P["bone"], segs=6, rot=(0, 90, 0), var=0.1)
    b.ball(0.05, (0.19, 0, 0.04), P["bone"], subdiv=0)
    b.ball(0.045, (-0.18, 0.02, 0.04), P["bone_old"], subdiv=0)
    b.box((0.05, 0.03, 0.02), (0.02, -0.02, 0.06), P["ash_dark"], var=0.0)  # the crack
    b.to_object("CrackedBone")
    export("cracked_bone")
    reset_scene()

    b = Builder()  # bent arrowheads (junk)
    for i, (x, y, r) in enumerate(((0, 0, 20), (0.08, 0.05, -40), (-0.07, 0.04, 70))):
        b.box((0.04, 0.012, 0.10), (x, y, 0.01), P["rust"], rot=(90, 0, r), var=0.1, taper=(0.1, 1))
        b.box((0.015, 0.015, 0.08), (x - 0.03, y - 0.04, 0.01), P["wood_dark"], rot=(90, 0, r))
    b.to_object("BentArrowhead")
    export("bent_arrowhead")
    reset_scene()

    b = Builder()  # a raw hound flank on the bone
    b.ball(0.13, (0, 0, 0.08), P["draught"], scale=(1.4, 1, 0.7), subdiv=1, var=0.12)
    b.ball(0.10, (0.04, 0.02, 0.12), P["skin"], scale=(1.2, 0.9, 0.5), subdiv=1, var=0.1)  # fat
    b.cyl(0.025, 0.025, 0.16, (0.24, 0, 0.07), P["bone"], segs=6, rot=(0, 90, 0))
    b.ball(0.035, (0.32, 0, 0.07), P["bone"], subdiv=0)
    b.to_object("HoundMeat")
    export("hound_meat")
    reset_scene()

    b = Builder()  # helm of the old watch (rare): a full helm with a brass crest
    b.ball(0.17, (0, 0, 0.11), P["steel"], scale=(1, 1.08, 0.95), subdiv=1, var=0.06)
    b.cyl(0.20, 0.20, 0.04, (0, 0, 0.03), P["steel_dark"], segs=12)
    b.box((0.26, 0.03, 0.03), (0, -0.17, 0.10), P["black"], var=0.0)  # eye slit
    b.box((0.03, 0.30, 0.10), (0, 0, 0.29), P["brass"], var=0.05)  # crest
    b.box((0.05, 0.05, 0.10), (0, -0.19, 0.03), P["steel_dark"])  # nasal
    b.to_object("OldWatchHelm")
    export("old_watch_helm")
    reset_scene()

    b = Builder()  # witchbane (epic): a pale blade with witchlight in the fuller
    b.box((0.045, 0.045, 0.18), (0, 0, 0.0), P["leather_dark"])
    b.ball(0.045, (0, 0, -0.11), P["witchlight"], subdiv=1, glow=True)
    b.box((0.30, 0.06, 0.05), (0, 0, 0.11), P["grave_iron"], taper=(1.2, 1))
    b.box((0.08, 0.018, 0.86), (0, 0, 0.57), P["steel_bright"], var=0.06, taper=(0.4, 1))
    b.box((0.02, 0.022, 0.70), (0, 0, 0.50), P["witchlight"], var=0.0, glow=True)
    b.to_object("Witchbane")
    export("witchbane")


def build_tam():
    """Old Tam, fisher and woodsman by the pond: same joint layout as the Warden."""
    root = empty("Tam")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.16, 0.18, 0.48), (0, 0, -0.26), P["cloak"])
            b.box((0.16, 0.18, 0.40), (0, 0.01, -0.66), P["leather"])   # waders
            b.box((0.17, 0.26, 0.10), (0, -0.05, -0.88), P["leather_dark"])
        return part("Leg_" + side, root, (0.11 * s, 0, 0.93), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.42, 0.26, 0.26), (0, 0, 0.10), P["cloak"])
        b.box((0.46, 0.29, 0.42), (0, 0, 0.42), P["moss"], taper=(1.06, 1.0), var=0.12)   # oilskin coat
        b.box((0.48, 0.30, 0.06), (0, 0, 0.18), P["leather_dark"])                        # belt
        b.box((0.14, 0.10, 0.14), (0.20, -0.08, 0.06), P["wood_grey"])                    # creel
        b.box((0.12, 0.04, 0.06), (-0.16, -0.16, 0.30), P["brass"], var=0.0)              # tin of hooks
    t = part("Torso", root, (0, 0, 0.92), torso)

    def head(b):
        b.box((0.08, 0.08, 0.08), (0, 0, 0.03), P["skin"])
        b.box((0.21, 0.23, 0.25), (0, 0, 0.19), P["skin"], taper=(0.92, 0.9))
        b.box((0.20, 0.10, 0.16), (0, -0.09, 0.08), P["ash"], taper=(0.7, 1.0))           # grey beard
        b.box((0.18, 0.03, 0.03), (0, -0.12, 0.22), P["black"], var=0.0)                   # eyes
        b.cyl(0.24, 0.24, 0.03, (0, 0, 0.32), P["wood_grey"], segs=12)                     # wide hat brim
        b.cyl(0.13, 0.12, 0.12, (0, 0, 0.39), P["wood_grey"], segs=10)                     # crown
    part("Head", t, (0, 0, 0.66), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.13, 0.14, 0.40), (0, 0, -0.18), P["moss"])
            b.box((0.10, 0.11, 0.14), (0, -0.01, -0.46), P["skin"])
        return part("Arm_" + side, t, (0.28 * s, 0, 0.56), fn)

    arm("L")
    ar = arm("R")

    def rod(b):
        b.box((0.035, 0.035, 0.30), (0, 0, 0.0), P["leather_dark"])
        b.cyl(0.016, 0.006, 1.5, (0, 0, 0.88), P["wood"], segs=5)
        b.cyl(0.035, 0.035, 0.04, (0.04, 0, 0.12), P["iron"], segs=6, rot=(0, 90, 0))     # reel
    part("Weapon", ar, (0, -0.02, -0.5), rod).rotation_euler = (math.radians(35), 0, 0)
    export("tam")


def build_camp_items():
    """Camp, torch, rod, fish and the hollow's chest."""
    b = Builder()  # the Warden's camp: a ring of stones, crossed logs, a flame and a bedroll
    for i in range(8):
        a = i / 8 * math.tau
        b.ball(0.09, (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.05), P["stone"], subdiv=0, var=0.15)
    b.box((0.60, 0.09, 0.09), (0, 0, 0.07), P["bark"], rot=(0, 0, 30))
    b.box((0.60, 0.09, 0.09), (0, 0, 0.11), P["bark"], rot=(0, 0, -40))
    b.ball(0.16, (0, 0, 0.24), P["flame"], scale=(1, 1, 1.6), subdiv=1, glow=True, var=0.0)
    b.box((0.55, 1.2, 0.08), (1.1, 0.2, 0.04), P["cloth_red"], var=0.08)      # bedroll
    b.cyl(0.10, 0.10, 0.55, (1.1, -0.45, 0.10), P["cloth"], segs=8, rot=(0, 90, 0))
    b.to_object("Camp")
    export("camp")
    reset_scene()

    b = Builder()  # a torch: grip at the origin, burning head along +Z
    b.box((0.05, 0.05, 0.50), (0, 0, 0.12), P["wood"], var=0.1)
    b.box((0.09, 0.09, 0.12), (0, 0, 0.40), P["rag"], var=0.1)
    b.ball(0.08, (0, 0, 0.52), P["flame"], scale=(1, 1, 1.5), subdiv=1, glow=True, var=0.0)
    b.to_object("Torch")
    export("torch")
    reset_scene()

    b = Builder()  # a fishing rod, laid down
    b.box((0.04, 0.04, 0.26), (0, 0, 0.0), P["leather_dark"])
    b.cyl(0.016, 0.006, 1.3, (0, 0, 0.78), P["wood"], segs=5)
    b.cyl(0.035, 0.035, 0.04, (0.04, 0, 0.10), P["iron"], segs=6, rot=(0, 90, 0))
    b.to_object("FishingRod")
    export("fishing_rod")
    reset_scene()

    def fish(name, body, fin, length, girth):
        b = Builder()
        b.ball(girth, (0, 0, girth), P[body], scale=(length / girth, 0.55, 1), subdiv=1, var=0.08)
        b.box((0.02, 0.10, 0.12), (-length - 0.04, 0, girth), P[fin], var=0.0, rot=(0, 0, 0))   # tail
        b.box((0.10, 0.02, 0.05), (0, 0, girth * 1.9), P[fin], var=0.0)                         # dorsal fin
        b.ball(0.015, (length * 0.75, -girth * 0.45, girth * 1.2), P["black"], subdiv=0)
        b.to_object(name)
        export(name.lower())
        reset_scene()

    fish("Perch", "moss", "cloth_red", 0.16, 0.07)
    fish("Dace", "steel_bright", "steel", 0.15, 0.05)
    fish("Eel", "pine_black", "fur_dark", 0.32, 0.04)

    b = Builder()  # an old boot
    b.box((0.12, 0.26, 0.08), (0, 0.04, 0.04), P["leather_dark"], var=0.15)
    b.box((0.12, 0.12, 0.24), (0, -0.05, 0.18), P["leather_dark"], var=0.15)
    b.box((0.13, 0.13, 0.03), (0, -0.05, 0.30), P["moss"], var=0.1)
    b.to_object("OldBoot")
    export("old_boot")
    reset_scene()

    b = Builder()  # a strongbox left in the dark
    b.box((0.70, 0.45, 0.40), (0, 0, 0.20), P["wood_dark"], var=0.1)
    b.box((0.72, 0.47, 0.16), (0, 0, 0.46), P["wood"], var=0.1)
    for x in (-0.25, 0.25):
        b.box((0.06, 0.49, 0.58), (x, 0, 0.29), P["iron"])
    b.box((0.10, 0.04, 0.12), (0, -0.25, 0.36), P["brass"], var=0.0)
    b.to_object("Chest")
    export("chest")


def build_one_handers():
    """One-handed swords and daggers for dual wielding: grip at the origin, blade +Z."""
    b = Builder()  # arming sword: plain cross guard, straight blade
    b.box((0.04, 0.04, 0.17), (0, 0, 0.0), P["leather"])
    b.box((0.24, 0.05, 0.04), (0, 0, 0.10), P["iron"])
    b.ball(0.035, (0, 0, -0.10), P["iron"], subdiv=0)
    b.box((0.06, 0.016, 0.74), (0, 0, 0.49), P["steel"], var=0.05, taper=(0.45, 1))
    b.to_object("ArmingSword")
    export("arming_sword")
    reset_scene()

    b = Builder()  # militia sword: wider blade, brass guard, red grip
    b.box((0.045, 0.045, 0.17), (0, 0, 0.0), P["cloth_red"])
    b.box((0.26, 0.06, 0.05), (0, 0, 0.10), P["brass"])
    b.ball(0.04, (0, 0, -0.10), P["brass"], subdiv=0)
    b.box((0.075, 0.018, 0.72), (0, 0, 0.48), P["steel_bright"], var=0.04, taper=(0.5, 1))
    b.box((0.02, 0.02, 0.45), (0, 0, 0.38), P["steel_dark"], var=0.0)
    b.to_object("MilitiaSword")
    export("militia_sword")
    reset_scene()

    b = Builder()  # dirk: short tapering blade
    b.box((0.035, 0.035, 0.13), (0, 0, 0.0), P["leather_dark"])
    b.box((0.13, 0.04, 0.03), (0, 0, 0.075), P["iron"])
    b.box((0.05, 0.014, 0.36), (0, 0, 0.27), P["steel"], var=0.05, taper=(0.2, 1))
    b.to_object("Dirk")
    export("dirk")
    reset_scene()

    b = Builder()  # bone knife: a ghoul's shin bone ground to an edge
    b.box((0.04, 0.04, 0.14), (0, 0, 0.0), P["rag"])
    b.ball(0.035, (0, 0, 0.085), P["bone_old"], subdiv=0)
    b.box((0.055, 0.02, 0.34), (0.01, 0, 0.27), P["bone"], var=0.08, taper=(0.25, 1))
    b.to_object("BoneKnife")
    export("bone_knife")


def build_cooking_items():
    """Cooked food: grilled fish and a steak on a trencher, a bowl of stew."""
    def plate(b):
        b.cyl(0.16, 0.15, 0.025, (0, 0, 0.012), P["wood"], segs=10)

    b = Builder()  # grilled fish
    plate(b)
    b.ball(0.05, (0, 0, 0.07), P["rust"], scale=(2.6, 0.9, 0.8), subdiv=1, var=0.1)
    b.box((0.02, 0.07, 0.07), (-0.15, 0, 0.07), P["leather_dark"], var=0.0)
    b.box((0.10, 0.01, 0.01), (0.02, -0.03, 0.11), P["black"], var=0.0)  # grill marks
    b.box((0.10, 0.01, 0.01), (-0.04, -0.03, 0.11), P["black"], var=0.0)
    b.to_object("CookedFish")
    export("cooked_fish")
    reset_scene()

    b = Builder()  # steak
    plate(b)
    b.ball(0.08, (0, 0, 0.06), P["leather_dark"], scale=(1.4, 1, 0.45), subdiv=1, var=0.12)
    b.ball(0.03, (0.06, 0.02, 0.08), P["bone"], scale=(1, 1, 0.6), subdiv=0)
    b.to_object("Steak")
    export("steak")
    reset_scene()

    b = Builder()  # stew in a bowl
    b.cyl(0.12, 0.08, 0.09, (0, 0, 0.045), P["wood_dark"], segs=10)
    b.cyl(0.11, 0.11, 0.01, (0, 0, 0.085), P["rust"], segs=10, var=0.1)
    b.ball(0.025, (0.03, 0.02, 0.09), P["moss"], subdiv=0)
    b.ball(0.02, (-0.04, -0.01, 0.09), P["bone"], subdiv=0)
    b.to_object("Stew")
    export("stew")


def build_innkeeper():
    """Hester Vale, keeper of the Ford Inn: same joint layout as the Warden."""
    root = empty("Innkeeper")

    def legs(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.16, 0.18, 0.48), (0, 0, -0.26), P["cloth_red"])
            b.box((0.15, 0.17, 0.40), (0, 0.01, -0.66), P["cloth"])
            b.box((0.16, 0.24, 0.09), (0, -0.04, -0.88), P["leather_dark"])
        return part("Leg_" + side, root, (0.11 * s, 0, 0.93), fn)

    legs("L")
    legs("R")

    def torso(b):
        b.box((0.44, 0.27, 0.30), (0, 0, 0.10), P["cloth_red"])
        b.box((0.44, 0.27, 0.40), (0, 0, 0.42), P["cloth_red"], taper=(1.0, 0.92), var=0.1)
        b.box((0.36, 0.03, 0.58), (0, -0.14, 0.18), P["parchment"], var=0.06)   # apron
        b.box((0.46, 0.29, 0.05), (0, 0, 0.28), P["leather_dark"])              # apron string
        b.box((0.10, 0.06, 0.12), (0.18, -0.17, 0.12), P["brass"], var=0.0)    # keys
    t = part("Torso", root, (0, 0, 0.92), torso)

    def head(b):
        b.box((0.08, 0.08, 0.08), (0, 0, 0.03), P["skin"])
        b.box((0.21, 0.23, 0.25), (0, 0, 0.19), P["skin"], taper=(0.92, 0.9))
        b.box((0.18, 0.03, 0.03), (0, -0.12, 0.22), P["black"], var=0.0)
        b.box((0.24, 0.25, 0.12), (0, 0.02, 0.33), P["hair"], var=0.1)          # hair
        b.ball(0.08, (0, 0.13, 0.30), P["hair"], subdiv=0)                       # bun
    part("Head", t, (0, 0, 0.66), head)

    def arm(side):
        s = 1 if side == "L" else -1

        def fn(b):
            b.box((0.13, 0.14, 0.40), (0, 0, -0.18), P["cloth_red"])
            b.box((0.10, 0.11, 0.14), (0, -0.01, -0.46), P["skin"])
        return part("Arm_" + side, t, (0.28 * s, 0, 0.56), fn)

    arm("L")
    arm("R")
    export("innkeeper")


def build_town():
    """Brackenford: the Ford Inn (shell, the wall facing the camera, roof),
    cottages, a well and lamp posts. Game +Z (south, towards the camera) is
    Blender -Y."""
    W, D, H = 12.0, 9.0, 3.0
    b = Builder()  # the inn's shell: floor, north/east/west walls, fittings
    b.box((W, D, 0.12), (0, 0, 0.06), P["wood"], var=0.06)
    for i in range(-5, 6):
        b.box((0.04, D - 0.4, 0.005), (i, 0, 0.123), P["wood_dark"], var=0.0)        # floorboards
    b.box((W, 0.3, H), (0, D / 2, H / 2), P["wood_grey"], var=0.08)                    # north
    b.box((0.3, D, H), (W / 2, 0, H / 2), P["wood_grey"], var=0.08)                    # east
    for y0, y1 in ((-D / 2, -0.9), (0.9, D / 2)):                                      # west, door gap
        b.box((0.3, y1 - y0, H), (-W / 2, (y0 + y1) / 2, H / 2), P["wood_grey"], var=0.08)
    b.box((0.3, 1.8, 0.8), (-W / 2, 0, H - 0.4), P["wood_grey"])                       # over the door
    for x in (-W / 2, -2, 2, W / 2):                                                   # timber frame
        b.box((0.36, 0.36, H), (x, D / 2, H / 2), P["wood_dark"], var=0.0)
    b.box((W + 0.2, 0.36, 0.25), (0, D / 2, H - 0.12), P["wood_dark"], var=0.0)
    b.box((0.36, D + 0.2, 0.25), (W / 2, 0, H - 0.12), P["wood_dark"], var=0.0)
    b.box((0.36, D + 0.2, 0.25), (-W / 2, 0, H - 0.12), P["wood_dark"], var=0.0)
    # hearth on the north wall, west end, with a chimney through the roof
    b.box((2.2, 0.9, 1.3), (-3.8, D / 2 - 0.55, 0.65), P["stone"], var=0.1)
    b.box((1.2, 0.5, 0.7), (-3.8, D / 2 - 0.85, 0.45), P["black"], var=0.0)            # fire mouth
    b.ball(0.22, (-3.8, D / 2 - 0.9, 0.35), P["flame"], scale=(1.4, 0.8, 1.1), subdiv=1, glow=True)
    b.box((1.4, 0.8, 4.0), (-3.8, D / 2 - 0.4, 3.0), P["stone_dark"], var=0.1)
    b.cyl(0.03, 0.03, 0.8, (-3.4, D / 2 - 1.0, 1.0), P["iron"], segs=5)                 # spit post
    b.ball(0.18, (-3.9, D / 2 - 1.0, 0.55), P["iron"], scale=(1, 1, 0.8), subdiv=1)     # pot
    # the bar along the north wall, east end, and kegs behind it
    b.box((3.6, 0.6, 1.05), (3.2, D / 2 - 1.6, 0.52), P["wood_dark"], var=0.06)
    b.box((3.8, 0.7, 0.08), (3.2, D / 2 - 1.6, 1.08), P["wood"], var=0.04)
    for x in (2.2, 3.2, 4.2):
        b.cyl(0.3, 0.3, 0.7, (x, D / 2 - 0.5, 0.5), P["wood"], segs=10, rot=(90, 0, 0))
        b.cyl(0.31, 0.31, 0.06, (x, D / 2 - 0.5, 0.5), P["iron"], segs=10, rot=(90, 0, 0))
    # tables and stools
    for (tx, ty) in ((-2.2, -1.2), (1.4, -2.4), (-1.0, 1.4)):
        b.box((1.4, 0.9, 0.08), (tx, ty, 0.76), P["wood"], var=0.06)
        b.box((0.12, 0.12, 0.72), (tx, ty, 0.38), P["wood_dark"])
        for dx in (-0.9, 0.9):
            b.cyl(0.18, 0.18, 0.45, (tx + dx, ty, 0.23), P["wood_dark"], segs=8)
    # beds against the east wall, south end
    for by in (-3.4, -1.6):
        b.box((2.0, 1.0, 0.45), (W / 2 - 1.3, by, 0.23), P["wood_dark"])
        b.box((1.8, 0.9, 0.15), (W / 2 - 1.35, by, 0.52), P["parchment"], var=0.05)
        b.box((1.0, 0.92, 0.12), (W / 2 - 1.75, by, 0.55), P["cloth_red"], var=0.05)
        b.box((0.3, 0.6, 0.12), (W / 2 - 0.5, by, 0.62), P["candle"], var=0.0)            # pillow
    # a lantern by the door
    b.ball(0.12, (-W / 2 - 0.3, 1.2, 2.2), P["flame"], subdiv=1, glow=True)
    b.to_object("InnShell")
    export("inn_shell")
    reset_scene()

    b = Builder()  # the south wall, which fades when you are inside
    b.box((W, 0.3, H), (0, -D / 2, H / 2), P["wood_grey"], var=0.08)
    for x in (-W / 2, -2, 2, W / 2):
        b.box((0.36, 0.36, H), (x, -D / 2, H / 2), P["wood_dark"], var=0.0)
    b.box((W + 0.2, 0.36, 0.25), (0, -D / 2, H - 0.12), P["wood_dark"], var=0.0)
    for x in (-4, 0, 4):                                                               # lit windows
        b.box((1.0, 0.34, 0.8), (x, -D / 2, 1.7), P["flame"], var=0.0, glow=True)
        b.box((1.15, 0.38, 0.1), (x, -D / 2, 2.15), P["wood_dark"], var=0.0)
    b.to_object("InnFront")
    export("inn_front")
    reset_scene()

    b = Builder()  # the roof (gabled, ridge east-west) and the sign
    pitch = 34
    half = D / 2 + 0.6
    for side in (1, -1):
        b.box((W + 0.8, half / math.cos(math.radians(pitch)), 0.18),
              (0, side * half / 2, H + half / 2 * math.tan(math.radians(pitch))),
              P["wood_dark"] if side > 0 else P["bark"], rot=(side * pitch, 0, 0), var=0.1)
    for x in (-W / 2, W / 2):                                                          # gable ends
        for i in range(5):
            h = (i + 0.5) * 0.6
            wdt = (D + 0.2) * (1 - (i + 0.5) / 5.5)
            b.box((0.3, wdt, 0.6), (x, 0, H + h), P["wood_grey"], var=0.06)
    b.box((1.6, 0.06, 0.7), (-W / 2 - 0.9, 0.6, 2.4), P["wood"], var=0.05)             # sign board
    b.box((0.06, 0.06, 1.0), (-W / 2 - 0.5, 0.6, 2.9), P["iron"], var=0.0)
    b.to_object("InnRoof")
    export("inn_roof")
    reset_scene()

    b = Builder()  # a cottage, closed up
    b.box((6, 5, 2.6), (0, 0, 1.3), P["ash"], var=0.08)
    for x in (-3, 3):
        b.box((0.3, 5.1, 2.6), (x, 0, 1.3), P["wood_dark"], var=0.0)
    b.box((1.0, 0.1, 1.9), (0.8, -2.52, 0.95), P["wood_dark"], var=0.0)               # door
    b.box((0.8, 0.1, 0.6), (-1.6, -2.52, 1.6), P["flame"], var=0.0, glow=True)        # window
    for side in (1, -1):
        b.box((6.6, 3.5, 0.16), (0, side * 1.4, 3.5), P["bark"], rot=(side * 38, 0, 0), var=0.1)
    for x in (-3, 3):
        for i in range(3):
            b.box((0.28, 4.6 * (1 - (i + 0.5) / 3.6), 0.5), (x, 0, 2.85 + i * 0.5), P["ash"], var=0.06)
    b.box((0.6, 0.6, 1.6), (2.0, 1.2, 4.2), P["stone_dark"], var=0.1)                 # chimney
    b.to_object("Cottage")
    export("cottage")
    reset_scene()

    b = Builder()  # the village well
    b.cyl(0.9, 0.95, 0.8, (0, 0, 0.4), P["stone"], segs=12, var=0.1)
    b.cyl(0.7, 0.7, 0.05, (0, 0, 0.78), P["black"], segs=12, var=0.0)
    for x in (-0.85, 0.85):
        b.box((0.14, 0.14, 1.9), (x, 0, 1.3), P["wood_dark"])
    b.box((2.2, 1.4, 0.12), (0, 0, 2.3), P["bark"], rot=(0, 0, 0), var=0.1)
    b.cyl(0.08, 0.08, 1.7, (0, 0, 1.7), P["wood"], segs=6, rot=(0, 90, 0))
    b.cyl(0.14, 0.12, 0.2, (0.2, 0, 1.3), P["wood"], segs=8)                          # bucket
    b.to_object("Well")
    export("well")
    reset_scene()

    b = Builder()  # a lamp post
    b.box((0.14, 0.14, 2.6), (0, 0, 1.3), P["wood_dark"])
    b.box((0.6, 0.08, 0.08), (0.25, 0, 2.55), P["iron"], var=0.0)
    b.box((0.22, 0.22, 0.3), (0.5, 0, 2.3), P["iron"], var=0.0)
    b.ball(0.09, (0.5, 0, 2.3), P["flame"], subdiv=1, glow=True)
    b.to_object("LampPost")
    export("lamp_post")


BUILDERS = [
    build_warden, build_ghoul, build_brute, build_cart,
    lambda: build_crate(False), lambda: build_crate(True), build_wheel,
    build_shrine, build_watch_post, build_pine, build_dead_tree,
    lambda: build_rock(0), lambda: build_rock(1),
    lambda: build_gravestone(0), lambda: build_gravestone(1),
    build_ruin_wall, build_waymarker, build_fence, build_items, build_equipment,
    build_mara, build_forge_camp, build_shop_items,
    build_hound, build_archer, build_seer, build_blackwood_props, build_blackwood_items,
    build_loot_items, build_tam, build_camp_items, build_one_handers,
    build_cooking_items, build_innkeeper, build_town,
]

if __name__ == "__main__":
    # `-- build_loot_items` builds only the named builders
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for fn in BUILDERS:
        if only and getattr(fn, "__name__", "") not in only:
            continue
        reset_scene()
        fn()
    print("done:", sorted(os.listdir(OUT_GLB)))
