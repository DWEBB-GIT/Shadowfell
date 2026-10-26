"""
The painted texture for a modular human (build_humans.py calls texture()).

Every part of one body shares one 512x512 diffuse atlas:
  1. unwrap: each part is smart-projected, the right side of the body reuses
     the left side's UVs (so the atlas only holds half of everything), the
     parts seen close up (faces, hair, hands) get more texels, and all the
     islands are packed together.
  2. bake: Cycles bakes the parts' colours, their own ambient occlusion,
     worn edges (a bevel normal against the surface normal), a material
     class, position and normal into float images.
  3. paint: numpy paints each material class from those (cloth weave and
     folds, quilting, leather mottling, chain links, brushed and chipped steel,
     hair strands, eyes, lips) with a soft light from above baked in.

Skin and hair are painted near-white: the game multiplies them by the
character's skin tone and hair colour, so M_Skin and M_Hair stay tintable.
"""
import math

import bpy
import numpy as np
from mathutils import Vector, kdtree

SIZE = 512
MARGIN = 4  # pixels of bleed round each island
# texel density, relative to the body, for the parts seen close up
DENSITY = {"Face": 1.9, "Hair": 1.35, "Beard": 1.35, "Hands": 1.2, "Head": 1.2}

CLOTH = {"linen", "cloth", "cloth_dark", "rag", "robe", "robe_trim", "cloak", "cloak_dark", "cloak_red",
         "gambeson", "trousers", "red_cloth", "shirt", "cape"}
LEATHER = {"leather", "leather_dark", "lips", "boot"}
METAL = {"steel", "steel_dark", "iron", "brass"}
RUSTY = {"iron", "steel_dark"}

_painted = {}  # body key -> finished pixels, so a preview with many humans paints each body once


def _density(name):
    return DENSITY.get(name.split(".")[0].split("_")[0], 1.0)


# ---------------------------------------------------------------- unwrap
def _mirror(me):
    """{face on the right (x < 0): its mirror face on the left}, and each vertex's mirror vertex."""
    kd = kdtree.KDTree(len(me.vertices))
    for v in me.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    vm = []
    for v in me.vertices:
        _, j, d = kd.find(Vector((-v.co.x, v.co.y, v.co.z)))
        vm.append(j if d < 1e-5 else None)
    by_verts = {frozenset(p.vertices): p.index for p in me.polygons}
    pairs = {}
    for p in me.polygons:
        if p.center.x > -1e-5:
            continue
        m = [vm[i] for i in p.vertices]
        if None in m:
            continue
        q = by_verts.get(frozenset(m))
        if q is not None and me.polygons[q].center.x > 1e-5:
            pairs[p.index] = q
    return pairs, vm


def _select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def unwrap(objs):
    _select(objs)
    mirrors = {}
    for o in objs:
        me = o.data
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        mirrors[o] = _mirror(me)
        for p in me.polygons:
            p.select = p.index not in mirrors[o][0]
    bpy.context.tool_settings.use_uv_select_sync = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    islands = []
    for o in objs:
        me = o.data
        uv = me.uv_layers[0].data
        own = [p.index for p in me.polygons if p.index not in mirrors[o][0]]
        islands += _islands(me, uv, own, _density(o.name))
    _pack(islands)
    for o in objs:
        me = o.data
        uv = me.uv_layers[0].data
        pairs, vm = mirrors[o]
        for f, q in pairs.items():
            src = {me.loops[li].vertex_index: uv[li].uv.copy() for li in me.polygons[q].loop_indices}
            for li in me.polygons[f].loop_indices:
                uv[li].uv = src[vm[me.loops[li].vertex_index]]
        for p in me.polygons:
            p.select = True


