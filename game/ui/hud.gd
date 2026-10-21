class_name Hud
extends CanvasLayer
## The HUD (src/ui/hud.js): it reads game state and forwards requests
## (respawn, close). It never decides gameplay outcomes itself.
##
## Built in code from the browser's layout: the character frame top left,
## the target frame beside it, the log bottom left, and along the bottom the
## experience bar over the spell bar, with the cast and swing bars above.
## The item, quest, dialogue and shop windows come with the full UI.

const PANEL := Color(0.055, 0.047, 0.039, 0.78)
const BORDER := Color("6b5532")
const BORDER_DIM := Color("3e3220")
const GOLD := Color("c9a45c")
const TEXT := Color("d9cdb0")
const TEXT_DIM := Color("9a8f78")
const LOG_COLOURS := {
	"hit": Color("e2d3ae"), "hurt": Color("d98a72"), "loot": Color("d8bd73"), "rep": Color("9fb6e8"),
	"say": Color("f0e2a0"), "xp": Color("c9b77a"), "level": Color("c9b77a"), "heal": Color("a8c08a"),
	"lore": Color("b9b2a0"), "kill": Color("e0c8a0"), "muted": TEXT_DIM,
}
const SLOT := 48

var game
## 'title' | 'document' | 'death'. Bags, character panel and spellbook are
## not modal: the world keeps running while they are open, as in WoW.
var modal = "title"
var pad_mode := false
var showcase := false
var log_throttle := {}
var enemy_bars := {}
var recent_foe = null
var recent_foe_time := 0.0
var level_up_time := 0.0
var signpost = null
var shown_target = null
var font: Font

var root: Control
var bottom: VBoxContainer
var hp: Dictionary
var mp: Dictionary
var gauge: Dictionary
var xp: Dictionary
var pips: HBoxContainer
var buffs: HBoxContainer
var char_name: Label
var char_level: Label
var target: PanelContainer
var target_name: Label
var target_level: Label
var target_label: Label
var target_hp: Dictionary
var target_mp: Dictionary
var target_stagger: Dictionary
var target_auras: HBoxContainer
var cast: Dictionary
var swing: Dictionary
var swing_off: Dictionary
var slots: Array = []
var coins: Label
var log_box: VBoxContainer
var prompt: Label
var toast_label: Label
var toast_left := 0.0
var error_label: Label
var error_left := 0.0
var levelup: PanelContainer
var levelup_title: Label
var levelup_list: Label
var death: PanelContainer
var death_text: Label
var document: PanelContainer
var doc_title: Label
var doc_body: RichTextLabel
var sign_card: PanelContainer
var sign_text: Label
var region_label: Label
var tracker: Label
var world_tip_label: Label
var vignette: TextureRect
var vignette_t := 0.0
var bars_layer: Control
var numbers: DamageNumbers
var title_panel: PanelContainer
var title_note: Label
var title_list: VBoxContainer
var title_error: Label
var name_edit: LineEdit
var class_pick: OptionButton


func _init(g) -> void:
	game = g
	name = "Hud"
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", TEXT)
	root = Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()
	var ev = game.events
	ev.on("log", func(e): log_line(e.get("text", ""), e.get("kind", ""), e.get("throttle"), e.get("rarity")))
	ev.on("objectiveChanged", func(_e): refresh_objective())
	ev.on("questsChanged", func(_e): refresh_objective())
	ev.on("regionChanged", func(e):
		region_label.text = e.region.name
		if e.announce:
			toast(e.region.name)
			if e.region.id == "blackwood":
				log_line("The pines close overhead and the road light fails. The Blackwood.", "lore", "enter-blackwood"))
	ev.on("levelUp", show_level_up)
	ev.on("barChanged", func(_e): render_bar())
	ev.on("enemyHit", _fought)
	ev.on("playerHurt", _fought)


func _fought(e: Dictionary) -> void:
	if e.get("enemy") != null:
		recent_foe = e.enemy
		recent_foe_time = 6.0


# ------------------------------------------------------------ building
static func box(bg := PANEL, border := BORDER, pad := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(pad)
	return s


func _panel(parent: Control, pad := 6) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, BORDER, pad))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _label(parent: Control, text := "", size := 15, colour := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func gradient(hi: Color, lo: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, hi)
	g.set_color(1, lo)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 32
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	return t


## a bar: a dark track, a gradient fill and centred text
func _bar(parent: Control, hi: Color, lo: Color, height: int, text_size := 12) -> Dictionary:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, height)
	track.add_theme_stylebox_override("panel", box(Color(0.04, 0.035, 0.03, 0.9), BORDER_DIM, 0))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(track)
	var fill := TextureRect.new()
	fill.texture = gradient(hi, lo)
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	var l := _label(track, "", text_size)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return {"root": track, "fill": fill, "text": l}


