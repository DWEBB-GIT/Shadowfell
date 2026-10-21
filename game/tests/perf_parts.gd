extends SceneTree
## Times each part of one game step on its own (CPU only), averaged over
## 200 runs, after the game has settled:
##   godot --headless --path . --script res://game/tests/perf_parts.gd -- x z

var frames := 0
var game


func _initialize() -> void:
	Store.dir = "user://perf_store"
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _t(label: String, f: Callable, runs := 200) -> void:
	var t := Time.get_ticks_usec()
	for i in runs:
		f.call()
	print("%-22s %7.3f ms" % [label, (Time.get_ticks_usec() - t) / 1000.0 / runs])


func _process(_d: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3:
		var r = game.roster.create("Perf", "warden")
		game.enter_world(r.character.id if r.ok else game.roster.list[0].id)
		if args.size() >= 2:
			game.player.place_at(float(args[0]), float(args[1]))
		game._snap_camera()
	if frames < 400:
		return false
	var g = game
	var dt := 1.0 / 60
	var h = g.hud
	_t("whole step", func(): g.step(dt))
	_t("handle_input", func(): g._handle_input(dt))
	_t("player", func(): g.player.update(dt, {"move": {"x": 0, "z": 0}, "aim": null, "actions": {}}))
	_t("spells", func(): g.spells.update(dt))
	_t("resources", func(): g.resources.update(dt))
	_t("camp", func(): g.camp.update(dt, g.time))
	_t("water_and_dark", func(): g.water_and_dark.update(dt, g.time))
	_t("enemies", func(): g.enemies.update(dt))
	_t("npcs", func(): g.npcs.update(dt))
	_t("merchant+dialogue", func(): g.merchant.update(); g.dialogue.update())
	_t("telegraphs", func(): g.telegraphs.update(dt))
	_t("targeting", func(): g.targeting.update(dt, g.raw_aim, 3.0))
	_t("interaction", func(): g.interaction.update())
	_t("loot", func(): g.loot.update(dt, g.time))
	_t("sparkles", func(): g.sparkles.update(dt))
	_t("fx", func(): g.fx.update(dt))
	_t("audio", func(): g.audio.update(dt))
	_t("world.update", func(): g.world.update(dt, 1.0))
	_t("region", func(): g._update_region())
	_t("world.indoors", func(): g.world.update_indoors(dt, g.player.position))
	_t("camera", func(): g._update_camera(dt))
	_t("hud.update", func(): h.update(dt))
	_t("  refresh_stats", func(): h.refresh_stats())
	_t("  slots", func(): h._refresh_slots())
	_t("  spells", func(): h._refresh_spells())
	_t("  target", func(): h._update_target())
	_t("  enemy_bars", func(): h._update_enemy_bars())
	_t("  labels", func(): h.labels.update(dt))
	_t("  quest marks", func(): h.quests.update_marks())
	_t("  items.update", func(): h.items.update(dt))
	_t("  layout", func(): h.layout())
	_t("minimap markers", func(): h.minimap.markers())
	quit()
	return false
