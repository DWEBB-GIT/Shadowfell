class_name WorldLabels
extends Control
## Text over things in the world, from one pool of labels
## (src/ui/worldLabels.js): the names of items lying on the ground in their
## rarity colour (as in WoW and Diablo), nameplates over townsfolk (with
## their title) and enemies (until their health bar, which carries the name,
## takes over), and your own name over your character. Settings (O) hide
## each. Nothing shows through a roof: a label inside a building only shows
## while you are in there too.

const RANGE := 18.0 ## metres from the Warden

var game
var pool: Array = [] ## Labels, reused frame to frame


func _init(g) -> void:
	game = g
	name = "WorldLabels"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## each entry: { text, sub?, colour, at: Vector3, loot? }
func _names() -> Array:
	var out := []
	var settings = game.settings
	var player = game.player
	if settings.get_value("playerName") and game.character and not player.dead:
		out.append({"text": game.character.name, "colour": Color("f0e6c8"), "at": player.position + Vector3(0, 2.15, 0)})
	if not settings.get_value("names"):
		return out
	for n in game.npcs.list:
		out.append({"text": n.name, "sub": "<%s>" % n.def.title if n.def.get("title") else "", "colour": Color("9ee070"), "at": n.position + Vector3(0, 2.15, 0)})
	for e in game.enemies.list:
		if not e.alive or game.hud.enemy_bars.has(e.id):
			continue
		var h: float = e.cfg.get("barHeight", 3.0 if e.cfg.get("elite") else 2.1)
		out.append({"text": e.cfg.name, "colour": Color("ff8a50") if e.cfg.get("elite") else Color("e8604a"), "at": e.position + Vector3(0, h, 0)})
	return out


func _ground_items() -> Array:
	var out := []
	if not game.settings.get_value("lootNames"):
		return out
	for l in game.loot.active:
		var r = l.def.get("reward")
		# quest pick-ups (firewood, ore...) carry no name: their sparkle and
		# the quest log show them (Dan, 2026-10-19)
		if l.def.get("quest"):
			continue
		if r == null or not r.get("item") or not DB.items.has(r.item) or not game.loot.available(l):
			continue
		var v := Items.view({"id": r.item, "rolls": r.get("rolls")})
		var n: int = r.get("count", 1)
		out.append({"text": v.name + (" ×%d" % n if n > 1 else ""), "colour": Items.rarity_colour(v.get("rarity", "common")), "at": Vector3(l.x, l.base_y + 0.75, l.z), "loot": true})
	return out


func update(_dt := 0.0) -> void:
	var cam: Camera3D = game.camera
	var vp := get_viewport_rect().size
	var p: Vector3 = game.player.position
	var n := 0
	for lab in _ground_items() + _names():
		var at: Vector3 = lab.at
		if U.hyp(at.x - p.x, at.z - p.z) > RANGE:
			continue
		if game.world and game.world.roof_over(at.x, at.z):
			continue # indoors, under a roof you can see
		if cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		if s.x < -vp.x * 0.05 or s.x > vp.x * 1.05 or s.y < -vp.y * 0.05 or s.y > vp.y * 1.05:
			continue
		var l: Label
		if n < pool.size():
			l = pool[n]
		else:
			l = UI.label(self, "", 12, Color.WHITE, 4)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_constant_override("line_spacing", -2)
			pool.append(l)
		var text: String = lab.text + ("\n" + lab.sub if lab.get("sub", "") != "" else "")
		if l.text != text:
			l.text = text
			l.size = l.get_combined_minimum_size()
		l.add_theme_color_override("font_color", lab.colour)
		var loot: bool = lab.get("loot", false)
		if l.get_meta("loot", false) != loot:
			l.set_meta("loot", loot)
			if loot:
				var bg := UI.box(Color(10 / 255.0, 8 / 255.0, 6 / 255.0, 0.55), Color(0, 0, 0, 0), 0, 0, Vector4(4, 0, 4, 0))
				bg.set_corner_radius_all(2)
				l.add_theme_stylebox_override("normal", bg)
			else:
				l.remove_theme_stylebox_override("normal")
			l.size = l.get_combined_minimum_size()
		l.position = (s - Vector2(l.size.x / 2, l.size.y)).round()
		l.visible = true
		n += 1
	for i in range(n, pool.size()):
		pool[i].visible = false
