class_name TitleScreen
extends Control
## The title screen, character select and character creation (alpha;
## src/ui/titleUI.js). One screen with three views; mouse, keyboard and
## gamepad all drive it. Every view keeps a list of controls you can move
## between: the D-pad, the left stick or the arrow keys move, and A / Enter
## / Space presses the one in focus. B / Esc goes back. On character select
## and creation the world shows behind, with the Warden standing in it.

const CLASSES_KEY := "classes"
const CLASS_COLOURS := {"warden":"#c79c6e","rogue":"#fff273","ranger":"#86c77a","occultist":"#b694ed","paladin":"#ed99bb","wizard":"#83d3f1"}

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
var creator_appearance: Dictionary = ForgeCharacter.defaults()
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
	if view=="select":
		g.fill_style=Color("15282c")
		g.fill_rect(0,0,r.size.x,r.size.y)
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
	b.add_theme_stylebox_override("normal", UI.frame(Vector4(18, 7, 18, 7), "button", 6))
	b.add_theme_stylebox_override("disabled", UI.frame(Vector4(18, 7, 18, 7), "button_disabled", 6))
	b.add_theme_stylebox_override("hover", UI.frame(Vector4(18, 7, 18, 7), "button_hover", 7))
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
	var crest_art := Icons.art("ui", "crest")
	if crest_art:
		var crest := TextureRect.new()
		crest.texture = crest_art
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest.custom_minimum_size = Vector2(0, 72)
		col.add_child(crest)
	else:
		var crest := UI.label(col, "✠", 30, Color(UI.GOLD, 0.7))
		crest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h1 := UI.logo(col, DB.text.title.name.to_upper(), 64)
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
	_build_credits(v)


## A small corner button that opens the credits list from data/meta/credits.json.
func _build_credits(v: Control) -> void:
	var btn := UI.square_button(v, "©", func(): main.credits.visible = not main.credits.visible, 30)
	btn.tooltip_text = "Credits"
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = Vector2(-46, -46)
	var c = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/credits.json"))
	var w := UI.window(v, "Credits", 560, func(): main.credits.visible = false)
	var p: PanelContainer = w.panel
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = Vector2(-280, -230)
	p.visible = false
	main.credits = p
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	w.body.add_child(scroll)
	var r := UI.rich(scroll, 13, 520)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := ""
	if c is Dictionary:
		text = "[color=#c9a45c]Created by[/color]\n%s\n" % UI.esc(c.get("creator", ""))
		for sec in c.get("sections", []):
			text += "\n[font_size=16][color=#efe2bf]%s[/color][/font_size]\n" % UI.esc(sec.title)
			if sec.has("note"):
				text += "[color=#9a8f78]%s[/color]\n" % UI.esc(sec.note)
			for e in sec.entries:
				text += "[color=#c9a45c]%s[/color]: %s by %s (%s)\n[color=#9a8f78]%s[/color]\n" % [UI.esc(e.what), UI.esc(e.title), UI.esc(e.author), UI.esc(e.licence), UI.esc(e.link)]
	UI.set_rich(r, text)


