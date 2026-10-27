"""
The male base body, modelled fresh from Dan's Shadowfall concept sheets
(reference/character_sheet.png and reference/base_model_sheet.png): faceted
low-poly shapes, heroic proportions, skin and plain linen underwear, in a
T-pose for Mixamo's auto-rigger. No gear. Hair, beard, brows and eyes are
separate objects so they can be swapped, hidden or recoloured.
    blender --background --python assets/blender/base_male.py -- [--compare <dir>]
Writes base_male.blend, base_male_diffuse.png (one 512 hand-painted diffuse)
and base_male_mixamo.fbx next to this script. --compare also renders the body
and face beside the sheets into <dir>.

Every shape starts as a loft of cross-section rings. The body is then
"sculpted": smoothed (subdivision), given its muscles, and reduced back to a
low-poly budget, which leaves the uneven triangle facets of the sheet. The
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
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)  # works on numbers and arrays


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
    (0.040, .068, .072, .050, -.018, 2.8),
    (0.058, .071, .090, .080, .000, 2.5),
    (0.078, .075, .095, .100, .000, 2.4),
    (0.098, .079, .095, .106, .000, 2.4),
    (0.118, .082, .093, .110, .000, 2.4),
    (0.138, .083, .100, .112, .000, 2.5),
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
EYE_Z, EYE_X = .118, .034


def face_dy(x, z):
    """How far the face surface moves forward (-) or back (+) for its features."""
    ax = abs(x)
    dy = 0.0
    dy -= .004 * g(z, .138, .011) * (1 - sstep(.05, .07, ax))  # brow ridge
    dy += .003 * g(z, EYE_Z, .011) * g(ax, EYE_X, .016)  # eye sockets
    dy -= .004 * g(z, .122, .014) * g(x, 0, .012)  # bridge of the nose
    dy -= .004 * g(z, .100, .012) * g(ax, .046, .012)  # cheekbones
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
        B=(0, -.101, z + .128), U=(.008, -.098, z + .114), R=(0, -.115, z + .108),
        T=(0, -.126, z + .084), S=(.0095, -.118, z + .081), W=(.017, -.099, z + .076),
        C=(0, -.107, z + .071), K=(0, -.086, z + .098)).items()}
    for f in ("B U R", "R U S", "R S T", "U W S", "S W C", "S C T", "B K U", "U K W", "W K C"):
        bm.faces.new([v[k] for k in f.split()])


def build_ears(bm):
    z = HEAD_Z
    base = [(.077, .000, z + .130), (.077, .024, z + .128), (.077, .032, z + .104), (.076, .020, z + .082),
            (.076, .003, z + .088)]
    rim = [(.091, .002, z + .137), (.097, .026, z + .137), (.100, .038, z + .110), (.094, .028, z + .077),
           (.087, .008, z + .078)]
    loft(bm, [base, rim], end=(.091, .018, z + .107))


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


def surface(ax, z):
    """The point on the head (with its features) at half-width ax and height z, and its outward normal."""
    lo, hi = 0.0, math.pi / 2
    for _ in range(28):
        mid = (lo + hi) / 2
        if head_point(mid, z)[0] < ax:
            lo = mid
        else:
            hi = mid
    t, e = lo, 1e-3
    du = Vector(head_point(t + e, z)) - Vector(head_point(t - e, z))
    dv = Vector(head_point(t, z + e)) - Vector(head_point(t, z - e))
    n = du.cross(dv).normalized()
    if n.y > 0:
        n = -n
    return Vector(head_point(t, z)), n


def brow_z(ax):
    return .1345 + .0035 * sstep(.012, .045, ax) - .002 * sstep(.048, .062, ax)


def build_brows(bm):
    """Chunky wedges along the brow ridge, thick at the inner end, as on the sheet."""
    rings = []
    for ax in (.011, .02, .03, .04, .05, .058, .063):
        bz = brow_z(ax)
        hw = .0064 - .003 * sstep(.012, .063, ax)
        lift = .0052 - .003 * sstep(.012, .063, ax)
        lo, n = surface(ax, bz - hw)
        hi, _ = surface(ax, bz + hw * .8)
        mid, _ = surface(ax, bz + hw * .2)
        rings.append([tuple(lo - n * .001), tuple(mid + n * lift), tuple(hi - n * .001)])
    loft(bm, rings, start=tuple(sum((Vector(p) for p in rings[0]), Vector()) / 3),
         end=tuple(sum((Vector(p) for p in rings[-1]), Vector()) / 3))


def build_eyes(bm):
    """A slightly domed almond over each eye opening, so eyes can be swapped or recoloured."""
    ring = []
    for i in range(8):
        a = i / 8 * math.tau
        ex, ez = math.cos(a), math.sin(a)
        ez *= .0043 if ez > 0 else .0033
        p, n = surface(EYE_X + .0128 * ex, EYE_Z + ez + .0012 * ex)
        ring.append(p + n * .0008)
    c, n = surface(EYE_X, EYE_Z)
    vs = [bm.verts.new(p) for p in ring]
    cv = bm.verts.new(c + n * .0026)
    for i in range(8):
        bm.faces.new((vs[i], vs[(i + 1) % 8], cv))


# where the beard stops, by ring angle (deg): a moustache under the nose, a bare cheek
# above the line from the mouth to the ear, and sideburns up to the hair
BEARD_TOP = [(0, .071), (10, .072), (20, .069), (32, .072), (46, .082), (60, .096), (72, .114), (82, .148)]
BEARD_ANGLES = (0, 8, 16, 24, 36, 50, 64, 74, 82)


def beard_thick(x, z, deg):
    t = .006 + .006 * sstep(.04, 0, z) * sstep(34, 0, deg) - .002 * sstep(60, 82, deg)
    m = (x / .018) ** 2 + ((z - .052) / .0065) ** 2  # the mouth shows through
    return t * sstep(.85, 1.1, m) - .003 * (1 - sstep(.85, 1.1, m))


def build_beard(bm):
    rows = []
    for s in (0, .25, .5, .75, 1):
        row = []
        for deg in BEARD_ANGLES:
            t = math.radians(deg)
            bot = .036 * sstep(36, 82, deg)
            z = bot + (lerp_rows(BEARD_TOP, deg)[0] - bot) * s
            p = Vector(head_point(t, z))
            e = 1e-3
            du = Vector(head_point(t + e, z)) - Vector(head_point(t - e, z))
            dv = Vector(head_point(t, z + e)) - Vector(head_point(t, z - e))
            n = du.cross(dv).normalized()
            if n.dot(p - Vector((0, 0, HEAD_Z + .1))) < 0:
                n = -n
            row.append(p + n * beard_thick(p.x, z, deg) * (1 - .75 * s ** 3))
        rows.append(row)
    under = []
    for k, (down, back, inward) in enumerate(((.008, .014, .95), (.012, .040, .84))):
        under.insert(0, [Vector((p.x * inward, p.y + back, p.z - down)) for p in rows[0]])
    tuck = [p - (p - Vector((0, 0, HEAD_Z + .1))).normalized() * .009 for p in rows[-1]]
    rings = [[tuple(p) for p in r] for r in under + rows + [tuck]]
    loft(bm, rings, closed=False)


def build_neck(bm):
    rows = [(1.50, .098, .076, .088, .014), (1.57, .084, .066, .074, .014), (1.64, .072, .056, .064, .010)]
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
    (1.260, .188, .126, .104, .000, 2.8),
    (1.340, .204, .134, .106, .000, 3.0),
    (1.410, .212, .120, .106, .004, 3.2),
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
    (.950, .088, .112, .096, .110, .120),
    (.860, .097, .112, .094, .110, .114),
    (.740, .102, .100, .084, .100, .100),
    (.600, .104, .080, .070, .082, .076),
    (.500, .105, .068, .061, .070, .064),
    (.420, .106, .072, .062, .068, .082),
    (.320, .107, .068, .058, .064, .080),
    (.200, .108, .052, .047, .052, .056),
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


FOOT = [(.070, .037, .088), (.033, .050, .115), (-.048, .058, .096), (-.124, .061, .064),
        (-.184, .057, .046), (-.222, .044, .035)]  # y, half width, height


def build_feet(bm):
    cx = .110
    rings = []
    for y, w, h in FOOT:
        rings.append([(cx - w, y, 0), (cx + w, y, 0), (cx + w, y, .55 * h), (cx + .55 * w, y, h),
                      (cx - .55 * w, y, h), (cx - w, y, .55 * h)])
    loft(bm, rings, start=(cx, .077, .038), end=(cx, -.232, .016))


# ------------------------------------------------------------------ sculpt
# muscles, in the T-pose: centre (half width, y, z), radii, how far they swell (m)
MUSCLES = [
    ((.215, .000, 1.455), (.05, .07, .055), .009),  # deltoid
    ((.330, -.035, 1.430), (.06, .03, .035), .009),  # biceps
    ((.310, .035, 1.435), (.07, .03, .035), .007),  # triceps
    ((.520, -.010, 1.435), (.06, .04, .040), .008),  # forearm
    ((.095, -.120, 1.345), (.07, .04, .045), .010),  # pectorals
    ((.095, -.120, 1.290), (.07, .03, .012), -.004),  # under the pecs
    ((.032, -.105, 1.245), (.022, .02, .022), .004),  # abdominals
    ((.032, -.105, 1.180), (.022, .02, .022), .004),
    ((.032, -.105, 1.115), (.022, .02, .022), .004),
    ((.000, -.110, 1.180), (.008, .03, .080), -.003),  # the line down the middle
    ((.080, .020, 1.530), (.05, .05, .030), .010),  # trapezius
    ((.170, .050, 1.300), (.04, .06, .080), .009),  # lats
    ((.150, -.050, 1.120), (.03, .06, .060), .004),  # obliques
    ((.090, -.070, 1.490), (.06, .02, .010), .003),  # collarbones
    ((.080, .100, .930), (.06, .04, .060), .012),  # glutes
    ((.100, -.070, .720), (.05, .04, .110), .010),  # quads
    ((.060, -.050, .560), (.03, .03, .040), .007),  # inner quad, above the knee
    ((.155, -.010, .720), (.03, .05, .100), .006),  # outer quad
    ((.100, .070, .720), (.05, .04, .100), .006),  # hamstrings
    ((.120, .050, .380), (.04, .04, .070), .011),  # calves
    ((.085, .050, .390), (.03, .04, .060), .008),
    ((.104, -.060, .500), (.025, .02, .025), .004),  # knee caps
]


def muscles(co, nrm):
    ax = np.abs(co[:, 0])
    amount = np.zeros(len(co))
    for (cx, cy, cz), (rx, ry, rz), amp in MUSCLES:
        amount += amp * np.exp(-((ax - cx) / rx) ** 2 - ((co[:, 1] - cy) / ry) ** 2 - ((co[:, 2] - cz) / rz) ** 2)
    return nrm * amount[:, None]


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def refine(obj, tris, sculpt=None):
    """Smooths a blocky part (two levels of subdivision), sculpts it, then reduces it
    to about this many triangles (both sides). Leaves the left half, for mirroring."""
    tx._select([obj])
    mods = [obj.modifiers.new("Mirror", "MIRROR"), obj.modifiers.new("Subdivision", "SUBSURF")]
    mods[0].use_clip = mods[0].use_mirror_merge = True
    mods[1].levels = 2
    for m in mods:
        bpy.ops.object.modifier_apply(modifier=m.name)
    me = obj.data
    if sculpt:
        co = np.empty(len(me.vertices) * 3)
        nrm = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        me.vertices.foreach_get("normal", nrm)
        co = co.reshape(-1, 3) + sculpt(co.reshape(-1, 3), nrm.reshape(-1, 3))
        me.vertices.foreach_set("co", co.ravel())
        me.update()
    dec = obj.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = min(1.0, tris / tri_count(me))
    dec.use_symmetry = True
    dec.symmetry_axis = "X"
    bpy.ops.object.modifier_apply(modifier=dec.name)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                           plane_co=(0, 0, 0), plane_no=(1, 0, 0), clear_inner=True)
    bm.to_mesh(me)
    bm.free()


# class (1 body skin, 2 head skin, 3 hair, 4 nose, 5 ears, 6 beard, 7 brows, 8 eyes),
# the UV quadrant each part is packed into, and its triangle budget after sculpting
PARTS = [
    ("Head", build_head, 2, (.5, .5), None),
    ("Nose", build_nose, 4, (.5, .5), None),
    ("Ears", build_ears, 5, (.5, .5), None),
    ("Eyes", build_eyes, 8, (.5, .5), None),
    ("Brows", build_brows, 7, (.5, .5), None),
    ("Beard", build_beard, 6, (0, .5), None),
    ("Hair", build_hair, 3, (0, .5), None),
    ("Neck", build_neck, 2, (0, .5), 90),
    ("Torso", build_torso, 1, (0, .5), 600),
    ("Arms", build_arms, 1, (.5, 0), 460),
    ("Hands", build_hands, 1, (.5, 0), 280),
    ("Legs", build_legs, 1, (0, 0), 480),
    ("Feet", build_feet, 1, (0, 0), 140),
]
PARTS_BY = {p[0]: p for p in PARTS}
MODULAR = ("Hair", "Beard", "Brows", "Eyes")  # separate objects; the rest is joined into Body


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
    ((-.034, -.088, .118), (1253, 698)),  # right eye
    ((.034, -.088, .118), (1284, 699)),  # left eye
    ((-.022, -.094, .057), (1268, 744)),  # right corner of the mouth
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


def portrait(col, p, n, cls, keep):
    """Projects the sheet's portrait onto the head, hair and beard. The portrait sees his
    right side; texels are shared by both sides, so each is looked up on the right.
    keep (0..1) holds the face's own paint where the beard, brows and hair cover it."""
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
    head = np.isin(cls, (2, 3, 4, 5, 6)) & (p[:, 2] > HEAD_Z - .03)
    low = np.where(cls == 6, 1, tx.smooth(HEAD_Z, HEAD_Z + .014, p[:, 2]))
    w = tx.smooth(.12, .4, nq @ view) * inside * head * low * np.where(cls == 2, keep, 1)
    w = w * np.where(cls == 4, tx.smooth(-.6, -.2, n[:, 2]), 1) * np.where(cls == 6, .8, 1)
    sheet = read_png(SHEET)
    u, v = np.clip(uv[:, 0], 0, sheet.shape[1] - 2), np.clip(uv[:, 1], 0, sheet.shape[0] - 2)
    iu, iv = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = (u - iu)[:, None], (v - iv)[:, None]
    s = (sheet[iv, iu] * (1 - fu) * (1 - fv) + sheet[iv, iu + 1] * fu * (1 - fv)
         + sheet[iv + 1, iu] * (1 - fu) * fv + sheet[iv + 1, iu + 1] * fu * fv)
    w = w * tx.smooth(y0, y0 + 6, uv[:, 1])  # the panel's top edge cuts through his hair
    w = w * (1 - tx.smooth(.0, .03, s[:, 2] - s[:, 0]) * tx.smooth(.25, .15, s.max(1)))  # the dark backdrop
    # hair and beard meshes reaching past what the portrait painted as hair keep their own paint
    w = w * (1 - np.isin(cls, (3, 6)) * tx.smooth(.2, .3, s[:, 0] - s[:, 2]) * tx.smooth(.45, .6, s[:, 0]))
    return blend(col, s, w)


