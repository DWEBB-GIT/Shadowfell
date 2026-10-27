@tool
extends HSplitContainer
## Skills: what a trainer teaches for coins (data/skills.json), such as
## Camping or Fishing. A skill unlocks the abilities it teaches (its tools,
## which name it as their `skill`); one with a top rank rises with use.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

const KEY_ORDER := ["id", "name", "trainer", "cost", "maxRank", "teaches", "desc"]

## open another record (an npc, an ability) on its own tab
signal open_record(kind: String, id: String)

var s: DataStore
var list: ItemList
var form: VBoxContainer
var current: Dictionary = {}
var new_ids := {} ## skills made since the last save: their id can still change
var problems: Callable ## set by the screen: () -> PackedStringArray


func setup(store: DataStore) -> void:
	s = store
	name = "Skills"
	split_offset = 260
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var top := UI.hbox(left)
	top.add_child(UI.button("New skill", func(): new_skill({}), "Make a new skill a trainer teaches"))
	top.add_child(UI.button("Delete", _delete, "Delete the chosen skill"))
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
	for sk in s.skills:
		var i := list.add_item("%s (%s)" % [sk.get("name", sk.id), s.npc_name(sk.get("trainer"))] + ("   new" if new_ids.has(sk.id) else ""))
		list.set_item_metadata(i, sk.id)
		list.set_item_tooltip(i, sk.id)
		if sk == current:
			list.select(i)


func select(id) -> void:
	current = s.skill(id)
	refresh_list()
	_build()


func _changed(rebuild := false) -> void:
	var copy := current.duplicate()
	current.clear()
	for k in KEY_ORDER:
		if copy.has(k):
			current[k] = copy[k]
	for k in copy:
		if not current.has(k):
			current[k] = copy[k]
	s.touch("skills")
	if rebuild:
		refresh_list()
		_build.call_deferred()


