class_name Collision
extends RefCounted
## Static obstacles are circles on the ground plane (src/world/collision.js):
## trees, rocks, ruins, walls as rows of small circles. Cheap and predictable.
## Each circle is a Dictionary { x, z, r, wall, off }; setting `off` lifts it.

var circles := []
var cell_size := 6.0
var grid := {}
var bounds: Dictionary


func _init() -> void:
	bounds = DB.world.bounds


## `wall`: part of a building's walls, which block line of sight.
func add(x: float, z: float, r: float, wall := false) -> Dictionary:
	var c := {"x": x, "z": z, "r": r, "wall": wall, "off": false, "i": circles.size()}
	circles.append(c)
	for i in range(floori((x - r) / cell_size), floori((x + r) / cell_size) + 1):
		for j in range(floori((z - r) / cell_size), floori((z + r) / cell_size) + 1):
			var k := Vector2i(i, j)
			if not grid.has(k):
				grid[k] = []
			grid[k].append(c)
	return c


func _nearby(x: float, z: float, r: float) -> Array:
	var out := []
	var seen := {}
	for i in range(floori((x - r) / cell_size), floori((x + r) / cell_size) + 1):
		for j in range(floori((z - r) / cell_size), floori((z + r) / cell_size) + 1):
			for c in grid.get(Vector2i(i, j), []):
				if c.off or seen.has(c.i):
					continue
				seen[c.i] = true
				out.append(c)
	return out


## Push a moving circle (a Vector3, x/z used) out of obstacles and keep it in
## the region. Returns the corrected position.
func resolve(pos: Vector3, radius: float) -> Vector3:
	for pass_ in 2:
		for c in _nearby(pos.x, pos.z, radius + 2):
			var dx: float = pos.x - c.x
			var dz: float = pos.z - c.z
			var mn: float = c.r + radius
			var d2 := dx * dx + dz * dz
			if d2 < mn * mn:
				var d := sqrt(d2)
				if d == 0:
					d = 0.0001
				pos.x = c.x + dx / d * mn
				pos.z = c.z + dz / d * mn
	return clamp_to_bounds(pos, radius)


## Is there a wall between two points? (a door is a gap in the wall's circles)
func wall_between(ax: float, az: float, bx: float, bz: float) -> bool:
	var dx := bx - ax
	var dz := bz - az
	var len2 := dx * dx + dz * dz
	if len2 < 1e-6:
		return false
	for c in _nearby((ax + bx) / 2, (az + bz) / 2, sqrt(len2) / 2 + 1):
		if not c.wall:
			continue
		var k := clampf(((c.x - ax) * dx + (c.z - az) * dz) / len2, 0, 1)
		var ex: float = ax + dx * k - c.x
		var ez: float = az + dz * k - c.z
		if ex * ex + ez * ez < pow(c.r * 0.7, 2):
			return true
	return false


func clamp_to_bounds(pos: Vector3, radius := 0.0) -> Vector3:
	pos.x = minf(bounds.maxX - radius, maxf(bounds.minX + radius, pos.x))
	pos.z = minf(bounds.maxZ - radius, maxf(bounds.minZ + radius, pos.z))
	return pos


func is_inside(x: float, z: float) -> bool:
	return x >= bounds.minX and x <= bounds.maxX and z >= bounds.minZ and z <= bounds.maxZ


# ------------------------------------------------------------- path finding
## Does a circle of `radius` moving in a straight line from a to b run into
## an obstacle? Obstacles the mover already stands in are ignored, so it can
## always walk out of one.
func blocked_between(ax: float, az: float, bx: float, bz: float, radius: float) -> bool:
	var dx := bx - ax
	var dz := bz - az
	var len2 := dx * dx + dz * dz
	if len2 < 1e-6:
		return false
	for c in _nearby((ax + bx) / 2, (az + bz) / 2, sqrt(len2) / 2 + radius + 2):
		var mn: float = c.r + radius - 0.05
		if pow(ax - c.x, 2) + pow(az - c.z, 2) < mn * mn:
			continue
		var k := clampf(((c.x - ax) * dx + (c.z - az) * dz) / len2, 0, 1)
		var ex: float = ax + dx * k - c.x
		var ez: float = az + dz * k - c.z
		if ex * ex + ez * ez < mn * mn:
			return true
	return false


