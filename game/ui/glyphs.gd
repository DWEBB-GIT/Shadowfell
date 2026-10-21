class_name Glyphs
extends RefCounted
## The painted spell glyphs (src/ui/icons.js abilityIcons), stroke for
## stroke on a 64 px tile: a few spells have their own picture, every other
## spell gets one painted from its kind in its school's colour.

const SCHOOL := {"holy": "#ffd070", "shadow": "#a86ae8", "nature": "#8ad04a", "fire": "#ff8a3a", "physical": "#d8d0c0"}
## spells that reuse another's picture
const SAME_AS := {"heavyStrike": "strike", "crushingBlow": "shieldBreak"}
const OWN := ["strike", "shieldBreak", "lunge", "brace", "rebuke", "hallowedBolt", "rend", "quickShot", "venomArrow", "smite", "hallowedGround", "cleave", "setCamp", "cook", "fish", "battleCry"]


## every spell with a picture: its own, or one painted from its kind
static func ids() -> Array:
	var out: Array = OWN.duplicate()
	out.append_array(SAME_AS.keys())
	for a in DB.abilities.values():
		if not out.has(a.id) and a.get("kind"):
			out.append(a.id)
	return out


## Paint one glyph: the dark tile, then the picture.
static func paint(g: Canvas2D, id: String, size := 64.0) -> void:
	var grad := g.create_radial_gradient(size / 2, size / 2, 4, size / 2, size / 2, size * 0.7)
	Canvas2D.add_color_stop(grad, 0, "#3a2f22")
	Canvas2D.add_color_stop(grad, 1, "#100c09")
	g.fill_style = grad
	g.fill_rect(0, 0, size, size)
	id = SAME_AS.get(id, id)
	match id:
		"strike": _strike(g)
		"shieldBreak": _shieldBreak(g)
		"lunge": _lunge(g)
		"brace": _brace(g)
		"rebuke": _rebuke(g)
		"hallowedBolt": _hallowedBolt(g)
		"rend": _rend(g)
		"quickShot": _quickShot(g)
		"venomArrow": _venomArrow(g)
		"smite": _smite(g)
		"hallowedGround": _hallowedGround(g)
		"cleave": _cleave(g)
		"setCamp": _setCamp(g)
		"cook": _cook(g)
		"fish": _fish(g)
		"battleCry": _battleCry(g)
		_:
			if DB.abilities.has(id):
				_kind_glyph(g, DB.abilities[id])


static func _line(g: Canvas2D, pts: Array) -> void:
	g.begin_path()
	for i in pts.size():
		if i:
			g.line_to(pts[i][0], pts[i][1])
		else:
			g.move_to(pts[i][0], pts[i][1])
	g.stroke()


static func _dot(g: Canvas2D, x: float, y: float, r: float) -> void:
	g.begin_path()
	g.arc(x, y, r, 0, TAU)
	g.fill()


static func _ring(g: Canvas2D, r: float, from := 0.0, to := TAU) -> void:
	g.begin_path()
	g.arc(32, 32, r, from, to)
	g.stroke()


static func _glow(g: Canvas2D, x: float, y: float, r0: float, r: float, stops: Array) -> void:
	var gr := g.create_radial_gradient(x, y, r0, x, y, r)
	for s in stops:
		Canvas2D.add_color_stop(gr, s[0], s[1])
	g.fill_style = gr
	g.begin_path()
	g.arc(x, y, r, 0, TAU)
	g.fill()


# ------------------------------------------------------------- own pictures
static func _strike(g: Canvas2D) -> void:
	# a sword slash
	g.stroke_style = "#c8c4b8"
	g.line_width = 5
	_line(g, [[14, 50], [48, 16]])
	g.stroke_style = "#8a6a3a"
	g.line_width = 6
	_line(g, [[10, 42], [22, 54]])
	g.stroke_style = "rgba(230,200,140,0.6)"
	g.line_width = 2
	g.begin_path()
	g.arc(30, 34, 24, -1.9, -0.3)
	g.stroke()


static func _shieldBreak(g: Canvas2D) -> void:
	# a burst cracking the ground
	g.stroke_style = "#e0b060"
	g.line_width = 3
	for i in 8:
		var a := i / 8.0 * TAU
		_line(g, [[32 + cos(a) * 9, 34 + sin(a) * 9], [32 + cos(a) * 24, 34 + sin(a) * 24]])
	g.fill_style = "#f2d9a0"
	_dot(g, 32, 34, 7)


