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
