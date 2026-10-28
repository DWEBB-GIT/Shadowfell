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
  skeleton.glb           the risen dead (undead enemies): the model's own
                         skeleton, with Idle, Walk, Attack, Hit and Death
                         clips keyed here
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
  * Clip names: Idle, Walk (loops), Attack, Hit, Death (plays once and holds).
"""
import json
import math
import os
import re

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "imported")
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
FPS = 24


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def import_glb(name, guess_bind=True):
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name), guess_original_bind_pose=guess_bind)


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


# ---- spell poses -------------------------------------------------------------

def key3(t, up, impact, wind, blow, snap=0.3, follow=0.3):
    """One key of a blow, as Rig._key3 in game/entities/rig.gd: snapped into
    the windup (`snap` of the time to `up`), held, whipped through to the
    blow by `impact`, held there (`follow` of the rest), then back to rest."""
    if t < up:
        x = min(1.0, t / max(0.001, up * snap))
        return wind * (1 - (1 - x) ** 2)
    if t < impact:
        x = (t - up) / (impact - up)
        return wind + (blow - wind) * x * x
    after = impact + (1 - impact) * follow
    if t < after:
        return blow
    x = (t - after) / (1 - after)
    return blow * (1 - x * x * (3 - 2 * x))


# the game's body parts on the rigged player's bones, and each part axis as a
# turn about a world axis here (game x = x, game y (up) = z, game z (forward)
# = -y, as forward is -Y in Blender and +Z in the game)
PART_BONES = {"Torso": "Spine1", "Head": "Head", "Arm_R": "RightArm", "Arm_L": "LeftArm", "Leg_L": "LeftUpLeg", "Leg_R": "RightUpLeg"}
AXES = [("x", 1), ("z", 1), ("y", -1)]
# where a clip's blow falls (Rig.CLIP_IMPACT)
CLIP_IMPACT = 0.5


def spell_clips(p, m):
    """A clip for every spell pose in data/spell_fx.json `poses`, named as
    the pose, keyed every frame so the snap and the whip stay sharp."""
    path = os.path.join(HERE, "..", "..", "data", "spell_fx.json")
    with open(path) as f:
        poses = json.load(f)["poses"]
    for name, pose in poses.items():
        up = CLIP_IMPACT * pose["up"]

        def keys(t, pose=pose, up=up):
            out = {}
            for part, axis, wind, blow in pose["keys"]:
                ax, sign = AXES[axis]
                out.setdefault(m(PART_BONES[part]), []).append((ax, sign * key3(t, up, CLIP_IMPACT, wind, blow)))
            hips = []
            raise_ = min(1.0, t / CLIP_IMPACT) if t < CLIP_IMPACT else max(0.0, 1 - (t - CLIP_IMPACT) / (1 - CLIP_IMPACT))
            raise_ = raise_ * raise_ * (3 - 2 * raise_)
            lift = 0.0
            if "hop" in pose:
                lift += pose["hop"] * math.sin(math.pi * min(1.0, t / CLIP_IMPACT))
            if "sink" in pose:
                lift -= pose["sink"] * raise_
            if lift:
                hips.append(("loc", Vector((0, 0, lift))))
            if "spin" in pose:
                k = min(1.0, t / CLIP_IMPACT)
                hips.append(("z", -2 * math.pi * pose["spin"] * k * k * (3 - 2 * k)))
            if hips:
                out[m("Hips")] = hips
            return out

        p.clip(name, 24, False, keys, step=1)


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

    def pose(self, pose):
        """Set the bones to one pose: {bone: [(axis, radians) | ("loc", Vector)]}"""
        for pb in self.arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
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

    def clip(self, name, frames, loop, keys, step=2):
        """keys(t) -> {bone: [(axis, radians) | ("loc", Vector)]} for t in 0..1"""
        act = bpy.data.actions.new(name)
        self.arm.animation_data_create()
        self.arm.animation_data.action = act
        for pb in self.arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        for f in range(0, frames + 1, step):
            t = f / frames
            self.pose(keys(t if not loop or f < frames else 0.0))
            for pb in self.arm.pose.bones:
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


def skeleton():
    """The risen dead: a T-posed humanoid (Reallusion CC bone names) stood
    facing -Y, 1.8 m tall, its arms keyed down for every clip."""
    reset_scene()
    # the file's skin binds a different pose than its bones' rest: take the
    # bones as they stand so the two agree
    import_glb("stylized_skeleton.glb", guess_bind=False)
    objs = flatten()
    arm = next(o for o in objs if o.type == "ARMATURE")
    for b in arm.data.bones:
        b.name = re.sub(r"_\d+$", "", b.name)
    bone = lambda n: arm.matrix_world @ arm.data.bones["CC_Base_" + n].head_local
    left = bone("L_Upperarm") - bone("R_Upperarm")
    yaw = math.atan2(left.y, left.x)  # turn its left onto +X, so it faces -Y
    lo, hi = bounds(objs)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    transform_all(objs, Matrix.Rotation(-yaw, 4, "Z") @ Matrix.Translation(-centre))
    lo, hi = bounds(objs)
    transform_all(objs, Matrix.Scale(1.8 / (hi.z - lo.z), 4))
    for o in objs:
        o.name = "skeleton" if o.type == "MESH" else "Skeleton"
    retexture(objs, "skeleton", 512)
    p = Poser(arm)

    def arms(l_down, r_down, l_fwd=0.0, r_fwd=0.0, l_elbow=0.3, r_elbow=0.3):
        """Arms from the T-pose: lowered by `down`, swung forward by `fwd`,
        elbows bent forward by `elbow` (radians)."""
        return {
            "CC_Base_L_Upperarm": [("y", l_down), ("x", -l_fwd)],
            "CC_Base_R_Upperarm": [("y", -r_down), ("x", -r_fwd)],
            "CC_Base_L_Forearm": [("z", -l_elbow)],
            "CC_Base_R_Forearm": [("z", r_elbow)],
        }

    def legs(l_fwd, r_fwd, l_knee, r_knee):
        return {
            "CC_Base_L_Thigh": [("x", -l_fwd)],
            "CC_Base_R_Thigh": [("x", -r_fwd)],
            "CC_Base_L_Calf": [("x", l_knee)],
            "CC_Base_R_Calf": [("x", r_knee)],
        }

    def idle(t):
        # a hunched sway, the head lolling, the jaw working
        pose = arms(1.15 + sin(t) * 0.04, 1.2 + sin(t, 1, 0.3) * 0.04, 0.25, 0.2, 0.45, 0.4)
        pose.update(legs(0.08, -0.04, 0.12, 0.1))
        pose.update({
            "CC_Base_Waist": [("x", 0.12 + sin(t) * 0.03), ("y", sin(t, 1, 0.2) * 0.05)],
            "CC_Base_Spine02": [("x", 0.1)],
            "CC_Base_Head": [("x", -0.15), ("y", sin(t, 1, 0.5) * 0.15), ("z", sin(t, 1, 0.1) * 0.12)],
            "CC_Base_JawRoot": [("x", 0.08 + max(0.0, sin(t, 2)) * 0.12)],
            "CC_Base_Hip": [("loc", Vector((0, 0, -0.02)))],
        })
        return pose

    def walk(t):
        # a stiff, dragging shamble: legs barely lift, arms reach ahead
        a = sin(t)
        pose = arms(1.0, 1.05, 0.6 - a * 0.2, 0.55 + a * 0.2, 0.35, 0.35)
        pose.update(legs(a * 0.38, -a * 0.38, 0.12 + max(0.0, -a) * 0.4, 0.12 + max(0.0, a) * 0.4))
        pose.update({
            "CC_Base_Hip": [("loc", Vector((0, 0, -0.03 + abs(sin(t, 1, 0.25)) * 0.03))), ("z", a * 0.1)],
            "CC_Base_Waist": [("x", 0.2), ("z", -a * 0.12), ("y", sin(t, 1, 0.25) * 0.06)],
            "CC_Base_Head": [("x", -0.15), ("y", -sin(t, 1, 0.25) * 0.08)],
        })
        return pose

    def attack(t):
        # the right arm rises behind the head (0..0.45), whips down across
        # the body at 0.5 (the blow), and holds a moment before recovering
        up = math.sin(min(1.0, t / 0.45) * math.pi / 2) if t < 0.45 else max(0.0, 1 - (t - 0.45) / 0.1)
        strike = 0.0 if t < 0.45 else min(1.0, (t - 0.45) / 0.08) * (1 - max(0.0, t - 0.7) / 0.3)
        pose = arms(1.1, 1.15 - 1.2 * up + 0.2 * strike, 0.3 + 0.3 * up, 0.2 + 1.9 * up + 0.7 * strike,
                    0.5, 0.4 + 0.9 * up - 0.3 * strike)
        pose.update(legs(0.25 * strike, -0.15 * strike, 0.15 + 0.25 * strike, 0.15))
        pose.update({
            "CC_Base_Waist": [("x", 0.1 - 0.2 * up + 0.45 * strike), ("z", 0.25 * up - 0.35 * strike)],
            "CC_Base_Head": [("x", -0.15 - 0.1 * up + 0.2 * strike)],
            "CC_Base_JawRoot": [("x", 0.35 * up)],
            "CC_Base_Hip": [("loc", Vector((0, -0.08 * strike, -0.05 * strike)))],
        })
        return pose

    def hit(t):
        # knocked back at the start, and back to its stance by the end
        k = math.sin(min(1.0, t / 0.2) * math.pi / 2) * (1 - max(0.0, t - 0.2) / 0.8)
        pose = idle(0.0)
        pose.update(arms(1.15 - 0.35 * k, 1.2 - 0.4 * k, 0.25 - 0.3 * k, 0.2 - 0.3 * k, 0.45, 0.4))
        pose.update({
            "CC_Base_Waist": [("x", 0.12 - 0.4 * k), ("z", 0.15 * k)],
            "CC_Base_Spine02": [("x", 0.1 - 0.25 * k)],
            "CC_Base_Head": [("x", -0.15 - 0.4 * k), ("z", -0.2 * k)],
            "CC_Base_JawRoot": [("x", 0.3 * k)],
            "CC_Base_Hip": [("loc", Vector((0, 0.08 * k, -0.02)))],
        })
        return pose

    def death(t):
        # knees give, then it topples backwards and the arms fall loose
        knees = min(1.0, t / 0.3)
        k = max(0.0, min(1.0, (t - 0.15) / 0.45))
        k = k * k * (3 - 2 * k)
        pose = arms(1.15 - 0.9 * k, 1.2 - 1.0 * k, 0.25, 0.2, 0.45 - 0.3 * k, 0.4 - 0.3 * k)
        pose.update(legs(0.5 * knees - 0.2 * k, 0.3 * knees - 0.1 * k, 0.9 * knees - 0.6 * k, 0.7 * knees - 0.5 * k))
        pose.update({
            "CC_Base_Hip": [("x", -1.45 * k), ("loc", Vector((0, 0.35 * k, -0.25 * knees - 0.6 * k)))],
            "CC_Base_Waist": [("x", 0.3 * knees - 0.3 * k)],
            "CC_Base_Head": [("x", -0.3 * k), ("y", 0.5 * k)],
            "CC_Base_JawRoot": [("x", 0.3 * k)],
        })
        return pose

    p.clip("Idle", 60, True, idle)
    p.clip("Walk", 28, True, walk)
    p.clip("Attack", 24, False, attack)
    p.clip("Hit", 10, False, hit, step=1)
    p.clip("Death", 30, False, death)
    export("skeleton.glb")


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
    m = lambda k: "mixamorig_" + k
    # the T-pose was for binding: the arms-down stance becomes the rest pose,
    # so the game's hand and head sockets line up with the body at rest
    # (game/entities/rig.gd, Rig.sockets)
    Poser(arm).pose({
        m("LeftArm"): [("y", 1.3), ("x", -0.05)],
        m("RightArm"): [("y", -1.3), ("x", -0.05)],
        m("LeftForeArm"): [("x", -0.2)],
        m("RightForeArm"): [("x", -0.2)],
    })
    bpy.context.view_layer.update()
    for o in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier="Armature")
        o.modifiers.new("Armature", "ARMATURE").object = arm
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    p = Poser(arm)

    # forward is -Y: an X turn of -a swings a limb forward, +a back
    def idle(t):
        return {
            m("Spine1"): [("x", sin(t) * 0.02)],
            m("Head"): [("z", sin(t, 1, 0.25) * 0.08)],
            m("LeftArm"): [("x", sin(t) * 0.03)],
            m("RightArm"): [("x", -sin(t) * 0.03)],
        }

    def gait(stride, bob, lean, arms, knee):
        def keys(t):
            a = sin(t)
            return {
                m("Hips"): [("loc", Vector((0, 0, abs(sin(t, 2)) * bob))), ("z", a * 0.08)],
                m("Spine"): [("x", -lean)],
                m("Spine1"): [("z", -a * 0.12)],
                m("LeftUpLeg"): [("x", -a * stride)],
                m("RightUpLeg"): [("x", a * stride)],
                m("LeftLeg"): [("x", max(0.0, sin(t, 1, 0.25)) * knee)],
                m("RightLeg"): [("x", max(0.0, sin(t, 1, 0.75)) * knee)],
                m("LeftArm"): [("x", a * arms)],
                m("RightArm"): [("x", -a * arms)],
                m("LeftForeArm"): [("x", -arms * 0.8)],
                m("RightForeArm"): [("x", -arms * 0.8)],
            }
        return keys

    def attack(t):
        # the auto attack: a quick raise (it starts ahead of the swing clock,
        # so it costs no time), a whip down across by 0.5 where the blow
        # lands, a held follow-through, then back to rest
        k = lambda wind, blow: key3(t, 0.3, 0.5, wind, blow, snap=0.8)
        return {
            m("Spine1"): [("z", k(0.4, -0.45)), ("x", k(-0.05, 0.2))],
            m("RightArm"): [("x", k(-2.6, -0.5)), ("y", k(0.0, 0.6))],
            m("RightForeArm"): [("x", k(-0.7, -0.05))],
            m("LeftArm"): [("x", k(-0.4, -0.2))],
            m("RightUpLeg"): [("x", k(0.0, 0.25))],
            m("LeftUpLeg"): [("x", k(0.0, -0.3))],
        }

    def cast(t):
        k = math.sin(min(1.0, t / 0.3) * math.pi / 2) * (1 - max(0.0, t - 0.75) / 0.25)
        return {
            m("RightArm"): [("x", -1.3 * k)],
            m("LeftArm"): [("x", -1.3 * k)],
            m("RightForeArm"): [("x", -0.3 * k)],
            m("LeftForeArm"): [("x", -0.3 * k)],
            m("Spine1"): [("x", 0.1 * k)],
        }

    def sit(t):
        # sitting on the ground, hands on the knees
        b = sin(t) * 0.02
        return {
            m("Hips"): [("loc", Vector((0, 0, -0.5)))],
            m("Spine"): [("x", -0.1 + b)],
            m("LeftUpLeg"): [("x", -1.45)],
            m("RightUpLeg"): [("x", -1.35)],
            m("LeftLeg"): [("x", 1.5)],
            m("RightLeg"): [("x", 1.4)],
            m("LeftArm"): [("x", -0.6)],
            m("RightArm"): [("x", -0.6)],
        }

    def death(t):
        # knees give, then down on the back
        k = min(1.0, t / 0.5)
        k = k * k * (3 - 2 * k)
        knee = math.sin(min(1.0, t / 0.25) * math.pi) * (1 - k)
        return {
            m("Hips"): [("x", -1.5 * k), ("loc", Vector((0, 0.15 * k, -0.8 * k - 0.15 * knee)))],
            m("LeftLeg"): [("x", 0.6 * knee)],
            m("RightLeg"): [("x", 0.5 * knee)],
            m("LeftArm"): [("y", 0.9 * k)],
            m("RightArm"): [("y", -0.7 * k)],
            m("Head"): [("x", -0.3 * k)],
        }

    p.clip("Idle", 72, True, idle)
    p.clip("Walk", 24, True, gait(0.5, 0.03, 0.0, 0.4, 0.8))
    p.clip("Run", 16, True, gait(0.85, 0.06, 0.18, 0.7, 1.4))
    p.clip("Attack", 14, False, attack)
    p.clip("Cast", 16, False, cast)
    p.clip("Sit", 48, True, sit)
    p.clip("Death", 24, False, death)
    spell_clips(p, m)
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
        "skeleton": skeleton,
        "male": base_male,
    }
    for k, job in jobs.items():
        if not only or k in only:
            job()
