#!/usr/bin/env python3
"""Town life on the new map (Dan, 2026-11-11: "background NPCs, people
drinking, shopping, out travelling, wandering merchants etc. More life").

Writes data/terrain/new_map/town_life.json (npcSpawns only) and names it in
map.json `overlays`, so the game adds these people to the hand-placed
spawns.json without touching it. Re-run after the towns or roads change;
`--remove` takes them all away again.

Every inn on the map (a spawns.json building with `rest`) gets:
- DRINKERS inn regulars (npcs.json life_drinker, routine `drinker`): a seat
  in the inn most of the day, a breath of air by the door now and then.
- SHOPPERS townsfolk (life_shopper) who go round the shop fronts of their
  town (anyone with a shop, forge or bank within SHOP_RANGE of the inn),
  stop at the inn for a meal and go home at night. Their timetable is
  their own (the spawn's `routine` and `places`).
Roads (spawns.json `roads`, the wm_road_* between towns) are joined into
routes from one inn town to another (up to MAX_HOPS roads, at most
MAX_ROUTE m); each of the ROUTES shortest gets a traveller (life_traveller)
and every other one a pedlar too (life_pedlar, who sells from a pack). They
walk the spawn's `path` back and forth (Npcs.walk_road).

Each person is a spawn of a shared npcs.json entry with its own `person` id
and name (Layout), so nothing here needs a hand-made npcs.json entry.

    python3 tools/world/new_map/town_life.py [--remove]

Then move anyone left on blocked ground (inside a wall, on a cliff) onto
open ground, which needs the game's terrain (run_tests checks it):

    godot --headless --path . --script res://tools/world/new_map/town_life_ground.gd
"""
import json, math, sys, heapq
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIR = ROOT / "data/terrain/new_map"
MAP = DIR / "map.json"
OVERLAY = DIR / "town_life.json"
SPAWNS = DIR / "spawns.json"
NPCS = ROOT / "data/npcs/npcs.json"

DRINKERS = 2
SHOPPERS = 2
SHOP_RANGE = 60.0
SERVICES = ("shop", "forge", "banker", "jeweller", "refiner")
TOWN_RANGE = 30.0     # a road end this close to an inn is in its town
JOIN = 4.0            # road ends this close are the same crossing
MAX_HOPS = 3
MAX_ROUTE = 700.0
ROUTES = 12
STEP = 3.0            # keep a path point every STEP m or so

FEMALE = ["Cara", "Elda", "Gilda", "Isolde", "Kestrel", "Lisbet", "Nan", "Pella", "Rosa", "Tilda", "Vera", "Yanna",
          "Bess", "Dilys", "Fay", "Hilde", "Jess", "Lorna", "Mabyn", "Orla", "Sela", "Una", "Ada", "Cress"]
MALE = ["Aldo", "Bryn", "Dunstan", "Fenn", "Hob", "Jory", "Merrick", "Osgar", "Quill", "Sim", "Ulric", "Wat",
        "Abner", "Col", "Edric", "Garth", "Ivo", "Kit", "Ned", "Piers", "Rufus", "Tobias", "Wynn", "Bram"]
FEMALE_MODELS = ("mara", "innkeeper")  # the bodies' look; tam and warden read as men
LAST = ["Ashdown", "Barley", "Cobb", "Dunmore", "Fallow", "Greaves", "Hatch", "Ivers", "Kettle", "Linden",
        "Marsh", "Nettles", "Oakes", "Pike", "Reed", "Sallow", "Thatcher", "Underhill", "Wick", "Yarrow"]
TINTS = ["#8a6a4a", "#6a5a4a", "#7a6a5a", "#5a6a5a", "#7a5a4a", "#6a6a7a", "#8a7a5a", "#5a5a6a",
         "#7a7a6a", "#6a4a3a", "#5a6a4a", "#8a6a5a"]
MODELS = {"life_drinker": ["tam", "mara", "tam"], "life_shopper": ["mara", "tam", "mara"],
          "life_traveller": ["tam", "warden", "mara"], "life_pedlar": ["innkeeper"]}
DIALOGUES = {"life_drinker": 3, "life_shopper": 3, "life_traveller": 3, "life_pedlar": 2}

out = []
used_names = set()
count = {}


