class_name ItemUI
extends Control
## Bags, the character panel, the spellbook, Professions, Settings, Talents,
## Cooking, the shop, the tooltip, and the bag slots and spell bar on the
## bottom bar (src/ui/itemUI.js). None of these pause the game.
##
## Each bag opens and closes on its own (click its bag slot, or its ×); B
## opens or closes them all, as in WoW. Spells are dragged between bar slots,
## off the bar to remove them, and from the spellbook back onto it.
##
## Mouse: drag an item between slots to move, swap, equip or unequip it; drag
## it out over the world to drop it on the ground; right-click to use/equip.
## Gamepad: a highlight moves between slots; A picks up and puts down,
## X uses or equips, Y drops on the ground, B cancels or closes.
##
## Every action is a request to the Inventory, which decides what is allowed.

const STAT_LABEL := {"stamina": "Stamina", "strength": "Strength", "agility": "Agility", "intellect": "Intellect", "armour": "armour", "resistance": "resistance", "block": "% block chance", "haste": "% haste", "accuracy": "% accuracy", "spellPower": "spell power"}
const KIND_LABEL := {"weapon": "Weapon", "armor": "Armour", "shield": "Shield", "bag": "Bag", "ammo": "Arrows", "consumable": "Consumable", "material": "Material", "junk": "Junk", "document": "Document", "jewellery": "Jewellery", "torch": "Torch", "tool": "Tool", "key": "Key", "gem": "Gem"}
const RECIPE_COLOUR := {"orange": Color("ff8040"), "yellow": Color("ffe040"), "green": Color("40c040"), "grey": Color("909090"), "red": Color("c03030")}
const REP_COLOUR := {"hostile": Color("8a3a2a"), "neutral": Color("8a7a3a")}

var game
var hud
var icons: Icons
var open_bags := {} ## socket indices whose bag window is open
var open := {"character": false, "spellbook": false, "skills": false, "settings": false, "talents": false, "cooking": false}
var drag = null ## { from, at, moved }
var focus = null ## gamepad highlight: a location string
var carry = null ## gamepad: location of the item being carried
var shop_opened_bags := false
var char_tab := "main"
var slots := {} ## loc -> ISlot for everything on screen (the bar's are added by the HUD)
var bar_slots := {} ## 'a:<n>' -> ISlot, made once by the HUD
var tip_from = null ## 'ui' | 'world' | null
var tip_cursor := false ## this tip follows the mouse (buffs, debuffs, combat type)
var tip_key = null
var tip_text := ""
var preview: CharPreview

var bags: Control
var character: Dictionary
var spellbook: Dictionary
var skills_win: Dictionary
var settings_win: Dictionary
var talents: Dictionary
var cooking: Dictionary
var craft_skill := "cooking" ## whose recipes the crafting window shows
var shop: Dictionary
var tooltip: HBoxContainer
var ghost: TextureRect
var sockets: HBoxContainer ## the bag slots in the bottom-right dock (the HUD makes the box)
var _cook_clock := 0.0
var _cook_last := ""


func _init(g, h) -> void:
	game = g
	hud = h
	icons = h.icons
	name = "ItemUI"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	var ev = game.events
	for e in ["inventoryChanged", "equipmentChanged", "levelUp", "barChanged", "skillsChanged", "reputationChanged", "titlesChanged"]:
		ev.on(e, func(_e): render())
	for e in ["craftEnd", "craftStart", "campPitched"]:
		ev.on(e, func(_e):
			if open.cooking:
				render())
	# a merchant opens your bags with it (and closes the ones it opened)
	ev.on("merchantOpened", func(_e):
		shop_opened_bags = not bags_open
		if shop_opened_bags:
			for i in _sockets():
				open_bags[i] = true
		focus = null
		_after_change("shop"))
	ev.on("merchantClosed", func(_e):
		if shop_opened_bags:
			open_bags.clear()
		shop_opened_bags = false
		_after_change(null))


# ------------------------------------------------------------------ building
func _build() -> void:
	bags = Control.new()
	bags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bags)
	character = UI.window(self, "Warden", 0, func(): close("character"))
	character.title.size_flags_horizontal = Control.SIZE_FILL
	character.level = UI.label(null, "", 14, UI.TEXT_DIM)
	character.level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character.level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	character.head.add_child(character.level)
	character.head.move_child(character.level, 1)
	# the tabs share one page area, sized by the equipment page, so the
	# window never changes size or moves as you switch: the longer pages scroll
	character.pages = MarginContainer.new()
	character.body.add_child(character.pages)
	character.main = UI.vbox(character.pages, 6)
	character.rep = _char_page(character.pages)
	character.titles = _char_page(character.pages)
	var tabs := UI.hbox(character.body, 4)
	character.tabs = {}
	for t in [["main", "Equipment"], ["titles", "Titles"], ["rep", "Reputation"]]:
		var id: String = t[0]
		# a tab only swaps which page shows: nothing is rebuilt, so no flash
		var b := UI.button(tabs, t[1], func():
			char_tab = id
			_show_char_tab())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		character.tabs[id] = b
	preview = CharPreview.new(game)
	spellbook = UI.window(self, "Spells", 500, func(): close("spellbook"))
	skills_win = UI.window(self, "Professions", 420, func(): close("skills"))
	# both scroll once they outgrow the screen, with a line of help under
	for w in [spellbook, skills_win]:
		w.title.size_flags_horizontal = Control.SIZE_FILL
		w.sub = UI.label(null, "", 13, UI.TEXT_DIM)
		w.sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w.head.add_child(w.sub)
		w.head.move_child(w.sub, 1)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		w.body.add_child(sc)
		w.scroll = sc
		w.inner = UI.vbox(sc, 6)
		w.inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w.foot = UI.hint(w.body)
	settings_win = UI.window(self, "Settings", 320, func(): close("settings"))
	talents = UI.window(self, "Talents", 470, func(): close("talents"))
	talents.sub = UI.label(null, "", 13, UI.TEXT_DIM)
	talents.head.add_child(talents.sub)
	talents.head.move_child(talents.sub, 1)
	var tsc := ScrollContainer.new()
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tsc.custom_minimum_size = Vector2(0, 420)
	talents.body.add_child(tsc)
	talents.inner = UI.vbox(tsc, 6)
	talents.inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cooking = UI.window(self, "Cooking", 380, func(): close("cooking"))
	shop = UI.window(self, "", 330, func(): game.merchant.close())
	shop.sub = UI.label(null, "", 13, UI.TEXT_DIM)
	shop.head.add_child(shop.sub)
	shop.head.move_child(shop.sub, 1)
	_build_settings()
	for w in [character, spellbook, skills_win, settings_win, talents, cooking, shop]:
		w.panel.visible = false
	tooltip = HBoxContainer.new()
	tooltip.add_theme_constant_override("separation", 6)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip.z_index = 20
	add_child(tooltip)
	ghost = TextureRect.new()
	ghost.size = Vector2(40, 40)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.modulate.a = 0.85
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.visible = false
	ghost.z_index = 30
	add_child(ghost)


