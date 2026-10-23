class_name QuestUI
extends Control
## The quest side of the HUD (src/ui/questUI.js): the dialogue window, the
## trainer window, the quest log (L), the tracked objectives under the
## minimap, and the ! and ? over townsfolk. Like the bags, none of these
## pause the game.
##
## Gamepad: in the dialogue window up and down pick a choice, A takes it and
## B goes back. In the quest log up and down pick a quest, X tracks or
## untracks it, Y abandons it (press twice), and B closes.

const MARK := {"ready": "?", "available": "!", "active": "?"}
## each kind of choice has its own badge, so speech, buying and training read
## apart at a glance (Dan, 2026-10-16): [glyph, colour, badge]
const OPTION_ICON := {
	"ready": ["?", "#ffd23c", "#3a3008"], "available": ["!", "#ffd23c", "#3a3008"], "active": ["?", "#a8a8a8", "#000000"],
	"talk": ["❝", "#e8dcc0", "#3a3226"], "shop": ["⚖", "#ffe08a", "#5a4410"], "bye": ["✕", "#9a8f78", "#000000"],
	"accept": ["✓", "#9a8f78", "#000000"], "back": ["↩", "#9a8f78", "#000000"], "train": ["★", "#bfe0ff", "#1e3a5a"], "home": ["⌂", "#ffc890", "#5a2e12"],
}
const OPTION_TEXT := {"shop": "#f0e0a8", "train": "#cfe4f8", "ready": "#f0d890", "available": "#f0d890", "accept": "#b8e090"}
const GROUP_HEAD := {"quest": "QUESTS", "talk": "ASK ABOUT", "service": "SERVICES"}
const TRAIN_STATE := {"known": "Known", "locked": "", "poor": "Not enough money", "learn": ""}

var game
var hud
var log_open := false
var selected = null ## quest shown in the log
var choice := 0 ## gamepad highlight in the dialogue window
var confirm_abandon = null
var marks := {} ## npc id -> Label

var dialogue: Dictionary
var trainer: Dictionary
var quest_log: Dictionary
var tracker: PanelContainer
var tracker_box: VBoxContainer
var marks_layer: Control


func _init(g, h) -> void:
	game = g
	hud = h
	name = "QuestUI"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks_layer = Control.new()
	marks_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marks_layer)
	tracker = UI.panel(self, 0)
	tracker.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 0, 1, Vector4(10, 6, 10, 8)))
	tracker.custom_minimum_size = Vector2(260, 0)
	tracker_box = UI.vbox(tracker, 3)
	tracker.visible = false
	dialogue = UI.window(self, "", 340, func(): game.dialogue.close())
	_with_subtitle(dialogue)
	trainer = UI.window(self, "", 360, func(): game.dialogue.close())
	_with_subtitle(trainer)
	trainer.sub.text = "Trainer"
	quest_log = UI.window(self, "Quest log", 600, func(): toggle_log(false))
	_with_subtitle(quest_log)
	for w in [dialogue, trainer, quest_log]:
		w.panel.visible = false

	var ev = game.events
	ev.on("dialogueChanged", func(_e):
		choice = 0
		render_dialogue())
	ev.on("questsChanged", func(_e): render())
	ev.on("inventoryChanged", func(_e):
		if game.dialogue.is_open:
			render_dialogue())


func _with_subtitle(w: Dictionary) -> void:
	w.title.size_flags_horizontal = Control.SIZE_FILL
	w.sub = UI.label(null, "", 13, UI.TEXT_DIM)
	w.sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.head.add_child(w.sub)
	w.head.move_child(w.sub, 1)


var any_open: bool:
	get:
		return log_open or game.dialogue.is_open


func close_all() -> bool:
	var was := any_open
	game.dialogue.close()
	toggle_log(false)
	return was


func toggle_log(on = null) -> void:
	log_open = not log_open if on == null else on
	confirm_abandon = null
	var act: Array = game.quests.active
	if log_open and (selected == null or not act.has(selected)):
		selected = act[0] if not act.is_empty() else null
	render_log()


func select(id) -> void:
	selected = id
	confirm_abandon = null
	render_log()


