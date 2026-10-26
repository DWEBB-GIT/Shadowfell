class_name TitleScreen
extends Control
## The title screen, character select and character creation (alpha;
## src/ui/titleUI.js). One screen with three views; mouse, keyboard and
## gamepad all drive it. Every view keeps a list of controls you can move
## between: the D-pad, the left stick or the arrow keys move, and A / Enter
## / Space presses the one in focus. B / Esc goes back. On character select
## and creation the world shows behind, with the Warden standing in it.

const CLASSES_KEY := "classes"

var game
var view = null ## 'main' | 'select' | 'create' | null when closed
var selected = null ## character id on the select screen
var class_id := ""
var confirm_delete := false
var focus_el: Control
var stick_wait := 0.0
var note := ""
var _pad_shown = null

var bg: Control
var views := {}
var main: Dictionary = {}
var sel: Dictionary = {}
var create: Dictionary = {}
var hints: Array = [] ## [Label, keyboard text, pad text]


func _init(g) -> void:
	game = g
	name = "TitleScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for c in DB.text.title.classes:
		if c.get("archetype") and class_id == "":
			class_id = c.id
	bg = Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_bg)
	add_child(bg)
	_build_main()
	_build_select()
	_build_create()
	visible = false


static func ago(t: float) -> String:
	var s := maxf(0, (Time.get_unix_time_from_system() * 1000 - t) / 1000.0)
	if s < 90:
		return "just now"
	if s < 5400:
		return "%d minutes ago" % roundi(s / 60)
	if s < 129600:
		return "%d hours ago" % roundi(s / 3600)
	return "%d days ago" % roundi(s / 86400)


# ------------------------------------------------------------ building
## the backdrop: dark all over on the main title; on select and create, dark
## on the left where the list is and clear over the Warden
func _draw_bg() -> void:
	var r := bg.get_rect()
	var g := Canvas2D.new(bg)
	if view == "main":
		var grad := g.create_radial_gradient(r.size.x / 2, r.size.y / 2, 0, r.size.x / 2, r.size.y / 2, r.size.length() * 0.5)
		Canvas2D.add_color_stop(grad, 0, Color(8 / 255.0, 6 / 255.0, 4 / 255.0, 0.72))
		Canvas2D.add_color_stop(grad, 0.75, Color(3 / 255.0, 2 / 255.0, 1 / 255.0, 0.94))
		g.fill_style = grad
	else:
		var grad := g.create_linear_gradient(0, 0, r.size.x, 0)
		Canvas2D.add_color_stop(grad, 0, Color(4 / 255.0, 3 / 255.0, 2 / 255.0, 0.88))
		Canvas2D.add_color_stop(grad, 0.34, Color(4 / 255.0, 3 / 255.0, 2 / 255.0, 0.35))
		Canvas2D.add_color_stop(grad, 0.55, Color(0, 0, 0, 0))
		Canvas2D.add_color_stop(grad, 1, Color(4 / 255.0, 3 / 255.0, 2 / 255.0, 0.2))
		g.fill_style = grad
	g.fill_rect(0, 0, r.size.x, r.size.y)


func _view(id: String) -> Control:
	var v := Control.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	views[id] = v
	return v


## a button the keyboard and pad can move to
func _nav(parent: Node, text: String, cb: Callable, size := 15) -> Button:
	var b := UI.button(parent, text, cb, size)
	b.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), UI.BORDER, 0, 1, Vector4(18, 7, 18, 7)))
	b.add_theme_stylebox_override("disabled", UI.box(Color("1d1812"), UI.BORDER_DIM, 0, 1, Vector4(18, 7, 18, 7)))
	b.add_theme_stylebox_override("hover", UI.box(Color("2a2219"), UI.GOLD, 0, 1, Vector4(18, 7, 18, 7)))
	b.set_meta("nav", true)
	b.mouse_entered.connect(func():
		if not b.disabled:
			focus(b, true))
	return b