static func _lunge(g: Canvas2D) -> void:
	# a forward charge
	g.stroke_style = "#c8c4b8"
	g.line_width = 4
	g.begin_path()
	g.move_to(12, 32)
	g.line_to(50, 32)
	g.line_to(40, 22)
	g.move_to(50, 32)
	g.line_to(40, 42)
	g.stroke()
	g.stroke_style = "rgba(200,170,110,0.6)"
	g.line_width = 2
	for y in [22, 42]:
		_line(g, [[10, y], [28, y]])


static func _brace(g: Canvas2D) -> void:
	# a kite shield
	g.fill_style = "#4f6a8a"
	g.stroke_style = "#c8d4e0"
	g.line_width = 3
	g.begin_path()
	g.move_to(32, 10)
	g.line_to(50, 18)
	g.quadratic_curve_to(50, 42, 32, 56)
	g.quadratic_curve_to(14, 42, 14, 18)
	g.close_path()
	g.fill()
	g.stroke()
	g.stroke_style = "#e0c070"
	g.begin_path()
	g.move_to(32, 16)
	g.line_to(32, 48)
	g.move_to(20, 28)
	g.line_to(44, 28)
	g.stroke()


static func _rebuke(g: Canvas2D) -> void:
	# a spell broken: a spark of gold under a struck-through ring
	_glow(g, 32, 32, 1, 14, [[0, "#fff6d0"], [0.6, "#ffc850"], [1, "rgba(255,160,40,0)"]])
	g.stroke_style = "#d84a30"
	g.line_width = 5
	g.begin_path()
	g.arc(32, 32, 21, 0, TAU)
	g.move_to(17, 17)
	g.line_to(47, 47)
	g.stroke()


static func _hallowedBolt(g: Canvas2D) -> void:
	# a mote of gold fire with its trail
	g.stroke_style = "rgba(255,210,120,0.55)"
	g.line_width = 6
	_line(g, [[10, 54], [36, 28]])
	_glow(g, 40, 24, 2, 16, [[0, "#fff6d0"], [0.5, "#ffc850"], [1, "rgba(255,160,40,0)"]])


static func _rend(g: Canvas2D) -> void:
	# three claw tears and drops of blood
	g.stroke_style = "#c03a2a"
	g.line_width = 4
	for x in [18, 30, 42]:
		g.begin_path()
		g.move_to(x, 12)
		g.quadratic_curve_to(x - 6, 30, x - 2, 46)
		g.stroke()
	g.fill_style = "#8a1a14"
	for p in [[16, 54], [28, 56], [40, 53]]:
		_dot(g, p[0], p[1], 3)


static func _arrow(g: Canvas2D, head: String) -> void:
	g.stroke_style = "#d8c8a0"
	g.line_width = 3
	_line(g, [[12, 52], [50, 14]])
	g.fill_style = head
	g.begin_path()
	g.move_to(54, 10)
	g.line_to(42, 14)
	g.line_to(50, 22)
	g.close_path()
	g.fill()


static func _quickShot(g: Canvas2D) -> void:
	# an arrow in flight with speed lines
	_arrow(g, "#c8c4b8")
	g.stroke_style = "#a04a2a"
	g.line_width = 3
	for p in [[12, 52], [17, 47]]:
		g.begin_path()
		g.move_to(p[0], p[1])
		g.line_to(p[0] - 4, p[1] - 8)
		g.move_to(p[0], p[1])
		g.line_to(p[0] + 8, p[1] + 4)
		g.stroke()
	g.stroke_style = "rgba(255,230,170,0.6)"
	g.line_width = 2
	for o in [-10, 10]:
		_line(g, [[16 + o, 36 + o], [30 + o, 22 + o]])


static func _venomArrow(g: Canvas2D) -> void:
	# an arrow dripping green venom
	_arrow(g, "#7ad04a")
	g.fill_style = "#5aa83a"
	for d in [[44, 30, 3.5], [40, 40, 3], [46, 46, 2.5]]:
		_dot(g, d[0], d[1], d[2])
	_glow(g, 48, 16, 1, 14, [[0, "rgba(160,255,110,0.7)"], [1, "rgba(90,200,60,0)"]])


