class_name Fx
extends RefCounted
## Restrained visual feedback (src/systems/fx.js): a ground shockwave for
## Shield Break, small sparks on hits, dust, and a faint pillar on level-up.
## Each effect is a node with a life and an update; it is freed when done.

## the colour of each school of magic (and of a Ranger's tar)
const SCHOOL_COLOURS := {"holy": Color("ffd070"), "shadow": Color("9a5ae0"), "nature": Color("8ad04a"), "fire": Color("ff8030"), "physical": Color("e8dcc0"), "tar": Color("7c6040"), "frost":Color("a7e7ff"), "lightning":Color("83baff"), "arcane":Color("bc9bff"), "steam":Color("d8e9e9")}

var game
var items := []
var move_mark = null
var traps := {}
var keyed_zones := {}
var dust_mesh: BoxMesh
var dust_mat: StandardMaterial3D


## The soft round shadow under a character.
static func blob_shadow(size: float, tex: Texture2D = null) -> MeshInstance3D:
	var m := Tex.fx_material(tex if tex else Tex.blob(), Color.WHITE, false)
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
	# a spell with its own look (data/abilities/spell_fx.json) skips the generic one
	ev.on("spellFx", func(e): spell_fx(e))
	ev.on("burst", func(e):
		if not _has_look(e.get("id", ""), "impact"):
			shockwave(e.position, e.radius, Color("ffe6a0") if e.get("school") == "holy" else Color("ffd9a0"))
		aoe_weight(e))
	ev.on("enemyHit", func(e):
		var land := func():
			if e.get("damage",0) > 0 and not e.get("periodic", false):
				contact_impact(e)
			_blow_lands(e)
		# The opening auto-attack resolves early but its visible impact waits
		# for the blade's windup, together with the floating damage number.
		var delay: float = e.get("show",0.0)
		if delay > 0:
			_add(Node3D.new(),delay,func(_it,k,_dt):
				if k >= 1: land.call())
		else:
			land.call())
	# the weight of a landed blow: the camera kicks (nothing ever pauses)
	ev.on("hitImpact", func(e):
		if e.get("heavy") or e.get("crit"):
			game.shake_camera(DB.CONFIG.impact.critShake if e.get("crit") else DB.CONFIG.impact.shake))
	ev.on("playerHurt", func(e):
		game.shake_camera(DB.CONFIG.impact.critShake if e.get("heavy") else DB.CONFIG.impact.shake * 0.6)
		game.hud.flash_damage())
	# a hero's moment: a seal, a spiral and a column of light, a star flare,
	# a fountain of sparks and a flash of real light (data `moments.levelUp`)
	ev.on("levelUp", func(_e): moment("levelUp"))
	# an enchanter's work: a violet light rises off you
	ev.on("itemEnchanted", func(_e): pillar(game.player.position, Color("c8a0ff")))
	# the rune forge's finish: a column of the rune's colour off the forge,
	# a ring and a fountain of sparks, and a burst of real light
	ev.on("runeForged", func(e):
		var st = game.rune_forge.station
		if st == null:
			return
		var c := Color(Runes.def(e.rune).glow.colour)
		var at := Vector3(st.position[0], Terrain.height_at(st.position[0], st.position[1]), st.position[1])
		pillar(at, c)
		shockwave(at + Vector3(0, 0.1, 0), 3.0, c)
		sparks(at + Vector3(0, 1.6, 0), 24, c)
		light(at, null, {"energy": 4.0, "range": 7.0, "life": 1.0, "height": 1.7}, c)
		game.shake_camera(DB.CONFIG.impact.shake))
	# a refine: gold light off the altar (or the Refiner's hands) when it
	# takes, a dull violet puff when a refine fails
	ev.on("refined", func(e):
		var at := Vector3(e.position[0], Terrain.height_at(e.position[0], e.position[1]), e.position[1])
		if e.ok:
			pillar(at, Color("ffe6a0"))
			shockwave(at + Vector3(0, 0.1, 0), 2.6, Color("ffd890"))
			sparks(at + Vector3(0, 1.6, 0), 20, Color("ffe6a0"))
			light(at, null, {"energy": 3.5, "range": 6.0, "life": 0.9, "height": 1.7}, Color("ffd890"))
		else:
			sparks(at + Vector3(0, 1.6, 0), 10, Color("7a6a90"))
			dust(at + Vector3(0, 1.0, 0), 8))
	ev.on("itemScrapped", func(_e): sparks(game.player.position, 12, Color("c8a0ff")))
	ev.on("enemyDefeated", func(e):
		dust(e.enemy.position, 10)
		kill_punch(e.enemy))
	# the Grave Slam lands where the telegraph was painted
	ev.on("graveSlam", func(e):
		var sh = e.shape
		var r: float = sh.range * 0.55
		shockwave(Vector3(sh.x + sin(sh.angle) * r, game.player.position.y, sh.z + cos(sh.angle) * r), sh.range * 0.6))
	# a light scuff of dust, not a cloud (smaller and fainter, Dan 2026-11-02);
	# a spirit's hop raises none
	ev.on("playerJumped", func(e):
		if not game.player.ghost:
			ground_puff(e.position, 3, 0.5))
	ev.on("playerLanded", func(e):
		if not game.player.ghost:
			ground_puff(e.position, 4, clampf(e.speed / 6.8, 0.5, 0.8)))
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
	ev.on("spellFlash", func(e): flash(e.position, Color(e.colour) if e.has("colour") else SCHOOL_COLOURS.get(e.get("school"), Color("ffe08a"))))
	ev.on("zone", func(e):
		var field := zone(e.x,e.z,e.radius,e.duration,SCHOOL_COLOURS.get(e.get("school"),Color("ffd070")))
		if e.has("key"):
			keyed_zones[e.key] = field)
	ev.on("zoneGone", func(e):
		var field = keyed_zones.get(e.key)
		if field != null:
			field.life = maxf(0.001, field.age)
			keyed_zones.erase(e.key))
	ev.on("classImpact", func(e): shockwave(e.position,e.radius,SCHOOL_COLOURS.get(e.school,Color.WHITE)))
	ev.on("classAffliction", func(e): flash(e.position,SCHOOL_COLOURS.get(e.school,Color.WHITE)))
	ev.on("shieldAbsorbed", func(e): flash(e.position,Color("f5d780") if e.id == "lightShield" else Color("a592ff")))
	ev.on("tarIgnited", func(e): shockwave(e.position,2.0,Color("ff8030")))
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
	light(under, null, {"life": 0.1, "energy": 0.0}, Color.WHITE)
	zone(under.x, under.z, 1, 0.1)
	ground_puff(under, 1, 1.0)
	var splat := Tex.ground_quad(Tex.fx_material(Tex.splat(), Color("4e0806"), false))
	splat.position = under
	_add(splat, 0.1, func(_it, _k, _dt): pass)
	var drop := Tex.sprite(Tex.fx_material(Tex.drop(), Color("9a1612"), false, true))
	drop.position = under
	_add(drop, 0.1, func(_it, _k, _dt): pass)
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
	var tag := str(obj.name) # its name before the scene makes a twin's unique
	game.scene.add_child(obj)
	var it := {"obj": obj, "life": life, "age": 0.0, "update": update, "tag": tag}
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