func abandon() -> void:
	var id = selected
	if id == null:
		return
	if DB.quests[id].get("autoAccept"):
		game.events.emit("log", {"text": "That is the road you are on. It cannot be abandoned.", "kind": "muted", "throttle": "abandon"})
		return
	if confirm_abandon != id:
		confirm_abandon = id
		render_log()
		return
	game.quests.abandon(id)
	var act: Array = game.quests.active
	selected = act[0] if not act.is_empty() else null
	confirm_abandon = null
	render_log()


func render() -> void:
	render_tracker()
	render_log()
	if game.dialogue.is_open:
		render_dialogue()


# ------------------------------------------------------------ pieces
func _objectives(objs: Array) -> String:
	var out := ""
	for o in objs:
		out += "[color=%s]- %s[/color]\n" % ["#8cbf78" if o.done else UI.hex(UI.TEXT), UI.esc(Quests.line(o))]
	return "[font_size=12]%s[/font_size]" % out


func _sub(text: String) -> String:
	return "[font_size=11][color=#9a8f78]%s[/color][/font_size]\n" % text.to_upper()


func _rewards(r: Dictionary) -> String:
	var parts := []
	if r.get("coins"):
		var cr := U.coin_range(r.coins)
		parts.append(UI.money(cr[0]) if cr[0] == cr[1] else "%s – %s" % [UI.money(cr[0]), UI.money(cr[1])])
	if r.get("xp"):
		parts.append("%s experience" % U.n(r.xp))
	for f in r.get("reputation", {}):
		parts.append("+%s %s" % [U.n(r.reputation[f]), UI.esc(DB.factions[f].name)])
	for g in r.get("items", []):
		var def := Items.get_def(g.item)
		parts.append("{item:%s:26} [color=%s]%s[/color]%s" % [g.item, UI.hex(Items.rarity_colour(def.get("rarity", "common"))), UI.esc(def.name), " ×%d" % g.count if g.get("count", 1) > 1 else ""])
	return _sub("Rewards") + "    ".join(parts) + "\n" if not parts.is_empty() else ""


# ---------------------------------------------------------- dialogue
func render_dialogue() -> void:
	var page = game.dialogue.page
	dialogue.panel.visible = page != null and not page.has("train")
	trainer.panel.visible = page != null and page.has("train")
	if page == null:
		return
	choice = mini(choice, page.options.size() - 1)
	if page.has("train"):
		_render_trainer(page)
		return
	var w := dialogue
	w.title.text = page.name
	w.sub.text = page.title
	UI.clear(w.body)
	var q = page.get("quest")
	if q != null:
		var head := "Ready to hand in" if q.status == "ready" else "New quest" if q.status == "available" else "In progress"
		# one of several ways a story can go: taking it closes the others
		var text := "[font_size=15][color=#c9a45c]%s[/color][/font_size]\n[font_size=11][color=%s]%s[/color][/font_size]\n" % [UI.esc(q.name), "#ffd23c" if q.status != "active" else "#9a8f78", head.to_upper()]
		if q.choice and q.status == "available":
			text += "[font_size=12][color=#e8a860][i]A choice. Taking this closes the other ways.[/i][/color][/font_size]\n"
		UI.set_rich(UI.rich(w.body, 13), text)
	UI.wrapped(UI.label(w.body, ("%s %s" % [page.salutation, page.text]) if page.get("salutation", "") != "" else page.text, 14, Color("e6dbc0")))
	if q != null:
		UI.set_rich(UI.rich(w.body, 13), _sub("Objectives") + _objectives(q.objectives) + _rewards(q.reward))
	UI.rule(w.body)
	var opts := UI.vbox(w.body, 2)
	var group = null
	for i in page.options.size():
		var o: Dictionary = page.options[i]
		# a heading over each kind of choice (Goodbye stands apart)
		var g = o.get("group")
		if g != null and g != group:
			if g == "bye":
				UI.gap(opts, 6)
				UI.rule(opts)
			else:
				UI.label(opts, GROUP_HEAD.get(g, ""), 10, UI.TEXT_DIM)
		if g != null:
			group = g
		_option(opts, o, hud.pad_mode and i == choice)
	UI.hint(w.body).text = "A: choose   B: back" if hud.pad_mode else "Click a choice. Esc or walking away ends the conversation."
	layout()


