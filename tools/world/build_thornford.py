"""Build the first authored district into an OUTPUT COPY of the current map.

Usage: python tools/world/build_thornford.py --source PROJECT --output STAGING
Review and copy the resulting files individually. Never run this over later
hand edits without reviewing the generated tf_* records and terrain first.
No external packages; the map remains editable by the existing World dock.
"""
import argparse
import base64
import json
import math
import random
import struct
import zlib
from pathlib import Path

P = argparse.ArgumentParser(description=__doc__)
P.add_argument('--source', required=True, type=Path)
P.add_argument('--output', required=True, type=Path)
ARGS = P.parse_args()
SRC, OUT = ARGS.source.resolve(), ARGS.output.resolve()
if SRC == OUT:
    P.error('Output must be a separate staging directory.')
REL = Path('data/terrain/new_map')
RNG = random.Random(31102026)


def read(rel):
    return json.loads((SRC / rel).read_text(encoding='utf-8-sig'))


def write(rel, value):
    dest = OUT / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def smooth(lo, hi, x):
    k = max(0.0, min(1.0, (x - lo) / (hi - lo)))
    return k * k * (3 - 2 * k)


ROUTES = [
    ('tf_watch_road', 'The Lantern Road', 3.5, [(-450, -193), (-450, -235), (-465, -265), (-465, -300), (-445, -340), (-450, -380), (-450, -425), (-415, -455), (-415, -485)]),
    ('tf_wood_loop', 'Briarwood Loop', 2.7, [(-465, -265), (-515, -270), (-575, -275), (-575, -320), (-555, -360), (-515, -385), (-450, -380)]),
    ('tf_farm_lane', 'Orchard Lane', 3.0, [(-450, -235), (-405, -245), (-365, -270), (-350, -270)]),
    ('tf_farm_loop', 'Orchard Return', 2.4, [(-350, -270), (-355, -325), (-395, -345), (-445, -340)]),
]
AREAS = [(-450, -207, 37), (-465, -300, 17), (-445, -340, 20),
         (-450, -425, 25), (-415, -485, 18), (-575, -275, 19),
         (-555, -360, 23), (-350, -270, 22)]


