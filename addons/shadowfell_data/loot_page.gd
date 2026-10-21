@tool
extends HSplitContainer
## Loot: who drops what. Pick an enemy (or boss) to give it a loot table and a
## skinning table, or pick a table to edit its drops.
##
## A table (data/loot_tables.json) has `always` drops (a hound's meat, every
## time) and random `drops`: some rolls, each with a chance of anything; then
## a rarity by weight, then an item from that rarity's list by weight.
##
## As in WoW, an enemy's own table holds what is its own (a ghoul's bones, a
## boss's blade), and the gear any mob of its level might carry comes from a
## world-drop band (levels 1 to 5, 6 to 10...), picked by its level. A ghoul
## in a level 12 zone is a level variant: its own entry, `base: ghoul`.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")
const IO := preload("json_io.gd")

var s: DataStore
var tree: Tree
var form: VBoxContainer
var current_table: Dictionary = {}
var current_enemy: Dictionary = {}
var new_ids := {}


func setup(store: DataStore) -> void:
	s = store
	name = "Loot tables"
	split_offset = 260
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var top := UI.hbox(left)
	top.add_child(UI.button("New table", func(): _new_table(null)))
	top.add_child(UI.button("New band", _new_band, "A new world-drop band: gear for every enemy of a level range"))
	top.add_child(UI.button("Delete", _delete_table, "Delete the chosen table or band"))
	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(_on_tree)
	left.add_child(tree)
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
	refresh_tree()
	_build()


func reload() -> void:
	new_ids.clear()
	current_table = {}
	current_enemy = {}
	refresh_tree()
	_build()


func refresh_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	var en := tree.create_item(root)
	en.set_text(0, "Enemies and bosses")
	en.set_selectable(0, false)
	# level variants sit under the enemy they are based on
	var rows := {}
	for e in s.enemies:
		var parent: TreeItem = rows.get(e.get("base"), en)
		var it := tree.create_item(parent)
		rows[e.id] = it
		var r := s.resolved(e)
		var tag := ""
		if r.get("type") == "boss":
			tag = "  [boss]"
		elif r.get("elite"):
			tag = "  [elite]"
		it.set_text(0, "%s  %s%s" % [r.get("name", e.id), _levels(r), tag])
		it.set_tooltip_text(0, "%s · drops %s" % [e.id, r.get("lootTable", "nothing")])
		it.set_metadata(0, {"enemy": e.id})
		if e == current_enemy:
			it.select(0)
	var tb := tree.create_item(root)
	tb.set_text(0, "Loot tables")
	tb.set_selectable(0, false)
	for t in s.loot_tables:
		var it := tree.create_item(tb)
		var users := s.users_of_table(t.id)
		it.set_text(0, t.id + ("" if users.size() else "  (unused)"))
		it.set_metadata(0, {"table": t.id})
		if t == current_table and current_enemy.is_empty():
			it.select(0)
	var wb := tree.create_item(root)
	wb.set_text(0, "World drops (by level)")
	wb.set_selectable(0, false)
	for b in s.world_drops:
		var it := tree.create_item(wb)
		it.set_text(0, "Levels %s–%s  (%s)" % [_n(b.get("minLevel", 0)), _n(b.get("maxLevel", 0)), b.id])
		it.set_metadata(0, {"table": b.id})
		if b == current_table and current_enemy.is_empty():
			it.select(0)


## "Lv 4" or "Lv 10–12"
static func _levels(e: Dictionary) -> String:
	var lo = e.get("level", 1)
	var hi = e.get("maxLevel", lo)
	return "Lv %s" % _n(lo) if hi <= lo else "Lv %s–%s" % [_n(lo), _n(hi)]


func _on_tree() -> void:
	var m = tree.get_selected().get_metadata(0)
	if m == null:
		return
	if m.has("enemy"):
		current_enemy = DataStore.find(s.enemies, m.enemy)
		current_table = DataStore.find(s.loot_tables, s.resolved(current_enemy).get("lootTable"))
	else:
		current_enemy = {}
		current_table = s.table_or_band(m.table)
	_build.call_deferred()


func show_table(id: String) -> void:
	current_enemy = {}
	current_table = s.table_or_band(id)
	refresh_tree()
	_build()


func _touch(rebuild := true) -> void:
	s.touch("loot_tables")
	if rebuild:
		_build.call_deferred()


# ------------------------------------------------------------------ form
func _build() -> void:
	UI.clear(form)
	if not current_enemy.is_empty():
		_enemy_header(current_enemy)
	if current_table.is_empty():
		if current_enemy.is_empty():
			UI.note(form, "Choose an enemy to set what it drops, or a loot table to edit it.")
		return
	_table_form(current_table)