## one choice in a conversation: its badge, then the words
func _option(parent: Node, o: Dictionary, focused: bool) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var flat := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 1, Vector4(34, 5, 6, 5))
	var lit := UI.box(Color(201 / 255.0, 164 / 255.0, 92 / 255.0, 0.12), UI.BORDER_DIM, 0, 1, Vector4(34, 5, 6, 5))
	b.add_theme_stylebox_override("normal", lit if focused else flat)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("pressed", lit)
	b.add_theme_font_size_override("font_size", 14)
	var col := Color(OPTION_TEXT.get(o.icon, UI.hex(UI.TEXT)))
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col)
	b.text = o.text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# a choice you can't take yet (too poor, missing materials) stays, dimmed
	if o.get("disabled", false):
		b.modulate.a = 0.5
	var id: String = o.id
	b.pressed.connect(func(): game.dialogue.choose(id))
	parent.add_child(b)
	var ic: Array = OPTION_ICON.get(o.icon, ["", "#9a8f78", "#000000"])
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(6, 4)
	badge.size = Vector2(22, 22)
	badge.draw.connect(func():
		badge.draw_circle(Vector2(11, 11), 11, Color.BLACK)
		badge.draw_circle(Vector2(11, 11), 10, Color(ic[2]) if ic[2] != "#000000" else Color(0, 0, 0, 0.45))
		var f := UI.bold
		var sz := f.get_string_size(ic[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		badge.draw_string(f, Vector2(11 - sz.x / 2, 11 + (f.get_ascent(13) - f.get_descent(13)) / 2), ic[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(ic[1])))
	b.add_child(badge)


## The trainer window, like the shop's: a row per skill or recipe with
## what it needs and costs, Learn, and Back to the conversation.
func _render_trainer(page: Dictionary) -> void:
	var w := trainer
	w.title.text = page.name
	UI.clear(w.body)
	var t := UI.label(w.body, page.text, 13, UI.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var list := UI.vbox(w.body, 4)
	for i in page.train.size():
		var r: Dictionary = page.train[i]
		var row := PanelContainer.new()
		var focused: bool = hud.pad_mode and i == choice
		row.add_theme_stylebox_override("panel", UI.box(Color(201 / 255.0, 164 / 255.0, 92 / 255.0, 0.12) if focused else Color(0, 0, 0, 0), UI.BORDER if focused else Color(0, 0, 0, 0), 0, 1, Vector4(4, 4, 4, 4)))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(row)
		var h := UI.hbox(row, 8)
		var ic := TextureRect.new()
		ic.texture = hud.icons.item(r.item) if r.get("item") else hud.icons.abilities.get(r.get("ability", ""))
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if r.state == "known" or r.state == "locked":
			ic.modulate = Color(0.55, 0.52, 0.48)
		h.add_child(ic)
		var body := UI.rich(h, 11)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var note: String = TRAIN_STATE.get(r.state, "")
		if note == "":
			note = r.get("need", "")
		var note_bb := " · [color=%s]%s[/color]" % ["#d06048" if r.state == "locked" or r.state == "poor" else "#9a8f78", UI.esc(note)] if note != "" else ""
		UI.set_rich(body, "[font_size=14][color=%s]%s[/color][/font_size]\n[color=#9a8f78]%s[/color]%s" % ["#9a8f78" if r.state == "known" else UI.hex(UI.TEXT), UI.esc(r.name), UI.esc(r.kind), note_bb])
		if r.state != "known":
			var cost := UI.rich(h, 12)
			cost.autowrap_mode = TextServer.AUTOWRAP_OFF
			UI.set_rich(cost, "[color=#d8c890]%s[/color]" % UI.money(r.cost))
		var id: String = r.id
		var b := UI.button(h, "Known" if r.state == "known" else "Learn", func(): game.dialogue.choose(id))
		b.disabled = r.state != "learn"
		if r.get("desc"):
			hud.items.tip_on(row, r.desc, r.name)
	var foot := UI.hbox(w.body, 5)
	var back := UI.button(foot, "↩ Back", func(): game.dialogue.back())
	if page.options.size() and choice == page.options.size() - 1 and hud.pad_mode:
		back.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), UI.GOLD, 0, 1, Vector4(8, 2, 8, 2)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(sp)
	var coins := UI.rich(foot, 13)
	coins.autowrap_mode = TextServer.AUTOWRAP_OFF
	UI.set_rich(coins, UI.money(game.inventory.coins))
	UI.hint(w.body).text = "A: learn   B: back" if hud.pad_mode else "Back returns to the conversation. Walking away ends it."
	layout()


# --------------------------------------------------------- quest log
func render_log() -> void:
	var w := quest_log
	w.panel.visible = log_open
	if not log_open:
		return
	var ql = game.quests
	var act: Array = ql.active
	w.sub.text = "%d in hand · %d done" % [act.size(), ql.done.size()]
	UI.clear(w.body)
	var cols := UI.hbox(w.body, 12)
	cols.custom_minimum_size = Vector2(0, 240)
	var list := UI.vbox(cols, 2)
	list.custom_minimum_size = Vector2(202, 0)
	if act.is_empty():
		var r := UI.rich(list, 12, 200)
		UI.set_rich(r, "[color=#9a8f78]No quests in hand. Look for a [color=#ffd23c]![/color] over someone's head.[/color]")
	for id in act:
		var s: String = ql.status(id)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = ("◆ " if ql.tracked.has(id) else "    ") + DB.quests[id].name + ("  (Complete)" if s == "ready" else "")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(202, 0)
		b.add_theme_font_size_override("font_size", 13)
		var sel: bool = id == selected
		b.add_theme_stylebox_override("normal", UI.box(Color(201 / 255.0, 164 / 255.0, 92 / 255.0, 0.16) if sel else Color(0, 0, 0, 0), UI.BORDER_DIM if sel else Color(0, 0, 0, 0), 0, 1, Vector4(6, 4, 6, 4)))
		b.add_theme_stylebox_override("hover", UI.box(Color(201 / 255.0, 164 / 255.0, 92 / 255.0, 0.08), UI.BORDER_DIM if sel else Color(0, 0, 0, 0), 0, 1, Vector4(6, 4, 6, 4)))
		b.add_theme_color_override("font_color", Color("ffd23c") if s == "ready" else UI.TEXT)
		var qid: String = id
		b.pressed.connect(func(): select(qid))
		list.add_child(b)
	var sep := ColorRect.new()
	sep.color = UI.BORDER_DIM
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(sep)
	var detail := UI.vbox(cols, 4)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id = selected
	if id == null or not act.has(id):
		if not ql.done.is_empty():
			var text := _sub("Completed")
			for d in ql.done:
				text += "[font_size=12][color=#9a8f78]%s[/color][/font_size]\n" % UI.esc(DB.quests[d].name)
			UI.set_rich(UI.rich(detail, 13), text)
	else:
		var q: Dictionary = DB.quests[id]
		var s: String = ql.status(id)
		var turn_in: String = DB.npcs[q.turnIn].name
		var text := "[font_size=15][color=#c9a45c]%s[/color][/font_size]\n%s\n" % [UI.esc(q.name), UI.esc(q.get("summary", ""))]
		text += _sub("Objectives") + _objectives(ql.objectives(id))
		text += "[font_size=12][color=#ffd23c]Return to %s.[/color][/font_size]\n" % UI.esc(turn_in) if s == "ready" else "[font_size=12][color=#9a8f78]Hand in to %s.[/color][/font_size]\n" % UI.esc(turn_in)
		text += _rewards(q.get("reward", {}))
		UI.set_rich(UI.rich(detail, 13), text)
		var acts := UI.hbox(detail, 8)
		var qid: String = id
		UI.button(acts, "Untrack" if ql.tracked.has(id) else "Track", func(): game.quests.set_tracked(qid, not game.quests.tracked.has(qid)))
		if not q.get("autoAccept"):
			var ab := UI.button(acts, "Really abandon?" if confirm_abandon == id else "Abandon", abandon)
			if confirm_abandon == id:
				ab.add_theme_color_override("font_color", Color("ff9070"))
				ab.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), Color("a05040"), 0, 1, Vector4(8, 2, 8, 2)))
	UI.hint(w.body).text = "Up/down: choose   X: track (up to %d)   Y: abandon   B: close" % Quests.MAX_TRACKED if hud.pad_mode else "Tracked quests (up to %d) show under the map. L or Esc closes." % Quests.MAX_TRACKED
	layout()


