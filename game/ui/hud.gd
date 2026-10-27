class_name Hud
extends CanvasLayer
## The HUD (src/ui/hud.js): it reads game state and forwards requests
## (respawn, close). It never decides gameplay outcomes itself.
##
## Built in code, laid out like a modern MMO (see layout()): the character
## frame top left with the target frame beside it, the minimap and tracked
## quests top right, the log bottom left, the spell bar bottom centre with
## the experience bar on it and the cast and swing bars above, and money,
## bag sockets and menus stacked bottom right.
## The windows live in ItemUI and QuestUI; the title screen in TitleScreen.

const LOG_COLOURS := {
	"hit": Color("e2d3ae"), "hurt": Color("d98a72"), "loot": Color("d8bd73"), "rep": Color("9fb6e8"),
	"say": Color("f0e2a0"), "xp": Color("c9b77a"), "level": Color("c9b77a"), "heal": Color("a8c08a"),
	"lore": Color("b9b2a0"), "kill": Color("e0c8a0"), "muted": UI.TEXT_DIM,
}
const SLOT := 48
const EDGE := 12.0 ## the gap between the HUD and the screen edge
## the menus in the right dock: [window, glyph, tip, key action, pad label]
const MICRO := [
	["character", "⚔", "Character", "character", "View"],
	["spellbook", "✦", "Spells", "spellbook", "↑"],
	["skills", "⚒", "Professions", "skills", ""],
	["talents", "❀", "Talents", "talents", ""],
	["quests", "!", "Quest Log", "quests", "→"],
	["settings", "☰", "Settings", "settings", ""],
]
const UNIT_GAP := 132.0 ## from the middle of the screen to each unit frame
const UNIT_W := 236.0 ## the width of your frame and your target's
const UNIT_H := 96.0 ## the room kept over the spell bar for the unit frames
const ORB_R := 14.0 ## the menu orbs round the minimap
const ORB_TOP := 250.0 ## degrees round the rim of the first orb (0 = east, 90 = south)
const ORB_STEP := 22.4
const CIRCLE := "shader_type canvas_item;\nvoid fragment() { if (distance(UV, vec2(0.5)) > 0.5) discard; }\n"

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
var portrait_of = null

var icons: Icons
var keybind_ui: KeybindUI
var items: ItemUI
var quests: QuestUI
var minimap: Minimap
var labels: WorldLabels
var title: TitleScreen
var loading: LoadingScreen

var root: Control
var char_panel: Control
var char_name: Label
var char_level: Label
var char_img: TextureRect
var char_badge: Label
var hp: Dictionary
var mp: Dictionary
var gauge: Dictionary
var pips: HBoxContainer
var buffs: HBoxContainer
var target: Control
var target_ring: Panel
var target_img: TextureRect
var target_badge: Label
var target_name: Label
var target_label: Label
var target_kind: Label ## combat type: ⚔ melee, ➶ ranged, ✦ magic
var target_hp: Dictionary
var target_mp: Dictionary
var target_stagger: Dictionary
var target_auras: HBoxContainer
var bottom: VBoxContainer
var action_bar: PanelContainer
var xp: Dictionary
var slots: Array = [] ## ISlot per bar slot
var dock: PanelContainer ## money and the bag sockets, bottom right
var micro_buttons := {} ## key action -> [orb Button, tip]
var coins: RichTextLabel
var _coins_shown := -1
var cast: Dictionary
var swing: Dictionary
var swing_off: Dictionary
var log_box: VBoxContainer
var log_shade: Panel
var prompt: PanelContainer
var prompt_key: Label
var prompt_text: Label
var _prompt_shown := ""
var _prompt_big := false ## a prompt that matters most (back to your body) sits large mid-screen
var toast_label: Label
var toast_left := 0.0
var zone_banner: VBoxContainer ## a zone's name across the top of the screen as you enter it
var zone_title: Label
var zone_sub: Label
var zone_left := 0.0
var world_map: WorldMapUI
var error_label: Label
var error_left := 0.0
var levelup: PanelContainer
var levelup_title: Label
var levelup_list: Label
var backdrop: ColorRect
var death: PanelContainer
var death_text: Label
var document: PanelContainer
var doc_title: Label
var doc_body: RichTextLabel
var sign_card: PanelContainer
var sign_text: Label
var quick_bind_banner: PanelContainer
var mute: Label
var vignette: TextureRect
var hurt: TextureRect
var vignette_t := 0.0
var bars_layer: Control
var player_auras: HBoxContainer ## your buffs over your head, above your name
var numbers: DamageNumbers


func _init(g) -> void:
	game = g
	g.hud = self # the windows built below reach the HUD through the game
	name = "Hud"
	UI.setup_fonts()
	icons = Icons.new()
	add_child(icons)
	UI.icons = icons
	root = Control.new()
	root.theme = UI.theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	keybind_ui = KeybindUI.new(game, self)
	_build()
	var ev = game.events
	ev.on("log", func(e): log_line(e.get("text", ""), e.get("kind", ""), e.get("throttle"), e.get("rarity")))
	ev.on("objectiveChanged", func(_e): refresh_objective())
	ev.on("questsChanged", func(_e): refresh_objective())
	ev.on("regionChanged", func(e):
		if e.announce:
			var lv := str(e.region.get("levels", ""))
			show_zone(e.region.name, ("Levels " + lv) if lv != "" and lv[0].is_valid_int() else lv)
			if e.region.id == "blackwood":
				log_line("The pines close overhead and the road light fails. The Blackwood.", "lore", "enter-blackwood"))
	ev.on("subzoneChanged", func(e):
		if e.announce and e.name != "" and zone_left < 2.0:
			show_zone(e.name, game.region.get("name", "") if game.region is Dictionary else "", 2.6))
	ev.on("levelUp", show_level_up)
	ev.on("barChanged", func(_e): render_bar())
	ev.on("enemyHit", _fought)
	ev.on("playerHurt", _fought)


func _fought(e: Dictionary) -> void:
	if e.get("enemy") != null:
		recent_foe = e.enemy
		recent_foe_time = 6.0


# ------------------------------------------------------------ building
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


## a bar (.bar): a dark track, a gradient fill and centred text
func _bar(parent: Control, hi: Color, lo: Color, height: int, text_size := 11) -> Dictionary:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, height)
	track.add_theme_stylebox_override("panel", UI.bar_track())
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
	var l := UI.label(track, "", text_size, Color("f0e4c8"), 4)
	l.add_theme_font_override("font", UI.bold)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return {"root": track, "fill": fill, "text": l}


static func set_fill(b: Dictionary, k: float) -> void:
	if b.fill is UnitBar:
		b.fill.k = k
		return
	b.fill.anchor_right = clampf(k, 0, 1)
	b.fill.offset_right = 0


