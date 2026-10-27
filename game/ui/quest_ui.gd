class_name QuestUI
extends Control
## The quest side of the HUD (src/ui/questUI.js): the dialogue window, the
## trainer window, the quest log (L), the tracked objectives under the
## minimap, and the ! and ? over townsfolk. Like the bags, none of these
## pause the game.
##
## Gamepad: in the dialogue window up and down pick a choice, A takes it and
## B goes back. In the quest log up and down pick a quest, A follows it
## (the minimap shows the way), X tracks or untracks it, Y abandons it
## (press twice), and B closes.

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
var tracker_collapsed := false
const TRACKER_W := 236.0
var _way: RichTextLabel ## the way to the followed quest, under it in the tracker
var _way_text := ""
var _way_t := 0.0
var log_list_scroll: ScrollContainer
var log_list: VBoxContainer
var log_detail_scroll: ScrollContainer
var log_detail: VBoxContainer
var log_actions: HBoxContainer
var log_hint: Label
const LOG_W := 860.0
const LOG_LIST_W := 280.0
const LOG_H := 440.0
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
	# a smoky band behind the list, solid at the screen edge (shown on
	# hover by the HUD); it takes the clicks so pointing at the list never walks you
	tracker.add_theme_stylebox_override("panel", UI.shade("right", 0.6, Vector4(14, 6, 8, 8)))
	tracker.mouse_filter = Control.MOUSE_FILTER_STOP
	tracker.self_modulate.a = 0 # the band shows while the pointer is over it
	tracker.custom_minimum_size = Vector2(TRACKER_W, 0)
	tracker_box = UI.vbox(tracker, 6)
	tracker.visible = false
	dialogue = UI.window(self, "", 340, func(): game.dialogue.close())
	_with_subtitle(dialogue)
	trainer = UI.window(self, "", 360, func(): game.dialogue.close())
	_with_subtitle(trainer)
	trainer.sub.text = "Trainer"
	quest_log = UI.window(self, "Quest log", LOG_W, func(): toggle_log(false))
	_with_subtitle(quest_log)
	_build_log()
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
		var order := _ordered()
		selected = order[0] if not order.is_empty() else null
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
	var order := _ordered()
	selected = order[0] if not order.is_empty() else null
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


## the tracker's steps: a tick when done, an empty box while open
func _steps(objs: Array) -> String:
	var out := []
	for o in objs:
		out.append("[color=#8cbf78]  ✓ %s[/color]" % UI.esc(Quests.line(o)) if o.done else "[color=#6e6250]  ▢[/color] [color=%s]%s[/color]" % [UI.hex(UI.TEXT), UI.esc(Quests.line(o))])
	return "[font_size=12]%s[/font_size]" % "\n".join(out)


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
## The quests in hand in the order the log lists them: grouped by zone
## (the easiest zone first, dungeons last), easiest first within a group.
## [{ name, dungeon, ids }]
func groups() -> Array:
	var by := {}
	for id in game.quests.active:
		var z := Quests.zone(id)
		var key: String = ("d:" if z.dungeon else "z:") + str(z.name)
		if not by.has(key):
			by[key] = {"name": z.name, "dungeon": z.dungeon, "ids": []}
		by[key].ids.append(id)
	var out: Array = by.values()
	for g in out:
		g.ids.sort_custom(func(a, b): return Quests.levels(a).x < Quests.levels(b).x)
		g.low = Quests.levels(g.ids[0]).x
	out.sort_custom(func(a, b): return a.low < b.low if a.dungeon == b.dungeon else b.dungeon)
	return out


func _ordered() -> Array:
	var out := []
	for g in groups():
		out.append_array(g.ids)
	return out


## "Lv 3" or "Lv 3–5"
static func level_text(v: Vector2i) -> String:
	return "Lv %d" % v.x if v.x == v.y else "Lv %d–%d" % [v.x, v.y]


func _level_colour(v: Vector2i) -> Color:
	return Quests.level_colour(v.y, game.progression.level)


