"""
Renders the male Wanderer beside the concept sheet's front, side and back
views, at the sheet's scale, to trace the model against it:
    blender --background --python assets/blender/compare_humans.py -- <out dir>
Writes <out dir>/compare.png: each view as [sheet | model].

reference/character_sheet.png is Dan's "Shadowfall Human Male - Modular
Character" sheet. VIEWS gives where each view sits on it, in sheet pixels.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_humans as bh  # noqa: E402
import texture_humans as tx  # noqa: E402

SHEET = os.path.join(HERE, "reference", "character_sheet.png")
GROUND = 453.3  # the sheet row the figures stand on
PX_PER_M = 175.8  # the front figure is 320 px from boots to crown, for a 1.82 m man
# view: (left, top, right, bottom) on the sheet, figure axis x on the sheet, camera direction
VIEWS = {
    "front": ((300, 120, 480, 470), 390, Vector((0, 1, 0))),
    "side": ((470, 120, 610, 470), 533, Vector((1, 0, 0))),
    "back": ((595, 120, 755, 470), 675, Vector((0, -1, 0))),
}
# the heads, close up; the axis here is the head's own centre on the sheet
HEADS = {
    "front": ((362, 125, 428, 187), 395.2, Vector((0, 1, 0))),
    "side": ((500, 125, 566, 187), 533, Vector((1, 0, 0))),
    "back": ((646, 125, 712, 187), 678.9, Vector((0, -1, 0))),
}
WANDERER = {"chest": "leather", "legs": "leather", "feet": "leather", "hands": "leather", "waist": "leather",
            "wrists": "leather", "shoulders": "leather", "back": "leather"}
SCALE = 3  # output pixels per sheet pixel


def dress(parts, gear, face="A", hair="Short", beard="Full"):
    shown = {"Face_" + face, "Hair_" + hair, "Beard_" + beard}
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
    for name, info in parts.items():
        info["obj"].hide_render = name in hidden


def stand(arm):
    """The sheet's stance: arms hanging a little away from the body, feet apart."""
    def rot(name, axis, deg):
        pb = arm.pose.bones[name]
        local = pb.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion(local, math.radians(deg))

    rot(bh.bone("Arm", 1), (0, 1, 0), 74)
    rot(bh.bone("Arm", -1), (0, 1, 0), -74)
    rot(bh.bone("ForeArm", 1), (0, 0, 1), -12)
    rot(bh.bone("ForeArm", -1), (0, 0, 1), 12)
    rot(bh.bone("UpLeg", 1), (0, 1, 0), -6)
    rot(bh.bone("UpLeg", -1), (0, 1, 0), 6)
    rot(bh.bone("Foot", 1), (0, 1, 0), 6)
    rot(bh.bone("Foot", -1), (0, 1, 0), -6)


def scene_setup():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.45, 0.47, 0.5, 1)
    bg.inputs["Strength"].default_value = 0.8
    scene.render.film_transparent = True
    scene.world = world
    for name, energy, rot in (("Key", 3.2, (40, 0, -30)), ("Fill", 0.9, (60, 0, 150))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        light.data.energy = energy
        light.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(light)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.type = "ORTHO"
    scene.collection.objects.link(cam)
    scene.camera = cam
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.view_settings.view_transform = "Standard"
    return scene, cam


def read_png(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1]  # top row first


def render_view(scene, cam, view, box, axis, look, scale, out_dir):
    x0, y0, x1, y1 = box
    w, h = (x1 - x0) / PX_PER_M, (y1 - y0) / PX_PER_M
    scene.render.resolution_x = (x1 - x0) * scale
    scene.render.resolution_y = (y1 - y0) * scale
    cam.data.ortho_scale = max(w, h)
    # the camera's centre, relative to the figure's axis, and its height above the ground
    across = ((x0 + x1) / 2 - axis) / PX_PER_M
    up = (GROUND - (y0 + y1) / 2) / PX_PER_M
    right = look.cross(Vector((0, 0, 1)))
    cam.location = -look * 10 + right * across + Vector((0, 0, up))
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    path = os.path.join(out_dir, f"model_{view}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return read_png(path)


def main():
    out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(HERE, "compare")
    os.makedirs(out_dir, exist_ok=True)
    import trace_wanderer
    trace_wanderer.main()  # already standing as the sheet does, with the sheet's skin and hair
    scene, cam = scene_setup()
    sheet = read_png(SHEET)
    for name, views, scale in (("compare", VIEWS, SCALE), ("compare_head", HEADS, 8)):
        strips = []
        for view, (box, axis, look) in views.items():
            x0, y0, x1, y1 = box
            ref = sheet[y0:y1, x0:x1]
            ref = np.repeat(np.repeat(ref, scale, 0), scale, 1)
            model = render_view(scene, cam, f"{name}_{view}", box, axis, look, scale, out_dir)
            gap = np.zeros((ref.shape[0], 12, 4), np.float32)
            gap[..., 3] = 1
            strips += [ref, model[:ref.shape[0], :ref.shape[1]], gap, gap]
        pic = np.concatenate(strips[:-2], 1)
        h, w = pic.shape[:2]
        img = bpy.data.images.new(name, w, h, alpha=True)
        img.pixels.foreach_set(np.ascontiguousarray(pic[::-1]).ravel())
        img.filepath_raw = os.path.join(out_dir, name + ".png")
        img.file_format = "PNG"
        img.save()
        print("compare ->", img.filepath_raw)


if __name__ == "__main__":
    main()
