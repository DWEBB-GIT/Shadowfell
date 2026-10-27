class_name Fx
extends RefCounted
## Restrained visual feedback (src/systems/fx.js): a ground shockwave for
## Shield Break, small sparks on hits, dust, and a faint pillar on level-up.
## Each effect is a node with a life and an update; it is freed when done.

## the colour of each school of magic (and of a Ranger's tar)
const SCHOOL_COLOURS := {"holy": Color("ffd070"), "shadow": Color("9a5ae0"), "nature": Color("8ad04a"), "fire": Color("ff8030"), "physical": Color("e8dcc0"), "tar": Color("5a4630")}

var game
var items := []
var move_mark = null
var traps := {}
var dust_mesh: BoxMesh
var dust_mat: StandardMaterial3D


## The soft round shadow under a character.
static func blob_shadow(size: float) -> MeshInstance3D:
	var m := Tex.fx_material(Tex.blob(), Color.WHITE, false)
	var q := Tex.ground_quad(m)
	q.scale = Vector3(size, 1, size)
	q.position.y = 0.03
	return q


func _init(g) -> void:
	game = g
	dust_mesh = BoxMesh.new()
	dust_mesh.size = Vector3(0.12, 0.12, 0.12)
	dust_mat = StandardMaterial3D.new()
	dust_mat.albedo_color = Color("6a5c48")
	var ev: Events = game.events
	# a spell with its own look (data/spell_fx.json) skips the generic one
	ev.on("spellFx", func(e): spell_fx(e))
	ev.on("burst", func(e):
		if not _has_look(e.get("id", ""), "impact"):
			shockwave(e.position, e.radius, Color("ffe6a0") if e.get("school") == "holy" else Color("ffd9a0")))
	ev.on("enemyHit", func(e): sparks(e.enemy.position, 14 if e.get("crit") else 7 if e.get("kind") == "strike" else 8))
	# the weight of a landed blow: the camera kicks (nothing ever pauses)
	ev.on("hitImpact", func(e):
		if e.get("heavy") or e.get("crit"):
			game.shake_camera(DB.CONFIG.impact.critShake if e.get("crit") else DB.CONFIG.impact.shake))
	ev.on("playerHurt", func(e):
		game.shake_camera(DB.CONFIG.impact.critShake if e.get("heavy") else DB.CONFIG.impact.shake * 0.6)
		game.hud.flash_damage())
	ev.on("levelUp", func(_e): pillar(game.player.position))
	# an enchanter's work: a violet light rises off you
	ev.on("itemEnchanted", func(_e): pillar(game.player.position, Color("c8a0ff")))
	ev.on("itemScrapped", func(_e): sparks(game.player.position, 12, Color("c8a0ff")))
	ev.on("enemyDefeated", func(e): dust(e.enemy.position, 10))
	# the Grave Slam lands where the telegraph was painted
	ev.on("graveSlam", func(e):
		var sh = e.shape
		var r: float = sh.range * 0.55
		shockwave(Vector3(sh.x + sin(sh.angle) * r, game.player.position.y, sh.z + cos(sh.angle) * r), sh.range * 0.6))
	ev.on("playerLunge", func(_e): dust(game.player.position, 6, 0.3))
	ev.on("braceBlock", func(_e): sparks(game.player.position, 10))
	ev.on("anvilStrike", func(e):
		var p: Vector3 = game.player.position
		if U.hyp(p.x - e.x, p.z - e.z) < 25:
			sparks(Vector3(e.x, Terrain.height_at(e.x, e.z) - 0.3, e.z), 5))
	ev.on("playerBrace", func(e):
		if not _has_look(e.get("id", ""), "cast"):
			brace_glow(e.get("window", DB.brace.window)))
	ev.on("projectile", func(e): projectile(e))
	# a channel that drains (Siphon Life) draws a beam from the target to you
	ev.on("castStart", func(e):
		var c = game.player.casting
		if c != null and c.channel and c.target != null and c.spell.tuning.get("healPercent", 0) > 0:
			siphon_beam(c, SCHOOL_COLOURS.get(c.spell.get("school"), Color("9a5ae0"))))
	ev.on("darkCircle", func(e): shockwave(Vector3(e.x, Terrain.height_at(e.x, e.z), e.z), e.radius, Color("9a7cff")))
	# spells (game/systems/spells.gd)
	ev.on("spellFlash", func(e): flash(e.position, SCHOOL_COLOURS.get(e.get("school"), Color("ffe08a"))))
	ev.on("zone", func(e): zone(e.x, e.z, e.radius, e.duration, SCHOOL_COLOURS.get(e.get("school"), Color("ffd070"))))
	# a set trap is a small dull ring until it is sprung or wears out
	ev.on("trap", func(e): traps[e.key] = zone(e.x, e.z, e.radius, e.duration, Color("8a7050"), 0.35))
	ev.on("trapGone", func(e):
		var it = traps.get(e.key)
		if it:
			it.life = maxf(1e-3, minf(it.life, it.age))
		traps.erase(e.key))
	ev.on("cleave", func(e):
		if _has_look(e.get("id", ""), "impact"):
			return
		var r: float = e.range * 0.5
		var p: Vector3 = e.position
		shockwave(Vector3(p.x + sin(e.facing) * r, p.y, p.z + cos(e.facing) * r), e.range * 0.7, Color("ffc890")))
	ev.on("buff", func(e):
		if not _has_look(e.get("id", ""), "cast"):
			pillar(game.player.position, Color("ff9a5a")))
	ev.on("splash", func(e): splash(e.x, e.y, e.z, e.get("small", false)))
	ev.on("campPitched", func(e): dust(Vector3(e.x, Terrain.height_at(e.x, e.z), e.z), 10, 0.6))
	ev.on("itemDropped", func(e): dust(Vector3(e.item.x, game.player.position.y, e.item.z), 4, 0.2))


