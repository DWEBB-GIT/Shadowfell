@tool
extends HSplitContainer
## Items: the list on the left, the chosen item's form on the right.
## New item: pick what it is (one-hand weapon > sword), name it, then fill in
## rarity, stats, effects, sprite and model.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")
const Preview := preload("model_preview.gd")

## the order keys are written in, so an edited item reads like the others
const KEY_ORDER := ["id", "name", "kind", "rarity", "quest", "slot", "weaponType", "itemLevel", "speed", "range", "armourType", "statSplit", "stats", "damage", "use", "reservedFor"]
const KEY_ORDER_END := ["stack", "buyCount", "price", "model", "icon", "sprite", "description"]

## what "New item" offers: label -> the start of the record
const NEW_TYPES := [
	["One-hand weapon", {"kind": "weapon", "slot": "oneHand"}],
	["Main-hand weapon", {"kind": "weapon", "slot": "mainHand"}],
	["Ranged weapon", {"kind": "weapon", "slot": "ranged", "weaponType": "bow"}],
	["Armour", {"kind": "armor"}],
	["Shield", {"kind": "shield", "slot": "offHand"}],
	["Jewellery", {"kind": "jewellery"}],
	["Potion (heals at once)", {"kind": "consumable", "use": {"heal": 40}}],
	["Food (heals over time)", {"kind": "consumable", "use": {"food": {"heal": 60, "seconds": 15}}}],
	["Material", {"kind": "material"}],
	["Junk", {"kind": "junk", "rarity": "junk"}],
	["Quest item", {"kind": "material", "rarity": "quest", "quest": true}],
	["Tool", {"kind": "tool"}],
	["Bag", {"kind": "bag", "bagSlots": 6}],
	["Ammo", {"kind": "ammo", "ammoDps": 1}],
	["Torch", {"kind": "torch", "slot": "offHand", "light": 8}],
	["Key", {"kind": "key"}],
	["Document", {"kind": "document"}],
]

var s: DataStore
var list: ItemList
var search: LineEdit
var kind_filter: OptionButton
var form: VBoxContainer
var current: Dictionary = {}
var new_ids := {} ## items made since the last save: their id can still change
var preview: Preview
var _file_dialog: FileDialog


func setup(store: DataStore) -> void:
	s = store
	name = "Items"
	split_offset = 260
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var top := UI.hbox(left)
	top.add_child(UI.button("New item", _new_item_dialog, "Make a new item"))
	top.add_child(UI.button("Duplicate", _duplicate, "Copy the chosen item"))
	top.add_child(UI.button("Delete", _delete, "Delete the chosen item"))
	search = LineEdit.new()
	search.placeholder_text = "Search"
	search.text_changed.connect(func(_t): refresh_list())
	left.add_child(search)
	var kinds := [[null, "All types"]]
	for k in DataStore.KINDS:
		kinds.append([k, DataStore.KIND_NAMES[k]])
	kind_filter = UI.choice(kinds, null, func(_k): refresh_list())
	left.add_child(kind_filter)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(i): select(list.get_item_metadata(i)))
	left.add_child(list)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(pad)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(form)
	refresh_list()
	_build_form()


func reload() -> void:
	new_ids.clear()
	var id = current.get("id")
	current = {}
	refresh_list()
	if id != null:
		select(id)
	else:
		_build_form()


func refresh_list() -> void:
	list.clear()
	var q := search.text.to_lower()
	var k = kind_filter.get_item_metadata(kind_filter.selected)
	for d in s.items:
		if k != null and d.get("kind") != k:
			continue
		if q != "" and not (str(d.get("name", "")).to_lower().contains(q) or str(d.id).contains(q)):
			continue
		var i := list.add_item(str(d.get("name", d.id)))
		list.set_item_metadata(i, d.id)
		list.set_item_custom_fg_color(i, s.rarity_colour(d.get("rarity")))
		list.set_item_tooltip(i, "%s · %s" % [d.id, DataStore.KIND_NAMES.get(d.get("kind"), "")])
		if d == current:
			list.select(i)


func select(id) -> void:
	current = s.item(id)
	for i in list.item_count:
		if list.get_item_metadata(i) == id:
			list.select(i)
			list.ensure_current_is_visible()
	_build_form()


## an edit to the chosen item: tidy its keys, mark items.json changed
func _changed(rebuild := false) -> void:
	_tidy(current)
	s.touch("items")
	if rebuild:
		_build_form.call_deferred()


