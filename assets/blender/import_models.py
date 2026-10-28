"""
Shadowfell imported models.

Turns bought or downloaded models (assets/blender/imported/*.glb, see
assets/blender/imported/CREDITS.md for their licences) and the base male
body (assets/blender/base_male.blend) into game-ready glTF binaries in
assets/models/:

  rat.glb, chicken.glb   the creature's own skeleton, with Idle, Walk,
                         Attack and Death clips keyed here
  stylized_dagger.glb    a held weapon: grip at the origin, blade up +Y
  stylized_sword.glb
  base_male.glb          the base male body on a new Mixamo-named skeleton
                         (automatic weights), with Idle and Walk test clips

Run headless with either:
    blender --background --python assets/blender/import_models.py
or, with the bpy module installed (pip install bpy):
    python assets/blender/import_models.py

Conventions (game/core/assets.gd and game/entities/rig.gd rely on these):
  * 1 Blender unit = 1 metre, feet on the ground at the origin, forward is
    Blender -Y (+Z in the game), as build_fx.py.
  * Textured materials are named "T_<name>": the game keeps them as they are
    instead of swapping in its shared vertex-colour material. Only the base
    colour map is kept, shrunk, for the retro look (no normal or roughness
    maps, which the flat-shaded world does not use).
  * Clip names: Idle, Walk (loops), Attack, Death (plays once and holds).
"""
import math
import os

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "imported")
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
FPS = 24


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def import_glb(name):
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name))


def flatten():
    """Unparent every mesh and armature (keeping where they are), drop the
    empties the exporter wrapped them in, and bake in their transforms."""
    # the glTF importer draws bones with a sphere mesh: not part of the model
    for o in list(bpy.data.objects):
        if o.type == "ARMATURE":
            for pb in o.pose.bones:
                if pb.custom_shape:
                    shape = pb.custom_shape
                    pb.custom_shape = None
                    if shape.name in bpy.data.objects:
                        bpy.data.objects.remove(shape)
    keep = [o for o in bpy.data.objects if o.type in ("MESH", "ARMATURE")]
    for o in keep:
        mw = o.matrix_world.copy()
        if o.type == "MESH" and o.parent and o.parent.type == "ARMATURE":
            continue
        o.parent = None
        o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type not in ("MESH", "ARMATURE"):
            bpy.data.objects.remove(o)
    # skinned meshes keep their armature parent but must sit at its origin
    for o in keep:
        if o.type == "MESH" and o.parent:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
    apply_all(keep)
    for o in keep:
        if o.type == "MESH":
            arm = next((m.object for m in o.modifiers if m.type == "ARMATURE"), None)
            if arm:
                o.parent = arm
    for a in bpy.data.actions:
        bpy.data.actions.remove(a)
    return keep


def apply_all(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def transform_all(objs, m):
    for o in objs:
        if o.parent is None:
            o.matrix_world = m @ o.matrix_world
    apply_all(objs)


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return lo, hi


def retexture(objs, name, size):
    """One plain material per model: the base colour map shrunk to `size`."""
    img = None
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            if m and m.node_tree and img is None:
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image:
                        links = [l for l in n.outputs["Color"].links if l.to_socket.name in ("Base Color", "Color")]
                        if links:
                            img = n.image
                            break
    if img is None:
        raise RuntimeError("no base colour texture in " + name)
    img = img.copy()
    img.name = "T_" + name
    if img.size[0] > size:
        img.scale(size, size)
    img.file_format = "PNG"
    mat = bpy.data.materials.new("T_" + name)
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    for o in objs:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)


def export(path, animations=True):
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, path), export_format="GLB", export_yup=True,
        export_apply=False, export_animations=animations, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_anim_single_armature=True,
        export_image_format="AUTO", export_texcoords=True, export_normals=True,
        export_skins=True, export_def_bones=False, export_reset_pose_bones=True,
        export_extras=False, export_cameras=False, export_lights=False)
    print("wrote", path)


# ---- weapons -----------------------------------------------------------------