def seg_dist(x, z, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    k = max(0, min(1, ((x - a[0]) * dx + (z - a[1]) * dz) / (dx * dx + dz * dz)))
    return math.hypot(x - a[0] - dx * k, z - a[1] - dz * k)


def road_dist(x, z):
    return min(seg_dist(x, z, a, b) - half for _, _, half, pts in ROUTES for a, b in zip(pts, pts[1:]))


def open_dist(x, z):
    return min(road_dist(x, z) - 4, *(math.hypot(x - a, z - b) - r for a, b, r in AREAS))


def in_district(x, z):
    return -650 <= x <= -285 and -535 <= z <= -140


# Read and update the existing packed grid, including duplicated tile edges.
data = (SRC / REL / 'world.bin').read_bytes()
x0, z0, cell = struct.unpack_from('<fff', data, 8)
tile, tx, tz = struct.unpack_from('<III', data, 24)
tiles = {}


def unpack(i, j):
    key = (i, j)
    if key in tiles:
        return tiles[key]
    off, size = struct.unpack_from('<II', data, 36 + (j * tx + i) * 8)
    raw = zlib.decompress(data[off:off + size]) if size else bytes(4356)
    delta = struct.unpack_from('<1089h', raw)
    cols = [0] * 33
    h = []
    for b in range(33):
        run = 0
        for a in range(33):
            cols[a] += delta[b * 33 + a]
            run += cols[a]
            h.append(run * .05 - 50 if size else -12)
    tiles[key] = [h, list(raw[2178:3267]), list(raw[3267:4356])]
    return tiles[key]


def decode_layer(s, default=-1):
    return list(struct.unpack('<1024h', zlib.decompress(base64.b64decode(s)))) if s else [default] * 1024


layer_path = SRC / REL / 'sculpt.json'
layer = json.loads(layer_path.read_text(encoding='utf-8-sig')) if layer_path.exists() else {
    '_about': 'World dock sculpt layer, including the authored Thornford district.',
    'version': 1, 'x0': x0, 'z0': z0, 'cell': cell, 'tiles': {}}
layers = {}
edited = set()
for b in range(math.ceil((-535 - z0) / cell), math.floor((-140 - z0) / cell) + 1):
    for a in range(math.ceil((-650 - x0) / cell), math.floor((-285 - x0) / cell) + 1):
        x, z = x0 + a * cell, z0 + b * cell
        old = unpack(a // 32, b // 32)
        idx = (b % 32) * 33 + a % 32
        h0, w0, info0 = old[0][idx], old[1][idx], old[2][idx]
        edge = min(x + 650, -285 - x, z + 535, -140 - z)
        blend = smooth(0, 20, edge)
        od, rd = open_dist(x, z), road_dist(x, z)
        ridge = smooth(0, 25, od)
        level = 3.2 + max(0, -z - 260) * .012
        desired = level + ridge * (9 + 2 * math.sin(x * .06) + 2 * math.cos(z * .045))
        h = round((h0 + (desired - h0) * blend) * 20) / 20
        w = round(w0 + ((1 - smooth(1, 7, od)) * 255 - w0) * blend)
        surf = (1 if z > -315 else 9) if od < 10 else 5
        if z < -390 and math.hypot(x + 450, z + 425) < 28:
            surf = 5
        if blend < .5:
            surf = info0 & 15
        key = f'{a // 32},{b // 32}'
        if key not in layers:
            prev = layer['tiles'].get(key, {})
            layers[key] = [decode_layer(prev.get('h'), 0), decode_layer(prev.get('w')), decode_layer(prev.get('s'))]
        li = (b % 32) * 32 + a % 32
        layers[key][0][li] += round((h - h0) * 20)
        layers[key][1][li] = w
        layers[key][2][li] = surf
        iset = [a // 32 - 1, a // 32] if a % 32 == 0 else [a // 32]
        jset = [b // 32 - 1, b // 32] if b % 32 == 0 else [b // 32]
        for i in iset:
            for j in jset:
                if 0 <= i < tx and 0 <= j < tz:
                    t = unpack(i, j)
                    q = (b - j * 32) * 33 + a - i * 32
                    t[0][q], t[1][q], t[2][q] = h, w, (info0 & 240) | surf
                    edited.add((i, j))
for key, values in layers.items():
    layer['tiles'][key] = {k: base64.b64encode(zlib.compress(struct.pack('<1024h', *v))).decode() for k, v in zip('hws', values)}
write(REL / 'sculpt.json', layer)
blobs = []
index = bytearray(tx * tz * 8)
offset = 36 + len(index)
for j in range(tz):
    for i in range(tx):
        k = j * tx + i
        if (i, j) in edited:
            h, walk, info = tiles[i, j]
            q = [round((v + 50) * 20) for v in h]
            delta = []
            for b in range(33):
                for a in range(33):
                    dx = q[b * 33 + a] - (q[b * 33 + a - 1] if a else 0)
                    up = q[(b - 1) * 33 + a] - (q[(b - 1) * 33 + a - 1] if a else 0) if b else 0
                    delta.append(dx - up)
            blob = zlib.compress(struct.pack('<1089h', *delta) + bytes(walk) + bytes(info))
        else:
            at, size = struct.unpack_from('<II', data, 36 + k * 8)
            blob = data[at:at + size]
        struct.pack_into('<II', index, k * 8, offset if blob else 0, len(blob))
        blobs.append(blob)
        offset += len(blob)
(OUT / REL / 'world.bin').write_bytes(data[:36] + index + b''.join(blobs))

w, s = read(REL / 'spawns.json'), read(REL / 'scenery.json')
# Preserve every previous placed object. Generated records have stable ids.
for d in [w, s]:
    for key, value in d.items():
        if isinstance(value, list):
            d[key] = [r for r in value if not isinstance(r, dict) or not r.get('id', '').startswith('tf_')]


def add(key, row):
    w.setdefault(key, []).append(row)


def prop(model, x, z, scale=1, rotation=None, collider=None, **extra):
    p = dict(id=f'tf_prop_{len(s["props"]):04d}', model=model,
             position=[round(x, 2), round(z, 2)], scale=round(scale, 2),
             rotation=round(RNG.uniform(0, 360) if rotation is None else rotation, 2), **extra)
    if collider is not None:
        p['collider'] = collider
    s['props'].append(p)


w['playerStart'] = dict(position=[-450, -203], facing=180)
w['openingText'] = 'Thornford. Speak with Captain Rowan by the lanterns, then follow the road into the woods.'
w['trainerOverrides'] = {k: 'tf_rowan' for k in ['brask', 'nell', 'odo', 'grue', 'aveline', 'wenna', 'ysolde', 'sabeth', 'pell']}
w['trainerOverrides'].update(orrin='tf_iren', tam='tf_scout', hester='tf_elsie', briony='tf_elsie')
w['regions'] = [dict(id='tf_reach', name='Thornford Reach', levels='1-4', rect=[-650, -535, 365, 395]),
                dict(id='new_map', name='The Uncharted Marches', levels='1+')]
for ident, name, half, pts in ROUTES:
    add('roads', dict(id=ident, name=name, kind='road' if half >= 3 else 'track', halfWidth=half, points=pts))
places = [('tf_town', 'Thornford', 'town', [-450, -207], 'An old trading village sheltering the last watch on the western road.'),
          ('tf_cairn', 'The Fallen Lantern', 'story', [-465, -300], 'A broken lantern lies beside fresh tracks. Someone dragged the road watch north.'),
          ('tf_camp', 'Briarwood Camp', 'camp', [-575, -275], 'The foresters left their axes behind. Wolves circle the old camp.'),
          ('tf_hollow', 'Wolf Hollow', 'hunt', [-555, -360], 'Fresh pawprints turn through the briars. A narrow path rejoins the watch road to the east.'),
          ('tf_watch', 'Old Watch Ruins', 'ruin', [-450, -425], 'The watch bell is silent. Its keeper still stands among the fallen stones.'),
          ('tf_shrine', 'Dawnstone Shrine', 'landmark', [-415, -485], 'Dawnstone catches the first light over the western hills. The road ends here for now.'),
          ('tf_orchard', 'Holt Orchard', 'place', [-350, -270], 'The orchard lane forms a second way back from the old watch road.')]
w['pois'] = [dict(id=i, name=n, kind=k, at=p, note=t, region='tf_reach', act='Chapter 1') for i, n, k, p, t in places]
w['subzones'] = [dict(id=i, name=n, at=p, radius=r) for (i, n, _, p, _), r in zip(places, [37, 20, 23, 26, 32, 24, 26])]
for i, p, size, roof, walls in [
    ('tf_inn', [-465, -204], [10, 8], 'thatch', 'plaster'),
    ('tf_smithy', [-435, -206], [8, 7], 'slate', 'stone'),
    ('tf_watchhouse', [-463, -225], [8, 6], 'tile', 'timber'),
    ('tf_cottage', [-435, -188], [7, 6], 'thatch', 'plaster'),
    ('tf_farmhouse', [-336, -264], [8, 6], 'thatch', 'timber')]:
    add('houses', dict(id=i, position=p, size=size, roof=roof, walls=walls, door='s', chimney=True))
add('houses', dict(id='tf_watch_tower', position=[-456, -441], size=[5, 5], roof='slate', walls='stone', tower=True, door='s'))
for npc, pos in [('tf_rowan', [-454, -211]), ('tf_elsie', [-462, -198]), ('tf_iren', [-435, -199]), ('tf_scout', [-568, -273])]:
    add('npcSpawns', dict(npc=npc, position=pos, facing=180))
add('shrines', dict(id='tf_home_shrine', position=[-444, -193], rotation=0, label='at the Thornford shrine'))
add('shrines', dict(id='tf_dawn_shrine', position=[-415, -486], rotation=0, label='at Dawnstone Shrine'))
for model, pos, scale, rotation, radius in [
    ('shrine', [-444, -193], 1, 0, .9), ('anvil', [-435, -197], 1, 0, .5),
    ('cart', [-457, -298], 1, 35, 1.3), ('crate', [-459, -302], 1, 10, .5),
    ('camp', [-578, -280], 1.2, 30, .8), ('camp', [-563, -281], 1, -20, .8),
    ('watch_post', [-455, -433], 1.3, 0, 2), ('standing_stone', [-415, -487], 1.5, 0, .8),
    ('bone_pile', [-561, -364], 1.2, 0, .3), ('well', [-443, -213], 1, 0, .7)]:
    prop(model, *pos, scale, rotation, radius)
# Broken walls frame an arena while leaving broad approaches and exits.
for x, z, r in [(-468, -434, 0), (-469, -417, 90), (-430, -433, 0), (-433, -414, 90)]:
    prop('ruin_wall', x, z, 1.8, r, .8)
for x, z in [(-476, -210), (-432, -213), (-465, -268), (-470, -303), (-441, -341), (-452, -383), (-464, -420), (-414, -477)]:
    s.setdefault('lights', []).append(dict(id=f'tf_light_{x}_{z}', position=[x, z], height=1.5,
                                         intensity=2.8, distance=9, color='#ffd19a', brazier=True, flicker=True))
for pos, to in [([-453, -244], ['tf_cairn', 'tf_orchard']), ([-476, -267], ['tf_camp', 'tf_watch']),
                ([-448, -375], ['tf_watch', 'tf_hollow']), ([-419, -455], ['tf_shrine', 'tf_town'])]:
    add('signposts', dict(id=f'tf_sign_{len(w.get("signposts", []))}', position=pos, points=[dict(to=i) for i in to]))
for pos in [(-450, -203), (-465, -300), (-575, -275), (-555, -360), (-450, -425), (-415, -485)]:
    s.setdefault('motes', []).append(dict(id=f'tf_motes_{pos[0]}_{pos[1]}', position=pos, radius=6, count=12, color='#e5d49b'))
for kind, points in [('tf_revenant', [(-473, -316), (-455, -326), (-436, -341), (-451, -357), (-444, -374)]),
                     ('tf_wolf', [(-570, -340), (-561, -361), (-542, -368), (-529, -377)]),
                     ('tf_sentry', [(-460, -403), (-439, -411)]) ,
                     ('tf_keeper', [(-450, -428)])]:
    for k, pos in enumerate(points):
        add('enemySpawns', dict(id=f'{kind}_{k+1}', enemy=kind, position=pos))
for k, pos in enumerate([[-583, -267], [-572, -288], [-565, -310], [-553, -336], [-522, -375]]):
    add('placedLoot', dict(id=f'tf_herb_{k}', model='res://assets/environment/nature/plants/Flower_3_Group.gltf', scale=.6,
                          position=pos, prompt='Gather ditchbell', reward=dict(item='ditchbell'), respawn=50))
add('chests', dict(id='tf_watch_chest', name='the watch strongbox', position=[-439, -432], coins=12, items=[dict(item='healing_draught', count=1)]))
add('stations', dict(id='tf_hearth', name='the Thornford hearth', kind='fire', position=[-463, -194], radius=3))
add('stations', dict(id='tf_forge', name="Iren's forge", kind='forge', position=[-435, -197], radius=3))
prop('forge', -463, -194, .55, 0)
for x, z in [(-458, -197), (-440, -197), (-440, -218), (-458, -218)]:
    prop('crate', x, z, .7, 0, .45)
for x, z in [(-467, -212), (-437, -215), (-431, -193), (-469, -190)]:
    prop('res://assets/environment/nature/trees/CommonTree_1.gltf', x, z, .8, collider=.3, tint='#c4c7ac')
    prop('res://assets/environment/nature/plants/Flower_3_Group.gltf', x + 1.7, z + 1.6, .45)
for x, z in [(-460, -198), (-458, -200), (-456, -202), (-454, -204),
             (-452, -206), (-450, -208), (-448, -210), (-446, -211),
             (-440, -199), (-442, -200), (-444, -201)]:
    prop('res://assets/environment/nature/rocks/RockPath_Round_Wide.gltf', x, z, .8, heightOffset=.03, tint='#aaa793')

# A coherent forest edge, rather than evenly scattered props on an empty field.
# Every canopy has a physical trunk; wide routes stay clear of colliders.
trees = 0
protected = [r['position'] for key in ['npcSpawns', 'enemySpawns', 'placedLoot', 'chests', 'shrines'] for r in w.get(key, [])]
for z in range(-518, -151, 8):
    for x in range(-635, -298, 8):
        x, z = x + RNG.uniform(-2.5, 2.5), z + RNG.uniform(-2.5, 2.5)
        od = open_dist(x, z)
        # Frame clearings inside the camera view while keeping the playable
        # corridor wide. Tree colliders, rather than an invisible wall, mark
        # these softer inner edges of the woods.
        visual_edge = min(road_dist(x, z) - 2, *(math.hypot(x - a, z - b) - r * .65 for a, b, r in AREAS))
        if visual_edge < 2 or od > 40 or RNG.random() > .78:
            continue
        if math.hypot(x + 450, z + 207) < 36 or any(math.hypot(x-p[0], z-p[1]) < 4 for p in protected):
            continue
        if any(math.hypot(x-h['position'][0], z-h['position'][1]) < max(h['size']) * .75 + 2 for h in w.get('houses', [])):
            continue
        model = RNG.choice(['CommonTree_1', 'CommonTree_2', 'CommonTree_4', 'Pine_1', 'Pine_3'])
        if z < -390 and RNG.random() < .3:
            model = RNG.choice(['DeadTree_1', 'TwistedTree_1'])
        prop('res://glTF/' + model + '.gltf', x, z, RNG.uniform(1.0, 1.65), collider=.32,
             tint=RNG.choice(['#c3c6a8', '#b5c4a7', '#d1c8aa']))
        trees += 1
        if RNG.random() < .22:
            prop('res://assets/environment/nature/rocks/Rock_Medium_1.gltf', x + 2.4, z + 1.8, RNG.uniform(.6, 1.5), collider=.7)
        if RNG.random() < .65:
            prop('res://assets/environment/nature/plants/Bush_Common.gltf', x - 2.3, z - 1.3, RNG.uniform(.8, 1.3))
for _ in range(750):
    x, z = RNG.uniform(-620, -310), RNG.uniform(-515, -155)
    rd, od = road_dist(x, z), open_dist(x, z)
    if rd < 1.2 or od > 14 or math.hypot(x + 450, z + 207) < 28:
        continue
    model = RNG.choice(['Grass_Common_Short', 'Grass_Wispy_Short', 'Fern_1', 'Flower_4_Group', 'Clover_1'])
    prop('res://glTF/' + model + '.gltf', x, z, RNG.uniform(.28, .65))
write(REL / 'spawns.json', w)
write(REL / 'scenery.json', s)


def quest(i, name, giver, summary, offer, objectives, reward, requires=None, **extra):
    return dict(id=i, name=name, map='new', giver=giver, turnIn=giver, summary=summary, offer=offer,
                progress='Follow the marked paths. The signposts will bring you back to Thornford.',
                complete=extra.pop('complete', 'You have done the Reach a kindness. Here, take this for the road.'),
                objectives=objectives, reward=reward, requires=requires or [], **extra)


def examine(i, place, label):
    return dict(id=i, type='examine', target='poi:' + place, label=label, location=place)


def kill(i, target, count, label, loc):
    return dict(id=i, type='kill', target=target, count=count, label=label, location=loc)


content = {
    '_about': 'Thornford Reach: editable first district, built from the installed stylized assets. New-map quests only. World placements and sculpt edits are in data/terrain/new_map.',
    'locations': [dict(id=i, name=n, position=p, radius=20) for i, n, _, p, _ in places],
    'npcs': [dict(id='tf_rowan', name='Captain Rowan', title='Thornford Watch', mapIcon='trainer', level=10, model='warden', rig='warden', tint='#a4bdc2', dialogue='tf_rowan'),
             dict(id='tf_elsie', name='Elsie Reed', title='Lantern Inn', mapIcon='innkeeper', level=8, model='innkeeper', rig='warden', tint='#c9b4a1', shop='tf_inn', innkeeper=True, bedPrice=2, dialogue='tf_elsie'),
             dict(id='tf_iren', name='Iren Holt', title='Smith', mapIcon='blacksmith', level=10, model='mara', rig='warden', shop='tf_forge', forge=True, dialogue='tf_iren'),
             dict(id='tf_scout', name='Scout Fen', title='Briarwood Watch', level=6, model='tam', rig='warden', tint='#a3b892', dialogue='tf_scout')],
    'enemies': [dict(id='tf_revenant', base='ghoul', name='Lantern-road Revenant', level=1, detection=7, respawn=90),
                dict(id='tf_wolf', base='hound', name='Briarwood Wolf', level=2, pack=0, detection=7, respawn=100),
                dict(id='tf_sentry', base='ghoul', name='Fallen Watch Sentry', level=2, detection=7, respawn=120),
                dict(id='tf_keeper', base='brute', name='The Bellkeeper', level=3, detection=8, respawn=240)],
    'quests': [
        quest('tf_lanterns', 'Where the Lanterns Went Out', 'tf_rowan',
              'Follow the lantern road north, examine the fallen watch lantern and defeat three revenants. Return to Captain Rowan in Thornford.',
              "The watch carried lanterns up the north road last night. None came home. Find their fallen lantern by the cart and put three of those dead things to rest. Come back here when it is done.",
              [examine('lantern', 'tf_cairn', 'Examine the fallen lantern'), kill('dead', 'tf_revenant', 3, 'Road revenants defeated', 'tf_cairn')],
              dict(coins=25, xp=260, items=[dict(item='healing_draught', count=2)]), autoAccept=True,
              complete="The lantern glass is cold. Rowan turns it over in his hands. 'They reached the old watch. Speak to Fen in Briarwood before you go after them.'"),
        quest('tf_briar', 'The Way Through Briarwood', 'tf_scout',
              'Clear three Briarwood wolves and survey Wolf Hollow. The woodland path loops back to the watch road.',
              "The wolves have taken the hollow south of this camp. Clear three and look over the hollow. Its eastern path will put you back on the watch road, below the ruins.",
              [kill('wolves', 'tf_wolf', 3, 'Briarwood wolves defeated', 'tf_hollow'), examine('hollow', 'tf_hollow', 'Survey Wolf Hollow')],
              dict(coins=20, xp=400, items=[dict(item='tool_pack', count=1)]), ['tf_lanterns']),
        quest('tf_bell', 'The Silent Watch', 'tf_rowan',
              'Find the Old Watch Ruins, defeat the Bellkeeper and visit Dawnstone Shrine. Return to Captain Rowan.',
              "Fen has opened the western loop. Now take the road north to the broken watchtower. The Bellkeeper is still there, though no living hand rings that bell. End his watch, then climb to Dawnstone Shrine and tell me what you found.",
              [examine('ruins', 'tf_watch', 'Search the Old Watch Ruins'), kill('keeper', 'tf_keeper', 1, 'The Bellkeeper defeated', 'tf_watch'), examine('shrine', 'tf_shrine', 'Visit Dawnstone Shrine')],
              dict(coins=40, xp=400, items=[dict(item='iron_shield', count=1)]), ['tf_briar'], setsFlag='tf_reach_safe',
              complete="For the first time in days, birds call along the north road. Rowan sets a shield on the table. 'The Reach has a road again. And now it has a Warden.'"),
        quest('tf_herbs', 'Something for the Road', 'tf_elsie',
              'Gather three ditchbell flowers beside the Briarwood path and bring them to Elsie at the Lantern Inn.',
              "Blue ditchbell grows along the western woodland path. Bring me three sprigs. You need no training to pick those marked patches, and I will brew something useful for your pack.",
              [dict(id='herbs', type='collect', target='ditchbell', count=3, label='Ditchbell flowers', location='tf_camp')],
              dict(coins=10, xp=100, items=[dict(item='healing_draught', count=1)])),
    ],
    'dialogues': []
}
for i, text in [('tf_rowan', 'Welcome to Thornford, Warden. The north road needs a steady hand. Keep the lanterns on your left and you will find your way back.'),
                ('tf_elsie', 'A bed, a hot meal, and a little light in the windows. That is what I can offer. Set your home here before you take the woodland road.'),
                ('tf_iren', 'The forge is hot. I can mend what the woods have bitten and sell you something that bites back.'),
                ('tf_scout', 'Thornford lies east. Wolf Hollow is south. Follow its eastern path to rejoin the watch road; you do not need to cut through the thickets.')]:
    content['dialogues'].append(dict(id=i, greetings=[dict(text=text)], topics=[], nodes=[]))
# Use the existing authoring tables, so every quest, NPC and enemy remains
# editable through Game Data. The recipe lives with the tools, not autoloads.
for file_name, table in [('npcs', 'npcs'), ('enemies', 'enemies'), ('quests', 'quests'), ('dialogue', 'dialogues')]:
    content_path = Path('data') / read(Path('data/catalogue.json'))['files'][file_name]
    d = read(content_path)
    d[table] = [r for r in d[table] if not r['id'].startswith('tf_')] + content[table]
    write(content_path, d)
d = read(Path('data/npcs/shops.json'))
shops = []
for source, ident, name in [('ford_inn', 'tf_inn', 'The Lantern Inn'), ('mara_forge', 'tf_forge', "Iren's Forge")]:
    shop = next(s for s in d['shops'] if s['id'] == source).copy()
    shop.update(id=ident, name=name)
    shops.append(shop)
d['shops'] = [s for s in d['shops'] if not s['id'].startswith('tf_')] + shops
content['shops'] = shops
write(Path('data/npcs/shops.json'), d)
d = read(Path('data/world/world.json'))
d['locations'] = [r for r in d['locations'] if not r['id'].startswith('tf_')] + content['locations']
write(Path('data/world/world.json'), d)
d = read(Path('data/ui/text.json'))
for i, _, _, _, note in places:
    d['examine']['poi:' + i] = note
write(Path('data/ui/text.json'), d)
write(Path('docs/thornford-content.json'), content)
print(f'Thornford: {len(edited)} terrain tiles updated; {trees} trees; {len(s["props"])} total props; 4 quests. Existing objects retained.')
