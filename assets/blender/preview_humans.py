"""
Renders a posed line-up of the modular humans, to check shapes and skinning:
    blender --background --python assets/blender/build_humans.py -- --preview <dir>
"""
import math
import os

import bpy
from mathutils import Quaternion, Vector

import build_humans as bh
import texture_humans as tx

# (body, face, hair, beard, {slot: armour type}, skin, hair colour)
LINEUP = [
    ("male", "A", "Short", None, {}, (0.80, 0.60, 0.48, 1), (0.16, 0.11, 0.07, 1)),
    ("female", "A", "Long", None, {}, (0.55, 0.38, 0.26, 1), (0.08, 0.06, 0.05, 1)),
    ("male", "C", "Cropped", "Full", {"chest": "cloth", "legs": "cloth", "feet": "cloth", "waist": "cloth",
                                      "head": "cloth"}, (0.66, 0.50, 0.40, 1), (0.40, 0.36, 0.32, 1)),
    ("male", "C", "Short", "Full", {"chest": "leather", "legs": "leather", "feet": "leather", "hands": "leather",
                                    "waist": "leather", "wrists": "leather", "shoulders": "leather"},
     (0.72, 0.52, 0.40, 1), (0.22, 0.13, 0.08, 1)),
    ("female", "B", "Ponytail", None, {"chest": "leather", "legs": "leather", "feet": "leather", "hands": "leather",
                                       "waist": "leather", "wrists": "leather", "back": "leather"},
     (0.86, 0.68, 0.56, 1), (0.45, 0.20, 0.08, 1)),
    ("male", "B", "Short", "Moustache", {"chest": "mail", "legs": "mail", "feet": "mail", "hands": "mail",
                                         "head": "mail", "shoulders": "mail", "waist": "mail", "back": "mail"},
     (0.42, 0.28, 0.19, 1), (0.05, 0.04, 0.04, 1)),
    ("female", "C", "Bun", None, {"chest": "plate", "legs": "plate", "feet": "plate", "hands": "plate",
                                  "shoulders": "plate", "waist": "plate", "wrists": "plate"},
     (0.74, 0.56, 0.44, 1), (0.60, 0.50, 0.30, 1)),
    ("male", "A", "Short", "Short", {"chest": "plate", "legs": "plate", "feet": "plate", "hands": "plate",
                                     "head": "plate", "shoulders": "plate", "waist": "plate", "back": "plate"},
     (0.80, 0.60, 0.48, 1), (0.16, 0.11, 0.07, 1)),
]


def pose(arm, phase):
    """A mid-stride pose with the arms down, to show off the joints."""
    def rot(name, axis, deg):
        pb = arm.pose.bones[name]
        local = pb.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion(local, math.radians(deg))

    s = 1 if phase % 2 == 0 else -1
    rot(bh.bone("Arm", 1), (0, 1, 0), 68)
    rot(bh.bone("Arm", -1), (0, 1, 0), -68)
    rot(bh.bone("ForeArm", 1), (0, 0, 1), -35)
    rot(bh.bone("ForeArm", -1), (0, 0, 1), 35)
    rot(bh.bone("UpLeg", 1), (1, 0, 0), -22 * s)
    rot(bh.bone("UpLeg", -1), (1, 0, 0), 18 * s)
    rot(bh.bone("Leg", -1 if s > 0 else 1), (1, 0, 0), 25)
    rot(bh.bone("Spine1"), (0, 0, 1), 8 * s)
    rot(bh.bone("Head"), (0, 0, 1), -10 * s)


def render(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for n, (key, face, hair, beard, gear, skin, hair_c) in enumerate(LINEUP):
        arm, parts = bh.build_human(key)
        # later humans in the scene get ".001" names; key them by the plain name
        parts = {name.split(".")[0]: info for name, info in parts.items()}
        shown = {"Face_" + face, "Hair_" + hair}
        if beard:
            shown.add("Beard_" + beard)
        hidden = set()
        for name, info in parts.items():
            if info["slot"] in ("face", "hair", "beard") and name not in shown:
                hidden.add(name)
            if info["slot"] not in ("body", "face", "hair", "beard") and gear.get(info["slot"]) != info["variant"]:
                hidden.add(name)
        for name, info in parts.items():
            if name not in hidden and info["slot"] not in ("body", "face", "hair", "beard"):
                hidden.update(info["hides"])
                hidden.update(p for p in parts if parts[p]["slot"] in ("face", "hair", "beard")
                              and parts[p]["slot"].title() in info["hides"])
        skin_m = tx.tint(bh.MATSET[1], skin)
        hair_m = tx.tint(bh.MATSET[2], hair_c)
        for name, info in parts.items():
            obj = info["obj"]
            obj.hide_render = name in hidden
            obj.data.materials[1] = skin_m
            obj.data.materials[2] = hair_m
        arm.location.x = (n - (len(LINEUP) - 1) / 2) * 0.85
        arm.rotation_euler.z = math.radians(-20)
        pose(arm, n)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.22, 0.23, 0.26, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scene.collection.objects.link(sun)

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 7.6
    scene.collection.objects.link(cam)
    scene.camera = cam
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 2100
    scene.render.resolution_y = 760
    scene.view_settings.view_transform = "Standard"

    for label, loc, rot in (("front", (0, -12, 3.0), (80, 0, 0)), ("back", (0, 12, 3.0), (80, 0, 180))):
        cam.location = loc
        cam.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.render.filepath = os.path.join(out_dir, f"humans_{label}.png")
        bpy.ops.render.render(write_still=True)
        print("preview ->", scene.render.filepath)

    # close-ups of the heads, three-quarter on
    scene.render.resolution_x = scene.render.resolution_y = 520
    cam.data.ortho_scale = .62
    for n in range(len(LINEUP)):
        x = (n - (len(LINEUP) - 1) / 2) * 0.85
        cam.location = (x - 4.6, -11.1, 1.66)
        cam.rotation_euler = (math.radians(90), 0, math.radians(-22.5))
        scene.render.filepath = os.path.join(out_dir, f"head_{n}.png")
        bpy.ops.render.render(write_still=True)