static func _smite(g: Canvas2D) -> void:
	# a star of light
	g.fill_style = "#ffe9a8"
	g.begin_path()
	for i in 16:
		var a := i / 16.0 * TAU - PI / 2
		var r := 7.0 if i % 2 else (18.0 if i % 4 else 26.0)
		g.line_to(32 + cos(a) * r, 32 + sin(a) * r)
	g.close_path()
	g.fill()


static func _hallowedGround(g: Canvas2D) -> void:
	# a glowing ring on the ground with a rune inside
	g.stroke_style = "#ffd070"
	g.line_width = 4
	g.begin_path()
	g.ellipse(32, 38, 24, 12, 0, 0, TAU)
	g.stroke()
	g.stroke_style = "rgba(255,220,140,0.7)"
	g.line_width = 2
	for x in [20, 32, 44]:
		_line(g, [[x, 36], [x, 14 + absf(x - 32) * 0.5]])


static func _cleave(g: Canvas2D) -> void:
	# a broad arc of a swing
	g.stroke_style = "#d8d0c0"
	g.line_width = 6
	g.begin_path()
	g.arc(32, 46, 26, -2.6, -0.55)
	g.stroke()
	g.stroke_style = "rgba(230,180,110,0.6)"
	g.line_width = 2
	g.begin_path()
	g.arc(32, 46, 18, -2.4, -0.75)
	g.stroke()
	g.fill_style = "#8a6a3a"
	g.fill_rect(28, 44, 8, 14)


static func _setCamp(g: Canvas2D) -> void:
	# a campfire under a little tent
	g.fill_style = "#7a5c3a"
	g.begin_path()
	g.move_to(32, 10)
	g.line_to(54, 44)
	g.line_to(10, 44)
	g.close_path()
	g.fill()
	g.fill_style = "#1a120c"
	g.begin_path()
	g.move_to(32, 22)
	g.line_to(40, 44)
	g.line_to(24, 44)
	g.fill()
	g.fill_style = "#ffa040"
	g.begin_path()
	g.ellipse(32, 50, 6, 9, 0, 0, TAU)
	g.fill()
	g.stroke_style = "#6a4a2a"
	g.line_width = 3
	g.begin_path()
	g.move_to(20, 58)
	g.line_to(44, 52)
	g.move_to(20, 52)
	g.line_to(44, 58)
	g.stroke()


static func _cook(g: Canvas2D) -> void:
	# a pot over flames
	g.fill_style = "#e07a2a"
	for f in [[22, 16], [32, 22], [42, 16]]:
		var x: float = f[0]
		var h: float = f[1]
		g.begin_path()
		g.move_to(x - 6, 58)
		g.quadratic_curve_to(x - 4, 58 - h * 0.6, x, 58 - h)
		g.quadratic_curve_to(x + 4, 58 - h * 0.6, x + 6, 58)
		g.fill()
	g.fill_style = "#4a4440"
	g.begin_path()
	g.ellipse(32, 30, 18, 12, 0, 0, PI)
	g.fill()
	g.fill_rect(14, 26, 36, 5)
	g.stroke_style = "rgba(220,220,210,0.6)"
	g.line_width = 2
	g.begin_path()
	g.move_to(26, 22)
	g.quadratic_curve_to(22, 15, 27, 8)
	g.move_to(37, 22)
	g.quadratic_curve_to(41, 15, 36, 8)
	g.stroke()


static func _fish(g: Canvas2D) -> void:
	# a rod, its line and a bob on the water
	g.stroke_style = "#8a6a3a"
	g.line_width = 3
	_line(g, [[8, 56], [44, 10]])
	g.stroke_style = "rgba(220,220,200,0.7)"
	g.line_width = 1
	g.begin_path()
	g.move_to(44, 10)
	g.quadratic_curve_to(52, 30, 46, 44)
	g.stroke()
	g.stroke_style = "#5a8a9a"
	g.line_width = 2
	g.begin_path()
	g.ellipse(46, 48, 12, 4, 0, 0, TAU)
	g.stroke()
	g.fill_style = "#d04030"
	_dot(g, 46, 45, 4)


