extends SceneTree
## The HUD's fixed pieces stay clear of each other, and the character
## window keeps one size and place on every tab.
## godot --headless --path . --script res://game/tests/hud_layout_check.gd
## (with a display, a path after -- also saves a picture of each tab)

var game
var frame := 0
var bad := 0
var rects := {}
const TABS := ["main", "titles", "rep", "main"]


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Layout Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 20:
		var hud = game.hud
		var mm = hud.minimap
		var place: Rect2 = mm.location.get_global_rect()
		var xy: Rect2 = mm.coords.get_global_rect()
		for b in mm.zoom_buttons:
			var r: Rect2 = b.get_global_rect()
			_check(not r.intersects(place) and not r.intersects(xy), "zoom button clear of the place name and coordinates")
			_check(is_equal_approx(r.size.x, r.size.y), "zoom button is round, not a pill")
		var orbs: Array = []
		for k in hud.micro_buttons:
			orbs.append(hud.micro_buttons[k][0])
		var round_things: Array = orbs + mm.zoom_buttons
		for i in round_things.size():
			var r: Rect2 = round_things[i].get_global_rect()
			for j in range(i + 1, round_things.size()):
				var o: Rect2 = round_things[j].get_global_rect()
				var apart := r.get_center().distance_to(o.get_center()) - (r.size.x + o.size.x) / 2
				_check(apart >= 2, "rim buttons %d and %d clear of each other" % [i, j])
		for o in orbs:
			var r: Rect2 = o.get_global_rect()
			_check(not r.intersects(place) and r.position.x >= 0 and r.position.y >= 0, "menu orb on screen and clear of the place name")
		_check(not mm.get_global_rect().grow(16).intersects(hud.quests.tracker.get_global_rect()) or hud.quests.tracker.position.y > xy.end.y, "tracker under the coordinates")
		var frames: Array = [hud.char_panel, hud.target]
		hud.target.visible = true
		for f in frames:
			var r: Rect2 = f.get_global_rect()
			_check(not r.intersects(hud.bottom.get_global_rect()), "unit frame clear of the spell bar")
			_check(not r.intersects(hud.log_box.get_global_rect()), "unit frame clear of the log")
			_check(not r.intersects(hud.dock.get_global_rect()), "unit frame clear of the bag tray")
			print("  unit frame ", r)
		_check(not hud.char_panel.get_global_rect().intersects(hud.target.get_global_rect()), "unit frames clear of each other")
		hud.target.visible = false
		_check(not hud.dock.get_global_rect().intersects(hud.bottom.get_global_rect()), "bag tray clear of the spell bar")
		_check(absf(hud.dock.get_global_rect().end.y - hud.bottom.get_global_rect().end.y) < 1, "bag tray level with the spell bar")
		hud.show_window("character")
	elif frame >= 30 and (frame - 30) % 10 == 0 and (frame - 30) / 10 <= TABS.size():
		var i: int = (frame - 30) / 10
		var w = game.hud.items.character
		if i > 0:
			var r: Rect2 = w.panel.get_global_rect()
			rects[TABS[i - 1]] = r
			print("character window on %-7s %s" % [TABS[i - 1], r])
			var args := OS.get_cmdline_user_args()
			if args.size() > 0:
				root.get_texture().get_image().save_png("%s/tab_%d_%s.png" % [args[0], i - 1, TABS[i - 1]])
		if i < TABS.size():
			game.hud.items.char_tab = TABS[i]
			game.hud.items._show_char_tab()
		else:
			for t in rects:
				_check(rects[t] == rects["main"], "character window on %s same as on main" % t)
			print("hud layout: %d failed" % bad)
			quit(1 if bad else 0)
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		bad += 1
	print(("ok   " if ok else "FAIL ") + what)