static func set_fill(b: Dictionary, k: float) -> void:
	b.fill.anchor_right = clampf(k, 0, 1)
	b.fill.offset_right = 0


func _place(c: Control, preset: int, pos: Vector2, size := Vector2.ZERO) -> void:
	c.set_anchors_preset(preset)
	c.position = pos
	if size != Vector2.ZERO:
		c.custom_minimum_size = size
		c.size = size


func _build() -> void:
	# the character frame, top left
	var cp := _panel(root)
	cp.position = Vector2(12, 12)
	cp.custom_minimum_size = Vector2(260, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 3)
	cp.add_child(cv)
	var head := HBoxContainer.new()
	cv.add_child(head)
	char_name = _label(head, "", 16, GOLD)
	char_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_level = _label(head, "1", 14, TEXT_DIM)
	hp = _bar(cv, Color("b5422f"), Color("8e2a20"), 18)
	mp = _bar(cv, Color("5a82c8"), Color("2c4a8a"), 13, 10)
	gauge = _bar(cv, Color("e0a84a"), Color("9a5a1c"), 13, 10)
	pips = HBoxContainer.new()
	cv.add_child(pips)
	buffs = HBoxContainer.new()
	buffs.position = Vector2(12, 120)
	root.add_child(buffs)

	# the target frame, beside it
	target = _panel(root)
	target.position = Vector2(290, 12)
	target.custom_minimum_size = Vector2(240, 0)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	target.add_child(tv)
	var th := HBoxContainer.new()
	tv.add_child(th)
	target_name = _label(th, "", 16, GOLD)
	target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_level = _label(th, "", 14, TEXT_DIM)
	target_label = _label(tv, "", 12, TEXT_DIM)
	target_hp = _bar(tv, Color("b5422f"), Color("8e2a20"), 16)
	target_mp = _bar(tv, Color("5a82c8"), Color("2c4a8a"), 11, 9)
	target_stagger = _bar(tv, Color("e8d080"), Color("a08030"), 11, 9)
	target_auras = HBoxContainer.new()
	tv.add_child(target_auras)
	target.visible = false

	# region and quest tracker, top right
	region_label = _label(root, "", 18, GOLD)
	region_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	region_label.position = Vector2(-312, 12)
	region_label.size = Vector2(300, 24)
	tracker = _label(root, "", 13, TEXT)
	tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tracker.autowrap_mode = TextServer.AUTOWRAP_WORD
	tracker.position = Vector2(-312, 42)
	tracker.size = Vector2(300, 200)

	# the bottom: swing bars, cast bar, experience bar and the spell bar
	bottom = VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var bars_box := VBoxContainer.new()
	bars_box.custom_minimum_size = Vector2(300, 0)
	bars_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(bars_box)
	swing_off = _bar(bars_box, Color("9a9a9a"), Color("5a5a5a"), 12, 10)
	swing = _bar(bars_box, Color("c8c8c8"), Color("7a7a7a"), 12, 10)
	cast = _bar(bars_box, Color("e8c060"), Color("a07820"), 16, 12)
	xp = _bar(bottom, Color("a48a45"), Color("6b5a2c"), 12, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	_build_bar(row)
	coins = _label(root, "", 15, GOLD)
	coins.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coins.position = Vector2(-212, -36)
	coins.size = Vector2(200, 24)
	world_tip_label = _label(root, "", 14, TEXT)
	world_tip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	world_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	world_tip_label.position = Vector2(-312, -64)
	world_tip_label.size = Vector2(300, 24)
	var build := _label(root, _build_label(), 10, TEXT_DIM)
	build.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	build.position = Vector2(-212, -14)
	build.size = Vector2(200, 14)
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# the log, bottom left
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_box.position = Vector2(12, -150)
	log_box.custom_minimum_size = Vector2(420, 0)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	# messages in the middle
	prompt = _label(root, "", 16, TEXT)
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.position = Vector2(-300, -170)
	prompt.size = Vector2(600, 24)
	prompt.add_theme_stylebox_override("normal", box(PANEL, BORDER, 5))
	toast_label = _label(root, "", 18, GOLD)
	_centred(toast_label, 0.22)
	error_label = _label(root, "", 20, Color("ff3a2a"))
	_centred(error_label, 0.18)
	levelup = _panel(root, 10)
	levelup.set_anchors_preset(Control.PRESET_CENTER_TOP)
	levelup.position = Vector2(-140, 90)
	levelup.custom_minimum_size = Vector2(280, 0)
	var lv := VBoxContainer.new()
	levelup.add_child(lv)
	levelup_title = _label(lv, "", 20, GOLD)
	levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup_list = _label(lv, "", 14)
	levelup.visible = false

	# the red edge when you are hurt
	vignette = TextureRect.new()
	var vg := Gradient.new()
	vg.set_color(0, Color(0.6, 0, 0, 0))
	vg.set_color(1, Color(0.6, 0.02, 0.02, 0.55))
	vg.add_point(0.55, Color(0.6, 0, 0, 0))
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.1, 0.5)
	vignette.texture = vt
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0
	root.add_child(vignette)

	bars_layer = Control.new()
	bars_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars_layer)
	root.move_child(bars_layer, 0)
	numbers = DamageNumbers.new(game)
	root.add_child(numbers)
	root.move_child(numbers, 1)

	# the signpost card
	sign_card = _panel(root, 10)
	sign_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	sign_card.position = Vector2(-340, -80)
	sign_card.custom_minimum_size = Vector2(320, 0)
	var sv := VBoxContainer.new()
	sign_card.add_child(sv)
	_label(sv, "Signpost", 14, GOLD)
	sign_text = _label(sv, "", 14)
	sign_card.visible = false

	_build_death()
	_build_document()
	_build_title()