static func _battleCry(g: Canvas2D) -> void:
	# sound waves from a shout
	g.stroke_style = "#ff9a5a"
	g.line_width = 3
	for r in [8, 16, 24]:
		g.begin_path()
		g.arc(14, 32, r, -0.8, 0.8)
		g.stroke()
	g.fill_style = "#e0c070"
	g.begin_path()
	g.move_to(8, 26)
	g.line_to(16, 32)
	g.line_to(8, 38)
	g.fill()


# ------------------------------------------------------------- by kind
## A plain glyph for a spell without its own: the shape says what it does
## (a slash, a bolt, drops for a dot, a ring for ground...), the colour its school.
static func _kind_glyph(g: Canvas2D, a: Dictionary) -> void:
	var c: String = SCHOOL.get(a.get("school", ""), "#d8d0c0")
	var tuning: Dictionary = a.get("tuning", {})
	g.stroke_style = c
	g.fill_style = c
	g.line_width = 4
	var kind: String = a.get("kind", "")
	if a.get("ranged"):
		# an arrow, with the spell's mark at its head
		g.stroke_style = "#d8c8a0"
		_line(g, [[12, 52], [48, 16]])
		_line(g, [[48, 16], [36, 18]])
		_line(g, [[48, 16], [46, 28]])
		g.fill_style = c
		if kind == "dot":
			_dot(g, 48, 16, 6)
		if tuning.get("maxTargets", 0) > 1:
			_line(g, [[8, 40], [36, 12]])
			_line(g, [[24, 56], [52, 28]])
		if kind == "cast":
			_ring(g, 24, -2.4, -0.6)
		return
	match kind:
		"instant", "charge":
			_line(g, [[14, 50], [48, 16]])
			if tuning.get("bothHands"):
				_line(g, [[16, 16], [50, 50]])
			if not tuning.has("damageMultiplier"):
				_dot(g, 32, 32, 8)
			g.line_width = 2
			_ring(g, 22, -1.9, -0.3)
		"dot":
			for p in [[20, 22], [34, 34], [44, 18], [26, 46]]:
				_dot(g, p[0], p[1], 5)
		"cast", "channel":
			g.global_alpha = 0.5
			_line(g, [[10, 54], [34, 30]])
			g.global_alpha = 1
			_dot(g, 40, 24, 11)
			if kind == "channel":
				g.line_width = 2
				_line(g, [[8, 40], [16, 34], [24, 40], [32, 34], [40, 40], [48, 34], [56, 40]])
		"aoe", "trap":
			_ring(g, 20)
			g.line_width = 2
			_ring(g, 12)
			if kind == "trap":
				for i in 8:
					var t := i / 8.0 * TAU
					_line(g, [[32 + cos(t) * 20, 32 + sin(t) * 20], [32 + cos(t) * 26, 32 + sin(t) * 26]])
		"burst":
			for i in 10:
				var t := i / 10.0 * TAU
				_line(g, [[32 + cos(t) * 8, 32 + sin(t) * 8], [32 + cos(t) * 24, 32 + sin(t) * 24]])
		"control":
			# an eye, or closed for sleep
			g.line_width = 3
			_line(g, [[10, 32], [22, 22], [42, 22], [54, 32], [42, 42], [22, 42], [10, 32]])
			if not a.get("applies", {}).get("sleep"):
				_dot(g, 32, 32, 6)
			else:
				_line(g, [[14, 32], [50, 32]])
		"stealth":
			_dot(g, 32, 32, 20)
			g.fill_style = "#100c09"
			_dot(g, 40, 26, 18)
		"guard", "shield":
			if kind == "shield":
				g.global_alpha = 0.35
				_dot(g, 32, 32, 22)
				g.global_alpha = 1
			_ring(g, 22)
			_line(g, [[32, 14], [32, 50]])
		"leap":
			_line(g, [[50, 32], [14, 32]])
			_line(g, [[14, 32], [24, 22]])
			_line(g, [[14, 32], [24, 42]])
			g.line_width = 2
			_ring(g, 20, -2.6, -0.5)
		"purge":
			g.begin_path()
			g.move_to(32, 10)
			g.quadratic_curve_to(50, 34, 32, 54)
			g.quadratic_curve_to(14, 34, 32, 10)
			g.fill()
		_:
			_dot(g, 32, 32, 12)