func _build() -> void:
	bars_layer = Control.new()
	bars_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_auras = UI.hbox(bars_layer, 2)
	root.add_child(bars_layer)
	labels = WorldLabels.new(game)
	root.add_child(labels)
	numbers = DamageNumbers.new(game)
	root.add_child(numbers)

	_build_char_panel()
	_build_target()
	minimap = Minimap.new(game)
	root.add_child(minimap)

	# the log, bottom left (#log), on a smoky band that fades to the right
	log_shade = Panel.new()
	log_shade.add_theme_stylebox_override("panel", UI.shade("left", 0.55))
	log_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_shade)
	log_box = UI.vbox(root, 1)
	log_box.custom_minimum_size = Vector2(420, 0)

	# the cast and swing bars over the spell bar
	cast = _bar(root, Color("e8c060"), Color("a87a28"), 16)
	swing = _bar(root, Color("c8c4b8"), Color("7c776a"), 12, 10)
	swing_off = _bar(root, Color("a9b4c0"), Color("5d6874"), 11, 9)
	for b in [cast, swing, swing_off]:
		b.root.size = Vector2(240, b.root.custom_minimum_size.y)
	_build_bottom()
	_build_dock()
	_build_orbs()

	# the prompt: a key badge and what it does (#prompt)
	prompt = UI.panel(root, 0)
	prompt.add_theme_stylebox_override("panel", UI.frame(Vector4(14, 5, 14, 5)))
	var ph := UI.hbox(prompt, 8)
	prompt_key = UI.label(ph, "", 12, UI.GOLD)
	prompt_key.add_theme_stylebox_override("normal", UI.box(Color("1d1812"), UI.BORDER, 0, 1, Vector4(5, 0, 5, 1)))
	prompt_text = UI.label(ph, "", 14)
	prompt.visible = false

	world_map = WorldMapUI.new(game)
	root.add_child(world_map)
	zone_banner = VBoxContainer.new()
	zone_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_banner.add_theme_constant_override("separation", 0)
	root.add_child(zone_banner)
	zone_title = UI.label(zone_banner, "", 34, UI.GOLD)
	zone_title.add_theme_font_override("font", _spaced(34, 4))
	zone_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	zone_title.add_theme_constant_override("outline_size", 8)
	zone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_sub = UI.label(zone_banner, "", 15, UI.TEXT)
	zone_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	zone_sub.add_theme_constant_override("outline_size", 6)
	zone_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_banner.modulate.a = 0
	toast_label = UI.label(root, "", 18, UI.GOLD)
	toast_label.add_theme_stylebox_override("normal", UI.frame(Vector4(18, 6, 18, 6)))
	toast_label.modulate.a = 0
	error_label = UI.label(root, "", 20, Color("ff3a2a"), 4)
	error_label.modulate.a = 0
	levelup = UI.panel(root, 0)
	levelup.add_theme_stylebox_override("panel", UI.frame(Vector4(16, 10, 16, 12)))
	levelup.custom_minimum_size = Vector2(280, 0)
	var lv := UI.vbox(levelup, 6)
	levelup_title = UI.label(lv, "", 20, UI.GOLD)
	levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup_list = UI.label(lv, "", 14)
	levelup_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup.visible = false

	# the signpost card
	sign_card = UI.panel(root, 10)
	sign_card.custom_minimum_size = Vector2(320, 0)
	var sv := UI.vbox(sign_card, 4)
	UI.label(sv, "Signpost", 14, UI.GOLD)
	sign_text = UI.label(sv, "", 14)
	sign_card.visible = false

	quick_bind_banner = UI.panel(root, 0)
	quick_bind_banner.add_theme_stylebox_override("panel", UI.box(UI.WINDOW, UI.GOLD, 0, 1, Vector4(14, 8, 14, 8)))
	UI.label(quick_bind_banner, "Quick bind: hover a spell or utility bar slot and press a key. Esc when done.", 14, UI.GOLD)
	quick_bind_banner.visible = false
	mute = UI.label(root, "Sound off (Settings, O)", 12, UI.TEXT_DIM, 3)
	mute.visible = false

	# the dark edge of the screen, and the red flash when you are hurt
	vignette = _radial(Color(0, 0, 0, 0), Color(0, 0, 0, 0.45), 0.6)
	hurt = _radial(Color(0.59, 0.08, 0.04, 0), Color(0.59, 0.08, 0.04, 0.75), 0.7)
	hurt.modulate.a = 0
	# both darken the world, not the HUD: over the panels they turned the
	# corner UI (money, bags, minimap) a muddy half-grey
	root.move_child(hurt, 0)
	root.move_child(vignette, 0)

	items = ItemUI.new(game, self)
	items.sockets = _sockets_box
	root.add_child(items)
	for s in slots:
		items.bar_slots[s.loc] = s
		s.on_input = items.slot_input
		s.on_hover = items.slot_hover
	quests = QuestUI.new(game, self)
	root.add_child(quests)
	root.move_child(quests, items.get_index()) # windows under the item tooltip
	items.tip_on(minimap.zoom_buttons[0], "Zoom in")
	items.tip_on(minimap.zoom_buttons[1], "Zoom out")
	items.tip_on(coins, "Money")
	_build_modals()
	title = TitleScreen.new(game)
	root.add_child(title)
	title.visible = false
	loading = LoadingScreen.new()
	root.add_child(loading)


func _radial(inner: Color, outer: Color, from: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	g.add_point(from, inner)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.2, 0.5)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