func _put(key: String, value, rebuild := false) -> void:
	if value == null or (value is String and value == "" and key != "description"):
		current.erase(key)
	else:
		current[key] = value
	_changed(rebuild)


static func _tidy(d: Dictionary) -> void:
	var copy := d.duplicate()
	d.clear()
	for k in KEY_ORDER:
		if copy.has(k):
			d[k] = copy[k]
	for k in copy:
		if not d.has(k) and not KEY_ORDER_END.has(k):
			d[k] = copy[k]
	for k in KEY_ORDER_END:
		if copy.has(k):
			d[k] = copy[k]


# ------------------------------------------------------------------ form
func _build_form() -> void:
	UI.clear(form)
	preview = null
	if current.is_empty():
		UI.note(form, "Choose an item on the left, or press New item.")
		return
	var d := current
	var kind = d.get("kind")
	var title := Label.new()
	title.text = str(d.get("name", d.id))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", s.rarity_colour(d.get("rarity")))
	form.add_child(title)

	# ---- what it is
	UI.heading(form, "Item")
	var g := UI.grid(form)
	UI.row(g, "Name", UI.line(str(d.get("name", "")), func(t):
		d.name = t
		title.text = t
		if new_ids.has(d.id):
			_rename_new(DataStore.slug(t))
		_changed()
		_list_text()))
	var id_edit := LineEdit.new()
	id_edit.text = d.id
	id_edit.editable = new_ids.has(d.id)
	id_edit.tooltip_text = "Saves, shops, quests and loot tables use the id, so it is locked once saved." if not id_edit.editable else "Made from the name until you save. Locked after that."
	id_edit.text_submitted.connect(func(t): _rename_new(DataStore.slug(t)))
	id_edit.focus_exited.connect(func(): _rename_new(DataStore.slug(id_edit.text)))
	UI.row(g, "ID", id_edit)
	var kinds := []
	for k in DataStore.KINDS:
		kinds.append([k, DataStore.KIND_NAMES[k]])
	UI.row(g, "Type", UI.choice(kinds, kind, func(k): _set_kind(k)))
	if DataStore.KIND_SLOTS.has(kind):
		var slots := []
		for sl in DataStore.KIND_SLOTS[kind]:
			slots.append([sl, DataStore.SLOTS[sl]])
		UI.row(g, "Slot", UI.choice(slots, d.get("slot"), func(v):
			_put("slot", v)
			if v == "ranged" and not d.has("range"):
				_put("range", 30.0)
			elif v != "ranged":
				d.erase("range")
			_changed(true)), "One-hand weapons go in either hand (the off hand only for classes that dual wield).")
	if kind == "weapon":
		var types := [[null, "(none)"]]
		for t in _weapon_types():
			types.append([t, t.capitalize()])
		UI.row(g, "Weapon type", UI.choice(types, d.get("weaponType"), func(v): _put("weaponType", v)), "Classes can be barred from a weapon type (archetypes.json bannedWeaponTypes).")
	if kind == "armor":
		var types := []
		for a in s.armour_types:
			types.append([a.id, a.name])
		UI.row(g, "Armour type", UI.choice(types, d.get("armourType"), func(v): _put("armourType", v, true)))
	var rars := []
	for r in s.rarities:
		rars.append([r.id, r.name])
	var rar := UI.choice(rars, d.get("rarity"), func(v):
		_put("rarity", v, true)
		_list_text())
	for i in rar.item_count:
		rar.set_item_icon(i, _swatch(s.rarity_colour(rar.get_item_metadata(i))))
	UI.row(g, "Rarity", rar, str(s.rarity(d.get("rarity")).get("desc", "")))
	UI.row(g, "Quest item", UI.check(d.get("quest", false), "Only for a quest (cannot be sold or dropped as loot)", func(on):
		_put("quest", true if on else null)
		if on:
			_put("rarity", "quest")
		_changed(true)))
	if DataStore.GEAR.has(kind) or kind == "jewellery":
		UI.row(g, "Item level", UI.spin(d.get("itemLevel", 1), 1, 60, 1, func(v): _put("itemLevel", v, true)), "Its armour, damage and stat points all come from this.")
	if kind == "weapon":
		UI.row(g, "Swing speed", UI.spin(d.get("speed", 2.4), 1, 5, 0.1, func(v): _put("speed", v, true), " s"), "Seconds a swing. Slower weapons hit harder; damage a second is the same.")
	UI.row(g, "Stack size", UI.spin(d.get("stack", 1), 1, 200, 1, func(v): _put("stack", v)))
	UI.row(g, "Price", UI.spin(d.get("price", 0), 0, 100000, 1, func(v): _put("price", v), " coins"), "What a merchant charges. They buy it back for about a quarter.")
	var desc := TextEdit.new()
	desc.text = str(d.get("description", ""))
	desc.custom_minimum_size.y = 70
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.text_changed.connect(func(): _put("description", desc.text))
	UI.row(g, "Description", desc)

	if DataStore.GEAR.has(kind) or kind == "jewellery":
		_stats_section(d)
	if kind == "consumable" or d.has("use"):
		_effects_section(d)
	_extras_section(d)
	_art_section(d)
	_loot_section(d)


