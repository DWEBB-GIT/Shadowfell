extends RefCounted
## Sampled walking surface used by the ordinary Game controller and pathfinder.

const ATLAS := preload("res://game/world/lantern_coast/atlas.tres")
const LAND := preload("res://game/world/lantern_coast/land.gd")
const PLACEMENTS := preload("placement_records.gd")
const BUILDINGS := preload("settlement_building.gd")
const ESCAPE_ROUTES := preload("escape_routes.tres")
const FERRY_DOCKS := preload("ferry_docks.gd")
const MAX_WALK_SLOPE_DEGREES := 45.0
const MAX_GRADE := tan(deg_to_rad(MAX_WALK_SLOPE_DEGREES))
const STEP_TOLERANCE := 0.001
const SHORE_CLEARANCE := 0.08
const RAIL_CLEARANCE := 0.76
const WADE_DEPTH := 0.72
const INLAND_WATER := 1
const OPEN_COAST := 2

var land: Node3D
var _fishing: Array = ATLAS.get_meta("fishing", [])
var _springs: Array = ATLAS.get_meta("springs", [])
var _falls: Array = ATLAS.get_meta("falls", [])
var _bridges: Array = []
var _obstacles := {}
var _registered := {}
var _bounds: Array = ATLAS.get_meta("terrain_bounds")
var _access_width := 0
var _access_rows := 0
var _water_access: PackedByteArray
var _exits: PackedByteArray
var _exit_width: int
var _exit_rows: int
var dungeon
var buildings: Array[Dictionary] = []
var _building_cells := {}


func _init() -> void:
	var packed: PackedByteArray = ATLAS.get_meta("water_access")
	_access_width = roundi((_bounds[2] - _bounds[0]) / LAND.STEP) + 5
	_access_rows = roundi((_bounds[3] - _bounds[1]) / LAND.STEP) + 5
	_water_access = packed.decompress(_access_width * _access_rows, FileAccess.COMPRESSION_DEFLATE)
	_exit_width = int(_bounds[2] - _bounds[0])
	_exit_rows = int(_bounds[3] - _bounds[1])
	var outlets: PackedByteArray = ESCAPE_ROUTES.get_meta("outlets")
	_exits = outlets.decompress(_exit_width * _exit_rows, FileAccess.COMPRESSION_DEFLATE)
	land = LAND.new()
	land.name = "StreamedTerrain"
	land.configure(ATLAS.get_meta("regions"), PLACEMENTS.read_path_paint())
	for bridge in ATLAS.get_meta("bridges"):
		var axis := (_point(bridge.b) - _point(bridge.a)).normalized()
		_bridges.append({"centre": _point(bridge.point), "axis": axis,
			"along": bridge.length * 0.5 + 0.25, "across": bridge.width * 0.5,
			"height": bridge.height, "rails": true})
	for pier in ATLAS.get_meta("piers", []) + FERRY_DOCKS.PIERS:
		var a := _point(pier.a)
		var b := _point(pier.b)
		_bridges.append({"centre": (a + b) * 0.5, "axis": (b - a).normalized(),
			"along": a.distance_to(b) * 0.5, "across": pier.width * 0.5,
			"height": pier.height, "bank_height":pier.get("bank_height", pier.height),
			"ramp":pier.get("ramp", 0.0), "rails": false})


func height_at(p: Vector2) -> float:
	if dungeon != null and dungeon.occupies(p):
		return dungeon.FLOOR
	var structure := _building_height(p)
	if is_finite(structure):
		return structure
	var ground: float = land.floor_height(p)
	var bridge := _bridge(p)
	if not bridge.is_empty():
		return maxf(ground, _deck_height(p, bridge))
	return maxf(ground, water_height(p) - WADE_DEPTH) if _water_kind(p) == INLAND_WATER else ground


func _water_kind(p: Vector2) -> int:
	var x := roundi((p.x - float(_bounds[0])) / LAND.STEP) + 2
	var z := roundi((p.y - float(_bounds[1])) / LAND.STEP) + 2
	if x < 0 or z < 0 or x >= _access_width or z >= _access_rows or _water_access.is_empty():
		return OPEN_COAST
	return _water_access[z * _access_width + x]


