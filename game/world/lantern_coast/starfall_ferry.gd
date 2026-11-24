extends RefCounted
## The player crosses on the visible hull. Motion and arrival use the same route.

const DOCKS := preload("ferry_docks.gd")
const LANDMARKS := preload("landmarks.gd")
const BOARD_TIME := 1.0
const SAIL_SPEED := 13.0
const HULL_HEIGHT := 0.24
const RIDER := Vector3(0.42, 0.92, -1.55)

var game
var docks: Array = []
var voyage := {}
var _clock := 0.0


func _init(g, routes: Array) -> void:
	game = g
	for route in routes:
		var reverse: Array = route.path.duplicate()
		reverse.reverse()
		var s := _dock(route.name, route.origin, route.destination, route.path)
		var t := _dock(route.name, route.destination, route.origin, reverse)
		s.other = docks.size() + 1
		t.other = docks.size()
		docks.append_array([s, t])


func _dock(name: String, pier: Dictionary, other: Dictionary, path: Array) -> Dictionary:
	var root := Node3D.new()
	root.name = str(pier.id).to_pascal_case() + "Boat"
	game.scene.add_child(root)
	var hull := LANDMARKS.ferry_hull(root, name == "Cutlass Ferry")
	var at := DOCKS.board_at(pier)
	var d := {"name":name, "pier":pier, "at":at, "to":DOCKS.board_at(other), "to_name":other.destination,
		"boat":root, "hull":hull, "wake":_wake(root), "curve":_sailing_curve(path)}
	_moor(d)
	var seaward := DOCKS.seaward(pier)
	var side := Vector2(-seaward.y, seaward.x)
	var lantern := at + side * 1.27
	game.atmosphere.add_coast_lamp(Vector3(lantern.x, float(pier.height) + 1.5, lantern.y), "amber")
	return d


static func _sailing_curve(path: Array) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.6
	for i in path.size():
		var point: Vector2 = path[i]
		var back: Vector2 = point - path[maxi(0, i - 1)]
		var next: Vector2 = path[mini(path.size() - 1, i + 1)] - point
		var direction := (back.normalized() + next.normalized()).normalized()
		var tangent := Vector3(direction.x, 0, direction.y)
		curve.add_point(Vector3(point.x, HULL_HEIGHT, point.y),
			-tangent * back.length() * 0.31, tangent * next.length() * 0.31)
	return curve


func _moor(dock: Dictionary) -> void:
	var at := DOCKS.berth(dock.pier)
	var face := DOCKS.seaward(dock.pier)
	dock.boat.position = Vector3(at.x, HULL_HEIGHT, at.y)
	dock.boat.rotation = Vector3(0, atan2(face.x, face.y), 0)


func active() -> bool:
	return not voyage.is_empty()


func board(dock: Dictionary) -> bool:
	var p: Player = game.player
	if active() or p.dead or p.ghost or game.releasing or game.combat_blocks_logout() or game.targeting.attacking:
		game.hud.error("You can board the ferry when you are out of combat.")
		return false
	if game._far(dock.at.x, dock.at.y, 3.0):
		game.hud.error("Move closer to the end of the jetty to board.")
		return false
	var curve: Curve3D = dock.curve
	var other: Dictionary = docks[dock.other]
	var berth: Vector3 = curve.sample_baked(0.0)
	if not dock.boat.position.is_equal_approx(berth):
		_moor(dock)
	var start := p.position
	p._reset_jump()
	p.set_sitting(false)
	game.move_to = null
	game.targeting.clear()
	game.fishing.stop(true)
	game.loot.stop_gathering()
	game.mining.stop()
	game.gathering.stop()
	game.interaction.current = null
	other.boat.hide()
	voyage = {"dock":dock, "other":other, "start":start, "start_yaw":dock.boat.rotation.y,
		"t":0.0, "length":curve.get_baked_length(), "sailing":maxf(10.0, curve.get_baked_length() / SAIL_SPEED)}
	game.hud.toast("Sailing to " + dock.to_name)
	return true


func idle(dt: float) -> void:
	_clock += dt
	var p: Vector3 = game.player.position
	for dock in docks:
		var at: Vector3 = dock.boat.position
		if p.distance_squared_to(at) < 125.0 * 125.0:
			_rock(dock, 0.26)


