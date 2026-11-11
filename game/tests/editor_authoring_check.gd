extends SceneTree
## Authoring regression tests; all fixtures live under user://.
const IO := preload("res://addons/shadowfell_data/json_io.gd")
const EditorWorld := preload("res://addons/shadowfell_data/world_editor.gd")
const Catalog := preload("res://addons/shadowfell_world/catalog.gd")
const Sculpt := preload("res://addons/shadowfell_world/sculpt.gd")
const Page := preload("res://addons/shadowfell_data/abilities_page.gd")
const DataStore := preload("res://addons/shadowfell_data/store.gd")
const Checks := preload("res://addons/shadowfell_data/checks.gd")
const Fields := preload("res://addons/shadowfell_data/ability_fields.gd")
var FIXTURE := "user://editor_authoring_check_%d" % Time.get_ticks_usec()
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE)
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "act1")
	DB.ready = false
	DB.ensure()
	var store := DataStore.new()
	var data_copy := FIXTURE + "/data"
	DirAccess.make_dir_recursive_absolute(data_copy)
	for file in DataPaths.entries():
		DirAccess.copy_absolute(ProjectSettings.globalize_path(DataPaths.path_for(file)), ProjectSettings.globalize_path(data_copy + "/" + file + ".json"))
	store.data_dir = data_copy
	store.load_all()
	var validation := Checks.run(store)
	check(validation.is_empty(), "authored data validates before edits: %s" % str(validation))
	var page := Page.new()
	page.setup(store)
	root.add_child(page)
	for id in ["ambush", "tarTrap", "divineStorm", "brace", "holyStrike"]:
		page.select(id)
		check(not page.current.is_empty() and page.form.get_child_count() > 10, "ability form builds: " + id)
	check(Fields.FIELDS.has("perPoint") and Fields.FIELDS.has("bothHands") and Fields.FIELDS.has("armTime") and Fields.FIELDS.has("healPerHit"), "library offers finisher, off-hand, trap and healing options")
	check(not Fields.applicable("armTime", {"kind": "burst"}) and Fields.applicable("healPerHit", {"kind": "burst"}), "field library distinguishes incompatible mechanics")
	var ability: Dictionary = page.create("instant", "Authoring test")
	ability.desc = "A test finisher."
	ability.tuning.erase("damageMin")
	ability.tuning.erase("damageMax")
	ability.tuning.damageMultiplier = 1.2
	ability.tuning.perPoint = 0.3
	ability.tuning.bothHands = 1
	ability.spendsAll = "combo"
	ability.applies = {"name": "Slowed", "duration": 3, "slow": 50, "then": {"name": "Stunned", "duration": 2, "stun": 1}}
	ability.execute = {"below": 30, "percent": 50}
	ability.stacks = {"id": "testStacks", "name": "Test", "max": 3, "duration": 10, "critBonus": 5}
	ability.loadouts = {"dualWield": {"tuning": {"bothHands": 1, "damageMultiplier": 1.4}}}
	page.select(ability.id)
	check(Checks.run(store).is_empty(), "composed finisher, chained aura, execute, stacks and loadout validate")
	var warrior: Dictionary = store.archetypes[0]
	store.set_spell_source(warrior, ability.id, "bar")
	page._rename_new("authoringRenamed")
	check(warrior.bar.has("authoringRenamed") and not warrior.bar.has("authoringTest"), "renaming a new spell updates the starting bar")
	ability.tuning.tickInterval = 0
	check(Array(Checks.run(store)).any(func(message): return message.contains("tickInterval must be greater")), "unsafe tick interval is caught")
	ability.tuning.erase("tickInterval")
	check(store.save_all().size() == 2, "ability and class edits save to fixture data")
	var reread: Dictionary = IO.load_file(data_copy + "/abilities.json")
	var persisted := DataStore.find(reread.abilities, "authoringRenamed")
	check(IO.same(persisted.get("loadouts"), ability.loadouts) and IO.same(persisted.get("applies"), ability.applies) and persisted.tuning.bothHands == 1, "advanced ability mechanics survive save/reload")
	page.free()
	# No authoring files are written by these ability checks.
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	DB.ready = false
	DB.ensure()
	var active_store := DataStore.new()
	active_store.load_all()
	check(active_store.map_id == "new" and active_store._path("world").ends_with("new_map/spawns.json"), "Game Data targets new-map placements")
	var active_copy := FIXTURE + "/active_data"
	DirAccess.make_dir_recursive_absolute(active_copy + "/terrain/new_map")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(active_store._path("world")), ProjectSettings.globalize_path(active_copy + "/terrain/new_map/spawns.json"))
	active_store.data_dir = active_copy
	active_store.npc_spawns.append({"npc": "tam", "position": [270, -150], "facing": 90})
	active_store.touch("world")
	check(active_store.save_all().size() == 1, "Game Data saves an NPC into the active map's placement file")
	var active_saved: Dictionary = IO.load_file(active_copy + "/terrain/new_map/spawns.json")
	check(active_saved.npcSpawns.size() >= 1 and not active_saved.has("bounds") and IO.same(active_saved.get("buildings", []), active_store._world_disk.get("buildings", [])), "new-map data saving preserves its own authored buildings without copying Act 1")
	var catalog := Catalog.models()
	check(catalog.any(func(row): return str(row[1]).begins_with("res://assets/environment/nature/") and str(row[1]).ends_with(".gltf")), "installed nature models are discovered")
	var model := "res://assets/environment/nature/trees/CommonTree_1.gltf"
	check(Assets.has(model), "a project glTF scene can be instantiated")
	var world := EditorWorld.new()
	root.add_child(world)
	world.rebuild()
	check(world.get_node_or_null("Props") != null and world.get_node_or_null("NPCs") != null, "new map has editable groups")
	# the map's generated overlays (the test hub city) are shown in the game, not edited here
	var extra := DB.overlay_lists("spawns")
	check(world.get_node("Houses").get_child_count() == DB.world.houses.size() - extra.get("houses", []).size() and world.get_node("Buildings").get_child_count() == DB.world.buildings.size() - extra.get("buildings", []).size() and world.get_node("Ponds").get_child_count() == DB.world.water.size() - extra.get("water", []).size(), "houses, enterable buildings and fishing water are visible in the world editor")
	check(not world.has_unsaved_changes(), "opening the map creates no pending placement changes")
	var precise := {"model": model, "position": DB.world.playerStart.position.duplicate(), "scale": 0.3456789, "rotation": 0, "rotation3": [0, 90, 90]}
	var precise_marker := world.make_marker("Props", precise)
	var precise_out := EditorWorld._record({"name": "Props", "list": "props", "file": "scenery", "turn": "rotation", "scale": "scale"}, precise_marker, {})
	check(IO.same(precise, precise_out), "precise scales and full rotations survive opening without edits")
	precise_marker.free()
	var wp := FIXTURE + "/spawns.json"
	var sp := FIXTURE + "/scenery.json"
	IO.save_file(wp, world._files.world)
	IO.save_file(sp, world._files.scenery)
	world._paths = {"world": wp, "scenery": sp}
	var original_text := FileAccess.get_file_as_string(wp)
	check(world.save_world().is_empty() and FileAccess.get_file_as_string(wp) == original_text, "untouched map save writes nothing")
	var start: Array = DB.world.playerStart.position
	var prop := world.make_marker("Props", {"model": model, "position": start.duplicate(), "collider": 0.5, "tint": "93b091"})
	world.attach(prop, world.get_node("Props"))
	prop.position.y += 1.25
	prop.rotation_degrees = Vector3(12, 34, 3)
	prop.scale = Vector3(1, 2, 3)
	var npc := world.make_marker("NPCs", {"npc": "tam", "position": [start[0] + 4, start[1]], "facing": 90})
	world.attach(npc, world.get_node("NPCs"))
	var enemy := world.make_marker("Enemies", {"id": "authoring_enemy", "enemy": "ghoul", "position": [start[0] + 8, start[1]]})
	world.attach(enemy, world.get_node("Enemies"))
	var duplicate := world.make_marker("Enemies", enemy.get_meta("record"))
	world.attach(duplicate, world.get_node("Enemies"))
	check(world.has_unsaved_changes(), "moving and placing records marks the world changed")
	check(world.save_world().size() == 2, "world and scenery save together to fixture files")
	var saved_world: Dictionary = IO.load_file(wp)
	var saved_scenery: Dictionary = IO.load_file(sp)
	var transformed: Array = saved_scenery.props.filter(func(p): return IO.same(p.get("scale3", []), [1, 2, 3]) and IO.same(p.get("rotation3", []), [12, 34, 3]))
	check(transformed.size() == 1, "the edited prop is found among existing placements")
	if transformed.is_empty():
		world.free()
		quit(1)
		return
	var placed: Dictionary = transformed[0]
	check(IO.same(placed.scale3, [1, 2, 3]) and IO.same(placed.rotation3, [12, 34, 3]) and absf(placed.heightOffset - 1.25) < 0.02, "full prop transform survives saving")
	var ids := []
	for record in saved_world.enemySpawns:
		check(not ids.has(record.id), "spawn id remains unique: " + str(record.id))
		ids.append(record.id)
	var loaded_world := DB.new_map_world(IO.load_file("res://data/world/world.json"), wp)
	var loaded_scenery := DB.new_map_scenery(IO.load_file("res://data/world/scenery.json"), sp)
	check(loaded_world.npcSpawns == saved_world.npcSpawns and loaded_world.enemySpawns == saved_world.enemySpawns and loaded_scenery.props == saved_scenery.props, "runtime reads saved new-map NPC, enemy and scenery records")
	var runtime := World.prop_instance(placed)
	check(runtime.position.is_equal_approx(prop.position) and runtime.scale.is_equal_approx(prop.scale) and runtime.rotation.is_equal_approx(prop.rotation), "runtime renders the same prop transform as the editor")
	runtime.free()
	check(not world.has_unsaved_changes() and world.save_world().is_empty(), "a second save is a no-op")
	# Painting overrides the map image; undo restores the original colour path.
	var brush := Sculpt.new()
	var before = Terrain.ground_colour(start[0], start[1])
	brush.begin_stroke()
	brush.apply(Sculpt.PAINT, start[0], start[1], 12, 1, 0.1, 0, Terrain.SAND)
	check(Terrain.ground_colour(start[0], start[1]) == null, "surface paint is visible over the map image")
	var states := brush.end_stroke()
	brush.restore(states[0])
	check(Terrain.ground_colour(start[0], start[1]) == before, "undo restores the map image colour")
	brush.begin_stroke()
	var corner := Vector2(snappedf(start[0], Land.CHUNK), snappedf(start[1], Land.CHUNK))
	var affected := brush.apply(Sculpt.RAISE, corner.x, corner.y, 1, 1, 0.1)
	var chunk := Vector2i(floori(corner.x / Land.CHUNK), floori(corner.y / Land.CHUNK))
	check(affected.has(chunk) and affected.has(chunk + Vector2i(-1, 0)) and affected.has(chunk + Vector2i(0, -1)) and affected.has(chunk + Vector2i(-1, -1)), "sculpting a chunk corner refreshes all four shared meshes")
	states = brush.end_stroke()
	brush.restore(states[0])
	world.free()
	# Independent instances must not share tint edits.
	var a := Assets.instance(model)
	var b := Assets.instance(model)
	var meshes := b.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "nature model contains renderable meshes")
	if not meshes.is_empty():
		var original_material = meshes[0].get_active_material(0)
		Assets.tint_instance(a, Color("668866"))
		var changed_meshes := a.find_children("*", "MeshInstance3D", true, false)
		check(changed_meshes[0].get_active_material(0) != original_material and meshes[0].get_active_material(0) == original_material, "per-instance tint preserves the pack's shared materials")
	a.free()
	b.free()
	Terrain.reload_tiles()
	Terrain._ground_img = null
	Terrain._map_tex = null
	Assets._cache.clear()
	Assets._converted.clear()
	Assets._shared.clear()
	await process_frame
	print("editor_authoring_check: %d failed" % failed)
	quit(1 if failed else 0)