# ---------------------------------------------------- tracked quests
func render_tracker() -> void:
	var ql = game.quests
	UI.clear(tracker_box)
	var ids: Array = ql.active.filter(func(id): return ql.tracked.has(id))
	tracker.visible = not ids.is_empty()
	var first := true
	for id in ids:
		if not first:
			UI.rule(tracker_box)
		first = false
		var q: Dictionary = DB.quests[id]
		var s: String = ql.status(id)
		var text := "[font_size=13][color=#c9a45c]%s[/color][/font_size]%s\n" % [UI.esc(q.name), " [font_size=10][color=#ffd23c]COMPLETE[/color][/font_size]" if s == "ready" else ""]
		if s == "ready":
			text += "[font_size=12][color=#ffd23c]    Return to %s[/color][/font_size]" % UI.esc(DB.npcs[q.turnIn].name)
		else:
			text += _objectives(ql.objectives(id))
		var r := UI.rich(tracker_box, 13, 240)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UI.set_rich(r, text)
		# tracked quests open in the log when clicked, as in WoW
		var qid: String = id
		r.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				selected = qid
				toggle_log(true))
	tracker.size = tracker.get_combined_minimum_size()


# ------------------------------------------------- ! and ? over heads
func update_marks() -> void:
	var cam: Camera3D = game.camera
	var vp := get_viewport_rect().size
	var bob := sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.6) * 0.5 + 0.5
	for n in game.npcs.all:
		var status: String = game.quests.marker_for(n.id) if n.present else ""
		var l: Label = marks.get(n.id)
		if l == null:
			l = UI.label(marks_layer, "", 34, UI.QUEST_GOLD, 6)
			l.add_theme_font_override("font", UI.bold)
			marks[n.id] = l
		if status == "":
			l.visible = false
			continue
		# 'active' and 'ready' are both ?, so watch the status, not the text
		if l.get_meta("status", "") != status:
			l.set_meta("status", status)
			l.text = MARK[status]
			l.add_theme_color_override("font_color", Color("b4b4b4") if status == "active" else UI.QUEST_GOLD)
			l.size = l.get_combined_minimum_size()
		var at: Vector3 = n.position + Vector3(0, 2.55, 0)
		var s := cam.unproject_position(at)
		var visible := not cam.is_position_behind(at) and s.x > -vp.x * 0.025 and s.x < vp.x * 1.025 and s.y > -vp.y * 0.025 and s.y < vp.y * 1.025
		l.visible = visible
		l.position = s - Vector2(l.size.x / 2, l.size.y) - Vector2(0, bob * 5)