func _exit_flag(p: Vector2) -> int:
	var x := floori(p.x - float(_bounds[0]))
	var z := floori(p.y - float(_bounds[1]))
	if x < 0 or z < 0 or x >= _exit_width or z >= _exit_rows:
		return 0
	return _exits[z * _exit_width + x] if not _exits.is_empty() else 1


## An outlet may be a walkable route or a short descent that meets one.
func has_exit(p: Vector2) -> bool:
	if _exit_flag(p) > 0 or is_finite(_building_height(p)) or not _bridge(p).is_empty():
		return true
	if dungeon != null and dungeon.occupies(p):
		return dungeon.floor_at(p)
	# The baked samples sit in the centre of each metre. At a cell edge,
	# accept the bordering route if the actual ground also supports it.
	if not _has_surface(p):
		return false
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var adjacent: Vector2 = p + dir * 0.52
		if _exit_flag(adjacent) == 1 and absf(height_at(p) - height_at(adjacent)) <= MAX_GRADE * 0.52:
			return true
	return false


func stable_footing(p: Vector2, radius: float) -> bool:
	return _can_pass(p, radius, -INF) and not is_wading(p)


func safe_arrival(p: Vector2, radius: float) -> Vector2:
	if _can_pass(p, radius, -INF) or (_has_surface(p) and has_exit(p) and not inside_prop(p, radius)):
		return p
	for distance in [1.0, 2.0, 3.5, 5.0, 8.0, 12.0, 18.0, 24.0, 36.0, 48.0]:
		for i in 16:
			var at: Vector2 = p + Vector2.from_angle(float(i) * TAU / 16.0) * distance
			if stable_footing(at, radius):
				return at
	var start: Array = DB.world.playerStart.position
	return Vector2(start[0], start[1])


func is_wading(p: Vector2) -> bool:
	if _water_kind(p) != INLAND_WATER or not _bridge(p).is_empty():
		return false
	var depth: float = water_height(p) - land.floor_height(p)
	return depth > 0.0 and depth <= 4.0


func walk_at(p: Vector2) -> float:
	if dungeon != null and dungeon.occupies(p):
		return float(dungeon.floor_at(p))
	if inside_prop(p, 0.0):
		return 0.0
	return _terrain_walk_at(p)


func direct_walk(a: Vector2, b: Vector2, radius: float) -> bool:
	return _sweep(a, b, radius, -INF, false).distance_squared_to(b) < 0.001225


## With a tuned camera the closest keyboard direction can miss a deck by
## up to 22.5 degrees. Keep deliberate sideways motion available at the rails.
func bridge_direction(at: Vector2, direction: Vector2, radius: float) -> Vector2:
	for bridge in _bridges:
		if not bridge.rails:
			continue
		var axis: Vector2 = bridge.axis
		var offset: Vector2 = at - bridge.centre
		if absf(offset.dot(axis)) > bridge.along + 5.0 or absf(offset.cross(axis)) > bridge.across - radius:
			continue
		var alignment := direction.dot(axis)
		if absf(alignment) >= 0.92:
			return axis * signf(alignment)
	return direction


func move_pick(origin: Vector3, ray: Vector3, player: Vector3, hit, radius: float):
	var start := Vector2(player.x, player.z)
	if hit is Vector3:
		var at := Vector2(hit.x, hit.z)
		if is_wading(at) and _can_pass(at, radius, -INF):
			return Vector3(at.x, height_at(at), at.y)
		# Let the normal pathfinder take a switchback up to a real slope hit.
		if absf(height_at(at) - hit.y) < 0.9 and _can_pass(at, radius, -INF) and (
				hit.y <= player.y + 3.1 or start.distance_squared_to(at) <= 62.0 * 62.0):
			return hit
	var flat = Plane(Vector3.UP, player.y).intersects_ray(origin, ray)
	if flat == null:
		return null
	var aim := Vector2(flat.x, flat.z)
	var best := Vector2.INF
	var score := INF
	for radius_ in [0.0, 1.8, 3.5, 5.5, 8.0]:
		for i in (1 if radius_ == 0.0 else 12):
			var point: Vector2 = aim + Vector2.from_angle(i * TAU / 12.0) * radius_
			if not _can_pass(point, radius, -INF):
				continue
			var elevation := absf(height_at(point) - player.y)
			if elevation > 3.6:
				continue
			var cost: float = radius_ + elevation * 1.5
			if radius_ == 0.0:
				return Vector3(point.x, height_at(point), point.y)
			if cost < score:
				best = point
				score = cost
	return Vector3(best.x, height_at(best), best.y) if best.is_finite() else null