func _set_kind(k: String) -> void:
	var d := current
	d.kind = k
	var slots: Array = DataStore.KIND_SLOTS.get(k, [])
	if slots.is_empty():
		d.erase("slot")
	elif not slots.has(d.get("slot")):
		d.slot = slots[0]
	if k != "weapon":
		for key in ["weaponType", "speed", "range"]:
			d.erase(key)
	elif not d.has("speed"):
		d.speed = 2.4
	if k != "armor":
		d.erase("armourType")
	elif not d.has("armourType"):
		d.armourType = "cloth"
	if DataStore.GEAR.has(k) or k == "jewellery":
		if not d.has("itemLevel"):
			d.itemLevel = 1
	else:
		d.erase("itemLevel")
		d.erase("statSplit")
	_changed(true)
	_list_text()


func _weapon_types() -> Array:
	var out: Array = DataStore.WEAPON_TYPES.duplicate()
	for d in s.items:
		if d.has("weaponType") and not out.has(d.weaponType):
			out.append(d.weaponType)
	return out


func _stats_section(d: Dictionary) -> void:
	UI.heading(form, "Stats")
	UI.note(form, "Armour, weapon damage and stat points come from the item level, slot and rarity (no hand-typed numbers). Give each stat a share of the points: 1 and 1 splits them evenly. Common and junk gear has no points to split.")
	var g := UI.grid(form)
	var split: Dictionary = d.get("statSplit", {})
	for k in DataStore.STAT_KEYS:
		UI.row(g, k.capitalize(), UI.spin(split.get(k, 0), 0, 10, 0.5, func(v):
			var sp: Dictionary = d.get("statSplit", {})
			if v > 0:
				sp[k] = v
			else:
				sp.erase(k)
			d.statSplit = sp
			if sp.is_empty():
				d.erase("statSplit")
			_changed()
			_show_numbers(d)))
	var out := Label.new()
	out.name = "Numbers"
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.add_theme_color_override("font_color", Color("9fd08a"))
	form.add_child(out)
	_show_numbers(d)
	if d.has("stats"):
		UI.note(form, "This item also states fixed stats, which win over the worked-out ones: %s" % JSON.stringify(d.stats), Color("d0b070"))


## what the item gives at its level, worked out as the game does
func _show_numbers(d: Dictionary) -> void:
	var out := form.get_node_or_null("Numbers") as Label
	if out == null:
		return
	var sc := Scaling.scaled_item(d)
	var parts := PackedStringArray()
	if sc.get("damage") is Array:
		var dmg: Array = sc.damage
		parts.append("Damage %d–%d every %.1f s (%.1f a second)" % [dmg[0], dmg[1], d.get("speed", 1), (dmg[0] + dmg[1]) / 2.0 / d.get("speed", 1)])
	for k in sc.get("stats", {}):
		parts.append("%s%d %s" % ["" if k in ["armour"] else "+", sc.stats[k], k.capitalize() + ("%" if k in ["block", "haste"] else "")])
	out.text = "In game: " + (", ".join(parts) if parts.size() else "nothing yet")