func _hint(parent: Node, kbm: String, pad: String) -> Label:
	var l := UI.label(parent, kbm, 12, UI.TEXT_DIM, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.append([l, kbm, pad])
	return l


func _build_main() -> void:
	var v := _view("main")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var col := UI.vbox(centre, 6)
	col.custom_minimum_size = Vector2(640, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var crest := UI.label(col, "✠", 30, Color(UI.GOLD, 0.7))
	crest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h1 := UI.label(col, "S H A D O W F A L L", 46, UI.GOLD, 4)
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.h1 = h1
	var t: Dictionary = DB.text.title
	var sub := UI.label(col, ("%s  ·  %s" % [t.tagline, t.build]).to_upper(), 12, UI.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var stamp := "Godot build"
	if FileAccess.file_exists("res://data/build.json"):
		var b = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
		if b is Dictionary:
			stamp = "Godot build %s · %s" % [b.get("commit", "?"), b.get("time", "")]
	var ver := UI.label(col, stamp, 10, Color(UI.TEXT_DIM, 0.75))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.version = ver
	var intro := UI.label(col, DB.text.intro, 15, Color("c6bba0"))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.note = UI.label(col, "", 14, UI.WARN)
	main.note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.gap(col, 16)
	var menu := UI.vbox(col, 8)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	for b in [["continue", "Continue"], ["chars", "Characters"], ["new", "New character"], ["controls", "Controls"]]:
		var btn := _nav(menu, b[1], Callable(), 16)
		btn.custom_minimum_size = Vector2(280, 0)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		main[b[0]] = btn
	main["continue"].pressed.connect(func():
		if game.roster.last != null:
			game.enter_world(game.roster.last))
	main.chars.pressed.connect(func(): show_view("select"))
	main.new.pressed.connect(func(): show_view("create"))
	main.controls.pressed.connect(func(): main.table.visible = not main.table.visible)
	main.table = _controls_table(col)
	main.table.visible = false
	var foot := _hint(v, "↑↓ Enter", "D-pad · A")
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.position = Vector2(-300, -30)
	foot.size = Vector2(600, 18)
	main.foot = foot


func _controls_table(parent: Node) -> Control:
	var row := UI.hbox(parent, 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# the mouse rows follow the control scheme (Settings: Classic controls)
	var mouse_rows := [["Left click", "Attack the enemy at the cursor; talk; loot"], ["Hold left click", "Aim at the cursor as you walk"], ["Right click", "Spell slot 1, at the cursor"], ["1 · 2 · 3 · 4 · R · F", "The six spell slots (F: Brace)"]] if game.mouse_aim else [["Left click", "Select an enemy or person; loot"], ["Right click", "Auto attack an enemy; talk; loot"], ["1 · 2 · 3 · 4 · Q · E", "The six spell slots (E: Brace)"]]
	var tables := [
		["Keyboard and mouse", [["WASD / arrow keys", "Move"]] + mouse_rows + [["Shift-1 to Shift-4", "The four utility slots (draught, torch, fishing...)"], ["Space", "Interact / loot everything nearby"], ["Tab", "Next target"], ["Mouse wheel", "Zoom the camera"], ["B · C · P · L", "Bags · Character · Spellbook · Quest log"], ["K · O · Esc", "Save · Settings (keys, sound, click to move) · Close / clear target"]]],
		["Gamepad", [["Left stick", "Move"], ["Right stick", "Aim"], ["RT", "Auto attack the target (or who is ahead)"], ["R3 (stick click)", "Next target"], ["X · Y · RB", "Lunge · Shield Break · Healing draught"], ["LB · LT", "Spell-bar slots 4 and 5"], ["B", "Brace"], ["A", "Interact / loot / confirm"], ["Start · View", "Bags · Character"], ["D-pad up · down · right", "Spellbook · Save · Quest log"]]],
	]
	for t in tables:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 2)
		row.add_child(grid)
		UI.label(grid, t[0], 12, UI.TEXT)
		UI.label(grid, "", 12)
		for r in t[1]:
			var a := UI.label(grid, r[0], 12, UI.GOLD)
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var b := UI.label(grid, r[1], 12, UI.TEXT_DIM)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(170, 0)
	return row


func _side(v: Control, title: String) -> VBoxContainer:
	var p := UI.panel(v, 0)
	p.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 0, 1, Vector4(16, 14, 16, 14)))
	p.custom_minimum_size = Vector2(300, 0)
	p.set_meta("side", true)
	var col := UI.vbox(p, 6)
	UI.label(col, title, 20, UI.GOLD)
	return col


func _centre(v: Control) -> VBoxContainer:
	var c := UI.vbox(v, 8)
	c.alignment = BoxContainer.ALIGNMENT_END
	c.set_meta("centre", true)
	return c


func _build_select() -> void:
	var v := _view("select")
	var side := _side(v, "Characters")
	sel.count = UI.label(side, "", 12, UI.TEXT_DIM)
	sel.list = UI.vbox(side, 6)
	var acts := UI.hbox(side, 8)
	sel.create = _nav(acts, "Create new", func(): show_view("create"), 13)
	sel.delete = _nav(acts, "Delete", ask_delete, 13)
	sel.back = _nav(acts, "Back", back, 13)
	for b in [sel.create, sel.delete, sel.back]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel.confirm = UI.vbox(side, 8)
	sel.confirm_text = UI.label(sel.confirm, "", 13, Color("e0b8a0"))
	sel.confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ca := UI.hbox(sel.confirm, 8)
	sel.yes = _nav(ca, "Delete for ever", do_delete, 13)
	sel.yes.add_theme_color_override("font_color", Color("e0a090"))
	sel.yes.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), Color("8a3a2a"), 0, 1, Vector4(18, 7, 18, 7)))
	sel.no = _nav(ca, "Keep", cancel_delete, 13)
	sel.confirm.visible = false
	var c := _centre(v)
	sel.name = UI.label(c, "", 34, UI.GOLD, 6)
	sel.name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel.line = UI.label(c, "", 14, Color("d6c9a8"), 4)
	sel.line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel.enter = _nav(c, "Enter world", enter_selected, 18)
	sel.enter.custom_minimum_size = Vector2(220, 0)
	sel.enter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint(c, "↑↓ choose · Enter play · Del delete · Esc back", "D-pad choose · A play · Y delete · B back")