def weapon(src, out, length, pommel, flip):
    """Lay a held weapon in the game's grip space: blade along +Z here (+Y in
    the game), flat side facing -Y, `length` metres long, the grip at the
    origin `pommel` metres above the butt end. `flip` turns it end over end
    when the blade would point down (checked by eye: game/tests/model_shots.gd)."""
    reset_scene()
    import_glb(src)
    objs = flatten()
    meshes = [o for o in objs if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    # line the model's own axes (some come in at a slant) up with X, Y, Z:
    # the longest spread becomes Z, the thinnest Y
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    centre = sum(pts, Vector()) / len(pts)
    cov = Matrix(((0.0,) * 3,) * 3)
    for p in pts:
        d = p - centre
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    axes = []
    m = cov.copy()
    for _ in range(3):
        v = Vector((1.0, 0.7, 0.3))
        for _ in range(100):
            v = (m @ v).normalized()
        lam = v.dot(cov @ v)
        axes.append(v)
        m = m - lam * Matrix([[v[i] * v[j] for j in range(3)] for i in range(3)])
    long_, wide, thin = axes
    rot = Matrix((wide, -thin, long_))
    if rot.determinant() < 0:
        rot = Matrix((-wide, -thin, long_))
    transform_all([ob], rot.to_4x4() @ Matrix.Translation(-centre))
    if flip:
        transform_all([ob], Matrix.Rotation(math.pi, 4, "Y"))
    lo, hi = bounds([ob])
    s = length / (hi.z - lo.z)
    transform_all([ob], Matrix.Scale(s, 4) @ Matrix.Translation(Vector((0, 0, -lo.z)) - Vector((0, 0, pommel / s))))
    ob.name = out.replace(".glb", "")
    retexture([ob], ob.name, 256)
    export(out, animations=False)


# ---- creatures ---------------------------------------------------------------

class Poser:
    """Keys bone turns about world axes (forward is -Y, up +Z, X is the
    creature's left-right), so clips read the same whatever the bones' own
    rolls are."""

    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}

    def bone(self, key):
        for b in self.arm.pose.bones:
            if b.name.startswith(key + "__") or b.name == key:
                return b
        raise KeyError(key)

    def clip(self, name, frames, loop, keys):
        """keys(t) -> {bone: [(axis, radians) | ("loc", Vector)]} for t in 0..1"""
        act = bpy.data.actions.new(name)
        self.arm.animation_data_create()
        self.arm.animation_data.action = act
        for pb in self.arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        step = 2
        for f in range(0, frames + 1, step):
            t = f / frames
            pose = keys(t if not loop or f < frames else 0.0)
            for pb in self.arm.pose.bones:
                q = Quaternion()
                loc = Vector()
                for k, turns in pose.items():
                    if pb.name.startswith(k + "__") or pb.name == k:
                        for axis, a in turns:
                            if axis == "loc":
                                loc += self.rest[pb.name].inverted() @ a
                                continue
                            w = Vector({"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis])
                            local = self.rest[pb.name].inverted() @ w
                            q = Quaternion(local.normalized(), a) @ q
                pb.rotation_quaternion = q
                pb.location = loc
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        act.use_fake_user = True
        track = self.arm.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        self.arm.animation_data.action = None


def creature(src, out, size_axis, size, tex):
    """Face the creature down -Y with its feet at the origin, `size` metres
    along `size_axis` (0 length, 2 height)."""
    reset_scene()
    import_glb(src)
    objs = flatten()
    arm = next(o for o in objs if o.type == "ARMATURE")
    head = next(b for b in arm.data.bones if b.name.startswith("HEAD__"))
    base = next(b for b in arm.data.bones if b.name.startswith("BASE__"))
    fwd = (arm.matrix_world @ head.head_local) - (arm.matrix_world @ base.head_local)
    fwd.z = 0
    yaw = math.atan2(fwd.x, -fwd.y)  # turn fwd onto -Y
    lo, hi = bounds(objs)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    transform_all(objs, Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation(-centre))
    lo, hi = bounds(objs)
    ext = hi - lo
    s = size / (ext.y if size_axis == 0 else ext.z)
    transform_all(objs, Matrix.Scale(s, 4))
    for o in objs:
        o.name = out.replace(".glb", "") if o.type == "MESH" else "Skeleton"
    retexture(objs, out.replace(".glb", ""), tex)
    return arm


def sin(t, n=1.0, ph=0.0):
    return math.sin((t * n + ph) * math.tau)


def rat():
    arm = creature("stylized_rat.glb", "rat.glb", 0, 0.62, 512)
    p = Poser(arm)
    L = 0.62  # body length, for moves in metres

    def idle(t):
        sniff = max(0.0, sin(t, 4)) * 0.12
        return {
            "CHEST": [("x", sin(t, 1) * 0.04)],
            "HEAD": [("x", -0.1 - sniff), ("z", sin(t, 1, 0.2) * 0.25)],
            "TAIL": [("z", sin(t, 1) * 0.25)],
            "TAIL1": [("z", sin(t, 1, 0.15) * 0.3)],
            "TAIL2": [("z", sin(t, 1, 0.3) * 0.35)],
        }

    def walk(t):
        a, b = sin(t), sin(t, 1, 0.5)
        return {
            "BASE": [("loc", Vector((0, 0, abs(sin(t, 2)) * 0.012 * L / 0.62)))],
            "CHEST": [("x", sin(t, 2) * 0.05)],
            "HEAD": [("x", sin(t, 2, 0.25) * 0.08)],
            "LF_SHOULDER": [("x", a * 0.55)],
            "RT_SHOULDER": [("x", b * 0.55)],
            "LF_ELBOW": [("x", max(0.0, -a) * 0.5)],
            "RT_ELBOW": [("x", max(0.0, -b) * 0.5)],
            "LF_HIP": [("x", b * 0.6)],
            "RT_HIP": [("x", a * 0.6)],
            "LF_KNEE": [("x", max(0.0, a) * -0.5)],
            "RT_KNEE": [("x", max(0.0, b) * -0.5)],
            "TAIL": [("z", sin(t) * 0.3)],
            "TAIL1": [("z", sin(t, 1, 0.2) * 0.35)],
            "TAIL2": [("z", sin(t, 1, 0.4) * 0.4)],
        }

    def attack(t):
        # rear up and back (0..0.45), snap forward and bite (0.45..0.6), recover
        up = math.sin(min(1.0, t / 0.45) * math.pi / 2) if t < 0.45 else max(0.0, 1 - (t - 0.45) / 0.15)
        lunge = 0.0 if t < 0.45 else math.sin(min(1.0, (t - 0.45) / 0.2) * math.pi) * (1 - max(0.0, t - 0.75) / 0.25)
        return {
            "BASE": [("loc", Vector((0, 0.06 * up - 0.1 * lunge, 0.0)))],
            "CHEST": [("x", -0.45 * up + 0.25 * lunge)],
            "HEAD": [("x", -0.3 * up + 0.35 * lunge)],
            "LF_SHOULDER": [("x", -0.6 * up + 0.5 * lunge)],
            "RT_SHOULDER": [("x", -0.6 * up + 0.5 * lunge)],
            "TAIL": [("x", 0.25 * up)],
        }

    def death(t):
        k = min(1.0, t / 0.4)
        k = k * k * (3 - 2 * k)
        curl = min(1.0, t / 0.6)
        return {
            # roll onto its side about the hips (the root bone's pivot is far off)
            "BASE": [("y", -1.45 * k), ("loc", Vector((0, 0, -0.06 * k)))],
            "LF_SHOULDER": [("x", -0.6 * curl)],
            "RT_SHOULDER": [("x", -0.5 * curl)],
            "LF_HIP": [("x", 0.6 * curl)],
            "RT_HIP": [("x", 0.5 * curl)],
            "HEAD": [("x", 0.3 * curl)],
            "TAIL": [("z", 0.5 * curl)],
        }

    p.clip("Idle", 48, True, idle)
    p.clip("Walk", 16, True, walk)
    p.clip("Attack", 14, False, attack)
    p.clip("Death", 24, False, death)
    export("rat.glb")


WING_FOLD = 0.6


def chicken():
    arm = creature("stylized_chicken.glb", "chicken.glb", 2, 0.5, 512)
    p = Poser(arm)

    def idle(t):
        # look about, then peck at the ground once a loop
        peck = math.sin(min(1.0, max(0.0, (t - 0.6) / 0.25)) * math.pi)
        look = sin(t, 1) * 0.5 if t < 0.55 else 0.0
        return {
            "CHEST": [("x", sin(t, 2) * 0.03 + peck * 0.25)],
            "NECK1": [("x", peck * 0.5)],
            "NECK2": [("x", peck * 0.4)],
            "HEAD": [("z", look), ("x", peck * 0.2)],
            "TAIL": [("z", sin(t, 2) * 0.08)],
        }

    def walk(t):
        a, b = sin(t), sin(t, 1, 0.5)
        thrust = sin(t, 2)
        return {
            "BASE": [("loc", Vector((0, 0, abs(sin(t, 2)) * 0.012))), ("y", sin(t) * 0.06)],
            "NECK1": [("loc", Vector((0, -thrust * 0.02, 0)))],
            "NECK2": [("x", thrust * 0.15)],
            "HEAD": [("x", -thrust * 0.15)],
            "LF_KNEE": [("x", a * 0.6)],
            "RT_KNEE": [("x", b * 0.6)],
            "LF_ANKLE": [("x", max(0.0, -a) * -0.6)],
            "RT_ANKLE": [("x", max(0.0, -b) * -0.6)],
            "LF_WING": [("y", 0.05 + abs(a) * 0.05)],
            "RT_WING": [("y", -0.05 - abs(a) * 0.05)],
            "TAIL": [("x", sin(t, 2) * 0.1)],
        }

    def attack(t):
        # two quick pecks
        k = abs(math.sin(t * 2 * math.pi))
        return {
            "CHEST": [("x", k * 0.35)],
            "NECK1": [("x", k * 0.5)],
            "NECK2": [("x", k * 0.4)],
            "LF_WING": [("y", 0.4 * k)],
            "RT_WING": [("y", -0.4 * k)],
        }

    def death(t):
        k = min(1.0, t / 0.4)
        k = k * k * (3 - 2 * k)
        return {
            "BASE": [("y", 1.5 * k), ("loc", Vector((0, 0, -0.1 * k)))],
            "NECK1": [("x", 0.4 * k)],
            "HEAD": [("x", 0.3 * k)],
            "LF_KNEE": [("x", -0.5 * k)],
            "RT_KNEE": [("x", -0.4 * k)],
            "LF_WING": [("y", 0.3 * k)],
        }

    def folded(keys):
        # the model was posed with its wings held out: fold them to the body
        def out(t):
            k = keys(t)
            k["LF_WING"] = [("y", -WING_FOLD)] + k.get("LF_WING", [])
            k["RT_WING"] = [("y", WING_FOLD)] + k.get("RT_WING", [])
            return k
        return out

    p.clip("Idle", 72, True, folded(idle))
    p.clip("Walk", 16, True, folded(walk))
    p.clip("Attack", 14, False, folded(attack))
    p.clip("Death", 24, False, folded(death))
    export("chicken.glb")


# ---- the base male on a skeleton --------------------------------------------

def base_male():
    """Build a Mixamo-named skeleton for the T-posed base male, bind it with
    automatic weights and key two test clips."""
    reset_scene()
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "base_male.blend"))
    bpy.context.scene.render.fps = FPS
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    body = bpy.data.objects["Body"]
    lo, hi = bounds([body])
    H = hi.z - lo.z
    vs = [body.matrix_world @ v.co for v in body.data.vertices]

    def mean(pts):
        return sum(pts, Vector()) / max(1, len(pts))

    # landmarks from the mesh: the arm line in the T-pose, the legs' centres
    arm_pts = [v for v in vs if v.x > (hi.x * 0.55)]
    arm_z = mean(arm_pts).z
    leg_pts = [v for v in vs if v.z < lo.z + H * 0.25 and v.x > 0]
    leg_x = mean(leg_pts).x
    hand_x = hi.x
    z = lambda f: lo.z + H * f
    sh_x = hi.x * 0.16
    joints = {
        "Hips": ((0, 0, z(0.53)), (0, 0, z(0.6)), None),
        "Spine": ((0, 0, z(0.6)), (0, 0, z(0.68)), "Hips"),
        "Spine1": ((0, 0, z(0.68)), (0, 0, z(0.76)), "Spine"),
        "Spine2": ((0, 0, z(0.76)), (0, 0, z(0.83)), "Spine1"),
        "Neck": ((0, 0, z(0.83)), (0, 0, z(0.88)), "Spine2"),
        "Head": ((0, 0, z(0.88)), (0, 0, hi.z), "Neck"),
    }
    for side, sx in (("Left", 1), ("Right", -1)):
        joints[side + "Shoulder"] = ((sx * hi.x * 0.04, 0, arm_z + H * 0.01), (sx * sh_x, 0, arm_z), "Spine2")
        joints[side + "Arm"] = ((sx * sh_x, 0, arm_z), (sx * hand_x * 0.55, 0, arm_z), side + "Shoulder")
        joints[side + "ForeArm"] = ((sx * hand_x * 0.55, 0, arm_z), (sx * hand_x * 0.86, 0, arm_z), side + "Arm")
        joints[side + "Hand"] = ((sx * hand_x * 0.86, 0, arm_z), (sx * hand_x, 0, arm_z), side + "ForeArm")
        joints[side + "UpLeg"] = ((sx * leg_x, 0, z(0.51)), (sx * leg_x, -0.01, z(0.28)), "Hips")
        joints[side + "Leg"] = ((sx * leg_x, -0.01, z(0.28)), (sx * leg_x, 0.02, z(0.05)), side + "UpLeg")
        joints[side + "Foot"] = ((sx * leg_x, 0.02, z(0.05)), (sx * leg_x, -0.1, z(0.01)), side + "Leg")
    adata = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", adata)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in joints.items():
        eb = adata.edit_bones.new("mixamorig_" + name)
        eb.head, eb.tail = Vector(h), Vector(t)
        eb.roll = 0
        if parent:
            eb.parent = adata.edit_bones["mixamorig_" + parent]
            eb.use_connect = (Vector(h) - Vector(joints[parent][1])).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    # bind: automatic (heat) weights for the body, the head bone for the rest
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for o in meshes:
        if o is body:
            continue
        vg = o.vertex_groups.new(name="mixamorig_Head")
        vg.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        o.parent = arm
    for mat in bpy.data.materials:
        if mat.name == "M_BaseMale":
            mat.name = "T_base_male"
    p = Poser(arm)
    p.bone = lambda key: arm.pose.bones["mixamorig_" + key]
    # Poser matches "KEY__" or the exact name; give it exact names
    m = lambda k: "mixamorig_" + k

    def relax(t):
        # arms down from the T-pose; X turns are pitch, Y turns lower an arm
        return {
            m("LeftArm"): [("y", 1.2)],
            m("RightArm"): [("y", -1.2)],
            m("LeftForeArm"): [("x", -0.15)],
            m("RightForeArm"): [("x", -0.15)],
        }

    def idle(t):
        k = relax(t)
        k[m("Spine1")] = [("x", sin(t) * 0.02)]
        k[m("Head")] = [("z", sin(t, 1, 0.25) * 0.08)]
        k[m("LeftArm")].append(("x", sin(t) * 0.03))
        k[m("RightArm")].append(("x", -sin(t) * 0.03))
        return k

    def walk(t):
        a = sin(t)
        k = relax(t)
        k[m("Hips")] = [("loc", Vector((0, 0, abs(sin(t, 2)) * 0.03))), ("z", a * 0.08)]
        k[m("Spine1")] = [("z", -a * 0.12)]
        k[m("LeftUpLeg")] = [("x", -a * 0.5)]
        k[m("RightUpLeg")] = [("x", a * 0.5)]
        k[m("LeftLeg")] = [("x", max(0.0, sin(t, 1, 0.25)) * 0.8)]
        k[m("RightLeg")] = [("x", max(0.0, sin(t, 1, 0.75)) * 0.8)]
        k[m("LeftArm")].append(("x", a * 0.4))
        k[m("RightArm")].append(("x", -a * 0.4))
        return k

    p.clip("Idle", 72, True, idle)
    p.clip("Walk", 24, True, walk)
    arm.data.pose_position = "POSE"
    export("base_male.glb")


if __name__ == "__main__":
    import sys
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    jobs = {
        "dagger": lambda: weapon("stylized_dagger.glb", "stylized_dagger.glb", 0.52, 0.09, False),
        "sword": lambda: weapon("stylized_sword.glb", "stylized_sword.glb", 1.04, 0.15, True),
        "rat": rat,
        "chicken": chicken,
        "male": base_male,
    }
    for k, job in jobs.items():
        if not only or k in only:
            job()