static func _spaced(size: int, spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = UI.font
	f.spacing_glyph = spacing
	return f


## the game's name, the region and the build stamp (#title-area)
## the character frame (#char-panel): your round portrait with the bars
## running out of it, the level on a badge under it and combo points under
## the energy bar (as in the ARPG/MMO kits Dan pointed at)
func _build_char_panel() -> void:
	var f := _unit_frame(root, false)
	char_panel = f.root
	char_img = f.img
	char_badge = f.badge
	var cv: VBoxContainer = f.col
	char_name = UI.label(cv, "", 14, UI.GOLD, 4)
	char_name.add_theme_stylebox_override("normal", _indent(false))
	char_name.clip_text = true
	char_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	char_level = UI.label(null, "", 13, UI.TEXT_DIM) # the level shows on the badge
	hp = _unit_bar(cv, Color("d8553c"), Color("8a2218"), 18, false)
	mp = _unit_bar(cv, Color("5a8ad8"), Color("24407e"), 12, false, 10)
	gauge = _unit_bar(cv, Color("e0a84a"), Color("9a5a1c"), 12, false, 10)
	pips = UI.hbox(_indented(cv, false), 3)
	buffs = UI.hbox(_indented(cv, false), 4)
	game.events.on("equipmentChanged", func(_e): _player_portrait.call_deferred())


## your portrait, taken again when you enter the world or change gear
func _player_portrait() -> void:
	if game.player != null and game.player.model != null:
		char_img.texture = icons.player_portrait(game.player.model)


const PORTRAIT := 64.0 ## the round portrait on the unit frames
const BAR_UNDER := 14.0 ## how far the bars run in under the portrait's rim

## a unit frame with no box: a column of bars that starts under the round
## portrait's rim (on the right when `mirror`), the portrait drawn over it
func _unit_frame(parent: Control, mirror: bool) -> Dictionary:
	var f := Control.new()
	f.mouse_filter = Control.MOUSE_FILTER_STOP # clicks here never walk you
	f.custom_minimum_size = Vector2(UNIT_W, PORTRAIT + 14)
	parent.add_child(f)
	var col := UI.vbox(f, 3)
	var w := UNIT_W - PORTRAIT + BAR_UNDER
	col.custom_minimum_size.x = w
	col.position = Vector2(0.0 if mirror else UNIT_W - w, 2)
	var pic := _portrait(f, PORTRAIT)
	pic.root.position = Vector2(UNIT_W - PORTRAIT if mirror else 0.0, 4)
	return {"root": f, "col": col, "img": pic.img, "badge": pic.badge, "ring": pic.ring}


## a bar on a unit frame, its text kept clear of the portrait
func _unit_bar(parent: Control, hi: Color, lo: Color, height: int, mirror: bool, text_size := 11) -> Dictionary:
	var bar := UnitBar.new(hi, lo, height, mirror)
	parent.add_child(bar)
	var l := UI.label(bar, "", text_size, Color("f0e4c8"), 4)
	l.add_theme_font_override("font", UI.bold)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 0.0 if mirror else BAR_UNDER
	l.offset_right = -BAR_UNDER if mirror else 0.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return {"root": bar, "fill": bar, "text": l}


## room for the portrait's rim before a frame's text
func _indent(mirror: bool) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	if mirror:
		s.content_margin_right = BAR_UNDER + 4
	else:
		s.content_margin_left = BAR_UNDER + 4
	return s


func _indented(parent: Control, mirror: bool) -> Control:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_right" if mirror else "margin_left", int(BAR_UNDER) + 4)
	parent.add_child(m)
	return m


## a round portrait in a bronze ring with the level on a badge under it
func _portrait(parent: Control, d: float) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(d, d)
	holder.size = Vector2(d, d)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var ring_panel := Panel.new()
	ring_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_panel.size = Vector2(d, d)
	var ring := UI.box(Color("1a1510"), Color("b08a4a"), 0, 3)
	ring.set_corner_radius_all(int(d / 2))
	ring.shadow_color = Color(0, 0, 0, 0.6)
	ring.shadow_size = 4
	ring_panel.add_theme_stylebox_override("panel", ring)
	holder.add_child(ring_panel)
	var img := TextureRect.new()
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.position = Vector2(3, 3)
	img.size = Vector2(d - 6, d - 6)
	var sh := Shader.new()
	sh.code = CIRCLE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	img.material = mat
	holder.add_child(img)
	var badge_label := UI.label(holder, "", 12, Color("f0d890"))
	var badge := UI.box(Color("120e0a"), Color("b08a4a"), 0, 1, Vector4(4, 0, 4, 0))
	badge.set_corner_radius_all(9)
	badge_label.add_theme_stylebox_override("normal", badge)
	badge_label.add_theme_font_override("font", UI.bold)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.custom_minimum_size = Vector2(26, 18)
	badge_label.size = Vector2(26, 18)
	badge_label.position = Vector2(d / 2 - 13, d - 9)
	return {"root": holder, "ring": ring_panel, "img": img, "badge": badge_label}


## the target frame, the player's mirror: portrait on the right (#target-frame)
func _build_target() -> void:
	var f := _unit_frame(root, true)
	target = f.root
	target_ring = f.ring
	target_img = f.img
	target_badge = f.badge
	# the combat type (melee, ranged, magic) shows when you point at the portrait
	target_img.mouse_filter = Control.MOUSE_FILTER_STOP
	target_img.mouse_entered.connect(func(): items.cursor_tip(target_kind.get_meta("tip", "")))
	target_img.mouse_exited.connect(func(): items.cursor_tip_off())
	var tv: VBoxContainer = f.col
	var nr := UI.hbox(tv, 6)
	target_label = UI.label(nr, "", 11, UI.TEXT_DIM, 4)
	target_name = UI.label(nr, "", 14, Color("e8c8a0"), 4)
	target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	target_name.add_theme_stylebox_override("normal", _indent(true))
	target_name.clip_text = true
	target_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# not shown (its crossed swords read as a close button); holds the tip
	target_kind = UI.label(null, "", 13, UI.GOLD, 3)
	target_hp = _unit_bar(tv, Color("d8553c"), Color("8a2218"), 18, true)
	target_mp = _unit_bar(tv, Color("5a8ad8"), Color("24407e"), 12, true, 9)
	target_stagger = _unit_bar(tv, Color("e8d080"), Color("a08030"), 12, true, 9)
	var ta := _indented(tv, true)
	target_auras = UI.hbox(ta, 4)
	target_auras.alignment = BoxContainer.ALIGNMENT_END
	target.visible = false


## experience on top of the spell bar, bottom centre (#bottom-bar)
func _build_bottom() -> void:
	bottom = UI.vbox(root, 6) # the XP bar stands clear of the bar and its end caps
	var bar_frame := UI.capped_frame(Vector4(4, 3, 4, 2))
	# the experience bar spans the frame itself, not the end caps beside it
	var xm := MarginContainer.new()
	xm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xm.add_theme_constant_override("margin_left", int(bar_frame.cap_room) + 4)
	xm.add_theme_constant_override("margin_right", int(bar_frame.cap_room) + 4)
	bottom.add_child(xm)
	# purple like the +XP popups, so the pale text reads against it
	xp = _bar(xm, Color("8a62c4"), Color("43286e"), 16, 12)
	# a notch every tenth of the level, so progress reads at a glance
	var ticks := Control.new()
	ticks.set_anchors_preset(Control.PRESET_FULL_RECT)
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticks.draw.connect(func():
		for i in range(1, 10):
			var x := roundf(ticks.size.x * i / 10.0)
			ticks.draw_line(Vector2(x, 2), Vector2(x, ticks.size.y - 2), Color(0, 0, 0, 0.7), 1.0)
			ticks.draw_line(Vector2(x + 1, 2), Vector2(x + 1, ticks.size.y - 2), Color(1, 0.92, 0.75, 0.22), 1.0))
	ticks.resized.connect(ticks.queue_redraw)
	xp.root.add_child(ticks)
	xp.root.move_child(ticks, 1)
	action_bar = UI.panel(bottom, 0)
	action_bar.add_theme_stylebox_override("panel", bar_frame)
	action_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UI.hbox(action_bar, 2)
	var i := 0
	for b in ActionBar.BAR_SLOTS:
		if b.get("utility") and not ActionBar.BAR_SLOTS[i - 1].get("utility"):
			row.add_child(_divider())
		var s := ISlot.new("a:%d" % i, SLOT)
		s.bar = true
		row.add_child(s)
		slots.append(s)
		i += 1


var _sockets_box: HBoxContainer


## bottom right, one row level with the spell bar: money and the bag
## sockets (#right-dock). The menus are orbs round the minimap (_build_orbs).
func _build_dock() -> void:
	dock = UI.panel(root, 0)
	dock.add_theme_stylebox_override("panel", UI.frame(Vector4(10, 4, 8, 4)))
	dock.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UI.hbox(dock, 6)
	row.alignment = BoxContainer.ALIGNMENT_END
	coins = UI.rich(row, 15)
	coins.autowrap_mode = TextServer.AUTOWRAP_OFF
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_divider())
	_sockets_box = UI.hbox(row, 2)
	_sockets_box.alignment = BoxContainer.ALIGNMENT_END
	_sockets_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## the menus as round buttons down the minimap's left rim, RuneScape style,