func _build_create() -> void:
	var v := _view("create")
	var side := _side(v, "Create a character")
	UI.label(side, "CLASS", 12, UI.TEXT_DIM)
	create.list = UI.vbox(side, 6)
	var detail := UI.panel(v, 0)
	detail.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 0, 1, Vector4(16, 12, 16, 12)))
	detail.custom_minimum_size = Vector2(320, 0)
	detail.set_meta("detail", true)
	create.detail = UI.rich(detail, 14, 288)
	var c := _centre(v)
	var row := UI.hbox(c, 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_edit := LineEdit.new()
	name_edit.max_length = 25
	name_edit.placeholder_text = "Name"
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.set_meta("nav", true)
	name_edit.text_submitted.connect(func(_t): do_create())
	name_edit.text_changed.connect(func(_t): create.error.text = "")
	name_edit.focus_entered.connect(func(): focus_el = name_edit)
	row.add_child(name_edit)
	create.name = name_edit
	create.random = _nav(row, "⚄", random_name, 20)
	game.hud.items.tip_on(create.random, "Random name")
	create.error = UI.label(c, "", 13, UI.WARN, 3)
	create.error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create.error.custom_minimum_size = Vector2(0, 18)
	var acts := UI.hbox(c, 8)
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	create.back = _nav(acts, "Back", back, 13)
	create.confirm = _nav(acts, "Create and enter", do_create, 18)
	create.confirm.custom_minimum_size = Vector2(220, 0)
	_hint(c, "Type a name · Enter create · Esc back", "D-pad choose · A select · Y random name · B back")


# ------------------------------------------------------------ views
var is_open: bool:
	get:
		return view != null


func open(n := "", which := "main") -> void:
	note = n
	game.hud.modal = "title"
	visible = true
	show_view("select" if which == "select" and not game.roster.list.is_empty() else "main")


func close() -> void:
	visible = false
	view = null
	game.hud.showcase = false


func show_view(v: String) -> void:
	view = v
	confirm_delete = false
	for id in views:
		views[id].visible = id == v
	game.hud.showcase = v != "main"
	bg.queue_redraw()
	if v == "main":
		_render_main()
	if v == "select":
		_render_select()
	if v == "create":
		_render_create()
	_labels()
	layout()


func back() -> void:
	if view == "select" and confirm_delete:
		cancel_delete()
		return
	if view == "create" and not game.roster.list.is_empty():
		show_view("select")
		return
	if view != "main":
		show_view("main")


# ------------------------------------------------------------- main
func _render_main() -> void:
	var roster = game.roster
	var last = roster.by_id(roster.last) if roster.last != null else null
	var i = info(last) if last != null else null
	var can_continue: bool = i != null and i.ok
	main["continue"].visible = can_continue
	main["continue"].text = "Continue\n%s · level %s %s" % [last.name, i.level, class_name_of(last)] if can_continue else "Continue"
	main.chars.visible = not roster.list.is_empty()
	var n := note
	if n == "":
		for c in roster.list:
			if not info(c).ok:
				n = "%s's save could not be read. It has been kept aside and will not be overwritten." % c.name
				break
	main.note.text = n
	main.note.visible = n != ""
	main.foot.text = "Shadowfall %s · saves are kept on this computer · %s" % [DB.text.title.build, "D-pad · A" if game.hud.pad_mode else "↑↓ Enter"]
	focus(main["continue"] if can_continue else main.new)


# ------------------------------------------------------------ select
func info(c: Dictionary) -> Dictionary:
	var r: Dictionary = game.save.read(c.key)
	if r.status == "ok":
		var d: Dictionary = r.data
		return {"ok": true, "level": U.n(d.progression.level), "where": (DB.region_at(d.player.position[0], d.player.position[1]) if d.player.position is Array else DB.region_at(d.player.position.x, d.player.position.z)).get("name", "")}
	if r.status == "none":
		return {"ok": true, "level": "1", "where": "Not yet set out"}
	return {"ok": false, "level": "?", "where": "Save unreadable"}


func class_name_of(c: Dictionary) -> String:
	for k in DB.text.title.classes:
		if k.id == c.get("classId"):
			return k.name
	return DB.text.title.classes[0].name


## a character or class card: name, then a gold line, then a dim line
func _card(parent: Node, lines: Array, cb: Callable, selected_: bool, faded := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := UI.box(Color(46 / 255.0, 36 / 255.0, 22 / 255.0, 0.9) if selected_ else Color(20 / 255.0, 16 / 255.0, 12 / 255.0, 0.85), UI.GOLD if selected_ else UI.BORDER_DIM, 0, 1, Vector4(12, 8, 12, 8))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", normal)
	b.custom_minimum_size = Vector2(268, 0)
	var r := UI.rich(b, 12, 244)
	r.position = Vector2(12, 8)
	var text := "[font_size=16][color=#efe2bf]%s[/color][/font_size]\n[color=#c9a45c]%s[/color]" % [UI.esc(lines[0]), UI.esc(lines[1])]
	if lines.size() > 2:
		text += "\n[color=#%s]%s[/color]" % ["d8a070" if lines.size() > 3 and lines[3] else "9a8f78", UI.esc(lines[2])]
	UI.set_rich(r, text)
	b.custom_minimum_size.y = 16 + 22 + 16 * (lines.size() - 1)
	b.pressed.connect(cb)
	b.set_meta("nav", true)
	b.mouse_entered.connect(func(): focus(b, true))
	if faded:
		b.modulate.a = 0.55
	parent.add_child(b)
	return b


func _render_select() -> void:
	var roster = game.roster
	if selected == null or roster.by_id(selected) == null:
		selected = roster.last if roster.last != null else (roster.list[0].id if not roster.list.is_empty() else null)
	# most recently played first
	var list: Array = roster.list.duplicate()
	list.sort_custom(func(a, b): return a.lastPlayed > b.lastPlayed)
	sel.count.text = "%d of %d" % [roster.list.size(), roster.max]
	UI.clear(sel.list)
	sel.cards = {}
	for c in list:
		var i := info(c)
		var id: String = c.id
		var card := _card(sel.list, [c.name, "Level %s %s" % [i.level, class_name_of(c)], i.where, not i.ok], func():
			# a second click on the chosen character plays them (a double click)
			if selected == id:
				enter_selected()
			else:
				select(id), c.id == selected)
		card.set_meta("char", id)
		sel.cards[id] = card
	sel.create.disabled = roster.full
	sel.confirm.visible = false
	select(selected)


func select(id) -> void:
	selected = id
	var c = game.roster.by_id(id) if id != null else null
	for cid in sel.get("cards", {}):
		var card: Button = sel.cards[cid]
		var on: bool = cid == id
		var box := UI.box(Color(46 / 255.0, 36 / 255.0, 22 / 255.0, 0.9) if on else Color(20 / 255.0, 16 / 255.0, 12 / 255.0, 0.85), UI.GOLD if on else UI.BORDER_DIM, 0, 1, Vector4(12, 8, 12, 8))
		card.add_theme_stylebox_override("normal", box)
		card.add_theme_stylebox_override("hover", box)
	var i = info(c) if c != null else null
	sel.name.text = c.name if c != null else ""
	sel.line.text = "Level %s %s · %s · played %s" % [i.level, class_name_of(c), i.where, ago(c.lastPlayed)] if c != null else "No characters yet"
	sel.enter.disabled = c == null or not i.ok
	sel.delete.disabled = c == null
	focus(sel.cards.get(id) if id != null and sel.has("cards") and sel.cards.has(id) else sel.create)


func enter_selected() -> void:
	var c = game.roster.by_id(selected) if selected != null else null
	if c != null and info(c).ok:
		game.enter_world(c.id)


func ask_delete() -> void:
	var c = game.roster.by_id(selected) if selected != null else null
	if c == null:
		return
	confirm_delete = true
	sel.confirm_text.text = "Delete %s? Their save is removed from this computer and cannot be brought back." % c.name
	sel.confirm.visible = true
	focus(sel.no)


func cancel_delete() -> void:
	confirm_delete = false
	sel.confirm.visible = false
	focus(sel.delete)


func do_delete() -> void:
	game.roster.remove(selected)
	selected = null
	show_view("select" if not game.roster.list.is_empty() else "main")


# ------------------------------------------------------------ create
func _render_create() -> void:
	UI.clear(create.list)
	create.cards = {}
	for c in DB.text.title.classes:
		var id: String = c.id
		var card := _card(create.list, [c.name, c.role if c.get("archetype") else "Coming later"], func(): pick_class(id), id == class_id, not c.get("archetype"))
		card.set_meta("class", id)
		create.cards[id] = card
	pick_class(class_id, false)
	var roster = game.roster
	create.error.text = "You can keep %d characters. Delete one to make room." % roster.max if roster.full else ""
	create.confirm.disabled = roster.full
	if create.name.text == "" or roster.name_problem(create.name.text) != "":
		create.name.text = roster.random_name()
	focus(create.confirm)


func pick_class(id: String, move_focus := true) -> void:
	var c: Dictionary = {}
	for k in DB.text.title.classes:
		if k.id == id:
			c = k
	for cid in create.cards:
		var on: bool = cid == id
		var box := UI.box(Color(46 / 255.0, 36 / 255.0, 22 / 255.0, 0.9) if on else Color(20 / 255.0, 16 / 255.0, 12 / 255.0, 0.85), UI.GOLD if on else UI.BORDER_DIM, 0, 1, Vector4(12, 8, 12, 8))
		create.cards[cid].add_theme_stylebox_override("normal", box)
		create.cards[cid].add_theme_stylebox_override("hover", box)
	var traits := ""
	for t in c.get("traits", []):
		traits += "[color=#cbbd98][font_size=13]•  %s[/font_size][/color]\n" % UI.esc(t)
	UI.set_rich(create.detail, "[font_size=20][color=#c9a45c]%s[/color][/font_size]   [font_size=12][color=#9a8f78]%s[/color][/font_size]\n\n%s\n\n%s%s" % [UI.esc(c.name), UI.esc(c.role).to_upper(), UI.esc(c.blurb), traits, "" if c.get("archetype") else "\n[color=#d8a070][font_size=13]This class arrives in a later build.[/font_size][/color]"])
	if c.get("archetype"):
		class_id = id
	create.confirm.disabled = not c.get("archetype") or game.roster.full
	if move_focus and create.cards.has(id):
		focus(create.cards[id])
	layout()


func random_name() -> void:
	create.name.text = game.roster.random_name()
	create.error.text = ""


func do_create() -> void:
	var cls = null
	for k in DB.text.title.classes:
		if k.id == class_id:
			cls = k
	if cls == null or not cls.get("archetype"):
		return
	var r: Dictionary = game.roster.create(Roster.tidy_name(create.name.text), cls.id)
	if not r.ok:
		create.error.text = r.reason
		return
	create.name.text = ""
	create.name.release_focus()
	game.enter_world(r.character.id)


# ------------------------------------------------------------ focus and input
func _nav_list() -> Array:
	var v = views.get(view)
	if v == null:
		return []
	var scope: Node = sel.confirm if view == "select" and confirm_delete else v
	var out := []
	for n in scope.find_children("*", "Control", true, false):
		if not n.get_meta("nav", false) or not n.is_visible_in_tree():
			continue
		if n is BaseButton and n.disabled:
			continue
		if view == "select" and not confirm_delete and sel.confirm.is_ancestor_of(n):
			continue
		out.append(n)
	return out


func focus(el: Control, from_mouse := false) -> void:
	if el == null:
		return
	if from_mouse and create.has("name") and create.name.has_focus():
		return
	if focus_el and is_instance_valid(focus_el) and focus_el is Button:
		_lit(focus_el, false)
	focus_el = el
	if el is Button:
		_lit(el, true)
	if el is LineEdit and not from_mouse:
		el.grab_focus()
	# moving onto a character or a class shows it
	if not from_mouse and el.has_meta("char") and el.get_meta("char") != selected:
		select(el.get_meta("char"))
	if not from_mouse and el.has_meta("class"):
		pick_class(el.get_meta("class"), false)


## the focus look (style.css .nav-focus): a gold edge and a warm glow
func _lit(b: Button, on: bool) -> void:
	b.modulate = Color(1.18, 1.12, 1.0, b.modulate.a) if on else Color(1, 1, 1, b.modulate.a)
	if b.has_meta("char") or b.has_meta("class"):
		return
	if on:
		b.add_theme_color_override("font_color", Color("f2e6c6"))
	else:
		b.remove_theme_color_override("font_color")
		if b == sel.get("yes"):
			b.add_theme_color_override("font_color", Color("e0a090"))


func move(step: int) -> void:
	var list := _nav_list()
	if list.is_empty():
		return
	var i := list.find(focus_el)
	i = 0 if i < 0 else (i + step + list.size()) % list.size()
	focus(list[i])


func press() -> void:
	var el := focus_el
	if el == null or (el is BaseButton and el.disabled):
		return
	if el is LineEdit:
		do_create()
		return
	if el.has_meta("char"):
		enter_selected() # A on a character plays them
		return
	if el is BaseButton:
		el.pressed.emit()


func _labels() -> void:
	var pad: bool = game.hud.pad_mode
	for h in hints:
		h[0].text = h[2] if pad else h[1]


## Lay out the views for the screen's size (style.css .select-side,
## .select-center, #class-detail).
func layout() -> void:
	var vp := get_viewport_rect().size
	for v in views.values():
		for c in v.get_children():
			if not (c is Control):
				continue
			if c.get_meta("side", false):
				c.size = Vector2(300, minf(c.get_combined_minimum_size().y, vp.y - 56))
				c.position = Vector2(28, roundf((vp.y - c.size.y) / 2))
			elif c.get_meta("centre", false):
				c.size = c.get_combined_minimum_size()
				var left := 28.0 + 300
				c.size.x = maxf(c.size.x, vp.x - left)
				c.position = Vector2(left, vp.y * 0.93 - c.size.y)
			elif c.get_meta("detail", false):
				c.size = c.get_combined_minimum_size()
				c.position = Vector2(vp.x - 28 - c.size.x, roundf((vp.y - c.size.y) / 2))


## Called each frame while the title is open, before anything else reads input.
func update(dt: float) -> void:
	var input = game.input
	var pad = game.pad
	var B := Pad.BUTTONS
	if _pad_shown != game.hud.pad_mode:
		_pad_shown = game.hud.pad_mode
		_labels()
	layout()
	if create.has("name") and create.name.has_focus():
		if input.consume("Escape"):
			create.name.release_focus()
		return # typing a name
	var up: bool = input.consume("ArrowUp") or input.consume("ArrowLeft") or pad.pressed(B.UP) or pad.pressed(B.LEFT)
	var down: bool = input.consume("ArrowDown") or input.consume("ArrowRight") or input.consume("Tab") or pad.pressed(B.DOWN) or pad.pressed(B.RIGHT)
	# the left stick moves too, repeating while held
	var sy: float = pad.left.y if pad.left.z > 0.5 else 0.0
	stick_wait -= dt
	if not sy:
		stick_wait = 0
	elif stick_wait <= 0:
		move(1 if sy > 0 else -1)
		stick_wait = 0.22
	if up:
		move(-1)
	if down:
		move(1)
	if input.consume("Enter") or input.consume("Space") or pad.pressed(B.A):
		press()
	if input.consume("Escape") or pad.pressed(B.B):
		back()
	if pad.pressed(B.Y) or input.consume("Delete"):
		if view == "select" and not confirm_delete:
			ask_delete()
		elif view == "create":
			random_name()
