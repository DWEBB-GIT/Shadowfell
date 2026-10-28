class_name DamageNumbers
extends Control
## Floating damage numbers: serif figures that drift up and fade
## (src/ui/damageNumbers.js).
##   dealt  parchment white      taken  dull red "-n"
##   crit   amber, "!"           block  grey "Block"     heal  green "+n"
##   miss   grey "Miss", your blow that missed
##   xp     purple "+n XP", over a fallen enemy
## Each number is sized against your usual white hit: bigger than usual
## reads bigger. Crits stay longer, and a crit of twice your usual hit or
## more pulses once as it lands. Tuning in CONFIG.damageNumbers.

const MAX := 40
const COLOURS := {
	"dealt": Color("e6dcc4"), "taken": Color("c8524a"), "crit": Color("e8a84a"), "big": Color("ffc25a"),
	"takenCrit": Color("e0603c"), "block": Color("a8a8a0"), "miss": Color("a8a8a0"), "heal": Color("8cbf78"),
	"xp": Color("b77cff"),
}

var game
var items: Array = [] ## { label, pos, t, dx, life, crit, pulse }


func _init(g) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	game.events.on("damageNumber", add)
	game.events.on("xpGained", func(e): add({"target": e.target, "amount": e.amount, "kind": "xp"}))


## how big a number is against the usual hit (1 = the base font)
static func number_scale(amount: float, usual: float) -> float:
	var t: Dictionary = DB.CONFIG.damageNumbers
	if not usual or usual <= 0 or not amount:
		return 1.0
	return minf(t.maxScale, maxf(t.minScale, pow(amount / usual, t.sizePower)))


## your usual white hit with that hand, before armour
func usual_hit(hand := "main") -> float:
	var h := "ranged" if hand == "ranged" and game.inventory.ranged_weapon != null else "main"
	var r: Array = game.stats.swing_range_for(h)
	return (r[0] + r[1]) / 2.0


func add(e: Dictionary) -> void:
	var target = e.get("target")
	if target == null:
		return
	var t: Dictionary = DB.CONFIG.damageNumbers
	var kind: String = e.get("kind", "dealt")
	var amount = e.get("amount", 0)
	var crit: bool = e.get("crit", false)
	var blocked = e.get("blocked", 0)
	var text: String
	var cls := kind
	var ratio := 1.0
	if kind == "miss":
		text = "Miss"
	elif kind == "heal" or kind == "xp":
		if amount <= 0:
			return
		text = "+%s%s" % [U.n(amount), " XP" if kind == "xp" else ""]
	elif blocked and amount == 0:
		text = "Block"
		cls = "block"
	else:
		text = "%s%s%s" % ["-" if kind == "taken" else "", U.n(amount), "!" if crit else ""]
		if blocked:
			text += " (%s blocked)" % U.n(blocked)
		var ref: float = usual_hit(e.get("hand", "main")) if kind == "dealt" else float(e.get("usual", 0))
		ratio = amount / ref if ref > 0 else 1.0
	var pulse: bool = crit and ratio >= t.pulseAt
	var colour: Color = COLOURS.get(cls, COLOURS.dealt)
	if crit:
		colour = COLOURS.takenCrit if kind == "taken" else COLOURS.big if pulse else COLOURS.crit
	var scale_ := 0.8 if cls == "block" or cls == "miss" else number_scale(ratio, 1)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", roundi(t.font * scale_))
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var cfg = target.get("cfg")
	var high := 2.6 if cfg and cfg.get("elite") else 1.8
	# spread numbers a little so quick hits do not stack exactly
	var dx := (items.size() % 3) * 18 - 18
	var life: float = t.critLife if crit else t.life
	if kind == "xp":
		# above the killing blow's number, and it stays a while
		high += 0.6
		dx = 0
		life = t.critLife
	items.append({"label": l, "pos": target.position + Vector3(0, high, 0), "t": 0.0, "dx": dx, "crit": crit, "pulse": pulse, "life": life})
	while items.size() > MAX:
		items.pop_front().label.queue_free()


func update(dt: float) -> void:
	var cam: Camera3D = game.camera
	var t: Dictionary = DB.CONFIG.damageNumbers
	for i in range(items.size() - 1, -1, -1):
		var n: Dictionary = items[i]
		n.t += dt
		if n.t >= n.life:
			n.label.queue_free()
			items.remove_at(i)
			continue
		var k: float = n.t / n.life
		var l: Label = n.label
		l.visible = not cam.is_position_behind(n.pos)
		if not l.visible:
			continue
		var s := cam.unproject_position(n.pos)
		# crits pop in a touch large and settle; a huge crit swells once more
		var sc: float = 1 + 0.25 * maxf(0, 1 - n.t * 6) if n.crit else 1.0
		if n.pulse and n.t < 0.45:
			sc += t.pulse * sin(n.t / 0.45 * PI)
		l.pivot_offset = l.size / 2
		l.scale = Vector2(sc, sc)
		l.position = Vector2(s.x + n.dx, s.y - k * 50) - l.size / 2
		# everything fades over the last 40% of its life
		l.modulate.a = 1.0 if k < 0.6 else 1 - (k - 0.6) / 0.4


func clear() -> void:
	for n in items:
		n.label.queue_free()
	items = []
