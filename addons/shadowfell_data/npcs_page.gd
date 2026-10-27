@tool
extends HSplitContainer
## NPCs: townsfolk, with the shop they keep (and what it sells), how they
## greet you, the quests they give and take back, and where they stand.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

## the order keys are written in, so an edited npc reads like the others
const KEY_ORDER := ["id", "mapIcon", "name", "title", "level", "model", "rig", "tint", "shop", "work", "dialogue", "innkeeper", "board"]
const SHOP_ORDER := ["id", "name", "vendorType", "stock", "faction"]
## what the minimap can draw for an npc's trade (src/data/schema.js NPC_MAP_ICONS)
const MAP_ICONS := [[null, "(none)"], ["vendor", "Vendor"], ["blacksmith", "Blacksmith"], ["fishing", "Fishing"], ["cooking", "Cooking"], ["innkeeper", "Innkeeper"], ["trainer", "Class trainer"], ["tanner", "Tanner"]]

## open another record (a quest) on its own tab
signal open_record(kind: String, id: String)

var s: DataStore
var list: ItemList
var search: LineEdit
var form: VBoxContainer
var current: Dictionary = {}
var new_ids := {} ## npcs made since the last save: their id can still change
var problems: Callable ## set by the screen: () -> PackedStringArray


func setup(store: DataStore) -> void:
	s = store
	name = "NPCs"
	split_offset = 260
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var top := UI.hbox(left)
	top.add_child(UI.button("New NPC", _new_npc, "Make a new townsperson"))
	top.add_child(UI.button("Duplicate", _duplicate, "Copy the chosen npc"))
	top.add_child(UI.button("Delete", _delete, "Delete the chosen npc"))
	search = LineEdit.new()
	search.placeholder_text = "Search"
	search.text_changed.connect(func(_t): refresh_list())
	left.add_child(search)
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
	_build()


func reload() -> void:
	new_ids.clear()
	var id = current.get("id")
	current = {}
	if id != null:
		select(id)
	else:
		refresh_list()
		_build()


func refresh_list() -> void:
	list.clear()
	var q := search.text.to_lower()
	for n in s.npcs:
		var label := "%s (%s)" % [n.get("name", n.id), n.get("title", "")] if n.has("title") else str(n.get("name", n.id))
		if q != "" and not (label.to_lower().contains(q) or str(n.id).contains(q)):
			continue
		var i := list.add_item(label + ("   new" if new_ids.has(n.id) else ""))
		list.set_item_metadata(i, n.id)
		list.set_item_tooltip(i, n.id)
		if n == current:
			list.select(i)


func select(id) -> void:
	current = s.npc(id)
	refresh_list()
	for i in list.item_count:
		if list.get_item_metadata(i) == id:
			list.ensure_current_is_visible()
	_build()


func _changed(rebuild := false) -> void:
	_order(current, KEY_ORDER)
	s.touch("npcs")
	if rebuild:
		refresh_list()
		_build.call_deferred()


