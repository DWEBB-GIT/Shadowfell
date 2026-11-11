#!/usr/bin/env python3
"""The test hub city on the new map (Dan, 2026-11-10; plan:
/mnt/project-files/design/hub-city/hub-city-plan.html).

Writes data/terrain/new_map/hub_city.json (houses, walls, gates, roads,
water, stations, NPCs, dummies, the flat pad, a map marker, props, lamps) and
names it in map.json `overlays`, so the game adds it to the hand-placed
spawns.json/scenery.json without touching them. Re-run after a change;
`--remove` takes the city away again.

The city is a 165 m square turned 45 degrees: local (u, v) metres, u running
south-east and v south-west on the map, so every street and building reads
on the diagonal from the fixed camera (Dan, 2026-11-10). Nine 55 m districts
on a 3 x 3 grid; the Grand Gate is on the south-west face, the river runs
outside the south-east wall.

    python3 tools/world/new_map/hub_city.py [--remove]
"""
import json, math, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MAP = ROOT / "data/terrain/new_map/map.json"
OVERLAY = ROOT / "data/terrain/new_map/hub_city.json"

CX, CZ = -180.0, -656.0   # open rillbank meadow, ~200 m from any placed content
GROUND = 3.0              # the meadow's height there (flat to 0.2 m)
WATER = GROUND - 0.3
HALF = 82.5               # half the wall's side
CELL = 55.0
TURN = -45                # house rotation: its length along u
K = math.sqrt(0.5)
START_STONE = (-600.0, -172.0)  # by the new-character start (-617, -182)


def w(u, v):
    """local (u, v) -> world [x, z]"""
    return [round(CX + K * (u - v), 2), round(CZ + K * (u + v), 2)]


out = {k: [] for k in ["houses", "townWalls", "gates", "roads", "water", "stations", "npcSpawns",
                       "enemySpawns", "signposts", "pois", "subzones"]}
props, lights = [], []
n = 0
_rects, _segs = [], []  # in local (u, v): house footprints, street capsules (for overlap()))


def nid(kind):
    global n
    n += 1
    return f"hub_{kind}_{n}"


def house(name, u, v, size, roof="slate", walls="stone", storeys=1, tower=False, chimney=False, turn=TURN):
    _rects.append((name, u - size[0] / 2, v - size[1] / 2, u + size[0] / 2, v + size[1] / 2))
    h = {"id": "hub_" + name, "position": w(u, v), "size": size, "roof": roof, "walls": walls, "rotation": turn, "door": "s"}
    if storeys > 1:
        h["storeys"] = storeys
    if tower:
        h["tower"] = True
    if chimney:
        h["chimney"] = True
    out["houses"].append(h)


def road(name, pts, half=3.0, kind="road"):
    for a, b in zip(pts, pts[1:]):
        _segs.append((name, a, b, half))
    out["roads"].append({"id": nid("road"), "name": name, "kind": kind, "halfWidth": half, "points": [w(*p) for p in pts]})


def prop(model, u, v, rot=0, scale=1.0):
    props.append({"id": nid("prop"), "model": model, "position": w(u, v), "rotation": rot + 45, "scale": scale})


def lamp(u, v):
    prop("lamp_post", u, v)
    x, z = w(u, v)
    lights.append({"id": nid("light"), "position": [x, z], "height": 2.6, "intensity": 2.4, "distance": 10, "color": "#ffd19a", "flicker": True})


def npc(id_, u, v, facing=225):
    out["npcSpawns"].append({"npc": id_, "position": w(u, v), "facing": facing})