## Settings: one checkbox (or slider) each, then the key bindings, made once
func _build_settings() -> void:
	var body: VBoxContainer = settings_win.body
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	settings_win.scroll = scroll
	var v := UI.vbox(scroll, 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_win.inner = v
	settings_win.inputs = {}
	var group := ""
	for s in Settings.SETTINGS:
		if s.get("group") and s.group != group:
			group = s.group
			UI.label(v, group, 13, UI.GOLD)
		var id: String = s.id
		if s.has("min"):
			var row := UI.hbox(v, 8)
			var l := UI.label(row, s.label, 14)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var sl := HSlider.new()
			sl.min_value = s.min
			sl.max_value = s.max
			sl.step = 1
			sl.custom_minimum_size = Vector2(120, 16)
			sl.focus_mode = Control.FOCUS_NONE
			row.add_child(sl)
			var val := UI.label(row, "", 14, UI.TEXT_DIM)
			val.custom_minimum_size = Vector2(38, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# sliders as they move, so the sound follows the hand
			sl.value_changed.connect(func(x):
				game.settings.set_value(id, int(x))
				val.text = "%d%%" % int(x))
			settings_win.inputs[id] = [sl, val]
		else:
			var cb := CheckBox.new()
			cb.text = s.label
			cb.focus_mode = Control.FOCUS_NONE
			cb.add_theme_font_size_override("font_size", 14)
			cb.add_theme_color_override("font_color", UI.TEXT)
			cb.add_theme_color_override("font_hover_color", Color("f2e6c6"))
			cb.add_theme_color_override("font_pressed_color", UI.TEXT)
			cb.toggled.connect(func(on): game.settings.set_value(id, on))
			v.add_child(cb)
			settings_win.inputs[id] = [cb]
	UI.label(v, "Key bindings", 13, UI.GOLD)
	var btns := UI.hbox(v, 6)
	hud.keybind_ui.quick_button = UI.button(btns, "Quick bind", func(): hud.keybind_ui.set_quick(not hud.keybind_ui.quick))
	UI.button(btns, "Reset to defaults", func(): game.keys.reset_all())
	hud.keybind_ui.list = UI.vbox(v, 1)
	var foot := UI.hbox(v, 6)
	UI.button(foot, "Save the game", func(): game.manual_save())
	UI.button(foot, "Logout", func(): game.log_out())


# ------------------------------------------------------------------ state
var any_open: bool:
	get:
		return not open_bags.is_empty() or open.character or open.spellbook or open.skills or open.settings or open.talents or open.cooking or game.merchant.current != null

var bags_open: bool:
	get:
		return not open_bags.is_empty()


func _sockets() -> Array:
	var out := []
	var s: Array = game.inventory.sockets
	for i in s.size():
		if s[i]:
			out.append(i)
	return out


## shop slots: m:<item> buys, y:<n> buys back
func _shop_click(loc: String) -> bool:
	var m = game.merchant
	if loc.begins_with("m:"):
		m.buy(loc.substr(2))
	elif loc.begins_with("y:"):
		m.buy_back(int(loc.substr(2)))
	else:
		return false
	render()
	return true


## 'bags' toggles every bag at once (WoW's B); the others toggle one window.
func toggle(which: String) -> void:
	if which == "bags":
		if bags_open:
			open_bags.clear()
		else:
			for i in _sockets():
				open_bags[i] = true
		_after_change("bags")
		return
	open[which] = not open[which]
	_after_change(which)


func show_window(which: String) -> void:
	# one crafting window, for whichever skill's recipes (Cooking, Smelting,
	# Alchemy: "craft:<skill>")
	if which == "cooking" or which == "smelting" or which.begins_with("craft:"):
		craft_skill = "mining" if which == "smelting" else which.substr(6) if which.begins_with("craft:") else "cooking"
		which = "cooking"
		_cook_last = ""
	if which == "bags":
		for i in _sockets():
			open_bags[i] = true
	else:
		open[which] = true
	_after_change(which)


func toggle_bag(i: int) -> void:
	if i >= game.inventory.sockets.size() or not game.inventory.sockets[i]:
		return
	if open_bags.has(i):
		open_bags.erase(i)
	else:
		open_bags[i] = true
	_after_change("bags")


func close(which: String) -> void:
	if which == "bags":
		open_bags.clear()
	else:
		open[which] = false
	_after_change(which)


func close_all() -> bool:
	var was := any_open
	open_bags.clear()
	for k in open:
		open[k] = false
	shop_opened_bags = false
	game.merchant.close()
	_after_change(null)
	return was


func _after_change(which) -> void:
	if not any_open:
		carry = null
		focus = null
		_hide_tip()
	render()
	if any_open and (focus == null or not _visible_locs().has(focus)):
		focus = _default_focus(which)
	_paint_focus()


# ------------------------------------------------------------------ slots
func _slot(parent: Node, loc: String, stack, px := 42, ph := "") -> ISlot:
	var s := ISlot.new(loc, px)
	s.show_stack(stack, icons, ph)
	s.carried = carry == loc
	s.on_input = slot_input
	s.on_hover = slot_hover
	if parent:
		parent.add_child(s)
	slots[loc] = s
	return s


func _spell_slot(parent: Node, id: String, px := 42) -> ISlot:
	var s := ISlot.new("k:" + id, px)
	s.icon = icons.abilities.get(id)
	s.border = ISlot.EMPTY_BORDER
	s.carried = carry == "k:" + id
	s.on_input = slot_input
	s.on_hover = slot_hover
	parent.add_child(s)
	slots["k:" + id] = s
	return s


func _slot_node(loc: String) -> ISlot:
	var s = bar_slots.get(loc) if loc.begins_with("a:") else slots.get(loc)
	return s if s != null and is_instance_valid(s) and s.is_visible_in_tree() else null


func slot_input(s: ISlot, e: InputEventMouseButton) -> void:
	if not e.pressed:
		return
	if e.button_index == MOUSE_BUTTON_LEFT:
		_down(s.loc, e.global_position)
	elif e.button_index == MOUSE_BUTTON_RIGHT:
		_context(s.loc)


func slot_hover(s: ISlot, on: bool) -> void:
	if s.loc.begins_with("a:"):
		hud.keybind_ui.hovered = int(s.loc.substr(2)) if on else null
	if drag != null:
		return
	if on:
		tip_from = "ui"
		tip_cursor = false
		_tooltip(s.loc)
	elif tip_from == "ui":
		_hide_tip()


## right-click: use, equip, sell, open a bag
func _context(loc: String) -> void:
	if loc.begins_with("a:") or loc.begins_with("k:"):
		return
	if _shop_click(loc):
		return
	# with a shop open, right-clicking something you carry sells it (WoW)
	if game.merchant.current != null and (loc.begins_with("b:") or loc.begins_with("e:")):
		game.merchant.sell(loc)
	elif loc.begins_with("s:"):
		toggle_bag(int(loc.substr(2)))
	elif loc != "":
		game.inventory.use(loc)


## a plain tooltip for any button, stat or row: shown in the corner, as items are
func tip_on(c: Control, text: String, head := "") -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP if c.mouse_filter == Control.MOUSE_FILTER_IGNORE else c.mouse_filter
	c.mouse_entered.connect(func():
		if drag != null or text == "":
			return
		tip_from = "ui"
		tip_cursor = false
		_set_tip([(_name_line(head, "") if head != "" else "") + _esc(text)], [], 0))
	c.mouse_exited.connect(func():
		if tip_from == "ui":
			_hide_tip())


## a tooltip shown at the cursor rather than in the corner: buffs and debuffs
## on frames and nameplates. `text` is a Callable so it reads live values.
func tip_at_cursor(c: Control, text: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_entered.connect(func(): cursor_tip(text.call()))
	c.mouse_exited.connect(cursor_tip_off)


func cursor_tip(t: String) -> void:
	if drag != null or t == "":
		return
	tip_from = "ui"
	tip_cursor = true
	_set_tip([t], [], 0)


func cursor_tip_off() -> void:
	if tip_from == "ui":
		_hide_tip()


# ------------------------------------------------------------------ render
func _icon_for(id) -> Texture2D:
	return icons.item(id)


func render() -> void:
	if not is_inside_tree():
		return
	slots.clear()
	var inv = game.inventory
	_render_sockets(inv)
	_render_bags(inv)
	_render_character(inv)
	_render_shop(inv)
	_render_talents()
	_render_cooking()
	_render_settings()
	_render_skills()
	_render_spellbook()
	# a carried bar slot is shown faded
	for loc in bar_slots:
		bar_slots[loc].carried = carry == loc
		bar_slots[loc].queue_redraw()
	_paint_focus()
	layout()


## bag sockets on the bottom bar (backpack last, as in WoW: right-most)
func _render_sockets(inv) -> void:
	if sockets == null:
		return
	UI.clear(sockets)
	# a bag whose socket was emptied closes with it
	for i in open_bags.keys():
		if i >= inv.sockets.size() or not inv.sockets[i]:
			open_bags.erase(i)
	# the tool pack's own slot comes first, left of the bags (empty until earned)
	for i in range(Items.TOOL_SOCKET, 0, -1):
		var s = inv.sockets[i] if i < inv.sockets.size() else null
		var slot := _slot(sockets, "s:%d" % i, {"id": s.id, "count": 1} if s else null, 40, "⚒" if i == Items.TOOL_SOCKET else "")
		slot.ghost = Icons.art("ui", "socket_tool" if i == Items.TOOL_SOCKET else "socket_bag")
		if i == Items.TOOL_SOCKET:
			slot.placeholder_size = 18
			slot.dim = 1.0 if s else 0.6
			if not s:
				tip_on(slot, "Tool pack slot: earned from Mara Venn's first errand")
		# a quiver shows how many arrows it holds
		# (the tool pack's holds is a list, and Array == String is a script error)
		if s and str(Items.get_def(s.id).get("holds")) == "ammo":
			var n: int = inv.arrows_in(i)
			slot.count = str(n)
			slot.count_centre = true
			slot.count_size = 13
			slot.count_colour = Color("f0e4c8") if n else Color("ff6a50")
		slot.lit = open_bags.has(i)
	# the free space in all bags shows on the backpack, as in WoW
	var free: int = inv.free_slots()
	var bp := _slot(sockets, "s:0", null, 40)
	bp.border = UI.BORDER
	bp.lit = open_bags.has(0)
	bp.key = "Start" if hud.pad_mode else game.keys.label("bags").split(" / ")[0]
	bp.count = str(free)
	bp.count_colour = Color("ff6a50") if free == 0 else Color("f0e4c8")
	bp.painter = Callable(self, "_paint_backpack")
	tip_on(bp, "Backpack (B): %d free slot%s" % [free, "" if free == 1 else "s"])


## the backpack's little picture (style.css .bp-icon)
func _paint_backpack(s: ISlot) -> void:
	var r := Rect2(8, 7, s.size.x - 16, s.size.y - 16)
	s.draw_rect(Rect2(r.position.x + r.size.x * 0.3, r.position.y - 5, r.size.x * 0.4, 7), Color("5a3e1e"), false, 2)
	s.draw_rect(r, Color("6a4a26"))
	s.draw_rect(Rect2(r.position.x, r.end.y - 5, r.size.x, 5), Color("3a2410"))
	s.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.4), Color("8a6436"))
	s.draw_rect(r, Color.BLACK, false, 1)


## bags window: one frame per bag, stacked up from the bag slots
func _render_bags(inv) -> void:
	UI.clear(bags)
	bags.visible = bags_open
	if not bags_open:
		return
	for i in inv.sockets.size():
		var s = inv.sockets[i]
		if not s or not open_bags.has(i):
			continue
		var frame := UI.panel(bags, 14, UI.WINDOW)
		var v := UI.vbox(frame, 6)
		var head := UI.hbox(v, 8)
		var t := UI.label(head, "Backpack" if i == 0 else Items.get_def(s.id).name, 14, UI.GOLD)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var used := 0
		for st in s.slots:
			if st:
				used += 1
		UI.label(head, "%d/%d" % [used, s.slots.size()], 13, UI.TEXT_DIM)
		var bag: int = i
		UI.square_button(head, "×", func(): toggle_bag(bag))
		UI.rule(v)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		v.add_child(grid)
		for j in s.slots.size():
			_slot(grid, "b:%d:%d" % [i, j], s.slots[j])
		if i == 0:
			var foot := UI.rich(v, 13)
			foot.fit_content = true
			foot.autowrap_mode = TextServer.AUTOWRAP_OFF
			foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			UI.set_rich(foot, "[right]%s[/right]" % UI.money(inv.coins))


func _render_character(inv) -> void:
	var w := character
	w.panel.visible = open.character
	if not open.character:
		return
	var who: String = game.character.name if game.character else "Warden"
	w.title.text = game.titles.full_name(who)
	UI.clear(w.rep)
	UI.clear(w.titles)
	# the paper doll lives across renders; only the slots and numbers change
	if preview.get_parent():
		preview.get_parent().remove_child(preview)
	UI.clear(w.main)
	# every page is built, the hidden ones too, so switching tabs is instant
	_render_paper_doll(inv, w.main)
	_render_rep(w.rep)
	_render_titles(w.titles)
	_show_char_tab()


## a tab page that scrolls inside the shared page area
func _char_page(pages: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(sc)
	var v := UI.vbox(sc, 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _show_char_tab() -> void:
	var w := character
	for id in w.tabs:
		var b: Button = w.tabs[id]
		b.add_theme_color_override("font_color", UI.GOLD if id == char_tab else UI.TEXT_DIM)
		b.add_theme_stylebox_override("normal", UI.box(Color(20 / 255.0, 16 / 255.0, 12 / 255.0, 0.8), UI.GOLD if id == char_tab else Color(201 / 255.0, 162 / 255.0, 83 / 255.0, 0.3), 0, 1, Vector4(4, 4, 4, 4)))
	w.main.visible = char_tab == "main"
	w.rep.get_parent().visible = char_tab == "rep"
	w.titles.get_parent().visible = char_tab == "titles"


const SLOT_PX := 52 ## the paper doll's gear slots
const FIG_W := 190 ## the figure's box, about 3/5 of its old width
const STATS_W := 200 ## the scrolling numbers beside the paper doll
var _stats_scroll := 0


func _equip_col(parent: Node, inv, where: String, px := SLOT_PX) -> void:
	for s in DB.EQUIP_SLOTS:
		if s.col == where:
			var sl := _slot(parent, "e:" + s.id, inv.equipment.get(s.id), px, s.label)
			sl.placeholder_size = 9
			# both rings and both trinkets share one outline
			sl.ghost = Icons.art("slots", "slot_" + s.id.rstrip("12"))


func _render_paper_doll(inv, main: VBoxContainer) -> void:
	# the figure and gear on the left, the numbers in their own scroll on
	# the right, so the window stays short enough for the screen (Dan, 2026-10-28)
	var split := UI.hbox(main, 14)
	var gear := UI.vbox(split, 6)
	var body := UI.hbox(gear, 4)
	var left := UI.vbox(body, 3)
	_equip_col(left, inv, "left")
	var fig := PanelContainer.new()
	fig.add_theme_stylebox_override("panel", UI.box(Color("120f0b"), Color(107 / 255.0, 85 / 255.0, 50 / 255.0, 0.45), 0))
	fig.custom_minimum_size = Vector2(FIG_W, 5 * SLOT_PX + 4 * 3) # as tall as a column of slots
	body.add_child(fig)
	fig.add_child(preview)
	# rings and trinkets sit on the figure, in a row along its feet
	var jewels := UI.hbox(fig, 4)
	jewels.alignment = BoxContainer.ALIGNMENT_CENTER
	jewels.size_flags_vertical = Control.SIZE_SHRINK_END
	jewels.add_theme_constant_override("separation", 4)
	_equip_col(jewels, inv, "fig", 44)
	var right := UI.vbox(body, 3)
	_equip_col(right, inv, "right")
	var bottom := UI.hbox(gear, 4)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_equip_col(bottom, inv, "bottom")
	# the ammo slot, beside the ranged slot: which arrows Auto Shot uses
	# and how many of them you carry
	var ammo = inv.get_at(Inventory.AMMO_LOC)
	var a := _slot(bottom, Inventory.AMMO_LOC, ammo, SLOT_PX, "Ammo")
	a.placeholder_size = 9
	a.count = str(ammo.count) if ammo else ""
	a.count_size = 13
	a.count_colour = Color("f0e4c8") if ammo and ammo.count else Color("ff6a50")
	# the numbers
	var p = game.player
	var prog = game.progression
	var st = game.stats
	var t: Dictionary = st.totals
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(STATS_W, 0)
	split.add_child(sc)
	# rebuilt on every change, so keep the reader's place
	sc.scroll_vertical = _stats_scroll
	sc.get_v_scroll_bar().value_changed.connect(func(v): _stats_scroll = int(v))
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new() # clear of the scroll bar
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 18)
	sc.add_child(pad)
	pad.add_child(grid)
	var lvl: int = prog.level
	var arch: Dictionary = st.archetype
	var wears: Array = arch.get("armourTypes", []).map(func(k): return DB.armour_types[k].name)
	var conf: Dictionary = DB.CONFIG.stats
	# the level sits by the name, at the top
	character.level.text = "Level %d %s" % [lvl, arch.name]
	# grouped under headings, as most RPGs do (Dan, 2026-10-28)
	var rows := [
		"Character",
		["Trait", arch.trait.name, arch.trait.desc] if arch.get("trait") else null,
		["Health", "%d / %d" % [ceili(p.health), p.max_health], "", "health"],
	]
	# the class's resources, as applicable: mana, then its own bar(s)
	var res = game.resources
	if res and res.max_mana > 0:
		rows.append(["Mana", "%d / %d" % [floori(res.mana), roundi(res.max_mana)], "", "mana"])
	if res:
		for b in res.bars:
			rows.append([b.name, "%d / %d" % [floori(res.amount(b.id)), roundi(b.get("max", 0))], b.get("desc", "")])
	rows += [
		"Attributes",
		["Stamina", U.n(t.stamina), "+%s health per point" % U.n(conf.healthPerStamina), "stamina"],
		["Strength", U.n(t.strength), "Adds to every swing and weapon ability" if st.power_stat == "strength" else "", "strength"],
		["Agility", U.n(t.agility), "+%.2f%% crit chance per point at level %d%s" % [1.0 / st.agility_per_crit, lvl, "; adds to every swing and weapon ability" if st.power_stat == "agility" else ""], "agility"],
		["Intellect", U.n(t.intellect), "Spell power, and mana for casters", "intellect"],
		"Offence",
		["Crit", "%.1f%%" % st.crit_chance, "Critical hits do %s%% damage" % U.n(conf.critMultiplier * 100), "crit"],
		["Haste", "%s%%" % U.n(st.haste), "Shortens the time between swings, ability windups, casts and the global cooldown (swing %.2fs, GCD %.2fs)" % [st.attack_cooldown, st.global_cooldown], "haste"],
		["Damage", "–".join(st.swing_range.map(func(x): return U.n(x))), "Your hit with %s: its own %s damage, plus %s from your %s on every swing" % [inv.weapon.name, "–".join(st.weapon_range.map(func(x): return U.n(x))), U.fixed(st.swing_power, 1), st.power_stat.capitalize()]],
		["Attack speed", "%.2fs" % st.attack_cooldown, "Time between swings: weapon speed %.1f, shortened by haste" % st.weapon_speed],
		["Spell power", U.n(st.spell_power), "Added to your spells: from Intellect, and from a caster's weapon"],
	]
	if st.dual_wielding:
		rows.append(["Off hand", "%s / %.2fs" % ["–".join(st.swing_range_for("off").map(func(x): return U.n(x))), st.attack_cooldown_for("off")], "%s: its own swing timer; off-hand blows do %d%% damage" % [inv.off_weapon.name, roundi(conf.offHandDamage * 100)]])
	rows.append(["DPS", "%.1f" % st.dps, "From auto attack alone, both hands" if st.dual_wielding else "From auto attack alone", "dps"])
	rows.append(["Miss", "%s%%" % U.fixed(Stats.miss_chance(lvl, lvl, st.accuracy), 1), "Chance to miss a foe of your own level: %s%% less for each level below you, %s%% more for each level above. Accuracy from gear (%s%%) takes it down." % [U.n(conf.missPerLevelBelow), U.n(conf.missPerLevelAbove), U.n(st.accuracy)]])
	rows += [
		"Defence",
		["Armour", "%s (−%d%%)" % [U.n(t.armour), roundi(Stats.mitigation(t.armour, lvl))], "Physical damage taken, against any foe."],
		["Block", "%s%%" % U.n(st.block_chance) if st.block_chance else "no shield", "Chance to block a melee blow, which stops %s%% of it: the shield's own block chance plus block chance from gear" % U.n(conf.blockReduction), "block"],
	]
	rows.append("General")
	rows.append(["Wears", ", ".join(wears) + (", shields" if arch.get("shields") else "")])
	rows.append(["Speed", "%s m/s" % U.fixed(DB.CONFIG.player.speed, 1), "Movement speed"])
	for r in rows:
		if r == null:
			continue
		if r is String:
			# a heading over each group of numbers
			if grid.get_child_count() > 0:
				UI.gap(grid, 8)
			var head := UI.label(grid, r.to_upper(), 11, UI.GOLD, 4)
			head.add_theme_font_override("font", UI.bold)
			UI.rule(grid, Color(UI.GOLD, 0.35))
			continue
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UI.label(cell, r[0], 13, UI.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := UI.rich(cell, 13)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		# one total per stat: level, class and gear are already in it (Dan, 2026-10-23)
		UI.set_rich(value, "[right][color=#efe2c0]%s[/color][/right]" % UI.esc(r[1]))
		var v := UI.vbox(null, 1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(cell)
		UI.rule(v, Color(107 / 255.0, 85 / 255.0, 50 / 255.0, 0.2))
		grid.add_child(v)
		if r.size() > 2 and r[2] != "":
			tip_on(v, r[2])
	var hint := UI.hint(main)
	hint.text = "A: pick up / place   X: equip or use   Y: drop   B: back" if hud.pad_mode else "Drag items between your bags and here. Right-click to equip. Drag out of a window to drop."


## a reputation bar with its standing written over it
func _rep_bar(parent: Node, k: float, colour: Color, text: String) -> void:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 14)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_stretch_ratio = 1.3
	track.add_theme_stylebox_override("panel", UI.box(Color("1c1712"), Color.BLACK, 0))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(track)
	var fill := ColorRect.new()
	fill.color = colour
	fill.anchor_bottom = 1
	fill.anchor_right = clampf(k, 0, 1)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	var l := UI.label(track, text, 10, UI.TEXT, 3)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _rep_row(parent: Node, name_: String, k: float, colour: Color, text: String, tip: String) -> void:
	var row := UI.hbox(parent, 6)
	var l := UI.label(row, name_, 11)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_bar(row, k, colour, text)
	tip_on(row, tip)


## reputation, WoW style: renown first (how known you are anywhere, Fable
## style), then a bar per faction with its standing
func _render_rep(box_: VBoxContainer) -> void:
	var rep = game.reputation
	var tier: Dictionary = rep.renown_tier
	var tk: float = minf(1, float(tier.into) / tier.span) if tier.get("span") else 1.0
	UI.label(box_, "Renown", 12, UI.GOLD)
	_rep_row(box_, "%s renown" % U.n(floor(rep.renown)), tk, Color("7a5a2a"), tier.name + (" %s / %s" % [U.n(tier.into), U.n(tier.span)] if tier.get("span") else ""), tier.desc)
	var d := UI.label(box_, tier.desc, 11, Color("a99"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_font_override("font", UI.italic)
	UI.label(box_, "Factions", 12, UI.GOLD)
	for f in DB.factions.values():
		var s: Dictionary = rep.standing(f.id)
		var k: float = minf(1, float(s.into) / s.span) if s.get("span") else 1.0
		_rep_row(box_, f.name, k, REP_COLOUR.get(s.id, Color("4f6d3a")), s.name + (" %s / %s" % [U.n(s.into), U.n(s.span)] if s.get("span") else ""), f.get("description", ""))


## titles, Fable style: what you may be called (renown unlocks them)
func _render_titles(box_: VBoxContainer) -> void:
	var rep = game.reputation
	var ttl = game.titles
	UI.label(box_, "Titles", 12, UI.GOLD)
	var d := UI.label(box_, "%s renown (%s). Reputation with anyone adds to it." % [U.n(floor(rep.renown)), rep.renown_tier.name], 11, Color("a99"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_font_override("font", UI.italic)
	var entries := [{"id": "", "name": "No title", "desc": "Folk call you what they like.", "chosen": ttl.chosen == null}]
	entries.append_array(ttl.list)
	for x in entries:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var chosen: bool = x.get("chosen", false)
		var locked = x.get("locked")
		b.text = "%s\n%s" % [x.name, locked if locked else x.get("desc", "")]
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", UI.GOLD if chosen else UI.TEXT)
		b.add_theme_stylebox_override("normal", UI.box(Color(20 / 255.0, 16 / 255.0, 12 / 255.0, 0.8), UI.GOLD if chosen else Color(201 / 255.0, 162 / 255.0, 83 / 255.0, 0.25), 0, 1, Vector4(6, 4, 6, 4)))
		b.add_theme_stylebox_override("hover", UI.box(Color(30 / 255.0, 24 / 255.0, 16 / 255.0, 0.9), UI.GOLD, 0, 1, Vector4(6, 4, 6, 4)))
		b.disabled = locked != null and locked != ""
		if b.disabled:
			b.modulate.a = 0.5
		var id = x.id if x.id != "" else null
		b.pressed.connect(func(): game.titles.choose(id))
		box_.add_child(b)


## merchant window: stock, buyback, and whatever the merchant has to say
func _render_shop(inv) -> void:
	var m = game.merchant
	var w := shop
	w.panel.visible = m.current != null
	if m.current == null:
		return
	var def: Dictionary = m.def
	w.title.text = def.name
	w.title.size_flags_horizontal = Control.SIZE_FILL
	w.sub.text = def.title
	w.sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.clear(w.body)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	w.body.add_child(grid)
	for id in m.stock:
		var price: int = m.price_of(id)
		var n: int = Items.get_def(id).get("buyCount", 1) # arrows come by the hundred
		var row := UI.hbox(grid, 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slot(row, "m:" + id, {"id": id, "count": n})
		var info := UI.rich(row, 12)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var colour := UI.hex(Items.rarity_colour(Items.get_def(id).get("rarity", "common")))
		var price_colour := "#c05040" if price > inv.coins else "#d8c890"
		UI.set_rich(info, "[color=%s]%s[/color]\n[color=%s]%s[/color]%s" % [colour, UI.esc(Items.get_def(id).name), price_colour, UI.money(price), " [color=#9a8f78][font_size=12]for %d[/font_size][/color]" % n if n > 1 else ""])
	var sub := UI.label(w.body, "BUY BACK", 11, UI.TEXT_DIM)
	sub.add_theme_constant_override("line_spacing", 0)
	var bb := UI.hbox(w.body, 4)
	bb.custom_minimum_size = Vector2(0, 40)
	if m.buyback.is_empty():
		UI.label(bb, "Nothing sold yet.", 12, UI.TEXT_DIM)
	for i in m.buyback.size():
		var b: Dictionary = m.buyback[i]
		_slot(bb, "y:%d" % i, {"id": b.id, "count": b.count, "rolls": b.get("rolls")})
	var foot := UI.hbox(w.body, 5)
	if m.npc != null:
		UI.button(foot, "↩ Back", func():
			var keeper = game.merchant.npc
			game.merchant.close()
			if keeper:
				game.npcs.talk(keeper))
	# smiths mend gear, as in WoW: one button for everything
	if def.repair:
		var cost: int = inv.repair_all_cost
		var rb := UI.button(foot, "Repair all  %s" % U.money(cost) if cost else "Nothing to repair", func(): game.inventory.repair_all())
		rb.disabled = cost == 0
	var junk := _junk_value(inv)
	var jb := UI.button(foot, "Sell all junk  %s" % U.money(junk) if junk else "No junk", func(): game.merchant.sell_junk())
	jb.disabled = junk == 0
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(spacer)
	var coins := UI.rich(foot, 13)
	coins.autowrap_mode = TextServer.AUTOWRAP_OFF
	UI.set_rich(coins, UI.money(inv.coins))
	var h := UI.hint(w.body)
	h.text = "A: buy   Y on a bag item: sell   B: leave" if hud.pad_mode else "Click to buy. Right-click (or drag here) anything in your bags to sell it."


## what the junk in your bags would fetch here
func _junk_value(inv) -> int:
	var total := 0
	for loc in inv.bag_locations():
		var stack = inv.get_at(loc)
		if stack != null and Items.view(stack).get("rarity", "common") == "junk":
			total += Items.sell_price(stack, DB.CONFIG.shop.sellFraction) * int(stack.get("count", 1))
	return total


## Cooking: every recipe you know, coloured by how much it can still teach
## you (WoW's orange / yellow / green / grey), with its ingredients.
func _render_cooking() -> void:
	var w := cooking
	w.panel.visible = open.cooking
	if not open.cooking:
		return
	UI.clear(w.body)
	_cook_last = _cook_sig()
	var ck = game.cooking
	var inv = game.inventory
	var sk := craft_skill
	var craft := Cooking.craft_of(sk)
	w.title.text = craft.get("window", "Cooking")
	var rank: int = ck.rank(sk)
	var mx: int = game.skills.cap(sk)
	UI.label(w.body, "%s %d / %d" % [DB.skills[sk].name, rank, mx], 13, Color("f0d070"))
	_skill_bar(w.body, float(rank) / mx, 0)
	var list: Array = ck.known(sk)
	var station: String = list[0].get("station", "fire") if not list.is_empty() else ("forge" if sk == "mining" else "fire")
	var here: String = ck.near_station(station)
	UI.label(w.body, "At %s." % here if here != "" else "You need %s." % craft.get("station", "a fire"), 12, UI.TEXT_DIM if here != "" else Color("d06a50"))
	var busy = ck.crafting
	if list.is_empty():
		var l := UI.label(w.body, "You know no recipes yet. Trainers teach them.", 13, UI.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for r in list:
		var out := Items.get_def(r.output.item)
		var n: int = ck.can_make(r)
		var need := []
		for x in r.inputs:
			var have: int = inv.count(x.item)
			need.append("[color=%s]%s %d/%d[/color]" % ["#9a8f78" if have >= x.count else "#d06a50", UI.esc(Items.get_def(x.item).name), have, x.count])
		var ok: bool = n > 0 and ck.near_station(r.get("station", "fire")) != "" and busy == null and rank >= r.rank
		var row := UI.hbox(w.body, 8)
		var ic := TextureRect.new()
		ic.texture = _icon_for(r.output.item)
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(ic)
		var txt := UI.rich(row, 11)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.set_rich(txt, "[font_size=13][color=%s]%s%s%s[/color][/font_size]\n%s" % [UI.hex(RECIPE_COLOUR.get(ck.colour(r), UI.TEXT)), UI.esc(out.name), " ×%d" % r.output.count if r.output.count > 1 else "", " [%d]" % n if n else "", ", ".join(need)])
		var id: String = r.id
		UI.button(row, craft.get("button", "Make"), func(): game.cooking.start(id, 1)).disabled = not ok
		UI.button(row, "All", func(): game.cooking.start(id, 1 << 30)).disabled = not (ok and n > 1)
		UI.rule(w.body, Color("2a2218"))


func _cook_sig() -> String:
	var ck = game.cooking
	var sk := craft_skill
	var list: Array = ck.known(sk)
	var station: String = list[0].get("station", "fire") if not list.is_empty() else "fire"
	var s := "%s|%d|%s|%s|%d" % [sk, ck.rank(sk), ck.near_station(station), ck.crafting != null, game.inventory.free_slots()]
	for r in list:
		s += "|%d" % ck.can_make(r)
	return s


## k: the trained part (gold); extra: what tools add on top (green)
func _skill_bar(parent: Node, k: float, width := 90, extra := 0.0) -> void:
	var track := ColorRect.new()
	track.color = Color.BLACK
	track.custom_minimum_size = Vector2(width, 4)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(track)
	var fill := ColorRect.new()
	fill.color = Color("c8a040")
	fill.anchor_bottom = 1
	fill.anchor_right = clampf(k, 0, 1)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	if extra > 0:
		var more := ColorRect.new()
		more.color = Color("5fd35f")
		more.anchor_left = clampf(k, 0, 1)
		more.anchor_bottom = 1
		more.anchor_right = clampf(k + extra, 0, 1)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(more)


func _render_settings() -> void:
	var w := settings_win
	w.panel.visible = open.settings
	if not open.settings:
		return
	for id in w.inputs:
		var v = game.settings.get_value(id)
		var parts: Array = w.inputs[id]
		if parts[0] is HSlider:
			parts[0].set_value_no_signal(v)
			parts[1].text = "%d%%" % int(v)
		else:
			parts[0].set_pressed_no_signal(v)
	hud.keybind_ui.render()


## Professions (U), apart from the spellbook (Dan, 2026-10-16): each
## profession with its rank, and its abilities to drag onto the bar
func _render_skills() -> void:
	var w := skills_win
	w.panel.visible = open.skills
	if not open.skills:
		return
	UI.clear(w.inner)
	var sk = game.skills
	# only what you have learned: the rest are yours to discover (Dan, 2026-10-27)
	var learned := DB.skills.values().filter(func(d): return sk.has(d.id))
	w.sub.text = "%d learned" % learned.size() if not learned.is_empty() else ""
	if learned.is_empty():
		UI.wrapped(UI.label(w.inner, "You have no professions yet. Folk who practise a craft may teach you theirs.", 13, UI.TEXT_DIM))
	for d in learned:
		_prof_row(w.inner, d)
	w.foot.text = "Professions are learned from trainers and rise as you use them. Drag an ability onto your bar."


## a small heading over a group of rows
func _section(parent: Node, text: String) -> void:
	var l := UI.label(parent, text, 10, UI.GOLD)
	l.modulate.a = 0.8


func _prof_row(parent: Node, d: Dictionary) -> void:
	var sk = game.skills
	var known: bool = sk.has(d.id)
	var ladder: bool = sk.laddered(d.id)
	var ranked: bool = ladder or d.get("maxRank")
	var mx: int = sk.cap(d.id) if known else int(d.get("maxRank", 60))
	var bonus: int = sk.tool_bonus(d.id) if known and ranked else 0
	var level := ("%d%s / %d" % [sk.rank(d.id), "+%d" % bonus if bonus else "", mx] if ranked else "Learned") if known else "Not learned"
	var row := UI.panel(parent, 0, Color("1a150f"), UI.BORDER_DIM)
	row.add_theme_stylebox_override("panel", UI.box(Color("1a150f"), UI.BORDER_DIM, 0, 1, Vector4(8, 6, 8, 6)))
	row.modulate.a = 1.0 if known else 0.55
	var h := UI.hbox(row, 10)
	# the icon, or an empty square of its size so the rows line up
	var pic := TextureRect.new()
	pic.texture = icons.profession(d.id)
	pic.custom_minimum_size = Vector2(36, 36)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pic)
	var body := UI.vbox(h, 3)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UI.hbox(body, 6)
	UI.label(top, "%s %s" % [sk.rank_name(d.id), d.name] if known and ladder else d.name, 13, Color("f0e4c8")).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bonus:
		var rl := RichTextLabel.new()
		rl.bbcode_enabled = true
		rl.fit_content = true
		rl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rl.scroll_active = false
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rl.add_theme_font_size_override("normal_font_size", 15)
		rl.text = "[color=#f0d070]%d[/color][color=#5fd35f]+%d[/color][color=#f0d070] / %d[/color]" % [sk.rank(d.id), bonus, mx]
		top.add_child(rl)
	else:
		UI.label(top, level, 15 if known else 12, Color("f0d070") if known else UI.TEXT_DIM)
	_skill_bar(body, float(sk.rank(d.id)) / mx if known else 0.0, 90, float(bonus) / mx)
	if known and ladder:
		_ladder_lines(body, d)
	var abil := UI.hbox(h, 4)
	if known:
		for a in d.get("teaches", []):
			if ActionBar.bar_ability(game, a):
				_spell_slot(abil, a, 36)
		if d.id == "cooking":
			UI.button(abil, "Cookbook", func(): show_window("cooking"))
		if d.id == "mining":
			UI.button(abil, "Smelting", func(): show_window("smelting"))
		elif d.id != "cooking" and d.has("craft"):
			UI.button(abil, d.craft.get("window", "Craft"), func(): show_window("craft:" + d.id))
	tip_on(row, d.get("desc", ""), d.name)


## A laddered profession's extra lines: skill experience to the next level,
## who trains the next rank once the limit is reached, perks chosen and the
## perk choices waiting (a button each).
func _ladder_lines(body: Node, d: Dictionary) -> void:
	var sk = game.skills
	var id: String = d.id
	var lvl: int = sk.rank(id)
	if lvl < sk.cap(id):
		UI.label(body, "%d / %d skill experience to level %d" % [int(sk.xp.get(id, 0)), Skills.xp_needed(lvl), lvl + 1], 11, UI.TEXT_DIM)
	else:
		var nxt: Dictionary = sk.next_rank(id)
		var text := "At the %s's limit." % sk.rank_name(id)
		if not nxt.is_empty():
			var why: String = sk.rank_blocked(id)
			# no trainer's name: more than one will teach each rank in time (Dan)
			text += " A trainer can raise you to %s%s." % [nxt.name, " (%s)" % why.to_lower().replace("requires ", "needs ") if why != "" else ""]
		UI.wrapped(UI.label(body, text, 11, Color("e0b060")))
	var chosen := []
	for p in d.get("perks", []):
		var c: Dictionary = sk.chosen_perk(id, int(p.level))
		if not c.is_empty():
			chosen.append(c.name)
	if not chosen.is_empty():
		UI.wrapped(UI.label(body, "Perks: " + ", ".join(chosen), 11, Color("9fd38a")))
	for p in sk.perk_choices(id):
		UI.label(body, "Choose a perk (level %d):" % int(p.level), 11, UI.GOLD)
		var row := UI.hbox(body, 4)
		for c in p.choices:
			var b = UI.button(row, c.name, func():
				sk.choose_perk(id, int(p.level), c.id)
				_after_change("skills"))
			tip_on(b, c.desc, c.name)


## spellbook: every ability, ready to drag onto the bar. A card each, two
## to a row: the icon to drag, its name, what it costs and how often, and
## whether it is on the bar (and on which key).
func _render_spellbook() -> void:
	var w := spellbook
	w.panel.visible = open.spellbook
	if not open.spellbook:
		return
	UI.clear(w.inner)
	# professions' abilities (fishing, cooking, camp) live in Professions (U)
	var ids := []
	for id in DB.abilities:
		if ActionBar.bar_ability(game, id) and not DB.abilities[id].get("skill"):
			ids.append(id)
	var arch: Dictionary = game.stats.archetype
	w.sub.text = "%s · %d spells" % [arch.get("name", ""), ids.size()]
	if ids.is_empty():
		UI.wrapped(UI.label(w.inner, "No spells yet.", 13, UI.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	w.inner.add_child(grid)
	for id in ids:
		_spell_card(grid, id)
	w.foot.text = "A: pick up / place on the bar   Y: remove from the bar   B: back" if hud.pad_mode else "Drag a spell onto the bar. Drag spells along the bar to rearrange them, or off it to remove them."


## What changes a spell now: its Enhanced rank, its fork, legendary powers.
func _upgrade_lines(id: String) -> Array:
	var out := []
	var b = game.builds
	var up = DB.abilities.get(id, {}).get("upgrades")
	if up != null and b.has_enhanced(id):
		out.append(_l("Enhanced: %s" % _esc(up.enhanced.text), "#8fbf6a", 12))
		for f in up.forks:
			if f.id == b.fork_of(id):
				out.append(_l("%s: %s" % [_esc(f.name), _esc(f.text)], "#8fbf6a", 12))
	for p in b.powers():
		if p.get("spell") == id or p.get("spells", []).has(id):
			out.append(_l("%s: %s" % [_esc(p.name), _esc(p.text)], UI.hex(Items.rarity_colour("legendary")), 12))
	return out


# ------------------------------------------------------------------ talents
## Path points buy each spell's Enhanced rank, then one of its two forks;
## one key passive per character (builds.gd, data/builds.json).
func _render_talents() -> void:
	var w := talents
	w.panel.visible = open.talents
	if not open.talents:
		return
	UI.clear(w.inner)
	var b = game.builds
	var rule := Builds.points_rule()
	w.sub.text = "%d of %d path points free" % [b.points_free, b.points_total]
	if b.points_total == 0:
		UI.wrapped(UI.label(w.inner, "Path points start at level %d: one each level. Each buys a spell's Enhanced rank, then one of its two forks." % int(rule.fromLevel), 13, UI.TEXT_DIM))
	# the key passive
	UI.label(w.inner, "Key passive", 15, Color("e8c070"))
	var kp_row := UI.hbox(w.inner, 6)
	for p in Builds.passives_for(game.stats.archetype.get("id", "")):
		var chosen: bool = b.key_passive == p.id
		var pid: String = p.id
		var btn := UI.button(kp_row, ("✓ " if chosen else "") + p.name, func():
			b.choose_passive(pid)
			render(), 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = chosen or not b.key_passive_open
		tip_on(btn, p.text, p.name)
	if not b.key_passive_open:
		UI.wrapped(UI.label(w.inner, "Opens at level %d. You may change it later." % int(DB.builds.get("keyPassiveLevel", 10)), 12, UI.TEXT_DIM))
	# spell upgrades
	UI.label(w.inner, "Spell upgrades", 15, Color("e8c070"))
	for id in game.stats.archetype.get("abilities", []):
		var a: Dictionary = DB.abilities.get(id, {})
		var up = a.get("upgrades")
		if up == null or not game.skills.knows_ability(id):
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(Color("15110c"), Color("6b5532") if b.has_enhanced(id) else Color("2e261a"), 0, 1, Vector4(6, 6, 8, 6)))
		w.inner.add_child(card)
		var h := UI.hbox(card, 8)
		_spell_slot(h, id, 36)
		var v := UI.vbox(h, 3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(v, a.name, 13, Color("f0e4c8"))
		var row := UI.hbox(v, 4)
		var sid: String = id
		var enh := UI.button(row, "✓ Enhanced" if b.has_enhanced(id) else "Enhance", func():
			b.enhance(sid)
			render(), 12)
		enh.disabled = b.has_enhanced(id) or b.points_free < int(rule.get("enhancedCost", 1))
		tip_on(enh, up.enhanced.text, "Enhanced " + a.name)
		for f in up.forks:
			var fid: String = f.id
			var mine: bool = b.fork_of(id) == fid
			var fb := UI.button(row, ("✓ " if mine else "") + f.name, func():
				b.choose_fork(sid, fid)
				render(), 12)
			fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fb.disabled = mine or b.fork_of(id) != "" or not b.has_enhanced(id) or b.points_free < int(rule.get("forkCost", 1))
			tip_on(fb, f.text, f.name)
	if b.points_spent > 0:
		UI.button(w.inner, "Take back all path points", func():
			b.respec()
			render(), 12)


func _spell_card(parent: Node, id: String) -> void:
	var a: Dictionary = DB.abilities[id]
	var at: int = game.action_bar.slots.find(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.box(Color("15110c"), Color("6b5532") if at >= 0 else Color("2e261a"), 0, 1, Vector4(6, 6, 8, 6)))
	card.custom_minimum_size = Vector2(230, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var h := UI.hbox(card, 8)
	_spell_slot(h, id, 40)
	var v := UI.vbox(h, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label(v, a.name, 13, Color("f0e4c8"))
	var facts := []
	var r = game.resources
	for k in a.get("cost", {}):
		facts.append("%s %s" % [U.n(a.cost[k]), r.name_of(k)])
	for k in a.get("gain", {}):
		facts.append("+%s %s" % [U.n(a.gain[k]), r.name_of(k)])
	var cd: float = a.get("tuning", {}).get("cooldown", 0.0)
	if cd > 0:
		facts.append("%s sec cooldown" % U.n(cd))
	if not facts.is_empty():
		UI.label(v, " · ".join(facts), 11, Color("8fb4f0"))
	var key: String = game.keys.label("bar%d" % at) if at >= 0 else ""
	UI.label(v, ("On the bar" + (" · key %s" % key if key != "" else "")) if at >= 0 else "Not on the bar", 10, Color("8cbf78") if at >= 0 else UI.TEXT_DIM)
	tip_on(card, a.get("desc", ""), a.name)


# ------------------------------------------------------------------ layout
## Where each window sits (style.css), recomputed as the screen changes.
func layout() -> void:
	var vp := get_viewport_rect().size
	if character.panel.visible:
		# the equipment page sets the size of every tab's page (layout(),
		# not the render: a new label measures its height only once laid out)
		if character.main.visible:
			character.pages.custom_minimum_size = character.main.get_combined_minimum_size()
		_fit(character.panel, Vector2(12, 12))
	if shop.panel.visible:
		_fit(shop.panel, Vector2(character.panel.size.x + 24 if open.character else 12, 12))
	for w in [spellbook, skills_win]:
		if w.panel.visible:
			# above the spell bar, scrolling rather than running off the top
			var inner: Vector2 = w.inner.get_combined_minimum_size()
			var room := maxf(120, vp.y - 140 - 12 - 110)
			w.scroll.custom_minimum_size = Vector2(inner.x + (12 if inner.y > room else 0), minf(inner.y, room))
			var s := _fit(w.panel, Vector2.ZERO)
			w.panel.position = Vector2(roundf((vp.x - s.x) / 2), maxf(12, vp.y - 140 - s.y))
	if settings_win.panel.visible:
		var inner: Control = settings_win.inner
		settings_win.scroll.custom_minimum_size = Vector2(296, minf(inner.get_combined_minimum_size().y, vp.y - 290))
		var s := _fit(settings_win.panel, Vector2.ZERO)
		settings_win.panel.position = Vector2(roundf((vp.x - s.x) / 2), 70)
	if talents.panel.visible:
		var s := _fit(talents.panel, Vector2.ZERO)
		talents.panel.position = Vector2(roundf((vp.x - s.x) / 2), roundf(vp.y * 0.3))
	if cooking.panel.visible:
		var s := _fit(cooking.panel, Vector2.ZERO)
		cooking.panel.position = Vector2(roundf((vp.x - s.x) / 2), roundf(vp.y * 0.22))
	_layout_bags(vp)


func _fit(p: Control, at: Vector2) -> Vector2:
	UI.fit_steady(p)
	if at != Vector2.ZERO:
		p.position = at
	return p.size


## the bag frames stack up from above the bag slots, right-aligned, and wrap
## into another column to the left when the screen runs out of height
func _layout_bags(vp: Vector2) -> void:
	if not bags.visible:
		return
	var right := vp.x - 12
	var bottom: float = hud.purse.position.y - 8 # stacked up from the bag tray and its purse
	var top_limit := 28.0
	var y := bottom
	var col_w := 0.0
	for f in bags.get_children():
		if f.is_queued_for_deletion():
			continue
		var s: Vector2 = f.get_combined_minimum_size()
		f.size = s
		if y - s.y < top_limit and y < bottom:
			right -= col_w + 8
			y = bottom
			col_w = 0
		f.position = Vector2(right - s.x, y - s.y)
		y -= s.y + 8
		col_w = maxf(col_w, s.x)


## left edge of the bags, for the tooltip to stay clear of them
func _bags_left() -> float:
	var x := INF
	if bags.visible:
		for f in bags.get_children():
			x = minf(x, f.position.x)
	return x


# ------------------------------------------------------------------ tooltip
func _esc(s) -> String:
	return UI.esc(s)


func _name_line(name_: String, colour: String, size := 15) -> String:
	return "[font_size=%d][color=%s]%s[/color][/font_size]\n" % [size, colour if colour != "" else "#f0e4c8", _esc(name_)]


func _l(text: String, colour := "", size := 0) -> String:
	var s := text
	if colour != "":
		s = "[color=%s]%s[/color]" % [colour, s]
	if size:
		s = "[font_size=%d]%s[/font_size]" % [size, s]
	return s + "\n"


func _hide_tip() -> void:
	tooltip.visible = false
	tip_from = null
	tip_cursor = false
	tip_key = null


## Fill the tooltip: one box, or the worn items' boxes and then this one
## (`width` 0 sizes a plain tip to its text).
func _set_tip(main: Array, worn: Array, width := 240) -> void:
	UI.clear(tooltip)
	for w in worn:
		_tip_box(w, 220)
	_tip_box("".join(main), 220 if not worn.is_empty() else width)
	tooltip.visible = true
	_place_tip()


func _tip_box(text: String, width: float) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(10 / 255.0, 9 / 255.0, 14 / 255.0, 0.96), Color("5a5a70"), 0, 1, Vector4(10, 7, 10, 7)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(p)
	var r := UI.rich(p, 13)
	text = text.strip_edges()
	if width <= 0:
		# a short tip is as wide as its words, up to 240
		var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(text, "", true)
		var longest := 0.0
		for line in plain.split("\n"):
			longest = maxf(longest, UI.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
		width = clampf(longest + 4, 40, 220)
	r.custom_minimum_size = Vector2(width, 0)
	r.size = Vector2(width, 0) # measured at its own width from the first frame
	UI.set_rich(r, text)


## The bottom-right corner, above the bag slots (left of the bags when
## they are open, so it never covers them).
func _place_tip() -> void:
	if not tooltip.visible:
		return
	var vp := get_viewport_rect().size
	var s := UI.fit_steady(tooltip)
	if tip_cursor:
		var m := get_viewport().get_mouse_position() + Vector2(16, 18)
		if m.x + s.x > vp.x - 8:
			m.x -= s.x + 28
		if m.y + s.y > vp.y - 8:
			m.y -= s.y + 30
		tooltip.position = Vector2(maxf(8, m.x), maxf(8, m.y))
		return
	var x := vp.x - s.x - 16
	var bar_top: float = hud.bottom_top()
	var y := minf(vp.y, bar_top) - s.y - 10
	var bl := _bags_left()
	if bl < INF:
		x = minf(x, bl - s.x - 10)
	tooltip.position = Vector2(maxf(8, x), maxf(8, y))


## "20 mana" / "25 Resolve" / "Gives 15 Resolve" under an ability's name
func _cost_line(a: Dictionary) -> String:
	var r = game.resources
	var parts := []
	for k in a.get("cost", {}):
		parts.append("%s %s" % [U.n(a.cost[k]), r.name_of(k)])
	if a.get("spendsAll"):
		parts.append("Spends all %s" % r.name_of(a.spendsAll))
	for k in a.get("gain", {}):
		parts.append("Gives %s %s" % [U.n(a.gain[k]), r.name_of(k)])
	return _l(" · ".join(parts), "#8fb4f0", 12) if not parts.is_empty() else ""


func _tooltip(loc: String) -> void:
	if loc.begins_with("a:") or loc.begins_with("k:"):
		var id = game.action_bar.slots[int(loc.substr(2))] if loc.begins_with("a:") else loc.substr(2)
		if id == null:
			_hide_tip()
			return
		var item = ActionBar.item_ref(id)
		if item != null:
			var d := Items.get_def(item)
			_set_tip([_name_line(d.name, UI.hex(Items.rarity_colour(d.get("rarity", "common")))), _l("[i]%s[/i]" % _esc(d.get("description", "")), "#d0b878"), _l("Press to use%s" % (" (again to put it away)" if d.get("slot") == "offHand" else ""), "#8fbf6a", 12)], [])
			return
		var ab: Dictionary = DB.abilities.get(id, {})
		var req := Spells.requirement_text(ab)
		var lines := [_name_line(ab.get("name", id), ""), _cost_line(ab)]
		if req != "":
			lines.append(_l(_esc(req), "#ff4a3a" if Spells.missing_gear(game, ab) != "" else UI.hex(UI.TEXT), 12))
		lines.append(_l("[i]%s[/i]" % _esc(ab.get("desc", "")), "#d0b878"))
		lines.append_array(_upgrade_lines(id))
		_set_tip(lines, [])
		return
	var inv = game.inventory
	var stack = inv.get_at(loc) if loc != "" else null
	var shop_price = null
	if loc.begins_with("m:"):
		stack = {"id": loc.substr(2), "count": 1}
		shop_price = game.merchant.price_of(stack.id)
	elif loc.begins_with("y:"):
		var bb: Array = game.merchant.buyback
		var i := int(loc.substr(2))
		stack = bb[i] if i < bb.size() else null
		shop_price = stack.paid if stack else null
	if stack == null or loc == "s:0":
		_hide_tip()
		return
	var lines := _stack_lines(stack, loc, shop_price)
	if loc == Inventory.AMMO_LOC:
		_set_tip(lines, [])
	else:
		_fill(lines, Items.view(stack), loc)


## Every line of one item's tooltip, as hovering it in the bags shows it
## (the compare box shows the worn item the same way).
func _stack_lines(stack: Dictionary, loc: String, shop_price, compare := false) -> Array:
	var inv = game.inventory
	var def := Items.view(stack)
	var rare := ["enhanced", "rare", "epic", "legendary"].has(def.get("rarity"))
	var kind: String = KIND_LABEL.get(def.kind, def.kind.capitalize())
	var kind_line: String = (DB.rarities[def.rarity].name + " " + kind.to_lower()) if rare else kind
	if def.get("slot"):
		var slot_name := ""
		if def.slot == "oneHand":
			slot_name = "One-hand" + (" " + def.weaponType if def.get("weaponType") else "")
		else:
			for s in DB.EQUIP_SLOTS:
				if s.id == def.slot or s.get("fits") == def.slot:
					slot_name = s.label
					break
		kind_line += " · " + slot_name
	var lines := [_name_line(def.name, UI.hex(Items.rarity_colour(def.get("rarity", "common")))), _l(_esc(kind_line), "#9a8f78", 12)]
	if def.get("itemLevel"):
		lines.append(_l("Item level %s" % U.n(def.itemLevel), "#e8c860", 12))
	if def.get("armourType"):
		var ok: bool = inv.can_wear(def)
		lines.append(_l(DB.armour_types[def.armourType].name + ("" if ok else " (a %s cannot wear this)" % game.stats.archetype.name), "" if ok else UI.hex(UI.DOWN)))
	if def.get("damage"):
		# weapons compare by damage per second, as in WoW
		var st = game.stats
		var speed: float = def.get("speed", DB.CONFIG.stats.fistSpeed)
		var mine: float = (def.damage[0] + def.damage[1]) / 2.0 / speed
		var diff: float = roundf((mine - (st.weapon_range[0] + st.weapon_range[1]) / 2.0 / st.weapon_speed) * 10) / 10
		var cmp := "" if loc.begins_with("e:") or diff == 0 else " [color=%s](%s%s)[/color]" % [UI.hex(UI.UP if diff > 0 else UI.DOWN), "+" if diff > 0 else "", U.n(diff)]
		lines.append("[table=2][cell expand=1]%s–%s damage[/cell][cell]Speed %.2f[/cell][/table]\n" % [U.n(def.damage[0]), U.n(def.damage[1]), speed])
		lines.append(_l("(%.1f damage per second%s)" % [mine, cmp]))
	for k in def.get("stats", {}):
		lines.append(_l("+%s %s" % [U.n(def.stats[k]), STAT_LABEL.get(k, k)], UI.hex(UI.UP)))
	# forge work: reforged stat, sockets and the gems in them
	var rf = def.get("reforged")
	if typeof(rf) == TYPE_DICTIONARY:
		lines.append(_l("Reforged: %s into %s" % [STAT_LABEL.get(rf.from, rf.from), STAT_LABEL.get(rf.to, rf.to)], "#a0c8e8", 12))
	for g in Items.gems_of(stack):
		lines.append(_l("◆ %s: %s" % [_esc(Items.get_def(g).name), _esc(Gems.bonus_text(g))], UI.hex(Items.rarity_colour(Items.get_def(g).get("rarity", "common")))) if g != null else _l("◇ Empty socket", "#9a8f78"))
	if def.get("kind") == "gem":
		lines.append(_l("In a socket: %s" % _esc(Gems.bonus_text(stack.id)), UI.hex(UI.UP)))
	var cap: int = game.forge.temper_cap(stack) if Items.ROLLED_KINDS.has(def.kind) else 0
	if cap > 0:
		lines.append(_l("Enchanted %d / %d" % [Items.temper_of(stack), cap], "#c8a040", 12))
	if def.get("bagSlots"):
		lines.append(_l("%s slots" % U.n(def.bagSlots)))
	var power := Builds.power_def(Items.power_of(stack))
	if not power.is_empty():
		lines.append(_l("%s: %s" % [_esc(power.name), _esc(power.text)], UI.hex(Items.rarity_colour("legendary"))))
	var dur := Items.durability(stack)
	if dur != -1:
		lines.append(_l("Broken: gives no stats until repaired", UI.hex(UI.DOWN)) if dur == 0 else _l("Durability %d / 100" % dur, UI.hex(UI.DOWN) if dur <= 25 else ""))
	if stack.get("count", 1) > 1:
		lines.append(_l("%d carried" % stack.count))
	lines.append(_l("[i]%s[/i]" % _esc(def.get("description", "")), "#d0b878"))
	var sell := Items.sell_price(stack, DB.CONFIG.shop.sellFraction)
	if shop_price != null:
		lines.append(_l("Price: %s" % UI.money(shop_price), "#f0d890", 12))
	elif def.get("quest"):
		lines.append(_l("Quest item", "#b8a880", 12))
	elif not sell:
		lines.append(_l("No sell value", "#9a8f78", 12))
	else:
		lines.append(_l("Sell for %s%s" % [UI.money(sell * stack.get("count", 1)), " (%s each)" % UI.money(sell) if stack.get("count", 1) > 1 else ""], "#b8a880", 12))
	var hint := ""
	if shop_price != null:
		if not hud.pad_mode:
			hint = "Click to buy"
	elif game.merchant.current != null and not def.get("quest") and not loc.begins_with("s:") and loc != Inventory.AMMO_LOC and not hud.pad_mode:
		hint = "Right-click to sell"
	elif loc == Inventory.AMMO_LOC:
		lines.insert(lines.size() - 2, _l("Auto Shot uses these. When they run out, the next arrows in your bags take their place. Drag other arrows here to change.", "#8fbf6a", 12))
		return lines
	else:
		var action := ""
		if def.kind == "ammo":
			action = "Right-click to use these for Auto Shot"
		elif loc.begins_with("e:") or loc.begins_with("s:"):
			action = "Right-click to unequip"
		elif def.get("slot"):
			action = "Right-click to equip"
		elif def.kind == "consumable":
			action = "Right-click to drink"
		elif def.kind == "document":
			action = "Right-click to read"
		elif def.kind == "bag":
			action = "Right-click to place in a bag slot"
		if not hud.pad_mode:
			hint = action
	if hint != "" and not compare:
		lines.append(_l(hint, "#8fbf6a", 12))
	return lines


## WoW-style compare: gear hovered outside the character panel shows what is
## worn in that slot alongside, with the stat changes on the hovered item.
func _fill(lines: Array, def: Dictionary, loc: String) -> void:
	var worn := []
	var worn_at := [] ## where each is worn, for its full tooltip
	if def.get("slot") and not loc.begins_with("e:") and not loc.begins_with("s:"):
		var pairs := {"oneHand": ["mainHand", "offHand"], "mainHand": ["mainHand", "offHand"] if def.get("damage") else ["mainHand"], "finger": ["finger1", "finger2"], "trinket": ["trinket1", "trinket2"]}
		for s in pairs.get(def.slot, [def.slot]):
			var st = game.inventory.get_at("e:" + s)
			var w = Items.view(st) if st != null else null
			# an off-hand shield is not compared against a weapon
			if w != null and (s != "offHand" or def.slot == "offHand" or w.get("damage")):
				worn.append(w)
				worn_at.append(s)
	if worn.is_empty():
		_set_tip(lines, [])
		return
	var totals := func(d: Dictionary) -> Dictionary:
		var t: Dictionary = d.get("stats", {}).duplicate()
		if d.get("damage"):
			t.damage = (d.damage[0] + d.damage[1]) / 2.0
		return t
	var label := func(k: String) -> String: return "average damage" if k == "damage" else STAT_LABEL.get(k, k)
	var boxes := []
	for s in worn_at:
		var at: String = "e:" + s
		boxes.append(_l("CURRENTLY EQUIPPED", "#9a8f78", 11) + "".join(_stack_lines(game.inventory.get_at(at), at, null, true)))
	var a: Dictionary = totals.call(def)
	var diffs := []
	for w in worn:
		var b: Dictionary = totals.call(w)
		var out := ""
		var keys := a.keys()
		for k in b:
			if not keys.has(k):
				keys.append(k)
		for k in keys:
			var d: float = roundf((a.get(k, 0) - b.get(k, 0)) * 10) / 10
			if d:
				out += _l("%s%s %s" % ["+" if d > 0 else "", U.n(d), label.call(k)], UI.hex(UI.UP if d > 0 else UI.DOWN))
		diffs.append(_l("If you replace %s:" % _esc(w.name), "#9a8f78", 12) + (out if out != "" else _l("No stat change", "#9a8f78", 12)))
	var at := lines.size()
	for i in lines.size():
		if lines[i].contains("#b8a880") or lines[i].contains("#f0d890") or (lines[i].contains("#9a8f78") and lines[i].contains("No sell value")):
			at = i
			break
	for i in diffs.size():
		lines.insert(at + i, diffs[i])
	_set_tip(lines, boxes)


## Whoever is under the cursor in the world: called every frame with the
## pick (or null). Item and button tooltips come first.
func world_tip(pick) -> void:
	if tip_from == "ui" and tooltip.visible:
		return
	var key = pick.obj if pick != null and (pick.kind == "enemy" or pick.kind == "npc" or pick.kind == "sign") else null
	if key == null:
		if tip_from == "world":
			_hide_tip()
		return
	tip_from = "world"
	tip_cursor = false
	var text := ""
	if pick.kind == "sign":
		text = _name_line("Signpost", "")
		for l in Layout.signpost_lines(key):
			text += "[color=#c9a45c]%s[/color] %s [color=#9a8f78][font_size=12]%s m %s[/font_size][/color]\n" % [l.arrow, _esc(l.label), U.n(l.metres), l.dir]
	elif pick.kind == "enemy":
		text = _name_line(key.cfg.name, "#f0d050" if key.passive else "#ff8a6a") + _l("Level %s%s" % [U.n(key.cfg.get("level", 1)), " Elite" if key.cfg.get("elite") else ""]) + _l("%d / %d health" % [ceili(key.health), key.max_health], "#9a8f78", 12)
	else:
		text = _name_line(key.name, "#a8e08c") + (_l("<%s>" % _esc(key.def.title), "#9a8f78", 12) if key.def.get("title") else "") + _l("Level %s" % U.n(key.def.get("level", 1)))
	if not is_same(tip_key, key) or tip_text != text:
		tip_key = key
		tip_text = text
		_set_tip([text], [])
	_place_tip()


# ------------------------------------------------------------------ mouse drag
func _icon_for_loc(loc: String) -> Texture2D:
	if loc.begins_with("a:"):
		var a = game.action_bar.slots[int(loc.substr(2))]
		return _icon_for(ActionBar.item_ref(a)) if ActionBar.item_ref(a) != null else icons.abilities.get(a)
	if loc.begins_with("k:"):
		return icons.abilities.get(loc.substr(2))
	var stack = game.inventory.get_at(loc)
	return _icon_for(stack.id) if stack != null else null


func _down(loc: String, at: Vector2) -> void:
	if loc.begins_with("a:"):
		if game.action_bar.slots[int(loc.substr(2))] != null:
			drag = {"from": loc, "at": at, "moved": false}
		return
	if loc.begins_with("k:"):
		drag = {"from": loc, "at": at, "moved": false}
		return
	if loc == "s:0":
		toggle_bag(0)
		return
	if loc.begins_with("m:") or loc.begins_with("y:"):
		_shop_click(loc)
		return
	if game.inventory.get_at(loc) == null:
		if loc.begins_with("s:"):
			toggle_bag(int(loc.substr(2)))
		return
	drag = {"from": loc, "at": at, "moved": false}


func _input(e: InputEvent) -> void:
	if drag == null:
		return
	if e is InputEventMouseMotion:
		if not drag.moved and e.global_position.distance_to(drag.at) < 4:
			return
		if not drag.moved:
			drag.moved = true
			ghost.texture = _icon_for_loc(drag.from)
			ghost.visible = true
			tooltip.visible = false
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		ghost.position = e.global_position - Vector2(20, 20)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_up(e.global_position)
		get_viewport().set_input_as_handled()


func _up(at: Vector2) -> void:
	var d: Dictionary = drag
	drag = null
	ghost.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var bar = game.action_bar
	if not d.moved:
		# a plain click: a bag in its socket opens that bag; a spell is cast
		if d.from.begins_with("s:"):
			toggle_bag(int(d.from.substr(2)))
		if d.from.begins_with("a:"):
			var a = bar.slots[int(d.from.substr(2))]
			if a != null:
				bar.clicked[a] = true
		return
	if game.merchant.current != null and _over(shop.panel, at) and not d.from.begins_with("a:") and not d.from.begins_with("k:"):
		game.merchant.sell(d.from)
		return
	var to = _slot_at(at)
	dropOn(d.from, to, _over(hud.action_bar, at), _over_window(at))


func _over(c: Control, at: Vector2) -> bool:
	return c != null and is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(at)


func _over_window(at: Vector2) -> bool:
	for w in [character, spellbook, skills_win, settings_win, talents, cooking, shop]:
		if _over(w.panel, at):
			return true
	for f in bags.get_children():
		if _over(f, at):
			return true
	return hud.over_hud(at)


func _slot_at(at: Vector2):
	for loc in _visible_locs(true):
		var s := _slot_node(loc)
		if s and s.get_global_rect().has_point(at):
			return loc
	return null


## Shared by mouse and gamepad: put whatever is at `from` onto `to`.
func dropOn(from: String, to, over_bar := false, over_window := false) -> void:
	var bar = game.action_bar
	var inv = game.inventory
	if from.begins_with("a:") or from.begins_with("k:"):
		var ability = bar.slots[int(from.substr(2))] if from.begins_with("a:") else from.substr(2)
		if to != null and to.begins_with("a:"):
			if from.begins_with("a:"):
				bar.move(int(from.substr(2)), int(to.substr(2)))
			else:
				bar.place(ability, int(to.substr(2)))
		elif from.begins_with("a:") and not over_bar:
			bar.remove(int(from.substr(2))) # dragged off the bar
			var nm := ActionBar.entry_name(ability)
			var text := "%s removed from the bar." % nm if ActionBar.item_ref(ability) != null else "%s removed from the bar. Open %s to put it back." % [nm, "Professions (U)" if DB.abilities.get(ability, {}).get("skill") else "the spellbook (P)"]
			game.events.emit("log", {"text": text, "kind": "muted", "throttle": "bar-removed"})
		return
	if to != null and to.begins_with("a:"):
		# anything usable (a draught, a torch, lockpicks) goes on as an item
		var stack = inv.get_at(from)
		if stack != null:
			var d := Items.get_def(stack.id)
			if d.get("slot") or ["consumable", "document", "torch", "tool"].has(d.get("kind")):
				bar.place_item(stack.id, int(to.substr(2)))
		return
	if to != null and not to.begins_with("k:"):
		if to != "s:0":
			inv.move(from, to)
		return
	# released over the world rather than a window: drop it on the ground
	if not over_window:
		game.loot.drop_from_inventory(from)


# ------------------------------------------------------------------ gamepad
const _NAV_ORDER := ["m:", "y:", "b:", "e:", "k:", "s:", "a:"]


## every slot on screen, windows first and the spell bar last
func _visible_locs(with_backpack := false) -> Array:
	var out := []
	for loc in slots:
		var s := _slot_node(loc)
		if s and (with_backpack or loc != "s:0"):
			out.append(loc)
	for loc in bar_slots:
		if _slot_node(loc):
			out.append(loc)
	return out


func _default_focus(which) -> Variant:
	var locs := _visible_locs()
	var pick := func(prefix: String):
		for l in locs:
			if l.begins_with(prefix):
				return l
		return null
	if which == "character" and open.character:
		return "e:mainHand"
	if which == "spellbook" and open.spellbook:
		return pick.call("k:")
	if which == "shop" and game.merchant.current != null:
		return pick.call("m:")
	var b = pick.call("b:")
	if b != null:
		return b
	if open.character:
		return "e:mainHand"
	var k = pick.call("k:")
	return k if k != null else pick.call("a:")


func _paint_focus() -> void:
	for loc in slots:
		if is_instance_valid(slots[loc]):
			slots[loc].focused = false
			slots[loc].queue_redraw()
	for loc in bar_slots:
		bar_slots[loc].focused = false
		bar_slots[loc].queue_redraw()
	if focus == null or not hud.pad_mode:
		return
	var s := _slot_node(focus)
	if s:
		s.focused = true
		s.queue_redraw()
		_tooltip(focus)


func _step(dir: String) -> void:
	var locs := _visible_locs()
	var current := _slot_node(focus) if focus != null else null
	if current == null:
		focus = locs[0] if not locs.is_empty() else null
		return
	var c0 := current.get_global_rect().get_center()
	var v: Vector2 = {"up": Vector2(0, -1), "down": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}[dir]
	var best = null
	var best_score := INF
	for loc in locs:
		if loc == focus:
			continue
		var c := _slot_node(loc).get_global_rect().get_center()
		var dx := c.x - c0.x
		var dy := c.y - c0.y
		var along := dx * v.x + dy * v.y
		if along <= 4:
			continue
		var across := absf(dx * v.y - dy * v.x)
		var score := along + across * 2.5
		if score < best_score:
			best_score = score
			best = loc
	if best != null:
		focus = best


## Called each frame while a panel is open and a gamepad is in use.
func gamepad(pad, dt: float) -> void:
	var B := Pad.BUTTONS
	var inv = game.inventory
	var dir: String = pad.nav_direction(dt)
	if dir != "":
		_step(dir)
	if pad.pressed(B.LB) or pad.pressed(B.RB):
		# cycle the highlight between the open windows and the spell bar
		var locs := _visible_locs()
		var groups := ["m:", "b:", "e:", "k:", "a:"].filter(func(p): return locs.any(func(l): return l.begins_with(p)))
		var cur := -1
		for i in groups.size():
			if focus != null and focus.begins_with(groups[i]):
				cur = i
		if not groups.is_empty():
			var next: String = groups[(cur + (groups.size() - 1 if pad.pressed(B.LB) else 1)) % groups.size()]
			if next == "e:":
				focus = "e:mainHand"
			else:
				for l in locs:
					if l.begins_with(next):
						focus = l
						break
	var bar = game.action_bar
	var is_spell := func(l): return l != null and (l.begins_with("a:") or l.begins_with("k:"))
	var has_thing := func(l: String) -> bool:
		if l.begins_with("a:"):
			return bar.slots[int(l.substr(2))] != null
		return l.begins_with("k:") or inv.get_at(l) != null
	var shop_loc := func(l): return l != null and (l.begins_with("m:") or l.begins_with("y:"))
	if pad.pressed(B.A) and shop_loc.call(focus) and carry == null:
		_shop_click(focus)
	elif pad.pressed(B.A) and focus != null and not shop_loc.call(focus):
		if carry != null:
			if carry != focus:
				dropOn(carry, focus, is_spell.call(focus) and focus.begins_with("a:"), true)
			carry = null
		elif has_thing.call(focus):
			carry = focus
		render()
	if pad.pressed(B.X) and focus != null and not is_spell.call(focus) and not shop_loc.call(focus):
		carry = null
		inv.use(focus)
	if pad.pressed(B.Y):
		var loc = carry if carry != null else focus
		carry = null
		if loc != null and loc.begins_with("a:"):
			bar.remove(int(loc.substr(2)))
		elif loc != null and not is_spell.call(loc) and inv.get_at(loc) != null and game.merchant.current != null:
			game.merchant.sell(loc)
		elif loc != null and not is_spell.call(loc) and inv.get_at(loc) != null:
			game.loot.drop_from_inventory(loc)
		render()
	if pad.pressed(B.B):
		if carry != null:
			carry = null
			render()
		else:
			close_all()
	_paint_focus()


## each frame: the paper doll, the corner tooltip, cooking's live state
func update(dt: float) -> void:
	if tip_cursor and tooltip.visible:
		_place_tip()
	if open.character and char_tab == "main" and preview.is_inside_tree():
		preview.render()
	# cooking changes as you walk to a fire or your bags fill: redraw when it does
	if open.cooking:
		_cook_clock -= dt
		if _cook_clock <= 0:
			_cook_clock = 0.25
			var sig := _cook_sig()
			if sig != _cook_last:
				_render_cooking()
				layout()
	_place_tip()