## `o` (an effect part) can make them bigger and longer lived: `spread`
## (sideways speed), `rise` [min, max] upward speed, `life`, `size`,
## `gravity` and `height` (where they start above `pos`).
func sparks(pos: Vector3, n: int, colour := Color("ffc890"), o := {}) -> void:
	var spread: float = o.get("spread", 4.0)
	var rise: Array = o.get("rise", [1.5, 4.0])
	var life: float = o.get("life", 0.3)
	var size: float = o.get("size", 0.25)
	var gravity: float = o.get("gravity", 12.0)
	for i in n:
		var s := Tex.sprite(Tex.fx_material(Tex.glint(), colour, true, true))
		s.scale = Vector3.ONE * size
		s.position = Vector3(pos.x, pos.y + o.get("height", 1.1), pos.z)
		var v := Vector3((randf() - 0.5) * spread, lerpf(rise[0], rise[1], randf()), (randf() - 0.5) * spread)
		_add(s, life * (1 + randf() * 0.5), func(it, k, dt):
			it.obj.position += it.v * dt
			it.v.y -= gravity * dt
			it.obj.material_override.albedo_color.a = 1 - k * k, {"v": v})


## A burst of real light that flares and dies away (`p`: `colour`,
## `energy`, `range`, `height`, `life`). No shadows, and only its energy
## changes as it plays, so it costs no more than a lamp for a moment.
func light(at: Vector3, follow, p: Dictionary, colour: Color) -> void:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.omni_range = p.get("range", 8.0)
	l.shadow_enabled = false
	l.light_energy = 0
	var energy: float = p.get("energy", 3.0)
	var height: float = p.get("height", 1.5)
	l.position = at + Vector3.UP * height
	_add(l, p.get("life", 1.2), func(it, k, _dt):
		if follow:
			it.obj.position = follow.position + Vector3.UP * height
		it.obj.light_energy = energy * minf(1, k / 0.06) * pow(1 - k, 1.6))


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
## after `life` seconds. `look` (a spell id) adds that spell's
## `projectile` shapes (data/abilities/spell_fx.json), carried along its flight.
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
	var look: Array = DB.spell_fx.get(p.get("look", ""), {}).get("projectile", [])
	if not look.is_empty():
		var holder := Node3D.new()
		holder.add_child(obj)
		for part in look:
			holder.add_child(_carried(part))
		obj = holder
	var aimed := not bolt or not look.is_empty()
	var from: Vector3 = p.from
	var to: Vector3 = p.to
	var a := from
	var b := Vector3(to.x, Terrain.height_at(to.x, to.z) + 1.0, to.z)
	obj.position = a
	var life = p.get("life")
	var time: float = life if life != null else maxf(0.08, a.distance_to(b) / p.speed)
	var trail = p.get("trail", arrow_trail(p) if kind == "arrow" else null)
	if kind == "arrow":
		release_puff(a, b)
	_add(obj, maxf(0.05, time), func(it, k, dt):
		if trail != null:
			it.emit -= dt
			# Carry the fraction forward: resetting the timer lost emissions
			# at 60 Hz and made the same arrow look different by frame rate.
			var emitted := 0
			while it.emit <= 0 and emitted < 4:
				it.emit += TRAIL_EVERY
				trail_bit(it.obj.position, trail)
				emitted += 1
			if emitted == 4:
				it.emit = maxf(0, it.emit)
		if it.follow:
			var fp: Vector3 = it.follow.position
			it.b = Vector3(fp.x, Terrain.height_at(fp.x, fp.z) + 1.0, fp.z)
		var o: Node3D = it.obj
		o.position = it.a.lerp(it.b, k)
		# a slight arc for arrows
		if not bolt:
			o.position.y += sin(k * PI) * minf(1.2, it.a.distance_to(it.b) * 0.04)
		if aimed:
			_look(o, it.b), {"a": a, "b": b, "follow": follow, "emit": 0.0})
	if aimed:
		_look(obj, b)