func _enemy_header(e: Dictionary) -> void:
	var r := s.resolved(e)
	var title := Label.new()
	title.text = str(r.get("name", e.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	UI.note(form, "%s · %s%s · %s coins" % [e.id, _levels(r), " · " + str(r.type) if r.has("type") else "", _n(r.get("coins", 0))])
	if e.has("base"):
		UI.note(form, "A level variant of %s: it is the same enemy, with only what is set here changed." % s.resolved(DataStore.find(s.enemies, e.base)).get("name", e.base), Color("9fb6e8"))
	var g := UI.grid(form)
	if e.has("base"):
		UI.row(g, "Name", UI.line(str(r.get("name", "")), func(t):
			e.name = t
			s.touch("enemies")), "e.g. Barrow Ghoul")
	UI.row(g, "Level", UI.spin(r.get("level", 1), 1, 60, 1, func(v):
		e.level = v
		if e.get("maxLevel", v) < v:
			e.maxLevel = v
		_enemy_changed()), "Its health, damage and armour come from its level and type.")
	UI.row(g, "Up to level", UI.spin(r.get("maxLevel", r.get("level", 1)), 1, 60, 1, func(v):
		if v > s.resolved(e).get("level", 1):
			e.maxLevel = v
		elif e.has("base") and s.resolved(DataStore.find(s.enemies, e.base)).has("maxLevel"):
			e.maxLevel = s.resolved(e).get("level", 1)
		else:
			e.erase("maxLevel")
		_enemy_changed()), "Each spawn of it rolls a level from Level to this, as WoW's creatures do. Same as Level: always that level.")
	var tables := [[null, "(drops nothing of its own)"]]
	for t in s.loot_tables:
		tables.append([t.id, t.id])
	var h := HBoxContainer.new()
	h.add_child(UI.choice(tables, r.get("lootTable") if r.get("lootTable") != "" else null, func(v):
		_enemy_set(e, "lootTable", v)
		current_table = DataStore.find(s.loot_tables, v)
		_build.call_deferred()))
	h.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(UI.button("New table for it", func(): _new_table(e)))
	UI.row(g, "Own loot table", h, "What only it drops (its bones, a boss's own blade). Enemies of a kind can share one.")
	var skins := [[null, "(cannot be skinned)"]]
	for t in s.loot_tables:
		skins.append([t.id, t.id])
	UI.row(g, "Skinning table", UI.choice(skins, r.get("skin") if r.get("skin") != "" else null, func(v): _enemy_set(e, "skin", v)), "What Skinning its body gives.")
	UI.row(g, "World drops", UI.check(r.get("worldDrops", true) != false, "Also drops gear for its level (off for beasts)", func(on):
		if on and not s.resolved(DataStore.find(s.enemies, e.get("base", ""))).get("worldDrops", true) == false:
			e.erase("worldDrops")
		else:
			e.worldDrops = on
		_enemy_changed()))
	var band := s.band_for(e)
	var bands := PackedStringArray()
	for b in s.world_drops:
		if b.get("maxLevel", 0) >= r.get("level", 1) and b.get("minLevel", 0) <= r.get("maxLevel", r.get("level", 1)):
			bands.append("%s (levels %s–%s)" % [b.id, _n(b.minLevel), _n(b.maxLevel)])
	if r.get("worldDrops", true) == false:
		UI.note(form, "It drops no world gear.")
	elif bands.size():
		UI.note(form, "World gear from: " + ", ".join(bands) + ". The band is picked by its level, so nothing to set by hand.", Color("9fd08a"))
	else:
		UI.note(form, "No world-drop band covers its level yet: press New band.", Color("d0b070"))
	var vb := UI.hbox(form)
	vb.add_child(UI.button("Make a level variant…", func(): _new_variant(e), "A copy of this enemy for another zone (a level 12 ghoul): its own name, level and loot"))
	if current_table.is_empty():
		return
	var shared := s.users_of_table(current_table.id).filter(func(u): return u.get("enemy") != e)
	if shared.size():
		UI.note(form, "Its own table is shared: a change below also changes " + ", ".join(shared.map(func(u): return u.text)) + ".", Color("d0b070"))


func _enemy_changed() -> void:
	s.touch("enemies")
	refresh_tree()
	_build.call_deferred()


## Set an enemy's table. A variant that should drop nothing while its base
## does says so with "" (an empty name inherits nothing).
func _enemy_set(e: Dictionary, key: String, v) -> void:
	var from_base = s.resolved(DataStore.find(s.enemies, e.get("base", ""))).get(key) if e.has("base") else null
	if v == null:
		if from_base:
			e[key] = ""
		else:
			e.erase(key)
	elif v == from_base:
		e.erase(key)
	else:
		e[key] = v
	s.touch("enemies")
	refresh_tree()


func _new_variant(base: Dictionary) -> void:
	var r := s.resolved(base)
	var lv: int = int(r.get("level", 1)) + 5
	var root_id: String = base.get("base", base.id)
	var v := {"id": s.unique_id(s.enemies, "%s_%d" % [root_id, lv]), "base": root_id, "name": str(r.get("name", "")), "level": lv}
	s.enemies.insert(s.enemies.find(base) + 1, v)
	s.touch("enemies")
	current_enemy = v
	current_table = DataStore.find(s.loot_tables, s.resolved(v).get("lootTable"))
	refresh_tree()
	_build.call_deferred()


func _table_form(t: Dictionary) -> void:
	var band := s.is_band(t)
	UI.heading(form, ("World drops " if band else "Table ") + t.id)
	if band:
		UI.note(form, "Gear any enemy of these levels may carry, rolled as well as its own table (WoW's world drops). Beasts and others marked off do not roll it.")
		var bg := UI.grid(form)
		UI.row(bg, "From level", UI.spin(t.get("minLevel", 1), 1, 60, 1, func(v):
			t.minLevel = v
			_touch()
			refresh_tree()))
		UI.row(bg, "To level", UI.spin(t.get("maxLevel", 1), 1, 60, 1, func(v):
			t.maxLevel = v
			_touch()
			refresh_tree()))
	if new_ids.has(t.id):
		var g := UI.grid(form)
		var id_edit := UI.line(t.id, func(_x): pass)
		id_edit.text_submitted.connect(func(x): _rename_table(DataStore.slug(x)))
		id_edit.focus_exited.connect(func(): _rename_table(DataStore.slug(id_edit.text)))
		UI.row(g, "ID", id_edit, "Locked once saved.")
	if band:
		var mobs := s.band_users(t)
		UI.note(form, "Rolled by: " + (", ".join(mobs.map(func(e): return "%s (%s)" % [s.resolved(e).get("name", e.id), _levels(s.resolved(e))])) if mobs.size() else "no enemy yet."))
	else:
		var users := s.users_of_table(t.id)
		UI.note(form, "Used by: " + (", ".join(users.map(func(u): return u.text)) if users.size() else "nothing yet. Choose an enemy on the left and give it this table."))

	# ---- every time
	UI.heading(form, "Always drops")
	UI.note(form, "Dropped every time, a number between min and max (a hound's meat).")
	var always: Array = t.get("always", [])
	for a in always:
		var h := UI.hbox(form)
		h.add_child(UI.item_picker(s, a.get("item"), func(id):
			a.item = id
			_touch(false), func(d): return _can_drop(d, t)))
		h.add_child(_small_label("min"))
		h.add_child(UI.spin(a.get("min", 1), 0, 99, 1, func(v):
			a.min = v
			_touch(false)))
		h.add_child(_small_label("max"))
		h.add_child(UI.spin(a.get("max", 1), 0, 99, 1, func(v):
			a.max = v
			_touch(false)))
		h.add_child(UI.button("✕", func():
			always.erase(a)
			if always.is_empty():
				t.erase("always")
			_touch(), "Remove"))
	form.add_child(UI.button("Add an always-drop…", func():
		UI.pick_item(form, s, func(d): return _can_drop(d, t), func(id):
			if not t.has("always"):
				_insert_before(t, "always", [], "drops")
			t.always.append({"item": id, "min": 1, "max": 1})
			_touch())))

	if not band:
		_quest_drops(t)

	# ---- random drops
	UI.heading(form, "Random drops")
	if not t.has("drops"):
		form.add_child(UI.button("Add random drops", func():
			t.drops = {"rolls": 1, "chance": 0.3, "rarity": {}, "items": {}}
			_touch()))
		return
	var drops: Dictionary = t.drops
	var g := UI.grid(form)
	UI.row(g, "Rolls", UI.spin(drops.get("rolls", 1), 1, 10, 1, func(v):
		drops.rolls = v
		_touch()), "How many times it rolls for a drop each kill.")
	UI.row(g, "Chance of a drop", UI.spin(drops.get("chance", 0) * 100, 0, 100, 0.5, func(v):
		drops.chance = snappedf(v / 100.0, 0.0001)
		_touch(), " %"), "Each roll's chance of dropping anything at all.")
	UI.note(form, "Then a rarity, by weight (0 = never):")
	var weights: Dictionary = drops.get("rarity", {})
	drops.rarity = weights
	var lists: Dictionary = drops.get("items", {})
	drops.items = lists
	var total := 0.0
	for w in weights.values():
		total += w
	var rg := GridContainer.new()
	rg.columns = 3
	rg.add_theme_constant_override("h_separation", 12)
	form.add_child(rg)
	for r in s.drop_rarities():
		var rid: String = r.id
		var l := Label.new()
		l.text = r.name
		l.add_theme_color_override("font_color", Color(r.colour))
		rg.add_child(l)
		rg.add_child(UI.spin(weights.get(rid, 0), 0, 1000, 1, func(v):
			if v > 0:
				weights[rid] = v
				if not lists.has(rid):
					lists[rid] = []
			else:
				weights.erase(rid)
				if lists.get(rid, []).is_empty():
					lists.erase(rid)
			_reorder(weights)
			_reorder(lists)
			_touch()))
		rg.add_child(_small_label("%.0f%% of drops" % (weights.get(rid, 0) / total * 100) if total > 0 and weights.has(rid) else ""))

	for r in s.drop_rarities():
		var rid: String = r.id
		if not weights.has(rid) and not lists.has(rid):
			continue
		var head := Label.new()
		head.text = "%s items" % r.name
		head.add_theme_color_override("font_color", Color(r.colour))
		head.add_theme_font_size_override("font_size", 15)
		form.add_child(head)
		if rid == "enhanced":
			UI.note(form, "Common gear listed here drops with a suffix (its magical property).")
		var entries: Array = lists.get(rid, [])
		for e in entries:
			var h := UI.hbox(form)
			h.add_child(UI.item_picker(s, e.get("item"), func(id):
				e.item = id
				_touch(false), func(d): return _fits(d, rid) and _can_drop(d, t)))
			h.add_child(_small_label("weight"))
			h.add_child(UI.spin(e.get("weight", 1), 1, 1000, 1, func(v):
				e.weight = v
				_touch()))
			h.add_child(_small_label("%.2f%% a kill" % (s.entry_chance(t, rid, e) * 100)))
			h.add_child(UI.button("✕", func():
				entries.erase(e)
				_touch(), "Remove"))
		form.add_child(UI.button("Add %s item…" % r.name.to_lower(), func():
			UI.pick_item(form, s, func(d): return _fits(d, rid) and _can_drop(d, t), func(id):
				if not lists.has(rid):
					lists[rid] = entries
				entries.append({"item": id, "weight": 1})
				if not weights.has(rid):
					weights[rid] = 5
				_reorder(weights)
				_reorder(lists)
				_touch())))
	var off := UI.hbox(form)
	off.add_child(UI.button("Remove random drops", func():
		t.erase("drops")
		_touch()))


## an item may sit under its own rarity; common gear also under enhanced
func _fits(d: Dictionary, rarity: String) -> bool:
	return d.get("rarity") == rarity or (rarity == "enhanced" and d.get("rarity") == "common" and DataStore.GEAR.has(d.get("kind")))


func _can_drop(d: Dictionary, t: Dictionary) -> bool:
	return not d.get("quest", false) and (not d.has("reservedFor") or d.reservedFor.has(t.id))


## keep rarities lowest first, as the file lists them
func _reorder(dict: Dictionary) -> void:
	var copy := dict.duplicate()
	dict.clear()
	for r in s.rarities:
		if copy.has(r.id):
			dict[r.id] = copy[r.id]
	for k in copy:
		if not dict.has(k):
			dict[k] = copy[k]


static func _insert_before(d: Dictionary, key: String, value, before: String) -> void:
	var copy := d.duplicate()
	d.clear()
	for k in copy:
		if k == before:
			d[key] = value
		d[k] = copy[k]
	if not d.has(key):
		d[key] = value


static func _n(v) -> String:
	return IO.number(v) if v is float or v is int else str(v)


static func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return l


# ------------------------------------------------------------------ tables
func _new_table(for_enemy) -> void:
	var base := DataStore.slug(for_enemy.id) if for_enemy is Dictionary else "new_table"
	var t := {"id": s.unique_table_id(base), "drops": {"rolls": 1, "chance": 0.3, "rarity": {"common": 1}, "items": {"common": []}}}
	s.loot_tables.append(t)
	new_ids[t.id] = true
	current_table = t
	if for_enemy is Dictionary:
		_enemy_set(for_enemy, "lootTable", t.id)
	else:
		current_enemy = {}
	_touch()
	refresh_tree()


func _rename_table(id: String) -> void:
	var t := current_table
	if not new_ids.has(t.get("id")) or id == "" or id == t.id:
		return
	id = s.unique_table_id(id)
	for u in s.users_of_table(t.id):
		if not u.get("own", false):
			continue
		if u.kind == "loot":
			u.enemy.lootTable = id
		elif u.kind == "skin":
			u.enemy.skin = id
		s.touch("enemies")
	new_ids.erase(t.id)
	new_ids[id] = true
	t.id = id
	_touch()
	refresh_tree()


func _delete_table() -> void:
	if current_table.is_empty():
		return
	var users := [] if s.is_band(current_table) else s.users_of_table(current_table.id)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete loot table"
	dlg.dialog_text = "Delete loot table %s?" % current_table.id
	if users.size():
		dlg.dialog_text += "\n\nIt is used by: %s.\nThey will drop nothing until given another table." % ", ".join(users.map(func(u): return u.text))
	dlg.confirmed.connect(func():
		for u in users:
			if not u.get("own", false):
				continue
			if u.kind == "loot":
				u.enemy.erase("lootTable")
				s.touch("enemies")
			elif u.kind == "skin":
				u.enemy.erase("skin")
				s.touch("enemies")
		for d in s.items:
			if d.has("reservedFor") and d.reservedFor.has(current_table.id):
				d.reservedFor.erase(current_table.id)
				if d.reservedFor.is_empty():
					d.erase("reservedFor")
				s.touch("items")
		s.loot_tables.erase(current_table)
		s.world_drops.erase(current_table)
		current_table = {}
		_touch()
		refresh_tree()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _new_band() -> void:
	var lo := 1
	for b in s.world_drops:
		lo = maxi(lo, int(b.get("maxLevel", 0)) + 1)
	var b := {"id": s.unique_table_id("world_%d_%d" % [lo, lo + 4]), "minLevel": lo, "maxLevel": lo + 4, "drops": {"rolls": 1, "chance": 0.25, "rarity": {"common": 60, "enhanced": 36, "rare": 4}, "items": {"common": [], "enhanced": [], "rare": []}}}
	s.world_drops.append(b)
	new_ids[b.id] = true
	current_enemy = {}
	current_table = b
	_touch()
	refresh_tree()


## Quest drops (WoW style): an item that drops only while one of the player's
## quests still needs it, at its own chance, whatever else the table rolls.
func _quest_drops(t: Dictionary) -> void:
	UI.heading(form, "Quest drops")
	UI.note(form, "Drops only while the player has the quest and still needs the item (a consignment note on a bandit). The item must be one of the quest's things to collect.")
	var list: Array = t.get("questDrops", [])
	var quests := []
	for q in s.quests:
		if _collects(q).size():
			quests.append([q.id, str(q.get("name", q.id))])
	for qd in list:
		var h := UI.hbox(form)
		var q := DataStore.find(s.quests, qd.get("quest"))
		var qp := UI.choice(quests, qd.get("quest"), func(v):
			qd.quest = v
			var c := _collects(DataStore.find(s.quests, v))
			if not c.has(qd.get("item")) and c.size():
				qd.item = c[0]
			_touch())
		qp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(qp)
		var items := []
		for id in _collects(q):
			items.append([id, s.item(id).get("name", id)])
		var ip := UI.choice(items, qd.get("item"), func(v):
			qd.item = v
			_touch(false))
		ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(ip)
		h.add_child(UI.spin(qd.get("chance", 0.4) * 100, 1, 100, 1, func(v):
			qd.chance = snappedf(v / 100.0, 0.0001)
			_touch(false), " %"))
		h.add_child(UI.button("✕", func():
			list.erase(qd)
			if list.is_empty():
				t.erase("questDrops")
			_touch(), "Remove"))
	if quests.is_empty():
		return
	form.add_child(UI.button("Add a quest drop", func():
		var q := DataStore.find(s.quests, quests[0][0])
		if not t.has("questDrops"):
			_insert_before(t, "questDrops", list, "always" if t.has("always") else "drops")
		list.append({"item": _collects(q)[0], "quest": q.id, "chance": 0.4})
		_touch()))


## the items a quest asks the player to collect
static func _collects(q: Dictionary) -> Array:
	var out := []
	for o in q.get("objectives", []):
		if o.get("type") == "collect" and not out.has(o.get("target")):
			out.append(o.target)
	return out