# --------------------------------------------------------- layout
func layout() -> void:
	var vp := get_viewport_rect().size
	for w in [dialogue, trainer]:
		if w.panel.visible:
			UI.fit_steady(w.panel)
			w.panel.position = Vector2(12, 136)
	if quest_log.panel.visible:
		var p: Control = quest_log.panel
		p.custom_minimum_size.x = minf(600, vp.x - 24)
		UI.fit_steady(p)
		p.position = Vector2(roundf((vp.x - p.size.x) / 2), 80)
	tracker.position = Vector2(vp.x - 12 - tracker.size.x, 204)


# --------------------------------------------------------- gamepad
## Returns true while the quest windows have the pad.
func gamepad(pad, dt: float) -> bool:
	var B := Pad.BUTTONS
	var dlg = game.dialogue
	if dlg.is_open:
		var page = dlg.page
		var n: int = page.options.size()
		var dir: String = pad.nav_direction(dt)
		if dir == "up":
			choice = (choice + n - 1) % n
		if dir == "down":
			choice = (choice + 1) % n
		if dir != "":
			render_dialogue()
		if pad.pressed(B.A):
			dlg.choose(page.options[choice].id)
		elif pad.pressed(B.B):
			dlg.back()
		return true
	if log_open:
		var list: Array = game.quests.active
		var dir: String = pad.nav_direction(dt)
		if (dir == "up" or dir == "down") and not list.is_empty():
			var i := list.find(selected)
			select(list[(i + (list.size() - 1 if dir == "up" else 1)) % list.size()])
		if pad.pressed(B.X) and selected != null:
			game.quests.set_tracked(selected, not game.quests.tracked.has(selected))
		if pad.pressed(B.Y):
			abandon()
		if pad.pressed(B.B):
			toggle_log(false)
		return true
	return false