func _build_log() -> void:
	var cols := UI.hbox(quest_log.body, 12)
	log_list_scroll = ScrollContainer.new()
	log_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_list_scroll.custom_minimum_size = Vector2(LOG_LIST_W + 14, LOG_H)
	cols.add_child(log_list_scroll)
	log_list = UI.vbox(log_list_scroll, 1)
	log_list.custom_minimum_size = Vector2(LOG_LIST_W, 0)
	var sep := ColorRect.new()
	sep.color = UI.BORDER_DIM
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(sep)
	var right := UI.vbox(cols, 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_detail_scroll = ScrollContainer.new()
	log_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_detail_scroll.custom_minimum_size = Vector2(0, LOG_H - 40)
	right.add_child(log_detail_scroll)
	log_detail = UI.vbox(log_detail_scroll, 6)
	log_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_actions = UI.hbox(right, 8)
	log_hint = UI.hint(quest_log.body)


func render_log() -> void:
	var w := quest_log
	w.panel.visible = log_open
	if not log_open:
		return
	var ql = game.quests
	var act: Array = ql.active
	w.sub.text = "%d in hand · %d done" % [act.size(), ql.done.size()]
	var vp := get_viewport_rect().size
	var win_w := minf(LOG_W, vp.x - 24)
	var h := clampf(vp.y - 230, 200, LOG_H)
	log_list_scroll.custom_minimum_size.y = h
	log_detail_scroll.custom_minimum_size.y = h - 40
	var detail_w := win_w - 24 - LOG_LIST_W - 14 - 25 - 16
	# the list, by zone
	UI.clear(log_list)
	var chosen_button: Control = null
	if act.is_empty():
		UI.set_rich(UI.rich(log_list, 12, LOG_LIST_W), "[color=#9a8f78]No quests in hand. Look for a [color=#ffd23c]![/color] over someone's head.[/color]")
	for g in groups():
		var head := UI.label(log_list, ("DUNGEON · " if g.dungeon else "") + g.name.to_upper(), 11, Color("d98a5a") if g.dungeon else UI.GOLD)
		head.add_theme_font_override("font", UI.bold)
		if log_list.get_child_count() > 1:
			head.custom_minimum_size.y = 26
			head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		for id in g.ids:
			var b := _log_entry(id)
			log_list.add_child(b)
			if id == selected:
				chosen_button = b
	# the details
	UI.clear(log_detail)
	UI.clear(log_actions)
	var sel_id = selected
	if sel_id == null or not act.has(sel_id):
		var text := ""
		if not ql.done.is_empty():
			text = _sub("Completed")
			for d in ql.done:
				text += "[font_size=12][color=#9a8f78]%s[/color][/font_size]\n" % UI.esc(DB.quests[d].name)
		UI.set_rich(UI.rich(log_detail, 13, detail_w), text)
	else:
		UI.set_rich(UI.rich(log_detail, 13, detail_w), _details(sel_id))
		_log_buttons(sel_id)
	log_hint.text = "Up/down: choose   A: show the way   X: track (up to %d)   Y: abandon   B: close" % Quests.MAX_TRACKED if hud.pad_mode else "Tracked quests (up to %d) show under the map; click one there to be shown the way. L or Esc closes." % Quests.MAX_TRACKED
	layout()
	if chosen_button != null:
		log_list_scroll.ensure_control_visible.call_deferred(chosen_button)


func _log_entry(id: String) -> Button:
	var ql = game.quests
	var s: String = ql.status(id)
	var lv := Quests.levels(id)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s[%s]  %s%s" % ["◆ " if ql.focus == id else ("• " if ql.tracked.has(id) else "   "), level_text(lv).substr(3), DB.quests[id].name, "  (Complete)" if s == "ready" else ""]
	b.tooltip_text = "%s · %s" % [level_text(lv), "ready to hand in" if s == "ready" else "in progress"]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(LOG_LIST_W, 0)
	b.add_theme_font_size_override("font_size", 13)
	var sel: bool = id == selected
	b.add_theme_stylebox_override("normal", UI.box(Color(201 / 255.0, 164 / 255.0, 92 / 255.0, 0.16) if sel else Color(0, 0, 0, 0), UI.BORDER_DIM if sel else Color(0, 0, 0, 0), 0, 1, Vector4(6, 3, 6, 3)))
	b.add_theme_stylebox_override("hover", UI.box(Color(201 / 255.0, 164 / 255.0, 92 / 255.0, 0.08), UI.BORDER_DIM if sel else Color(0, 0, 0, 0), 0, 1, Vector4(6, 3, 6, 3)))
	b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("hover"))
	# coloured by how hard it is for you, as WoW does
	var c := _level_colour(lv)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, c)
	b.pressed.connect(func(): select(id))
	return b


