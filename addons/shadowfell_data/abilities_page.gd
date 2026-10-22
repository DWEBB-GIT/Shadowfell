@tool
extends HSplitContainer
## Abilities: class spells and skill tools (data/abilities.json). A new
## spell picks what kind it is (a cast, a damage over time, a cleave...) and
## starts with the numbers that kind needs; the generic spell engine runs it
## with no new code. Put it in a class's spellbook here, and say whether the
## class knows it from the start or learns it from a trainer (archetypes.json
## `trained`: the trainer, the level and the cost).

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

## fields shown by the form; the rest are edited as JSON under Other fields
const FORM_KEYS := ["id", "name", "kind", "ranged", "school", "target", "range", "desc", "tuning", "cost", "gain", "skill", "bar"]

## open another record (a skill, an npc) on its own tab
signal open_record(kind: String, id: String)

var s: DataStore
var list: ItemList
var search: LineEdit
var class_filter: OptionButton
var form: VBoxContainer
var current: Dictionary = {}
var new_ids := {} ## abilities made since the last save: their id can still change
var problems: Callable ## set by the screen: () -> PackedStringArray


func setup(store: DataStore) -> void:
	s = store
	name = "Abilities"
	split_offset = 260
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var top := UI.hbox(left)
	top.add_child(UI.button("New spell", func(): _new_dialog(), "Make a new spell"))
	top.add_child(UI.button("Duplicate", _duplicate, "Copy the chosen ability"))
	top.add_child(UI.button("Delete", _delete, "Delete the chosen ability"))
	search = LineEdit.new()
	search.placeholder_text = "Search"
	search.text_changed.connect(func(_t): refresh_list())
	left.add_child(search)
	var classes := [[null, "All abilities"]]
	for a in s.archetypes:
		classes.append([a.id, a.get("name", a.id)])
	classes.append(["_skill", "Skill tools"])
	class_filter = UI.choice(classes, null, func(_v): refresh_list())
	left.add_child(class_filter)
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
	var c = class_filter.get_item_metadata(class_filter.selected)
	for a in s.abilities:
		if c == "_skill" and not a.has("skill"):
			continue
		if c != null and c != "_skill" and not s.find(s.archetypes, c).get("abilities", []).has(a.id):
			continue
		if q != "" and not (str(a.get("name", "")).to_lower().contains(q) or str(a.id).to_lower().contains(q)):
			continue
		var i := list.add_item(str(a.get("name", a.id)) + ("   new" if new_ids.has(a.id) else ""))
		list.set_item_metadata(i, a.id)
		list.set_item_tooltip(i, "%s · %s" % [a.id, a.get("kind", "own code")])
		if a == current:
			list.select(i)


func select(id) -> void:
	current = s.ability(id)
	refresh_list()
	for i in list.item_count:
		if list.get_item_metadata(i) == id:
			list.ensure_current_is_visible()
	_build()


func _changed(rebuild := false) -> void:
	s.touch("abilities")
	if rebuild:
		refresh_list()
		_build.call_deferred()


func _put(key: String, value, rebuild := false) -> void:
	if value == null or (value is String and value == "" and key != "desc"):
		current.erase(key)
	else:
		current[key] = value
	_changed(rebuild)