def ramp(stops, t):
    """Colour along stops [(t, (r, g, b)), ...] for each value of t."""
    ts = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops], np.float64) / 255
    return np.stack([np.interp(t, ts, cs[:, k]) for k in range(3)], 1)


def blend(base, colour, m):
    m = np.clip(m, 0, 1)[:, None]
    return base * (1 - m) + colour * m


SKIN = [(0, (96, 52, 36)), (.35, (160, 98, 70)), (.62, (206, 140, 104)), (.85, (228, 168, 128)), (1, (242, 196, 156))]  # the palette swatch
IRIS = [(0, (30, 20, 14)), (.6, (74, 50, 32)), (1, (40, 27, 19))]
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
    L = np.array([0, -.25, .97])
    lam = n @ L
    facet = np.array([tx._hash(int(a), int(b), int(c), 7) for a, b, c in np.rint(n * 6)]) - .5
    brush = tx.fbm(p, 90, 3) - .5
    t = .30 + .48 * (lam * .5 + .5) + .10 * n[:, 2].clip(0) + .04 * facet + .05 * brush
    t = t * (.55 + .45 * ao ** 1.2) + .12 * edge + .12 * S(-.2, -.9, n[:, 2])  # bounce light under the nose and jaw
    col = ramp(SKIN, t)

    face = (cls == 2) & (y < .02)
    front = S(-.2, -.6, n[:, 1])
    # warm flush on the cheeks, nose and ears
    col = blend(col, col * [1.1, .93, .88], .5 * F(ax, .046, .022) * F(hz, .09, .022) * (cls == 2))
    col = blend(col, col * [1.1, .92, .87], .45 * ((cls == 4) | (cls == 5)))
    col = blend(col, col * .8, .3 * F(ax, EYE_X, .016) * F(hz, EYE_Z + .004, .009) * face * front)  # sockets
    col = blend(col, col * .6, (cls == 4) * S(-.5, -.9, n[:, 2]) * F(ax, .01, .005))  # nostrils
    col = blend(col, col * .6, (cls == 5) * S(.6, .2, np.abs(n[:, 0])))  # inside the ears
    # lips and the mouth line, seen through the beard (and on a bare face)
    lip = ((x / .013) ** 2 + ((hz - .051) / .0042) ** 2 < 1) & face
    col = blend(col, ramp([(0, (92, 46, 36)), (1, (176, 104, 84))], .3 + .5 * (lam * .5 + .5)), lip * .85)
    col = blend(col, np.array([40, 20, 16]) / 255, (np.abs(hz - .0575) < .0013) * (ax < .019) * face)
    # where the beard, brows and hair sit, the skin stays clean (they can be taken off)
    deg = np.degrees(np.arctan2(ax, -y))
    top = np.interp(deg, [d for d, _ in BEARD_TOP], [t for _, t in BEARD_TOP])
    under_beard = S(.005, -.001, hz - top) * (deg < 90) * (cls == 2)
    under_brow = S(.0075, .0045, np.abs(hz - brow_z(ax))) * S(.006, .01, ax) * S(.07, .064, ax) * face
    zb = np.interp(deg, [d for d, _ in HAIRLINE], [t for _, t in HAIRLINE])
    scalp = S(zb - .01, zb + .002, hz) * (cls == 2)
    col = blend(col, col * [.86, .84, .84], .55 * under_beard * S(-.01, .01, hz))  # shaved shadow
    col = blend(col, col * .9, scalp)
    keep = 1 - np.maximum.reduce([under_beard, under_brow, scalp])

    # beard and brows: short dark strands
    strand = tx.fbm(p * [1, 1, 3.5], 300, 13) - .5
    beard_t = .3 + .5 * (lam * .5 + .5) * ao + .18 * strand + .04 * facet
    col = np.where((cls == 6)[:, None], ramp(BEARD, beard_t), col)
    col = np.where((cls == 7)[:, None], ramp(BEARD, beard_t * .75 - .05), col)

    # hair: swept back, strands running front to back
    hstrand = tx.fbm(p * [4, 1, 2], 220, 17) - .5
    hair_t = .22 + .55 * (lam * .5 + .5) * ao + .25 * hstrand + .08 * edge
    col = np.where((cls == 3)[:, None], ramp(HAIR, hair_t), col)

    # eyes: sclera, a brown iris, the upper lid's shadow
    ex, ez = (ax - EYE_X) / .0128, (hz - EYE_Z) / .005
    eye = cls == 8
    ecol = ramp([(0, (120, 104, 92)), (1, (214, 200, 184))], .5 + .4 * (1 - ex ** 2))
    r = np.hypot((ax - EYE_X + .001) / .0057, (hz - EYE_Z - .0004) / .0057)
    ecol = np.where((r < 1)[:, None], ramp(IRIS, .25 + .75 * r), ecol)
    ecol = np.where((r < .42)[:, None], np.array([10, 7, 6]) / 255, ecol)
    ecol = blend(ecol, ecol * .35, S(.1, .9, ez))  # under the upper lid
    ecol = blend(ecol, np.array([235, 228, 220]) / 255, (np.hypot(ex + .2, ez - .3) < .12) * 1.0)  # catchlight
    col = np.where(eye[:, None], ecol, col)

    # the sheet's own portrait painted over the head wherever it saw it
    col = portrait(col, p, n, cls, keep)

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
    centre = (0, 0, HEAD_Z + .11)
    centres = {"Hair": centre, "Ears": centre, "Head": centre, "Beard": centre, "Brows": centre, "Eyes": centre,
               "Nose": (0, -.09, HEAD_Z + .1), "Torso": (0, .01, 1.2), "Neck": (0, .015, 1.55)}
    objs = {name: make_object(name, fn, cls, outward=centres.get(name)) for name, fn, cls, _, _ in PARTS}
    corners = {}
    for name, _, _, corner, tris in PARTS:
        if tris:
            refine(objs[name], tris, muscles if name in ("Torso", "Arms", "Legs", "Neck") else None)
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
        o.data.set_sharp_from_angle(angle=math.radians(35 if PARTS_BY[o.name][4] else 18))
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

    modular = [objs.pop(name) for name in MODULAR]
    tx._select(list(objs.values()))
    bpy.context.view_layer.objects.active = objs["Torso"]
    bpy.ops.object.join()
    body = objs["Torso"]
    body.name = body.data.name = "Body"
    for o in modular:
        o.data.name = o.name
        print(f"base_male: {o.name} {tri_count(o.data)} triangles")
    print(f"base_male: Body {tri_count(body.data)}, all {sum(tri_count(o.data) for o in [body] + modular)} triangles")
    return body, modular


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


