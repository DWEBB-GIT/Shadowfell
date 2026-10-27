"""
The male base body, modelled fresh from Dan's "Shadowfall Human Male" concept
sheet (reference/character_sheet.png): chunky faceted low-poly shapes, heroic
proportions, skin, plain linen underwear and a short haircut and full beard,
in a T-pose for Mixamo's auto-rigger. No gear.
    blender --background --python assets/blender/base_male.py -- [--compare <dir>]
Writes base_male.blend, base_male_diffuse.png (one 512 hand-painted diffuse)
and base_male_mixamo.fbx next to this script. --compare also renders the body
and face beside the sheet into <dir>.

Every shape is a loft of cross-section rings (a squared-off ellipse per ring),
shaded flat so each facet reads as a painted plane, as on the sheet. The
character faces -Y with Z up, 1.82 m to the crown of the skull.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import texture_humans as tx  # noqa: E402  (the Cycles bake and noise)

SIZE = tx.SIZE


def g(v, m, w):
    return math.exp(-((v - m) / w) ** 2)


def sstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def squircle(t, p):
    """(sin, cos) of angle t pushed toward a square; p=2 is an ellipse."""
    s, c = math.sin(t), math.cos(t)
    return math.copysign(abs(s) ** (2 / p), s), math.copysign(abs(c) ** (2 / p), c)


def lerp_rows(rows, z):
    """Linear interpolation of table rows keyed on their first column."""
    if z <= rows[0][0]:
        return rows[0][1:]
    for a, b in zip(rows, rows[1:]):
        if z <= b[0]:
            f = (z - a[0]) / (b[0] - a[0])
            return tuple(u + (v - u) * f for u, v in zip(a[1:], b[1:]))
    return rows[-1][1:]


# ------------------------------------------------------------------ bmesh
def loft(bm, rings, start=None, end=None, closed=True):
    """Quads between rings of equal length; start/end are fan-cap centres (or None).
    Open rings (closed=False) are half rings, from the middle of the body round to its back."""
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    span = range(n) if closed else range(n - 1)
    for a, b in zip(vs, vs[1:]):
        for j in span:
            bm.faces.new((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]))
    for ring, c in ((vs[0], start), (vs[-1], end)):
        if c is not None:
            cv = bm.verts.new(c)
            for j in span:
                bm.faces.new((ring[j], ring[(j + 1) % n], cv))
    return vs


def make_object(name, build, cls, outward=None):
    """Builds the left half (+X) of a part; the right half is mirrored after unwrapping,
    so both halves share texels."""
    bm = bmesh.new()
    build(bm)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # half shells: point the faces away from this centre (or the part's own)
    c = Vector(outward) if outward else sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    if sum((f.calc_center_median() - c).dot(f.normal) * f.calc_area() for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    attr = me.color_attributes.new("Cls", "FLOAT_COLOR", "POINT")
    for d in attr.data:
        d.color = (cls / 10, 0, 0, 1)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ------------------------------------------------------------------- head
HEAD_Z = 1.578  # bottom of the chin
# z above the chin, half width, front, back, centre y, squareness
HEAD = [
    (0.000, .036, .028, .016, -.062, 2.2),
    (0.018, .057, .040, .030, -.050, 2.6),
    (0.040, .072, .072, .050, -.018, 3.0),
    (0.058, .075, .090, .080, .000, 3.0),
    (0.078, .079, .095, .100, .000, 2.8),
    (0.098, .082, .095, .106, .000, 2.7),
    (0.118, .083, .093, .110, .000, 2.6),
    (0.138, .083, .100, .112, .000, 2.6),
    (0.162, .081, .097, .112, .000, 2.5),
    (0.188, .075, .089, .106, .000, 2.4),
    (0.212, .062, .073, .092, .000, 2.3),
    (0.230, .036, .046, .060, .000, 2.2),
]
CROWN = .238
# ring angles, denser across the face: columns land on the nose, eyes and cheekbones
HEAD_ANGLES = [math.radians(a) for a in (0, 16, 34, 55, 80, 105, 130, 155, 180)]
HALF = [i / 8 * math.pi for i in range(9)]  # half rings for the torso
RING10 = [i / 10 * math.tau for i in range(10)]  # whole rings for limbs
EYE_Z, EYE_X = .118, .036


def face_dy(x, z):
    """How far the face surface moves forward (-) or back (+) for its features."""
    ax = abs(x)
    dy = 0.0
    dy -= .004 * g(z, .138, .011) * (1 - sstep(.05, .07, ax))  # brow ridge
    dy += .003 * g(z, EYE_Z, .011) * g(ax, EYE_X, .016)  # eye sockets
    dy -= .004 * g(z, .122, .014) * g(x, 0, .012)  # bridge of the nose
    dy -= .007 * g(z, .098, .013) * g(ax, .054, .014)  # cheekbones
    dy -= .006 * g(z, .074, .010) * g(x, 0, .026)  # moustache
    dy += .003 * g(z, .058, .006) * g(x, 0, .02)  # mouth
    dy -= .011 * g(z, .022, .016) * g(x, 0, .032)  # chin and beard
    return dy


def head_point(t, z, features=True):
    W, F, B, cy, p = lerp_rows(HEAD, z)
    s, c = squircle(t, p)
    x = W * s
    y = cy - (F if c > 0 else B) * c
    if features and c > 0:
        y += face_dy(x, z) * sstep(.25, .7, c)
    return x, y, HEAD_Z + z


def build_head(bm):
    rings = [[head_point(t, row[0]) for t in HEAD_ANGLES] for row in HEAD]
    loft(bm, rings, start=(0, -.05, HEAD_Z + .004), end=(0, .006, HEAD_Z + CROWN), closed=False)


def build_nose(bm):
    """A straight, broad wedge: bridge, flat-fronted tip, wings and the plane under it."""
    z = HEAD_Z
    v = {k: bm.verts.new(p) for k, p in dict(
        B=(0, -.101, z + .128), U=(.011, -.098, z + .114), R=(0, -.115, z + .108),
        T=(0, -.127, z + .084), S=(.013, -.118, z + .081), W=(.023, -.099, z + .076),
        C=(0, -.107, z + .071), K=(0, -.086, z + .098)).items()}
    for f in ("B U R", "R U S", "R S T", "U W S", "S W C", "S C T", "B K U", "U K W", "W K C"):
        bm.faces.new([v[k] for k in f.split()])


def build_ears(bm):
    z = HEAD_Z
    base = [(.077, .000, z + .130), (.077, .024, z + .128), (.077, .032, z + .104), (.076, .020, z + .082),
            (.076, .003, z + .088)]
    rim = [(.092, .000, z + .138), (.099, .034, z + .138), (.104, .052, z + .108), (.096, .036, z + .076),
           (.088, .008, z + .078)]
    loft(bm, [base, rim], end=(.092, .022, z + .106))


HAIRLINE = [  # ring angle (deg) -> where the hair starts, above the chin
    (0, .178), (16, .180), (34, .174), (55, .160), (80, .140), (105, .118), (130, .076), (155, .060), (180, .058)]


def hair_point(t, s, out=1.0, clump=0.0):
    deg = math.degrees(t)
    zb = lerp_rows(HAIRLINE, deg)[0]
    z = zb + (.232 - zb) * s
    x, y, zz = head_point(t, z, features=False)
    cy = lerp_rows(HEAD, z)[3]
    front = max(math.cos(t), 0)
    side = 1 - .7 * g(deg, 92, 30)  # short at the sides
    thick = ((.020 * s ** .7) * side + clump) * out
    d = Vector((x, y - cy, (z - .11) * 1.1)).normalized()
    p = Vector((x, y, zz)) + d * thick
    p.y -= .012 * front * g(s, .55, .3) * out  # swept up and back off the forehead
    p.z += .008 * front * g(s, .6, .3) * out + clump * .6
    return tuple(p)


def build_hair(bm):
    rings = [[hair_point(t, 0, -.25) for t in HEAD_ANGLES]]
    for k, s in enumerate((0, .3, .6, .85)):  # chunky locks: alternate columns stand proud
        ring = []
        for i, t in enumerate(HEAD_ANGLES):
            q = hair_point(t, s, clump=.0045 * ((i + k) % 2) * (0 < i < 8))
            if k == 0 and i in (1, 3):  # locks pointing down onto the forehead
                q = (q[0], q[1] - .004, q[2] - .012)
            ring.append(q)
        rings.append(ring)
    loft(bm, rings, end=(0, .008, HEAD_Z + .256), closed=False)


def build_neck(bm):
    rows = [(1.50, .088, .070, .082, .016), (1.57, .076, .062, .070, .016), (1.64, .066, .054, .062, .010)]
    rings = []
    for z, W, F, B, cy in rows:
        ring = []
        for t in HEAD_ANGLES[::2]:
            s, c = squircle(t, 2.2)
            ring.append((W * s, cy - (F if c > 0 else B) * c, z))
        rings.append(ring)
    loft(bm, rings, start=(0, .016, 1.47), end=(0, .01, 1.64), closed=False)


# ------------------------------------------------------------------- body
TORSO = [  # z, half width, front, back, centre y, squareness
    (0.860, .125, .085, .090, .005, 2.4),
    (0.920, .172, .100, .115, .010, 2.6),
    (1.000, .172, .100, .108, .006, 2.6),
    (1.080, .158, .100, .094, .004, 2.6),
    (1.170, .168, .106, .096, .002, 2.6),
    (1.260, .188, .118, .102, .000, 2.8),
    (1.340, .204, .124, .104, .000, 3.0),
    (1.410, .212, .112, .104, .004, 3.2),
    (1.470, .190, .082, .092, .010, 3.0),
    (1.545, .125, .070, .080, .014, 2.4),
]


def torso_dy(x, z, front):
    ax = abs(x)
    if front:
        return (-.014 * g(z, 1.335, .045) * g(ax, .09, .05)  # pecs
                - .005 * g(z, 1.15, .06) * g(x, 0, .05))  # belly
    return (.010 * g(z, 1.37, .06) * g(ax, .09, .04)  # shoulder blades
            + .015 * g(z, .93, .05) * g(ax, .08, .05))  # seat


def build_torso(bm):
    rings = []
    for z, W, F, B, cy, p in TORSO:
        ring = []
        for t in HALF:
            s, c = squircle(t, p)
            x = W * s
            y = cy - (F if c > 0 else B) * c
            y += torso_dy(x, z, c > 0) * abs(c)
            ring.append((x, y, z))
        rings.append(ring)
    loft(bm, rings, start=(0, .005, .85), end=(0, .016, 1.56), closed=False)


SHOULDER = (.19, 0.0, 1.43)  # where the arm pivots, for posing
ARM = [  # x, centre z, half height above, below, front, back
    (.130, 1.432, .088, .082, .082, .082),
    (.200, 1.436, .092, .078, .082, .082),
    (.260, 1.430, .078, .068, .074, .070),
    (.320, 1.426, .066, .062, .074, .066),
    (.390, 1.425, .060, .057, .066, .062),
    (.450, 1.425, .050, .050, .053, .055),
    (.510, 1.425, .056, .055, .062, .060),
    (.590, 1.424, .050, .048, .055, .053),
    (.680, 1.422, .037, .034, .047, .045),
    (.745, 1.420, .028, .028, .042, .040),
]


def build_arms(bm):
    rings = []
    for x, cz, up, down, F, B in ARM:
        ring = []
        for t in RING10:
            s, c = squircle(t, 2.4)
            ring.append((x, -(F if s > 0 else B) * s, cz + (up if c > 0 else down) * c))
        rings.append(ring)
    loft(bm, rings, start=(.12, 0, 1.43), end=(.75, 0, 1.42))


def box_ring(c, u, v, hu, hv):
    c, u, v = Vector(c), Vector(u), Vector(v)
    return [tuple(c + u * a * hu + v * b * hv) for a, b in ((1, 1), (-1, 1), (-1, -1), (1, -1))]


def build_hands(bm):
    palm = []
    for x, w, h in ((.740, .042, .021), (.800, .054, .022), (.855, .054, .017)):
        ring = []
        for i in range(8):
            s, c = squircle(i / 8 * math.tau + math.pi / 8, 4)
            ring.append((x, w * s, 1.419 + h * c))
        palm.append(ring)
    loft(bm, palm, (.735, 0, 1.419), (.86, 0, 1.418))
    Y, Z = (0, 1, 0), (0, 0, 1)
    for y, length in ((-.040, .092), (-.0135, .100), (.0135, .094), (.039, .076)):  # index to little finger
        x0 = .842
        rings = [box_ring((x0 + length * f, y, 1.418 - .008 * f * f), Y, Z, .0125, .011 - .0025 * f)
                 for f in (0, .5, 1)]
        loft(bm, rings, None, (x0 + length + .008, y, 1.408))
    d = Vector((.55, -.8, -.25)).normalized()
    u = d.cross(Vector(Z)).normalized()
    v = u.cross(d)
    base = Vector((.770, -.040, 1.414))
    rings = [box_ring(base + d * f, u, v, .014 - .003 * f / .08, .012) for f in (0, .04, .08)]
    loft(bm, rings, None, tuple(base + d * .089))


LEG = [  # z, centre x, half width outside, inside, front, back
    (.950, .088, .104, .090, .102, .112),
    (.860, .096, .102, .086, .100, .106),
    (.740, .101, .090, .075, .090, .092),
    (.600, .103, .070, .062, .072, .068),
    (.500, .104, .061, .055, .064, .058),
    (.420, .105, .064, .056, .062, .074),
    (.320, .106, .060, .052, .058, .072),
    (.200, .107, .047, .043, .047, .051),
    (.100, .108, .040, .038, .042, .044),
    (.070, .108, .038, .036, .040, .042),
]


def build_legs(bm):
    rings = []
    for z, cx, wo, wi, F, B in LEG:
        ring = []
        for t in RING10:
            s, c = squircle(t, 2.4)
            ring.append((cx + (wo if s > 0 else wi) * s, -(F if c > 0 else B) * c, z))
        rings.append(ring)
    loft(bm, rings, start=(.09, 0, .96), end=(.108, 0, .06))


FOOT = [(.065, .034, .080), (.030, .046, .105), (-.045, .053, .088), (-.115, .056, .058),
        (-.170, .052, .042), (-.205, .040, .032)]  # y, half width, height


def build_feet(bm):
    cx = .110
    rings = []
    for y, w, h in FOOT:
        rings.append([(cx - w, y, 0), (cx + w, y, 0), (cx + w, y, .55 * h), (cx + .55 * w, y, h),
                      (cx - .55 * w, y, h), (cx - w, y, .55 * h)])
    loft(bm, rings, start=(cx, .072, .035), end=(cx, -.214, .015))


# 1 body skin, 2 head skin, 3 hair, 4 nose, 5 ears; the UV quadrant each part is packed into
PARTS = [
    ("Head", build_head, 2, (.5, .5)),
    ("Nose", build_nose, 4, (.5, .5)),
    ("Ears", build_ears, 5, (.5, .5)),
    ("Hair", build_hair, 3, (.5, .5)),
    ("Neck", build_neck, 2, (0, .5)),
    ("Torso", build_torso, 1, (0, .5)),
    ("Arms", build_arms, 1, (.5, 0)),
    ("Hands", build_hands, 1, (.5, 0)),
    ("Legs", build_legs, 1, (0, 0)),
    ("Feet", build_feet, 1, (0, 0)),
]


# -------------------------------------------------------------------- UVs
def unwrap(objs, corner):
    tx._select(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=.012)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        uv = o.data.uv_layers.active.data
        a = np.empty(len(uv) * 2, np.float32)
        uv.foreach_get("uv", a)
        a = a.reshape(-1, 2) * .49 + np.array(corner) + .005
        uv.foreach_set("uv", a.ravel())


# ------------------------------------------------------------------ paint
SHEET = os.path.join(HERE, "reference", "character_sheet.png")
# the portrait close-up (a three-quarter view from his right): points on the head and
# where the sheet painted them, in sheet pixels
PORTRAIT_BOX = (1150, 618, 1315, 800)
LANDMARKS = [
    ((-.0362, -.087, .118), (1253, 698)),  # right eye
    ((.0362, -.087, .118), (1284, 699)),  # left eye
    ((-.052, -.079, .119), (1241, 697)),  # right eye, outer corner
    ((0, -.127, .084), (1288, 724)),  # tip of the nose
    ((0, -.099, .057), (1283.6, 744.4)),  # middle of the mouth
    ((-.097, .022, .106), (1187, 712)),  # right ear
    ((-.097, .030, .133), (1185, 691)),  # top of the ear
    ((-.091, .018, .080), (1196, 733)),  # ear lobe
]


def read_png(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1, :, :3].astype(np.float64)  # top row first


def portrait(col, p, n, cls):
    """Projects the sheet's portrait onto the head. The portrait sees his right side;
    the head's texels are shared by both sides, so each is looked up on the right."""
    src = np.array([(x, y, z + HEAD_Z, 1) for (x, y, z), _ in LANDMARKS])
    dst = np.array([uv for _, uv in LANDMARKS], np.float64)
    A, *_ = np.linalg.lstsq(src, dst, rcond=None)  # an affine camera, 4 x 2
    print("portrait fit, px off:", np.round(np.linalg.norm(src @ A - dst, axis=1), 1))
    view = np.cross(A[:3, 0], A[:3, 1])
    view /= np.linalg.norm(view)
    if view @ [-.5, -.85, 0] < 0:
        view = -view
    q = p.copy()
    q[:, 0] = -np.abs(q[:, 0])
    nq = n.copy()
    nq[:, 0] = np.where(p[:, 0] > 0, -n[:, 0], n[:, 0])
    uv = np.c_[q, np.ones(len(q))] @ A
    x0, y0, x1, y1 = PORTRAIT_BOX
    inside = (uv[:, 0] > x0 + 1) & (uv[:, 0] < x1 - 2) & (uv[:, 1] > y0 + 1) & (uv[:, 1] < y1 - 2)
    head = np.isin(cls, (2, 3, 4, 5)) & (p[:, 2] > HEAD_Z - .004)
    w = tx.smooth(.12, .4, nq @ view) * inside * head * tx.smooth(HEAD_Z, HEAD_Z + .014, p[:, 2])
    sheet = read_png(SHEET)
    u, v = np.clip(uv[:, 0], 0, sheet.shape[1] - 2), np.clip(uv[:, 1], 0, sheet.shape[0] - 2)
    iu, iv = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = (u - iu)[:, None], (v - iv)[:, None]
    s = (sheet[iv, iu] * (1 - fu) * (1 - fv) + sheet[iv, iu + 1] * fu * (1 - fv)
         + sheet[iv + 1, iu] * (1 - fu) * fv + sheet[iv + 1, iu + 1] * fu * fv)
    w = w * tx.smooth(y0, y0 + 6, uv[:, 1])  # the panel's top edge cuts through his hair
    w = w * (1 - tx.smooth(.0, .03, s[:, 2] - s[:, 0]) * tx.smooth(.25, .15, s.max(1)))  # the dark backdrop
    return blend(col, s, w)