func _effects_section(d: Dictionary) -> void:
	UI.heading(form, "Effects")
	var use: Dictionary = d.get("use", {})
	var mode := "food" if use.has("food") else "heal" if use.has("heal") else "none"
	var g := UI.grid(form)
	UI.row(g, "When used", UI.choice([["none", "Nothing"], ["heal", "Heals at once"], ["food", "Food: heals over time while sitting"]], mode, func(m):
		match m:
			"none": d.erase("use")
			"heal": d.use = {"heal": 40}
			"food": d.use = {"food": {"heal": 60, "seconds": 15}}
		_changed(true)))
	if mode == "heal":
		UI.row(g, "Heals", UI.spin(use.heal, 1, 100000, 1, func(v):
			d.use.heal = v
			_changed()))
	elif mode == "food":
		UI.row(g, "Heals", UI.spin(use.food.heal, 1, 100000, 1, func(v):
			d.use.food.heal = v
			_changed()), "Health over the whole time. Eating 10 seconds makes you Well Fed.")
		UI.row(g, "Over", UI.spin(use.food.seconds, 1, 120, 1, func(v):
			d.use.food.seconds = v
			_changed(), " s"))


func _extras_section(d: Dictionary) -> void:
	var keys := []
	for k in DataStore.EXTRAS:
		if DataStore.EXTRAS[k][2].has(d.get("kind")) or d.has(k):
			if k == "range" and d.get("slot") != "ranged" and not d.has(k):
				continue
			keys.append(k)
	if keys.is_empty():
		return
	UI.heading(form, "More")
	var g := UI.grid(form)
	for k in keys:
		var e: Array = DataStore.EXTRAS[k]
		if e[1] == "bool":
			UI.row(g, e[0], UI.check(d.get(k, false), "", func(on): _put(k, true if on else null)))
		else:
			UI.row(g, e[0], UI.spin(d.get(k, 0), 0, 1000, 1 if e[1] == "int" else 0.1, func(v): _put(k, v if v > 0 else null)), "0 means it has none")