def build():
    H, C = HALF, CELL
    s = C / 2  # 27.5: the ring streets between the districts
    g, gg = 4.0, 5.0  # half a gate's width; the Grand Gate's
    # --- walls (stone). Gates at the ends of ring streets (north, west), the
    # Grand Gate on Kings' Way, the water gate onto the docks' piers
    lines = [
        [(-H, -H), (s - g, -H)], [(s + g, -H), (H, -H)],                # north-east face (v = -H)
        [(H, -H), (H, -C - 6)], [(H, -C + 6), (H, H)],                  # south-east face
        [(H, H), (gg + 4, H)], [(-gg - 4, H), (-H, H)],                 # south-west face
        [(-H, H), (-H, s + g)], [(-H, s - g), (-H, -H)],                # north-west face
    ]
    out["townWalls"].append({"id": "hub_walls", "name": "the city walls", "kind": "wall", "style": "stone",
                             "lines": [[w(*a), w(*b)] for a, b in lines]})
    out["gates"] += [
        {"id": "hub_grand_gate", "name": "the Grand Gate", "kind": "city_gate", "line": [w(-gg, H), w(gg, H)]},
        {"id": "hub_north_gate", "name": "the north gate", "kind": "town_gate", "line": [w(s - g, -H), w(s + g, -H)]},
        {"id": "hub_west_gate", "name": "the west gate", "kind": "town_gate", "line": [w(-H, s - g), w(-H, s + g)]},
        {"id": "hub_water_gate", "name": "the water gate", "kind": "town_gate", "line": [w(H, -C - 6), w(H, -C + 6)]},
    ]
    # --- streets: the ring between districts, one through each district
    for a in (-s, s):
        road("City street", [(a, -H), (a, H)], 2.6)
        road("City street", [(-H, a), (H, a)], 2.6)
    road("North road", [(s, -H), (s, -H - 18)], 2.6)
    road("West road", [(-H, s), (-H - 18, s)], 2.6)
    road("Crown Square", [(-6, 0), (6, 0)], 13.0)
    road("Kings' Way", [(0, 12), (0, H + 12)], 4.2)
    road("The King's Road", [(0, H + 12), (0, H + 45)], 3.4)
    road("Guild Row", [(-s, -C), (s, -C)], 2.6)
    road("Dock Lane", [(s, -C), (H + 10, -C)], 2.6)
    road("Market Street", [(s, 0), (H - 3, 0)], 3.2)
    road("Artisans' Lane", [(-C, -s), (-C, s)], 2.6)
    road("Cathedral Close", [(-C, -s), (-C, -38)], 3.0)
    road("Lantern Lane", [(-H + 3, C), (-s, C)], 2.2, "lane")
    road("Drill yard", [(36, 47), (70, 47)], 9.0, "track")
    # --- water: the river outside the south-east wall; a canal off it along
    # the market (a gap halfway is the bridge); the square's fountain
    for v in range(-110, 111, 11):
        out["water"].append({"id": nid("river"), "name": "the city river", "position": w(H + 15, v), "radius": 10,
                             "fishTable": "mere_fish", "fishLevel": 1, "color": "#4f7f96", "level": WATER})
    for u in [33, 37, 41, 45, 49, 61, 65, 69, 73, 77]:
        out["water"].append({"id": nid("canal"), "name": "the canal", "position": w(u, 9.0), "radius": 2.4,
                             "fishTable": "mere_fish", "fishLevel": 1, "color": "#4f7f96", "level": WATER})
    out["water"].append({"id": "hub_fountain", "name": "the Crown fountain", "position": w(0, 0), "radius": 4.5,
                         "color": "#6a9bb3", "level": WATER})
    # --- Crown Square: town hall on its north side, bank, general goods
    house("town_hall", 0, -19, [20, 9], roof="tile", storeys=2, tower=True)
    house("bank", -18, 18, [9, 7], roof="slate", storeys=2)
    house("general_goods", 18, 18, [9, 7], roof="tile", walls="timber", chimney=True)
    for (u, v) in [(-11, -10), (11, -10), (-11, 10), (11, 10)]:
        lamp(u, v)
    prop("waymarker", 7, 6)
    # --- Cathedral Close (north): the cathedral, its walled cemetery behind
    house("cathedral", -C, -50, [30, 12], roof="slate", storeys=3, tower=True)
    for i in range(8):
        for j in range(3):
            prop("grave0" if (i + j) % 2 else "grave1", -74 + i * 5.2, -76 + j * 4.5)
    for k in range(14):
        prop("fence", -77 + k * 3.0, -61.5, rot=90)
    prop("standing_stone", -36, -72, scale=0.8)
    # --- Guild Row (north-east): six class halls either side of the street
    for i, cls in enumerate(["warrior", "paladin", "priest", "sorcerer", "rogue", "ranger"]):
        house(f"guild_{cls}", [-17, 0, 17][i % 3], -63 if i < 3 else -47, [13, 9],
              roof=["tile", "slate", "slate", "slate", "thatch", "thatch"][i], storeys=2, chimney=i % 2 == 0)
    # --- Riverside Docks (east): warehouses for future vendors, fishmonger, piers
    house("warehouse_1", 47, -66, [14, 8], roof="tile", walls="timber")
    house("warehouse_2", 47, -44, [14, 8], roof="tile", walls="timber")
    house("fishmonger", 70, -68, [7, 6], roof="thatch", walls="timber", chimney=True)
    for v in (-C - 9, -C + 9):
        prop("res://assets/scenery/PondDock.tscn", H + 8, v, rot=90, scale=1.4)
    for i in range(4):
        prop("crate", 66 + i * 1.3, -45, rot=i * 20)
    # --- Artisans' Quarter (west): smithy, jeweller, refinery, runewright, stations
    house("smithy", -69, -15, [10, 8], roof="slate", chimney=True)
    house("jeweller", -41, -15, [8, 7], roof="tile", walls="plaster")
    house("refinery", -69, 15, [8, 7], roof="slate")
    house("runewright", -41, 15, [8, 7], roof="slate", tower=True)
    out["stations"] += [
        {"id": "hub_forge", "name": "the city forge", "kind": "forge", "position": w(-63, -4), "radius": 3},
        {"id": "hub_refining_altar", "name": "the city refining altar", "kind": "refining", "position": w(-63, 5), "radius": 2.6},
        {"id": "hub_rune_forge", "name": "the runewright's forge", "kind": "runeforge", "position": w(-47, 5), "radius": 2.6},
        {"id": "hub_alchemy", "name": "the city alchemy bench", "kind": "alchemy", "model": "crate", "position": w(-47, -4), "radius": 2.6},
        {"id": "hub_hearth", "name": "the artisans' hearth", "kind": "fire", "position": w(-47, -23), "radius": 2.6},
    ]
    prop("anvil", -66, -7)
    npc("hub_smith", -61, -9)
    npc("hub_jeweller", -49, -9)
    npc("hub_refiner", -61, 9)
    # --- Market Street (east of the square): the Market Hall, stalls past the canal
    house("market_hall", 55, -14, [26, 13], roof="tile", storeys=2)
    for i, u in enumerate([40, 52, 64]):
        prop("awning", u, 17)
        prop("crate", u + 2, 19, rot=i * 30)
    prop("cart", 75, 18, rot=90)
    # --- Lantern Lane (west corner): houses and empty shops to let
    for i, u in enumerate([-70, -55, -40]):
        for j, v in enumerate((44, 66)):
            house(f"lane_{i}_{j}", u, v, [10, 7], roof=["thatch", "tile", "slate"][(i + j) % 3],
                  walls=["timber", "plaster"][(i + j) % 2], chimney=(i + j) % 2 == 0)
        lamp(u + 6, 58)
    # --- Kings' Way and the Grand Gate (south-west): the inn, shopfronts to let
    house("gilded_stag", 15, 45, [14, 10], roof="tile", walls="timber", storeys=2, chimney=True)
    house("shopfront_w_0", -14, 45, [10, 7], roof="tile", walls="plaster")
    house("shopfront_w_1", -14, 64, [10, 7], roof="slate", walls="timber")
    house("shopfront_e_0", 14, 64, [10, 7], roof="slate", walls="plaster")
    npc("hub_innkeeper", 6.5, 42)
    for v in (34, 54, 72):
        lamp(-6, v)
        lamp(6, v)
    npc("hub_gate_guard", -6, 76, 45)
    npc("hub_gate_guard_2", 6, 76, 45)
    # --- The Garrison (south): barracks, watchtower, armoury, the drill yard
    house("barracks", 60, 70, [20, 9], roof="slate", storeys=2)
    house("watchtower", 76, 76, [6, 6], roof="slate", storeys=3, tower=True)
    house("armoury", 38, 70, [9, 7], roof="slate")
    npc("hub_captain", 48, 59)
    dummies = ["training_dummy", "training_dummy_10", "training_dummy_20", "training_dummy_40"]
    for i, enemy in enumerate(dummies):
        for j in range(2):
            out["enemySpawns"].append({"id": f"hub_dummy_{i}_{j}", "enemy": enemy, "position": w(38 + i * 8, 42 + j * 6)})
    out["enemySpawns"].append({"id": "hub_dummy_armoured", "enemy": "training_dummy_armoured", "position": w(72, 45)})
    for k in range(3):
        prop("waymarker", 79, 33 + k * 5, scale=0.9)  # archery butts (stand-ins)
    # --- waystones: one by the start, one inside the Grand Gate
    sx, sz = START_STONE
    out["stations"] += [
        {"id": "hub_waystone_start", "name": "the waystone", "kind": "waystone", "position": [sx, sz], "radius": 2.4,
         "to": w(0, 70), "toName": "the hub city", "toFacing": 315},
        {"id": "hub_waystone_city", "name": "the city waystone", "kind": "waystone", "position": w(-9, 74), "radius": 2.4,
         "to": [sx + 3, sz + 2], "toName": "Abel's broken cart", "toFacing": 100},
    ]
    out["pois"].append({"id": "hub_city", "name": "The Hub City (test)", "kind": "town", "at": w(0, 0),
                        "note": "A test hub: walled river city with guild halls, market, artisans, cathedral and garrison."})
    out["subzones"].append({"id": "hub_city", "name": "The Hub City", "at": w(0, 0), "radius": 115})


