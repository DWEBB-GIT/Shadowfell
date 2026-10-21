class_name Camp
extends RefCounted
## The player's camp (Set Camp, learned from Old Tam; src/systems/camp.js).
## One camp at a time: pitching a new one strikes the old. The camp is where
## the spirit rises after a death, and resting beside it, with no enemy
## near, builds rested experience. A faint ring on the ground shows how
## close you must stay to rest; it glows brighter while you rest.

var game
var mesh: Node3D
var light: OmniLight3D
var ring: MeshInstance3D


func _init(g) -> void:
	game = g


## Is anything hostile close enough to stop the player making camp?
var enemies_near: bool:
	get:
		var p: Vector3 = game.player.position
		for e in game.enemies.list:
			if e.alive and (e.engaged > 0 or not e.passive and U.hyp(e.position.x - p.x, e.position.z - p.z) < DB.CONFIG.camp.clearRadius):
				return true
		return false


func pitch(x: float, z: float) -> void:
	var ws = game.world_state
	ws.camp = {"x": snappedf(x, 0.01), "z": snappedf(z, 0.01)}
	ws.rest_point = "camp"
	show()
	game.events.emit("campPitched", {"x": x, "z": z})
	game.events.emit("log", {"text": "You make camp. If you fall, your spirit will rise here.", "kind": "heal"})
	if game.hud:
		game.hud.toast("Camp made")


## Put the camp's model where the world state says it is (also after a load).
func show() -> void:
	var c = game.world_state.camp
	if mesh:
		mesh.queue_free()
	mesh = null
	ring = null
	light = null
	if c == null:
		return
	mesh = Node3D.new()
	mesh.name = "Camp"
	mesh.add_child(Assets.instance("camp"))
	light = Tex.point_light(Color("ffa050"), 2.2, 9, 1.6)
	light.position = Vector3(0, 0.8, 0)
	mesh.add_child(light)
	mesh.position = Vector3(c.x, Terrain.height_at(c.x, c.z), c.z)
	ring = _ring(c)
	mesh.add_child(ring)
	game.scene.add_child(mesh)


## the rest circle: a thin band laid over the ground around the fire
func _ring(c: Dictionary) -> MeshInstance3D:
	var r: float = DB.CONFIG.camp.restRadius
	var base := Terrain.height_at(c.x, c.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 72
	var pts := []
	for i in segs + 1:
		var a := TAU * i / segs
		var row := []
		for rr in [r - 0.07, r + 0.07]:
			var x: float = sin(a) * rr
			var z: float = cos(a) * rr
			row.append(Vector3(x, Terrain.height_at(c.x + x, c.z + z) - base + 0.06, z))
		pts.append(row)
	for i in segs:
		var a: Vector3 = pts[i][0]
		var b: Vector3 = pts[i][1]
		var cc: Vector3 = pts[i + 1][0]
		var d: Vector3 = pts[i + 1][1]
		for v in [a, b, cc, cc, b, d]:
			st.add_vertex(v)
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(Color("ffb060"), 0.35)
	mat.render_priority = 2
	m.material_override = mat
	m.name = "CampRestRing"
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## 'camp' by your fire, 'inn' under an inn's roof (no enemy near), else ""
var resting: String:
	get:
		var c = game.world_state.camp
		var player = game.player
		if player.dead or enemies_near:
			return ""
		var indoors = game.world.indoors if game.world else null
		if indoors != null and indoors.def.get("rest"):
			return "inn"
		return "camp" if c != null and U.hyp(player.position.x - c.x, player.position.z - c.z) <= DB.CONFIG.camp.restRadius else ""


func update(_dt: float, time: float) -> void:
	if light:
		light.light_energy = (2.0 + sin(time * 9) * 0.25 + sin(time * 23) * 0.15) * Tex.OMNI_SCALE
	# rested experience builds while you sit by the fire
	var prog = game.progression
	var where := resting
	if ring:
		ring.material_override.albedo_color.a = 0.6 + sin(time * 3) * 0.1 if where == "camp" else 0.3
	if where != "":
		var cap: float = prog.xp_to_next * DB.CONFIG.camp.restedCap
		if prog.rested < cap:
			var was: float = prog.rested
			prog.rested = minf(cap, prog.rested + prog.xp_to_next * DB.CONFIG.camp.restedPerSecond * _dt)
			if was == 0:
				var text := "You rest at the inn. You feel rested." if where == "inn" else "You rest by the fire. You feel rested."
				game.events.emit("log", {"text": text, "kind": "heal", "throttle": "rested"})
