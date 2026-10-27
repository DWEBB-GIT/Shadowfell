@tool
extends HSplitContainer
## Quests: the list on the left (under the npc who gives each), the chosen
## quest's form on the right: who gives it and takes it back, what it needs
## first, what they say, its objectives and its reward. The same design as
## the browser quest editor (tools/quest-editor).

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

## the order keys are written in, so an edited quest reads like the others
const KEY_ORDER := ["id", "name", "giver", "turnIn", "autoAccept", "requires", "choice", "summary", "offer", "progress", "complete", "objectives", "reward", "setsFlag", "turnInLog"]
const OBJECTIVE_ORDER := ["id", "type", "target", "count", "keep", "label", "location"]
const REWARD_ORDER := ["coins", "xp", "items", "reputation", "infamy"]
const TYPES := [["kill", "Kill"], ["collect", "Collect"], ["examine", "Examine"], ["talk", "Talk to the hand-in npc"]]

## open another record (an npc) on its own tab
signal open_record(kind: String, id: String)

var s: DataStore
var tree: Tree
var search: LineEdit
var form: VBoxContainer
var current: Dictionary = {}
var new_ids := {} ## quests made since the last save: their id can still change
var problems: Callable ## set by the screen: () -> PackedStringArray


func setup(store: DataStore) -> void:
	s = store
	name = "Quests"
	split_offset = 260
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var top := UI.hbox(left)
	top.add_child(UI.button("New quest", func(): new_quest({}), "Write a new quest"))
	top.add_child(UI.button("Duplicate", _duplicate, "Copy the chosen quest"))
	top.add_child(UI.button("Delete", _delete, "Delete the chosen quest"))
	search = LineEdit.new()
	search.placeholder_text = "Search quests, npcs, text"
	search.text_changed.connect(func(_t): refresh_tree())
	left.add_child(search)
	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(func():
		var m = tree.get_selected().get_metadata(0)
		if m != null and (current.is_empty() or m != current.id):
			current = s.quest(m)
			_build.call_deferred())
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
	var id = current.get("id")
	current = {}
	if id != null:
		select(id)
	else:
		refresh_tree()
		_build()


func refresh_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	var q := search.text.to_lower()
	var givers := {}
	var bad := _problem_ids()
	for d in s.quests:
		if q != "" and not (JSON.stringify(d).to_lower().contains(q) or s.npc_name(d.get("giver")).to_lower().contains(q)):
			continue
		var g = d.get("giver")
		if not givers.has(g):
			givers[g] = tree.create_item(root)
			givers[g].set_text(0, s.npc_name(g).to_upper())
			givers[g].set_selectable(0, false)
			givers[g].set_custom_color(0, Color(0.6, 0.6, 0.6))
		var it := tree.create_item(givers[g])
		it.set_text(0, str(d.get("name", d.id)) + ("   new" if new_ids.has(d.id) else ""))
		it.set_tooltip_text(0, d.id)
		it.set_metadata(0, d.id)
		if bad.has(d.id):
			it.set_custom_color(0, Color("e08070"))
		if d == current:
			it.select(0)
			tree.scroll_to_item(it)


func select(id) -> void:
	current = s.quest(id)
	refresh_tree()
	_build()


## quest ids with a failing check
func _problem_ids() -> Dictionary:
	var out := {}
	if not problems.is_valid():
		return out
	for p in problems.call():
		if p.begins_with("Quest "):
			out[p.trim_prefix("Quest ").get_slice(":", 0)] = true
	return out


func _changed(rebuild := false) -> void:
	_tidy(current)
	s.touch("quests")
	if rebuild:
		refresh_tree()
		_build.call_deferred()


func _put(d: Dictionary, key: String, value, rebuild := false) -> void:
	if value == null or (value is String and value == "") or (value is bool and not value):
		d.erase(key)
	else:
		d[key] = value
	_changed(rebuild)


static func _tidy(q: Dictionary) -> void:
	_order(q, KEY_ORDER)
	for o in q.get("objectives", []):
		_order(o, OBJECTIVE_ORDER)
	if q.has("reward"):
		_order(q.reward, REWARD_ORDER)


static func _order(d: Dictionary, order: Array) -> void:
	var copy := d.duplicate()
	d.clear()
	for k in order:
		if copy.has(k):
			d[k] = copy[k]
	for k in copy:
		if not d.has(k):
			d[k] = copy[k]