## Draws one of each kind of effect for a moment, out of sight under the
## ground, so their shaders are compiled now and not on the first hit (a GL
## driver compiles a shader the first time it draws with it, which stalls
## that frame).
func prewarm(pos: Vector3) -> void:
	var under := pos - Vector3(0, 6, 0)
	var n := items.size()
	shockwave(under, 1)
	sparks(under, 1)
	flash(under, Color.WHITE)
	pillar(under)
	zone(under.x, under.z, 1, 0.1)
	for name in _look_meshes():
		_shape({"mesh": name, "life": 0.1}, under, 0.0, null, Color.WHITE, {})
	var tm := ShaderMaterial.new()
	tm.shader = Telegraphs.SHADER
	tm.render_priority = 2
	var t := Tex.ground_quad(tm)
	t.position = under
	_add(t, 0.1, func(_it, _k, _dt): pass)
	for i in range(n, items.size()):
		items[i].life = minf(items[i].life, 0.1)
		items[i].obj.position.y = under.y


## `update(it, k, dt)`; `it` is the effect's own dictionary, so it can keep state.
func _add(obj: Node3D, life: float, update: Callable, state := {}) -> Dictionary:
	game.scene.add_child(obj)
	var it := {"obj": obj, "life": life, "age": 0.0, "update": update}
	it.merge(state)
	items.append(it)
	return it


func shockwave(pos: Vector3, radius: float, colour := Color("ffd9a0")) -> void:
	var ring := Tex.ground_quad(Tex.fx_material(Tex.ring(), colour))
	ring.position = Vector3(pos.x, pos.y + 0.12, pos.z)
	_add(ring, 0.45, func(it, k, _dt):
		var s: float = radius * 2 * (0.3 + k * 0.8)
		it.obj.scale = Vector3(s, s, s)
		it.obj.material_override.albedo_color.a = 1 - k)
	dust(pos, 14, radius * 0.7)


func sparks(pos: Vector3, n: int, colour := Color("ffc890")) -> void:
	for i in n:
		var s := Tex.sprite(Tex.fx_material(Tex.glint(), colour, true, true))
		s.scale = Vector3.ONE * 0.25
		s.position = Vector3(pos.x, pos.y + 1.1, pos.z)
		var v := Vector3((randf() - 0.5) * 4, 1.5 + randf() * 2.5, (randf() - 0.5) * 4)
		_add(s, 0.3 + randf() * 0.15, func(it, k, dt):
			it.obj.position += it.v * dt
			it.v.y -= 12 * dt
			it.obj.material_override.albedo_color.a = 1 - k, {"v": v})


func dust(pos: Vector3, n: int, spread := 0.6) -> void:
	for i in n:
		var m := MeshInstance3D.new()
		m.mesh = dust_mesh
		m.material_override = dust_mat
		var a := randf() * TAU
		var v := Vector3(cos(a) * (1 + randf() * 2), 1 + randf() * 1.5, sin(a) * (1 + randf() * 2))
		m.position = Vector3(pos.x + cos(a) * spread * randf(), pos.y + 0.1, pos.z + sin(a) * spread * randf())
		_add(m, 0.6, func(it, k, dt):
			it.obj.position += it.v * dt
			it.v.y -= 6 * dt
			it.obj.scale = Vector3.ONE * maxf(0.001, 1 - k), {"v": v})