## What an arrow leaves in the air behind it (Dan 2026-11-03): embers from a
## fire arrow (an ability of the fire school, or the look's `trail`) or a
## runed bow in its rune's colour, else a tiny faint wisp, just the air
## cutting behind the shaft (Dan 2026-11-04: no glow on a plain arrow).
const TRAIL_EVERY := 0.022


func arrow_trail(p: Dictionary) -> Dictionary:
	var id: String = p.get("look", "")
	var look: Dictionary = DB.spell_fx.get(id, {})
	if look.has("trail"):
		return look.trail
	var sp = DB.spells.get(id)
	if sp is Dictionary and sp.get("school") == "fire":
		return {"colour": "#ff8030", "embers": true}
	var bow = game.inventory.ranged_weapon if game.inventory else null
	var rune := Runes.of(bow)
	if rune != "":
		var g = Runes.def(rune).get("glow", {})
		return {"colour": g.get("colour", "#ffd090"), "embers": true}
	return {"colour": "#f4f0e840", "embers": false}


var _trail_mats := {}


## one mote of an arrow's trail: it shrinks away; embers also rise and drift
func trail_bit(pos: Vector3, tr: Dictionary) -> void:
	var c := str(tr.get("colour", "#fff2dc"))
	var embers: bool = tr.get("embers", false)
	if not _trail_mats.has(c):
		_trail_mats[c] = Tex.fx_material(Tex.glint(), Color(c), true, true)
	var mote := Tex.sprite(_trail_mats[c])
	mote.name = "ArrowMote"
	var size := (0.2 + randf() * 0.12) if embers else 0.045
	mote.scale = Vector3.ONE * size
	mote.position = pos + (Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.08 if embers else Vector3.ZERO)
	var drift := Vector3(randf() - 0.5, 1.0, randf() - 0.5) * (0.7 if embers else 0.0)
	_add(mote, 0.4 if embers else 0.1, func(it, k, dt):
		it.obj.scale = Vector3.ONE * size * (1.0 - k)
		it.obj.position += drift * dt)


