"""Bake where a player can land and still reach a trail or settlement."""
import base64
from collections import deque
import json
from pathlib import Path
import sys
import zlib

import numpy as np


def atlas_entry(atlas, name):
    return json.loads(atlas.split(f"metadata/{name} = ", 1)[1].splitlines()[0])


def connected_cells(state, height, starts, max_grade):
    """Flood only in four directions and across steps that can be reversed."""
    passable = state >= 2
    east = passable[:, :-1] & passable[:, 1:] & (abs(height[:, :-1] - height[:, 1:]) <= max_grade)
    down = passable[:-1] & passable[1:] & (abs(height[:-1] - height[1:]) <= max_grade)
    east = east.astype(np.uint8)
    down = down.astype(np.uint8)
    rows, width = state.shape
    stride = width + 2
    links = np.zeros((rows + 2, stride), np.uint8)
    links[1:-1, 1:-2] |= east
    links[1:-1, 2:-1] |= east * 2
    links[1:-2, 1:-1] |= down * 4
    links[2:-1, 1:-1] |= down * 8
    graph = links.tobytes()
    seen = bytearray(len(graph))
    queue = deque()
    for x, z in starts:
        index = (z + 1) * stride + x + 1
        if graph[index] and not seen[index]:
            seen[index] = 1
            queue.append(index)
    while queue:
        index = queue.popleft()
        exits = graph[index]
        for bit, shift in ((1, 1), (2, -1), (4, stride), (8, -stride)):
            if exits & bit and not seen[index + shift]:
                seen[index + shift] = 1
                queue.append(index + shift)
    return np.frombuffer(seen, np.uint8).reshape(links.shape)[1:-1, 1:-1].astype(bool)


def descents(state, height, connected):
    """Propagate uphill from reachable footing, through a short cliff face."""
    steep = state == 1
    usable = connected.copy()
    for _ in range(16):
        next_usable = usable.copy()
        next_usable[1:] |= steep[1:] & usable[:-1] & (height[1:] >= height[:-1] - 0.08)
        next_usable[:-1] |= steep[:-1] & usable[1:] & (height[:-1] >= height[1:] - 0.08)
        next_usable[:, 1:] |= steep[:, 1:] & usable[:, :-1] & (height[:, 1:] >= height[:, :-1] - 0.08)
        next_usable[:, :-1] |= steep[:, :-1] & usable[:, 1:] & (height[:, :-1] >= height[:, 1:] - 0.08)
        if np.array_equal(usable, next_usable):
            break
        usable = next_usable
    return usable & steep


def main(atlas_path, samples_path, output_path):
    atlas = atlas_path.read_text(encoding="utf-8")
    x0, z0, x1, z1 = atlas_entry(atlas, "terrain_bounds")
    width, rows = x1 - x0, z1 - z0
    raw = samples_path.read_bytes()
    max_grade = float(np.frombuffer(raw, dtype="<f4", count=1)[0])
    samples = np.frombuffer(raw, np.uint8, offset=4).reshape(rows, 5 * width)
    state = samples[:, :width].copy()
    height = samples[:, width:].copy().view("<f4")
    points = [hub["point"] for hub in atlas_entry(atlas, "hubs")]
    # Shore points and upper trailheads support intended exits on separate landmasses.
    points.extend(water["bank"] for water in atlas_entry(atlas, "fishing"))
    points.extend(trail["points"][0][:2] for trail in atlas_entry(atlas, "footpaths"))
    starts = [(int(x - x0), int(z - z0)) for x, z in points if x0 <= x < x1 and z0 <= z < z1]
    connected = connected_cells(state, height, starts, max_grade)
    slippery = descents(state, height, connected)
    flags = connected.astype(np.uint8) + slippery.astype(np.uint8) * 2
    blocked = (state != 0) & (flags == 0)
    print(f"Reachable land and water cells: {connected.sum():,}")
    print(f"Cliff cells with a downhill exit: {slippery.sum():,}")
    print(f"Isolated inland water cells: {(blocked & (state == 3)).sum():,}")
    print(f"Isolated ground cells: {(blocked & (state == 2)).sum():,}")
    print(f"Cliff cells without a nearby exit: {(blocked & (state == 1)).sum():,}")
    for kind in (2, 3):
        interior = blocked & (state == kind)
        zs, xs = interior.nonzero()
        if len(xs):
            offsets = np.linspace(0, len(xs) - 1, min(12, len(xs)), dtype=int)
            print(f"Kind {kind} examples:", [(int(xs[i] + x0), int(zs[i] + z0)) for i in offsets])
    packed = base64.b64encode(zlib.compress(flags.tobytes(), level=9)).decode("ascii")
    output_path.write_text(
        '[gd_resource type="Resource" format=3]\n\n[resource]\n'
        f'metadata/outlets = PackedByteArray("{packed}")\n', encoding="utf-8", newline="\n"
    )


if __name__ == "__main__":
    main(*(Path(arg) for arg in sys.argv[1:]))