## An arrow (a thin shaft) or a bolt (a glowing mote) flying from -> to.
## With `follow` (an enemy), it homes in on it as it moves, and arrives
## after `life` seconds.
func projectile(p: Dictionary) -> void:
	var kind = p.get("kind")
	var follow = p.get("follow")
	var bolt: bool = kind == "bolt" or kind == "holy"
	var obj: Node3D
	if bolt:
		obj = Tex.sprite(Tex.fx_material(Tex.glint(), Color("ffd98a") if kind == "holy" else Color("9a7cff"), true, true))
		obj.scale = Vector3.ONE * 0.6
	elif follow and Assets.has("arrow"):
		obj = Assets.instance("arrow")
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.03, 0.7)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("d8c8a0")
		mi.material_override = mat
		obj = mi
	var from: Vector3 = p.from
	var to: Vector3 = p.to
	var a := from
	var b := Vector3(to.x, Terrain.height_at(to.x, to.z) + 1.0, to.z)
	obj.position = a
	var life = p.get("life")
	var time: float = life if life != null else maxf(0.08, a.distance_to(b) / p.speed)
	_add(obj, maxf(0.05, time), func(it, k, _dt):
		if it.follow:
			var fp: Vector3 = it.follow.position
			it.b = Vector3(fp.x, Terrain.height_at(fp.x, fp.z) + 1.0, fp.z)
		var o: Node3D = it.obj
		o.position = it.a.lerp(it.b, k)
		# a slight arc for arrows
		if not bolt:
			o.position.y += sin(k * PI) * minf(1.2, it.a.distance_to(it.b) * 0.04)
			_look(o, it.b), {"a": a, "b": b, "follow": follow})
	if not bolt:
		_look(obj, b)


## point a node's +z at a target (three.js lookAt for non-cameras)
static func _look(o: Node3D, target: Vector3) -> void:
	var d := target - o.position
	if d.length_squared() < 1e-6:
		return
	o.basis = Basis.looking_at(d, Vector3.UP, true)


## a pale shield of light in front of the Warden while Brace is up
func brace_glow(window: float) -> void:
	var player = game.player
	var s := Tex.sprite(Tex.fx_material(Tex.glint(), Color(Color("9cc4ff"), 0), true, true))
	s.scale = Vector3(1.4, 1.8, 1)
	_add(s, window, func(it, _k, _dt):
		var f: float = player.facing
		it.obj.position = Vector3(player.position.x + sin(f) * 0.6, player.position.y + 1.1, player.position.z + cos(f) * 0.6)
		it.obj.material_override.albedo_color.a = 0.5 if player.is_braced else 0.0)


## rings on the water where the bob lands or a fish takes it
func splash(x: float, y: float, z: float, small: bool) -> void:
	for i in (1 if small else 3):
		var ring := Tex.ground_quad(Tex.fx_material(Tex.ring(), Color("cfe6e0")))
		ring.position = Vector3(x, y + 0.03, z)
		var delay := i * 0.12
		_add(ring, 0.8 + delay, func(it, k, _dt):
			var t := maxf(0, (k * (0.8 + delay) - delay) / 0.8)
			var sc := (0.4 if small else 0.6) + t * (0.8 if small else 1.6)
			it.obj.scale = Vector3(sc, 1, sc)
			it.obj.material_override.albedo_color.a = 0.8 * (1 - t) if t > 0 else 0.0)


## a quick burst of light on a target (Smite)
func flash(pos: Vector3, colour: Color) -> void:
	var s := Tex.sprite(Tex.fx_material(Tex.glint(), colour, true, true))
	_add(s, 0.4, func(it, k, _dt):
		it.obj.position = Vector3(pos.x, pos.y + 1.2 + k * 0.6, pos.z)
		it.obj.scale = Vector3.ONE * 1.6 * (1 - k * 0.5)
		it.obj.material_override.albedo_color.a = 1 - k)


## click to move: a yellow ring that pulses twice where the walk is headed
func move_marker(x: float, z: float) -> void:
	if move_mark != null and is_instance_valid(move_mark.obj):
		move_mark.life = 0.001
	var ring := Tex.ground_quad(Tex.fx_material(Tex.ring(), Color("ffd84a")))
	ring.position = Vector3(x, Terrain.height_at(x, z) + 0.1, z)
	move_mark = _add(ring, 0.8, func(it, k, _dt):
		var t: float = fmod(k * 2, 1)
		var s: float = 1.1 - t * 0.6
		it.obj.scale = Vector3(s, 1, s)
		it.obj.material_override.albedo_color.a = (1 - t) * (1 - k * 0.5))


