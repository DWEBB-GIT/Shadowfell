class_name ToolBelt
extends PanelContainer
## The tool belt (Dan, 2026-11-02): one button in the bag tray (the tool
## pack's slot, or T) folds a column of tools up out of it. The tool is the
## button: the rod casts, the camp kit pitches camp, the torch lights, and
## so on, so a profession never needs a slot of its own on the spell bar.
## Picks, skinning and herb knives and lockpicks work by themselves when you
## use a vein, a carcass, a plant or a lock; clicking them says so.

const PX := 40 ## a belt slot, as big as a bag socket

var game
var hud
var column: VBoxContainer
var entries: Array = [] ## [{kind: 'ability'|'item', id, tip}]
var _sig := ""
var cells: Array = [] ## the belt's slots, top to bottom
var pick := -1 ## the pad's highlight (-1: none)


func _init(g, h) -> void:
	game = g
	hud = h
	add_theme_stylebox_override("panel", UI.frame(Vector4(5, 5, 5, 5)))
	mouse_filter = Control.MOUSE_FILTER_STOP
	column = UI.vbox(self, 3)
	visible = false


func toggle() -> void:
	if hud.modal:
		return
	game.audio.sfx("bag", 0.6)
	visible = not visible
	_sig = ""
	refresh()
	hud.items._render_sockets(game.inventory) # the button lights while open


func close() -> void:
	if visible:
		hud.items.cursor_tip_off()
	visible = false
	pick = -1


## what the belt holds now: the belt abilities you know, then each tool you
## carry (one of each), the rod folded into Fishing
static func collect(g) -> Array:
	var out: Array = []
	var owned := {}
	var rod = null
	# only the tool pack's tools (the bags', before it is earned): a tool
	# works only from the belt
	for i in g.inventory.sockets.size():
		var bag = g.inventory.sockets[i]
		if not bag or (g.inventory.tool_pack and i != Items.TOOL_SOCKET):
			continue
		for st in bag.slots:
			if not st:
				continue
			var def := Items.get_def(st.id)
			if def.get("kind") != "tool" and def.get("kind") != "torch":
				continue
			if def.get("rod", false):
				if rod == null or def.get("fishingSkill", 0) > Items.get_def(rod).get("fishingSkill", 0):
					rod = st.id
				continue
			owned[st.id] = true
	var off = g.inventory.equipment.get("offHand")
	if off and Items.get_def(off.id).get("kind") == "torch":
		owned[off.id] = true
	for a in ActionBar.BELT_ABILITIES:
		if not DB.abilities.has(a) or not g.skills.knows_ability(a):
			continue
		# Make Camp lights a fire and opens cooking, so Cook needs no slot
		# of its own (Dan, 2026-11-02)
		if a == "cook" and g.skills.knows_ability("setCamp"):
			continue
		var e := {"kind": "ability", "id": a}
		if a == "fish":
			e.item = rod # the rod's picture; greyed with no rod
		out.append(e)
	for id in owned:
		out.append({"kind": "item", "id": id})
	return out


func refresh() -> void:
	if not visible:
		return
	var list := collect(game)
	var sig := str(list)
	if sig == _sig:
		return
	_sig = sig
	entries = list
	UI.clear(column)
	cells = []
	if entries.is_empty():
		var l := UI.label(column, "No tools yet", 12, UI.TEXT_DIM)
		l.custom_minimum_size = Vector2(PX * 2, 0)
	for e in entries:
		var s := ISlot.new("t:" + e.id, PX)
		if e.kind == "ability":
			var it = e.get("item")
			if it:
				s.show_stack({"id": it, "count": 1}, hud.icons)
			else:
				s.icon = hud.icons.abilities.get(e.id)
			s.border = UI.BORDER
			if e.id == "fish" and it == null:
				s.dim = 0.45
		else:
			s.show_stack({"id": e.id, "count": 1}, hud.icons)
			var off = game.inventory.equipment.get("offHand")
			s.lit = off != null and off.id == e.id # the torch you hold
		var entry: Dictionary = e
		cells.append(s)
		s.on_input = func(_s, ev: InputEventMouseButton):
			if ev.pressed and (ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
				use(entry)
		s.on_hover = func(_s, on: bool):
			if on:
				hud.items.cursor_tip(tip(entry))
			else:
				hud.items.cursor_tip_off()
		column.add_child(s)
	size = Vector2.ZERO


## On a pad (D-pad down opens it): up and down move along the belt, A uses
## the tool, B (or down past the bottom) folds it away.
func gamepad(pad) -> void:
	var B := Pad.BUTTONS
	# this runs every frame the belt is open: off the pad it must leave the
	# highlight and the tooltip alone, or the last tool's tip (Return Home)
	# stuck over every other button (Dan, 2026-11-02)
	if not hud.pad_mode:
		if pick >= 0:
			pick = -1
			for c in cells:
				if is_instance_valid(c) and c.focused:
					c.focused = false
					c.queue_redraw()
		return
	if cells.is_empty():
		if pad.pressed(B.B) or pad.pressed(B.DOWN):
			close()
		return
	if pick < 0 or pick >= cells.size():
		pick = cells.size() - 1 # the tool nearest the tray
	if pad.pressed(B.UP):
		pick = maxi(0, pick - 1)
	elif pad.pressed(B.DOWN):
		if pick == cells.size() - 1:
			close()
			return
		pick += 1
	elif pad.pressed(B.B):
		close()
		return
	elif pad.pressed(B.A):
		use(entries[pick])
	for i in cells.size():
		var c: ISlot = cells[i]
		if is_instance_valid(c) and c.focused != (i == pick):
			c.focused = i == pick
			c.queue_redraw()
	if pick < entries.size():
		hud.items.cursor_tip(tip(entries[pick]))


func tip(e: Dictionary) -> String:
	if e.kind == "ability":
		var ab: Dictionary = DB.abilities[e.id]
		if e.id == "fish" and e.get("item") == null:
			return "Fishing: you need a fishing rod"
		return ab.get("name", e.id)
	var def := Items.get_def(e.id)
	return "%s: %s" % [def.get("name", e.id), _passive(def)]


func _passive(def: Dictionary) -> String:
	if def.get("kind") == "torch":
		return "click to light it or put it away"
	if def.get("miningPick", false):
		return "used by itself when you mine a vein"
	if def.get("skinningKnife", false):
		return "used by itself when you skin a kill"
	if def.has("herbalismSkill"):
		return "used by itself when you pick herbs"
	if def.get("id") == "lockpicks":
		return "used by itself on a lock"
	return "carried"


func use(e: Dictionary) -> void:
	if e.kind == "ability":
		if e.id == "fish" and e.get("item") == null:
			hud.error("You need a fishing rod")
			return
		# already by a fire: cook there rather than pitch another camp
		if e.id == "setCamp" and game.skills.knows_ability("cook") and game.cooking.near_fire != "":
			if not hud.panel_open("cooking"):
				hud.toggle_window("cooking")
			return
		game.action_bar.clicked[e.id] = true
		return
	var def := Items.get_def(e.id)
	if def.get("kind") == "torch":
		game.inventory.use_from_bar(e.id)
		_sig = ""
		refresh()
		return
	hud.toast("%s: %s" % [def.get("name", e.id), _passive(def)])


## stands on top of the tool pack's slot in the tray, its bottom on the tray's top
func place(anchor: Rect2) -> void:
	if not visible:
		return
	size = get_combined_minimum_size()
	position = Vector2(roundf(anchor.get_center().x - size.x / 2), anchor.position.y - 10 - size.y)
