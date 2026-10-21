@tool
extends HSplitContainer
## Rewards: what a quest gives when handed in, and what is inside a chest.
## Set items here; objectives and dialogue stay in the quest editor.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

var s: DataStore
var tree: Tree
var form: VBoxContainer
var current: Dictionary = {}
var current_kind := "" ## quest or chest


func setup(store: DataStore) -> void:
	s = store
	name = "Quest and chest rewards"
	split_offset = 260
	tree = Tree.new()
	tree.hide_root = true
	tree.custom_minimum_size.x = 240
	tree.item_selected.connect(_on_tree)
	add_child(tree)
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
	current = {}
	refresh_tree()
	_build()


func refresh_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	# quests, under the npc who gives them
	var givers := {}
	var qs := tree.create_item(root)
	qs.set_text(0, "Quests")
	qs.set_selectable(0, false)
	for q in s.quests:
		var g: String = s.npc_name(q.get("giver"))
		if not givers.has(g):
			givers[g] = tree.create_item(qs)
			givers[g].set_text(0, g)
			givers[g].set_selectable(0, false)
		var it := tree.create_item(givers[g])
		var n: int = q.get("reward", {}).get("items", []).size()
		it.set_text(0, str(q.get("name", q.id)) + ("  (%d item%s)" % [n, "" if n == 1 else "s"] if n else ""))
		it.set_metadata(0, {"quest": q.id})
		if q == current:
			it.select(0)
	var cs := tree.create_item(root)
	cs.set_text(0, "Chests")
	cs.set_selectable(0, false)
	for c in s.chests:
		var it := tree.create_item(cs)
		it.set_text(0, str(c.get("name", c.id)))
		it.set_tooltip_text(0, c.id)
		it.set_metadata(0, {"chest": c.id})
		if c == current:
			it.select(0)


func _on_tree() -> void:
	var m = tree.get_selected().get_metadata(0)
	if m == null:
		return
	if m.has("quest"):
		current = DataStore.find(s.quests, m.quest)
		current_kind = "quest"
	else:
		current = DataStore.find(s.chests, m.chest)
		current_kind = "chest"
	_build.call_deferred()


func _build() -> void:
	UI.clear(form)
	if current.is_empty():
		UI.note(form, "Choose a quest or a chest.")
		return
	var title := Label.new()
	title.text = str(current.get("name", current.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	if current_kind == "quest":
		_quest(current)
	else:
		_chest(current)


func _quest(q: Dictionary) -> void:
	UI.note(form, "%s · from %s" % [q.id, s.npc_name(q.get("giver"))])
	if q.has("summary"):
		UI.note(form, str(q.summary))
	# where each thing to collect drops (quest drops on loot tables)
	for o in q.get("objectives", []):
		if o.get("type") != "collect":
			continue
		var from := PackedStringArray()
		for t in s.loot_tables:
			for qd in t.get("questDrops", []):
				if qd.get("quest") == q.id and qd.get("item") == o.target:
					from.append("%s (%d%%)" % [t.id, roundi(qd.get("chance", 0) * 100)])
		if from.size():
			UI.note(form, "%s drops from: %s" % [o.get("label", o.target), ", ".join(from)], Color("9fd08a"))
	UI.heading(form, "Reward")
	if not q.has("reward"):
		q.reward = {}
	var r: Dictionary = q.reward
	var g := UI.grid(form)
	UI.row(g, "Coins", UI.spin(r.get("coins", 0), 0, 100000, 1, func(v): _num(r, "coins", v, "quests")))
	UI.row(g, "Experience", UI.spin(r.get("xp", 0), 0, 1000000, 5, func(v): _num(r, "xp", v, "quests")))
	_item_rows(r, "item", "quests", ["coins", "xp"])
	if r.has("reputation"):
		UI.note(form, "Reputation: " + ", ".join(r.reputation.keys().map(func(k): return "%s +%d" % [k, r.reputation[k]])) + " (set in the quest editor).")


func _chest(c: Dictionary) -> void:
	UI.note(form, c.id)
	UI.heading(form, "Inside")
	var g := UI.grid(form)
	UI.row(g, "Coins", UI.spin(c.get("coins", 0), 0, 100000, 1, func(v): _num(c, "coins", v, "world")))
	_item_rows(c, "id", "world", ["coins"])


func _num(d: Dictionary, key: String, v: float, file: String) -> void:
	if v > 0:
		d[key] = v
	else:
		d.erase(key)
	s.touch(file)


## the item list of a reward or chest; quests name items as `item`, chests as `id`
func _item_rows(holder: Dictionary, key: String, file: String, after: Array) -> void:
	UI.note(form, "Items:")
	var items: Array = holder.get("items", [])
	for e in items:
		var h := UI.hbox(form)
		h.add_child(UI.item_picker(s, e.get(key), func(id):
			e[key] = id
			s.touch(file)))
		var cl := Label.new()
		cl.text = "count"
		h.add_child(cl)
		h.add_child(UI.spin(e.get("count", 1), 1, 999, 1, func(v):
			e.count = v
			s.touch(file)))
		h.add_child(UI.button("✕", func():
			items.erase(e)
			if items.is_empty():
				holder.erase("items")
			s.touch(file)
			refresh_tree()
			_build.call_deferred(), "Remove"))
	form.add_child(UI.button("Add an item…", func():
		UI.pick_item(form, s, Callable(), func(id):
			if not holder.has("items"):
				_insert_after(holder, "items", items, after)
			items.append({key: id, "count": 1})
			s.touch(file)
			refresh_tree()
			_build.call_deferred())))


## add a key just after the last of `after` that it has, keeping the file's order
static func _insert_after(d: Dictionary, key: String, value, after: Array) -> void:
	var last := ""
	for k in d:
		if after.has(k):
			last = k
	var copy := d.duplicate()
	d.clear()
	if last == "":
		d[key] = value
	for k in copy:
		d[k] = copy[k]
		if k == last:
			d[key] = value