def r2(v):
    return round(v, 1)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def name_for(i, model):
    first = FEMALE if model in FEMALE_MODELS else MALE
    for k in range(len(first) * len(LAST)):
        n = "%s %s" % (first[(i * 7 + k) % len(first)], LAST[(i * 3 + k * 5) % len(LAST)])
        if n not in used_names:
            used_names.add(n)
            return n
    return "Stranger %d" % i


def person(kind, slug, position, facing=0, **extra):
    i = count.get(kind, 0)
    count[kind] = i + 1
    n = len(out)
    model = MODELS[kind][n % len(MODELS[kind])]
    sp = {"npc": kind, "person": "%s_%s_%d" % (kind, slug, i + 1), "name": name_for(n, model),
          "position": [r2(position[0]), r2(position[1])], "facing": round(facing) % 360,
          "model": model, "tint": TINTS[(n * 5) % len(TINTS)],
          "dialogue": "%s_%d" % (kind, n % DIALOGUES[kind] + 1)}
    sp.update(extra)
    out.append(sp)


def inn_door(b):
    """[x, z] just outside the inn's door, and which way is out (Npcs.inn_door)"""
    hw, hd = b["size"][0] / 2, b["size"][1] / 2
    sides = {"n": [], "s": [], "w": [], "e": []}
    for s in b.get("walls", []) if isinstance(b.get("walls"), list) else []:
        if s[0] == s[2]:
            sides["w" if s[0] < 0 else "e"].append(sorted([s[1], s[3]]))
        elif s[1] == s[3]:
            sides["n" if s[1] < 0 else "s"].append(sorted([s[0], s[2]]))
    c = b["position"]
    for k, runs in sides.items():
        if len(runs) < 2:
            continue
        runs.sort()
        m = (runs[0][1] + runs[1][0]) / 2
        return {"w": ([c[0] - hw - 1.6, c[1] + m], (-1, 0)), "e": ([c[0] + hw + 1.6, c[1] + m], (1, 0)),
                "n": ([c[0] + m, c[1] - hd - 1.6], (0, -1)), "s": ([c[0] + m, c[1] + hd + 1.6], (0, 1))}[k]
    return [c[0], c[1] + hd + 1.6], (0, 1)


def facing_to(a, b):
    """degrees, Npc convention: atan2(dx, dz)"""
    return math.degrees(math.atan2(b[0] - a[0], b[1] - a[1]))


def town_life(spawns, npcs):
    inns = [b for b in spawns["buildings"] if b.get("rest")]
    for b in inns:
        slug = b["id"].replace("wm_", "").replace("_rest_house", "").replace("_inn", "")
        door, out_dir = inn_door(b)
        side = (-out_dir[1], out_dir[0])
        for k in range(DRINKERS):
            o = (k - (DRINKERS - 1) / 2) * 2.4
            at = [door[0] + out_dir[0] * 1.5 + side[0] * o, door[1] + out_dir[1] * 1.5 + side[1] * o]
            person("life_drinker", slug, at, facing_to(at, door) + 180)
        # the shop fronts of the town: 1.8 m in front of each keeper, facing them
        fronts = []
        for sp in spawns["npcSpawns"]:
            n = npcs.get(sp["npc"], {})
            if not any(n.get(k) for k in SERVICES) or dist(sp["position"], b["position"]) > SHOP_RANGE:
                continue
            f = math.radians(sp.get("facing", n.get("facing", 0)))
            at = [sp["position"][0] + math.sin(f) * 1.8, sp["position"][1] + math.cos(f) * 1.8]
            fronts.append([r2(at[0]), r2(at[1]), round(facing_to(at, sp["position"])) % 360])
        fronts.sort(key=lambda q: dist(q, b["position"]))
        fronts = fronts[:3]
        for k in range(SHOPPERS):
            # loitering spot: out in front of the inn, a few metres off the door
            o = 5.0 + 2.5 * k
            at = [door[0] + out_dir[0] * o + side[0] * (3 - 6 * k), door[1] + out_dir[1] * o + side[1] * (3 - 6 * k)]
            if not fronts:
                person("life_shopper", slug, at, facing_to(at, door), routine="townsfolk")
                continue
            names = ["stall_%d" % (i + 1) for i in range(len(fronts))]
            order = [names[(k + i) % len(names)] for i in range(4)]
            # out and about all day: a stall, the next, a sit at the inn, round again
            blocks = [{"from": 7.0 + k * 0.5, "at": "work"}, {"from": 8.0 + k * 0.5, "at": order[0]},
                      {"from": 9.0 + k * 0.5, "at": order[1]}, {"from": 10.0 + k * 0.5, "at": "work"},
                      {"from": 11.0 + k * 0.5, "at": order[2]}, {"from": 12.0, "at": "inn"},
                      {"from": 13.5 + k * 0.5, "at": order[3]}, {"from": 14.5 + k * 0.5, "at": "work"},
                      {"from": 15.5 + k * 0.5, "at": order[0]}, {"from": 16.5 + k * 0.5, "at": order[1]},
                      {"from": 17.5, "at": "work"}, {"from": 18.5 + k * 0.5, "at": "inn"},
                      {"from": 20.5 + k * 0.5, "at": "home"}]
            person("life_shopper", slug, at, facing_to(at, door), routine=blocks,
                   places={nm: q for nm, q in zip(names, fronts)})
    roads_between_towns(spawns, inns)