func _terrain_walk_at(p: Vector2) -> float:
	if is_finite(_building_height(p)) or not _bridge(p).is_empty():
		return 1.0
	var sample: Vector2 = land.floor_sample(p)
	var above := sample.x - water_height(p)
	var inland := _water_kind(p) == INLAND_WATER
	if inland and above < 0.0:
		return float(above >= -4.0 and has_exit(p))
	return float(_ground_supports(above, inland) and can_walk_grade(sample.y))


static func can_walk_grade(grade: float) -> bool:
	return grade <= MAX_GRADE + STEP_TOLERANCE


static func _ground_supports(above_water: float, inland: bool) -> bool:
	return above_water >= (0.0 if inland else SHORE_CLEARANCE)


func set_fishing_water(water: Array) -> void:
	_fishing = water


func water_at(p: Vector2, margin: float):
	for water in _fishing:
		var size := Vector2(water.rx, water.rz) - Vector2.ONE * margin
		var offset := p - _point(water.position)
		if absf(offset.x) > size.x or absf(offset.y) > size.y or (offset / size).length_squared() > 1.0:
			continue
		if land.floor_height(p) < float(water.level) - 0.05:
			return water
	return null


func water_height(p: Vector2) -> float:
	var height := 0.0
	for spring in _springs:
		var offset := p - _point(spring.point)
		var extent := _point(spring.size) * 1.12
		if absf(offset.x) <= extent.x and absf(offset.y) <= extent.y and (offset / extent).length_squared() < 1.0:
			height = float(spring.level)
	for fall in _falls:
		var points: Array = fall.points
		var half: float = fall.half
		if p.distance_squared_to(_point(points[0])) > 1600.0:
			continue
		for i in range(1, points.size()):
			var a := _point(points[i - 1])
			var b := _point(points[i])
			var line := b - a
			var t := clampf((p - a).dot(line) / line.length_squared(), 0.0, 1.0)
			if p.distance_squared_to(a + line * t) <= half * half:
				height = maxf(height, lerpf(points[i - 1][2], points[i][2], t))
	return height


func block_step(from: Vector3, to: Vector3, radius: float, airborne := false, allow_drop := false) -> Vector3:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var movement := b - a
	if movement.is_zero_approx():
		return to
	# A loaded position or an obstacle push may leave the player just inside
	# an edge. Find nearby footing once, then resume normal swept movement.
	var feet := from.y if airborne else -INF
	var on_dry_face := allow_drop and _has_surface(a) and not inside_prop(a, radius, feet)
	if not _can_pass(a, radius, feet) and not on_dry_face:
		a = _nearby_footing(a, movement.normalized(), radius)
		b = a + movement
	var hit := _sweep(a, b, radius, feet, allow_drop)
	if hit.is_equal_approx(b):
		return Vector3(b.x, to.y, b.y)
	# Try two tangents on either side of the blocked direction. Keep the
	# most forward progress, without redirecting a full run into a sidestep.
	var remaining := b - hit
	var best := hit
	var best_progress := 0.0
	for angle in [0.70, -0.70, 1.23, -1.23]:
		var slide := remaining.rotated(angle) * cos(angle)
		var candidate := _sweep(hit, hit + slide, radius, feet, allow_drop)
		var progress := (candidate - hit).dot(movement)
		if progress > best_progress:
			best = candidate
			best_progress = progress
	return Vector3(best.x, to.y, best.y)


