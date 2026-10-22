@tool
extends VBoxContainer
## Quest chains: every quest as a box, arrows from a quest to the quests it
## unlocks, each chain on its own band (prerequisites left, follow-ups right),
## as the browser quest editor's chain map. Drag from a quest's right edge to
## another's left edge to make the second require the first; drag an arrow
## off to remove it.

const DataStore := preload("store.gd")
const UI := preload("ui.gd")
const QuestsPage := preload("quests_page.gd")

const W := 230.0
const H := 80.0
const GX := 70.0
const GY := 24.0

## open another record (a quest) on its own tab
signal open_record(kind: String, id: String)

var s: DataStore
var graph: GraphEdit
var problems: Callable ## set by the screen: () -> PackedStringArray


func setup(store: DataStore) -> void:
	s = store
	name = "Quest chains"
	UI.note(self, "Arrows run from a quest to the quests it unlocks. Drag from a quest's right edge to another quest to make it a requirement; drag an arrow's end away to remove it. Edit opens the quest.")
	graph = GraphEdit.new()
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.connection_request.connect(_connect)
	graph.disconnection_request.connect(_disconnect)
	add_child(graph)
	refresh_tree()


func reload() -> void:
	refresh_tree()


## lay every quest out again (called when the tab is shown)
func refresh_tree() -> void:
	graph.clear_connections()
	for c in graph.get_children():
		if c is GraphNode:
			graph.remove_child(c)
			c.queue_free()
	var bad := {}
	if problems.is_valid():
		for p in problems.call():
			if p.begins_with("Quest "):
				bad[p.trim_prefix("Quest ").get_slice(":", 0)] = true
	var pos := layout(s.quests)
	for q in s.quests:
		var n := GraphNode.new()
		n.name = q.id
		n.title = str(q.get("name", q.id))
		n.position_offset = pos.get(q.id, Vector2.ZERO)
		n.custom_minimum_size = Vector2(W, H)
		n.tooltip_text = q.id
		var info := Label.new()
		var r: Dictionary = q.get("reward", {})
		info.text = "%s · %d objective%s\n%d XP%s" % [s.npc_name(q.get("giver")), q.get("objectives", []).size(), "" if q.get("objectives", []).size() == 1 else "s", r.get("xp", 0), "" if r.get("items", []).is_empty() else " · %d item%s" % [r.items.size(), "" if r.items.size() == 1 else "s"]]
		if bad.has(q.id):
			info.add_theme_color_override("font_color", Color("e08070"))
		n.add_child(info)
		n.set_slot(0, true, 0, Color("8a7a5a"), true, 0, Color("e8c873"))
		var edit := UI.button("Edit", func(): open_record.emit("quest", q.id), "Open this quest on the Quests tab")
		n.get_titlebar_hbox().add_child(edit)
		graph.add_child(n)
	for q in s.quests:
		for r in q.get("requires", []):
			if not s.quest(r).is_empty():
				graph.connect_node(r, 0, q.id, 0)


## Each chain (quests joined by requirements) on its own band: a quest's
## column is how many quests come before it. Quests on their own go last,
## three to a row.
static func layout(quests: Array) -> Dictionary:
	var by_id := {}
	for q in quests:
		by_id[q.id] = q
	var depth := {}
	for q in quests:
		_depth(q.id, by_id, depth, [])
	# join chains (union-find on requirements)
	var parent := {}
	for q in quests:
		parent[q.id] = q.id
	var root := func(x):
		while parent[x] != x:
			x = parent[x]
		return x
	for q in quests:
		for r in q.get("requires", []):
			if by_id.has(r):
				parent[root.call(r)] = root.call(q.id)
	var chains := {}
	for q in quests:
		var k = root.call(q.id)
		if not chains.has(k):
			chains[k] = []
		chains[k].append(q)
	var pos := {}
	var y := 60.0 # below the graph's toolbar
	var single := []
	for chain in chains.values():
		if chain.size() == 1:
			single.append(chain[0])
			continue
		var cols := {}
		for q in chain:
			var d: int = depth[q.id]
			if not cols.has(d):
				cols[d] = []
			cols[d].append(q)
		var rows := 0
		for d in cols:
			for i in cols[d].size():
				pos[cols[d][i].id] = Vector2(20 + d * (W + GX), y + i * (H + GY))
			rows = maxi(rows, cols[d].size())
		y += rows * (H + GY) + GY * 2
	for i in single.size():
		pos[single[i].id] = Vector2(20 + (i % 3) * (W + GX), y + floori(i / 3.0) * (H + GY))
	return pos


static func _depth(id, by_id: Dictionary, depth: Dictionary, seen: Array) -> int:
	if depth.has(id):
		return depth[id]
	if seen.has(id) or not by_id.has(id):
		return 0
	var d := 0
	for r in by_id[id].get("requires", []):
		if by_id.has(r):
			d = maxi(d, 1 + _depth(r, by_id, depth, seen + [id]))
	depth[id] = d
	return d


func _connect(from: StringName, _fp: int, to: StringName, _tp: int) -> void:
	var q := s.quest(String(to))
	if q.is_empty() or from == to:
		return
	if not q.has("requires"):
		q.requires = []
		QuestsPage._tidy(q)
	if not q.requires.has(String(from)):
		q.requires.append(String(from))
		s.touch("quests")
	graph.connect_node(from, 0, to, 0)


func _disconnect(from: StringName, _fp: int, to: StringName, _tp: int) -> void:
	var q := s.quest(String(to))
	var reqs: Array = q.get("requires", [])
	reqs.erase(String(from))
	if reqs.is_empty():
		q.erase("requires")
	s.touch("quests")
	graph.disconnect_node(from, 0, to, 0)
