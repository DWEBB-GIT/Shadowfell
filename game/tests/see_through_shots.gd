extends SceneTree
## The see-through circle and nature collision (2026-11-02):
##   godot --path . --script res://game/tests/see_through_shots.gd -- out_dir
## Checks that a tree and a rock on Dan's new map block at their trunk/base,
## then saves pictures of the player standing behind a tree, a rock and a
## house (a house is put down for the picture).

const TREE := [263.0, -168.31] ## a Pine_1 near the town spot
var frames := 0
var game
var failures := 0


func _initialize() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	Store.dir = "user://see_through_shots"
	DirAccess.make_dir_recursive_absolute(Store.dir)
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)


func _save(name: String) -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png(out.path_join("see-through-%s.png" % name))
	print("saved ", name)


func _find(model: String) -> Dictionary:
	for p in Layout.props:
		if str(p.model).ends_with(model):
			return p
	return {}


func _stand_behind(x: float, z: float, gap: float) -> void:
	# the camera looks north, so "behind" is further north (smaller z)
	game.player.place_at(x, z - gap)
	game.zoom = DB.CONFIG.camera.zoomDefault
	game._snap_camera()


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		var r = game.roster.create("Shot", "warrior")
		game.enter_world(r.character.id)
	if frames == 12:
		var radius: float = game.player.radius
		for model in ["Pine_1.gltf", "CommonTree_1.gltf", "Rock_Medium_1.gltf", "TwistedTree_1.gltf"]:
			var p := _find(model)
			if p.is_empty():
				continue
			var s: float = p.get("scale", 1.0)
			var c: Array = World.model_collider(model)[0]
			var r := deg_to_rad(p.get("rotation", 0))
			var cx: float = p.position[0] + (c[0] * cos(r) + c[1] * sin(r)) * s
			var cz: float = p.position[1] + (-c[0] * sin(r) + c[1] * cos(r)) * s
			var got: Vector3 = game.collision.resolve(Vector3(cx + 0.05, 0, cz), radius)
			var d := Vector2(got.x - cx, got.z - cz).length()
			check(d >= c[2] * s + radius - 0.02, "%s pushes the player out (%.2f m)" % [model, d])
			print("%s blocks at %.2f m (collider %.2f x %.2f)" % [model, d, c[2], s])
		# indoors the circle is off: camera and focus meet, nothing is cut
		var was = game.world.indoors
		game.world.indoors = {"def": {}}
		game.world.set_cutaway(Vector3(0, 30, 20), Vector3(0, 1.2, 0))
		check(Land.cut_cam == Vector3(0, 1.2, 0), "no see-through circle indoors")
		game.world.indoors = was
		game.world.set_cutaway(Vector3(0, 30, 20), Vector3(0, 1.2, 0))
		check(Land.cut_cam == Vector3(0, 30, 20), "see-through circle outdoors")
		_stand_behind(TREE[0], TREE[1], 1.2)
	if frames == 40:
		_save("tree")
		var rock := _find("Rock_Medium_1.gltf")
		_stand_behind(rock.position[0], rock.position[1], 1.8)
	if frames == 70:
		_save("rock")
		var x: float = game.player.position.x + 40.0
		var z: float = game.player.position.z
		var h := {"id": "shot_house", "position": [x, z + 4.0], "size": [7, 5], "roof": "thatch", "walls": "plaster"}
		var mi := Town.house_visual(h)
		game.world.see_through.add_house(mi, mi.get_meta("house_form"))
		mi.position = Vector3(x, Terrain.height_at(x, z + 4.0), z + 4.0)
		game.world.group.add_child(mi)
		_stand_behind(x, z + 4.0, 1.0)
	if frames == 100:
		_save("house")
		print("see_through_shots: %d failed" % failures)
		quit(1 if failures else 0)
	return false