def ramp(stops, t):
    """Colour along stops [(t, (r, g, b)), ...] for each value of t."""
    ts = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops], np.float64) / 255
    return np.stack([np.interp(t, ts, cs[:, k]) for k in range(3)], 1)


def blend(base, colour, m):
    m = np.clip(m, 0, 1)[:, None]
    return base * (1 - m) + colour * m


SKIN = [(0, (70, 34, 24)), (.35, (128, 70, 48)), (.62, (184, 112, 78)), (.85, (214, 146, 104)), (1, (232, 176, 132))]
HAIR = [(0, (38, 26, 22)), (.4, (62, 43, 34)), (.75, (92, 66, 52)), (1, (124, 92, 72))]  # the portrait's
BEARD = [(0, (30, 19, 13)), (.45, (62, 40, 28)), (.8, (98, 66, 46)), (1, (128, 90, 62))]
LINEN = [(0, (84, 68, 52)), (.4, (138, 120, 96)), (.75, (180, 162, 134)), (1, (204, 188, 160))]


def paint(D):
    p = (D["pos"] - [.5, .5, 0]) * 2
    n = D["nrm"] * 2 - 1
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    ao, edge, cls = D["data"].T
    cls = np.rint(cls * 10)
    x, y, z = p.T
    ax = np.abs(x)
    hz = z - HEAD_Z
    S, F = tx.smooth, tx.gauss

    # light from above and a little in front, baked into the facets
    L = np.array([0, -.45, .89])
    lam = n @ L
    facet = np.array([tx._hash(int(a), int(b), int(c), 7) for a, b, c in np.rint(n * 6)]) - .5
    brush = tx.fbm(p, 90, 3) - .5
    t = .30 + .48 * (lam * .5 + .5) + .10 * n[:, 2].clip(0) + .04 * facet + .05 * brush
    t = t * (.55 + .45 * ao ** 1.2) + .12 * edge + .12 * S(-.2, -.9, n[:, 2])  # bounce light under the nose and jaw
    col = ramp(SKIN, t)

    face = (cls == 2) & (y < .02)
    front = S(-.2, -.6, n[:, 1])
    # warm flush on the cheeks, nose and ears; cooler under the jaw
    col = blend(col, col * [1.12, .92, .86], .6 * F(ax, .05, .025) * F(hz, .09, .025) * (cls == 2))
    col = blend(col, col * [1.12, .9, .85], .5 * ((cls == 4) | (cls == 5)))
    # deep sockets, and a dark lid line over small dark eyes
    col = blend(col, col * .75, .3 * F(ax, EYE_X, .017) * F(hz, EYE_Z + .004, .009) * face * front)
    ex, ez = (ax - EYE_X) / .0135, (hz - EYE_Z + .0012 * (ax - EYE_X) / .0135) / .0056
    eye = (ex ** 2 + ez ** 2 < 1) & face & (y < -.07)
    col[eye] = ramp([(0, (60, 46, 40)), (1, (176, 156, 138))], .35 + .6 * (lam[eye] * .5 + .5) ** 2)
    iris = (((ax - EYE_X + .0012) / .0074) ** 2 + ((hz - EYE_Z + .0004) / .0068) ** 2 < 1) & eye
    col[iris] = (34 / 255, 20 / 255, 14 / 255)
    lid = (np.abs(hz - (EYE_Z + .0052 - .0014 * ((ax - EYE_X) / .015) ** 2)) < .003) & (np.abs(ax - EYE_X) < .0155)
    col = blend(col, np.array([18, 10, 8]) / 255, (lid & face & (y < -.07)) * 1.0)
    # heavy, level brows that dip at the inner end (the sheet's stern look)
    bz = .1335 + .004 * S(.012, .045, ax) - .0015 * S(.048, .06, ax)
    bw = .0046 - .0014 * S(.012, .058, ax)
    jag = (tx.fbm(p * [1, 1, 3], 260, 5) - .5) * .003
    brow = (np.abs(hz - bz + jag) < bw) & (ax > .012) & (ax < .058) & face & (y < -.06)
    hair_t = .25 + .35 * (lam * .5 + .5) + .4 * (tx.fbm(p * [1, 1, 4], 160, 9) - .5)
    col = blend(col, ramp(BEARD, hair_t), brow * .95)

    # full short beard: jaw, chin and neck, joined to the hair by sideburns
    edge_z = .070 + .3 * np.maximum(ax - .03, 0) + .9 * np.maximum(ax - .066, 0) + (tx.fbm(p, 300, 11) - .5) * .005
    beard = S(.004, -.004, hz - edge_z) * S(-.022, -.006, hz) * (y < .028 - .25 * np.clip(.06 - hz, 0, 1))
    burns = S(.058, .064, ax) * (hz < .165) * (y > -.024) * (y < .006) * (hz > .06)
    beard = np.maximum(beard, burns * (cls == 2)) * (cls == 2)
    lip = ((x / .014) ** 2 + ((hz - .052) / .0042) ** 2 < 1) & face
    beard = beard * (1 - lip)
    stubble = S(.016, 0, hz - edge_z) * (1 - beard) * (cls == 2) * (hz > .04) * front
    col = blend(col, col * [.8, .74, .72], stubble * .5)
    strand = tx.fbm(p * [1, 1, 3.5], 300, 13) - .5
    beard_t = .3 + .5 * (lam * .5 + .5) * ao + .18 * strand + .12 * edge + .04 * facet
    col = blend(col, ramp(BEARD, beard_t), beard)
    col = blend(col, ramp([(0, (64, 32, 26)), (1, (138, 78, 62))], .3 + .5 * (lam * .5 + .5)), lip * .9)
    col = blend(col, np.array([20, 10, 8]) / 255, (np.abs(hz - .0575) < .0015) * (ax < .02) * face)
    col = blend(col, col * .6, (cls == 4) * S(-.5, -.9, n[:, 2]) * F(ax, .012, .006))  # nostrils
    col = blend(col, col * .6, (cls == 5) * S(.6, .2, np.abs(n[:, 0])))  # inside the ears

    # hair: swept back, strands running front to back
    hstrand = tx.fbm(p * [4, 1, 2], 220, 17) - .5
    hair_t = .22 + .55 * (lam * .5 + .5) * ao + .25 * hstrand + .08 * edge
    col = np.where((cls == 3)[:, None], ramp(HAIR, hair_t), col)

    # the sheet's own portrait painted over the head wherever it saw it
    col = portrait(col, p, n, cls)

    # body: collarbones, pecs, navel, knuckles
    body = cls == 1
    fr = (y < 0) & body
    col = blend(col, col * .72, fr * F(z, 1.282 + .25 * np.clip(ax - .05, 0, 1) ** 1 * .3, .012)
                * S(.02, .05, ax) * S(.16, .13, ax))
    col = blend(col, col * 1.12, fr * F(z, 1.468 - .12 * ax, .008) * S(.02, .04, ax) * S(.15, .12, ax))
    col = blend(col, col * .5, fr * (((x / .007) ** 2 + ((z - 1.085) / .009) ** 2) < 1))
    col = blend(col, col * .8, fr * F(x, 0, .006) * S(1.29, 1.24, z) * S(1.06, 1.1, z))

    # plain linen underwear, from the hips to the top of the thighs
    under = body & (z > .80) & (z < 1.0 + .012 * (ax / .17)) & (ax < .2)
    fold = tx.fbm(p * [1, 2, .6], 30, 21) - .5
    cloth_t = .28 + .5 * (lam * .5 + .5) * ao + .3 * fold + .05 * facet + .1 * edge
    cloth = ramp(LINEN, cloth_t)
    band = (z > .965 + .012 * (ax / .17)) | (z < .815)
    cloth = np.where(band[:, None], cloth * .78, cloth)
    tie = fr & (ax < .012) & (z > .94) & (z < .99)
    cloth = np.where((tie & under)[:, None], ramp(LINEN, cloth_t + .15) * .85, cloth)
    col = np.where(under[:, None], cloth, col)
    return np.clip(col, 0, 1)