func landing_at(at: Vector3, radius: float, direction: Vector2, last_footing := Vector2.INF) -> Vector3:
	var p := Vector2(at.x, at.z)
	if _can_pass(p, radius, -INF):
		return at
	if not has_exit(p) or not _has_surface(p):
		var bank := last_footing if last_footing.is_finite() and stable_footing(last_footing, radius) else safe_arrival(p, radius)
		return Vector3(bank.x, height_at(bank), bank.y)
	if not inside_prop(p, radius):
		return at
	var safe := _nearby_footing(p, direction, radius)
	if safe == p and last_footing.is_finite() and stable_footing(last_footing, radius):
		safe = last_footing
	return Vector3(safe.x, height_at(safe), safe.y)


func _nearby_footing(at: Vector2, preferred: Vector2, radius: float) -> Vector2:
	if preferred.is_zero_approx():
		preferred = Vector2.RIGHT
	for distance in [0.25, 0.5, 0.9, 1.35, 2.0]:
		var best := at
		var best_score := -INF
		for i in 12:
			var direction := preferred.rotated(TAU * i / 12.0)
			var candidate: Vector2 = at + direction * distance
			if not _can_pass(candidate, radius, -INF) or not _clear_rail(at, candidate, radius, -INF):
				continue
			var score := direction.dot(preferred)
			# Recover onto the low side of a steep triangle.
			score -= maxf(0.0, height_at(candidate) - height_at(at)) * 2.0
			if score > best_score:
				best = candidate
				best_score = score
		if best_score > -INF:
			return best
	return at


func _sweep(a: Vector2, b: Vector2, radius: float, feet: float, allow_drop: bool) -> Vector2:
	var count := maxi(1, ceili(a.distance_to(b) / 0.25))
	var last := a
	for i in range(1, count + 1):
		var next := a.lerp(b, float(i) / count)
		if _step_clear(last, next, radius, feet, allow_drop):
			last = next
			continue
		for j in 4:
			var middle := (last + next) * 0.5
			if _step_clear(last, middle, radius, feet, allow_drop):
				last = middle
			else:
				next = middle
		break
	return last


func _can_pass(p: Vector2, radius: float, feet: float) -> bool:
	if dungeon != null and dungeon.occupies(p):
		return dungeon.floor_at(p, radius)
	return _terrain_walk_at(p) >= 0.5 and not inside_prop(p, radius, feet)


func _has_surface(p: Vector2) -> bool:
	if dungeon != null and dungeon.occupies(p):
		return dungeon.floor_at(p)
	if is_finite(_building_height(p)) or not _bridge(p).is_empty():
		return true
	var water := water_height(p)
	var ground: float = land.floor_height(p)
	return ground >= water + SHORE_CLEARANCE or (_water_kind(p) == INLAND_WATER and ground >= water - 4.0)


func _step_clear(a: Vector2, b: Vector2, radius: float, feet: float, allow_drop: bool) -> bool:
	if dungeon != null and dungeon.occupies(a):
		return dungeon.floor_at(b, radius)
	if inside_prop(b, radius, feet) or not _clear_rail(a, b, radius, feet):
		return false
	var floor_b := _building_height(b)
	if is_finite(floor_b):
		return floor_b - height_at(a) <= maxf(0.18, a.distance_to(b) * MAX_GRADE) or feet > floor_b
	if not _bridge(b).is_empty():
		return true
	var sample: Vector2 = land.floor_sample(b)
	var kind := _water_kind(b)
	var inland := kind == INLAND_WATER
	var above := sample.x - water_height(b)
	if inland and above < 0.0:
		return above >= -4.0 and (has_exit(b) or (allow_drop and is_wading(a) and not has_exit(a)))
	if not _ground_supports(above, inland):
		return false
	var rise := sample.x - height_at(a)
	if not can_walk_grade(sample.y):
		# Even a diagonal with a small rise cannot climb a cliff face.
		return allow_drop and rise <= 0.0001 and kind != OPEN_COAST and has_exit(b)
	var step_limit := a.distance_to(b) * MAX_GRADE + STEP_TOLERANCE
	if absf(rise) <= step_limit:
		return true
	if rise > 0.0:
		# Allow a small change in footing when leaving shallow water.
		return feet > sample.x + 0.04 or (rise <= 0.08 and is_wading(a))
	return allow_drop and has_exit(b)