func _put(key: String, value, rebuild := false) -> void:
	if value == null or (value is String and value == "") or (value is bool and not value):
		current.erase(key)
	else:
		current[key] = value
	_changed(rebuild)


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
		UI.note(form, "Choose an npc on the left, or press New NPC.")
		return
	var n := current
	var title := Label.new()
	title.text = str(n.get("name", n.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	if problems.is_valid():
		for p in problems.call():
			if p.begins_with("NPC %s:" % n.id) or p.begins_with("Shop %s:" % n.get("shop", "")):
				UI.note(form, "⚠ " + p, Color("e08070"))

	# ---- who they are
	UI.heading(form, "NPC")
	var g := UI.grid(form)
	UI.row(g, "Name", UI.line(str(n.get("name", "")), func(t):
		n.name = t
		title.text = t
		if new_ids.has(n.id):
			_rename_new(DataStore.slug(t))
		_changed()))
	var id_edit := LineEdit.new()
	id_edit.text = n.id
	id_edit.editable = new_ids.has(n.id)
	id_edit.tooltip_text = "Quests, spawns and saves use the id, so it is locked once saved." if not id_edit.editable else "Made from the name until you save. Locked after that."
	id_edit.text_submitted.connect(func(t): _rename_new(DataStore.slug(t)))
	id_edit.focus_exited.connect(func(): _rename_new(DataStore.slug(id_edit.text)))
	UI.row(g, "ID", id_edit)
	UI.row(g, "Title", UI.line(str(n.get("title", "")), func(t): _put("title", t)), "Shown under the name: Smith, Farmer, Reeve.")
	UI.row(g, "Level", UI.spin(n.get("level", 1), 1, 60, 1, func(v): _put("level", v)), "Shown on their portrait and tooltip.")
	UI.row(g, "Model", UI.choice(Array(s.models).map(func(m): return [m, m]), n.get("model"), func(v): _put("model", v)), "Townsfolk share a few models; a tint tells them apart.")
	var tint := HBoxContainer.new()
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(80, 0)
	picker.edit_alpha = false
	picker.color = Color(n.get("tint", "#ffffff"))
	picker.disabled = not n.has("tint")
	var tinted := UI.check(n.has("tint"), "Tinted", func(on):
		picker.disabled = not on
		_put("tint", "#" + picker.color.to_html(false) if on else null))
	picker.color_changed.connect(func(c): _put("tint", "#" + c.to_html(false)))
	tint.add_child(tinted)
	tint.add_child(picker)
	UI.row(g, "Tint", tint, "Colours their model, to tell apart townsfolk who share one.")
	UI.row(g, "Map icon", UI.choice(MAP_ICONS, n.get("mapIcon"), func(v): _put("mapIcon", v)), "Puts their trade on the minimap.")
	UI.row(g, "Innkeeper", UI.check(n.get("innkeeper", false), "Keeps an inn (you can make it your home)", func(on): _put("innkeeper", on)))
	UI.row(g, "Smith", UI.check(n.get("forge", false), "Reforges, punches sockets and lets you smelt", func(on): _put("forge", true if on else null)))
	UI.row(g, "Enchanter", UI.check(n.get("enchanter", false), "Enchants gear (+1 item level a rank) and scraps it into dust and gems", func(on): _put("enchanter", true if on else null)))
	UI.row(g, "Jeweller", UI.check(n.get("jeweller", false), "Makes gems from shards, sets and removes gems", func(on): _put("jeweller", true if on else null)))
	UI.row(g, "Notice board", UI.check(n.get("board", false), "A notice board, not a person (no greeting by title)", func(on): _put("board", on)))

	_greeting(n)
	_shop(n)
	_trains(n)
	_quests(n)
	_world(n)


## the first plain greeting of their dialogue (what they say when you walk up)
func _greeting(n: Dictionary) -> void:
	UI.heading(form, "Greeting")
	var d := s.dialogue(n.get("dialogue"))
	if d.is_empty():
		UI.note(form, "They have no dialogue, so they only offer their quests and shop.")
		form.add_child(UI.button("Give them a greeting", func(): give_dialogue(n)))
		return
	var greets: Array = d.get("greetings", [])
	var plain = null
	for gr in greets:
		if not gr.has("when"):
			plain = gr
			break
	if plain == null:
		plain = {"text": ""}
		greets.insert(0, plain)
	var t := UI.text_box(plain, "text", func(): s.touch("dialogue"))
	form.add_child(t)
	form.add_child(UI.button("Edit all of their dialogue", func(): open_record.emit("dialogue", d.id), "Greetings for each step of a quest, topics and replies, on the Dialogue tab"))
	var others := greets.size() - 1
	var topics: int = d.get("topics", []).size()
	UI.note(form, "Dialogue %s: %d greeting%s that depend on quests or flags, %d topic%s to ask about (edited in data/dialogue.json)." % [d.id, others, "" if others == 1 else "s", topics, "" if topics == 1 else "s"], Color(0.6, 0.6, 0.6))


## a dialogue of their own, with one greeting to edit
func give_dialogue(n: Dictionary) -> void:
	var id: String = s.unique_id(s.dialogues, n.id)
	s.dialogues.append({"id": id, "greetings": [{"text": "Well met."}], "topics": [], "nodes": []})
	s.touch("dialogue")
	_put("dialogue", id, true)


func _shop(n: Dictionary) -> void:
	UI.heading(form, "Shop")
	var g := UI.grid(form)
	var h := HBoxContainer.new()
	var o := UI.choice([[null, "(no shop)"]] + s.shops.map(func(sh): return [sh.id, sh.get("name", sh.id)]), n.get("shop"), func(v): _put("shop", v, true))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(o)
	h.add_child(UI.button("New shop", func(): _new_shop(n), "Give them a shop of their own"))
	UI.row(g, "Keeps", h, "The shop they sell from. The \"Let me see your wares\" choice opens it.")
	var sh := s.shop(n.get("shop"))
	if sh.is_empty():
		return
	var touch := func(rebuild: bool):
		_order(sh, SHOP_ORDER)
		s.touch("shops")
		if rebuild:
			_build.call_deferred()
	UI.row(g, "Shop name", UI.line(str(sh.get("name", "")), func(t):
		sh.name = t
		touch.call(false)))
	UI.row(g, "Vendor type", UI.choice(s.vendor_types.map(func(v): return [v.id, v.get("name", v.id)]), sh.get("vendorType"), func(v):
		sh.vendorType = v
		touch.call(true)), str(s.vendor_type(sh.get("vendorType")).get("description", "")))
	UI.row(g, "Faction", UI.choice([[null, "(none)"]] + s.faction_choices(), sh.get("faction"), func(v):
		if v == null:
			sh.erase("faction")
		else:
			sh.faction = v
		touch.call(false)), "Optional. Standing with this faction changes its prices.")
	var shared := s.npcs.filter(func(o2): return o2 != n and o2.get("shop") == sh.id)
	if shared.size():
		UI.note(form, "Also kept by " + ", ".join(shared.map(func(o2): return o2.get("name", o2.id))) + ": changes here change theirs too.", Color("d0b070"))
	var vt := s.vendor_type(sh.get("vendorType"))
	var sells: Array = vt.get("sells", [])
	UI.note(form, "Sells %s. Merchants buy anything sellable." % ", ".join(sells.map(func(k): return DataStore.KIND_NAMES.get(k, k).to_lower())) if sells.size() else "This vendor type sells nothing.")
	if not sh.has("stock"):
		sh.stock = []
	var stock: Array = sh.stock
	for i in stock.size():
		var id = stock[i]
		var row := UI.hbox(form)
		row.add_child(UI.item_picker(s, id, func(nid):
			stock[i] = nid
			touch.call(true), func(d): return _sellable(d, sells)))
		var price := Label.new()
		var cost: int = s.item(id).get("price", 0)
		price.text = "%d coin%s" % [cost, "" if cost == 1 else "s"]
		price.custom_minimum_size.x = 80
		row.add_child(price)
		var up := UI.button("↑", func():
			stock.remove_at(i)
			stock.insert(i - 1, id)
			touch.call(true), "Move up")
		up.disabled = i == 0
		row.add_child(up)
		row.add_child(UI.button("✕", func():
			stock.remove_at(i)
			touch.call(true), "Stop selling it"))
	form.add_child(UI.button("Add an item…", func():
		UI.pick_item(form, s, func(d): return _sellable(d, sells) and not stock.has(d.id), func(nid):
			stock.append(nid)
			touch.call(true))))


## what a shop of this vendor type may sell: its kinds, no quest items, no
## boss's own drops
static func _sellable(d: Dictionary, sells: Array) -> bool:
	return sells.has(d.get("kind")) and not d.get("quest", false) and not d.has("reservedFor")


func _new_shop(n: Dictionary) -> void:
	var vt: String = s.vendor_types[0].id if s.vendor_types.size() else "general"
	var sh := {"id": s.unique_id(s.shops, n.id + "_shop"), "name": "%s's shop" % str(n.get("name", n.id)).get_slice(" ", 0), "vendorType": vt, "stock": []}
	s.shops.append(sh)
	s.touch("shops")
	_put("shop", sh.id, true)


## what they teach: skills, class spells (archetypes.json `trained`) and recipes
func _trains(n: Dictionary) -> void:
	UI.heading(form, "Trains")
	UI.note(form, "Anything here gives them a Train choice. Map icon Class trainer marks a class trainer on the minimap.", Color(0.6, 0.6, 0.6))
	UI.note(form, "Skills:")
	var skills := s.skills.filter(func(sk): return sk.get("trainer") == n.id)
	for sk in skills:
		var row := UI.hbox(form)
		var b := LinkButton.new()
		b.text = "%s (%d coins)" % [sk.get("name", sk.id), sk.get("cost", 0)]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): open_record.emit("skill", sk.id))
		row.add_child(b)
	var bar := UI.hbox(form)
	var others := s.skills.filter(func(sk): return sk.get("trainer") != n.id).map(func(sk): return [sk.id, "%s (now %s)" % [sk.get("name", sk.id), s.npc_name(sk.get("trainer"))]])
	if others.size():
		bar.add_child(UI.choice([[null, "+ teach a skill"]] + others, null, func(v):
			if v == null:
				return
			s.skill(v).trainer = n.id
			s.touch("skills")
			_build.call_deferred()))
	bar.add_child(UI.button("New skill", func(): open_record.emit("new_skill", n.id), "Make a new skill they teach, on the Skills tab"))

	UI.note(form, "Class spells (each class learns its own): the level it needs, the cost, and optionally a quest the player must hand in first:")
	var quests := [[null, "no quest needed"]] + s.quest_choices().map(func(q): return [q[0], "after " + q[1]])
	for e in s.trained_by(n.id):
		var c: Dictionary = e["class"]
		var t: Dictionary = e.entry
		var row := UI.hbox(form)
		var b := LinkButton.new()
		b.text = "%s: %s" % [c.get("name", c.id), s.ability_name(t.ability)]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): open_record.emit("ability", t.ability))
		row.add_child(b)
		var lv := Label.new()
		lv.text = "level"
		row.add_child(lv)
		row.add_child(UI.spin(t.get("level", 1), 1, 60, 1, func(v):
			t.level = int(v)
			s.touch("archetypes")))
		row.add_child(UI.spin(t.get("cost", 0), 0, 100000, 1, func(v):
			t.cost = int(v)
			s.touch("archetypes"), " coins"))
		var gate := UI.choice(quests, t.get("quest"), func(v):
			if v == null:
				t.erase("quest")
			else:
				t.quest = v
			s.touch("archetypes"))
		gate.tooltip_text = "The spell stays locked at the trainer until this quest is handed in."
		gate.custom_minimum_size.x = 180
		row.add_child(gate)
		row.add_child(UI.button("✕", func():
			s.set_spell_source(c, t.ability, "book")
			_build.call_deferred(), "They no longer teach it (the class knows it from the start, in its spellbook)"))
	# any class's spells, or any class spell at all for the chosen class
	var add := UI.hbox(form)
	var pick := {"class": s.archetypes[0].id if s.archetypes.size() else null}
	var cls := UI.choice(s.archetypes.map(func(c): return [c.id, c.get("name", c.id)]), pick["class"], func(v):
		pick["class"] = v)
	cls.tooltip_text = "The class that learns it"
	add.add_child(cls)
	var spells := [[null, "+ teach a spell"]]
	for a in s.class_spells():
		spells.append([a.id, "%s (%s)" % [a.get("name", a.id), ", ".join(s.classes_with(a.id).map(func(c): return c.get("name", c.id))) if not s.classes_with(a.id).is_empty() else "no class yet"]])
	add.add_child(UI.choice(spells, null, func(v):
		if v == null or pick["class"] == null:
			return
		var c := DataStore.find(s.archetypes, pick["class"])
		s.set_spell_source(c, v, "trained", n.id)
		_build.call_deferred()))
	add.add_child(UI.button("Teach all its spells", func():
		var c := DataStore.find(s.archetypes, pick["class"])
		for id in c.get("abilities", []).duplicate():
			if DataStore.spell_source(c, id) == "book":
				s.set_spell_source(c, id, "trained", n.id)
		_build.call_deferred(), "Every spell in the chosen class's spellbook that is not on its starting bar and not taught by someone else: this npc teaches it (teach starting-bar spells one by one to take them off the bar)"))
	add.add_child(UI.button("New spell", func(): open_record.emit("new_spell", n.id), "Make a new spell on the Abilities tab; tick a class and choose this trainer there"))
	UI.note(form, "Teaching a spell from the starting bar takes it off the bar, so a new character must train it. A spell from outside the class's spellbook is added to it.", Color(0.6, 0.6, 0.6))
	var recipes := s.recipes.filter(func(r): return r.get("trainer") == n.id)
	if recipes.size():
		UI.note(form, "Recipes: %s (recipes.json)." % ", ".join(recipes.map(func(r): return s.item(r.get("output", {}).get("item")).get("name", r.id))))