def material(img):
    mat = bpy.data.materials.new("M_BaseMale")
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.name = "Diffuse"
    tex.image = img
    tex.location = (-400, 200)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    for key in ("Specular IOR Level", "Specular"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 0.1
            break
    return mat


# ------------------------------------------------------------------- main
def build():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    centres = {"Hair": (0, .01, HEAD_Z + .12), "Ears": (0, .02, HEAD_Z + .105), "Head": (0, 0, HEAD_Z + .12),
               "Nose": (0, -.09, HEAD_Z + .1), "Torso": (0, .01, 1.2), "Neck": (0, .015, 1.55)}
    objs = {name: make_object(name, fn, cls, outward=centres.get(name)) for name, fn, cls, _ in PARTS}
    corners = {}
    for name, _, _, corner in PARTS:
        corners.setdefault(corner, []).append(objs[name])
    for corner, group in corners.items():
        unwrap(group, corner)
    for o in objs.values():  # the right half shares the left half's texels
        mod = o.modifiers.new("Mirror", "MIRROR")
        mod.use_mirror_merge = True
        mod.merge_threshold = 1e-4
        tx._select([o])
        bpy.ops.object.modifier_apply(modifier=mod.name)
        o.data.shade_smooth()  # smooth across small bends, crisp facets at the ridges
        o.data.set_sharp_from_angle(angle=math.radians(18))
    img = bpy.data.images.new("base_male_diffuse", SIZE, SIZE, alpha=False)
    mat = material(img)
    for o in objs.values():
        o.data.materials.append(mat)
    # one-off: which body part each vertex belongs to, for posing the arms in comparisons
    for name in ("Arms", "Hands"):
        me = objs[name].data
        a = me.attributes.new("arm", "FLOAT", "POINT")
        a.data.foreach_set("value", [1.0] * len(me.vertices))
    D = tx.bake(list(objs.values()))
    rgb = paint(D)
    px = np.ones((SIZE * SIZE, 4))
    px[:, :3] = rgb
    img.pixels.foreach_set(px.ravel().astype(np.float32))
    img.filepath_raw = os.path.join(HERE, "base_male_diffuse.png")
    img.file_format = "PNG"
    img.save()
    img.filepath = "//base_male_diffuse.png"

    hair = objs.pop("Hair")
    tx._select(list(objs.values()))
    bpy.context.view_layer.objects.active = objs["Torso"]
    bpy.ops.object.join()
    body = objs["Torso"]
    body.name = body.data.name = "Body"
    hair.data.name = "Hair"
    tris = sum(len(p.vertices) - 2 for o in (body, hair) for p in o.data.polygons)
    print(f"base_male: {tris} triangles")
    return body, hair


def pose_arms(body, deg):
    """Swings the arms down from the T-pose (for comparing with the sheet's stance)."""
    me = body.data
    arm = np.zeros(len(me.vertices))
    if "arm" in me.attributes:
        me.attributes["arm"].data.foreach_get("value", arm)
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    sx, _, sz = SHOULDER
    for side in (1, -1):
        m = (arm > .5) & (co[:, 0] * side > 0)
        w = np.clip((np.abs(co[m, 0]) - .13) / (.22 - .13), 0, 1)
        w = w * w * (3 - 2 * w)
        a = np.radians(deg) * w * side
        dx, dz = co[m, 0] - side * sx, co[m, 2] - sz
        co[m, 0] = side * sx + dx * np.cos(a) + dz * np.sin(a)
        co[m, 2] = sz - dx * np.sin(a) + dz * np.cos(a)
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def compare(out_dir, body):
    import compare_humans as ch
    os.makedirs(out_dir, exist_ok=True)
    scene, cam = ch.scene_setup()
    scene.render.film_transparent = False
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.012, .014, .018, 1)
    sheet = ch.read_png(ch.SHEET)
    gap = lambda h: np.dstack([np.zeros((h, 12, 3)), np.ones((h, 12, 1))])  # noqa: E731

    def save(name, pic):
        h, w = pic.shape[:2]
        img = bpy.data.images.new(name, w, h, alpha=True)
        img.pixels.foreach_set(np.ascontiguousarray(pic[::-1]).ravel().astype(np.float32))
        img.filepath_raw = os.path.join(out_dir, name + ".png")
        img.file_format = "PNG"
        img.save()
        print("compare ->", img.filepath_raw)

    # T-pose turnaround, for Mixamo
    scene.render.resolution_x, scene.render.resolution_y = 900, 760
    cam.data.ortho_scale = 2.3
    strips = []
    for view, look in (("front", Vector((0, 1, 0))), ("side", Vector((1, 0, 0))), ("back", Vector((0, -1, 0)))):
        cam.location = -look * 10 + Vector((0, 0, .92))
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"tpose_{view}.png")
        bpy.ops.render.render(write_still=True)
        strips.append(ch.read_png(scene.render.filepath))
    save("tpose", np.concatenate(strips, 1))

    # the face against the sheet's portrait (a three-quarter view from his right)
    x0, y0, x1, y1 = 1150, 618, 1315, 800
    ref = sheet[y0:y1, x0:x1]
    sc = 4
    ref = np.repeat(np.repeat(ref, sc, 0), sc, 1)
    scene.render.resolution_x, scene.render.resolution_y = ref.shape[1], ref.shape[0]
    cam.data.ortho_scale = .30 * ref.shape[1] / ref.shape[0] if ref.shape[1] > ref.shape[0] else .30
    a = math.radians(32)
    look = Vector((math.sin(a), math.cos(a), -.05)).normalized()
    centre = Vector((.012, -.02, HEAD_Z + .118))
    cam.location = centre - look * 3
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(out_dir, "face_34.png")
    bpy.ops.render.render(write_still=True)
    face = ch.read_png(scene.render.filepath)[:ref.shape[0], :ref.shape[1]]
    # and straight on, and in profile
    shots = [ref, face]
    for name, look in (("face_front", Vector((0, 1, 0))), ("face_side", Vector((-1, 0, 0)))):
        cam.location = Vector((0, -.01, HEAD_Z + .118)) - look * 3
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        shots.append(ch.read_png(scene.render.filepath)[:ref.shape[0], :ref.shape[1]])
    pic = []
    for s_ in shots:
        pic += [s_, gap(ref.shape[0])]
    save("compare_face", np.concatenate(pic[:-1], 1))

    # the body in the sheet's stance, beside the sheet's front, side and back views
    pose_arms(body, 74)
    strips = []
    for view, (box, axis, look) in ch.VIEWS.items():
        bx0, by0, bx1, by1 = box
        r = sheet[by0:by1, bx0:bx1]
        r = np.repeat(np.repeat(r, ch.SCALE, 0), ch.SCALE, 1)
        m = ch.render_view(scene, cam, f"body_{view}", box, axis, look, ch.SCALE, out_dir)
        strips += [r, m[:r.shape[0], :r.shape[1]], gap(r.shape[0])]
    save("compare_body", np.concatenate(strips[:-1], 1))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    body, hair = build()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "base_male.blend"))
    tx._select([body, hair])
    bpy.ops.export_scene.fbx(filepath=os.path.join(HERE, "base_male_mixamo.fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, mesh_smooth_type="OFF")
    if "--compare" in args:
        compare(args[args.index("--compare") + 1], body)


if __name__ == "__main__":
    main()