const PATH_CELL := 0.75
const PATH_PAD := 14.0 ## metres searched around the start and the goal
const PATH_MAX_NODES := 4000
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## A* over a grid of PATH_CELL squares around the start and goal, for a
## circle of `radius`, then pulled tight. Returns the waypoints (Vector2,
## x/z) after the start, ending at the goal, or [] if there is no way round.
func find_path(ax: float, az: float, bx: float, bz: float, radius: float) -> Array:
	var x0 := minf(ax, bx) - PATH_PAD
	var z0 := minf(az, bz) - PATH_PAD
	var w := int(ceil((maxf(ax, bx) + PATH_PAD - x0) / PATH_CELL))
	var h := int(ceil((maxf(az, bz) + PATH_PAD - z0) / PATH_CELL))
	if w * h > 40000:
		return []
	# rasterise the obstacles once
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	var cx := (x0 + w * PATH_CELL / 2)
	var cz := (z0 + h * PATH_CELL / 2)
	for c in _nearby(cx, cz, maxf(w, h) * PATH_CELL / 2 + 2):
		var rr: float = c.r + radius
		for i in range(maxi(0, floori((c.x - rr - x0) / PATH_CELL)), mini(w, floori((c.x + rr - x0) / PATH_CELL) + 1)):
			for j in range(maxi(0, floori((c.z - rr - z0) / PATH_CELL)), mini(h, floori((c.z + rr - z0) / PATH_CELL) + 1)):
				var px := x0 + (i + 0.5) * PATH_CELL
				var pz := z0 + (j + 0.5) * PATH_CELL
				if pow(px - c.x, 2) + pow(pz - c.z, 2) < rr * rr:
					blocked[j * w + i] = 1
	var start := Vector2i(clampi(floori((ax - x0) / PATH_CELL), 0, w - 1), clampi(floori((az - z0) / PATH_CELL), 0, h - 1))
	var goal := Vector2i(clampi(floori((bx - x0) / PATH_CELL), 0, w - 1), clampi(floori((bz - z0) / PATH_CELL), 0, h - 1))
	var s_id := start.y * w + start.x
	var g_id := goal.y * w + goal.x
	blocked[s_id] = 0
	blocked[g_id] = 0
	var cost := {s_id: 0.0}
	var came := {}
	var heap := [[_octile(start, goal), s_id]]
	var closed := {}
	var found := false
	var expanded := 0
	while not heap.is_empty() and expanded < PATH_MAX_NODES:
		var cur: int = _heap_pop(heap)[1]
		if closed.has(cur):
			continue
		if cur == g_id:
			found = true
			break
		closed[cur] = true
		expanded += 1
		var ci := cur % w
		var cj := cur / w
		for d: Vector2i in STEPS:
			var ni: int = ci + d.x
			var nj: int = cj + d.y
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var n: int = nj * w + ni
			if blocked[n] or closed.has(n):
				continue
			# no cutting a corner between two blocked squares
			if d.x != 0 and d.y != 0 and (blocked[cj * w + ni] or blocked[nj * w + ci]):
				continue
			var g: float = cost[cur] + (1.4142 if d.x != 0 and d.y != 0 else 1.0)
			if g < cost.get(n, INF):
				cost[n] = g
				came[n] = cur
				_heap_push(heap, [g + _octile(Vector2i(ni, nj), goal), n])
	if not found:
		return []
	var cells := []
	var at := g_id
	while at != s_id:
		cells.push_front(Vector2(x0 + (at % w + 0.5) * PATH_CELL, z0 + (at / w + 0.5) * PATH_CELL))
		at = came[at]
	if not cells.is_empty():
		cells[-1] = Vector2(bx, bz)
	# pull the string tight: skip every waypoint a straight walk can pass
	var out := []
	var from := Vector2(ax, az)
	var k := 0
	while k < cells.size():
		var far := k
		for m in range(cells.size() - 1, k, -1):
			if not blocked_between(from.x, from.y, cells[m].x, cells[m].y, radius):
				far = m
				break
		out.append(cells[far])
		from = cells[far]
		k = far + 1
	return out


static func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) + 0.4142 * mini(dx, dy)


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if heap[p][0] <= heap[i][0]:
			break
		var t = heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and heap[l][0] < heap[m][0]:
				m = l
			if r < n and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var t = heap[m]
			heap[m] = heap[i]
			heap[i] = t
			i = m
	return top
