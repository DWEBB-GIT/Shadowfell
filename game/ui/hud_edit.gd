class_name HudEdit
extends Control
## Edit mode for the HUD (Dan, 2026-11-02), as WoW's Edit Mode or FFXIV's
## HUD Layout: every piece shows an outline with its name; drag it on an
## 8 px grid. A moved piece is kept against the nearest corner, edge middle
## or the centre of the screen, so a layout survives a change of resolution.
## Right click a piece to put it back. Saved per character.

const GRID := 8.0
const STORE := "shadowfell.hud_layout"

var game
var hud
var saved := {} ## piece id -> {"a": Vector2 (0, 0.5 or 1 per axis), "o": Vector2}
var drag = null ## {id, grab: Vector2 (cursor minus the piece's top left)}
var hover := ""
var bar: PanelContainer ## Reset all / Done
var _loaded_for := "" ## the store key the layout was read from
var hint_label: Label


func _init(g, h) -> void:
	game = g
	hud = h
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	bar = UI.panel(self, 10, UI.WINDOW)
	var row := UI.hbox(bar, 8)
	var hint := UI.label(row, "Edit HUD: drag to move, right click to reset", 13, UI.GOLD)
	hint.set_meta("pad", "Edit HUD: LB/RB pick, D-pad moves, X resets it, Y resets all, B done")
	hint.set_meta("mouse", hint.text)
	hint_label = hint
	UI.button(row, "Reset all", func(): reset_all())
	UI.button(row, "Done", func(): close())


## [id, name, [the main node, then nodes that move with it]]
func pieces() -> Array:
	return [
		["minimap", "Minimap", [hud.minimap]],
		["objectives", "Objectives", [hud.quests.tracker]],
		["chat", "Chat", [hud.log_scroll, hud.log_tabs, hud.log_grip, hud.log_shade]],
		["you", "Your frame", [hud.char_panel]],
		["target", "Target frame", [hud.target]],
		["bar", "Spell bar", [hud.bottom]],
		["bags", "Bags and tools", [hud.dock]],
		["menus", "Menus", [hud.menus]],
		["cast", "Cast and progress bar", [hud.cast.root]],
		["swing", "Swing timer", [hud.swing.root, hud.swing_off.root]],
	]


func _key() -> String:
	return STORE + ("." + str(game.character.id) if game.character else "")


func load_layout() -> void:
	saved = {}
	var s = Store.get_item(_key())
	if s is String and s != "":
		var d = str_to_var(s)
		if d is Dictionary:
			saved = d


func _save() -> void:
	Store.set_item(_key(), var_to_str(saved))


## after the default layout: move each piece the player placed
func apply(vp: Vector2) -> void:
	if _key() != _loaded_for: # another character came in
		_loaded_for = _key()
		load_layout()
	for p in pieces():
		var nodes: Array = p[2]
		var main: Control = nodes[0]
		if main == null or not saved.has(p[0]):
			continue
		var s: Dictionary = saved[p[0]]
		var a: Vector2 = s.a
		var sz := main.size
		var at: Vector2 = (a * vp + s.o - a * sz).round()
		at = at.clamp(Vector2.ZERO, (vp - sz).max(Vector2.ZERO))
		var d: Vector2 = at - main.position
		for n in nodes:
			if n != null:
				(n as Control).position += d


func open() -> void:
	if hud.modal:
		return
	if game.resources.in_combat or game.targeting.attacking:
		hud.error("Not while fighting")
		return
	hud.items.close_all()
	hud.modal = "edit"
	visible = true
	hud.root.move_child(self, -1)


func close() -> void:
	drag = null
	visible = false
	if hud.modal == "edit":
		hud.modal = null


func reset_all() -> void:
	saved = {}
	_save()
	hud.items.reset_windows()


