"""Bake the approved Lantern Coast atlas into native Godot terrain packs.

First run: python bake_terrain.py --atlas <lantern-coast.html>
Subsequent runs: edit layout.json and run python bake_terrain.py.
Requires NumPy and Pillow. Coordinates in layout.json are in metres.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from paint_tiles import write_tiles

ROOT = Path(__file__).resolve().parent
CHUNK = 64
STEP = 2
SIDE = CHUNK // STEP + 3
ROAD_STEP = 0.5
ROAD_SIDE = int(CHUNK / ROAD_STEP) + 5
BOUNDS = (-960, -544, 960, 576)
HUBS = {
    # height, flat radius, biome colour, terrain pack
    "oat": (4, 58, "80934e", "west"), "bell": (5, 35, "859160", "west"),
    "gloam": (8, 19, "4f7046", "west"), "flint": (19, 30, "887c56", "flintcut"),
    "reed": (4, 33, "687f47", "reedmire"), "iron": (31, 22, "837c63", "ironstep"),
    "ash": (15, 68, "929753", "lowlands"), "tide": (5, 30, "819074", "lowlands"),
    "gate": (12, 31, "9c9463", "lowlands"), "red": (8, 58, "b18454", "redwash"),
    "cinder": (24, 34, "64534e", "cinder"), "white": (58, 32, "d2e0e5", "whitehorn"),
    "salt": (6, 59, "c4b893", "saltglass"), "star": (5, 23, "7f9473", "starfall"),
    "crown": (44, 31, "696267", "crown"),
}


def metres(x, z):
    return [(x - 500) * 2, (z - 286) * 2]


def read_svg_path(path):
    """Read the atlas subset of M, L, Q, T and Z and sample curves."""
    tokens = re.findall(r"[MLQTZ]|-?\d+(?:\.\d+)?", path)
    lines, line, last, control, op = [], [], None, None, "M"
    while tokens:
        if tokens[0].isalpha():
            op = tokens.pop(0)
        if op == "Z":
            if line:
                lines.append(line)
            line, last, control = [], None, None
            continue
        point = np.array([float(tokens.pop(0)), float(tokens.pop(0))])
        if op == "M":
            if line:
                lines.append(line)
            line, last, control, op = [metres(*point)], point, None, "L"
            continue
        if op in ("Q", "T"):
            if op == "Q":
                c = point
                point = np.array([float(tokens.pop(0)), float(tokens.pop(0))])
            else:
                c = 2 * last - control if control is not None else last
            count = max(4, int((np.linalg.norm(c - last) + np.linalg.norm(point - c)) / 5))
            for t in np.linspace(0, 1, count + 1)[1:]:
                line.append(metres(*((1 - t)**2 * last + 2 * (1 - t) * t * c + t*t * point)))
            control = c
        else:
            line.append(metres(*point))
            control = None
        last = point
    if line:
        lines.append(line)
    return lines


def make_layout(atlas):
    html = atlas.read_text(encoding="utf-8")
    names = dict(re.findall(r'<option value="([^"]+)">([^<]+)</option>', html))
    routes, centres = [], {}
    for classes, a, b, attributes, path in re.findall(
        r'<path class="(route[^"]*)" data-link="(\w+) (\w+)"([^>]*) d="([^"]+)"', html
    ):
        points = read_svg_path(path)[0]
        centres[a], centres[b] = points[0], points[-1]
        label = re.search(r'data-passage="([^"]+)"', attributes)
        routes.append(dict(a=a, b=b, points=points, ferry="ferry" in classes,
                           half=3.5 if "trail" in classes else 5.0,
                           name=label[1] if label else ""))
    islands = re.search(r'<path id="lc-islands" d="([^"]+)"', html)[1]
    coast = re.search(r'<path id="lc-coastline" d="([^"]+)"', html)[1]
    hub_list = [dict(id=key, name=names[key], point=centres[key], height=y, radius=r,
                     colour=c, pack=pack) for key, (y, r, c, pack) in HUBS.items()]
    def line(*points):
        return [metres(*p) for p in points]
    return dict(
        bounds=BOUNDS, hubs=hub_list, routes=routes, shores=read_svg_path(coast)+read_svg_path(islands),
        waterways=[
            dict(half=6.0, points=line((65, 320), (106, 310), (150, 306), (208, 304), (246, 299), (255, 279))),
            dict(half=5.0, points=line((302, 444), (325, 401), (318, 383), (294, 366), (289, 355), (313, 339), (325, 330), (327, 315))),
        ],
        ponds=[
            dict(point=metres(127, 367), radius=12),
            dict(point=metres(356, 350), radius=13),
        ],
        ridges=[
            dict(height=23, radius=23, points=line((126, 256), (154, 252), (185, 256), (193, 246))),
            dict(height=30, radius=29, points=line((235, 157), (268, 158), (286, 171), (302, 160), (325, 149))),
            dict(height=34, radius=21, points=line((229, 260), (246, 267), (265, 288), (282, 296))),
            dict(height=36, radius=28, points=line((356, 166), (371, 182), (375, 205), (393, 225))),
            dict(height=48, radius=35, points=line((404, 231), (426, 248), (450, 248), (464, 235))),
            dict(height=43, radius=28, points=line((405, 312), (428, 316), (451, 312), (476, 324), (490, 344))),
            dict(height=34, radius=31, points=line((520, 241), (547, 252), (565, 275), (577, 294))),
            dict(height=63, radius=41, points=line((644, 111), (680, 101), (712, 80), (746, 73), (785, 96), (821, 112))),
            dict(height=52, radius=30, points=line((772, 168), (796, 170), (825, 192), (840, 216))),
            dict(height=43, radius=22, points=line((754, 230), (754, 253), (736, 273), (724, 297))),
            dict(height=41, radius=25, points=line((820, 232), (840, 267), (825, 295), (844, 314))),
            dict(height=46, radius=28, points=line((891, 138), (912, 149), (923, 178))),
            dict(height=29, radius=20, points=line((724, 404), (748, 413), (783, 414), (802, 427))),
            dict(height=29, radius=21, points=line((895, 339), (917, 349), (926, 374))),
        ],
        overlooks=[
            dict(name="Reedmire Lookout", points=line((426, 292), (421, 298), (419, 301))),
            dict(name="Saltglass Lookout", points=line((821, 194), (829, 190), (839, 198))),
        ],
    )


def smooth(lo, hi, v):
    t = np.clip((v - lo) / (hi - lo), 0, 1)
    return t*t*(3 - 2*t)


def segments(points):
    for a, b in zip(points, points[1:]):
        a, b = np.array(a), np.array(b)
        d = np.linalg.norm(b - a)
        if d > 0.001:
            yield a, b, d


def distance_to_line(x, z, points):
    distance = np.full(x.shape, 1e6, dtype=np.float32)
    progress = np.zeros_like(distance)
    total = 0.0
    for a, b, length in segments(points):
        vx, vz = b - a
        t = np.clip(((x-a[0])*vx+(z-a[1])*vz) / length**2, 0, 1)
        d = (x-a[0]-t*vx)**2 + (z-a[1]-t*vz)**2
        progress = np.where(d < distance, total + length*t, progress)
        distance = np.minimum(distance, d)
        total += length
    return np.sqrt(distance), progress, total


def at_distance(points, distance):
    for a, b, length in segments(points):
        if distance <= length:
            return a + (b-a) * max(distance, 0) / length, (b-a)/length
        distance -= length
    return b, (b-a)/length


def local_slice(x, z, points, padding):
    arr = np.asarray(points)
    low, high = arr.min(axis=0)-padding, arr.max(axis=0)+padding
    start_x, end_x = np.searchsorted(x[0], [low[0], high[0]])
    start_z, end_z = np.searchsorted(z[:, 0], [low[1], high[1]])
    return np.s_[start_z:end_z, start_x:end_x]


def signed_shore(x, z, outlines):
    inside = np.zeros(x.shape, dtype=bool)
    distance = np.full(x.shape, 1e6, dtype=np.float32)
    for outline in outlines:
        area = np.zeros_like(inside)
        for a, b, length in segments(outline + outline[:1]):
            vx, vz = b-a
            if vz != 0:
                area ^= ((a[1] > z) != (b[1] > z)) & (x < a[0] + (z-a[1])*vx/vz)
            t = np.clip(((x-a[0])*vx+(z-a[1])*vz) / length**2, 0, 1)
            distance = np.minimum(distance, (x-a[0]-t*vx)**2 + (z-a[1]-t*vz)**2)
        inside |= area
    return np.sqrt(distance) * np.where(inside, 1, -1)


def rounded_outline(points):
    rounded = []
    points = np.asarray(points)
    for i, p in enumerate(points):
        before, after = points[i-1]-p, points[(i+1) % len(points)]-p
        start = p + before * min(0.25, 13.0/max(0.1, np.linalg.norm(before)))
        end = p + after * min(0.25, 13.0/max(0.1, np.linalg.norm(after)))
        for t in np.linspace(0, 1, 5):
            rounded.append(((1-t)**2*start + 2*t*(1-t)*p + t*t*end).tolist())
    return rounded


def rounded_route(points, radius):
    """Round road corners inside the adjoining segments, with no overshoot."""
    points = np.asarray(points, dtype=float)
    result = [points[0].tolist()]
    for prev, point, next_ in zip(points, points[1:], points[2:]):
        incoming = point - prev
        outgoing = next_ - point
        before, after = np.linalg.norm(incoming), np.linalg.norm(outgoing)
        if min(before, after) < .01:
            continue
        incoming /= before
        outgoing /= after
        angle = np.arccos(np.clip(np.dot(incoming, outgoing), -1, 1))
        if angle < np.deg2rad(10):
            result.append(point.tolist())
            continue
        trim = min(before * .46, after * .46, radius)
        a, b = point - incoming * trim, point + outgoing * trim
        for t in np.linspace(0, 1, max(5, int(trim * .8))):
            result.append(((1-t)**2*a + 2*t*(1-t)*point + t*t*b).tolist())
    result.append(points[-1].tolist())
    return result


def road_width(route, progress, total):
    if "heights" in route:
        width = route.get("paint_width", 1.36)
        variation = .25*np.sin(progress*.23) + .15*np.sin(progress*.10+1.4)
    else:
        width = route.get("paint_width", 2.45 if route["half"] >= 5 else 1.54)
        variation = .39*np.sin(progress*.069) + .23*np.sin(progress*.23)
    if route.get("width_profile"):
        profile = np.asarray(route["width_profile"])
        width = np.interp(progress/max(total, .01), profile[:,0], profile[:,1])
    return np.maximum(.60, width+variation)


def road_grade(route, hubs, progress, total):
    if route.get("height_profile"):
        anchors = np.asarray(route["height_profile"])
        return np.interp(progress/max(total, .01), anchors[:,0], anchors[:,1])
    low = route.get("y0", hubs[route["a"]]["height"])
    high = route.get("y1", hubs[route["b"]]["height"])
    return low+(high-low)*smooth(0, total, progress)


def road_paint(route, d, progress, total, texture_noise):
    if route.get("lookout"):
        return (1-smooth(0.96, 2.28, d))*smooth(0, 7, progress)
    width = road_width(route, progress, total)
    walking = "heights" in route or route["half"] < 4
    ragged = texture_noise*(.29 if walking else .34)
    visible = (1-smooth(width*.55, width+(1.02 if walking else 1.18), d+ragged))
    visible *= route.get("paint", .88 if walking else 1.0)
    for start, end in route.get("paint_gaps", []):
        visible *= 1-0.83*smooth(start*total-8, start*total+5, progress)*(
            1-smooth(end*total-5, end*total+8, progress))
    return visible


def noise_at(x, z):
    return np.sin(x*.064+np.sin(z*.035))*np.cos(z*.053)+0.58*np.sin(x*.13-z*.069)


def bake_road_mask(bounds, routes, height, coarse_x, coarse_z):
    x0, z0, x1, z1 = bounds
    x, z = np.meshgrid(np.arange(x0-1, x1+1.1, ROAD_STEP, dtype=np.float32),
                       np.arange(z0-1, z1+1.1, ROAD_STEP, dtype=np.float32))
    mask = np.zeros(x.shape, dtype=np.uint8)
    for route in routes:
        points = route["points"]
        sl = local_slice(x, z, points, 8)
        d, progress, total = distance_to_line(x[sl], z[sl], points)
        visible = road_paint(route, d, progress, total, noise_at(x[sl], z[sl]))
        mask[sl] = np.maximum(mask[sl], np.uint8(visible*255))
    # The fine paint mask follows the same dry shoreline as the terrain.
    dry_columns = np.stack([np.interp(x[0], coarse_x, row) for row in height])
    for col, heights in enumerate(dry_columns.T):
        mask[:,col] = np.uint8(mask[:,col]*smooth(.1, 1.1, np.interp(z[:,0], coarse_z, heights)))
    return mask


def water_crossings(route, waterways, y0, y1):
    points = route["points"]
    total = sum(d for _, _, d in segments(points))
    t = np.arange(0, total+0.5, 1.0)
    samples = np.array([at_distance(points, p)[0] for p in t])
    near = np.zeros(len(t), dtype=bool)
    for water in waterways:
        d, _, _ = distance_to_line(*samples.T, water["points"])
        near |= d < water["half"] + 4.0
    starts = np.flatnonzero(near & ~np.r_[False, near[:-1]])
    stops = np.flatnonzero(near & ~np.r_[near[1:], False])
    out, spans = [], []
    for start, stop in zip(starts, stops):
        if stop-start < 3 or start < 15 or stop > total-15:
            continue
        start, stop = t[start]-6, t[stop]+6
        a, _ = at_distance(points, start)
        b, _ = at_distance(points, stop)
        centre = (a+b)/2
        # WASD directions at the default camera yaw land on 45° axes in XZ.
        # Align the whole deck and the short landings, then let the trail bend.
        angle = np.arctan2(*(b-a)[::-1])
        angle = np.round(angle/(np.pi/4))*(np.pi/4)
        axis = np.array([np.cos(angle), np.sin(angle)])
        across = np.array([-axis[1], axis[0]])
        along = np.arange(-72.0, 72.1, 0.5)
        lane = centre + along[:,None]*axis
        wet = np.zeros(len(lane), dtype=bool)
        for side in [-4.0, 0.0, 4.0]:
            edge = lane + across*side
            for water in waterways:
                d, _, _ = distance_to_line(*edge.T, water["points"])
                wet |= d < water["half"]+3.0
        # Use the water crossing closest to the existing road. Ignore any
        # second bend of the same river further along the new axis.
        on_water = np.flatnonzero(wet)
        if not on_water.size:
            continue
        crossing = min(np.split(on_water, np.flatnonzero(np.diff(on_water) > 1)+1),
                       key=lambda span: np.min(np.abs(along[span])))
        lo, hi = along[crossing[0]]-7, along[crossing[-1]]+7
        a, b = centre+axis*lo, centre+axis*hi
        entry, exit_ = a-axis*7, b+axis*7
        centre = (a+b)/2
        height = y0+(y1-y0)*(start+stop)/(2*total)
        name = route["name"] or f"{route['a'].title()}{route['b'].title()} Footbridge"
        if name == "Sluice Towpath":
            name = "Towpath Footbridge"
        if out:
            name += f" {len(out) + 1}"
        out.append(dict(name=name, a=a.tolist(), b=b.tolist(), point=centre.tolist(),
                        entry=entry.tolist(), exit=exit_.tolist(),
                        height=height, length=float(np.linalg.norm(b-a)), width=8.0,
                        variant=int(name != "Lantern Bridge"), route=[route["a"], route["b"]]))
        radius = max(abs(lo), abs(hi))+12
        middle = (start+stop)*0.5
        spans.append((max(0, middle-radius), min(total, middle+radius),
                      entry.tolist(), a.tolist(), b.tolist(), exit_.tolist()))
    if spans:
        distances = np.r_[0, np.cumsum([length for _, _, length in segments(points)])]
        rebuilt, previous = [points[0]], 0
        for start, stop, *crossing in spans:
            rebuilt.extend(point for point, d in zip(points, distances) if previous < d < start)
            rebuilt.extend(crossing)
            previous = stop
        rebuilt.extend(point for point, d in zip(points, distances) if previous < d < total-0.01)
        rebuilt.append(points[-1])
        route["points"] = rebuilt
    return out


def vec2(point):
    return f"Vector2({point[0]:.3f}, {point[1]:.3f})"


def write_water_field(height):
    """Pack sea-bed depth and distance to the nearest dry sample."""
    dry = height >= 0.0
    distance = np.where(dry, 0.0, 12.0).astype(np.float32)
    # A 12 m radius is all the shallow-water shader needs.
    for _ in range(6):
        padded = np.pad(distance, 1, mode="edge")
        h, w = distance.shape
        for dz, dx in ((0, 1), (1, 0), (1, 2), (2, 1), (0, 0), (0, 2), (2, 0), (2, 2)):
            step = STEP * np.hypot(dx-1, dz-1)
            np.minimum(distance, padded[dz:dz+h, dx:dx+w] + step, out=distance)
    field = np.stack((np.clip((2.0-height) / 7.0, 0, 1), distance / 12.0), axis=2)
    Image.fromarray(np.uint8(field*255), "LA").save(ROOT / "water_field.png", optimize=True)


def water_access(layout, x, z, shore):
    """Walkable water is authored inland, even when a river reaches the sea."""
    access = np.where(shore < 18.0, 2, 0).astype(np.uint8)
    inland = np.zeros(x.shape, dtype=bool)
    for basin in layout.get("basins", []):
        if basin.get("beach"):
            continue
        px, pz = basin["point"]
        rx, rz = basin["size"]
        inland |= ((x-px)/rx)**2 + ((z-pz)/rz)**2 < (1+basin["feather"]*.7)**2
    for pond in layout.get("ponds", []):
        px, pz = pond["point"]
        inland |= (x-px)**2 + (z-pz)**2 < (pond["radius"]+2)**2
    for stream in layout["waterways"] + layout.get("feeders", []):
        if stream.get("falls") or stream.get("sea"):
            continue
        points = [p[:2] for p in stream["points"]]
        sl = local_slice(x, z, points, stream["half"]+6)
        distance, _, _ = distance_to_line(x[sl], z[sl], points)
        inland[sl] |= distance <= stream["half"]+4.5
    access[inland & (shore >= 9.0)] = 1
    return base64.b64encode(zlib.compress(access.tobytes(), 9)).decode()


def open_foreground(height, road, shore):
    """Shape near slopes from the coast's fixed south-east camera axis."""
    dz, dx = np.gradient(height, STEP)
    # Use the gentle land which could hold a player, including off-road
    # clearings. Very shallow banks are handled by the authored water pass.
    playable = (np.hypot(dx, dz) <= .77) & (height > 1.2) & (shore > 8)
    verge = np.where(playable, height, np.inf)
    limit = height.copy()
    for step in range(1, 20):
        distance = step * STEP * np.sqrt(2)
        # Wider than one sight ray, so the resulting slope has a shoulder.
        for cross in [-2, -1, 0, 1, 2]:
            j, i = step - cross, step + cross
            if i < 0 or j < 0:
                continue
            h, w = height.shape[0] - j, height.shape[1] - i
            along_grade = 1.28 + .48 * distance + abs(cross) * 1.3
            eased = 8.0 * smooth(45.0, 57.0, distance)
            np.minimum(limit[j:j+h, i:i+w], verge[:h, :w] + along_grade + eased,
                       out=limit[j:j+h, i:i+w])
    cut = np.maximum(height-limit, 0.0)
    # Preserve graded trails. Only the bordering terrain is softened.
    coast_weight = np.maximum(smooth(8, 17, shore), .98 * smooth(12, 24, height))
    mask = (1-smooth(.17, .60, road)) * coast_weight * smooth(1.5, 4.5, height)
    cut_img = Image.fromarray(np.uint8(np.clip(cut * 4, 0, 255)))
    softened = np.asarray(cut_img.filter(ImageFilter.GaussianBlur(1.65)), dtype=np.float32) / 4
    height -= np.maximum(softened, cut * .89) * mask