func stepping_off(from: Vector3, to: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	if dungeon != null and dungeon.occupies(a):
		return false
	var b := Vector2(to.x, to.z)
	if is_finite(_building_height(b)):
		return false
	if a.distance_squared_to(b) < 0.00001 or not _bridge(a).is_empty():
		return false
	return from.y - height_at(b) > a.distance_to(b) * MAX_GRADE + STEP_TOLERANCE


func _clear_rail(a: Vector2, b: Vector2, radius: float, feet: float) -> bool:
	var bridge := _bridge(a)
	if not bridge.is_empty():
		if not bridge.rails:
			return true
		var start: Vector2 = a - bridge.centre
		var end: Vector2 = b - bridge.centre
		var reach := maxf(bridge.across - radius, absf(start.cross(bridge.axis)))
		return (absf(end.dot(bridge.axis)) >= bridge.along
			or absf(end.cross(bridge.axis)) <= reach + 0.0001
			or _vaultable_rail(bridge, end, feet))
	bridge = _bridge(b)
	if bridge.is_empty() or not bridge.rails:
		return true
	var start: Vector2 = a - bridge.centre
	return (absf(start.dot(bridge.axis)) >= bridge.along
		or absf(start.cross(bridge.axis)) <= bridge.across
		or _vaultable_rail(bridge, start, feet))


func _vaultable_rail(bridge: Dictionary, offset: Vector2, feet: float) -> bool:
	if feet < bridge.height + RAIL_CLEARANCE:
		return false
	var axis: Vector2 = bridge.axis
	var side := Vector2(-axis.y, axis.x) * signf(offset.cross(axis))
	var bank: Vector2 = bridge.centre + axis * offset.dot(axis) + side * (bridge.across + 0.62)
	var sample: Vector2 = land.floor_sample(bank)
	return (sample.x >= water_height(bank) + SHORE_CLEARANCE
		and can_walk_grade(sample.y) and absf(sample.x - bridge.height) <= 1.25)


func inside_prop(p: Vector2, radius: float, feet := -INF) -> bool:
	var cell := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for obstacle: Dictionary in _obstacles.get(cell + Vector2i(dx, dz), []):
				if feet >= obstacle.clearance or not obstacle.rect.grow(radius).has_point(p):
					continue
				if not obstacle.has("half"):
					return true
				var local: Vector2 = (p - obstacle.centre).rotated(-obstacle.yaw).abs()
				if local.x <= obstacle.half.x + radius and local.y <= obstacle.half.y + radius:
					return true
	return false


func register_tree(point: Vector2, radius: float) -> void:
	var extent := Vector2.ONE * radius
	_add_obstacle(Rect2(point - extent, extent * 2.0))


func prepare_buildings(props: Array) -> void:
	for prop in props:
		if not BUILDINGS.supported(prop):
			continue
		var site := BUILDINGS.site(land, prop)
		buildings.append(site)
		var hx: float = site.size.x * 0.5
		var hz: float = site.size.y * 0.5
		var reach := Vector2(hx + 1.5, hz + BUILDINGS.APRON + 1.5).length()
		var center: Vector2 = site.center
		var from := _building_cell(center - Vector2.ONE * reach)
		var to := _building_cell(center + Vector2.ONE * reach)
		for z in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var key := Vector2i(x, z)
				if not _building_cells.has(key):
					_building_cells[key] = []
				_building_cells[key].append(site)
		if not prop.get("noCollision", false):
			var pose := Transform3D(Basis(Vector3.UP, site.yaw), Vector3(center.x, site.floor, center.y))
			for box in BUILDINGS.walls(site.size):
				register_prop_box(pose, box)
			for box in BUILDINGS.furniture(site):
				register_prop_box(pose, box, site.floor + float(box[4]) * 0.78)


func _building_cell(point: Vector2) -> Vector2i:
	return Vector2i((point / 24.0).floor())


func building_at(point: Vector2) -> Dictionary:
	for site in _building_cells.get(_building_cell(point), []):
		if BUILDINGS.inside(site, point):
			return site
	return {}


func clear_for_building(point: Vector2, margin := 0.0) -> bool:
	for site in _building_cells.get(_building_cell(point), []):
		var p := BUILDINGS.local(site, point)
		if site.floor_area.grow(margin).has_point(p) or site.approach.grow(margin).has_point(p):
			return true
	return false


func _building_height(point: Vector2) -> float:
	for site in _building_cells.get(_building_cell(point), []):
		var p := BUILDINGS.local(site, point)
		if site.approach.has_point(p):
			var ramp := clampf((p.y - site.size.y * 0.5) / BUILDINGS.APRON, 0.0, 1.0)
			return maxf(land.floor_height(point), lerpf(site.floor, site.ground, ramp))
		if site.floor_area.has_point(p):
			return site.floor
	return -INF


func building_wall_between(a: Vector2, b: Vector2) -> bool:
	# Tall walls use their rotated dimensions, just as the movement sweep does.
	var cell_a := _building_cell(a.min(b))
	var cell_b := _building_cell(a.max(b))
	var seen := {}
	for z in range(cell_a.y, cell_b.y + 1):
		for x in range(cell_a.x, cell_b.x + 1):
			for site in _building_cells.get(Vector2i(x, z), []):
				if site.prop.get("noCollision", false) or seen.has(site.center):
					continue
				seen[site.center] = true
				var start := BUILDINGS.local(site, a)
				var end := BUILDINGS.local(site, b)
				for box in BUILDINGS.walls(site.size):
					var half := Vector2(box[2], box[3]) * 0.5
					var center := Vector2(box[0], box[1])
					if Geometry2D.segment_intersects_segment(start, end, center - half, center + Vector2(half.x, -half.y)) != null \
						or Geometry2D.segment_intersects_segment(start, end, center + Vector2(half.x, -half.y), center + half) != null \
						or Geometry2D.segment_intersects_segment(start, end, center + half, center + Vector2(-half.x, half.y)) != null \
						or Geometry2D.segment_intersects_segment(start, end, center + Vector2(-half.x, half.y), center - half) != null:
						return true
	return false


func register_prop_box(xf: Transform3D, box: Array, clearance := INF) -> void:
	var at := xf * Vector3(box[0], 0, box[1])
	var basis := xf.basis
	var yaw := atan2(basis.x.z, basis.x.x)
	var half := Vector2(box[2] * basis.x.length(), box[3] * basis.z.length()) * .5
	var axis := Vector2.from_angle(yaw).abs()
	var extent := Vector2(axis.x * half.x + axis.y * half.y, axis.y * half.x + axis.x * half.y)
	var centre := Vector2(at.x, at.z)
	_add_obstacle(Rect2(centre - extent, extent * 2), clearance,
		{"centre": centre, "yaw": yaw, "half": half})


func _add_obstacle(rect: Rect2, clearance := INF, detail := {}) -> void:
	var entry: Dictionary = detail.merged({"rect": rect, "clearance": clearance})
	var first := Vector2i((rect.position / 8.0).floor())
	var last := Vector2i((rect.end / 8.0).floor())
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, z)
			if not _obstacles.has(key):
				_obstacles[key] = []
			_obstacles[key].append(entry)