## the bow let go: a small burst of air off the string, toward the shot
func release_puff(from: Vector3, to: Vector3) -> void:
	if not _trail_mats.has("release"):
		_trail_mats.release = Tex.fx_material(Tex.glint(), Color(1, 0.96, 0.88, 0.7), true, true)
	var pop := Tex.sprite(_trail_mats.release)
	pop.position = from + (to - from).normalized() * 0.25
	_add(pop, 0.12, func(it, k, _dt):
		it.obj.scale = Vector3.ONE * (0.25 + k * 0.5) * (1.0 - k))
	sparks(from, 3, Color("fff0d8"), {"spread": 1.5, "size": 0.12, "life": 0.18, "rise": [0.3, 1.0]})


## one shape carried by a projectile, its forward (+z) along the flight:
## `mesh`, `colour`, `glow`, `scale`, `forward` (metres ahead of the head)
func _carried(p: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = fx_mesh(p.mesh)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := Tex.fx_material(null, Color(Color(p.get("colour", "#ffffff")), p.get("glow", 1.0)))
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	var sc: Array = p.get("scale", [1, 1, 1])
	mi.scale = Vector3(sc[0], sc[1], sc[2])
	mi.position.z = p.get("forward", 0.0)
	return mi


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
		if Assets.has(name):
			path = Assets.model_path(name)
		if ResourceLoader.exists(path):
			var n: Node = load(path).instantiate()
			var found := n.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				var source: Mesh = found[0].mesh
				mesh = Assets._srgb_mesh(source) if source is ArrayMesh else source
			n.free()
		_fx_meshes[name] = mesh
	return _fx_meshes[name]


## when a look's parts play: while a cast is drawn out, as it goes, flying
## with its bolt or arrow, and where it lands
const PHASES := ["windup", "cast", "projectile", "impact"]


static func _has_look(id: String, phase: String) -> bool:
	return not DB.spell_fx.get(id, {}).get(phase, []).is_empty()


static func _look_meshes() -> Array:
	var names := {}
	for look in DB.spell_fx.values() + DB.fx_moments.values():
		if not look is Dictionary: # an `_about` note
			continue
		for phase in PHASES:
			for p in look.get(phase, []):
				if p.has("mesh"):
					names[p.mesh] = true
	return names.keys()


## A moment's look (data/abilities/spell_fx.json `moments`), played on you.
func moment(id: String) -> void:
	var p = game.player
	spell_fx({"id": id, "phase": "cast", "position": p.position, "facing": p.facing, "follow": p})


## A spell's own look: every part of its `cast` or `impact` list
## (data/abilities/spell_fx.json), each after its own delay.
## `e`: { id, phase, position, facing, follow (the player or null), tuning }
func spell_fx(e: Dictionary) -> void:
	var spell: Dictionary = DB.abilities.get(e.id, {})
	var school: Color = SCHOOL_COLOURS.get(spell.get("school"), SCHOOL_COLOURS.physical)
	for p in DB.spell_fx.get(e.id, DB.fx_moments.get(e.id, {})).get(e.phase, []):
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
			sparks(at, int(p.get("n", 6)), colour if p.has("colour") else Color("ffc890"), p)
		"light":
			light(at, follow, p, colour)
		"dust":
			dust(at, int(p.get("n", 6)), p.get("spread", 0.6))
		"flash":
			flash(at, colour)
		"shake":
			game.shake_camera(DB.CONFIG.impact.critShake if p.get("heavy") else DB.CONFIG.impact.shake)


## A melee blow connecting: hit-stop on both bodies, and on an auto attack
## a faint slash across the target in the swing's direction (main hand cuts
## down to the left, off hand down to the right).
## A compact contact flash that is visible from the gameplay camera on
## the first rendered hit frame. It never appears on misses or through walls.
func contact_impact(e: Dictionary) -> void:
	var enemy = e.enemy
	var crit: bool = e.get("crit", false)
	var high := clampf(enemy.radius * 1.6, 0.5, 1.35)
	var at: Vector3 = enemy.position + Vector3.UP * high + game.camera.global_basis.z * 0.35
	# a small, quick white pop where the blow lands: weight, not a light show
	# (the old cream glint and orange sparks read as a yellow flash, Dan 2026-11-02)
	var mat := Tex.fx_material(Tex.puff(), Color(1, 1, 1, 0.7), true, true)
	mat.render_priority = 2
	var pop := Tex.sprite(mat)
	pop.name = "HitContact"
	pop.position = at
	var size := 0.5 if crit else 0.34
	pop.scale = Vector3.ONE * size
	_add(pop, 0.1, func(it, k, _dt):
		it.obj.scale = Vector3.ONE * size * (1.0 + k * 0.6)
		mat.albedo_color.a = 0.7 * (1.0 - k) * (1.0 - k))
	# a crit or a weapon ability jolts the body back (the look only)
	var hard: bool = crit or (e.get("kind", "") == "strike" and not e.get("swing", false))
	if hard and e.get("hand", "") != "ranged" and enemy.rig:
		var p = game.player
		enemy.rig.knock(Vector3(enemy.position.x - p.position.x, 0, enemy.position.z - p.position.z), 0.26 if crit else 0.16)
	if game.settings.get_value("bloodEffects") and e.get("kind", "") == "strike":
		spatter(enemy, at, crit)


## What a blow knocks out of a foe: "red" blood from anything living, "bone"
## chips and grave dust from the undead, "straw" from the training dummy.
## An enemy's data can say (`blood`); otherwise it bleeds.
const BLOOD := {
	"red": [Color("9a1612"), Color("4e0806")],
	"bone": [Color("d8d0bc"), Color("8a8272")],
	"straw": [Color("d2b464"), Color("8a6c34")],
}


static func blood_of(enemy) -> String:
	var b = enemy.cfg.get("blood")
	if b:
		return str(b)
	return "straw" if enemy.cfg.get("dummy") else "red"


## The weight of an area blow (Dan 2026-11-03, Conquer Online's area hits):
## the more it catches, the harder the camera kicks, everything caught holds
## still for a beat, and a big catch flashes real light and throws up dust.
const SCHOOL_LIGHT := {"holy": Color("ffe6a0"), "fire": Color("ff9a50"), "shadow": Color("a070ff"), "nature": Color("a8e070")}


func aoe_weight(e: Dictionary) -> void:
	var hits: Array = e.get("hits", [])
	if hits.size() < 2:
		return
	var c: Dictionary = DB.CONFIG.impact
	game.shake_camera(c.shake * (1.0 + c.aoeShakePerHit * mini(hits.size(), 6)))
	for en in hits:
		if is_instance_valid(en) and en.rig:
			en.rig.hold(c.aoeHitStop)
	if hits.size() >= 3:
		var col: Color = SCHOOL_LIGHT.get(str(e.get("school", "")), Color("ffd9a0"))
		light(e.position, null, {"energy": 2.5, "range": e.get("radius", 4.0) * 1.8, "life": 0.4, "height": 0.8}, col)
		dust(e.position, 14, e.get("radius", 4.0) * 0.5)


## The killing blow lands harder: you hold still a moment longer, the camera
## kicks (more for an elite) and the body gives up a last spray.
func kill_punch(enemy) -> void:
	var p = game.player
	if p == null or p.position.distance_to(enemy.position) > 20.0:
		return
	var c: Dictionary = DB.CONFIG.impact
	var big: bool = enemy.type == "brute" or str(enemy.cfg.get("type", "")) in ["elite", "heavy"]
	if p.position.distance_to(enemy.position) <= 4.0 and p.rig:
		p.rig.hold(c.killHitStop)
	game.shake_camera(c.eliteKillShake if big else c.killShake)
	if game.settings.get_value("bloodEffects"):
		spatter(enemy, enemy.position + Vector3.UP * 1.0, true)


## A spray of drops thrown away from the player, a brief mist where the blow
## landed and, for blood, a splash on the ground that soaks in over seconds.
func spatter(enemy, at: Vector3, crit: bool) -> void:
	var kind := blood_of(enemy)
	var cols: Array = BLOOD.get(kind, BLOOD.red)
	var p = game.player
	var away := Vector3(enemy.position.x - p.position.x, 0, enemy.position.z - p.position.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(-away.z, 0, away.x)
	var floor_y: float = enemy.position.y + 0.04
	for i in (16 if crit else 10):
		var c: Color = cols[0].lerp(cols[1], randf())
		var mat := Tex.fx_material(Tex.drop(), c, false, true)
		mat.render_priority = 1
		var d := Tex.sprite(mat)
		d.name = "BloodDroplet" if kind == "red" else "HitChip"
		d.position = at
		var sz := randf_range(0.05, 0.12) * (1.3 if crit else 1.0)
		d.scale = Vector3.ONE * sz
		var v := away * randf_range(1.2, 3.8) + side * randf_range(-1.6, 1.6) + Vector3.UP * randf_range(0.4, 2.6)
		_add(d, randf_range(0.4, 0.6), func(it, k, dt):
			it.obj.position += it.v * dt
			it.v.y -= 14.0 * dt
			if it.obj.position.y < it.floor:
				it.obj.position.y = it.floor
				it.v = Vector3.ZERO
			mat.albedo_color.a = 1.0 if k < 0.6 else (1.0 - k) / 0.4, {"v": v, "floor": floor_y})
	var mist_mat := Tex.fx_material(Tex.puff(), Color(cols[0], 0.5), false, true)
	mist_mat.render_priority = 1
	var mist := Tex.sprite(mist_mat)
	mist.name = "BloodMist"
	mist.position = at
	_add(mist, 0.28, func(it, k, _dt):
		it.obj.scale = Vector3.ONE * (0.35 + k * 0.55) * (1.3 if crit else 1.0)
		mist_mat.albedo_color.a = 0.5 * (1.0 - k))
	if kind != "red":
		dust(enemy.position, 4 if crit else 2, 0.3)
		return
	for j in (2 if crit else 1):
		var off := away * randf_range(0.4, 1.2) + side * randf_range(-0.4, 0.4)
		var gx: float = enemy.position.x + off.x
		var gz: float = enemy.position.z + off.z
		var gm := Tex.fx_material(Tex.splat(), Color(cols[1], 0.85), false)
		var g := Tex.ground_quad(gm)
		g.name = "BloodSplat"
		g.position = Vector3(gx, Terrain.height_at(gx, gz) + 0.03, gz)
		g.rotation.y = randf() * TAU
		var gs := randf_range(0.55, 0.9) * (1.3 if crit else 1.0)
		g.scale = Vector3(gs * 0.3, 1, gs * 0.3)
		_add(g, 6.0, func(it, k, _dt):
			var grow := minf(1.0, k * 6.0 / 0.2)
			var sc := gs * (0.3 + 0.7 * grow)
			it.obj.scale = Vector3(sc, 1, sc)
			gm.albedo_color.a = 0.85 if k < 0.6 else 0.85 * (1.0 - k) / 0.4)


## Dust kicked out from the feet: a small ring as the player leaves the ground,
## a heavier one on landing (a harder landing throws more).
func ground_puff(pos: Vector3, n: int, strength: float) -> void:
	var y := Terrain.height_at(pos.x, pos.z)
	for i in n:
		var a := TAU * i / n + randf() * 0.6
		var dir := Vector3(cos(a), 0, sin(a))
		var mat := Tex.fx_material(Tex.puff(), Color(Color("a49378"), 0.0), false, true)
		mat.render_priority = 1
		var s := Tex.sprite(mat)
		s.name = "JumpDust"
		s.position = Vector3(pos.x, y + 0.15, pos.z) + dir * 0.25
		var sz := randf_range(0.22, 0.34) * strength
		s.scale = Vector3.ONE * sz
		var v := dir * randf_range(1.2, 2.4) * strength + Vector3.UP * randf_range(0.2, 0.7)
		_add(s, randf_range(0.35, 0.5), func(it, k, dt):
			it.obj.position += it.v * dt
			it.v *= maxf(0.0, 1.0 - 4.0 * dt)
			it.obj.scale = Vector3.ONE * it.sz * (0.6 + k * 1.4)
			mat.albedo_color.a = 0.4 * (1.0 - k) * minf(1.0, 0.3 + k * 8.0), {"v": v, "sz": sz})


func _blow_lands(e: Dictionary) -> void:
	var hand: String = e.get("hand", "main")
	var player = game.player
	var enemy = e.enemy
	if e.get("periodic", false) or e.get("kind") != "strike" or hand == "ranged" or e.get("damage", 0) <= 0:
		return
	if player.position.distance_to(enemy.position) > 4.0:
		return
	var c: Dictionary = DB.CONFIG.impact
	var t := minf(c.hitStopMax, c.hitStop + c.hitStopPerSecond * game.stats.hand_speed(hand))
	if e.get("crit"):
		t *= c.critHitStop
	player.rig.hold(t)
	enemy.rig.hold(t)
	if e.get("swing"):
		var facing := atan2(enemy.position.x - player.position.x, enemy.position.z - player.position.z)
		var slash := {"mesh": "fx_arc", "glow": 0.8 if not e.get("crit") else 1.0, "life": 0.23, "height": 1.1, "forward": -0.2,
			"faceCamera": true, "rot": [90, 0, 0], "angle": -30 if hand == "main" else 30, "size": [0.7, 0.95], "spin": 60 if hand == "main" else -60}
		_shape(slash, enemy.position, facing, null, Color("fff0d8"), {})


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
	var fall: float = p.get("fall", 0.0)
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
		holder.position = o + Vector3(sin(fa) * forward, height + fall * (1 - minf(1, k * 4)) ** 2, cos(fa) * forward)
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


## Weapon trails (Dan 2026-11-03): while a melee swing or a weapon ability
## plays, the blade leaves a short ribbon of light from hilt to tip that
## fades within a fifth of a second. One ImmediateMesh, rebuilt each frame
## only while a trail shows; nothing about the blow's timing changes.
const TRAIL_LIFE := 0.16
const TRAIL_SAMPLES := 14
var trail_mesh: ImmediateMesh
var trail_node: MeshInstance3D
var trail_pts: Array = [] ## [hilt, tip, age]
var trail_weapon: Node3D
var trail_local := [Vector3.ZERO, Vector3(0, 0.8, 0)] ## hilt and tip in the weapon's own space


func _trail_ends(w: Node3D) -> Array:
	var meshes := w.find_children("*", "MeshInstance3D", true, false)
	if w is MeshInstance3D:
		meshes.push_front(w)
	if meshes.is_empty():
		return [Vector3.ZERO, Vector3(0, 0.8, 0)]
	var mi: MeshInstance3D = meshes[0]
	var box: AABB = mi.get_aabb()
	var to_w: Transform3D = w.global_transform.affine_inverse() * mi.global_transform
	var axis := box.get_longest_axis_index()
	var lo := box.get_center()
	var hi := box.get_center()
	lo[axis] = box.position[axis]
	hi[axis] = box.end[axis]
	var a := to_w * lo
	var b := to_w * hi
	# the tip is the end further from the grip (the weapon's origin)
	return [a, b] if a.length() <= b.length() else [b, a]


func weapon_trail(dt: float) -> void:
	var p = game.player
	var rig = p.rig if p else null
	var off := false
	if rig != null and game.stats.dual_wielding:
		off = (rig.action != null and rig.action.get("trailHand") == "off") or (rig.off_action != null and (rig.action == null or rig.off_action.t < rig.action.t))
	var w: Node3D = (p.shield if off else p.weapon_part) if p else null
	var swinging: bool = rig != null and (off or (rig.action != null and (rig.action.type == "strike" or rig.action.get("trail", false)))) \
		and not p.bow_in_hand and w != null and w.is_visible_in_tree() and game.settings.get_value("weaponTrails") != false
	for pt in trail_pts:
		pt[2] += dt
	trail_pts = trail_pts.filter(func(pt): return pt[2] < TRAIL_LIFE)
	if swinging:
		if w != trail_weapon:
			trail_pts.clear()
			trail_weapon = w
			trail_local = _trail_ends(w)
		var g := w.global_transform
		var hilt: Vector3 = g * trail_local[0].lerp(trail_local[1], 0.3)
		var tip: Vector3 = g * trail_local[1]
		if trail_pts.is_empty() or trail_pts[-1][1].distance_to(tip) > 0.02:
			trail_pts.append([hilt, tip, 0.0])
			if trail_pts.size() > TRAIL_SAMPLES:
				trail_pts.pop_front()
	if trail_node == null:
		trail_mesh = ImmediateMesh.new()
		trail_node = MeshInstance3D.new()
		trail_node.name = "WeaponTrail"
		trail_node.mesh = trail_mesh
		trail_node.top_level = true
		trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = false
		trail_node.material_override = m
		game.scene.add_child(trail_node)
	trail_mesh.clear_surfaces()
	if trail_pts.size() < 2:
		return
	var col: Color = Color("b9d7ff") if off else Color("fff0d8")
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in trail_pts.size():
		var pt: Array = trail_pts[i]
		var a: float = (1.0 - pt[2] / TRAIL_LIFE) * (float(i + 1) / trail_pts.size())
		trail_mesh.surface_set_color(Color(col.r, col.g, col.b, a * 0.05))
		trail_mesh.surface_add_vertex(pt[0])
		trail_mesh.surface_set_color(Color(col.r, col.g, col.b, a * 0.55))
		trail_mesh.surface_add_vertex(pt[1])
	trail_mesh.surface_end()


func update(dt: float) -> void:
	weapon_trail(dt)
	for it in items.duplicate():
		it.age += dt
		var k: float = minf(1, it.age / it.life)
		it.update.call(it, k, dt)
		if k >= 1:
			RenderCleanup.detach(it.obj)
			it.obj.queue_free()
			items.erase(it)
	for key in keyed_zones.keys():
		var field: Dictionary = keyed_zones[key]
		if field.age >= field.life:
			keyed_zones.erase(key)