## Title, level and zone, the story, what to do, where to hand it in, and
## the rewards.
func _details(id: String) -> String:
	var ql = game.quests
	var q: Dictionary = DB.quests[id]
	var s: String = ql.status(id)
	var lv := Quests.levels(id)
	var z := Quests.zone(id)
	var danger: int = lv.y - int(game.progression.level)
	var note := "  [color=#ff4a3a](dangerous at your level)[/color]" if danger >= 5 else ("  [color=#ff9a40](hard at your level)[/color]" if danger >= 3 else "")
	var text := "[font_size=18][color=#e6b85e]%s[/color][/font_size]\n" % UI.esc(q.name)
	text += "[font_size=12][color=%s]%s[/color]  [color=#9a8f78]·  %s%s[/color]%s[/font_size]\n\n" % [UI.hex(_level_colour(lv)), level_text(lv).replace("Lv", "Level"), "Dungeon: " if z.dungeon else "", UI.esc(z.name), note]
	text += _sub("Description") + "[color=#d8ccb0]%s[/color]\n\n" % UI.esc(q.get("offer", q.get("summary", "")))
	text += _sub("Summary")
	if q.get("summary") and q.get("offer"):
		text += "[font_size=12][color=#b0a386]%s[/color][/font_size]\n" % UI.esc(q.summary)
	text += _objectives(ql.objectives(id))
	var where := Quests.hand_in(id)
	text += "[font_size=12][color=#ffd23c]Complete: return to %s.[/color][/font_size]\n\n" % UI.esc(where) if s == "ready" else "[font_size=12][color=#9a8f78]Hand in to %s.[/color][/font_size]\n\n" % UI.esc(where)
	text += _rewards(q.get("reward", {}))
	return text


func _log_buttons(id: String) -> void:
	var ql = game.quests
	var q: Dictionary = DB.quests[id]
	UI.button(log_actions, "Untrack" if ql.tracked.has(id) else "Track", func(): game.quests.set_tracked(id, not game.quests.tracked.has(id)), 13)
	UI.button(log_actions, "Stop following" if ql.focus == id else "Show the way", func(): game.quests.set_focus("" if game.quests.focus == id else id), 13)
	if not q.get("autoAccept"):
		var ab := UI.button(log_actions, "Really abandon?" if confirm_abandon == id else "Abandon", abandon, 13)
		if confirm_abandon == id:
			ab.add_theme_color_override("font_color", Color("ff9070"))
			ab.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), Color("a05040"), 0, 1, Vector4(8, 2, 8, 2)))