func _rect(nodes: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for n in nodes:
		var c: Control = n
		if c == null or c.size == Vector2.ZERO:
			continue
		var cr := Rect2(c.position, c.size)
		r = cr if first else r.merge(cr)
		first = false
	return r


func _at(pos: Vector2) -> String:
	# the smallest piece under the cursor, so the cast bar wins over the bar
	var best := ""
	var area := INF
	for p in pieces():
		var r := _rect(p[2])
		if r.has_point(pos) and r.get_area() < area:
			best = p[0]
			area = r.get_area()
	return best


func _piece(id: String) -> Array:
	for p in pieces():
		if p[0] == id:
			return p
	return []


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var id := _at(mb.position)
			if id != "":
				var main: Control = _piece(id)[2][0]
				drag = {"id": id, "grab": mb.position - main.position}
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if drag != null:
				_save()
			drag = null
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var id := _at(mb.position)
			if id != "" and saved.has(id):
				saved.erase(id)
				_save()
		accept_event()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		hover = _at(mm.position)
		if drag != null:
			_move(drag.id, mm.position - drag.grab)
		accept_event()


## put a piece's top left at `at` (snapped), keeping it against its nearest anchor
func _move(id: String, at: Vector2) -> void:
	var vp := get_viewport_rect().size
	var main: Control = _piece(id)[2][0]
	var sz := main.size
	at = (at / GRID).round() * GRID
	at = at.clamp(Vector2.ZERO, (vp - sz).max(Vector2.ZERO))
	var c := at + sz / 2
	var a := Vector2(roundf(c.x / vp.x * 2) / 2, roundf(c.y / vp.y * 2) / 2)
	saved[id] = {"a": a, "o": at + a * sz - a * vp}


var pad_pick := 0 ## the piece the pad moves
var _pad_wait := 0.0


## On a pad: LB / RB pick a piece, the D-pad or left stick moves it a grid
## step at a time, X puts it back, Y resets everything, B or Start is done.
func gamepad(pad, dt: float) -> void:
	var B := Pad.BUTTONS
	var list := pieces()
	if pad.pressed(B.B) or pad.pressed(B.START):
		close()
		return
	if pad.pressed(B.RB):
		pad_pick = (pad_pick + 1) % list.size()
	if pad.pressed(B.LB):
		pad_pick = (pad_pick - 1 + list.size()) % list.size()
	var id: String = list[pad_pick][0]
	hover = id
	if pad.pressed(B.X) and saved.has(id):
		saved.erase(id)
		_save()
	if pad.pressed(B.Y):
		reset_all()
	var d := Vector2(pad.left.x, pad.left.y) if pad.left.z > 0.5 else Vector2.ZERO
	if pad.held(B.LEFT): d.x = -1
	if pad.held(B.RIGHT): d.x = 1
	if pad.held(B.UP): d.y = -1
	if pad.held(B.DOWN): d.y = 1
	_pad_wait -= dt
	if d == Vector2.ZERO:
		_pad_wait = 0.0
		return
	if _pad_wait > 0:
		return
	_pad_wait = 0.06
	var main: Control = list[pad_pick][2][0]
	_move(id, main.position + Vector2(signf(roundf(d.x)), signf(roundf(d.y))) * GRID)
	_save()


func _process(_dt: float) -> void:
	if visible:
		var vp := get_viewport_rect().size
		hint_label.text = hint_label.get_meta("pad" if hud.pad_mode else "mouse")
		bar.size = bar.get_combined_minimum_size()
		bar.position = Vector2(roundf((vp.x - bar.size.x) / 2), roundf(vp.y * 0.32))
		queue_redraw()


func _draw() -> void:
	var vp := size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.25))
	var line := Color(1, 0.9, 0.6, 0.06)
	var x := 0.0
	while x < vp.x:
		draw_line(Vector2(x, 0), Vector2(x, vp.y), line, 1.0)
		x += GRID * 4
	var y := 0.0
	while y < vp.y:
		draw_line(Vector2(0, y), Vector2(vp.x, y), line, 1.0)
		y += GRID * 4
	# the centre lines, to line pieces up on
	draw_line(Vector2(vp.x / 2, 0), Vector2(vp.x / 2, vp.y), Color(1, 0.85, 0.4, 0.25), 1.0)
	draw_line(Vector2(0, vp.y / 2), Vector2(vp.x, vp.y / 2), Color(1, 0.85, 0.4, 0.25), 1.0)
	for p in pieces():
		var r := _rect(p[2])
		if r.size == Vector2.ZERO:
			continue
		var lit: bool = hover == p[0] or (drag != null and drag.id == p[0])
		draw_rect(r, Color(0.9, 0.7, 0.3, 0.22 if lit else 0.12))
		draw_rect(r, UI.GOLD if lit else Color(0.85, 0.7, 0.4, 0.8), false, 2.0)
		var label: String = p[1] + (" *" if saved.has(p[0]) else "")
		draw_string(UI.bold, r.position + Vector2(6, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
