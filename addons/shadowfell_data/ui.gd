@tool
extends RefCounted
## Small builders for the editor's forms, so each page reads as a list of
## fields rather than a pile of node setup.

const DataStore := preload("store.gd")


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func heading(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("e8c873"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	parent.add_child(gap)
	parent.add_child(l)
	parent.add_child(HSeparator.new())
	return l


static func note(parent: Node, text: String, colour := Color(0.7, 0.7, 0.7)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l


## a "label: control" line in a two-column grid
static func row(grid: GridContainer, label: String, control: Control, tip := "") -> Control:
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tip != "":
		control.tooltip_text = tip
	grid.add_child(control)
	return control


static func grid(parent: Node) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	parent.add_child(g)
	return g


static func line(text: String, on_change: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.text_changed.connect(on_change)
	return e


static func spin(value: float, lo: float, hi: float, step: float, on_change: Callable, suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.suffix = suffix
	s.custom_minimum_size.x = 110
	s.value_changed.connect(on_change)
	return s


static func check(on: bool, text: String, on_change: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(on_change)
	return c


## a dropdown of [value, label] pairs; calls on_change(value)
static func choice(options: Array, current, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	var at := -1
	for i in options.size():
		o.add_item(str(options[i][1]))
		o.set_item_metadata(i, options[i][0])
		if options[i][0] == current:
			at = i
	if at == -1 and current != null:
		o.add_item("%s (unknown)" % current)
		o.set_item_metadata(o.item_count - 1, current)
		at = o.item_count - 1
	o.select(at)
	o.item_selected.connect(func(i): on_change.call(o.get_item_metadata(i)))
	return o


static func button(text: String, on_press: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	return b


static func hbox(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	return h


## A button naming an item, in its rarity colour, that opens a searchable
## list. `filter` (optional) narrows the list; on_pick(id) is called.
static func item_picker(s: DataStore, current, on_pick: Callable, filter := Callable(), empty := "Choose an item…") -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = 220
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var show := func(id):
		var d := s.item(id)
		b.text = d.get("name", empty if id == null else str(id) + " (unknown)")
		b.add_theme_color_override("font_color", s.rarity_colour(d.get("rarity")) if not d.is_empty() else Color(0.75, 0.75, 0.75))
		b.tooltip_text = "" if d.is_empty() else "%s · %s" % [d.id, s.rarity(d.get("rarity")).get("name", "")]
	show.call(current)
	b.pressed.connect(func():
		pick_item(b, s, filter, func(id):
			show.call(id)
			on_pick.call(id)))
	return b


static func pick_item(near: Control, s: DataStore, filter: Callable, on_pick: Callable) -> void:
	var pop := PopupPanel.new()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 380)
	pop.add_child(box)
	var search := LineEdit.new()
	search.placeholder_text = "Search items"
	box.add_child(search)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var fill := func(q: String):
		list.clear()
		for d in s.items:
			if filter.is_valid() and not filter.call(d):
				continue
			if q != "" and not (d.get("name", "").to_lower().contains(q.to_lower()) or d.id.contains(q.to_lower())):
				continue
			var i := list.add_item("%s   (%s)" % [d.get("name", d.id), DataStore.KIND_NAMES.get(d.get("kind"), d.get("kind"))])
			list.set_item_metadata(i, d.id)
			list.set_item_custom_fg_color(i, s.rarity_colour(d.get("rarity")))
	fill.call("")
	search.text_changed.connect(fill)
	var choose := func(i):
		var id = list.get_item_metadata(i)
		pop.hide()
		on_pick.call(id)
	list.item_activated.connect(choose)
	list.item_clicked.connect(func(i, _at, _btn): choose.call(i))
	search.text_submitted.connect(func(_t):
		if list.item_count > 0:
			choose.call(0))
	pop.popup_hide.connect(pop.queue_free)
	near.add_child(pop)
	pop.popup(Rect2i(Vector2i(near.get_screen_position() + Vector2(0, near.size.y)), Vector2i(340, 380)))
	search.grab_focus()


## Coins from min to max, rolled when given; equal ends save a plain number.
## `on_change` is called after `d.coins` changes.
static func coins_row(g: GridContainer, d: Dictionary, on_change: Callable) -> void:
	var c = d.get("coins", 0)
	var cur := [int(c.get("min", 0)), int(c.get("max", 0))] if c is Dictionary else [int(c), int(c)]
	var h := HBoxContainer.new()
	var lo := spin(cur[0], 0, 100000, 1, func(_v): pass, " min")
	var hi := spin(cur[1], 0, 100000, 1, func(_v): pass, " max")
	var save := func(_v):
		var a := int(lo.value)
		var b := int(hi.value)
		if b < a:
			hi.set_value_no_signal(a)
			b = a
		if b <= 0:
			d.erase("coins")
		elif a == b:
			d.coins = a
		else:
			d.coins = {"min": a, "max": b}
		on_change.call()
	lo.value_changed.connect(save)
	hi.value_changed.connect(save)
	h.add_child(lo)
	h.add_child(hi)
	row(g, "Coins", h, "Silver given, rolled between min and max. Set both the same for a fixed amount.")


## The item list of a reward or chest, each with a count and a remove
## button, then "Add an item…". Quests name items as `item`, chests as `id`.
## A new list goes in just after the last of `after` the holder has.
## `on_change(rebuild)` is called after each change.
static func item_rows(parent: Node, s: DataStore, holder: Dictionary, key: String, after: Array, on_change: Callable) -> void:
	var items: Array = holder.get("items", [])
	for e in items:
		var h := hbox(parent)
		h.add_child(item_picker(s, e.get(key), func(id):
			e[key] = id
			on_change.call(false)))
		var cl := Label.new()
		cl.text = "count"
		h.add_child(cl)
		h.add_child(spin(e.get("count", 1), 1, 999, 1, func(v):
			e.count = v
			on_change.call(false)))
		h.add_child(button("✕", func():
			items.erase(e)
			if items.is_empty():
				holder.erase("items")
			on_change.call(true), "Remove"))
	parent.add_child(button("Add an item…", func():
		pick_item(parent, s, Callable(), func(id):
			if not holder.has("items"):
				insert_after(holder, "items", items, after)
			items.append({key: id, "count": 1})
			on_change.call(true))))


## add a key just after the last of `after` that it has, keeping the file's order
static func insert_after(d: Dictionary, key: String, value, after: Array) -> void:
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


## A list of names, each a link; on_click(id)
static func links(parent: Node, entries: Array, on_click: Callable, empty: String) -> void:
	if entries.is_empty():
		note(parent, empty)
		return
	var flow := HFlowContainer.new()
	parent.add_child(flow)
	for e in entries:
		var b := LinkButton.new()
		b.text = str(e[1])
		b.tooltip_text = str(e[0])
		b.pressed.connect(func(): on_click.call(e[0]))
		flow.add_child(b)
		var gap := Control.new()
		gap.custom_minimum_size.x = 12
		flow.add_child(gap)


## a multi-line text box that writes into d[key] (an empty optional one is removed)
static func text_box(d: Dictionary, key: String, on_change: Callable, required := true, height := 64) -> TextEdit:
	var t := TextEdit.new()
	t.text = str(d.get(key, ""))
	t.custom_minimum_size.y = height
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.text_changed.connect(func():
		if t.text == "" and not required:
			d.erase(key)
		else:
			d[key] = t.text
		on_change.call())
	return t