# ------------------------------------------------------------------ form
func _build() -> void:
	UI.clear(form)
	if current.is_empty():
		UI.note(form, "Choose a quest on the left, or press New quest.")
		return
	var q := current
	var title := Label.new()
	title.text = str(q.get("name", q.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	UI.note(form, "Given by %s · handed in to %s" % [s.npc_name(q.get("giver")), s.npc_name(q.get("turnIn"))])
	if problems.is_valid():
		for p in problems.call():
			if p.begins_with("Quest %s:" % q.id):
				UI.note(form, "⚠ " + p.trim_prefix("Quest %s: " % q.id), Color("e08070"))

	# ---- basics
	UI.heading(form, "Basics")
	var g := UI.grid(form)
	UI.row(g, "Name", UI.line(str(q.get("name", "")), func(t):
		q.name = t
		title.text = t
		if new_ids.has(q.id):
			_rename_new(DataStore.slug(t))
		_changed()))
	var id_edit := LineEdit.new()
	id_edit.text = q.id
	id_edit.editable = new_ids.has(q.id)
	id_edit.tooltip_text = "Saves store quest ids, so it is locked once saved." if not id_edit.editable else "Made from the name until you save. Locked after that."
	id_edit.text_submitted.connect(func(t): _rename_new(DataStore.slug(t)))
	id_edit.focus_exited.connect(func(): _rename_new(DataStore.slug(id_edit.text)))
	UI.row(g, "ID", id_edit)
	var npc_row := func(label: String, key: String, tip: String):
		var h := HBoxContainer.new()
		var o := UI.choice(s.npc_choices(), q.get(key), func(v):
			q[key] = v
			if key == "turnIn":
				for o2 in q.get("objectives", []):
					if o2.get("type") == "talk":
						o2.target = v
			_changed(true))
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(o)
		h.add_child(UI.button("Open", func(): open_record.emit("npc", q.get(key)), "Edit this npc on the NPCs tab"))
		UI.row(g, label, h, tip)
	npc_row.call("Giver", "giver", "Who offers the quest (a gold ! over their head).")
	npc_row.call("Hand in to", "turnIn", "Who the quest is handed back to (a gold ? once it is ready).")
	UI.row(g, "Auto accept", UI.check(q.get("autoAccept", false), "Starts by itself, without an offer", func(on): _put(q, "autoAccept", on)))
	UI.row(g, "Choice", UI.line(str(q.get("choice", "")), func(t): _put(q, "choice", t.strip_edges())), "Optional. Quests with the same choice name are one decision: taking one locks the others.")

	UI.note(form, "Requires (offered once all of these are done):")
	var chips := HFlowContainer.new()
	form.add_child(chips)
	var reqs: Array = q.get("requires", [])
	for r in reqs:
		var b := Button.new()
		b.text = str(s.quest(r).get("name", str(r) + " (missing!)")) + "  ✕"
		b.tooltip_text = "Click to stop requiring %s" % r
		b.pressed.connect(func():
			reqs.erase(r)
			if reqs.is_empty():
				q.erase("requires")
			_changed(true))
		chips.add_child(b)
	var others := [[null, "+ add a required quest"]]
	for o in s.quests:
		if o != q and not reqs.has(o.id):
			others.append([o.id, str(o.get("name", o.id))])
	form.add_child(UI.choice(others, null, func(v):
		if v == null:
			return
		if not q.has("requires"):
			q.requires = reqs
		reqs.append(v)
		_changed(true)))

	# ---- what they say
	UI.heading(form, "What they say")
	g = UI.grid(form)
	UI.row(g, "Summary", UI.text_box(q, "summary", _changed), "Shown in the quest log.")
	UI.row(g, "Offer", UI.text_box(q, "offer", _changed, false, 80), "What the giver says when offering it (not needed for auto accept).")
	UI.row(g, "Progress", UI.text_box(q, "progress", _changed), "What they say while it is active.")
	UI.row(g, "Complete", UI.text_box(q, "complete", _changed, true, 80), "What they say on hand-in.")
	UI.row(g, "Hand-in log line", UI.line(str(q.get("turnInLog", "")), func(t): _put(q, "turnInLog", t)), "Optional. Written to the log on hand-in.")

	# ---- objectives
	UI.heading(form, "Objectives")
	if not q.has("objectives"):
		q.objectives = []
	var objs: Array = q.objectives
	for i in objs.size():
		_objective(q, objs[i], i)
	form.add_child(UI.button("+ Add objective", func():
		objs.append({"id": _free_objective_id(q), "type": "kill", "target": s.enemies[0].id if s.enemies.size() else "", "count": 1, "label": ""})
		_changed(true)))

	# ---- reward
	UI.heading(form, "Reward")
	if not q.has("reward"):
		q.reward = {}
	var r: Dictionary = q.reward
	g = UI.grid(form)
	UI.coins_row(g, r, func(): _changed())
	UI.row(g, "Experience", UI.spin(r.get("xp", 0), 0, 1000000, 5, func(v):
		if v > 0:
			r.xp = v
		else:
			r.erase("xp")
		_changed()))
	UI.row(g, "Infamy", UI.spin(r.get("infamy", 0), 0, 1000, 1, func(v):
		if v > 0:
			r.infamy = int(v)
		else:
			r.erase("infamy")
		_changed()), "For a dark choice: it is remembered (infamy.json).")
	UI.note(form, "Items:")
	UI.item_rows(form, s, r, "item", ["coins", "xp"], _changed)
	UI.note(form, "Reputation:")
	var rep: Dictionary = r.get("reputation", {})
	for f in rep.keys():
		var h := UI.hbox(form)
		var fo := UI.choice(s.faction_choices(), f, func(v):
			if v == f or rep.has(v):
				return
			var amount = rep[f]
			rep.erase(f)
			rep[v] = amount
			_changed(true))
		fo.custom_minimum_size.x = 220
		h.add_child(fo)
		h.add_child(UI.spin(rep[f], -10000, 10000, 50, func(v):
			rep[f] = v
			_changed()))
		h.add_child(UI.button("✕", func():
			rep.erase(f)
			if rep.is_empty():
				r.erase("reputation")
			_changed(true), "Remove"))
	var unused := s.factions.filter(func(fa): return not rep.has(fa.id))
	if unused.size():
		form.add_child(UI.button("+ Add reputation", func():
			if not r.has("reputation"):
				r.reputation = rep
			rep[unused[0].id] = 250
			_changed(true)))

	# ---- after
	UI.heading(form, "After hand-in")
	g = UI.grid(form)
	UI.row(g, "Sets flag", UI.line(str(q.get("setsFlag", "")), func(t): _put(q, "setsFlag", t.strip_edges())), "Optional. A name dialogue and the world can check, e.g. manifest_delivered.")

	# ---- how it connects
	UI.heading(form, "Connections")
	UI.note(form, "Needs first:")
	UI.links(form, reqs.map(func(id): return [id, s.quest(id).get("name", id)]), select, "Nothing: offered from the start.")
	UI.note(form, "Unlocks:")
	UI.links(form, s.quests_after(q.id).map(func(o): return [o.id, o.get("name", o.id)]), select, "No quest follows this one yet.")
	UI.note(form, "Mentioned in dialogue:")
	var talk := s.dialogue_mentions(q.id)
	if talk.is_empty():
		UI.note(form, "No dialogue line checks this quest.", Color(0.55, 0.55, 0.55))
	for t in talk:
		UI.note(form, "%s (%s): \"%s\"" % [s.npc_name(t.npc), t.status, t.text], Color(0.75, 0.72, 0.6))

	var bar := UI.hbox(form)
	bar.add_child(UI.button("+ Follow-up quest", func(): new_quest({"requires": [q.id], "giver": q.get("giver"), "turnIn": q.get("turnIn")}), "A new quest offered once this one is done"))
	bar.add_child(UI.button("Duplicate", _duplicate))
	bar.add_child(UI.button("Delete quest", _delete))


func _objective(q: Dictionary, o: Dictionary, i: int) -> void:
	var card := PanelContainer.new()
	form.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var head := UI.hbox(box)
	var hl := Label.new()
	hl.text = "Objective %d" % (i + 1)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	head.add_child(UI.button("Remove", func():
		q.objectives.erase(o)
		_changed(true)))
	var g := UI.grid(box)
	UI.row(g, "Type", UI.choice(TYPES, o.get("type"), func(v):
		o.type = v
		match v:
			"kill":
				o.target = s.enemies[0].id if s.enemies.size() else ""
			"collect":
				o.target = s.items[0].id if s.items.size() else ""
			"examine":
				o.target = s.examine_points[0] if s.examine_points.size() else ""
			"talk":
				o.target = q.get("turnIn")
		if v in ["examine", "talk"]:
			o.erase("count")
		elif not o.has("count"):
			o.count = 1
		if v != "collect":
			o.erase("keep")
		_changed(true)))
	match o.get("type"):
		"kill":
			UI.row(g, "Enemy", UI.choice(s.enemies.map(func(e): return [e.id, s.enemy_name(e.id)]), o.get("target"), func(v):
				o.target = v
				_changed(true)), "Kills are counted from when the quest is taken.")
		"collect":
			UI.row(g, "Item", UI.item_picker(s, o.get("target"), func(id):
				o.target = id
				_changed(true)), "The player must carry this many. Make it a quest item (Items tab) so it is only for this quest.")
		"examine":
			UI.row(g, "Examine point", UI.choice(Array(s.examine_points).map(func(e): return [e, e]), o.get("target"), func(v):
				o.target = v
				_changed()), "A point in the world to look at (text.json examine).")
		"talk":
			UI.note(box, "Go and speak to %s (the hand-in npc)." % s.npc_name(q.get("turnIn")))
	if o.get("type") in ["kill", "collect"]:
		UI.row(g, "Count", UI.spin(o.get("count", 1), 1, 999, 1, func(v):
			o.count = v
			_changed()))
	if o.get("type") == "collect":
		UI.row(g, "Keep", UI.check(o.get("keep", false), "The player keeps the item on hand-in", func(on): _put(o, "keep", on)))
	UI.row(g, "Label", UI.line(str(o.get("label", "")), func(t):
		o.label = t
		_changed()), "Shown in the quest tracker, e.g. \"Gravebound Brute slain\".")
	UI.row(g, "Map area", UI.choice([[null, "(none)"]] + s.location_choices(), o.get("location"), func(v): _put(o, "location", v)), "Optional. Shown on the minimap while the objective is open.")
	UI.row(g, "Objective id", UI.line(str(o.get("id", "")), func(t):
		o.id = DataStore.slug(t)
		_changed()), "Unique within this quest. Saves store it, so change it only before the quest ships.")
	if o.get("type") == "collect":
		var from := PackedStringArray()
		for t in s.loot_tables:
			for qd in t.get("questDrops", []):
				if qd.get("quest") == q.id and qd.get("item") == o.get("target"):
					from.append("%s (%d%%)" % [t.id, roundi(qd.get("chance", 0) * 100)])
		var nodes: Array = s.files.world.get("placedLoot", []).filter(func(p): return p.get("item") == o.get("target"))
		if from.size():
			UI.note(box, "Drops from: " + ", ".join(from), Color("9fd08a"))
		if nodes.size():
			UI.note(box, "Lies in the world at %d place%s." % [nodes.size(), "" if nodes.size() == 1 else "s"], Color("9fd08a"))
		if from.is_empty() and nodes.is_empty() and s.item(o.get("target")).get("quest"):
			UI.note(box, "Nothing drops it yet: add it as a quest drop on the Loot tables tab, or place it with the World editor.", Color("d0b070"))


func _free_objective_id(q: Dictionary) -> String:
	var n: int = q.get("objectives", []).size() + 1
	while q.get("objectives", []).any(func(o): return o.get("id") == "objective_%d" % n):
		n += 1
	return "objective_%d" % n


# ------------------------------------------------------------------ actions
## A new quest; `base` may give its giver, turnIn and requires.
func new_quest(base: Dictionary) -> void:
	var giver = base.get("giver", s.npcs[0].id if s.npcs.size() else "")
	var q := {
		"id": s.unique_id(s.quests, "new_quest"),
		"name": "New quest",
		"giver": giver,
		"turnIn": base.get("turnIn", giver),
	}
	if base.has("requires"):
		q.requires = base.requires.duplicate()
	q.merge({"summary": "", "offer": "", "progress": "", "complete": "", "objectives": [{"id": "objective_1", "type": "kill", "target": s.enemies[0].id if s.enemies.size() else "", "count": 1, "label": ""}], "reward": {"coins": 0, "xp": 0}})
	# next to the giver's other quests
	var at := s.quests.size()
	for i in s.quests.size():
		if s.quests[i].get("giver") == giver:
			at = i + 1
	s.quests.insert(at, q)
	new_ids[q.id] = true
	s.touch("quests")
	select(q.id)


func _rename_new(id: String) -> void:
	var q := current
	if not new_ids.has(q.get("id")) or id == "" or id == q.id:
		return
	id = s.unique_id(s.quests, id)
	new_ids.erase(q.id)
	new_ids[id] = true
	q.id = id
	_changed()
	refresh_tree()


func _duplicate() -> void:
	if current.is_empty():
		return
	var q := current.duplicate(true)
	q.id = s.unique_id(s.quests, current.id + "_copy")
	q.name = str(current.get("name", "")) + " (copy)"
	q.erase("autoAccept")
	s.quests.insert(s.quests.find(current) + 1, q)
	new_ids[q.id] = true
	s.touch("quests")
	select(q.id)


func _delete() -> void:
	if current.is_empty():
		return
	var q := current
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete quest"
	dlg.dialog_text = "Delete %s (%s)?" % [q.get("name", ""), q.id]
	var named := PackedStringArray()
	for o in s.quests_after(q.id):
		named.append("quest " + o.id)
	for t in s.loot_tables:
		if t.get("questDrops", []).any(func(qd): return qd.get("quest") == q.id):
			named.append("loot table " + t.id)
	for m in s.dialogue_mentions(q.id):
		if not named.has("dialogue " + m.npc):
			named.append("dialogue " + m.npc)
	if named.size():
		dlg.dialog_text += "\n\nIt is still named in: %s.\nChange those too, or the checks will fail." % ", ".join(named)
	if not new_ids.has(q.id):
		dlg.dialog_text += "\n\nIt has been saved before, so players may have it in their saves. The usual rule is to stop offering a shipped quest rather than delete it."
	dlg.confirmed.connect(func():
		s.quests.erase(q)
		new_ids.erase(q.id)
		current = {}
		s.touch("quests")
		refresh_tree()
		_build()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