# ------------------------------------------------------------------ form
func _build() -> void:
	UI.clear(form)
	if current.is_empty():
		UI.note(form, "Choose an ability on the left, or press New spell.")
		return
	var a := current
	var title := Label.new()
	title.text = str(a.get("name", a.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	if problems.is_valid():
		for p in problems.call():
			if p.begins_with("Ability %s:" % a.id):
				UI.note(form, "⚠ " + p.trim_prefix("Ability %s: " % a.id), Color("e08070"))

	# ---- what it is
	UI.heading(form, "Ability")
	var g := UI.grid(form)
	UI.row(g, "Name", UI.line(str(a.get("name", "")), func(t):
		a.name = t
		title.text = t
		if new_ids.has(a.id):
			_rename_new(_camel(t))
		_changed()))
	var id_edit := LineEdit.new()
	id_edit.text = a.id
	id_edit.editable = new_ids.has(a.id)
	id_edit.tooltip_text = "Saves, spell bars and classes use the id, so it is locked once saved." if not id_edit.editable else "Made from the name until you save (camelCase, like the others). Locked after that."
	id_edit.text_submitted.connect(func(t): _rename_new(t.strip_edges()))
	id_edit.focus_exited.connect(func(): _rename_new(id_edit.text.strip_edges()))
	UI.row(g, "ID", id_edit)
	UI.row(g, "Description", UI.text_box(a, "desc", _changed, true, 70), "The tooltip: what it does, in the player's words.")
	if a.has("kind"):
		var kinds := []
		for k in DataStore.SPELL_KINDS:
			kinds.append([k, k.capitalize()])
		UI.row(g, "Kind", UI.choice(kinds, a.kind, func(k): _set_kind(k)), str(DataStore.SPELL_KINDS.get(a.kind, {}).get("about", "")))
		UI.note(form, str(DataStore.SPELL_KINDS.get(a.kind, {}).get("about", "")), Color(0.6, 0.6, 0.6))
		g = UI.grid(form)
	else:
		UI.note(form, "This ability runs on its own code (%s), so only its numbers and text can change here." % a.id, Color("d0b070"))
		g = UI.grid(form)
	var k: Dictionary = DataStore.SPELL_KINDS.get(a.get("kind"), {})
	var targets := [["enemy", "An enemy"], ["self", "Yourself"]] + ([["ground", "The ground"]] if k.get("ground") else [])
	UI.row(g, "Target", UI.choice(targets, a.get("target"), func(v): _put("target", v, true)))
	if a.get("target") != "self" or a.has("range"):
		UI.row(g, "Range", UI.spin(a.get("range", 0), 0, 60, 0.5, func(v): _put("range", v if v > 0 else null), " m"), "How far away the target may be.")
	UI.row(g, "School", UI.choice([[null, "(none)"]] + DataStore.SCHOOLS.map(func(x): return [x, x.capitalize()]), a.get("school"), func(v): _put("school", v)), "Physical damage is cut by armour; the others by resistance.")
	if a.get("kind") in ["instant", "dot", "cast"]:
		UI.row(g, "From a bow", UI.check(a.get("ranged", false), "Shot from the ranged weapon (needs a bow and an arrow)", func(on): _put("ranged", true if on else null, true)))
	UI.row(g, "On the bar", UI.check(a.get("bar", true) != false, "Can sit on the spell bar and shows in the spellbook", func(on): _put("bar", null if on else false)))

	_tuning(a)
	_amounts(a, "cost", "Cost", "What it spends: mana, or a class bar (resolve, energy, focus...).")
	_amounts(a, "gain", "Gain", "What it gives back: combo points, resolve...")
	_other(a)
	_classes(a)
	_skill(a)


## another kind: its target follows, and the numbers it needs are added
func _set_kind(k: String) -> void:
	var a := current
	var kd: Dictionary = DataStore.SPELL_KINDS[k]
	a.kind = k
	if kd.enemy:
		a.target = "enemy"
		if not a.has("range"):
			a.range = 5
	elif a.get("target") == "enemy" or (a.get("target") == "ground" and not kd.get("ground")):
		a.target = "self"
	if not (k in ["instant", "dot", "cast"]):
		a.erase("ranged")
	if not a.has("tuning"):
		a.tuning = {}
	for key in DataStore.needed_tuning(a):
		if not a.tuning.has(key):
			a.tuning[key] = 0
	_changed(true)


func _tuning(a: Dictionary) -> void:
	UI.heading(form, "Numbers")
	var need := DataStore.needed_tuning(a)
	if need.size():
		UI.note(form, "A %s needs: %s. Damage is in hit points at level 1; multipliers are of a weapon hit (1 = 100%%). Times are in seconds." % [a.kind, ", ".join(need)], Color(0.6, 0.6, 0.6))
	if not a.has("tuning"):
		a.tuning = {}
	var t: Dictionary = a.tuning
	var g := UI.grid(form)
	for key in t.keys():
		var h := HBoxContainer.new()
		h.add_child(UI.spin(t[key], -1000, 100000, 0.01, func(v):
			t[key] = v
			_changed()))
		var x := UI.button("✕", func():
			t.erase(key)
			_changed(true), "Remove this number" if not need.has(key) else "Needed by this kind")
		x.disabled = need.has(key)
		h.add_child(x)
		UI.row(g, key, h)
	var missing := need.filter(func(n): return not t.has(n))
	for m in missing:
		form.add_child(UI.button("+ %s (needed)" % m, func():
			t[m] = 0
			_changed(true)))
	var add := UI.hbox(form)
	var key_edit := LineEdit.new()
	key_edit.placeholder_text = "another number, e.g. healPercent"
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.add_child(key_edit)
	add.add_child(UI.button("Add", func():
		var key := key_edit.text.strip_edges()
		if key != "" and not t.has(key):
			t[key] = 0
			_changed(true)))


## cost or gain: {resource: amount}
func _amounts(a: Dictionary, key: String, label: String, tip: String) -> void:
	UI.heading(form, label)
	UI.note(form, tip, Color(0.6, 0.6, 0.6))
	var d: Dictionary = a.get(key, {})
	var res := s.resource_ids()
	for r in d.keys():
		var h := UI.hbox(form)
		var o := UI.choice(res.map(func(x): return [x, x.capitalize()]), r, func(v):
			if v == r or d.has(v):
				return
			var n = d[r]
			d.erase(r)
			d[v] = n
			_changed(true))
		o.custom_minimum_size.x = 200
		h.add_child(o)
		h.add_child(UI.spin(d[r], 1, 1000, 1, func(v):
			d[r] = v
			_changed()))
		h.add_child(UI.button("✕", func():
			d.erase(r)
			if d.is_empty():
				a.erase(key)
			_changed(true), "Remove"))
	var unused := res.filter(func(x): return not d.has(x))
	if unused.size():
		form.add_child(UI.button("+ Add %s" % label.to_lower(), func():
			if not a.has(key):
				a[key] = d
			d[unused[0]] = 10
			_changed(true)))


## the fields the form has no control for (applies, follow, loadouts...), as JSON
func _other(a: Dictionary) -> void:
	UI.heading(form, "Other fields")
	UI.note(form, "Auras it applies, follow-ups, what it needs equipped and the like, as JSON (see the top of abilities.json). Left as it is unless the text reads as JSON.", Color(0.6, 0.6, 0.6))
	var other := {}
	for k in a:
		if not FORM_KEYS.has(k):
			other[k] = a[k]
	var box := TextEdit.new()
	box.text = JSON.stringify(other, "  ") if other.size() else "{}"
	box.custom_minimum_size.y = 90
	form.add_child(box)
	var bad := UI.note(form, "", Color("e08070"))
	var held := {"k": other.keys()} # the keys the box last wrote
	box.text_changed.connect(func():
		var v = JSON.parse_string(box.text)
		if not v is Dictionary:
			bad.text = "Not JSON yet: not saved."
			return
		bad.text = ""
		for k in held["k"]:
			a.erase(k)
		held["k"] = []
		for k in v:
			if not FORM_KEYS.has(k):
				a[k] = v[k]
				held["k"].append(k)
		_changed())


## which classes have it, and whether each knows it from the start or learns
## it from a trainer
func _classes(a: Dictionary) -> void:
	UI.heading(form, "Classes")
	if a.has("skill"):
		UI.note(form, "A skill's tool: it comes with the %s skill, not a class." % s.skill(a.skill).get("name", a.skill))
		return
	UI.note(form, "Tick a class to put it in that class's spellbook. Then either they know it from the start, or a trainer teaches it once they reach a level, for coins.", Color(0.6, 0.6, 0.6))
	var npcs := [[null, "Knows it from the start"]] + s.npc_choices().map(func(c): return [c[0], "Taught by " + c[1]])
	for c in s.archetypes:
		var box := UI.hbox(form)
		var book: Array = c.get("abilities", [])
		var has: bool = book.has(a.id)
		box.add_child(UI.check(has, c.get("name", c.id), func(on):
			if on:
				book.append(a.id)
			else:
				book.erase(a.id)
				_untrain(c, a.id)
			s.touch("archetypes")
			_changed(true)))
		if not has:
			continue
		var fixed: bool = c.get("bar", []).has(a.id) or c.get("defensive") == a.id
		var entry := _trained(c, a.id)
		var who := UI.choice(npcs, entry.get("trainer"), func(v):
			if v == null:
				_untrain(c, a.id)
			elif entry.is_empty():
				if not c.has("trained"):
					c.trained = []
				c.trained.append({"ability": a.id, "trainer": v, "level": 2, "cost": 10})
			else:
				entry.trainer = v
			s.touch("archetypes")
			_changed(true))
		who.disabled = fixed
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(who)
		if fixed:
			who.tooltip_text = "It is on the class's starting bar (or is its defensive), so they know it from the start."
		if not entry.is_empty():
			var lv := Label.new()
			lv.text = "from level"
			box.add_child(lv)
			box.add_child(UI.spin(entry.get("level", 1), 1, 60, 1, func(v):
				entry.level = v
				s.touch("archetypes")))
			var cl := Label.new()
			cl.text = "for"
			box.add_child(cl)
			box.add_child(UI.spin(entry.get("cost", 0), 0, 100000, 1, func(v):
				entry.cost = v
				s.touch("archetypes"), " coins"))
			box.add_child(UI.button("Open", func(): open_record.emit("npc", entry.trainer), "Open the trainer on the NPCs tab"))


static func _trained(c: Dictionary, id) -> Dictionary:
	for t in c.get("trained", []):
		if t.get("ability") == id:
			return t
	return {}


func _untrain(c: Dictionary, id) -> void:
	var t := _trained(c, id)
	if t.is_empty():
		return
	c.trained.erase(t)
	if c.trained.is_empty():
		c.erase("trained")
	s.touch("archetypes")


func _skill(a: Dictionary) -> void:
	if not s.classes_with(a.id).is_empty():
		return
	UI.heading(form, "Skill")
	var h := UI.hbox(form)
	var o := UI.choice([[null, "(not a skill's tool)"]] + s.skills.map(func(x): return [x.id, x.get("name", x.id)]), a.get("skill"), func(v):
		var old = a.get("skill")
		if old != null:
			var sk := s.skill(old)
			sk.get("teaches", []).erase(a.id)
			s.touch("skills")
		_put("skill", v)
		if v != null:
			var sk := s.skill(v)
			if not sk.has("teaches"):
				sk.teaches = []
			if not sk.teaches.has(a.id):
				sk.teaches.append(a.id)
			s.touch("skills")
		_changed(true))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(o)
	if a.has("skill"):
		h.add_child(UI.button("Open", func(): open_record.emit("skill", a.skill), "Open the skill on the Skills tab"))
	UI.note(form, "A skill's tool comes with the skill, learned from its trainer (Camping teaches Set Camp).", Color(0.6, 0.6, 0.6))


# ------------------------------------------------------------------ actions
## lowerCamelCase from a name: "Hallowed Bolt" -> hallowedBolt
static func _camel(name: String) -> String:
	var words := DataStore.slug(name).split("_", false)
	var out := ""
	for i in words.size():
		out += words[i] if i == 0 else words[i].capitalize()
	return out


## ask what kind of spell and its name; then(a) is called with the new spell
func _new_dialog(then := Callable()) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "New spell"
	var box := VBoxContainer.new()
	dlg.add_child(box)
	var g := UI.grid(box)
	var kinds := []
	for k in DataStore.SPELL_KINDS:
		kinds.append([k, "%s: %s" % [k.capitalize(), DataStore.SPELL_KINDS[k].about]])
	var pick := {"kind": "instant"}
	UI.row(g, "Kind", UI.choice(kinds, "instant", func(v): pick.kind = v))
	var n := UI.line("", func(_t): pass)
	n.placeholder_text = "Name, e.g. Searing Brand"
	UI.row(g, "Name", n)
	dlg.confirmed.connect(func():
		var a := create(pick.kind, n.text.strip_edges() if n.text.strip_edges() != "" else "New spell")
		if then.is_valid():
			then.call(a)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(560, 160))


## a new spell of a kind, with the numbers that kind needs
func create(kind: String, spell_name: String) -> Dictionary:
	var k: Dictionary = DataStore.SPELL_KINDS[kind]
	var a := {"id": s.unique_id(s.abilities, _camel(spell_name)), "name": spell_name, "kind": kind, "school": "physical", "target": "enemy" if k.enemy else "self"}
	if k.enemy:
		a.range = 20 if kind in ["cast", "dot", "channel", "control"] else 5
	a.desc = ""
	var t := {}
	for key in ["cooldown"] + k.tuning:
		t[key] = 6 if key == "cooldown" else 1
	a.tuning = t
	if kind == "control":
		a.applies = {"name": spell_name, "duration": 4, "stun": 1}
	s.abilities.append(a)
	new_ids[a.id] = true
	s.touch("abilities")
	select(a.id)
	return a


func _rename_new(id: String) -> void:
	var a := current
	if not new_ids.has(a.get("id")) or id == "" or id == a.id:
		return
	id = s.unique_id(s.abilities, id)
	for c in s.archetypes:
		var book: Array = c.get("abilities", [])
		if book.has(a.id):
			book[book.find(a.id)] = id
			s.touch("archetypes")
		for t in c.get("trained", []):
			if t.get("ability") == a.id:
				t.ability = id
	for sk in s.skills:
		var teaches: Array = sk.get("teaches", [])
		if teaches.has(a.id):
			teaches[teaches.find(a.id)] = id
			s.touch("skills")
	new_ids.erase(a.id)
	new_ids[id] = true
	a.id = id
	_changed()
	refresh_list()


func _duplicate() -> void:
	if current.is_empty():
		return
	var a := current.duplicate(true)
	a.id = s.unique_id(s.abilities, current.id + "Copy")
	a.name = str(current.get("name", "")) + " copy"
	a.erase("skill")
	s.abilities.insert(s.abilities.find(current) + 1, a)
	new_ids[a.id] = true
	s.touch("abilities")
	select(a.id)


func _delete() -> void:
	if current.is_empty():
		return
	var a := current
	var named := PackedStringArray()
	for c in s.archetypes:
		if JSON.stringify(c).contains("\"%s\"" % a.id):
			named.append("class " + c.get("name", c.id))
	for o in s.abilities:
		if o != a and JSON.stringify(o).contains("\"%s\"" % a.id):
			named.append("ability " + o.id)
	for sk in s.skills:
		if sk.get("teaches", []).has(a.id):
			named.append("skill " + sk.id)
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete ability"
	dlg.dialog_text = "Delete %s (%s)?" % [a.get("name", ""), a.id]
	if named.size():
		dlg.dialog_text += "\n\nIt is still named in: %s.\nChange those too, or the checks will fail." % ", ".join(named)
	dlg.confirmed.connect(func():
		s.abilities.erase(a)
		new_ids.erase(a.id)
		current = {}
		s.touch("abilities")
		refresh_list()
		_build()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