func _controls_table(parent: Node) -> Control:
	var row := UI.hbox(parent, 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# the mouse rows follow the control scheme (Settings: Classic controls)
	var mouse_rows := [["Left click", "Attack the enemy at the cursor; select a person; loot"], ["Hold left click", "Aim at the cursor as you walk"], ["Right click", "Spell slot 1, at the cursor; talk to a person"], ["1 · 2 · 3 · 4 · R · F", "The six spell slots (F: Brace)"]] if game.mouse_aim else [["Left click", "Select an enemy or person; loot (Click to move: walk up, then attack or talk)"], ["Right click", "Auto attack an enemy; talk; loot"], ["1 · 2 · 3 · 4 · Q · E", "The six spell slots (E: Brace)"]]
	var tables := [
		["Keyboard and mouse", [["WASD / arrow keys", "Move"]] + mouse_rows + [["Shift-1 to Shift-4", "The four utility slots (draught, torch, fishing...)"], ["F (G with mouse aim)", "Interact / loot everything nearby"], ["Space", "Jump"], ["Tab", "Next target"], ["Mouse wheel", "Zoom the camera"], ["B · C · P · L", "Bags · Character · Spellbook · Quest log"], ["K · O · Esc", "Save · Settings (keys, sound, click to move) · Close / clear target"]]],
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
	p.add_theme_stylebox_override("panel", UI.frame(Vector4(16, 14, 16, 14)))
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
	sel.preview = preload("res://game/ui/roster_preview.gd").new()
	v.add_child(sel.preview)
	var shade:=Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(func():
		var g:=Canvas2D.new(shade)
		var gradient:=g.create_linear_gradient(0,0,shade.size.x*0.65,0)
		Canvas2D.add_color_stop(gradient,0,Color(0.015,0.025,0.03,0.92))
		Canvas2D.add_color_stop(gradient,0.65,Color(0.015,0.025,0.03,0.45))
		Canvas2D.add_color_stop(gradient,1,Color(0,0,0,0))
		g.fill_style=gradient
		g.fill_rect(0,0,shade.size.x,shade.size.y))
	shade.resized.connect(func(): shade.queue_redraw())
	v.add_child(shade)
	sel.brand=UI.logo(v,"MYTHKEEP",30)
	sel.brand.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	sel.brand.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sel.panel = UI.panel(v,0)
	sel.panel.add_theme_stylebox_override("panel",UI.frame(Vector4(16,14,16,14)))
	var side := UI.vbox(sel.panel,6)
	UI.label(side,"YOUR CHARACTERS",22,UI.GOLD)
	sel.count=UI.label(side,"",13,UI.TEXT_DIM)
	sel.scroll=ScrollContainer.new()
	sel.scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sel.scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sel.scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	side.add_child(sel.scroll)
	sel.list=UI.vbox(sel.scroll,3)
	sel.list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var acts := UI.hbox(side,8)
	sel.create=_nav(acts,"Create Character",func(): show_view("create"),14)
	sel.delete=_nav(acts,"Delete Character",ask_delete,14)
	for button in [sel.create,sel.delete]:
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var tools := UI.hbox(side,8)
	sel.restore=_nav(tools,"Recently Deleted",show_deleted,13)
	sel.back=_nav(tools,"Back",back,13)
	sel.message=UI.label(side,"New adventures keep your existing heroes.",12,UI.TEXT_DIM)
	sel.message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	sel.confirm=UI.vbox(side,6)
	sel.confirm_text=UI.label(sel.confirm,"",13,UI.WARN)
	sel.confirm_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	sel.delete_name=LineEdit.new()
	sel.delete_name.placeholder_text="Type the character's name"
	sel.confirm.add_child(sel.delete_name)
	var ca := UI.hbox(sel.confirm,8)
	sel.yes=_nav(ca,"Delete Character",do_delete,13)
	sel.no=_nav(ca,"Cancel",cancel_delete,13)
	sel.yes.disabled=true
	sel.delete_name.text_changed.connect(func(value): sel.yes.disabled=value!=str(game.roster.by_id(selected).name) if game.roster.by_id(selected)!=null else true)
	sel.confirm.visible=false
	sel.deleted=UI.vbox(side,6)
	UI.label(sel.deleted,"Recover a character within 30 days",13,UI.GOLD)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y=210
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sel.deleted_scroll=scroll
	sel.deleted.add_child(scroll)
	sel.deleted_list=UI.vbox(scroll,6)
	_nav(sel.deleted,"Back to characters",func(): sel.deleted.visible=false; sel.scroll.visible=true,13)
	sel.deleted.visible=false
	sel.footer=UI.vbox(v,6)
	sel.name=UI.label(sel.footer,"",30,UI.GOLD,5)
	sel.name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	sel.line=UI.label(sel.footer,"",13,UI.TEXT,3)
	sel.line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var rotate := UI.hbox(sel.footer,8)
	rotate.alignment=BoxContainer.ALIGNMENT_CENTER
	_nav(rotate,"↶ Rotate",func(): sel.preview.turn-=PI/4,13)
	_nav(rotate,"Front",func(): sel.preview.turn=0,13)
	_nav(rotate,"Rotate ↷",func(): sel.preview.turn+=PI/4,13)
	sel.line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	sel.enter=_nav(sel.footer,"ENTER WORLD",enter_selected,18)
	sel.hint=_hint(sel.footer,"Drag the character to rotate · Select a slot to inspect", "Right stick rotates · A selects · Enter World to play")
	sel.hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	sel.enter.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	sel.enter.custom_minimum_size=Vector2(260,44)
	sel.enter.add_theme_stylebox_override("normal",UI.box(Color("b68a3d"),Color("ffe0a0"),4,2,Vector4(24,8,24,8)))
	sel.enter.add_theme_stylebox_override("hover",UI.box(Color("dcaf58"),Color("fff0bf"),4,2,Vector4(24,8,24,8)))
	sel.enter.add_theme_stylebox_override("pressed",UI.box(Color("916a28"),Color("ffe0a0"),4,2,Vector4(24,8,24,8)))
	sel.enter.add_theme_color_override("font_color",Color("21170a"))
	sel.enter.add_theme_color_override("font_hover_color",Color("21170a"))
	for button in [sel.delete,sel.yes]:
		button.add_theme_stylebox_override("normal",UI.box(Color("542329"),Color("ad5961"),3,1,Vector4(12,7,12,7)))
		button.add_theme_stylebox_override("hover",UI.box(Color("7d3038"),Color("e59094"),3,1,Vector4(12,7,12,7)))
		button.add_theme_color_override("font_color",Color("ffd1ca"))


func _build_create() -> void:
	var v := _view("create")
	create.preview = preload("res://game/ui/roster_preview.gd").new()
	create.preview.center_character()
	v.add_child(create.preview)
	var side := _side(v, "Create a character")
	UI.label(side, "CLASS", 12, UI.TEXT_DIM)
	create.list = UI.vbox(side, 6)
	var detail := UI.panel(v, 0)
	detail.add_theme_stylebox_override("panel", UI.frame(Vector4(16, 12, 16, 12)))
	detail.custom_minimum_size = Vector2(320, 0)
	create.panel = detail
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(detail_scroll)
	var detail_column := UI.vbox(detail_scroll, 8)
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.detail = UI.rich(detail_column, 13, 288)
	create.detail.custom_minimum_size.y = 80
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(288, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(scroll)
	var options := UI.vbox(scroll, 5)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(options, "APPEARANCE", 12, UI.GOLD)
	create.appearance_selectors = {}
	for key in ["sex", "face", "hair", "beard", "moustache", "skin_colour", "hair_colour", "eye_colour"]:
		var row_option := UI.hbox(options, 8)
		var text := UI.label(row_option, {"sex":"Body", "skin_colour":"Skin tone", "hair_colour":"Hair colour", "eye_colour":"Eye colour"}.get(key, key.capitalize()), 12, UI.TEXT_DIM)
		text.custom_minimum_size.x = 88
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.set_meta("nav", true)
		var values := ForgeCharacter.choices(key)
		choice.set_meta("values", values)
		for value in values:
			choice.add_item(str(value).replace("_", " ").capitalize())
		choice.select(values.find(creator_appearance[key]))
		choice.item_selected.connect(func(index):
			creator_appearance[key] = choice.get_meta("values")[index]
			_refresh_creator_preview()
		)
		row_option.add_child(choice)
		create.appearance_selectors[key] = choice
	_nav(options, "Randomise appearance", func():
		for key in creator_appearance:
			if key != "version": creator_appearance[key] = ForgeCharacter.choices(key, creator_appearance.sex).pick_random()
		for key in create.appearance_selectors:
			var choice: OptionButton = create.appearance_selectors[key]
			choice.select(choice.get_meta("values").find(creator_appearance[key]))
		_refresh_creator_preview()
	, 13)
	var c := _centre(v)
	c.set_meta("centre", false)
	create.footer = c
	var row := UI.hbox(c, 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_edit := LineEdit.new()
	name_edit.max_length = Roster.NAME_MAX
	name_edit.placeholder_text = "Name"
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.set_meta("nav", true)
	name_edit.text_submitted.connect(func(_t): do_create())
	name_edit.text_changed.connect(func(t): _tidy_name_box(name_edit, t))
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
	show_view("select" if which == "select" and (not game.roster.list.is_empty() or not game.roster.deleted.is_empty()) else "main")


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
	main.chars.visible = not roster.list.is_empty() or not roster.deleted.is_empty()
	var n := note
	if n == "":
		for c in roster.list:
			if not info(c).ok:
				n = "%s's save could not be read. It has been kept aside and will not be overwritten." % c.name
				break
	main.note.text = n
	main.note.visible = n != ""
	main.foot.text = "%s %s · saves are kept on this computer · %s" % [DB.text.title.name, DB.text.title.build, "D-pad · A" if game.hud.pad_mode else "↑↓ Enter"]
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
	var roster=game.roster
	if selected==null or roster.by_id(selected)==null:
		selected=roster.last if roster.last!=null else (roster.list[0].id if not roster.list.is_empty() else null)
	sel.count.text="%d / 10 characters" % roster.list.size()
	UI.clear(sel.list)
	sel.cards={}
	sel.slots=[]
	for index in 10:
		var c=roster.list[index] if index<roster.list.size() else null
		var button := Button.new()
		button.set_meta("nav",true)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.text="+   Create a new character"
		button.add_theme_font_size_override("font_size",14)
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		if c!=null:
			var i:=info(c)
			var id: String=c.id
			button.text=""
			var emblem:=TextureRect.new()
			emblem.texture=Icons.art("ui","class_"+("warrior" if c.classId=="warden" else c.classId))
			emblem.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			emblem.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			emblem.position=Vector2(8,7)
			emblem.size=Vector2(40,40)
			emblem.mouse_filter=Control.MOUSE_FILTER_IGNORE
			button.add_child(emblem)
			var words:=UI.rich(button,12,220)
			words.position=Vector2(58,4)
			words.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var text: String="[font_size=15][color=#efe2bf]%s[/color][/font_size]\n[font_size=12]Level %s · [color=%s]%s[/color][/font_size]\n[font_size=11][color=#a9b5ad]%s[/color][/font_size]" % [UI.esc(c.name),i.level,CLASS_COLOURS.get(c.classId,"#c9a45c"),UI.esc(class_name_of(c)),UI.esc(i.where)]
			UI.set_rich(words,text)
			button.set_meta("details",words)
			button.set_meta("emblem",emblem)
			button.tooltip_text="%s · Level %s %s · %s" % [c.name,i.level,class_name_of(c),i.where]
			button.set_meta("char",id)
			button.pressed.connect(func(): select(id))
			sel.cards[id]=button
		else:
			button.disabled=roster.full
			button.pressed.connect(func(): show_view("create"))
		sel.list.add_child(button)
		sel.slots.append(button)
	sel.create.disabled=roster.full
	sel.create.tooltip_text="All ten slots are occupied. Delete a character to free a slot." if roster.full else "Begin a new adventure without replacing your existing characters."
	sel.message.text="All ten slots are occupied. Deleted characters can be recovered for 30 days." if roster.full else "New adventures keep your existing heroes."
	sel.confirm.visible=false
	sel.message.visible=false
	sel.deleted.visible=false
	sel.scroll.visible=true
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
	sel.line.text = "Level %s %s · %s · played %s" % [i.level, class_name_of(c), i.where, ago(c.lastPlayed)] if c != null else "Choose an empty slot to begin"
	if c != null:
		_preview_selected(c)
	elif sel.preview.actor != null:
		sel.preview.actor.group.visible=false
	sel.enter.disabled = c == null or not i.ok
	sel.delete.disabled = c == null
	focus(sel.cards.get(id) if id != null and sel.has("cards") and sel.cards.has(id) else sel.create)
	if sel.cards.has(id):
		_reveal_selected.call_deferred()


func enter_selected() -> void:
	var c = game.roster.by_id(selected) if selected != null else null
	if c != null and info(c).ok:
		game.enter_world(c.id)


func ask_delete() -> void:
	var c = game.roster.by_id(selected) if selected != null else null
	if c == null:
		return
	confirm_delete = true
	sel.deleted.visible=false
	sel.scroll.visible=false
	sel.confirm_text.text = "Delete %s? This frees a slot. You can restore this hero for 30 days. Type their name to confirm." % c.name
	sel.delete_name.text=""
	sel.yes.disabled=true
	sel.confirm.visible = true
	sel.delete_name.grab_focus()


func cancel_delete() -> void:
	sel.scroll.visible=true
	confirm_delete = false
	sel.confirm.visible = false
	focus(sel.delete)


func do_delete() -> void:
	var c=game.roster.by_id(selected)
	if c==null or sel.delete_name.text!=c.name:
		return
	if not game.roster.remove(selected):
		sel.confirm_text.text="The character could not be deleted. Your save has been kept."
		return
	selected = null
	show_view("select")


# ------------------------------------------------------------ create
func _render_create() -> void:
	_refresh_creator_preview()
	UI.clear(create.list)
	create.cards = {}
	for c in DB.text.title.classes:
		var id: String = c.id
		var card := _card(create.list, [c.name, c.role if c.get("archetype") else "Coming later"], func(): pick_class(id), id == class_id, not c.get("archetype"))
		var words := card.get_child(0) as RichTextLabel
		if words:
			UI.set_rich(words, "[font_size=16][color=%s]%s[/color][/font_size]\n[color=#c9a45c]%s[/color]" % [CLASS_COLOURS.get(id, "#efe2bf"), UI.esc(c.name), UI.esc(c.role if c.get("archetype") else "Coming later")])
		card.set_meta("class", id)
		# Dan's class crest on the card's right (the Warden's is the warrior's)
		var crest := Icons.art("ui", "class_" + ("warrior" if id == "warden" else id))
		if crest:
			var img := TextureRect.new()
			img.texture = crest
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			img.size = Vector2(40, 40)
			img.position = Vector2(card.custom_minimum_size.x - 50, (card.custom_minimum_size.y - 40) / 2)
			card.add_child(img)
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
		_refresh_creator_preview()
	create.confirm.disabled = not c.get("archetype") or game.roster.full
	if move_focus and create.cards.has(id):
		focus(create.cards[id])
	layout()


func random_name() -> void:
	create.name.text = game.roster.random_name()
	create.error.text = ""


## One word, letters only, first letter capital, as it is typed.
func _tidy_name_box(edit: LineEdit, t: String) -> void:
	create.error.text = ""
	var tidy := Roster.tidy_name(t)
	if tidy == t:
		return
	var caret := edit.caret_column
	var dropped := t.length() - tidy.length()
	edit.text = tidy
	edit.caret_column = clampi(caret - dropped, 0, tidy.length())


func do_create() -> void:
	var cls = null
	for k in DB.text.title.classes:
		if k.id == class_id:
			cls = k
	if cls == null or not cls.get("archetype"):
		return
	var r: Dictionary = game.roster.create(Roster.tidy_name(create.name.text), cls.id, creator_appearance)
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
	if b==sel.get("enter"):
		b.add_theme_color_override("font_color",Color("21170a"))
		return
	if b==sel.get("delete") or b==sel.get("yes"):
		b.add_theme_color_override("font_color",Color("ffd1ca"))
		return
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
	if create.has("preview"):
		create.preview.position = Vector2.ZERO
		create.preview.size = vp
		create.panel.position = Vector2(vp.x - 328, 24)
		create.panel.size = Vector2(300, maxf(200, vp.y - 170))
		create.footer.position = Vector2(320, vp.y - 165)
		create.footer.size = Vector2(maxf(300, vp.x - 640), 150)
	if sel.has("panel"):
		var width := clampf(vp.x*0.28,300,380)
		sel.preview.position=Vector2.ZERO
		sel.preview.size=vp
		sel.panel.position=Vector2(20,16)
		sel.panel.size=Vector2(width,vp.y-32)
		sel.scroll.custom_minimum_size.y=80
		sel.deleted_scroll.custom_minimum_size.y=clampf(vp.y-400,90,220)
		for slot in sel.get("slots",[]):
			slot.custom_minimum_size=Vector2(0,54)
			if slot.has_meta("details"):
				var words: RichTextLabel=slot.get_meta("details")
				words.custom_minimum_size.x=maxf(120,width-108)
				words.size.x=maxf(120,width-108)
		sel.footer.position=Vector2(width+40,vp.y-184)
		sel.footer.size=Vector2(maxf(1,vp.x-width-60),172)
		sel.brand.position=Vector2(width+40,24)
		sel.brand.size=Vector2(maxf(1,vp.x-width-60),42)

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
	if view=="select" and sel.delete_name.has_focus():
		if input.consume("Escape"):
			cancel_delete()
		elif input.consume("Enter") and not sel.yes.disabled:
			do_delete()
		return
	if view=="select" and pad.right.z>0.2:
		sel.preview.turn+=pad.right.x*dt*2.0
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


func _preview_selected(c: Dictionary) -> void:
	var saved: Dictionary=game.save.read(c.key)
	var gear := {}
	if saved.status=="ok":
		gear=saved.data.inventory.equipment.duplicate(true)
	else:
		var arch: Dictionary=DB.archetypes.get(c.classId,DB.archetypes.warden)
		for slot in arch.get("startingGear",{}):
			if slot!="ammo":
				gear[slot]={"id":arch.startingGear[slot],"count":1}
	sel.preview.show_character(gear, saved.data.player.get("appearance", c.get("appearance")) if saved.status == "ok" else c.get("appearance"))


func _refresh_creator_preview() -> void:
	var gear := {}
	var arch: Dictionary = DB.archetypes.get(class_id, DB.archetypes.warden)
	for slot in arch.get("startingGear", {}):
		if slot != "ammo": gear[slot] = {"id":arch.startingGear[slot], "count":1}
	create.preview.show_character(gear, creator_appearance)


func show_deleted() -> void:
	cancel_delete()
	sel.scroll.visible=false
	sel.deleted.visible=true
	UI.clear(sel.deleted_list)
	if game.roster.deleted.is_empty():
		UI.label(sel.deleted_list,"No recently deleted characters.",13,UI.TEXT_DIM)
	for c in game.roster.deleted:
		var id: String=c.id
		var button:=_nav(sel.deleted_list,"Restore %s · %s" % [c.name,class_name_of(c)],func():
			var result: Dictionary=game.roster.restore(id)
			if result.ok:
				selected=id
				_render_select()
			else:
				sel.message.text=result.reason
			sel.message.visible=true,13)
		button.disabled=game.roster.full
	layout()


func _reveal_selected() -> void:
	var card=sel.get("cards",{}).get(selected)
	if is_instance_valid(card) and sel.scroll.is_ancestor_of(card):
		sel.scroll.ensure_control_visible(card)