func register_landmark(id: String, landmark: Node3D) -> void:
	if _registered.has(id):
		return
	_registered[id] = true
	for body in landmark.find_children("*", "StaticBody3D", true, false):
		for shape in body.get_children():
			if shape is CollisionShape3D and shape.shape is BoxShape3D:
				var size: Vector3 = shape.shape.size
				var bounds: AABB = shape.global_transform * AABB(-size * 0.5, size)
				var clearance := INF
				if bounds.size.y <= 1.10:
					clearance = bounds.position.y + bounds.size.y * 0.74
				_add_obstacle(Rect2(Vector2(bounds.position.x, bounds.position.z),
					Vector2(bounds.size.x, bounds.size.z)), clearance)


func _bridge(p: Vector2) -> Dictionary:
	for bridge in _bridges:
		var offset: Vector2 = p - bridge.centre
		if absf(offset.dot(bridge.axis)) <= bridge.along and absf(offset.cross(bridge.axis)) <= bridge.across:
			return bridge
	return {}


static func _deck_height(p: Vector2, bridge: Dictionary) -> float:
	var offset: Vector2 = p - bridge.centre
	return FERRY_DOCKS.deck_height(bridge, offset.dot(bridge.axis) + bridge.along)


static func _point(a: Array) -> Vector2:
	return Vector2(a[0], a[1])