def bake(layout):
    x0, z0, x1, z1 = layout["bounds"]
    # Two padded samples beyond the map edge keep normals and paint seamless.
    x, z = np.meshgrid(np.arange(x0-2*STEP, x1+3*STEP, STEP, dtype=np.float32),
                       np.arange(z0-2*STEP, z1+3*STEP, STEP, dtype=np.float32))
    hubs = {hub["id"]: hub for hub in layout["hubs"]}
    # Copy routes so the source points stay editable; inserted bridge lines are generated.
    routes = json.loads(json.dumps(layout["routes"]))
    for junction in layout.get("junctions", []):
        hub = junction["hub"]
        street = junction["points"]
        for route in routes:
            if route["ferry"] or hub not in (route["a"], route["b"]):
                continue
            forward = route["a"] == hub
            other = route["b"] if forward else route["a"]
            if other not in junction["ends"]:
                continue
            points = route["points"] if forward else route["points"][::-1]
            landing = street[junction["ends"][other]]
            while len(points) > 2 and np.linalg.norm(np.subtract(points[0], hubs[hub]["point"])) < 26:
                points = points[1:]
            points = [landing] + points
            route["points"] = points if forward else points[::-1]
        routes.append(dict(a=hub, b=hub, points=street, half=4.4, name="", ferry=False,
                           paint_width=2.15, paint=0.86))
    bridges = []
    for route in routes:
        if not route["ferry"] and route["a"] != route["b"]:
            bridges += water_crossings(route, layout["waterways"],
                                       hubs[route["a"]]["height"], hubs[route["b"]]["height"])
    for route in routes:
        if not route["ferry"]:
            route["points"] = rounded_route(route["points"], route.get("bend_radius", 10))

    shore = signed_shore(x, z, [rounded_outline(p) for p in layout["shores"]])
    blend = np.zeros_like(x)
    height = np.zeros_like(x)
    paint = np.zeros((*x.shape, 3), dtype=np.float32)
    for hub in hubs.values():
        hx, hz = hub["point"]
        d2 = (x-hx)**2 + (z-hz)**2
        w = 1 / ((d2 + 1200)/1200)**2.35
        color = [int(hub["colour"][i:i+2], 16) for i in (0, 2, 4)]
        blend += w
        height += hub["height"]*w
        paint += w[:, :, None]*np.array(color, dtype=np.float32)
    height /= blend
    paint /= blend[:, :, None]
    ripple = noise_at(x, z)
    for stretch in layout.get("biome_stretches", []):
        radius, feather = stretch["radius"], stretch["feather"]
        sl = local_slice(x, z, stretch["points"], radius+feather+2)
        d, _, _ = distance_to_line(x[sl], z[sl], stretch["points"])
        weight = 1-smooth(radius, radius+feather, d + ripple[sl]*5)
        color = np.array([int(stretch["colour"][i:i+2], 16) for i in (0, 2, 4)])
        paint[sl] += (color-paint[sl])*weight[:, :, None]
    height += ripple*.85
    paint += ripple[:, :, None]*2.5
    for ridge in layout["ridges"]:
        rad = ridge["radius"]
        sl = local_slice(x, z, ridge["points"], rad+45)
        d, _, _ = distance_to_line(x[sl], z[sl], ridge["points"])
        edge = rad + ripple[sl]*2.7
        bump = (1-smooth(edge-4, edge+17, d)) * ridge["height"]
        height[sl] += bump * (0.93 + ripple[sl]*0.045)
    for hub in hubs.values():
        hx, hz = hub["point"]
        d = np.hypot(x-hx, z-hz)
        weight = 1 - smooth(hub["radius"]*.72, hub["radius"]+17, d)
        height += (hub["height"] + ripple*.22 - height)*weight

    path_nearness = np.zeros_like(x)
    road = np.zeros_like(x)
    camber = np.zeros_like(x)
    destination_grade = np.zeros_like(x)
    pass_distance = np.full_like(x, 90.0)
    pass_grade = np.zeros_like(x)
    corridors = [r for r in routes if not r["ferry"]]
    for overlook, base in zip(layout["overlooks"], ("iron", "white")):
        points = overlook["points"]
        # Attach lookout paths to the nearest point on the relevant road.
        region_route = next(r for r in corridors if {r["a"],r["b"]} ==
                            ({"reed","iron"} if base=="iron" else {"white","salt"}))
        _, progress, total = distance_to_line(np.array([points[0][0]]), np.array([points[0][1]]), region_route["points"])
        near, _ = at_distance(region_route["points"], float(progress[0]))
        y = float(road_grade(region_route, hubs, progress[0], total))
        approach = [near.tolist()] + points
        if np.linalg.norm(np.asarray(points[0]) - near) < 3.0:
            approach = [near.tolist()] + points[1:]
        overlook["approach"] = approach
        overlook["position"] = points[-1]
        corridors.append(dict(a=base, b=base, points=approach,
                              half=3.2, y0=y, y1=y+3, lookout=True))
    for route in (r for r in corridors if not r.get("lookout")):
        sl = local_slice(x, z, route["points"], 45)
        d, progress, total = distance_to_line(x[sl], z[sl], route["points"])
        # Leave a level strip, with short smooth slopes between the route and surrounding terrain.
        grade = road_grade(route, hubs, progress, total)
        for bridge in bridges:
            if bridge["route"] != [route["a"], route["b"]]:
                continue
            bdist = np.hypot(x[sl]-bridge["point"][0], z[sl]-bridge["point"][1])
            weight = 1-smooth(bridge["length"]/2+6, bridge["length"]/2+23, bdist)
            grade += (bridge["height"]-grade)*weight
        half = route["half"]
        nearest = d < pass_distance[sl]
        pass_grade[sl] = np.where(nearest, grade, pass_grade[sl])
        pass_distance[sl] = np.minimum(pass_distance[sl], d)
        cut = 1-smooth(half+4, half+17, d)
        update = cut > path_nearness[sl]
        destination_grade[sl] = np.where(update, grade, destination_grade[sl])
        path_nearness[sl] = np.maximum(path_nearness[sl], cut)
        width = road_width(route, progress, total)
        road[sl] = np.maximum(road[sl], road_paint(route, d, progress, total, ripple[sl]))
        shoulder = 0.25*np.exp(-((d-width-1.5)/1.7)**2)
        shoulder *= smooth(5, 18, progress)*(1-smooth(total-18, total-5, progress))
        for bridge in bridges:
            if bridge["route"] == [route["a"], route["b"]]:
                distance = np.hypot(x[sl]-bridge["point"][0], z[sl]-bridge["point"][1])
                shoulder *= smooth(bridge["length"]/2+2, bridge["length"]/2+10, distance)
        camber[sl] = np.where(update, shoulder, camber[sl])
    height += (destination_grade-height)*path_nearness + camber
    cliff_limit = pass_grade + 5.0 + 16.0*smooth(12.0, 36.0, pass_distance)
    height -= np.maximum(0.0, height-cliff_limit) * (1-smooth(27.0, 43.0, pass_distance))
    for route in (r for r in corridors if r.get("lookout")):
        sl = local_slice(x, z, route["points"], 26)
        d, progress, total = distance_to_line(x[sl], z[sl], route["points"])
        grade = route["y0"] + (route["y1"]-route["y0"])*smooth(0, total, progress)
        cut = (1-smooth(7, 18, d))*smooth(0, 7, progress)
        if route["a"] == "iron":
            # The Reedmire spur runs beside the main ramp. Soften its
            # influence on that road and keep its junction almost level.
            cut = (1-smooth(6, 17, d))*smooth(0, 8, progress)
            cut *= 1 - 0.5*smooth(0.62, 1.0, path_nearness[sl])
        height[sl] += (grade-height[sl])*cut
        path_nearness[sl] = np.maximum(path_nearness[sl], cut)
        road[sl] = np.maximum(road[sl], road_paint(route, d, progress, total, ripple[sl]))
    # Flatten the little exploration trails locally. The first and last
    # points follow the existing ground so junctions retain their road grade.
    for trail in layout.get("footpaths", []):
        points = trail["points"]
        sl = local_slice(x, z, points, 17)
        d, progress, total = distance_to_line(x[sl], z[sl], points)
        lengths = [0.0]
        for _, _, length in segments(points):
            lengths.append(lengths[-1] + length)
        levels = [
            level if level is not None else float(height[round((p[1]-z[0,0])/STEP), round((p[0]-x[0,0])/STEP)])
            for p, level in zip(points, trail["heights"])
        ]
        grade = np.interp(progress, lengths, levels)
        shelf = trail.get("shelf", 3)
        strength = 1-smooth(shelf, shelf+8, d)
        height[sl] += (grade-height[sl])*strength
        path_nearness[sl] = np.maximum(path_nearness[sl], strength)
        road[sl] = np.maximum(road[sl], road_paint(trail, d, progress, total, ripple[sl]))

    # Frame the crossing in both directions without narrowing the deck or
    # putting a soft walkable hill where a pass should have a defined mouth.
    for bank in layout.get("banks", []):
        sl = local_slice(x, z, bank["points"], bank["radius"]+22)
        d, _, _ = distance_to_line(x[sl], z[sl], bank["points"])
        rise = bank["rise"] * (1 - smooth(bank["radius"]*.55, bank["radius"]+11, d))
        height[sl] += rise * (1-path_nearness[sl])
    for opening in layout.get("sightlines", []):
        dx, dz = x-opening["point"][0], z-opening["point"][1]
        rx, rz = opening["radii"]
        side = dx*opening["camera"][0] + dz*opening["camera"][1]
        window = (1-smooth(.62, 1, np.hypot(dx/rx, dz/rz))) * smooth(-17, 8, side)
        window *= 1-smooth(opening["reach"]-14, opening["reach"], pass_distance)
        cap = pass_grade + opening["rise"] + 0.035*pass_distance
        height -= np.maximum(height-cap, 0)*window
    # A road may approach the coastline closely in Ironstep; protect the authored
    # saddle without lifting the sea well beyond the intended land boundary.
    beach = smooth(-5, 9, shore)
    beach = np.maximum(beach, path_nearness*smooth(-10, 0, shore))
    height = -5 + (height+5)*beach
    open_foreground(height, road, shore)
    for notch in layout.get("foreground_notches", []):
        px, pz = notch["point"]
        rx, rz = notch["radii"]
        sl = local_slice(x, z, [notch["point"]], max(rx, rz) + STEP)
        distance = np.hypot((x[sl]-px)/rx, (z[sl]-pz)/rz)
        strength = (1-smooth(.46, 1, distance)) * (1-smooth(.12, .55, road[sl]))
        height[sl] -= notch["cut"] * strength
    for water in layout["waterways"]:
        sl = local_slice(x, z, water["points"], water["half"]+9)
        d, _, _ = distance_to_line(x[sl], z[sl], water["points"])
        fade = 1-smooth(water["half"]-2.5, water["half"]+5.5, d)
        height[sl] += (-2.6-height[sl])*fade
        road[sl] *= 1-fade
    for pond in layout["ponds"]:
        hx, hz = pond["point"]
        d = np.hypot(x-hx, z-hz)
        fade = (1-smooth(pond["radius"]-4, pond["radius"]+2, d))*(1-path_nearness)
        height += (-2.0-height)*fade

    # Levels are shared by the carved beds, rendered surface and fishing.
    water_depth = -height.copy()
    for basin in layout.get("basins", []):
        rx, rz = basin["size"]
        sl = local_slice(x, z, [basin["point"]], max(rx, rz)*(1+basin["feather"])+2)
        dx, dz = x[sl]-basin["point"][0], z[sl]-basin["point"][1]
        d = np.hypot(dx/rx, dz/rz) + 0.035*ripple[sl]
        if basin.get("meander"):
            angle = np.arctan2(dz/rz, dx/rx)
            d += basin["meander"]*(.64*np.sin(2*angle+.7)+.36*np.sin(3*angle-1.2))
        core = 1-smooth(0.74, 1.0, d)
        bank = 1-smooth(0.93, 1+basin["feather"], d)
        grade = basin["level"] + 0.35 - basin["depth"]*core + np.maximum(d-1, 0)*3.0
        influence = bank if basin.get("raised") else bank*(1-0.85*path_nearness[sl]*smooth(0.84, 1.16, d))
        height[sl] += (grade-height[sl])*influence
        road[sl] *= 1-core
        if basin.get("raised"):
            # Close the rim over the perimeter of the rendered spring.
            rim = (1-smooth(1.14, 1.48, d))*smooth(0.88, 1.03, d)
            height[sl] += np.maximum(basin["level"]+0.65-height[sl], 0)*rim
            water_depth[sl] = np.where(d < 1.12, basin["level"]-height[sl], water_depth[sl])
        if basin.get("beach"):
            sand = (1-smooth(1.10, 1.65, d))[:, :, None]
            paint[sl] += (np.array([214, 175, 108], dtype=np.float32)-paint[sl])*sand

    for feeder in layout.get("feeders", []):
        points = [p[:2] for p in feeder["points"]]
        levels = [p[2] for p in feeder["points"]]
        half = feeder["half"]
        sl = local_slice(x, z, points, half+8)
        d, progress, _ = distance_to_line(x[sl], z[sl], points)
        lengths = np.r_[0, np.cumsum([length for _, _, length in segments(points)])]
        level = np.interp(progress, lengths, levels)
        inner = 1-smooth(half-1.1, half+1.0, d)
        outer = 1-smooth(half+1, half+5, d)
        bed = level + 0.48 - (1.55 if feeder.get("shallow") else 2.4)*inner
        # Excavating the outlet must never dam an earlier lake or the sea.
        if feeder.get("shallow"):
            outer *= 1 - path_nearness[sl] * smooth(.36, .90, height[sl])
        height[sl] += (np.minimum(bed, height[sl])-height[sl])*outer
        if feeder.get("falls"):
            water_depth[sl] = np.where(d <= half, level-height[sl], water_depth[sl])
        road[sl] *= 1-inner
    water_depth = np.maximum(water_depth, -height)

    # Keep the land almost level at the waterline, with the drop below it.
    raised_water = (water_depth > 0.18) & (height > 0.3)
    for shelf in layout.get("shore_shelves", []):
        points = shelf["points"]
        half = shelf["half"]
        sl = local_slice(x, z, points, half + 5)
        distance, progress, total = distance_to_line(x[sl], z[sl], points)
        if shelf.get("ford"):
            start, end = shelf["levels"]
            profile = np.interp(progress / total, [0, .46, .55, 1], [start, -.62, -.62, end])
        elif len(shelf["levels"]) == len(points):
            lengths = np.r_[0, np.cumsum([length for _, _, length in segments(points)])]
            profile = np.interp(progress, lengths, shelf["levels"])
        else:
            start, end = shelf["levels"]
            profile = start + (end - start) * progress / total
        weight = 1-smooth(half, half+4.0, distance)
        height[sl] += (profile-height[sl])*weight
    for bridge in bridges:
        a, b = np.asarray(bridge["a"]), np.asarray(bridge["b"])
        axis = (b-a)/bridge["length"]
        sl = local_slice(x, z, [a,b], bridge["width"]+8)
        dx, dz = x[sl]-a[0], z[sl]-a[1]
        along = dx*axis[0]+dz*axis[1]
        across = np.abs(dx*axis[1]-dz*axis[0])
        # Keep the deck and parapets clear of the bank mesh, including its
        # coarse height samples. Feather the cut past the actual span.
        at_end = np.maximum(-along, along-bridge["length"])
        edge = bridge["width"]*0.5
        weight = (1-smooth(1.4, 5.8, at_end))*(1-smooth(edge+1.5, edge+5.0, across))
        height[sl] -= np.maximum(0.0, height[sl]-(bridge["height"]-0.18))*weight
    write_water_field(height)
    fixtures = []
    for id_, point, yaw, light in layout.get("fixtures", []):
        # Snap local axes along the isometric diamond, then sample the terrain.
        u, v = np.round(np.dot(((1, 1), (1, -1)), point)/(2*np.sqrt(2)))*np.sqrt(2)
        fixtures.append(dict(id=id_, point=[round(u+v, 4), round(u-v, 4)], yaw=yaw, light=light))
    hunts = []
    incomplete = []
    for hunt in layout.get("hunting", []):
        id_, name, hub, point, radius, low, high, enemy, count = hunt[:9]
        options = hunt[9] if len(hunt) > 9 else {}
        rng = np.random.default_rng(790 + sum(ord(c)*(i+1) for i, c in enumerate(id_)))
        spots = []
        rolls = rng.random((1100, 2))
        angles, offsets = rolls[:,0]*2*np.pi, radius*np.sqrt(rolls[:,1])
        candidates = np.round((np.array(point) + offsets[:,None] *
                               np.stack((np.cos(angles), np.sin(angles)), axis=1))/STEP)*STEP
        for px, pz in options.get("positions", candidates.astype(int).tolist()):
            col, row = round((px-x[0,0])/STEP), round((pz-z[0,0])/STEP)
            area = np.s_[row-1:row+2, col-1:col+2]
            if (height[area].min() < 1.1 or water_depth[area].max() > .05
                    or np.ptp(height[area]) > 1.8 or pass_distance[row,col] < options.get("road_clearance", 12)
                    or road[area].max() > .20):
                continue
            if any(np.hypot(px-h["point"][0], pz-h["point"][1]) < options.get("hub_clearance", 26)
                   for h in hubs.values()):
                continue
            if any(np.hypot(px-p["position"][0], pz-p["position"][1]) < max(p["rx"],p["rz"])+8
                   for p in layout.get("fishing", [])):
                continue
            if any(np.hypot(px-s[0], pz-s[1]) < 6 for s in spots):
                continue
            spots.append([px,pz])
            if len(spots) == count:
                break
        if len(spots) != count:
            incomplete.append(f"{name}: found {len(spots)} of {count} safe enemy positions")
        if not spots:
            continue
        centre = [sum(s[i] for s in spots)/len(spots) for i in (0, 1)]
        hunts.append(dict(id=id_, name=name, hub=hub, point=centre, levels=[low,high],
                          spawns=[dict(id=f"lc_{id_}_{i+1}", enemy=enemy, position=p,
                                       level=round(low+(high-low)*i/max(count-1,1))) for i,p in enumerate(spots)]))
    if incomplete:
        raise ValueError("\n".join(incomplete))

    paving = np.zeros_like(x)
    bridge_aprons = [dict(points=[b["entry"], b["a"]], half=2.8)
                     for b in bridges if b["name"] == "Lantern Bridge"]
    for patch in layout.get("paving", []) + bridge_aprons:
        points = patch["points"]
        half = patch["half"]
        sl = local_slice(x, z, points, half+5)
        distance, progress, total = distance_to_line(x[sl], z[sl], points)
        taper = np.clip(half*(0.68+0.32*np.sin(np.pi*progress/total)), 0.65, None)
        mask = (1-smooth(taper-0.55, taper+0.60, distance))
        paving[sl] = np.maximum(paving[sl], mask)

    control = np.concatenate((np.clip(paint, 0, 255).astype(np.uint8),
                              np.uint8(road[:, :, None]*255)), axis=2)
    # The map uses the same height and paint samples as the terrain. Bake
    # the overview so opening it doesn't load and decompress every region.
    road_mask = bake_road_mask(layout["bounds"], corridors + layout.get("footpaths", []),
                               height, x[0], z[:,0])
    y_sample, x_sample = np.s_[4:-3:4], np.s_[4:-3:4]
    survey_height = height[y_sample, x_sample]
    survey = paint[y_sample, x_sample].copy()
    shade = np.clip((height[0:-7:4, 0:-7:4] - survey_height) * 0.023, -0.3, 0.22)
    survey *= (1 + shade)[:, :, None]
    # Put the actual widths and texture breaks in the atlas at the same scale
    # as the terrain, preserving the narrower tracks in the overview.
    source = Image.fromarray(road_mask[2:-2, 2:-2])
    mask = np.asarray(source.resize((survey.shape[1], survey.shape[0]), Image.Resampling.BOX))
    weight = smooth(.006, .25, mask.astype(np.float32)/255) * .75
    survey += (np.array([194, 166, 114])-survey)*weight[:, :, None]
    survey[(survey_height <= 0.3) | raised_water[y_sample, x_sample]] = (28, 52, 64)
    Image.fromarray(np.uint8(np.clip(survey, 0, 255))).save(ROOT / "overview.png")

    resources = ROOT / "terrain"
    resources.mkdir(exist_ok=True)
    terrain_files = {}
    grouped = {}
    for cz in range(z0//CHUNK, (z1+CHUNK-1)//CHUNK):
        for cx in range(x0//CHUNK, x1//CHUNK):
            ix, iz = (cx*CHUNK-x0)//STEP+1, (cz*CHUNK-z0)//STEP+1
            if iz+SIDE > height.shape[0] or ix < 0 or iz < 0:
                continue
            h = height[iz:iz+SIDE, ix:ix+SIDE]
            if h.max() < -0.1:
                continue
            cell = (cx, cz)
            nearest = min(hubs.values(), key=lambda hub: np.linalg.norm(
                np.array(hub["point"])-np.array([(cx+.5)*CHUNK,(cz+.5)*CHUNK])))
            pack = nearest["pack"]
            terrain_files[cell] = pack
            raw = np.rint(h*100).astype("<i2").tobytes() + control[iz:iz+SIDE,ix:ix+SIDE].tobytes()
            mask = paving[iz:iz+SIDE,ix:ix+SIDE]
            rx = int((cx*CHUNK-x0)/ROAD_STEP)
            rz = int((cz*CHUNK-z0)/ROAD_STEP)
            fine = road_mask[rz:rz+ROAD_SIDE,rx:rx+ROAD_SIDE]
            fine_road = fine.shape == (ROAD_SIDE, ROAD_SIDE) and fine.any()
            if mask.any() or fine_road:
                raw += np.uint8(mask*255).tobytes()
            if fine_road:
                raw += fine.tobytes()
            data = base64.b64encode(zlib.compress(raw, 9)).decode()
            grouped.setdefault(pack, []).append(f'{vec2(cell)}: PackedByteArray("{data}")')

    for pack, cells in grouped.items():
        (resources / f"{pack}.tres").write_text("[gd_resource type=\"Resource\" format=3]\n\n"
            "[resource]\nmetadata/cells = {\n"+",\n".join(cells)+"\n}\n", encoding="utf-8")
    entries = [f'{vec2(cell)}: "{pack}"' for cell, pack in terrain_files.items()]
    def gd_data(data):
        return json.dumps(data, ensure_ascii=False, separators=(", ", ": "))
    (ROOT / "atlas.tres").write_text(
        '[gd_resource type="Resource" format=3]\n\n[resource]\n'
        'metadata/regions = {\n'+",\n".join(entries)+'\n}\n'
        f'metadata/terrain_bounds = {gd_data(layout["bounds"])}\n'
        f'metadata/water_access = PackedByteArray("{water_access(layout, x, z, shore)}")\n'
        f'metadata/water_crossings = {gd_data([s["points"] for s in layout.get("shore_shelves", []) if s.get("ford")])}\n'
        f'metadata/hubs = {gd_data(layout["hubs"])}\n'
        f'metadata/routes = {gd_data(routes)}\n'
        f'metadata/bridges = {gd_data(bridges)}\n'
        f'metadata/overlooks = {gd_data(layout["overlooks"])}\n'
        f'metadata/footpaths = {gd_data(layout.get("footpaths", []))}\n'
        f'metadata/fishing = {gd_data(layout.get("fishing", []))}\n'
        f'metadata/piers = {gd_data(layout.get("piers", []))}\n'
        f'metadata/springs = {gd_data([b for b in layout.get("basins", []) if b.get("raised")])}\n'
        f'metadata/falls = {gd_data([f for f in layout.get("feeders", []) if f.get("falls")])}\n'
        f'metadata/ridge_passages = {gd_data(layout.get("ridge_passages", []))}\n'
        f'metadata/fixtures = {gd_data(fixtures)}\n'
        f'metadata/hunts = {gd_data(hunts)}\n',
        encoding="utf-8")
    bridge_scene = [
        '[gd_scene format=3]',
        '[ext_resource type="PackedScene" path="crossing.tscn" id="1_bridge"]',
        '[node name="Crossings" type="Node3D"]',
    ]
    for bridge in bridges:
        dx, dz = np.asarray(bridge["b"]) - bridge["a"]
        yaw = np.arctan2(dx, dz)
        px, pz = bridge["point"]
        bridge_scene += [
            f'[node name="{bridge["name"].replace(" ", "")}" parent="." instance=ExtResource("1_bridge")]',
            f'position = Vector3({px:.4f}, {bridge["height"]:.4f}, {pz:.4f})',
            f'rotation = Vector3(0, {yaw:.6f}, 0)',
            f'length = {bridge["length"] + 0.5:.3f}',
            f'clear_width = {bridge["width"]:.3f}',
            f'variant = {bridge["variant"]}',
        ]
    (ROOT / "crossings_baked.tscn").write_text("\n".join(bridge_scene)+"\n", encoding="utf-8")
    write_tiles(ROOT)
    print(f"{len(terrain_files)} cells in {len(grouped)} region files, {len(bridges)} physical crossings.")
    for bridge in bridges:
        print(bridge["name"], bridge["route"], round(bridge["length"], 1), bridge["point"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--atlas", type=Path)
    args = parser.parse_args()
    source = ROOT / "layout.json"
    if args.atlas:
        layout = make_layout(args.atlas)
        source.write_text(json.dumps(layout, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    else:
        layout = json.loads(source.read_text(encoding="utf-8"))
    bake(layout)


if __name__ == "__main__":
    main()