## from the top: character first. The key shows in each one's tip.
func _build_orbs() -> void:
	var i := 0
	for m in MICRO:
		var b := minimap.orb(ORB_TOP - ORB_STEP * i, ORB_R)
		var which: String = m[0]
		var action: String = m[3]
		var pad_label: String = m[4]
		var tip: String = m[2]
		b.pressed.connect(func(): toggle_panel(which))
		var glyph := UI.label(b, m[1], 15, UI.GOLD)
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.mouse_entered.connect(func():
			var k: String = pad_label if pad_mode else game.keys.label(action)
			items.cursor_tip(tip + (" (%s)" % k if k != "" else "")))
		b.mouse_exited.connect(func(): items.cursor_tip_off())
		micro_buttons[action] = [b, tip]
		i += 1


## the kit's bronze divider, upright between two groups in a row
func _divider() -> Control:
	var sep := TextureRect.new()
	sep.texture = UI.kit("divider")
	sep.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sep.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sep.custom_minimum_size = Vector2(8, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 3)
	m.add_theme_constant_override("margin_right", 3)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(sep)
	return m


func _build_modals() -> void:
	backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.35)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	root.add_child(backdrop)
	# the death screen (.death-panel)
	death = UI.panel(root, 20, UI.WINDOW)
	death.custom_minimum_size = Vector2(520, 0)
	death.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(death, 12)
	var t := UI.label(v, "You have fallen", 34, Color("b9705a"))
	t.add_theme_font_override("font", _spaced(34, 6))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_text = UI.label(v, "", 15, Color("c6bba0"))
	death_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	death_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bb := UI.hbox(v, 12)
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.button(bb, "Release spirit", func(): game.release_spirit(), 15)
	death.visible = false
	# a document (.parchment)
	document = UI.panel(root, 0, Color("2a2219"), Color("8a6d3b"))
	document.add_theme_stylebox_override("panel", UI.box(Color("2a2219"), Color("8a6d3b"), 0, 1, Vector4(18, 14, 18, 18)))
	document.custom_minimum_size = Vector2(560, 440)
	document.mouse_filter = Control.MOUSE_FILTER_STOP
	var dv := UI.vbox(document, 8)
	var dh := UI.hbox(dv, 8)
	doc_title = UI.label(dh, "", 20, UI.GOLD)
	doc_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.button(dh, "Close", func(): close_modal(), 12)
	UI.rule(dv)
	doc_body = UI.rich(dv, 15)
	doc_body.fit_content = false
	doc_body.scroll_active = true
	doc_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doc_body.add_theme_color_override("default_color", Color("e2d4b0"))
	document.visible = false


# ------------------------------------------------------------ title screen
func show_title(note := "") -> void:
	modal = "title"
	_set_world_ui(false)
	title.open(note, "select" if Game.to_select else "main")


func hide_title() -> void:
	modal = null
	title.close()
	_set_world_ui(true)
	mute.visible = muted
	death.visible = false
	document.visible = false
	backdrop.visible = false
	levelup.visible = false
	sign_card.visible = false
	target.visible = false
	prompt.visible = false
	render_bar()
	items.render()
	quests.render()
	refresh_objective()


## the loading screen over the world while Game.load_world() warms it up
func show_loading() -> void:
	modal = "loading"
	loading.open()


func hide_loading() -> void:
	if modal == "loading":
		modal = null
	loading.close()


func _set_world_ui(on: bool) -> void:
	for c in root.get_children():
		if c != title and c != loading:
			c.visible = on
	if on:
		for c in [death, document, backdrop, levelup, sign_card, quick_bind_banner, prompt, mute, world_map]:
			c.visible = false
		hurt.modulate.a = 0


var muted := false


func set_muted(m: bool) -> void:
	muted = m
	if modal != "title":
		mute.visible = m


func set_character(c: Dictionary) -> void:
	char_name.text = c.name
	_player_portrait.call_deferred()


# ------------------------------------------------------------ spell bar
func render_bar() -> void:
	var bar = game.action_bar
	if bar == null:
		return
	for i in slots.size():
		var s: ISlot = slots[i]
		var a = bar.slots[i]
		var item = ActionBar.item_ref(a) if a else null
		s.icon = (icons.item(item) if item else icons.abilities.get(a)) if a else null
		s.letter = "" if s.icon != null or a == null else ActionBar.entry_name(a).substr(0, 1)
		s.dim = 1.0 if a else 0.55
		s.queue_redraw()
	apply_key_labels()


## Swap every key label between keyboard and gamepad names.
func set_pad_mode(on: bool) -> void:
	if pad_mode == on:
		return
	pad_mode = on
	_prompt_shown = ""
	apply_key_labels()
	items.render()
	quests.render()


## keyboard labels follow the player's key bindings
func apply_key_labels() -> void:
	var keys = game.keys
	for i in slots.size():
		var b: Dictionary = ActionBar.BAR_SLOTS[i]
		slots[i].key = b.pad if pad_mode else keys.label("bar%d" % i).replace("Shift-", "⇧").replace(" / ", "/")
		slots[i].queue_redraw()


## the top of the bottom bar and the unit frames over it, for tooltips
## that sit above them
func bottom_top() -> float:
	return minf(bottom.position.y, char_panel.position.y)


