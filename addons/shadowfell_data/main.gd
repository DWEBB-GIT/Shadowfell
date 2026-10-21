@tool
extends VBoxContainer
## The Game Data screen: a toolbar (save, revert, checks) over three tabs.
## Nothing is written until Save; the game reads the files when it starts.

const DataStore := preload("store.gd")
const Checks := preload("checks.gd")
const UI := preload("ui.gd")
const ItemsPage := preload("items_page.gd")
const LootPage := preload("loot_page.gd")
const RewardsPage := preload("rewards_page.gd")

var s := DataStore.new()
var pages: Array = []
var status: Label
var save_button: Button
var problems: ItemList
var _check_queued := false


func _init(data_dir := "res://data") -> void:
	s.data_dir = data_dir
	name = "GameData"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.load_all()
	var bar := UI.hbox(self)
	save_button = UI.button("Save", save, "Write the changed data files (Ctrl+S here)")
	bar.add_child(save_button)
	bar.add_child(UI.button("Revert", revert, "Throw away unsaved changes and read the files again"))
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(status)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	for p in [ItemsPage.new(), LootPage.new(), RewardsPage.new()]:
		p.setup(s)
		tabs.add_child(p)
		pages.append(p)
	# a new item's "Add to loot table" and the loot tab stay in step
	tabs.tab_changed.connect(func(_i): _refresh_lists())
	problems = ItemList.new()
	problems.custom_minimum_size.y = 90
	problems.auto_height = false
	add_child(problems)
	s.changed.connect(_queue_check)
	_check()


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode == KEY_S and event.is_command_or_control_pressed():
		save()
		get_viewport().set_input_as_handled()


func _queue_check() -> void:
	if not _check_queued:
		_check_queued = true
		_check.call_deferred()


func _check() -> void:
	_check_queued = false
	var found := Checks.run(s)
	problems.clear()
	for p in found:
		var i := problems.add_item(p)
		problems.set_item_custom_fg_color(i, Color("e08070"))
	problems.visible = found.size() > 0
	var unsaved := ", ".join(s.dirty.keys().map(func(f): return f + ".json"))
	status.text = ("Unsaved: " + unsaved if unsaved != "" else "All saved") + ("   ·   %d check%s fail" % [found.size(), "" if found.size() == 1 else "s"] if found.size() else "   ·   all checks pass")
	save_button.disabled = s.dirty.is_empty()


func save() -> void:
	var found := Checks.run(s)
	var saved := s.save_all()
	for p in pages:
		if "new_ids" in p:
			p.new_ids.clear()
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		for f in saved:
			fs.update_file(s.data_dir + "/" + f)
	_refresh_lists()
	_check()
	status.text = "Saved " + ", ".join(saved) + ("   ·   %d check%s still fail: the browser build will refuse the data until they are fixed" % [found.size(), "" if found.size() == 1 else "s"] if found.size() else "")


func revert() -> void:
	s.load_all()
	for p in pages:
		p.reload()
	_check()


func _refresh_lists() -> void:
	for p in pages:
		if p.has_method("refresh_tree"):
			p.refresh_tree()
		elif p.has_method("refresh_list"):
			p.refresh_list()