def overlaps():
    """Houses that sit on a street or on each other (printed; the layout should have none)."""
    def seg_rect(a, b, r):
        best = 1e9
        for i in range(21):
            f = i / 20
            x, y = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
            dx = max(r[1] - x, 0, x - r[3])
            dy = max(r[2] - y, 0, y - r[4])
            best = min(best, math.hypot(dx, dy))
        return best
    bad = []
    for r in _rects:
        for s in _segs:
            if s[3] > 0 and seg_rect(s[1], s[2], r) < s[3] + 0.5:
                bad.append(f"{r[0]} on {s[0]}")
        for q in _rects:
            if q[0] < r[0] and not (q[3] + 1 < r[1] or r[3] + 1 < q[1] or q[4] + 1 < r[2] or r[4] + 1 < q[2]):
                bad.append(f"{r[0]} on {q[0]}")
        if max(abs(r[1]), abs(r[3]), abs(r[2]), abs(r[4])) > HALF - 2:
            bad.append(f"{r[0]} on the wall")
    return bad


def main():
    meta = json.loads(MAP.read_text())
    overlays = [o for o in meta.get("overlays", []) if o != OVERLAY.name]
    if "--remove" in sys.argv:
        OVERLAY.unlink(missing_ok=True)
    else:
        build()
        spawns = {k: v for k, v in out.items() if v}
        spawns["pads"] = [[CX, CZ, 140.0]]
        doc = {"_about": "Generated by tools/world/new_map/hub_city.py (do not edit by hand: change the script and re-run). "
                         "The test hub city; map.json `overlays` adds these lists to spawns.json's and scenery.json's in the game.",
               "spawns": spawns, "scenery": {"props": props, "lights": lights}}
        OVERLAY.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n")
        overlays.append(OVERLAY.name)
    if overlays:
        meta["overlays"] = overlays
    else:
        meta.pop("overlays", None)
    MAP.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    for b in overlaps():
        print("OVERLAP:", b)
    print("hub city:", {k: len(v) for k, v in out.items()}, "props", len(props), "lights", len(lights))


if __name__ == "__main__":
    main()