# ---------------------------------------------------- tracked quests
## The objectives under the minimap. The header folds it away; clicking a
## quest follows it (the minimap points the way to its next step) and a
## right click opens it in the quest log.
func render_tracker() -> void:
	var ql = game.quests
	UI.clear(tracker_box)
	_way = null
	var ids: Array = ql.active.filter(func(id): return ql.tracked.has(id))
	tracker.visible = not ids.is_empty()
	var head := UI.hbox(tracker_box, 6)
	var title := UI.label(head, "%s  OBJECTIVES" % ("▸" if tracker_collapsed else "▾"), 12, UI.GOLD, 4)
	title.add_theme_font_override("font", UI.bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = "Show the objectives" if tracker_collapsed else "Hide the objectives"
	UI.label(head, str(ids.size()), 11, UI.TEXT_DIM, 4)
	var rule := ColorRect.new()
	rule.color = Color(UI.GOLD, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker_box.add_child(rule)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	title.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_fold_tracker())
	if tracker_collapsed:
		tracker.size = tracker.get_combined_minimum_size()
		return
	for id in ids:
		var q: Dictionary = DB.quests[id]
		var s: String = ql.status(id)
		var focused: bool = ql.focus == id
		var text := "[font_size=13][color=%s]%s%s[/color][/font_size]%s\n" % ["#fff0a0" if focused else "#e8d8b0", "◆ " if focused else "", UI.esc(q.name), " [font_size=10][color=#8cbf78](Complete)[/color][/font_size]" if s == "ready" else ""]
		if s == "ready":
			text += "[font_size=12][color=#ffd23c]  ➜ Return to %s[/color][/font_size]" % UI.esc(Quests.hand_in(id))
		else:
			text += _steps(ql.objectives(id))
		var r := UI.rich(tracker_box, 13, TRACKER_W - 22)
		_outline(r)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		r.tooltip_text = "Click: show the way · Right click: open in the quest log"
		UI.set_rich(r, text)
		r.gui_input.connect(func(e):
			if not (e is InputEventMouseButton and e.pressed):
				return
			if e.button_index == MOUSE_BUTTON_LEFT:
				game.quests.set_focus("" if game.quests.focus == id else id)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				selected = id
				toggle_log(true))
		if focused:
			_way = UI.rich(tracker_box, 12, TRACKER_W - 22)
			_outline(_way)
			_way.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_way_text = ""
			_update_way()
	tracker.size = tracker.get_combined_minimum_size()


## dark edges round the tracker's text, so it reads over any ground
func _outline(r: RichTextLabel) -> void:
	r.add_theme_constant_override("outline_size", 4)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))


func _fold_tracker() -> void:
	tracker_collapsed = not tracker_collapsed
	render_tracker()


const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


## "→ Hallow Cut · 140 m north-east" under the followed quest
func _update_way() -> void:
	if _way == null or not is_instance_valid(_way) or game.player == null:
		return
	var at: Dictionary = game.quests.goal(game.quests.focus) if game.quests.focus != "" else {}
	var text := ""
	if at.is_empty():
		text = "[color=#9a8f78]    No place to point to.[/color]"
	else:
		var p: Vector3 = game.player.position
		var dx: float = at.x - p.x
		var dz: float = at.z - p.z
		var d := maxf(0, U.hyp(dx, dz) - at.r)
		if d < 4:
			text = "[color=#fff0a0]    ➜ %s · here[/color]" % UI.esc(at.label)
		else:
			# north is up the map, which is -z
			var i := posmod(roundi(atan2(dx, -dz) / (TAU / 8)), 8)
			text = "[color=#fff0a0]    ➜ %s · %d m %s[/color]" % [UI.esc(at.label), roundi(d), COMPASS[i]]
	if text != _way_text:
		_way_text = text
		UI.set_rich(_way, "[font_size=12]%s[/font_size]" % text)
		tracker.size = tracker.get_combined_minimum_size()


# ------------------------------------------------- ! and ? over heads
func update_marks() -> void:
	_way_t += get_process_delta_time()
	if _way_t >= 0.25:
		_way_t = 0.0
		_update_way()
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
			w.panel.position = Vector2(12, 12)
	if quest_log.panel.visible:
		var p: Control = quest_log.panel
		p.custom_minimum_size.x = minf(LOG_W, vp.x - 24)
		UI.fit_steady(p)
		p.position = Vector2(roundf((vp.x - p.size.x) / 2), 80)
	tracker.position = Vector2(vp.x - tracker.size.x, roundf(hud.minimap.position.y + hud.minimap.coords.position.y + hud.minimap.coords.size.y + 8))


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
		var list: Array = _ordered()
		var dir: String = pad.nav_direction(dt)
		if (dir == "up" or dir == "down") and not list.is_empty():
			var i := list.find(selected)
			select(list[(i + (list.size() - 1 if dir == "up" else 1)) % list.size()])
		if pad.pressed(B.A) and selected != null:
			game.quests.set_focus("" if game.quests.focus == selected else selected)
		if pad.pressed(B.X) and selected != null:
			game.quests.set_tracked(selected, not game.quests.tracked.has(selected))
		if pad.pressed(B.Y):
			abandon()
		if pad.pressed(B.B):
			toggle_log(false)
		return true
	return false