func advance(dt: float) -> void:
	_clock += dt
	voyage.t += dt
	var dock: Dictionary = voyage.dock
	var boat: Node3D = dock.boat
	var hull: Node3D = dock.hull
	var curve: Curve3D = dock.curve
	var on_sea: float = clampf((voyage.t - BOARD_TIME) / voyage.sailing, 0.0, 1.0)
	var distance: float = (on_sea - sin(TAU * on_sea) * 0.10) * voyage.length
	var moving: bool = voyage.t >= BOARD_TIME and on_sea < 1.0
	var direction := curve.sample_baked(minf(voyage.length, distance + 0.8), true) \
		- curve.sample_baked(maxf(0.0, distance - 0.8), true)
	var yaw := atan2(direction.x, direction.z)
	boat.position = curve.sample_baked(distance, true)
	boat.rotation.y = lerp_angle(voyage.start_yaw, yaw, smoothstep(0.0, BOARD_TIME, voyage.t))
	_rock(dock, 1.0 if moving else 0.28)
	dock.wake.visible = moving
	if moving:
		dock.wake.scale = Vector3.ONE * (0.6 + 0.4 * sin(PI * on_sea))
	var seat := boat.to_global(RIDER) + Vector3.UP * hull.position.y
	var p: Player = game.player
	var disembark := clampf((voyage.t - voyage.sailing - BOARD_TIME) / BOARD_TIME, 0.0, 1.0)
	if voyage.t < BOARD_TIME:
		var start: Vector3 = voyage.start
		p.position = start.lerp(seat, smoothstep(0.0, BOARD_TIME, voyage.t))
		p.facing = atan2(seat.x - start.x, seat.z - start.z)
	elif disembark > 0.0:
		var landing := _landing(dock)
		p.position = seat.lerp(landing, smoothstep(0.0, 1.0, disembark))
		p.facing = atan2(landing.x - seat.x, landing.z - seat.z)
	else:
		p.position = seat
		p.facing = yaw + 0.18
	p.rig.update(dt, 0.0 if moving else 0.55)
	p._sync()
	if disembark >= 1.0:
		_arrive(dock)


func _rock(dock: Dictionary, amount: float) -> void:
	var hull: Node3D = dock.hull
	hull.position.y = sin(_clock * 2.2) * 0.07 * amount
	hull.rotation.x = sin(_clock * 1.6) * 0.034 * amount
	hull.rotation.z = sin(_clock * 1.95 + 0.8) * 0.05 * amount
	var sail: Node3D = hull.get_node("Sail")
	sail.rotation.x = 0.16 + sin(_clock * 4.2) * 0.035 * amount


func _landing(dock: Dictionary) -> Vector3:
	return Vector3(dock.to.x, Terrain.height_at(dock.to.x, dock.to.y), dock.to.y)


func _arrive(dock: Dictionary) -> void:
	var other: Dictionary = voyage.other
	# Leave the arriving boat alongside the pier. The spare serves the origin.
	var spare := [other.boat, other.hull, other.wake]
	other.boat = dock.boat
	other.hull = dock.hull
	other.wake = dock.wake
	dock.boat = spare[0]
	dock.hull = spare[1]
	dock.wake = spare[2]
	_moor(dock)
	dock.boat.show()
	var landing := _landing(dock)
	var toward_land := -DOCKS.seaward(other.pier)
	voyage.clear()
	game.player.place_at(landing.x, landing.z, atan2(toward_land.x, toward_land.y))
	game.world.coast_scene.stream_for_player(game.player.position, true)
	game._snap_camera()
	game.hud.toast("Arrived at " + dock.to_name)
	game.events.emit("log", {"text":"The ferry docks at %s." % other.pier.name, "kind":"lore"})
	game.save.autosave()


static func _wake(parent: Node3D) -> MeshInstance3D:
	var vertices := SurfaceTool.new()
	vertices.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var a := Vector3(0.38 * side, 0, -2.8)
		var b := Vector3(1.25 * side, 0, -4.1)
		var c := Vector3(3.7 * side, 0, -11.3)
		var d := Vector3(2.6 * side, 0, -12.3)
		var foam := Color(0.71, 0.88, 0.87, 0.30)
		for v in [a, b, c, a, c, d]:
			vertices.set_color(foam if v == a or v == b else Color(foam, 0.0))
			vertices.add_vertex(v)
	var m := MeshInstance3D.new()
	m.mesh = vertices.commit()
	m.name = "Wake"
	m.position.y = -0.105
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	m.material_override = mat
	m.hide()
	parent.add_child(m)
	return m
