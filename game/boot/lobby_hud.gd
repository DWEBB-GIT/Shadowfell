class_name LobbyHud
extends CanvasLayer
## The little of the HUD the title screen uses (hud.gd has the same names),
## for the lobby, before the game's own HUD exists.

var root: Control
var modal = "title"
var showcase := false
var pad_mode := false
var items := Tips.new()


func _init() -> void:
	name = "LobbyHud"
	UI.setup_fonts()
	root = Control.new()
	root.theme = UI.theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)


func set_pad_mode(on: bool) -> void:
	pad_mode = on


## ItemUI.tip_on, as a plain tooltip
class Tips:
	func tip_on(c: Control, text: String, _head := "") -> void:
		c.tooltip_text = text
