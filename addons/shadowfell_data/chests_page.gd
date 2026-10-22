@tool
extends HSplitContainer
## Chests: what is inside each chest in the world. (Quest rewards are on the
## Quests tab; where a chest stands is in the World editor.)

const DataStore := preload("store.gd")
const UI := preload("ui.gd")

var s: DataStore
var list: ItemList
var form: VBoxContainer
var current: Dictionary = {}


func setup(store: DataStore) -> void:
	s = store
	name = "Chests"
	split_offset = 260
	list = ItemList.new()
	list.custom_minimum_size.x = 240
	list.item_selected.connect(func(i):
		current = DataStore.find(s.chests, list.get_item_metadata(i))
		_build.call_deferred())
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
	current = {}
	refresh_list()
	_build()


func refresh_list() -> void:
	list.clear()
	for c in s.chests:
		var n: int = c.get("items", []).size()
		var i := list.add_item(str(c.get("name", c.id)) + ("  (%d item%s)" % [n, "" if n == 1 else "s"] if n else ""))
		list.set_item_metadata(i, c.id)
		list.set_item_tooltip(i, c.id)
		if c == current:
			list.select(i)


func _build() -> void:
	UI.clear(form)
	if current.is_empty():
		UI.note(form, "Choose a chest.")
		return
	var c := current
	var title := Label.new()
	title.text = str(c.get("name", c.id))
	title.add_theme_font_size_override("font_size", 22)
	form.add_child(title)
	UI.note(form, c.id)
	UI.heading(form, "Inside")
	var g := UI.grid(form)
	UI.coins_row(g, c, func(): s.touch("world"))
	UI.note(form, "Items:")
	UI.item_rows(form, s, c, "id", ["coins"], func(rebuild):
		s.touch("world")
		if rebuild:
			refresh_list()
			_build.call_deferred())
