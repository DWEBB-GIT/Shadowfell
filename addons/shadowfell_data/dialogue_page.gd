@tool
extends HSplitContainer
## Dialogue: what each npc says (data/dialogue.json). Greetings (the last
## whose condition holds is said on opening), topics on the first page that
## open a node, and nodes with replies that open another node or go back.
## Quests, the shop, training and Goodbye are added by the game.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

const STATUSES := [["not_started", "not started"], ["available", "available (offered)"], ["active", "active"], ["ready", "ready to hand in"], ["done", "done"]]

## open another record (an npc) on its own tab
signal open_record(kind: String, id: String)

var s: DataStore
var list: ItemList
var form: VBoxContainer
var current: Dictionary = {}
var problems: Callable ## set by the screen: () -> PackedStringArray


func setup(store: DataStore) -> void:
	s = store
	name = "Dialogue"
	split_offset = 260
	list = ItemList.new()
	list.custom_minimum_size.x = 240
	list.item_selected.connect(func(i): select(list.get_item_metadata(i)))
	add_child(list)
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
	var id = current.get("id")
	current = {}
	if id != null:
		select(id)
	else:
		refresh_list()
		_build()


func refresh_list() -> void:
	list.clear()
	for d in s.dialogues:
		var i := list.add_item(_speakers(d.id))
		list.set_item_metadata(i, d.id)
		list.set_item_tooltip(i, d.id)
		if d == current:
			list.select(i)


## who uses a dialogue, by name
func _speakers(id) -> String:
	var who := s.npcs.filter(func(n): return n.get("dialogue") == id).map(func(n): return n.get("name", n.id))
	return ", ".join(who) if who.size() else "%s (nobody)" % id


func select(id) -> void:
	current = s.dialogue(id)
	refresh_list()
	for i in list.item_count:
		if list.get_item_metadata(i) == id:
			list.ensure_current_is_visible()
	_build()


func _changed(rebuild := false) -> void:
	s.touch("dialogue")
	if rebuild:
		_build.call_deferred()


# ------------------------------------------------------------------ form
func _build() -> void:
	UI.clear(form)
	if current.is_empty():
		UI.note(form, "Choose a dialogue on the left. An npc without one gets one from Give them a greeting on the NPCs tab.")
		return
	var d := current
	var title := Label.new()
	title.text = _speakers(d.id)
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	UI.note(form, "Dialogue %s. Quests, the shop, training and Goodbye are added by the game." % d.id)
	for n in s.npcs.filter(func(n2): return n2.get("dialogue") == d.id):
		form.add_child(UI.button("Open %s on the NPCs tab" % n.get("name", n.id), func(): open_record.emit("npc", n.id)))
	if problems.is_valid():
		for p in problems.call():
			if p.begins_with("Dialogue %s:" % d.id):
				UI.note(form, "⚠ " + p.trim_prefix("Dialogue %s: " % d.id), Color("e08070"))

	# ---- greetings
	UI.heading(form, "Greetings")
	UI.note(form, "Said on opening: the last one in the list whose condition holds. Put the plain one first and the later story beats below it.", Color(0.6, 0.6, 0.6))
	if not d.has("greetings"):
		d.greetings = []
	var greets: Array = d.greetings
	for i in greets.size():
		var g: Dictionary = greets[i]
		var box := _card()
		var head := UI.hbox(box)
		head.add_child(_condition(g, "Said when"))
		head.add_child(_move(greets, i))
		head.add_child(UI.button("✕", func():
			greets.erase(g)
			_changed(true), "Remove this greeting"))
		box.add_child(UI.text_box(g, "text", _changed, true, 54))
	form.add_child(UI.button("+ Add greeting", func():
		greets.append({"text": ""})
		_changed(true)))

	# ---- topics
	UI.heading(form, "Topics")
	UI.note(form, "Extra lines on the first page (\"Who are you?\"), shown while their condition holds. Each opens a node below.", Color(0.6, 0.6, 0.6))
	if not d.has("topics"):
		d.topics = []
	if not d.has("nodes"):
		d.nodes = []
	var topics: Array = d.topics
	var nodes: Array = d.nodes
	var node_choices := nodes.map(func(n): return [n.id, "%s: %s" % [n.id, _short(str(n.get("text", "")))]])
	for i in topics.size():
		var t: Dictionary = topics[i]
		var box := _card()
		var g := UI.grid(box)
		UI.row(g, "Player asks", UI.line(str(t.get("prompt", "")), func(v):
			t.prompt = v
			_changed()))
		UI.row(g, "Opens", UI.choice(node_choices, t.get("node"), func(v):
			t.node = v
			_changed()))
		var h := HBoxContainer.new()
		h.add_child(_condition(t, "Shown when"))
		h.add_child(_move(topics, i))
		h.add_child(UI.button("✕", func():
			topics.erase(t)
			_changed(true), "Remove this topic (its node stays)"))
		UI.row(g, "", h)
	form.add_child(UI.button("+ Add topic", func():
		var nid := _free_node_id(d, d.id + "_topic")
		nodes.append({"id": nid, "text": "", "replies": [{"text": "I see."}]})
		topics.append({"id": nid.trim_prefix(d.id + "_"), "prompt": "", "node": nid})
		_changed(true), "A new line to ask about, with a node for the answer"))

	# ---- nodes
	UI.heading(form, "Nodes")
	UI.note(form, "What they say when a topic or reply opens a node, and the replies offered. A reply with no node goes back to the first page.", Color(0.6, 0.6, 0.6))
	for n in nodes:
		var box := _card()
		var head := UI.hbox(box)
		var id_edit := LineEdit.new()
		id_edit.text = n.id
		id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		id_edit.tooltip_text = "The node's id: topics and replies name it"
		id_edit.text_submitted.connect(func(v): _rename_node(d, n, DataStore.slug(v)))
		id_edit.focus_exited.connect(func(): _rename_node(d, n, DataStore.slug(id_edit.text)))
		head.add_child(id_edit)
		var used := _node_used(d, n.id)
		var del := UI.button("Delete node", func():
			nodes.erase(n)
			_changed(true), "Delete this node" if not used else "Topics or replies still open it")
		del.disabled = used
		head.add_child(del)
		box.add_child(UI.text_box(n, "text", _changed, true, 54))
		if not n.has("replies"):
			n.replies = []
		var replies: Array = n.replies
		for r in replies:
			var h := UI.hbox(box)
			var rl := Label.new()
			rl.text = "  ↳"
			h.add_child(rl)
			var line := UI.line(str(r.get("text", "")), func(v):
				r.text = v
				_changed())
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.placeholder_text = "What the player says"
			h.add_child(line)
			var to := UI.choice([[null, "(back to the first page)"]] + node_choices, r.get("node"), func(v):
				if v == null:
					r.erase("node")
				else:
					r.node = v
				_changed())
			to.custom_minimum_size.x = 260
			h.add_child(to)
			h.add_child(UI.button("✕", func():
				replies.erase(r)
				_changed(true), "Remove this reply"))
		var add := UI.hbox(box)
		add.add_child(UI.button("+ Reply", func():
			replies.append({"text": ""})
			_changed(true)))
		add.add_child(UI.button("+ Reply to a new node", func():
			var nid := _free_node_id(d, n.id)
			nodes.insert(nodes.find(n) + 1, {"id": nid, "text": "", "replies": [{"text": "I see."}]})
			replies.append({"text": "", "node": nid})
			_changed(true), "A reply that leads on to a new node"))


