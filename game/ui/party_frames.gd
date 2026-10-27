class_name PartyFrames
extends VBoxContainer
## Party members down the left edge, WoW style: a small round portrait with
## the level on it, the name, and health and mana bars running out from it.
## Hidden while you travel alone. Whoever runs the party (companions now,
## other players if the game goes multiplayer) fills `members` with
## { name, level, health, max_health, mana, max_mana, model? }.

const W := 170.0
const PIC := 40.0

var hud
var members: Array = []
var _frames: Array = [] ## one per member: { root, img, badge, name, hp, mp, model }


func _init(h) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	visible = false


func layout(at: Vector2) -> void:
	position = at
	size = get_combined_minimum_size()


func update() -> void:
	visible = not members.is_empty() and hud.modal != "title"
	if not visible:
		return
	while _frames.size() < members.size():
		_frames.append(_frame())
	for i in _frames.size():
		var f: Dictionary = _frames[i]
		f.root.visible = i < members.size()
		if i >= members.size():
			continue
		var m: Dictionary = members[i]
		f.name.text = m.get("name", "")
		f.badge.text = str(m.get("level", 1))
		var dead: bool = m.get("health", 0) <= 0
		f.name.add_theme_color_override("font_color", UI.TEXT_DIM if dead else Color("e8d8b0"))
		hud.set_fill(f.hp, m.get("health", 0) / maxf(1, m.get("max_health", 1)))
		f.hp.text.text = "Dead" if dead else "%d" % ceili(m.get("health", 0))
		f.mp.root.visible = m.get("max_mana", 0) > 0
		if f.mp.root.visible:
			hud.set_fill(f.mp, m.get("mana", 0) / maxf(1, m.get("max_mana", 1)))
		var model = m.get("model")
		if model != f.model:
			f.model = model
			f.img.texture = hud.icons.portrait(model) if model else null


func _frame() -> Dictionary:
	var f := Control.new()
	f.mouse_filter = Control.MOUSE_FILTER_STOP # clicks here never walk you
	f.custom_minimum_size = Vector2(W, PIC + 8)
	add_child(f)
	var col := UI.vbox(f, 2)
	var w: float = W - PIC + hud.BAR_UNDER * 0.6
	col.custom_minimum_size.x = w
	col.position = Vector2(W - w, 0)
	var pic: Dictionary = hud._portrait(f, PIC)
	pic.root.position = Vector2(0, 2)
	var n := UI.label(col, "", 12, Color("e8d8b0"), 4)
	n.add_theme_stylebox_override("normal", hud._indent(false))
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var hp: Dictionary = hud._unit_bar(col, Color("5cb048"), Color("2a6a20"), 13, false, 9)
	var mp: Dictionary = hud._unit_bar(col, Color("5a8ad8"), Color("24407e"), 7, false, 1)
	mp.text.visible = false
	return {"root": f, "img": pic.img, "badge": pic.badge, "name": n, "hp": hp, "mp": mp, "model": null}