func _quests(n: Dictionary) -> void:
	UI.heading(form, "Quests")
	var gives := s.quests.filter(func(q): return q.get("giver") == n.id)
	var takes := s.quests.filter(func(q): return q.get("turnIn") == n.id and q.get("giver") != n.id)
	UI.note(form, "Gives:")
	UI.links(form, gives.map(func(q): return [q.id, q.get("name", q.id)]), func(id): open_record.emit("quest", id), "No quests yet.")
	if takes.size():
		UI.note(form, "Takes back quests given by others:")
		UI.links(form, takes.map(func(q): return [q.id, "%s (from %s)" % [q.get("name", q.id), s.npc_name(q.get("giver"))]]), func(id): open_record.emit("quest", id), "")
	form.add_child(UI.button("+ New quest from %s" % n.get("name", n.id), func(): open_record.emit("new_quest", n.id), "Write a quest this npc gives"))


func _world(n: Dictionary) -> void:
	UI.heading(form, "In the world")
	var sp := s.spawn_of(n.id)
	if sp.is_empty():
		UI.note(form, "Not placed anywhere yet, so they are not in the game.", Color("d0b070"))
		form.add_child(UI.button("Place in Brackenford", func(): _place(n), "Stand them in the town square; move them with the World editor"))
		return
	var p: Array = sp.get("position", [0, 0])
	UI.note(form, "Stands at x %s, z %s, facing %d°. Move them with the World editor (res://addons/shadowfell_data/world_editor.tscn)." % [p[0], p[1], sp.get("facing", 0)])
	if sp.has("goneWhen"):
		UI.note(form, "Gone while: " + JSON.stringify(sp.goneWhen))