func _card() -> VBoxContainer:
	var card := PanelContainer.new()
	form.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	return box


static func _short(t: String) -> String:
	return t if t.length() <= 50 else t.substr(0, 49) + "…"


## ↑: move an entry up its list
func _move(arr: Array, i: int) -> Button:
	var b := UI.button("↑", func():
		var x = arr[i]
		arr.remove_at(i)
		arr.insert(i - 1, x)
		_changed(true), "Move up")
	b.disabled = i == 0
	return b


## A condition editor for `holder.when`: always, a quest's status, a flag or
## an examined point.
func _condition(holder: Dictionary, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	h.add_child(l)
	var c: Dictionary = holder.get("when", {})
	var kind = "quest" if c.has("quest") else "flag" if c.has("flag") else "examined" if c.has("examined") else null
	h.add_child(UI.choice([[null, "always"], ["quest", "a quest is…"], ["flag", "a flag is set"], ["examined", "they looked at…"]], kind, func(k):
		if k == "quest":
			holder.when = {"quest": s.quests[0].id if s.quests.size() else "", "status": "done"}
		elif k == "flag":
			holder.when = {"flag": ""}
		elif k == "examined":
			holder.when = {"examined": s.examine_points[0] if s.examine_points.size() else ""}
		else:
			holder.erase("when")
		_changed(true)))
	match kind:
		"quest":
			var q := UI.choice(s.quests.map(func(x): return [x.id, x.get("name", x.id)]), c.quest, func(v):
				c.quest = v
				_changed())
			q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(q)
			h.add_child(UI.choice(STATUSES, c.get("status"), func(v):
				c.status = v
				_changed()))
		"flag":
			var f := UI.line(str(c.get("flag", "")), func(v):
				c.flag = v.strip_edges()
				_changed())
			f.placeholder_text = "flag name, e.g. feud_mended"
			f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(f)
		"examined":
			var e := UI.choice(Array(s.examine_points).map(func(x): return [x, x]), c.get("examined"), func(v):
				c.examined = v
				_changed())
			e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(e)
	return h


static func _free_node_id(d: Dictionary, base: String) -> String:
	var n := 2
	var id := base + "_2"
	while d.get("nodes", []).any(func(x): return x.get("id") == id):
		n += 1
		id = "%s_%d" % [base, n]
	return id


static func _node_used(d: Dictionary, id) -> bool:
	if d.get("topics", []).any(func(t): return t.get("node") == id):
		return true
	for n in d.get("nodes", []):
		if n.get("replies", []).any(func(r): return r.get("node") == id):
			return true
	return false


## rename a node and every topic and reply that opens it
func _rename_node(d: Dictionary, n: Dictionary, id: String) -> void:
	if id == "" or id == n.id or d.nodes.any(func(x): return x.get("id") == id):
		return
	for t in d.get("topics", []):
		if t.get("node") == n.id:
			t.node = id
	for o in d.nodes:
		for r in o.get("replies", []):
			if r.get("node") == n.id:
				r.node = id
	n.id = id
	_changed(true)