## is a screen point over the fixed HUD (not a window)?
func over_hud(at: Vector2) -> bool:
	for c in [char_panel, target, bottom, dock, minimap, quests.tracker]:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(at):
			return true
	return false


# ---------------------------------------------------------------- modals
## Only the title screen and documents pause the world; the death screen
## and the item windows do not.
var blocks_gameplay: bool:
	get:
		return modal == "title" or modal == "document" or modal == "loading"

## any of the item, quest or dialogue windows
var any_window_open: bool:
	get:
		return items.any_open or quests.any_open


## With a window open the pad drives it: the quest windows first.
func window_gamepad(pad, dt: float) -> void:
	if quests.any_open and quests.gamepad(pad, dt):
		return
	if items.any_open:
		items.gamepad(pad, dt)


## Bags, character panel, spellbook, quest log and the rest: toggles for
## B / C / P / L, the dock and the pad.
func toggle_panel(which: String) -> void:
	if modal:
		return
	game.audio.sfx("quest_log" if which == "quests" else "panel", 0.6)
	if which == "quests":
		quests.toggle_log()
	else:
		items.toggle(which)


func toggle_world_map() -> void:
	if modal:
		return
	game.audio.sfx("panel", 0.6)
	if world_map.visible:
		world_map.visible = false
	else:
		root.move_child(world_map, -1) # over the rest of the HUD
		world_map.open()


func show_window(which: String) -> void:
	if which == "quests":
		quests.toggle_log(true)
	elif which == "map":
		root.move_child(world_map, -1)
		world_map.open()
	else:
		items.show_window(which)


func toggle_window(which: String) -> void:
	toggle_panel(which)


## hovering over anyone in the world shows who they are
func world_tip(pick) -> void:
	items.world_tip(pick)


func open_document(id: String) -> void:
	var doc = DB.text.documents.get(id)
	if doc == null:
		return
	game.events.emit("documentRead", {"id": id})
	modal = "document"
	doc_title.text = doc.title
	var body = doc.body
	doc_body.text = ""
	UI.set_rich(doc_body, html_to_bbcode("".join(body) if typeof(body) == TYPE_ARRAY else str(body)))
	backdrop.visible = true
	document.visible = true


## the few tags the documents use, as BBCode
static func html_to_bbcode(h: String) -> String:
	var s := h.replace("[", "[lb]")
	for pair in [["<br>", "\n"], ["</p>", "\n\n"], ["</div>", "\n"], ["<b>", "[b]"], ["</b>", "[/b]"], ["<i>", "[i]"], ["</i>", "[/i]"], ["<em>", "[i]"], ["</em>", "[/i]"], ["<s>", "[s]"], ["</s>", "[/s]"], ["&amp;", "&"], ["&mdash;", "—"], ["&nbsp;", " "], ["&ndash;", "–"]]:
		s = s.replace(pair[0], pair[1])
	var re := RegEx.create_from_string("<[^>]+>")
	return re.sub(s, "", true).strip_edges()


func show_death(_coins_lost: int, destination: String) -> void:
	close_modal(true)
	modal = "death"
	var where := "by your camp" if destination == "camp" else "at the last shrine you rested at" if destination == "shrine" else "at the road's end"
	death_text.text = "Your spirit will rise %s. What you carried lies in a grave by your body: reach it within %d minutes, before scavengers do. Walk back to your body, or return to life where you rise; either way you come back wounded." % [where, roundi(DB.CONFIG.death.graveSeconds / 60.0)]
	backdrop.visible = true
	death.visible = true


func hide_death() -> void:
	death.visible = false
	backdrop.visible = false
	modal = null


