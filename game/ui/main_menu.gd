class_name MainMenu
extends RefCounted
## The main menu (Escape, with nothing else to close; Dan, 2026-10-29):
## Settings, Logout, Exit Game and Return to Game. Logout and Exit Game wait
## COUNTDOWN seconds first, with a Cancel button, as WoW does; a fight,
## death or Escape cancels the wait too. The world keeps running meanwhile.

const COUNTDOWN := 10.0

var game
var hud
var panel: PanelContainer
var wait_panel: PanelContainer
var wait_label: Label
var leaving := "" ## "logout" | "exit" while counting down
var left := 0.0


func _init(g, h) -> void:
	game = g
	hud = h
	var root: Control = hud.root
	panel = UI.panel(root, 0, UI.WINDOW)
	panel.add_theme_stylebox_override("panel", UI.frame(Vector4(26, 20, 26, 22), "window", 20))
	panel.custom_minimum_size = Vector2(240, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(panel, 8)
	var t := UI.label(v, "Main Menu", 20, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.rule(v)
	_button(v, "Settings", _settings)
	UI.gap(v, 10)
	_button(v, "Logout", func(): _start("logout"))
	_button(v, "Exit Game", func(): _start("exit"))
	UI.gap(v, 10)
	_button(v, "Return to Game", close)
	panel.visible = false
	# the countdown, under the top of the screen so the world stays in view
	wait_panel = UI.panel(root, 14, UI.WINDOW)
	wait_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var wv := UI.vbox(wait_panel, 10)
	wait_label = UI.label(wv, "", 16, UI.TEXT)
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_label.custom_minimum_size = Vector2(260, 0)
	var bb := UI.hbox(wv, 8)
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.button(bb, "Cancel", cancel, 14)
	wait_panel.visible = false


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := UI.button(parent, text, cb, 15)
	b.custom_minimum_size = Vector2(0, 32)


var is_open: bool:
	get:
		return panel.visible


func open() -> void:
	if hud.modal != null:
		return
	game.audio.sfx("panel", 0.6)
	hud.modal = "menu"
	hud.root.move_child(hud.backdrop, -1)
	hud.root.move_child(panel, -1)
	hud.backdrop.visible = true
	panel.visible = true


## Escape or Return to Game. Returns false when there was nothing to close.
func close() -> bool:
	if leaving != "":
		cancel()
		return true
	if not panel.visible:
		return false
	game.audio.sfx("panel", 0.6)
	panel.visible = false
	hud.backdrop.visible = false
	if hud.modal == "menu":
		hud.modal = null
	return true


func _settings() -> void:
	close()
	hud.show_window("settings")


func _start(what: String) -> void:
	if game.player.dead:
		hud.toast("You cannot leave while defeated.")
		return
	close()
	leaving = what
	left = COUNTDOWN
	hud.root.move_child(wait_panel, -1)
	wait_panel.visible = true
	_show()


func cancel() -> void:
	leaving = ""
	wait_panel.visible = false


func _show() -> void:
	wait_label.text = "%s in %d" % ["Logging out" if leaving == "logout" else "Exiting the game", ceili(left)]


func update(dt: float) -> void:
	if leaving == "":
		return
	if game.player.dead:
		cancel()
		return
	if game.resources.in_combat:
		cancel()
		hud.error("You cannot leave in the middle of a fight.")
		return
	left -= dt
	if left > 0:
		_show()
		return
	var what := leaving
	cancel()
	if what == "logout":
		game.log_out()
	else:
		game.exit_game()


func layout(vp: Vector2) -> void:
	for p in [panel, wait_panel]:
		p.size = p.get_combined_minimum_size()
	panel.position = ((vp - panel.size) / 2).round()
	wait_panel.position = Vector2(roundf((vp.x - wait_panel.size.x) / 2), roundf(vp.y * 0.22))