def _islands(me, uv, faces, density):
    """The UV islands among some faces, each scaled to metres (times its density):
    [(uv data, loop indices, width, height)], with its corner at 0, 0 and lying wide."""
    parent = {f: f for f in faces}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    seen = {}
    for f in faces:
        for li in me.polygons[f].loop_indices:
            key = (me.loops[li].vertex_index, round(uv[li].uv.x, 5), round(uv[li].uv.y, 5))
            g = seen.setdefault(key, f)
            if g != f:
                parent[find(g)] = find(f)
    groups = {}
    for f in faces:
        groups.setdefault(find(f), []).append(f)
    out = []
    for fs in groups.values():
        loops = [li for f in fs for li in me.polygons[f].loop_indices]
        area3 = sum(me.polygons[f].area for f in fs)
        area2 = 0.0
        for f in fs:
            pts = [uv[li].uv for li in me.polygons[f].loop_indices]
            area2 += abs(sum(a.x * b.y - b.x * a.y for a, b in zip(pts, pts[1:] + pts[:1]))) / 2
        k = math.sqrt(area3 / area2) * density if area2 > 1e-12 else 0.0
        xs = [uv[li].uv.x for li in loops]
        ys = [uv[li].uv.y for li in loops]
        x0, y0 = min(xs), min(ys)
        w, h = (max(xs) - x0) * k, (max(ys) - y0) * k
        for li in loops:
            uv[li].uv = Vector(((uv[li].uv.x - x0) * k, (uv[li].uv.y - y0) * k))
        if h > w:
            for li in loops:
                x, y = uv[li].uv
                uv[li].uv = Vector((y, w - x))
            w, h = h, w
        out.append((uv, loops, w, h))
    return out


def _pack(islands):
    """Shelf-packs the islands, tallest first, into the unit square."""
    islands = sorted(islands, key=lambda i: -i[3])
    side = math.sqrt(sum(w * h for _, _, w, h in islands) / .62)
    while True:
        pad = side * MARGIN * 2 / SIZE
        x = y = shelf = 0.0
        spots = []
        for _, _, w, h in islands:
            if x + w + pad > side:
                x, y, shelf = 0.0, y + shelf, 0.0
            spots.append((x + pad, y + pad))
            x += w + pad
            shelf = max(shelf, h + pad)
        if y + shelf + pad <= side:
            break
        side *= 1.03
    for (uv, loops, _, _), (sx, sy) in zip(islands, spots):
        for li in loops:
            uv[li].uv = Vector(((uv[li].uv.x + sx) / side, (uv[li].uv.y + sy) / side))


