class_name KeybindUI
extends RefCounted
## The key bindings list in the Settings window, plus Quick bind
## (src/ui/keybindUI.js): while it is on, hovering a spell or utility bar
## slot and pressing a key binds it there.

var game
var hud
var waiting = null ## action id waiting for a key
var waiting_slot := -1
var quick := false
var hovered = null ## bar slot index under the mouse during Quick bind
var list: VBoxContainer ## filled by render, inside the Settings window
var quick_button: Button


func _init(g, h) -> void:
	game = g
	hud = h
	game.events.on("keysChanged", func(_e):
		render()
		hud.apply_key_labels())


func render() -> void:
	if list == null or not is_instance_valid(list):
		return
	UI.clear(list)
	var keys = game.keys
	var group := ""
	for a in Keybinds.KEY_ACTIONS:
		if a.group != group:
			group = a.group
			var g := UI.label(list, group.to_upper(), 11, UI.TEXT_DIM)
			g.add_theme_constant_override("line_spacing", 0)
		var row := UI.hbox(list, 6)
		var l := UI.label(row, a.label, 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for slot in 2:
			var bindings: Array = keys.map.get(a.id, [])
			var current: String = bindings[slot] if slot < bindings.size() else ""
			var listening: bool = waiting == a.id and waiting_slot == slot
			var text := "Key / mouse…" if listening else (Keybinds.key_label(current) if current != "" else "Not bound")
			var id: String = a.id
			var index: int = slot
			var b := UI.button(row, text, func(): listen(id, index))
			b.tooltip_text = "Primary binding" if slot == 0 else "Alternate binding"
			b.custom_minimum_size = Vector2(94, 0)
			if listening:
				b.add_theme_color_override("font_color", UI.GOLD)
				b.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), UI.GOLD, 0, 1, Vector4(8, 2, 8, 2)))
	if quick_button:
		quick_button.add_theme_color_override("font_color", UI.GOLD if quick else UI.TEXT)


## wait for the next key and bind it (Escape cancels, Backspace unbinds)
func listen(id: String, slot := 0) -> void:
	waiting = id
	waiting_slot = slot
	render()
	game.input.capture = func(code: String, shift: bool):
		if code.begins_with("Shift"):
			return # a modifier: wait for the key it goes with
		game.input.capture = Callable()
		waiting = null
		var combo := Keybinds.combo_of(code, shift)
		if code == "Backspace":
			game.keys.unbind(id, slot)
		elif code != "Escape" and not game.keys.bind(id, combo, slot):
			hud.error("%s cannot be bound" % Keybinds.key_label(combo))
		render()


func set_quick(on: bool) -> void:
	quick = on
	hud.quick_bind_banner.visible = on
	render()
	if not on:
		game.input.capture = Callable()
		return
	game.input.capture = func(code: String, shift: bool):
		if code == "Escape":
			set_quick(false)
			return
		if hovered == null or code.begins_with("Shift"):
			return
		var combo := Keybinds.combo_of(code, shift)
		if not game.keys.bind("bar%d" % hovered, combo):
			hud.error("%s cannot be bound" % Keybinds.key_label(combo))