# ------------------------------------------------------------------ art
func _art_section(d: Dictionary) -> void:
	UI.heading(form, "Sprite and model")
	var h := UI.hbox(form)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var g := UI.grid(left)
	var models := []
	for m in s.models:
		models.append([m, m])
	UI.row(g, "Model", UI.choice(models, d.get("model"), func(m): _set_model(m)), "The 3D model it is in the world (and in your hand). From assets/models.")
	var mb := UI.hbox(left)
	mb.add_child(UI.button("Import model (.glb)…", func(): _pick_file(["*.glb ; Blender glTF"], _import_model), "Copies a .glb into assets/models and uses it"))
	UI.row(UI.grid(left), "Sprite", _sprite_label(d))
	var sb := UI.hbox(left)
	sb.add_child(UI.button("Choose sprite (.png)…", func(): _pick_file(["*.png ; PNG image"], _import_sprite), "Copies a square .png into assets/icons and uses it as the item's icon"))
	if d.has("sprite"):
		sb.add_child(UI.button("Remove sprite", func(): _put("sprite", null, true)))
	UI.note(left, "Without a sprite, its icon is a picture of its model.")
	var pics := VBoxContainer.new()
	h.add_child(pics)
	if d.has("sprite") and ResourceLoader.exists("%s/%s.png" % [DataStore.SPRITES_DIR, d.sprite]):
		var tr := TextureRect.new()
		tr.texture = load("%s/%s.png" % [DataStore.SPRITES_DIR, d.sprite])
		tr.custom_minimum_size = Vector2(64, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pics.add_child(tr)
	preview = Preview.new()
	preview.custom_minimum_size = Vector2(200, 200)
	pics.add_child(preview)
	preview.show_model(d.get("model", ""))


func _sprite_label(d: Dictionary) -> Label:
	var l := Label.new()
	l.text = "%s.png" % d.sprite if d.has("sprite") else "(none: the model's picture)"
	return l


func _set_model(m: String) -> void:
	var d := current
	# the icon follows the model unless it was set apart
	if d.get("icon") == d.get("model") or not d.has("icon"):
		d.icon = m
	d.model = m
	_changed(true)


func _pick_file(filters: Array, then: Callable) -> void:
	if _file_dialog:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(filters)
	_file_dialog.file_selected.connect(then)
	add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


## copy a file from anywhere on disk into the project under `dir`, named for
## the item; returns the name used (no extension), or "" if it failed
func _copy_in(from: String, dir: String, ext: String) -> String:
	var res := "%s/%s.%s" % [dir, current.id, ext]
	var to := ProjectSettings.globalize_path(res)
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if ProjectSettings.globalize_path(from) != to:
		var err := DirAccess.copy_absolute(from, to)
		if err != OK:
			push_error("Game Data: could not copy %s (%s)" % [from, error_string(err)])
			return ""
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		fs.update_file(res)
		fs.reimport_files(PackedStringArray([res]))
	s.scan_art()
	return current.id


func _import_model(path: String) -> void:
	var m := _copy_in(path, DataStore.MODELS_DIR, "glb")
	if m != "":
		_set_model(m)


func _import_sprite(path: String) -> void:
	var sp := _copy_in(path, DataStore.SPRITES_DIR, "png")
	if sp != "":
		_put("sprite", sp, true)


# ------------------------------------------------------------------ loot
func _loot_section(d: Dictionary) -> void:
	UI.heading(form, "Loot")
	var where := PackedStringArray()
	for t in s.loot_tables:
		for a in t.get("always", []):
			if a.get("item") == d.id:
				where.append("%s: always, %d to %d" % [t.id, a.min, a.max])
		for r in t.get("drops", {}).get("items", {}):
			for e in t.drops.items[r]:
				if e.get("item") == d.id:
					where.append("%s: %.1f%% a kill (as %s)" % [t.id, s.entry_chance(t, r, e) * 100, r])
	UI.note(form, "Drops from: " + (", ".join(where) if where.size() else "nothing yet. Add it to a loot table on the Loot tab."))
	if d.get("quest"):
		return
	var h := UI.hbox(form)
	var tables := []
	for t in s.loot_tables:
		tables.append([t.id, t.id])
	var pick := UI.choice(tables, null, func(_v): pass)
	h.add_child(pick)
	h.add_child(UI.button("Add to this loot table", func():
		if pick.selected >= 0:
			_add_to_table(pick.get_item_metadata(pick.selected))))
	UI.note(form, "Kept for (only these tables may drop it, e.g. a boss's own weapon):")
	var flow := HFlowContainer.new()
	form.add_child(flow)
	for t in s.loot_tables:
		var tid: String = t.id
		flow.add_child(UI.check(d.get("reservedFor", []).has(tid), tid, func(on):
			var rf: Array = d.get("reservedFor", [])
			if on and not rf.has(tid):
				rf.append(tid)
			elif not on:
				rf.erase(tid)
			_put("reservedFor", rf if rf.size() else null)))


## put the item in a table's list for its rarity (common gear can also drop
## as enhanced, with a suffix: it goes under its own rarity here)
func _add_to_table(tid: String) -> void:
	var t := DataStore.find(s.loot_tables, tid)
	var r: String = current.get("rarity", "common")
	if s.rarity(r).get("drops", true) == false:
		return
	var drops: Dictionary = t.get("drops", {"rolls": 1, "chance": 0.3, "rarity": {}, "items": {}})
	t.drops = drops
	if not drops.rarity.has(r):
		drops.rarity[r] = 5
	var lst: Array = drops.items.get(r, [])
	drops.items[r] = lst
	for e in lst:
		if e.item == current.id:
			return
	lst.append({"item": current.id, "weight": 1})
	s.touch("loot_tables")
	_build_form()


# ------------------------------------------------------------------ new, copy, delete
func _new_item_dialog() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "New item"
	dlg.ok_button_text = "Create"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	dlg.add_child(box)
	var g := UI.grid(box)
	var state := {"type": 0, "sub": null, "rarity": "common", "name": ""}
	var types := []
	for i in NEW_TYPES.size():
		types.append([i, NEW_TYPES[i][0]])
	var sub_row := OptionButton.new()
	var sub_label := Label.new()
	var fill_sub := func():
		sub_row.clear()
		var start: Dictionary = NEW_TYPES[state.type][1]
		var opts := []
		if start.kind == "weapon" and not start.has("weaponType"):
			sub_label.text = "Weapon type"
			for t in _weapon_types():
				if t != "bow":
					opts.append([t, t.capitalize()])
		elif not start.has("slot") and DataStore.KIND_SLOTS.has(start.kind):
			sub_label.text = "Slot"
			for sl in DataStore.KIND_SLOTS[start.kind]:
				opts.append([sl, DataStore.SLOTS[sl]])
		elif start.kind == "armor" or start.kind == "weapon":
			pass
		for i in opts.size():
			sub_row.add_item(opts[i][1])
			sub_row.set_item_metadata(i, opts[i][0])
		sub_row.visible = opts.size() > 0
		sub_label.visible = sub_row.visible
		state.sub = opts[0][0] if opts.size() else null
	g.add_child(Label.new())
	g.get_child(-1).text = "What is it?"
	var type_pick := UI.choice(types, 0, func(i):
		state.type = i
		fill_sub.call())
	type_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(type_pick)
	g.add_child(sub_label)
	sub_row.item_selected.connect(func(i): state.sub = sub_row.get_item_metadata(i))
	g.add_child(sub_row)
	var name_edit := UI.row(g, "Name", UI.line("", func(t): state.name = t)) as LineEdit
	name_edit.placeholder_text = "e.g. Hunter's Sword"
	var rars := []
	for r in s.rarities:
		rars.append([r.id, r.name])
	var rp := UI.choice(rars, "common", func(v): state.rarity = v)
	for i in rp.item_count:
		rp.set_item_icon(i, _swatch(s.rarity_colour(rp.get_item_metadata(i))))
	UI.row(g, "Rarity", rp)
	fill_sub.call()
	dlg.confirmed.connect(func():
		_create(NEW_TYPES[state.type][1], state.sub, state.name.strip_edges(), state.rarity)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	name_edit.grab_focus()


func _create(start: Dictionary, sub, item_name: String, rarity: String) -> void:
	if item_name == "":
		item_name = "New item"
	var d := {"id": s.unique_id(s.items, DataStore.slug(item_name)), "name": item_name}
	for k in start:
		d[k] = start[k].duplicate(true) if start[k] is Dictionary else start[k]
	if not start.has("rarity"):
		d.rarity = rarity
	var kind: String = d.kind
	if kind == "weapon" and not d.has("weaponType") and sub != null:
		d.weaponType = sub
	elif sub != null and DataStore.KIND_SLOTS.has(kind):
		d.slot = sub
	if DataStore.GEAR.has(kind) or kind == "jewellery":
		d.itemLevel = 1
	if kind == "weapon":
		var wd: Dictionary = DataStore.WEAPON_DEFAULTS.get(d.get("weaponType"), {"speed": 2.4, "model": "worn_sword"})
		d.speed = wd.speed
		d.model = wd.model
		if d.slot == "ranged":
			d.range = 30.0
	if kind == "armor":
		d.armourType = "cloth"
	d.stack = 20 if kind in ["consumable", "material", "junk", "ammo"] else 1
	d.price = 1 if kind == "junk" else 10
	if not d.has("model"):
		d.model = _stand_in_model(d)
	d.icon = d.model
	d.description = ""
	_tidy(d)
	s.items.append(d)
	new_ids[d.id] = true
	s.touch("items")
	search.text = ""
	kind_filter.select(0)
	refresh_list()
	select(d.id)


## a model already used by an item like this one, until it has its own
func _stand_in_model(d: Dictionary) -> String:
	for o in s.items:
		if o.get("kind") == d.kind and o.get("slot") == d.get("slot") and o.has("model"):
			return o.model
	for o in s.items:
		if o.get("kind") == d.kind and o.has("model"):
			return o.model
	return "coin_purse" if s.models.has("coin_purse") else (s.models[0] if s.models.size() else "")


func _rename_new(id: String) -> void:
	var d := current
	if not new_ids.has(d.get("id")) or id == "" or id == d.id:
		return
	id = s.unique_id(s.items, id)
	new_ids.erase(d.id)
	new_ids[id] = true
	d.id = id
	_changed()
	_list_text()


func _list_text() -> void:
	for i in list.item_count:
		var d := s.item(list.get_item_metadata(i))
		if d == current or d.is_empty():
			list.set_item_text(i, str(current.get("name", current.get("id"))))
			list.set_item_metadata(i, current.id)
			list.set_item_custom_fg_color(i, s.rarity_colour(current.get("rarity")))


func _duplicate() -> void:
	if current.is_empty():
		return
	var d := current.duplicate(true)
	d.name = str(current.get("name", "")) + " copy"
	d.id = s.unique_id(s.items, current.id + "_copy")
	d.erase("reservedFor")
	s.items.insert(s.items.find(current) + 1, d)
	new_ids[d.id] = true
	s.touch("items")
	refresh_list()
	select(d.id)


func _delete() -> void:
	if current.is_empty():
		return
	var uses := s.uses_of_item(current.id)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete item"
	dlg.dialog_text = "Delete %s (%s)?" % [current.get("name", ""), current.id]
	if uses.size():
		dlg.dialog_text += "\n\nIt is still named in: %s.\nRemove it there too, or the checks will fail." % ", ".join(uses)
	dlg.confirmed.connect(func():
		s.items.erase(current)
		new_ids.erase(current.id)
		current = {}
		s.touch("items")
		refresh_list()
		_build_form()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


static func _swatch(c: Color) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)