## Escape / B closes whatever is open. The death screen only closes by respawning.
func close_modal(force := false) -> bool:
	if modal == "title" or modal == "loading" or (modal == "death" and not force):
		return false
	if keybind_ui.quick:
		keybind_ui.set_quick(false)
		return true
	if modal == "document":
		document.visible = false
		backdrop.visible = false
		modal = null
		return true
	if world_map.visible:
		world_map.visible = false
		return true
	if quests.close_all():
		return true
	if items.close_all():
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
	var colour: Color = Items.rarity_colour(rarity) if rarity else LOG_COLOURS.get(kind, UI.TEXT)
	var l := UI.label(log_box, text, 13, colour, 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(log_box.custom_minimum_size.x, 0)
	l.set_meta("born", now)
	if kind == "lore":
		l.add_theme_font_override("font", UI.italic)
	while log_box.get_child_count() > 7:
		var c := log_box.get_child(0)
		log_box.remove_child(c)
		c.queue_free()


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


## WoW-style: the place's name large across the top, a line under it.
func show_zone(title: String, sub: String, seconds := 3.6) -> void:
	zone_title.text = title
	zone_sub.text = sub
	zone_sub.visible = sub != ""
	zone_left = seconds
	zone_banner.size = zone_banner.get_combined_minimum_size()
	var vp := root.get_viewport_rect().size if root.is_inside_tree() else Vector2(1280, 720)
	zone_banner.position = Vector2(roundf((vp.x - zone_banner.size.x) / 2), roundf(vp.y * 0.1))


func toast(text: String, kind := "") -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", Color("e09070") if kind == "bad" else UI.GOLD)
	toast_left = 2.2


func flash_damage() -> void:
	vignette_t = 0.45


func clear_numbers() -> void:
	numbers.clear()


## the tracked quests under the minimap
func refresh_objective() -> void:
	if game.quests == null:
		return
	quests.render_tracker()


func refresh_stats() -> void:
	var player = game.player
	var prog = game.progression
	char_level.text = "Level %d" % prog.level
	char_badge.text = str(prog.level)
	set_fill(hp, player.health / player.max_health)
	hp.text.text = "%d / %d" % [maxi(0, ceili(player.health)), player.max_health]
	_refresh_resources()
	var k: float = float(prog.xp) / prog.xp_to_next
	if prog.level >= DB.CONFIG.progression.maxLevel:
		set_fill(xp, 1.0)
		xp.text.text = "Level %d  ·  maximum level" % prog.level
	else:
		set_fill(xp, k)
		xp.text.text = "Level %d   %d / %d XP  (%d%%)%s" % [prog.level, prog.xp, prog.xp_to_next, floori(k * 100), "   %d%% rested" % prog.rested_percent if prog.rested >= 1 else ""]
	var c: int = game.inventory.coins
	if c != _coins_shown:
		_coins_shown = c
		coins.text = ""
		UI.set_rich(coins, UI.money(c))
	var inv = game.inventory
	for s in slots:
		var a = game.action_bar.slots[int(s.loc.substr(2))]
		var item = ActionBar.item_ref(a) if a else null
		if item == null:
			s.count = ""
			continue
		var off = inv.equipment.get("offHand")
		var have: int = inv.count(item) + (1 if off != null and off.id == item else 0)
		s.count = str(have) if Items.get_def(item).get("stack", 1) > 1 else ""
		s.dim = 0.45 if have == 0 else 1.0


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
		if g.get("colour") and gauge.root.get_meta("colour", "") != g.colour:
			gauge.root.set_meta("colour", g.colour)
			gauge.fill.tint(Color(g.colour), Color(g.colour).darkened(0.45))
		var o := " · %s!" % g.overload.name if g.get("overload") and v >= g.max else ""
		gauge.text.text = "%d %s%s" % [floori(v), g.name, o]
	var p = r.points_cfg
	pips.visible = p != null
	if p != null:
		if pips.get_child_count() != int(p.max):
			UI.clear(pips)
			for i in int(p.max):
				var pip := Panel.new()
				pip.custom_minimum_size = Vector2(11, 11)
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pips.add_child(pip)
		var n := floori(r.amount(p.id))
		var i := 0
		for c in pips.get_children():
			var on := i < n
			if not c.has_meta("on") or c.get_meta("on") != on:
				c.set_meta("on", on)
				# combo points: lit embers under the energy bar
				var st := UI.box(Color("e8602c") if on else Color("1a1410"), Color("d8a050") if on else Color("5a4630"), 0, 1)
				st.set_corner_radius_all(6)
				c.add_theme_stylebox_override("panel", st)
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


## Cooldown sweep per slot, plus the shared GCD sweep on GCD abilities;
## red when out of reach, dull blue without the resource (.oor, .nores).
func _refresh_slots() -> void:
	var player = game.player
	var gcd: float = player.cooldowns.get("gcd", 0.0)
	var tgt = game.targeting.current
	for s in slots:
		var a = game.action_bar.slots[int(s.loc.substr(2))]
		var cd := _cooldown(a) if a else [0.0, 0.0, false]
		var own: float = cd[0] / cd[1] if cd[1] > 0 else 0.0
		# whichever finishes later is what the player is waiting on
		var show_gcd: bool = cd[2] and gcd > cd[0]
		s.cooldown = 0.0 if show_gcd else own
		s.cd_left = 0.0 if show_gcd or a == "strike" else cd[0]
		s.gcd = gcd / game.stats.global_cooldown if show_gcd else 0.0
		var ab = DB.abilities.get(a) if a else null
		var tint := Color.WHITE
		var overlay := Color(0, 0, 0, 0)
		if ab != null:
			if not game.resources.can_afford(ab) or Spells.missing_gear(game, ab) != "":
				tint = Color(0.42, 0.45, 0.62)
			if tgt != null and tgt.alive and ab.get("target") == "enemy":
				var reach: float = (game.stats.ranged_reach if ab.get("ranged") else ab.get("range", 0.0)) + tgt.radius * 0.6
				if U.hyp(tgt.position.x - player.position.x, tgt.position.z - player.position.z) > reach:
					tint = Color(0.9, 0.45, 0.35)
					overlay = Color(200 / 255.0, 20 / 255.0, 10 / 255.0, 0.28)
		s.icon_tint = tint
		s.overlay = overlay
		s.glow = Color(140 / 255.0, 190 / 255.0, 1, 0.55) if a == "brace" and player.is_braced else Color(0, 0, 0, 0)
		s.border = Color("9cc4ff") if a == "brace" and player.is_braced else Color("2a2218") if cd[0] > 0 or show_gcd else UI.BORDER_DIM
		# redraw only when something shown changed (sweeps move in 1/90 turns)
		var sig := [ceili(s.cd_left), snappedf(s.cooldown, 0.011), snappedf(s.gcd, 0.011), tint, overlay, s.glow, s.border, s.count, s.dim]
		if s.get_meta("sig", []) != sig:
			s.set_meta("sig", sig)
			s.queue_redraw()


## The cast bar, buffs under the health bar, and the swing timers.
func _refresh_spells() -> void:
	var player = game.player
	var k = game.cooking.crafting
	var e = player.eating
	var c = null
	if player.casting != null:
		c = {"t": player.casting.t, "total": player.casting.total, "name": DB.spells[player.casting.id].name}
	elif k != null:
		var rc: Dictionary = DB.recipes[k.id]
		c = {"t": k.t, "total": k.total, "name": "%s %s%s" % [Cooking.craft_of(rc.skill).get("window", "Making"), Items.get_def(rc.output.item).name, " (%d)" % k.left if k.left > 1 else ""]}
	elif e != null:
		c = {"t": e.total - e.left, "total": e.total, "name": "Eating %s" % Items.get_def(e.id).name}
	elif game.fishing.bar != null:
		c = game.fishing.bar.duplicate()
		c.name = "Fishing"
	elif game.loot.gather_bar != null:
		c = game.loot.gather_bar
	elif game.mining.bar != null:
		c = game.mining.bar
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
	for extra in [game.boons.aura, game.law.aura, game.afterlife.wound_aura]:
		if extra != null:
			list.append(extra)
	_auras(buffs, list)
	_player_plate(list)
	_auras(target_auras, game.spells.dots_on(shown_target) if shown_target != null else [], true)


## buffs and debuffs (.aura): an icon with its time left under it
func _auras(box_: HBoxContainer, list: Array, debuff := false, px := 24) -> void:
	box_.visible = not list.is_empty()
	box_.set_meta("list", list) # the hover tip reads the live entry
	var key := ",".join(list.map(func(a): return str(a.id)))
	if box_.get_meta("key", "") != key:
		box_.set_meta("key", key)
		UI.clear(box_)
		for idx in list.size():
			var a: Dictionary = list[idx]
			var p := Panel.new()
			p.custom_minimum_size = Vector2(px, px)
			p.add_theme_stylebox_override("panel", UI.box(Color("0b0908"), Color("8a3a2a") if debuff else UI.BORDER_DIM, 0))
			box_.add_child(p)
			var img := TextureRect.new()
			img.texture = icons.aura(a)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.set_anchors_preset(Control.PRESET_FULL_RECT)
			img.offset_left = 1
			img.offset_top = 1
			img.offset_right = -1
			img.offset_bottom = -1
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(img)
			var t := UI.label(p, "", 10 if px >= 24 else 9, Color("f0e0c0"), 3)
			t.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			t.offset_top = -12
			t.offset_bottom = 2
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			items.tip_at_cursor(p, func():
				var now: Array = box_.get_meta("list", [])
				return aura_tip(now[idx], debuff) if idx < now.size() else "")
	# (an aura that lasts until something ends it, such as Shadow, shows no time)
	var i := 0
	for c in box_.get_children():
		if c.is_queued_for_deletion() or i >= list.size():
			continue
		var left = list[i].get("left", INF)
		c.get_child(1).text = "" if left == null or is_inf(left) else ("%dm" % ceili(left / 60.0) if left > 60 else str(ceili(left)))
		i += 1


## your buffs on your own nameplate, over the name label
func _player_plate(list: Array) -> void:
	var cam: Camera3D = game.camera
	var at: Vector3 = game.player.position + Vector3(0, 2.6, 0)
	var on: bool = not list.is_empty() and not game.player.dead and not cam.is_position_behind(at)
	player_auras.visible = on
	if not on:
		return
	_auras(player_auras, list, false, 18)
	player_auras.size = player_auras.get_combined_minimum_size()
	player_auras.position = (cam.unproject_position(at) - Vector2(player_auras.size.x / 2, player_auras.size.y)).round()


## a buff or debuff's tooltip: name, what it does, time left
func aura_tip(a: Dictionary, debuff: bool) -> String:
	var ab: Dictionary = DB.abilities.get(a.id, {})
	var nm: String = a.get("name", ab.get("name", str(a.id)))
	var text: String = a.get("text", ab.get("desc", ""))
	var out := "[color=%s][b]%s[/b][/color]" % ["#ff8a6a" if debuff else "#a8e08c", UI.esc(nm)]
	if text != "":
		out += "\n" + UI.esc(text)
	var left = a.get("left", INF)
	if left != null and not is_inf(left):
		out += "\n[color=#9a8f78][font_size=12]%s remaining[/font_size][/color]" % ("%dm" % ceili(left / 60.0) if left > 60 else "%ds" % ceili(left))
	return out


## The standard MMO layout, every piece anchored to a screen edge with the
## same margin: unit frames top left, minimap and quests top right, the
## log bottom left, the spell bar bottom centre with the experience bar on
## it and the cast bars above, money, bags and menus bottom right.
func layout() -> void:
	var vp := root.get_viewport_rect().size
	var m := EDGE
	char_panel.size = char_panel.get_combined_minimum_size()
	target.size = target.get_combined_minimum_size()
	minimap.position = Vector2(vp.x - m - Minimap.SIZE, m)
	bottom.size = bottom.get_combined_minimum_size()
	bottom.position = Vector2(roundf((vp.x - bottom.size.x) / 2), vp.y - m - bottom.size.y)
	# the tray stands as tall as the spell bar and level with it
	dock.custom_minimum_size.y = action_bar.get_combined_minimum_size().y
	dock.size = dock.get_combined_minimum_size()
	dock.position = Vector2(vp.x - m - dock.size.x, vp.y - m - dock.size.y)
	# on a narrow screen the bar moves left rather than under the dock
	if bottom.position.x + bottom.size.x > dock.position.x - m:
		bottom.position.x = maxf(m, dock.position.x - m - bottom.size.x)
	# your frame and your target's sit over the spell bar either side of the
	# middle, as WoW addon layouts do, with the cast and swing bars between
	# them; the tops line up and stay put as bars and auras come and go
	var cx := roundf(bottom.position.x + bottom.size.x / 2)
	var top := bottom.position.y - m - UNIT_H
	char_panel.position = Vector2(cx - UNIT_GAP - char_panel.size.x, top)
	target.position = Vector2(cx + UNIT_GAP, top)
	# the log fills the corner beside them; with no room there it sits above
	var room := minf(bottom.position.x, char_panel.position.x) - 2 * m
	var w := clampf(room, 220, 420)
	if not is_equal_approx(log_box.custom_minimum_size.x, w):
		log_box.custom_minimum_size.x = w
		for l in log_box.get_children():
			(l as Control).custom_minimum_size.x = w
	log_box.size = log_box.get_combined_minimum_size()
	var log_foot := vp.y - m if room >= 220 else bottom.position.y - m
	log_box.position = Vector2(m, log_foot - log_box.size.y)
	log_shade.visible = log_box.get_child_count() > 0 and log_box.is_visible_in_tree()
	log_shade.position = log_box.position - Vector2(m, 6)
	log_shade.size = log_box.size + Vector2(m + 60, 12)
	for b in [[cast, 42], [swing, 22], [swing_off, 8]]:
		var r: Control = b[0].root
		r.position = Vector2(roundf(bottom.position.x + (bottom.size.x - r.size.x) / 2), bottom.position.y - b[1] - r.size.y)
	prompt.size = prompt.get_combined_minimum_size()
	# just over the unit frames, clear of the cast, gather and skinning bars
	prompt.position = Vector2(roundf((vp.x - prompt.size.x) / 2), roundf(vp.y * 0.42 - prompt.size.y / 2) if _prompt_big else top - 6 - prompt.size.y)
	for l in [[toast_label, 0.22], [error_label, 0.18]]:
		var c: Control = l[0]
		c.size = c.get_combined_minimum_size()
		c.position = Vector2(roundf((vp.x - c.size.x) / 2), roundf(vp.y * l[1]))
	quick_bind_banner.size = quick_bind_banner.get_combined_minimum_size()
	quick_bind_banner.position = Vector2(roundf((vp.x - quick_bind_banner.size.x) / 2), roundf(vp.y * 0.18))
	levelup.size = levelup.get_combined_minimum_size()
	levelup.position = Vector2(roundf((vp.x - levelup.size.x) / 2), roundf(vp.y * 0.16))
	sign_card.size = sign_card.get_combined_minimum_size()
	sign_card.position = Vector2(vp.x - 340, roundf(vp.y / 2 - 80))
	quests.layout()
	items.layout() # windows settle to their size over a frame or two
	mute.size = mute.get_combined_minimum_size()
	mute.position = Vector2(vp.x - m - mute.size.x, dock.position.y - 6 - mute.size.y)
	for win in [death, document]:
		win.size = win.get_combined_minimum_size()
		win.position = ((vp - win.size) / 2).round()


func update(dt := 0.0) -> void:
	numbers.update(dt)
	# fading messages
	toast_left = maxf(0, toast_left - dt)
	toast_label.modulate.a = minf(1, toast_left / 0.4)
	zone_left = maxf(0, zone_left - dt)
	zone_banner.modulate.a = minf(1, zone_left / 0.8)
	error_left = maxf(0, error_left - dt)
	error_label.modulate.a = minf(1, error_left / 0.6)
	vignette_t = maxf(0, vignette_t - dt)
	hurt.modulate.a = vignette_t / 0.45
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
	var text: String = c.prompt if c != null and not modal else ""
	var key: String = "A" if pad_mode else (game.keys.label("interact") if game.keys.label("interact") != "" else "Space")
	var big: bool = c != null and c.get("big", false)
	if _prompt_shown != text + key or _prompt_big != big:
		_prompt_shown = text + key
		_prompt_big = big
		prompt_key.text = key
		prompt_text.text = text
		prompt_key.add_theme_font_size_override("font_size", 26 if big else 12)
		prompt_text.add_theme_font_size_override("font_size", 30 if big else 14)
		prompt.size = Vector2.ZERO
	prompt.visible = text != ""

	_update_target()
	_update_enemy_bars()
	labels.update(dt)
	quests.update_marks()
	items.update(dt)
	layout()


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
	var who = friend if friend != null else shown
	if who != null and not is_same(who, portrait_of):
		portrait_of = who
		var model = friend.def.get("model") if friend != null else shown.cfg.get("model")
		target_img.texture = icons.portrait(model) if model else null
	if who == null:
		return
	var elite: bool = shown != null and shown.cfg.get("elite", false)
	var ring: StyleBoxFlat = target_ring.get_theme_stylebox("panel")
	ring.border_color = Color("6a9a4a") if friend != null else Color("e0a040") if elite else Color("b08a4a")
	if friend != null:
		target_name.text = friend.name
		target_name.add_theme_color_override("font_color", Color("a8e08c"))
		target_badge.text = U.n(friend.def.get("level", 1))
		target_label.text = friend.def.get("title", "")
		target_kind.text = ""
		target_label.add_theme_color_override("font_color", UI.TEXT_DIM)
		target_hp.root.visible = false
		target_mp.root.visible = false
		target_stagger.root.visible = false
		return
	var cfg: Dictionary = shown.cfg
	target_name.text = cfg.name
	target_name.add_theme_color_override("font_color", Color("ff9c60") if elite else Color("f0d050") if shown.passive else Color("e8c8a0"))
	target_badge.text = U.n(cfg.get("level", 1))
	var kind := combat_kind(cfg)
	target_kind.text = KIND_GLYPH[kind][0]
	target_kind.add_theme_color_override("font_color", KIND_GLYPH[kind][1])
	target_kind.set_meta("tip", "[b]%s[/b]\nLevel %s · %s" % [kind.capitalize(), U.n(cfg.get("level", 1)), KIND_GLYPH[kind][2]])
	var attacking: bool = t != null and tg.attacking
	target_label.text = ("Attacking" if tg.target_in_reach or tg.target_in_shot else "Out of reach") if attacking else "Elite" if elite else ""
	target_label.add_theme_color_override("font_color", Color("ff8a60") if attacking else UI.TEXT_DIM)
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


const KIND_GLYPH := {
	"melee": ["⚔", Color("e0b070"), "fights up close"],
	"ranged": ["➶", Color("a8d070"), "shoots from range"],
	"magic": ["✦", Color("a890f0"), "casts spells"],
}


## melee, ranged or magic: an enemy's `combat` field, else read from its kit
static func combat_kind(cfg: Dictionary) -> String:
	if cfg.get("combat"):
		return cfg.combat
	var r = cfg.get("ranged")
	if r is Dictionary:
		return "magic" if r.get("school") or r.get("mana") else "ranged"
	return "magic" if cfg.get("mana", 0) > 0 else "melee"


## enemy health bars (.ebar), shown when engaged, damaged or targeted
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
		var on: bool = not cam.is_position_behind(pos) and s.x > -50 and s.x < vp.x + 50 and s.y > -50 and s.y < vp.y + 50
		bar.root.visible = on
		if not on:
			continue
		var elite: bool = e.cfg.get("elite", false)
		var targeted: bool = e == t
		var w := 96.0 if targeted else 130.0 if elite else 70.0
		var h := 12.0 if targeted else 8.0 if elite else 6.0
		bar.name.visible = elite or targeted or nemesis
		bar.name.text = ("☠ " if nemesis else "") + e.cfg.name
		bar.name.add_theme_color_override("font_color", Color("ff6a50") if nemesis else Color("f0d050") if e.passive else Color("ffb08a") if targeted else Color("d8c7a0"))
		bar.track.custom_minimum_size = Vector2(w, h)
		var st: StyleBoxFlat = bar.track.get_theme_stylebox("panel")
		var winding: bool = e.casting != null
		st.border_color = Color("ff6a40") if targeted else Color("d0a050") if winding else UI.BORDER if elite else UI.BORDER_DIM
		bar.fill.anchor_right = clampf(e.health / e.max_health, 0, 1)
		bar.hp.text = "%d / %d" % [ceili(e.health), e.max_health] if targeted else ""
		# FFXIV-style cast bar under the name while a telegraphed attack winds up
		var c = e.casting
		bar.cast.visible = c != null
		if c != null:
			var tl = c.get("telegraph")
			bar.cast_fill.anchor_right = minf(1, tl.t / tl.duration) if tl != null else 0.0
			bar.cast_name.text = c.get("label", "")
		_auras(bar.auras, game.spells.dots_on(e), true, 18)
		bar.root.size = bar.root.get_combined_minimum_size()
		bar.root.position = (s - Vector2(bar.root.size.x / 2, bar.root.size.y)).round()
	for id in enemy_bars.keys():
		if not seen.has(id):
			enemy_bars[id].root.queue_free()
			enemy_bars.erase(id)


func _enemy_bar(_e) -> Dictionary:
	var v := UI.vbox(bars_layer, 1)
	var n := UI.label(v, "", 11, Color("d8c7a0"), 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", UI.box(Color("0b0908"), UI.BORDER_DIM, 0, 1))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(track)
	var fill := ColorRect.new()
	fill.color = Color("8e2a20")
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	var hp_text := UI.label(track, "", 10, Color("f4ead0"), 3)
	hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cast_box := UI.vbox(v, 0)
	var ct := Panel.new()
	ct.custom_minimum_size = Vector2(96, 9)
	ct.add_theme_stylebox_override("panel", UI.box(Color("0b0908"), UI.BORDER, 0, 1))
	ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ct.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cast_box.add_child(ct)
	var cf := TextureRect.new()
	cf.texture = gradient(Color("e8b060"), Color("a86a20"))
	cf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cf.stretch_mode = TextureRect.STRETCH_SCALE
	cf.set_anchors_preset(Control.PRESET_FULL_RECT)
	cf.offset_left = 1
	cf.offset_top = 1
	cf.offset_bottom = -1
	cf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ct.add_child(cf)
	var cn := UI.label(cast_box, "", 11, Color("f0c890"), 4)
	cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var auras := UI.hbox(v, 2)
	auras.alignment = BoxContainer.ALIGNMENT_CENTER
	return {"root": v, "name": n, "track": track, "fill": fill, "hp": hp_text, "cast": cast_box, "cast_fill": cf, "cast_name": cn, "auras": auras}