# ------------------------------------------------------------------ bake
def _bake_material():
    mat = bpy.data.materials.new("Bake")
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    out = N("ShaderNodeOutputMaterial")
    emit = N("ShaderNodeEmission")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    img = N("ShaderNodeTexImage")
    nt.nodes.active = img
    col = N("ShaderNodeAttribute")
    col.attribute_name = "Col"
    cls = N("ShaderNodeAttribute")
    cls.attribute_name = "Cls"
    ao = N("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.only_local = True
    ao.inputs["Distance"].default_value = 0.08
    bev = N("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.008
    geo = N("ShaderNodeNewGeometry")
    dot = N("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    edge = N("ShaderNodeMath")
    edge.operation = "SUBTRACT"
    edge.inputs[0].default_value = 1.0
    nt.links.new(dot.outputs["Value"], edge.inputs[1])
    sep = N("ShaderNodeSeparateColor")
    nt.links.new(cls.outputs["Color"], sep.inputs["Color"])
    data = N("ShaderNodeCombineColor")
    nt.links.new(ao.outputs["AO"], data.inputs[0])
    nt.links.new(edge.outputs["Value"], data.inputs[1])
    nt.links.new(sep.outputs[0], data.inputs[2])
    pos = N("ShaderNodeVectorMath")  # -1..1 m across, 0..2 m up -> 0..1
    pos.operation = "MULTIPLY_ADD"
    nt.links.new(geo.outputs["Position"], pos.inputs[0])
    pos.inputs[1].default_value = (.5, .5, .5)
    pos.inputs[2].default_value = (.5, .5, 0)
    nrm = N("ShaderNodeVectorMath")
    nrm.operation = "MULTIPLY_ADD"
    nt.links.new(geo.outputs["Normal"], nrm.inputs[0])
    nrm.inputs[1].default_value = (.5, .5, .5)
    nrm.inputs[2].default_value = (.5, .5, .5)
    sources = {"col": col.outputs["Color"], "data": data.outputs["Color"], "pos": pos.outputs["Vector"],
               "nrm": nrm.outputs["Vector"]}
    return mat, img, emit, sources


def bake(objs):
    scene = bpy.context.scene
    engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    mat, img_node, emit, sources = _bake_material()
    saved = {o: list(o.data.materials) for o in objs}
    for o in objs:
        for i in range(len(o.data.materials)):
            o.data.materials[i] = mat
    _select(objs)
    out = {}
    for name, socket in sources.items():
        img = bpy.data.images.new(f"bake_{name}", SIZE, SIZE, alpha=False, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        img_node.image = img
        mat.node_tree.links.new(socket, emit.inputs["Color"])
        bpy.ops.object.bake(type="EMIT", margin=MARGIN, margin_type="EXTEND", use_clear=True,
                            target="IMAGE_TEXTURES")
        px = np.empty(SIZE * SIZE * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        out[name] = px.reshape(-1, 4)[:, :3].astype(np.float64)
        bpy.data.images.remove(img)
    for o, mats in saved.items():
        for i, m in enumerate(mats):
            o.data.materials[i] = m
    bpy.data.materials.remove(mat)
    scene.render.engine = engine
    return out


# ----------------------------------------------------------------- noise
def _hash(i, j, k, seed):
    h = (i * 374761393 + j * 668265263 + k * 1274126177 + seed * 974634291) & 0xffffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
    return ((h ^ (h >> 16)) & 0xffff) / 65535.0


def noise(p, scale, seed=0):
    """Smooth value noise in 0..1 at points p (N x 3); scale is cells per metre (per axis)."""
    q = p * np.asarray(scale, dtype=np.float64)
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)
    out = np.zeros(len(p))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = ((f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1])
                     * (f[:, 2] if dz else 1 - f[:, 2]))
                out += w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, scale, seed=0, octaves=3):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * noise(p, np.asarray(scale, dtype=np.float64) * 2 ** o, seed + o * 31)
        norm += amp
        amp *= .5
    return total / norm


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def gauss(x, m, w):
    return np.exp(-((x - m) / w) ** 2)


# ----------------------------------------------------------------- paint
def paint(D, keys, feat):
    """Paints the atlas (linear RGB, SIZE*SIZE x 3) from the baked maps.
    feat: eye_z, mouth_z, male (face features are at the same place on every face)."""
    cid_all = np.rint(D["data"][:, 2] * 64).astype(int) - 1
    m = cid_all >= 0
    out_all = np.full((SIZE * SIZE, 3), .05)
    cid = cid_all[m]
    c = D["col"][m]
    ao = np.clip(D["data"][m, 0], 0, 1)
    edge = np.clip(D["data"][m, 1] * 5, 0, 1) * smooth(.7, .95, ao)  # convex edges only
    p = D["pos"][m] * 2 - np.array([1.0, 1.0, 0.0])
    p[:, 0] = np.abs(p[:, 0])  # mirrored halves share texels
    n = D["nrm"][m] * 2 - 1
    out = c.copy()

    def group(names):
        return np.isin(cid, [keys.index(k) for k in names if k in keys])

    def where(names):
        s = group(names)
        return s, p[s]

    # cloth: fine weave, long hanging folds, dirt towards the hem, frayed edges
    s, q = where(CLOTH)
    if s.any():
        weave = .92 + .08 * noise(q, 240, 2)
        folds = .82 + .32 * fbm(q, (12, 12, 4), 3)
        dirt = .72 + .28 * smooth(.05, .6, q[:, 2])
        x = c[s] * (weave * folds * dirt)[:, None]
        out[s] = x * (1 + .35 * edge[s, None])
    s, q = where({"gambeson"})
    if s.any():  # diamond quilting
        a = np.abs(np.mod((q[:, 2] + q[:, 0] + q[:, 1] * .5) * 16, 1) - .5)
        b = np.abs(np.mod((q[:, 2] - q[:, 0] - q[:, 1] * .5) * 16, 1) - .5)
        out[s] *= (1 - .35 * smooth(.38, .5, np.maximum(a, b)))[:, None]
    # leather: mottled, scuffed lighter, worn pale at the edges
    s, q = where(LEATHER)
    if s.any():
        mott = .75 + .45 * fbm(q, 20, 9)
        grain = .93 + .08 * noise(q, 220, 10)
        x = c[s] * (mott * grain)[:, None]
        scuff = smooth(.55, .8, fbm(q, 7, 11))[:, None] * .5
        x = x * (1 - scuff) + (x * 1.6 + .01) * scuff
        out[s] = x + (x * 1.4 + .02) * edge[s, None] * .9
    s, q = where({"fur"})
    if s.any():
        out[s] = c[s] * (.55 + .8 * fbm(q, (70, 70, 9), 12))[:, None]
    # mail: offset rows of rings
    s, q = where({"mail"})
    if s.any():
        P = .016
        row = np.floor(q[:, 2] / P)
        u = np.mod((q[:, 0] + q[:, 1]) / P + .5 * np.mod(row, 2), 1) - .5
        v = np.mod(q[:, 2] / P, 1) - .5
        ring = np.clip(1 - np.abs(np.sqrt(u * u + v * v) - .3) * 6, 0, 1)
        x = c[s] * (.35 + .9 * ring)[:, None] * (.85 + .3 * fbm(q, 10, 13))[:, None]
        out[s] = x * (.4 + .6 * ao[s])[:, None] + (x + .06) * edge[s, None] * .6
    # metal: brushed, dirty in the hollows, rust on iron, scratched, chipped bright at the edges
    s, q = where(METAL)
    if s.any():
        brushed = .9 + .14 * noise(q, (90, 90, 7), 5)
        dirt = .78 + .3 * fbm(q, 12, 6)
        x = c[s] * (brushed * dirt * (.35 + .65 * ao[s] ** 1.5))[:, None]
        scratch = smooth(.8, .9, noise(q, (150, 150, 22), 7)) * .5
        x = x + (x * .8 + .04) * scratch[:, None]
        rust = smooth(.55, .78, fbm(q, 18, 8)) * (1.2 - ao[s]) * group(RUSTY)[s]
        x = x * (1 - rust[:, None] * .7) + np.array([.10, .035, .012]) * rust[:, None] * .7
        out[s] = x + (x * .9 + .05) * edge[s, None]
    # skin (tinted in game): blotches, warmer cheeks, nose and knuckles; eye shadows, lips, stubble
    s, q = where({"skin"})
    if s.any():
        x = np.tile([.96, .93, .92], (len(q), 1)) * (.94 + .1 * fbm(q, 28, 14))[:, None]
        ez, mz = feat["eye_z"], feat["mouth_z"]
        head = (q[:, 2] > mz - .08) * (q[:, 1] < .02)
        warm = (gauss(q[:, 0], .048, .02) * gauss(q[:, 2], ez - .03, .02)
                + gauss(q[:, 0], 0, .012) * gauss(q[:, 2], (ez + mz) / 2 - .004, .012)) * head
        x *= (1 - np.outer(np.clip(warm, 0, 1), [0, .12, .14]))
        sockets = gauss(q[:, 0], .033, .016) * gauss(q[:, 2], ez + .004, .012) * head
        x *= (1 - .18 * sockets)[:, None]
        lips = (gauss(q[:, 0], 0, .015) * gauss(q[:, 2], mz - .002, .0055) * head) ** .7
        x *= (1 - np.outer(np.clip(lips, 0, 1), [.12, .34, .36]))
        line = gauss(q[:, 0], 0, .013) * gauss(q[:, 2], mz - .0015, .0012) * head
        x *= (1 - .55 * np.clip(line, 0, 1))[:, None]
        if feat["male"]:
            jaw = smooth(mz - .006, mz - .016, q[:, 2]) * smooth(mz - .075, mz - .06, q[:, 2]) * head
            jaw *= (.7 + .5 * noise(q, 300, 15))
            x *= (1 - np.outer(np.clip(jaw, 0, 1), [.16, .14, .1]))
        out[s] = x
    # hair (tinted in game): strands running from the crown, a sheen band
    s, q = where({"hair"})
    if s.any():
        d = q - np.array([0, .01, feat["eye_z"] - .02])
        phi = np.arctan2(d[:, 1], d[:, 0])
        pol = np.arctan2(np.hypot(d[:, 0], d[:, 1]), d[:, 2])
        uv = np.stack([phi * 26, pol * 3, np.zeros(len(q))], 1)
        strands = .5 + .65 * fbm(uv, 1.0, 16)
        fine = .85 + .2 * noise(np.stack([phi * 90, pol * 8, np.zeros(len(q))], 1), 1.0, 17)
        x = .9 * strands * fine + .16 * gauss(pol, .85, .22)
        out[s] = np.repeat(x[:, None], 3, 1)
    # eyes: sclera, iris and pupil, a dark lash line
    s, q = where({"eye"})
    if s.any():
        dx, dz = q[:, 0] - .033, q[:, 2] - feat["eye_z"]
        r = np.hypot(dx, dz)
        x = np.tile([.55, .52, .46], (len(q), 1))
        x = np.where((r < .0056)[:, None], [.12, .07, .035], x)
        x = np.where((r < .0026)[:, None], [.01, .01, .01], x)
        x = np.where((dz > .0035)[:, None], [.02, .015, .015], x)
        out[s] = x
        ao[s] = 1.0
    # a soft light from above and the occlusion, with a painterly wobble over everything
    light = .84 + .16 * n[:, 2]
    occl = .5 + .5 * ao
    brush = .95 + .1 * fbm(p, 9, 1)
    out_all[m] = out * (light * occl * brush)[:, None]
    return out_all


def _srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= .0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - .055)


# ------------------------------------------------------------- materials
def _diffuse_node(mat):
    return mat.node_tree.nodes.get("Diffuse")


def apply(mats, img):
    """Sets M_Base, M_Skin and M_Hair to the painted texture (and nothing else, for glTF)."""
    for mat in mats:
        try:
            mat.use_nodes = True
        except Exception:
            pass
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        for nd in list(nt.nodes):
            if nd.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
                nt.nodes.remove(nd)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.name = "Diffuse"
        tex.image = img
        tex.location = (-400, 200)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.95
        for key in ("Specular IOR Level", "Specular"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = 0.0
                break


def tint(mat, colour, copy=True):
    """M_Skin or M_Hair multiplied by a colour, as the game tints them."""
    if copy:
        mat = mat.copy()
    nt = mat.node_tree
    tex = _diffuse_node(mat)
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    mul = nt.nodes.new("ShaderNodeMix")
    mul.name = "Tint"
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.location = (-180, 200)
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mul.inputs["A"])
    mul.inputs["B"].default_value = colour
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def texture(objs, mats, key, keys, feat):
    """Unwraps, bakes and paints one body's parts; returns the diffuse image."""
    unwrap(objs)
    if key not in _painted:
        D = bake(objs)
        _painted[key] = _srgb(paint(D, keys, feat))
    rgb = _painted[key]
    img = bpy.data.images.new(f"human_{key}_diffuse", SIZE, SIZE, alpha=False)
    px = np.ones((SIZE * SIZE, 4), dtype=np.float32)
    px[:, :3] = rgb
    img.pixels.foreach_set(px.ravel())
    apply(mats, img)
    return img
