class_name XpOrbs
extends RefCounted
## Cosmetic XP orbs: when an enemy falls, a few small purple motes (the
## colour of the "+N XP" popup) burst from the body, then home in on the
## player and chase them if they keep walking. The XP itself is granted at
## once (combat.gd); the orbs are only the show, nothing is collected.
## Kept cheap for the web build: two shared MultiMeshes (heads and trails),
## a fixed pool, no lights, no per-orb nodes.

const COLOUR := Color("b77cff") ## damage_numbers.gd "xp"
const GLOW := Color(0.62, 0.32, 1.0) ## a deeper purple, so additive light stays purple and never washes white
const MAX_ORBS := 160 ## a huge pack still fits; older orbs are reused past this
const TRAIL := 8 ## trail dots behind each orb
const TRAIL_STEP := 0.016 ## seconds between trail samples
const SIZE := 0.24 ## head size in metres
const MIN_PER_KILL := 3
const MAX_PER_KILL := 8
const CHEST := 1.1 ## where on the player they fly to

var game
var heads: MultiMesh
var trails: MultiMesh
var nodes: Array[MultiMeshInstance3D] = []
var orbs: Array = [] ## { pos, vel, age, delay, hist: Array[Vector3], tick, size }
var flashes: Array = [] ## { age } a soft pulse on the player as orbs land


func _init(g) -> void:
	game = g
	var tex := Tex._radial([[0.0, Color(1, 1, 1, 1)], [0.2, Color(1, 1, 1, 0.75)], [0.5, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0)]], 32)
	heads = _multimesh(MAX_ORBS + 8)
	trails = _multimesh(MAX_ORBS * TRAIL)
	for mm in [trails, heads]:
		var n := MultiMeshInstance3D.new()
		n.multimesh = mm
		var m := Tex.fx_material(tex, Color.WHITE, true, true)
		m.vertex_color_use_as_albedo = true
		m.billboard_keep_scale = true
		n.material_override = m
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.extra_cull_margin = 16384
		n.visible = false
		game.scene.add_child(n)
		nodes.append(n)
	game.events.on("xpGained", func(e): _on_xp(e))


func _multimesh(count: int) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = count
	mm.visible_instance_count = 0
	return mm


## more XP, more orbs, within a small range so a pack stays readable
static func count_for(amount: float) -> int:
	return clampi(MIN_PER_KILL + int(amount / 30.0), MIN_PER_KILL, MAX_PER_KILL)


func _on_xp(e: Dictionary) -> void:
	var target = e.get("target")
	if target == null or not ("position" in target):
		return
	spawn(target.position, count_for(float(e.get("amount", 0))))


## burst `n` orbs from a body at `at` (feet)
func spawn(at: Vector3, n: int) -> void:
	for i in n:
		if orbs.size() >= MAX_ORBS:
			orbs.pop_front()
		var ang := randf() * TAU
		var out := randf_range(1.2, 2.6)
		var p := at + Vector3(0, 0.9 + randf() * 0.4, 0)
		orbs.append({
			"pos": p,
			"vel": Vector3(cos(ang) * out, randf_range(2.4, 4.0), sin(ang) * out),
			"age": 0.0, "delay": i * 0.045 + randf() * 0.05,
			"hist": [p], "tick": 0.0, "size": SIZE * randf_range(0.8, 1.15),
		})


func update(dt: float) -> void:
	if orbs.is_empty() and flashes.is_empty():
		if nodes[0].visible:
			for n in nodes:
				n.visible = false
		return
	var player = game.player
	var goal: Vector3 = player.position + Vector3(0, CHEST, 0) if player else Vector3.ZERO
	var keep: Array = []
	for o in orbs:
		o.age += dt
		if o.age < o.delay:
			keep.append(o)
			continue
		var t: float = o.age - o.delay
		var to: Vector3 = goal - o.pos
		var dist := to.length()
		if t > 0.2 and (dist < 0.35 or t > 4.0) or dist > 80.0:
			if dist < 1.0:
				flashes.append({"age": 0.0})
			continue
		if t < 0.22:
			# the burst: thrown up and out, slowing in the air
			o.vel += Vector3(0, -6.0, 0) * dt
			o.vel *= exp(-2.5 * dt)
		else:
			# then home in, faster and tighter the longer it flies, so it
			# always catches a player who runs away
			var h := t - 0.22
			var speed := 7.0 + h * 22.0 + maxf(0.0, dist - 6.0) * 0.8
			var steer := 5.0 + h * 18.0
			o.vel = o.vel.lerp(to / maxf(dist, 0.001) * speed, 1.0 - exp(-steer * dt))
			# never overshoot the chest in one frame
			if o.vel.length() * dt > dist:
				o.vel = to / dt
		o.pos += o.vel * dt
		o.tick += dt
		if o.tick >= TRAIL_STEP:
			o.tick = 0.0
			o.hist.push_front(o.pos)
			if o.hist.size() > TRAIL:
				o.hist.pop_back()
		keep.append(o)
	orbs = keep
	_draw(goal, dt)


func _draw(goal: Vector3, dt: float) -> void:
	var h := 0
	var tr := 0
	for o in orbs:
		if o.age < o.delay:
			continue
		var fade_in := minf(1.0, (o.age - o.delay) / 0.08)
		var s: float = o.size * (0.6 + 0.4 * fade_in)
		heads.set_instance_transform(h, Transform3D(Basis.from_scale(Vector3(s, s, s)), o.pos))
		heads.set_instance_color(h, Color(GLOW, fade_in))
		h += 1
		var hist: Array = o.hist
		for i in hist.size():
			var k := 1.0 - float(i + 1) / float(TRAIL + 1)
			var ts := s * (0.3 + 0.55 * k)
			trails.set_instance_transform(tr, Transform3D(Basis.from_scale(Vector3(ts, ts, ts)), hist[i]))
			trails.set_instance_color(tr, Color(GLOW, 0.6 * k * fade_in))
			tr += 1
	# a soft purple pulse on the chest as each orb lands
	var keep: Array = []
	for f in flashes:
		f.age += dt
		if f.age >= 0.22 or h >= heads.instance_count:
			continue
		var k: float = f.age / 0.22
		var fs := 0.35 + 0.5 * k
		heads.set_instance_transform(h, Transform3D(Basis.from_scale(Vector3(fs, fs, fs)), goal))
		heads.set_instance_color(h, Color(GLOW, 0.45 * (1.0 - k)))
		h += 1
		keep.append(f)
	flashes = keep
	heads.visible_instance_count = h
	trails.visible_instance_count = tr
	for n in nodes:
		n.visible = h > 0 or tr > 0