def roads_between_towns(spawns, inns):
    roads = [r for r in spawns["roads"] if r["id"].startswith("wm_road_") and len(r["points"]) >= 2]
    # crossings: road ends joined within JOIN m
    nodes = []

    def node(p):
        for i, q in enumerate(nodes):
            if dist(p, q) <= JOIN:
                return i
        nodes.append(p)
        return len(nodes) - 1

    edges = {}
    for r in roads:
        a, b = node(r["points"][0]), node(r["points"][-1])
        length = sum(dist(r["points"][i], r["points"][i + 1]) for i in range(len(r["points"]) - 1))
        edges.setdefault(a, []).append((b, length, r["points"]))
        edges.setdefault(b, []).append((a, length, r["points"][::-1]))
    town_of = {}
    for i, p in enumerate(nodes):
        best = min(inns, key=lambda b: dist(p, b["position"]))
        if dist(p, best["position"]) <= TOWN_RANGE:
            town_of[i] = best["id"]
    routes = {}
    for start in town_of:
        # shortest ways out of town to another town, MAX_HOPS roads at most
        heap = [(0.0, 0, start, [])]
        seen = set()
        while heap:
            d, hops, at, pts = heapq.heappop(heap)
            if (at, hops) in seen or d > MAX_ROUTE:
                continue
            seen.add((at, hops))
            if at != start and at in town_of and town_of[at] != town_of[start]:
                key = tuple(sorted([town_of[start], town_of[at]]))
                if key not in routes or routes[key][0] > d:
                    routes[key] = (d, pts)
                continue
            if hops >= MAX_HOPS:
                continue
            for to, length, p in edges.get(at, []):
                heapq.heappush(heap, (d + length, hops + 1, to, pts + (p if not pts else p[1:])))
    picked = sorted(routes.items(), key=lambda kv: kv[1][0])[:ROUTES]
    for i, (key, (d, pts)) in enumerate(picked):
        path = [pts[0]]
        for p in pts[1:]:
            if dist(p, path[-1]) >= STEP:
                path.append(p)
        if path[-1] != pts[-1]:
            path.append(pts[-1])
        path = [[r2(p[0]), r2(p[1])] for p in path]
        slug = "%d" % (i + 1)
        person("life_traveller", "road" + slug, path[0], path=path)
        if i % 2 == 0:
            person("life_pedlar", "road" + slug, path[-1], path=path[::-1])


def main():
    meta = json.loads(MAP.read_text())
    overlays = [o for o in meta.get("overlays", []) if o != OVERLAY.name]
    if "--remove" in sys.argv:
        OVERLAY.unlink(missing_ok=True)
    else:
        spawns = json.loads(SPAWNS.read_text())
        npcs = {n["id"]: n for n in json.loads(NPCS.read_text())["npcs"]}
        for n in npcs.values():
            used_names.add(n["name"])
        town_life(spawns, npcs)
        doc = {"_about": "Generated by tools/world/new_map/town_life.py (do not edit by hand: change the script and re-run). "
                         "Background town life: inn regulars, shoppers, road travellers and pedlars; map.json `overlays` adds these to spawns.json's in the game.",
               "spawns": {"npcSpawns": out}}
        OVERLAY.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n")
        overlays.append(OVERLAY.name)
    if overlays:
        meta["overlays"] = overlays
    else:
        meta.pop("overlays", None)
    MAP.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    print("town life:", count, "people", len(out))


if __name__ == "__main__":
    main()
