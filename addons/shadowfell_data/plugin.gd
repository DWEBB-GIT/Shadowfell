@tool
extends EditorPlugin
## Adds a "Game Data" screen next to 2D, 3D and Script: items, loot tables,
## quests, npcs and their shops, and chests, read from and saved to data/*.json.

const Main := preload("main.gd")

var main: Control


func _enter_tree() -> void:
	main = Main.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(main)
	_make_visible(false)


func _exit_tree() -> void:
	if main:
		main.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if main:
		main.visible = visible


func _get_plugin_name() -> String:
	return "Game Data"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("ResourcePreloader", "EditorIcons")