func _centred(l: Label, top: float) -> void:
	l.anchor_left = 0
	l.anchor_right = 1
	l.anchor_top = top
	l.anchor_bottom = top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0


func _build_label() -> String:
	return "Godot build"


func _build_death() -> void:
	death = _panel(root, 16)
	death.set_anchors_preset(Control.PRESET_CENTER)
	death.position = Vector2(-220, -80)
	death.custom_minimum_size = Vector2(440, 0)
	death.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	death.add_child(v)
	var t := _label(v, "You have fallen", 24, Color("d98a72"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_text = _label(v, "", 15)
	death_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	var b := Button.new()
	b.text = "Release spirit"
	b.pressed.connect(func(): game.release_spirit())
	v.add_child(b)
	death.visible = false


func _build_document() -> void:
	document = _panel(root, 16)
	document.set_anchors_preset(Control.PRESET_CENTER)
	document.position = Vector2(-280, -220)
	document.custom_minimum_size = Vector2(560, 440)
	document.mouse_filter = Control.MOUSE_FILTER_STOP
	document.add_theme_stylebox_override("panel", box(Color("d8c8a0"), Color("6b5532"), 18))
	var v := VBoxContainer.new()
	document.add_child(v)
	doc_title = _label(v, "", 22, Color("2a2018"))
	doc_title.remove_theme_color_override("font_outline_color")
	doc_title.add_theme_constant_override("outline_size", 0)
	doc_body = RichTextLabel.new()
	doc_body.bbcode_enabled = true
	doc_body.fit_content = false
	doc_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doc_body.add_theme_color_override("default_color", Color("2a2018"))
	v.add_child(doc_body)
	var b := Button.new()
	b.text = "Close"
	b.pressed.connect(func(): close_modal())
	v.add_child(b)
	document.visible = false


## The title screen and character select (a plain version; the full title
## screen comes with the rest of the UI).
func _build_title() -> void:
	title_panel = _panel(root, 20)
	title_panel.set_anchors_preset(Control.PRESET_CENTER)
	title_panel.position = Vector2(-230, -230)
	title_panel.custom_minimum_size = Vector2(460, 0)
	title_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	title_panel.add_child(v)
	var t := _label(v, "SHADOWFELL", 34, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(v, "Alpha  ·  Godot build", 13, TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_note = _label(v, "", 13, Color("d98a72"))
	title_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_list = VBoxContainer.new()
	v.add_child(title_list)
	v.add_child(HSeparator.new())
	_label(v, "New character", 15, GOLD)
	var row := HBoxContainer.new()
	v.add_child(row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	var dice := Button.new()
	dice.text = "Random"
	dice.pressed.connect(func(): name_edit.text = game.roster.random_name())
	row.add_child(dice)
	class_pick = OptionButton.new()
	for k in DB.text.title.classes:
		class_pick.add_item("%s  (%s)" % [k.name, k.role])
		class_pick.set_item_metadata(class_pick.item_count - 1, k.id)
	v.add_child(class_pick)
	var create := Button.new()
	create.text = "Create and play"
	create.pressed.connect(_create_character)
	v.add_child(create)
	title_error = _label(v, "", 13, Color("d98a72"))
	title_error.autowrap_mode = TextServer.AUTOWRAP_WORD


func show_title(note := "") -> void:
	modal = "title"
	title_note.text = note
	title_note.visible = note != ""
	_fill_title_list()
	for c in root.get_children():
		c.visible = c == title_panel or c == vignette
	title_panel.visible = true


func _fill_title_list() -> void:
	for c in title_list.get_children():
		c.queue_free()
	for c in game.roster.list:
		var row := HBoxContainer.new()
		title_list.add_child(row)
		var cls := ""
		for k in DB.text.title.classes:
			if k.id == c.classId:
				cls = k.name
		var play := Button.new()
		play.text = "Play %s  (%s)" % [c.name, cls]
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = c.id
		play.pressed.connect(func(): game.enter_world(id))
		row.add_child(play)
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func():
			game.roster.remove(id)
			_fill_title_list())
		row.add_child(del)
	if game.roster.list.is_empty():
		_label(title_list, "No characters yet.", 14, TEXT_DIM)


func _create_character() -> void:
	var r: Dictionary = game.roster.create(name_edit.text, class_pick.get_item_metadata(class_pick.selected))
	if not r.ok:
		title_error.text = r.reason
		return
	game.enter_world(r.character.id)


func hide_title() -> void:
	modal = null
	for c in root.get_children():
		c.visible = true
	title_panel.visible = false
	death.visible = false
	document.visible = false
	levelup.visible = false
	sign_card.visible = false
	target.visible = false
	render_bar()
	refresh_objective()


func set_character(c: Dictionary) -> void:
	char_name.text = c.name


# ------------------------------------------------------------ spell bar
func _build_bar(row: HBoxContainer) -> void:
	var i := 0
	for b in ActionBar.BAR_SLOTS:
		if b.get("utility") and not ActionBar.BAR_SLOTS[i - 1].get("utility"):
			var sep := Control.new()
			sep.custom_minimum_size = Vector2(10, 0)
			row.add_child(sep)
		var p := Panel.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.add_theme_stylebox_override("panel", box(Color("0b0908"), BORDER_DIM, 0))
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(p)
		var cd := ColorRect.new()
		cd.color = Color(0, 0, 0, 0.6)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.add_child(cd)
		var nm := _label(p, "", 10)
		nm.set_anchors_preset(Control.PRESET_FULL_RECT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD
		nm.clip_text = true
		var key := _label(p, "", 10, TEXT_DIM)
		key.position = Vector2(3, 1)
		var count := _label(p, "", 11, TEXT)
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.position = Vector2(-18, -16)
		var slot := i
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				var a = game.action_bar.slots[slot]
				if a:
					game.action_bar.clicked[a] = true)
		slots.append({"panel": p, "cd": cd, "name": nm, "key": key, "count": count, "ability": null})
		i += 1


func render_bar() -> void:
	var bar = game.action_bar
	if bar == null:
		return
	for i in slots.size():
		var s: Dictionary = slots[i]
		var a = bar.slots[i]
		s.ability = a
		s.name.text = ActionBar.entry_name(a) if a else ""
		s.panel.modulate.a = 1.0 if a else 0.55
	_apply_key_labels()


## Swap every key label between keyboard and gamepad names.
func set_pad_mode(on: bool) -> void:
	if pad_mode == on:
		return
	pad_mode = on
	_apply_key_labels()


func _apply_key_labels() -> void:
	for i in slots.size():
		var b: Dictionary = ActionBar.BAR_SLOTS[i]
		slots[i].key.text = b.pad if pad_mode else game.keys.label("bar%d" % i).replace("Shift-", "S")


# ---------------------------------------------------------------- modals
## Only the title screen and documents pause the world; the death screen
## and the item windows do not.
var blocks_gameplay: bool:
	get:
		return modal == "title" or modal == "document"

## any of the item, quest or dialogue windows (they come with the full UI)
var any_window_open: bool:
	get:
		return false


func window_gamepad(_pad, _dt: float) -> void:
	pass


## Bags, character panel, spellbook, quest log and the rest: toggles for
## B / C / P / L and the pad.
func toggle_panel(which: String) -> void:
	if modal:
		return
	toast("The %s window is on its way to the Godot build" % which)


func show_window(which: String) -> void:
	toggle_panel(which)


func toggle_window(which: String) -> void:
	toggle_panel(which)


## hovering over anyone in the world shows who they are
func world_tip(pick) -> void:
	var t := ""
	if pick != null:
		var o = pick.obj
		match pick.kind:
			"enemy":
				t = "%s  (level %s)" % [o.cfg.name, U.n(o.cfg.get("level", 1))]
			"npc":
				t = o.name + (", %s" % o.def.title if o.def.get("title") else "")
			"chest":
				t = "Chest"
			"sign":
				t = "Signpost"
			"loot":
				t = o.get("name", "Loot")
	world_tip_label.text = t


func open_document(id: String) -> void:
	var doc = DB.text.documents.get(id)
	if doc == null:
		return
	modal = "document"
	doc_title.text = doc.title
	var body = doc.body
	doc_body.text = html_to_bbcode("".join(body) if typeof(body) == TYPE_ARRAY else str(body))
	document.visible = true


## the few tags the documents use, as BBCode
static func html_to_bbcode(h: String) -> String:
	var s := h
	for pair in [["<br>", "\n"], ["</p>", "\n\n"], ["<b>", "[b]"], ["</b>", "[/b]"], ["<i>", "[i]"], ["</i>", "[/i]"], ["<em>", "[i]"], ["</em>", "[/i]"], ["<s>", "[s]"], ["</s>", "[/s]"], ["&amp;", "&"], ["&mdash;", "—"], ["&nbsp;", " "], ["&ndash;", "–"]]:
		s = s.replace(pair[0], pair[1])
	var re := RegEx.create_from_string("<[^>]+>")
	return re.sub(s, "", true).strip_edges()


func show_death(coins_lost: int, destination: String) -> void:
	close_modal(true)
	modal = "death"
	var where := "by your camp" if destination == "camp" else "at the last shrine you rested at" if destination == "shrine" else "at the road's end"
	death_text.text = "Your spirit will rise %s. Walk back to your body to live again with nothing lost, or return to life where you rise%s." % [where, ", %s lighter" % U.money(coins_lost) if coins_lost > 0 else ""]
	death.visible = true


func hide_death() -> void:
	death.visible = false
	modal = null


## Escape / B closes whatever is open. The death screen only closes by respawning.
func close_modal(force := false) -> bool:
	if modal == "title" or (modal == "death" and not force):
		return false
	if modal == "document":
		document.visible = false
		modal = null
		return true
	if signpost != null:
		sign_card.visible = false
		signpost = null
		return true
	return false


# ------------------------------------------------------------- feedback
func log_line(text: String, kind := "", throttle = null, rarity = null) -> void:
	if text == "":
		return
	var now := Time.get_ticks_msec()
	if throttle:
		if now - log_throttle.get(throttle, -1000000) < 1500:
			return
		log_throttle[throttle] = now
	var colour: Color = Items.rarity_colour(rarity) if rarity else LOG_COLOURS.get(kind, TEXT)
	var l := _label(log_box, text, 14, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(420, 0)
	l.set_meta("born", now)
	if kind == "lore":
		l.add_theme_font_override("font", _italic())
	while log_box.get_child_count() > 7:
		var c := log_box.get_child(0)
		log_box.remove_child(c)
		c.queue_free()


func _italic() -> Font:
	var f := FontVariation.new()
	f.base_font = font
	f.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return f


## Level-up card: each stat that rose, old value to new.
func show_level_up(e: Dictionary) -> void:
	levelup_title.text = "Level %d" % e.level
	var lines := []
	for g in e.get("gains", []):
		lines.append("%s   %s → %s  (+%s)" % [g.label, str(g.from), str(g.to), str(g.diff)])
	levelup_list.text = "\n".join(lines)
	level_up_time = 6.0
	levelup.visible = true
	levelup.modulate.a = 1


## A signpost read (E, or a click on it): where its arms point, on screen
## until you walk away from it.
func show_signpost(sp: Dictionary) -> void:
	var lines := []
	for l in Layout.signpost_lines(sp):
		lines.append("%s  %s   %d m %s" % [l.arrow, l.label, l.metres, l.dir])
	sign_text.text = "\n".join(lines)
	sign_card.visible = true
	signpost = {"sp": sp, "at": game.player.position}
	game.events.emit("signpostRead", {"id": sp.id})


func _update_signpost() -> void:
	if signpost == null:
		return
	var p: Vector3 = game.player.position
	var near: bool = U.hyp(p.x - signpost.sp.position[0], p.z - signpost.sp.position[1]) < 6 or p.distance_to(signpost.at) < 3
	if not near:
		sign_card.visible = false
		signpost = null


## A WoW-style error in red in the middle of the screen ("Out of range"):
## it shows at once and fades; the same message again only restarts it.
func error(text: String) -> void:
	error_label.text = text
	error_left = 1.4


func toast(text: String, kind := "") -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", Color("e09070") if kind == "bad" else GOLD)
	toast_left = 2.2


func flash_damage() -> void:
	vignette_t = 0.5


func clear_numbers() -> void:
	numbers.clear()


## the tracked quests under the region name
func refresh_objective() -> void:
	var q = game.quests
	if q == null:
		return
	var out := []
	for id in q.tracked:
		var def = DB.quests.get(id)
		if def == null:
			continue
		out.append(def.name)
		for o in q.objectives(id):
			out.append("  " + Quests.line(o))
	tracker.text = "\n".join(out)


func refresh_stats() -> void:
	var player = game.player
	var prog = game.progression
	char_level.text = "Level %d" % prog.level
	set_fill(hp, player.health / player.max_health)
	hp.text.text = "%d / %d" % [maxi(0, ceili(player.health)), player.max_health]
	_refresh_resources()
	var k: float = float(prog.xp) / prog.xp_to_next
	set_fill(xp, k)
	xp.text.text = "Level %d  ·  %d / %d experience (%d%%)%s" % [prog.level, prog.xp, prog.xp_to_next, floori(k * 100), "  ·  %d rested" % floori(prog.rested) if prog.rested >= 1 else ""]
	coins.text = U.money(game.inventory.coins)
	var inv = game.inventory
	for s in slots:
		var item = ActionBar.item_ref(s.ability) if s.ability else null
		if item == null:
			s.count.text = ""
			continue
		var off = inv.equipment.get("offHand")
		var have: int = inv.count(item) + (1 if off != null and off.id == item else 0)
		s.count.text = str(have) if Items.get_def(item).get("stack", 1) > 1 else ""
		s.panel.modulate.a = 0.45 if have == 0 else 1.0


## mana, the class bar and combo points under the health bar
func _refresh_resources() -> void:
	var r = game.resources
	mp.root.visible = r.max_mana > 0
	if r.max_mana > 0:
		set_fill(mp, r.mana / r.max_mana)
		mp.text.text = "%d / %d mana" % [floori(r.mana), r.max_mana]
	var g = r.gauge_cfg
	gauge.root.visible = g != null
	if g != null:
		var v: float = r.amount(g.id)
		set_fill(gauge, v / g.max)
		if g.get("colour"):
			gauge.fill.texture = gradient(Color(g.colour), Color(g.colour).darkened(0.45))
		var o := " · %s!" % g.overload.name if g.get("overload") and v >= g.max else ""
		gauge.text.text = "%d %s%s" % [floori(v), g.name, o]
	var p = r.points_cfg
	pips.visible = p != null
	if p != null:
		if pips.get_child_count() != int(p.max):
			for c in pips.get_children():
				c.queue_free()
			for i in int(p.max):
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(12, 12)
				pips.add_child(pip)
		var n := floori(r.amount(p.id))
		var i := 0
		for c in pips.get_children():
			c.color = Color("e0b050") if i < n else Color(0.15, 0.12, 0.1)
			i += 1


## the cooldown on a slot: [remaining, total, on the global cooldown]
func _cooldown(a) -> Array:
	var cds: Dictionary = game.player.cooldowns
	if a == "strike":
		return [cds.get("attack", 0.0), game.stats.attack_cooldown, false]
	if a == "item:healing_draught":
		return [cds.get("draught", 0.0), DB.CONFIG.draught.cooldown, false]
	if DB.spells.has(a):
		var t: Dictionary = DB.spells[a].tuning
		return [cds.get(a, 0.0), t.get("cooldown", 0.0), not t.get("offGlobalCooldown", false)]
	return [0.0, 0.0, false]


## Cooldown sweep per slot, plus the shared GCD sweep on GCD abilities.
func _refresh_slots() -> void:
	var player = game.player
	var gcd: float = player.cooldowns.get("gcd", 0.0)
	# with an enemy selected, abilities that cannot reach it go red (WoW)
	var tgt = game.targeting.current
	for s in slots:
		var a = s.ability
		var cd := _cooldown(a) if a else [0.0, 0.0, false]
		var own: float = cd[0] / cd[1] if cd[1] > 0 else 0.0
		# whichever finishes later is what the player is waiting on
		var show_gcd: bool = cd[2] and gcd > cd[0]
		var k: float = gcd / game.stats.global_cooldown if show_gcd else own
		s.cd.anchor_top = 1 - clampf(k, 0, 1)
		s.cd.offset_top = 0
		var ab = DB.abilities.get(a) if a else null
		var tint := Color.WHITE
		if ab != null:
			if not game.resources.can_afford(ab) or Spells.missing_gear(game, ab) != "":
				tint = Color(0.55, 0.6, 1.0)
			if tgt != null and tgt.alive and ab.get("target") == "enemy":
				var reach: float = (game.stats.ranged_reach if ab.get("ranged") else ab.get("range", 0.0)) + tgt.radius * 0.6
				if U.hyp(tgt.position.x - player.position.x, tgt.position.z - player.position.z) > reach:
					tint = Color(1, 0.45, 0.4)
			if a == "brace" and player.is_braced:
				tint = Color(1, 0.9, 0.5)
		s.name.modulate = tint


## The cast bar, buffs under the health bar, and the swing timers.
func _refresh_spells() -> void:
	var player = game.player
	var k = game.cooking.crafting
	var e = player.eating
	var c = null
	if player.casting != null:
		c = {"t": player.casting.t, "total": player.casting.total, "name": DB.spells[player.casting.id].name}
	elif k != null:
		c = {"t": k.t, "total": k.total, "name": "Cooking %s%s" % [Items.get_def(DB.recipes[k.id].output.item).name, " (%d)" % k.left if k.left > 1 else ""]}
	elif e != null:
		c = {"t": e.total - e.left, "total": e.total, "name": "Eating %s" % Items.get_def(e.id).name}
	elif game.fishing.bar != null:
		c = game.fishing.bar.duplicate()
		c.name = "Fishing"
	elif game.loot.gather_bar != null:
		c = game.loot.gather_bar
	cast.root.visible = c != null
	if c != null:
		set_fill(cast, c.t / c.total)
		cast.text.text = "%s  %.1f" % [c.name, maxf(0, c.total - c.t)]
	# the weapon swing timer: fills until the next blow lands, while auto
	# attack is on (one per hand when dual wielding; the second is Auto Shot's
	# when the target is beyond reach and a bow is on your back)
	var tg = game.targeting
	var st = game.stats
	var shooting: bool = tg.target_in_shot
	for hand in ["main", "off"]:
		var b: Dictionary = swing if hand == "main" else swing_off
		var hidden: bool = not tg.attacking or player.dead or (hand == "off" and not shooting and not st.dual_wielding)
		b.root.visible = not hidden
		if hidden:
			continue
		var h: String = "ranged" if hand == "off" and shooting else hand
		var pend = null
		if h == "off" and player.pending_off != null:
			pend = player.pending_off.t
		elif h == "ranged" and player.pending_shot != null:
			pend = player.pending_shot.t
		elif h == "main" and player.pending != null and player.pending.type == "strike":
			pend = player.pending.t
		var left: float = maxf(0, pend if pend != null else player.cooldowns.get("attackOff" if h == "off" else "ranged" if h == "ranged" else "attack", 0.0))
		var total: float = st.attack_cooldown_for(h)
		set_fill(b, 1 - left / total)
		var ammo = game.inventory.ammo if h == "ranged" else null
		var arrows := ""
		if h == "ranged":
			arrows = " · %d arrows" % game.inventory.count(ammo) if ammo else " · no arrows"
		var still := " · stand still to shoot" if h == "ranged" and player.moving and ammo else ""
		var w = st.hand_weapon(h)
		b.text.text = "%s%s%s%s  %.1f" % [w.name if w else "Fists", " (off hand)" if h == "off" else " (Auto Shot)" if h == "ranged" else "", arrows, still, left]
	var list: Array = game.spells.buff_list()
	var fed = game.cooking.well_fed_aura
	if fed != null:
		list.append(fed)
	_auras(buffs, list)
	_auras(target_auras, game.spells.dots_on(shown_target) if shown_target != null else [])


func _auras(box_: HBoxContainer, list: Array) -> void:
	var key := ",".join(list.map(func(a): return str(a.id)))
	if box_.get_meta("key", "") != key:
		box_.set_meta("key", key)
		for c in box_.get_children():
			c.queue_free()
		for a in list:
			var p := _panel(box_, 3)
			var v := VBoxContainer.new()
			p.add_child(v)
			var nm: String = a.get("name", DB.abilities.get(a.id, {}).get("name", str(a.id)))
			_label(v, nm, 10, GOLD)
			_label(v, "", 10)
	# (an aura that lasts until something ends it, such as Shadow, shows no time)
	var i := 0
	for c in box_.get_children():
		if c.is_queued_for_deletion() or i >= list.size():
			continue
		var a: Dictionary = list[i]
		var left = a.get("left", INF)
		var txt := "" if left == null or is_inf(left) else ("%dm" % ceili(left / 60.0) if left > 60 else str(ceili(left)))
		var lbl: Label = c.get_child(0).get_child(1)
		lbl.text = txt
		i += 1


func update(dt := 0.0) -> void:
	numbers.update(dt)
	var vp := root.get_viewport_rect().size
	bottom.size = bottom.get_combined_minimum_size()
	bottom.position = Vector2(roundf((vp.x - bottom.size.x) / 2), vp.y - bottom.size.y - 10)
	# fading messages
	toast_left = maxf(0, toast_left - dt)
	toast_label.modulate.a = minf(1, toast_left / 0.4)
	error_left = maxf(0, error_left - dt)
	error_label.modulate.a = minf(1, error_left / 0.6)
	vignette_t = maxf(0, vignette_t - dt)
	vignette.modulate.a = vignette_t * 2
	var now := Time.get_ticks_msec()
	for l in log_box.get_children():
		l.modulate.a = 0.45 if now - int(l.get_meta("born", now)) > 9000 else 1.0
	if level_up_time > 0:
		level_up_time -= dt
		levelup.modulate.a = clampf(level_up_time, 0, 1)
		if level_up_time <= 0:
			levelup.visible = false
	recent_foe_time = maxf(0, recent_foe_time - dt)
	_update_signpost()
	refresh_stats()
	_refresh_slots()
	_refresh_spells()

	var c = game.interaction.current
	var prompt_text: String = c.prompt if c != null and not modal else ""
	var key: String = "A" if pad_mode else (game.keys.label("interact") if game.keys.label("interact") != "" else "Space")
	prompt.text = "[%s]  %s" % [key, prompt_text] if prompt_text != "" else ""
	prompt.visible = prompt_text != ""

	_update_target()
	_update_enemy_bars()


## target frame: the selected enemy, else the one an ability would go to,
## else the enemy you last traded blows with; or a selected townsperson.
func _update_target() -> void:
	var tg = game.targeting
	var t = tg.current
	var recent = recent_foe if recent_foe_time > 0 and recent_foe != null and recent_foe.alive else null
	var friend = tg.friendly if t == null else null
	var shown = null if friend != null else (t if t != null else tg.soft if tg.soft != null else recent)
	shown_target = shown
	target.visible = shown != null or friend != null
	if friend != null:
		target_name.text = friend.name
		target_level.text = "Level %s" % U.n(friend.def.get("level", 1))
		target_label.text = friend.def.get("title", "")
		target_hp.root.visible = false
		target_mp.root.visible = false
		target_stagger.root.visible = false
	if shown != null:
		var cfg: Dictionary = shown.cfg
		target_name.text = cfg.name
		target_name.add_theme_color_override("font_color", Color("e8b04a") if cfg.get("elite") else GOLD)
		target_level.text = "Level %s" % U.n(cfg.get("level", 1))
		target_label.text = ("Attacking" if tg.target_in_reach or tg.target_in_shot else "Out of reach") if t != null and tg.attacking else "Elite" if cfg.get("elite") else ""
		target_hp.root.visible = true
		set_fill(target_hp, shown.health / shown.max_health)
		target_hp.text.text = "%d / %d" % [ceili(shown.health), shown.max_health]
		target_mp.root.visible = cfg.get("mana", 0) > 0
		if cfg.get("mana", 0) > 0:
			set_fill(target_mp, shown.mana / cfg.mana)
			target_mp.text.text = "%d / %d" % [ceili(shown.mana), cfg.mana]
		# a boss's stagger bar: control fills it, full means Staggered
		var sb = shown.stagger_bar
		target_stagger.root.visible = sb != null
		if sb != null:
			var full: bool = shown.staggered > 0
			set_fill(target_stagger, 1.0 if full else sb.value / sb.need)
			target_stagger.text.text = "Staggered %d" % ceili(shown.staggered) if full else "Stagger"


## enemy health bars, shown when engaged or damaged
func _update_enemy_bars() -> void:
	var cam: Camera3D = game.camera
	var t = game.targeting.current
	var seen := {}
	var vp := root.get_viewport_rect().size
	for e in game.enemies.list:
		if not e.alive:
			continue
		var nemesis: bool = game.afterlife.is_nemesis(e)
		if e.engaged <= 0 and e.health >= e.max_health and e != t and e != shown_target and not nemesis:
			continue
		seen[e.id] = true
		var bar = enemy_bars.get(e.id)
		if bar == null:
			bar = _enemy_bar(e)
			enemy_bars[e.id] = bar
		var pos: Vector3 = e.position + Vector3(0, e.cfg.get("barHeight", 3.0 if e.cfg.get("elite") else 2.1), 0)
		var s := cam.unproject_position(pos)
		var visible: bool = not cam.is_position_behind(pos) and s.x > -50 and s.x < vp.x + 50 and s.y > -50 and s.y < vp.y + 50
		bar.root.visible = visible
		if not visible:
			continue
		bar.root.position = s - Vector2(bar.root.size.x / 2, bar.root.size.y)
		set_fill(bar.hp, e.health / e.max_health)
		bar.hp.text.text = "%d / %d" % [ceili(e.health), e.max_health] if e == t else ""
		if bar.has("mp"):
			set_fill(bar.mp, e.mana / e.cfg.mana)
		var border := Color("f2d27a") if e == t else Color("c04040") if nemesis else BORDER_DIM
		bar.hp.root.get_theme_stylebox("panel").border_color = border
		# FFXIV-style cast bar under the name while a telegraphed attack winds up
		var c = e.casting
		bar.cast.root.visible = c != null
		if c != null:
			var tl = c.get("telegraph")
			set_fill(bar.cast, minf(1, tl.t / tl.duration) if tl != null else 0.0)
			bar.cast.text.text = c.get("label", "")
	for id in enemy_bars.keys():
		if not seen.has(id):
			enemy_bars[id].root.queue_free()
			enemy_bars.erase(id)


func _enemy_bar(e) -> Dictionary:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(110, 0)
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars_layer.add_child(v)
	var n := _label(v, e.cfg.name, 11, Color("e8b04a") if e.cfg.get("elite") else TEXT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var out := {"root": v, "hp": _bar(v, Color("b5422f"), Color("8e2a20"), 9, 8)}
	out.hp.root.add_theme_stylebox_override("panel", box(Color(0.04, 0.035, 0.03, 0.9), BORDER_DIM, 0))
	if e.cfg.get("mana", 0) > 0:
		out.mp = _bar(v, Color("5a82c8"), Color("2c4a8a"), 4, 6)
	out.cast = _bar(v, Color("e8c060"), Color("a07820"), 10, 8)
	return out