## a spawn a little way off the Brackenford square, clear of the others
func _place(n: Dictionary) -> void:
	var town := DataStore.find(s.locations, "brackenford")
	var c: Array = town.get("position", s.files.world.get("playerStart", {}).get("position", [0, 0]))
	var at := Vector2(c[0], c[1])
	for step in 24:
		var tryp := at + Vector2(4, 0).rotated(step * TAU / 8) * (1 + floori(step / 8.0))
		if s.npc_spawns.all(func(o): return Vector2(o.position[0], o.position[1]).distance_to(tryp) > 2.5):
			at = tryp
			break
	s.npc_spawns.append({"npc": n.id, "position": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "facing": 180})
	s.touch("world")
	_build.call_deferred()


# ------------------------------------------------------------------ actions
func _new_npc() -> void:
	var n := {"id": s.unique_id(s.npcs, "new_npc"), "name": "New NPC", "title": "Townsfolk", "level": 5, "model": "tam" if s.models.has("tam") else (s.models[0] if s.models.size() else ""), "rig": "warden"}
	s.npcs.append(n)
	new_ids[n.id] = true
	s.touch("npcs")
	select(n.id)


func _rename_new(id: String) -> void:
	var n := current
	if not new_ids.has(n.get("id")) or id == "" or id == n.id:
		return
	id = s.unique_id(s.npcs, id)
	# its spawn and the quests written for it so far follow the new id
	for sp in s.npc_spawns:
		if sp.get("npc") == n.id:
			sp.npc = id
			s.touch("world")
	for q in s.quests:
		for k in ["giver", "turnIn"]:
			if q.get(k) == n.id:
				q[k] = id
				s.touch("quests")
	new_ids.erase(n.id)
	new_ids[id] = true
	n.id = id
	_changed()
	refresh_list()


func _duplicate() -> void:
	if current.is_empty():
		return
	var n := current.duplicate(true)
	n.id = s.unique_id(s.npcs, current.id + "_copy")
	n.name = str(current.get("name", "")) + " copy"
	n.erase("dialogue")
	s.npcs.insert(s.npcs.find(current) + 1, n)
	new_ids[n.id] = true
	s.touch("npcs")
	select(n.id)


func _delete() -> void:
	if current.is_empty():
		return
	var n := current
	var uses := s.uses_of_npc(n.id)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete NPC"
	dlg.dialog_text = "Delete %s (%s)? Where they stand in the world goes too." % [n.get("name", ""), n.id]
	if uses.size():
		dlg.dialog_text += "\n\nThey are still named in: %s.\nChange those too, or the checks will fail." % ", ".join(uses)
	dlg.confirmed.connect(func():
		s.npcs.erase(n)
		for sp in s.npc_spawns.filter(func(o): return o.get("npc") == n.id):
			s.npc_spawns.erase(sp)
			s.touch("world")
		new_ids.erase(n.id)
		current = {}
		s.touch("npcs")
		refresh_list()
		_build()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