## consecrated ground: a glowing ring that stays for the spell's duration
func zone(x: float, z: float, radius: float, duration: float, colour := Color("ffd070"), strength := 1.0) -> Dictionary:
	var ring := Tex.ground_quad(Tex.fx_material(Tex.ring(), colour))
	ring.position = Vector3(x, Terrain.height_at(x, z) + 0.1, z)
	ring.scale = Vector3(radius * 2, 1, radius * 2)
	return _add(ring, duration, func(it, k, _dt):
		it.obj.material_override.albedo_color.a = strength * (0.55 + 0.25 * sin(k * duration * TAU)) * minf(1, (1 - k) * 6))


## a beam of drained life from the target to the caster, for as long as the
## channel lasts, with motes of light running along it towards the caster
func siphon_beam(cast: Dictionary, colour: Color) -> void:
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.1
	cm.height = 1
	cm.radial_segments = 6
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = Tex.fx_material(null, Color(colour, 0))
	var motes := []
	for i in 4:
		var m := Tex.sprite(Tex.fx_material(Tex.glint(), colour, true, true))
		m.scale = Vector3.ONE * 0.45
		beam.add_child(m)
		motes.append(m)
	var player = game.player
	_add(beam, cast.total + 1.0, func(it, _k, dt):
		var on: bool = is_same(player.casting, cast) and cast.target.alive
		it.fade = minf(1, it.fade + dt * 6) if on else it.fade - dt * 5
		if it.fade <= 0:
			it.life = it.age
			return
		var a: Vector3 = cast.target.position + Vector3(0, 1.1, 0)
		var b: Vector3 = player.position + Vector3(0, 1.1, 0)
		var d := b - a
		var len := maxf(0.1, d.length())
		it.obj.global_position = (a + b) * 0.5
		var up := d / len
		var side := up.cross(Vector3.FORWARD if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
		# the cylinder's own y runs along the beam, stretched to its length
		it.obj.global_basis = Basis(side, up * len, side.cross(up))
		it.obj.material_override.albedo_color.a = it.fade * (0.55 + 0.2 * sin(it.age * 18))
		for i in motes.size():
			var f: float = fmod(it.age * 1.6 + i / float(motes.size()), 1.0)
			var mo: Node3D = motes[i]
			mo.global_position = a + d * f
			mo.global_basis = Basis.IDENTITY.scaled(Vector3.ONE * 0.45 * (0.6 + 0.4 * sin(f * PI)))
			mo.material_override.albedo_color.a = it.fade * sin(f * PI), {"fade": 0.0})


func pillar(pos: Vector3, colour := Color("ffe2a8")) -> void:
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.8
	cm.height = 4
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	col.mesh = cm
	col.material_override = Tex.fx_material(null, Color(colour, 0))
	col.position = Vector3(pos.x, pos.y + 2, pos.z)
	_add(col, 1.4, func(it, k, _dt):
		it.obj.material_override.albedo_color.a = sin(k * PI) * 0.25
		it.obj.position = game.player.position + Vector3(0, 2 + k, 0))


# ------------------------------------------------------------ spell looks
## the effect shapes in assets/models/fx (assets/blender/build_fx.py), by name
static var _fx_meshes := {}


static func fx_mesh(name: String) -> Mesh:
	if not _fx_meshes.has(name):
		var mesh: Mesh = null
		var path := "res://assets/models/fx/%s.glb" % name
		if ResourceLoader.exists(path):
			var n: Node = load(path).instantiate()
			var found := n.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				mesh = Assets._srgb_mesh(found[0].mesh)
			n.free()
		_fx_meshes[name] = mesh
	return _fx_meshes[name]


static func _has_look(id: String, phase: String) -> bool:
	return not DB.spell_fx.get(id, {}).get(phase, []).is_empty()


static func _look_meshes() -> Array:
	var names := {}
	for id in DB.spell_fx:
		for phase in ["cast", "impact"]:
			for p in DB.spell_fx[id].get(phase, []):
				if p.has("mesh"):
					names[p.mesh] = true
	return names.keys()


## A spell's own look: every part of its `cast` or `impact` list
## (data/spell_fx.json), each after its own delay.
## `e`: { id, phase, position, facing, follow (the player or null), tuning }
func spell_fx(e: Dictionary) -> void:
	var spell: Dictionary = DB.abilities.get(e.id, {})
	var school: Color = SCHOOL_COLOURS.get(spell.get("school"), SCHOOL_COLOURS.physical)
	for p in DB.spell_fx.get(e.id, {}).get(e.phase, []):
		var go := _spell_part.bind(p, e, school)
		if p.get("delay", 0) > 0:
			_add(Node3D.new(), p.delay, func(_it, k, _dt):
				if k >= 1:
					go.call())
		else:
			go.call()


func _spell_part(p: Dictionary, e: Dictionary, school: Color) -> void:
	var colour := Color(p.colour) if p.has("colour") else school
	var follow = e.get("follow") if p.get("follow") else null
	var f: float = e.facing
	var at: Vector3 = (follow.position if follow else e.position) + Vector3(sin(f), 0, cos(f)) * p.get("forward", 0.0)
	match p.fx:
		"mesh":
			_shape(p, e.position, f, follow, colour, e.get("tuning", {}))
		"ring":
			shockwave(at, p.get("radius", 2.0), colour)
		"sparks":
			sparks(at, int(p.get("n", 6)), colour if p.has("colour") else Color("ffc890"))
		"dust":
			dust(at, int(p.get("n", 6)), p.get("spread", 0.6))
		"flash":
			flash(at, colour)
		"shake":
			game.shake_camera(DB.CONFIG.impact.critShake if p.get("heavy") else DB.CONFIG.impact.shake)


## One effect shape: placed by `height`, `forward` and `rot` around its
## anchor, turned by `spin` about its own axis, grown from `size[0]` to
## `size[1]`, flaring in fast and fading out. Additive, so its greyscale
## vertex colours are its brightness and the tint is the colour.
func _shape(p: Dictionary, pos: Vector3, facing: float, follow, colour: Color, tuning: Dictionary) -> void:
	var mesh := fx_mesh(p.mesh)
	if mesh == null:
		return
	var life = p.get("life", 0.3)
	if typeof(life) == TYPE_STRING:
		life = tuning.get(life, 0.3)
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := Tex.fx_material(null, Color(colour, 0))
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	holder.add_child(mi)
	var rot: Array = p.get("rot", [0, 0, 0])
	var size: Array = p.get("size", [1, 1])
	var sc: Array = p.get("scale", [1, 1, 1])
	var glow: float = p.get("glow", 1.0)
	var spin: float = deg_to_rad(p.get("spin", 0))
	var height: float = p.get("height", 0.0)
	var forward: float = p.get("forward", 0.0)
	var braced: bool = p.get("whileBraced", false)
	# a long effect fades in and out over a fixed time, a short one over its life
	var edge: float = minf(0.25, 0.3 / maxf(0.01, life))
	var face_cam: bool = p.get("faceCamera", false)
	var angle: float = deg_to_rad(p.get("angle", 0))
	var tilt := Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])))
	_add(holder, life, func(_it, k, _dt):
		var o: Vector3 = follow.position if follow else pos
		var fa: float = follow.facing if follow else facing
		holder.position = o + Vector3(sin(fa) * forward, height, cos(fa) * forward)
		if face_cam:
			# an upright shape seen side on is a line, so it turns to face
			# the fixed camera (as a slash sprite would), stepped a little
			# toward it to draw over the target, and mirrored so the swing
			# runs the way you face across the screen
			var cam := holder.get_viewport().get_camera_3d()
			var cb: Basis = cam.global_basis.orthonormalized() if cam else Basis.IDENTITY
			var flip := -1.0 if Vector3(sin(fa), 0, cos(fa)).dot(cb.x) < 0 else 1.0
			holder.basis = cb * Basis(Vector3.BACK, angle * flip) * Basis.from_scale(Vector3(flip, 1, 1)) * tilt
			holder.position += cb.z * 0.6
		else:
			holder.rotation = Vector3(deg_to_rad(rot[0]), fa + deg_to_rad(rot[1]), deg_to_rad(rot[2]))
		var s: float = lerpf(size[0], size[1], 1 - pow(1 - k, 3))
		mi.scale = Vector3(sc[0], sc[1], sc[2]) * s
		mi.rotation.y = spin * (k - 0.5)
		var fade := minf(1, k / (edge * 0.35)) * (1 - smoothstep(1 - edge, 1, k))
		if braced and not game.player.is_braced:
			fade = 0.0
		mat.albedo_color.a = glow * fade)


func update(dt: float) -> void:
	for it in items.duplicate():
		it.age += dt
		var k: float = minf(1, it.age / it.life)
		it.update.call(it, k, dt)
		if k >= 1:
			it.obj.queue_free()
			items.erase(it)