func _build() -> void:
	UI.clear(form)
	if current.is_empty():
		UI.note(form, "Choose a skill on the left, or press New skill.")
		return
	var sk := current
	var title := Label.new()
	title.text = str(sk.get("name", sk.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	if problems.is_valid():
		for p in problems.call():
			if p.begins_with("Skill %s:" % sk.id):
				UI.note(form, "⚠ " + p.trim_prefix("Skill %s: " % sk.id), Color("e08070"))
	UI.heading(form, "Skill")
	var g := UI.grid(form)
	UI.row(g, "Name", UI.line(str(sk.get("name", "")), func(t):
		sk.name = t
		title.text = t
		if new_ids.has(sk.id):
			_rename_new(DataStore.slug(t))
		_changed()))
	var id_edit := LineEdit.new()
	id_edit.text = sk.id
	id_edit.editable = false
	id_edit.tooltip_text = "Made from the name until you save. Saves use it, so it is locked after that."
	UI.row(g, "ID", id_edit)
	var h := HBoxContainer.new()
	var who := UI.choice(s.npc_choices(), sk.get("trainer"), func(v):
		sk.trainer = v
		_changed(true))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(who)
	h.add_child(UI.button("Open", func(): open_record.emit("npc", sk.get("trainer")), "Open the trainer on the NPCs tab"))
	UI.row(g, "Trainer", h, "Who teaches it: a Train choice appears when you talk to them.")
	UI.row(g, "Cost", UI.spin(sk.get("cost", 0), 0, 100000, 1, func(v):
		sk.cost = v
		_changed(), " coins"))
	UI.row(g, "Top rank", UI.spin(sk.get("maxRank", 0), 0, 1000, 1, func(v):
		if v > 0:
			sk.maxRank = v
		else:
			sk.erase("maxRank")
		_changed()), "0: it does not rise. Otherwise it rises with use up to this rank, as Fishing and Cooking do.")
	UI.row(g, "Description", UI.text_box(sk, "desc", _changed, true, 64))

	UI.heading(form, "Crafting")
	var has_craft: bool = sk.get("craft") is Dictionary
	form.add_child(UI.check(has_craft, "Has recipes: a crafting window (like Cooking and Smelting)", func(on):
		if on:
			sk.craft = {"window": sk.get("name", "Crafting"), "verb": "make", "button": "Make", "station": "a workbench"}
		else:
			sk.erase("craft")
		_changed(true)))
	if has_craft:
		var cr: Dictionary = sk.craft
		var cg := UI.grid(form)
		for f in [["window", "Window title", "The crafting window's name."], ["verb", "Verb", "In the log: You %s the ..."], ["button", "Button", "The button that makes it."], ["station", "Station", "Where it is done, in words: a forge, a fire..."]]:
			var key: String = f[0]
			UI.row(cg, f[1], UI.line(str(cr.get(key, "")), func(txt):
				cr[key] = txt
				_changed()), f[2])

	UI.heading(form, "Teaches")
	UI.note(form, "Abilities that come with the skill, for its spellbook page (Professions). Each names this skill as its skill.", Color(0.6, 0.6, 0.6))
	if not sk.has("teaches"):
		sk.teaches = []
	var teaches: Array = sk.teaches
	for id in teaches.duplicate():
		var row := UI.hbox(form)
		var b := LinkButton.new()
		b.text = s.ability_name(id)
		b.tooltip_text = id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): open_record.emit("ability", id))
		row.add_child(b)
		row.add_child(UI.button("✕", func():
			teaches.erase(id)
			var a := s.ability(id)
			if a.get("skill") == sk.id:
				a.erase("skill")
				s.touch("abilities")
			_changed(true), "Stop teaching it"))
	var spare := s.ability_choices(func(a): return not teaches.has(a.id) and s.classes_with(a.id).is_empty() and (not a.has("skill") or a.skill == sk.id) and a.id not in ["strike", "autoShot"])
	var bar := UI.hbox(form)
	if spare.size():
		bar.add_child(UI.choice([[null, "+ teach an ability"]] + spare, null, func(v):
			if v == null:
				return
			teaches.append(v)
			s.ability(v).skill = sk.id
			s.touch("abilities")
			_changed(true)))
	bar.add_child(UI.button("New ability for this skill", func(): open_record.emit("new_ability", sk.id), "Make a new ability on the Abilities tab that this skill teaches"))
	var recipes := s.recipes.filter(func(r): return r.get("skill") == sk.id)
	if recipes.size():
		UI.note(form, "%d recipe%s use this skill (recipes.json)." % [recipes.size(), "" if recipes.size() == 1 else "s"], Color(0.6, 0.6, 0.6))


## A new skill; `base` may give its trainer.
func new_skill(base: Dictionary) -> void:
	var sk := {"id": s.unique_id(s.skills, "new_skill"), "name": "New skill", "trainer": base.get("trainer", s.npcs[0].id if s.npcs.size() else ""), "cost": 10, "teaches": [], "desc": ""}
	s.skills.append(sk)
	new_ids[sk.id] = true
	s.touch("skills")
	select(sk.id)


func _rename_new(id: String) -> void:
	var sk := current
	if not new_ids.has(sk.get("id")) or id == "" or id == sk.id:
		return
	id = s.unique_id(s.skills, id)
	for a in s.abilities:
		if a.get("skill") == sk.id:
			a.skill = id
			s.touch("abilities")
	new_ids.erase(sk.id)
	new_ids[id] = true
	sk.id = id
	_changed()
	refresh_list()
	_build.call_deferred()


func _delete() -> void:
	if current.is_empty():
		return
	var sk := current
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete skill"
	dlg.dialog_text = "Delete %s (%s)?" % [sk.get("name", ""), sk.id]
	var named := PackedStringArray()
	for a in s.abilities:
		if a.get("skill") == sk.id:
			named.append("ability " + a.id)
	for r in s.recipes:
		if r.get("skill") == sk.id:
			named.append("recipe " + r.id)
	if named.size():
		dlg.dialog_text += "\n\nIt is still named in: %s.\nChange those too, or the checks will fail." % ", ".join(named)
	if not new_ids.has(sk.id):
		dlg.dialog_text += "\n\nIt has been saved before, so players may have learned it."
	dlg.confirmed.connect(func():
		s.skills.erase(sk)
		new_ids.erase(sk.id)
		current = {}
		s.touch("skills")
		refresh_list()
		_build()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