BASE_SHEET = os.path.join(HERE, "reference", "base_model_sheet.png")
BASE_VIEWS = {  # (left, top, right, bottom) on the base-model sheet, figure axis x, camera direction
    "front": ((30, 105, 280, 710), 153, Vector((0, 1, 0))),
    "right": ((290, 105, 480, 710), 390, Vector((1, 0, 0))),
    "back": ((500, 105, 745, 710), 621, Vector((0, -1, 0))),
}


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

    # the body in the stance of the base-model sheet, beside its front, right and back views
    pose_arms(body, 72)
    base = ch.read_png(BASE_SHEET)
    ch.GROUND, ch.PX_PER_M = 698, 314  # its figures stand on row 698, 576 px from sole to hair
    strips = []
    for view, (box, axis, look) in BASE_VIEWS.items():
        bx0, by0, bx1, by1 = box
        r = base[by0:by1, bx0:bx1]
        r = np.repeat(np.repeat(r, 2, 0), 2, 1)
        m = ch.render_view(scene, cam, f"body_{view}", box, axis, look, 2, out_dir)
        strips += [r, m[:r.shape[0], :r.shape[1]], gap(r.shape[0])]
    save("compare_body", np.concatenate(strips[:-1], 1))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    body, modular = build()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "base_male.blend"))
    tx._select([body] + modular)
    bpy.ops.export_scene.fbx(filepath=os.path.join(HERE, "base_male_mixamo.fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, mesh_smooth_type="OFF")
    if "--compare" in args:
        compare(args[args.index("--compare") + 1], body)


if __name__ == "__main__":
    main()
