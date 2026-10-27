class_name Game
extends Node3D
## Game initialisation and the main loop (src/main.js). Each system owns its
## own state; this node wires them together and routes input.

const HEMI := 2.1 ## three.js light intensities
const SUN := 2.3
## Godot's directional light comes out brighter than three.js's at the same
## scaled intensity; this evens the sun out, matched by side-by-side screenshots.
const SUN_MATCH := 0.42
## The colour grade over the 3D view (not the HUD), and how much brighter the
## sun is than the matched three.js one: a stronger key light against a cooler
## fill gives the shadows their depth.
const GRADE := {"brightness": 1.08, "contrast": 1.12, "saturation": 1.25}
const SUN_BOOST := 1.35
const AMBIENT := Color("7f93ad")

var started := false
var time := 0.0
var events := Events.new()
var pending_death = null
var zoom := 1.0 ## mouse wheel camera zoom (CONFIG.camera.zoomMin..zoomMax)

## Mouse aim controls (the default; Settings: Classic controls turns it off):
## the mouse aims and WASD moves. Left click attacks, talks and loots; hold it
## to aim at the cursor while walking. Right click fires spell slot 1.
var mouse_aim: bool:
	get:
		return settings == null or not settings.get_value("classicControls")
## Keyboard turning (Settings: tankControls, WoW style): A and D turn you on
## the spot, W walks the way you face, S backs up slowly. Works with either
## click scheme; the gamepad stick and click-to-move still walk directly.
var tank_controls: bool:
	get:
		return settings != null and settings.get_value("tankControls")
var random := func() -> float: return randf() ## every combat roll goes through this (tests pin it)

var scene: Node3D
var input: GameInput
var pad := Pad.new()
var collision: Collision
var world: World
var water_and_dark: WaterAndDark
var world_state: WorldState
var progression: Progression
var stats: Stats
var player: Player
var inventory: Inventory
var quests: Quests
var combat: Combat
var spells: Spells
var builds: Builds
var resources: Resources
var afterlife: Afterlife
var skills: Skills
var settings: Settings
var keys: Keybinds
var reputation: Reputation
var titles: Titles
var camp: Camp
var fishing: Fishing
var cooking: Cooking
var telegraphs: Telegraphs
var enemies: Enemies
var targeting: Targeting
var npcs: Npcs
var merchant: Merchant
var dialogue: Dialogue
var loot: Loot
var chests: Chests
var discovery: Discovery ## POI markers, discovering places, boats
var mining: Mining
var forge: Forge
var law: Law
var boons: Boons
var sparkles: Sparkles
var interaction: Interaction
var action_bar: ActionBar
var hud: Hud
var audio: AudioSystem
## set by Log out: the reloaded scene opens on character select
static var to_select := false
var fx: Fx
var save: SaveManager
var roster := Roster.new()

var archetype_id: String = DB.CONFIG.player.archetype
var character = null
var boot_save := {"status": "none"}
var region = null
var raw_aim = null
var move_to = null
var shake := 0.0
var cursor := "-" ## the cursor shown (Cursors), "" for the arrow

var env: Environment
var sun: DirectionalLight3D
var player_light: OmniLight3D
var camera: Camera3D
var camera_target := Vector3.ZERO
var fog_base = null
var _bwk := -1.0
var subzone := "" ## the named valley or place the Warden is in (WorldMap.subzone_at)
var _region_at := Vector2(INF, INF)
var _region_from := Vector2.ZERO


func _ready() -> void:
	DB.ensure()
	scene = self
	_init_renderer()
	input = GameInput.new()
	input.name = "Input"
	add_child(input)
	collision = Collision.new()
	world = World.new(self).build()
	add_child(world.group)
	water_and_dark = WaterAndDark.new(self).build()

	world_state = WorldState.new(self)
	progression = Progression.new(self)
	stats = Stats.new(self)
	player = Player.new(self)
	add_child(player.group)
	inventory = Inventory.new(self)
	quests = Quests.new(self)
	combat = Combat.new(self)
	spells = Spells.new(self)
	builds = Builds.new(self)
	resources = Resources.new(self)
	afterlife = Afterlife.new(self)
	skills = Skills.new(self)
	settings = Settings.new(self)
	keys = Keybinds.new(self)
	input.is_bound = func(code): return keys.is_bound(code)
	reputation = Reputation.new(self)
	titles = Titles.new(self)
	camp = Camp.new(self)
	fishing = Fishing.new(self)
	cooking = Cooking.new(self)
	telegraphs = Telegraphs.new(self)
	enemies = Enemies.new(self)
	targeting = Targeting.new(self)
	npcs = Npcs.new(self)
	merchant = Merchant.new(self)
	dialogue = Dialogue.new(self)
	loot = Loot.new(self)
	chests = Chests.new(self)
	discovery = Discovery.new(self).build()
	mining = Mining.new(self)
	forge = Forge.new(self)
	law = Law.new(self)
	boons = Boons.new(self)
	sparkles = Sparkles.new(self)
	interaction = Interaction.new(self)
	action_bar = ActionBar.new(self)
	# every button in every menu clicks
	get_tree().node_added.connect(_hook_click)
	hud = Hud.new(self)
	add_child(hud)
	audio = AudioSystem.new(self)
	add_child(audio)
	fx = Fx.new(self)
	save = SaveManager.new(self)

	_snap_camera()
	_show_title()


func _init_renderer() -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = DB.CONFIG.camera.renderScale
	# View-distance fog: clear around the player, swallowing the road ahead.
	# Things past `far` are not drawn at all.
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = DB.CONFIG.fog.color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# three.js's hemisphere light as flat ambient. three.js divides every
	# light by pi where Godot does not, so its intensities are scaled by 1/pi
	# (Tex.LIGHT_SCALE), and like three.js there is no tone mapping.
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = HEMI * Tex.LIGHT_SCALE
	env.ambient_light_sky_contribution = 0.0 # there is no sky: all of it is this colour
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# The grade: the matched three.js lighting reads flat and grey on screen,
	# so colour and contrast are lifted after the fact (Compatibility supports
	# these adjustments and glow; both cost one cheap full-screen pass).
	env.adjustment_enabled = true
	env.adjustment_brightness = GRADE.brightness
	env.adjustment_contrast = GRADE.contrast
	env.adjustment_saturation = GRADE.saturation
	# bright things (flames, witchlights, spell effects) bloom softly
	env.glow_enabled = true
	env.glow_normalized = true
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3] else 0.0)
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = DB.CONFIG.fog.color
	env.fog_density = 1.0
	env.fog_depth_begin = DB.CONFIG.fog.near
	env.fog_depth_end = DB.CONFIG.fog.far
	# the haze glows warm towards the low sun
	env.fog_sun_scatter = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	camera = Camera3D.new()
	camera.fov = DB.CONFIG.camera.fov
	camera.near = 0.5
	camera.far = DB.CONFIG.fog.far + 6
	add_child(camera)
	camera.make_current()

	# dusk: a low amber sun and a warm glow around the Warden
	sun = DirectionalLight3D.new()
	sun.light_color = Color("ffc888")
	sun.light_energy = SUN * Tex.LIGHT_SCALE * SUN_MATCH * SUN_BOOST
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_opacity = 0.92
	sun.shadow_blur = 1.5
	add_child(sun)
	player_light = Tex.point_light(Color("ffb070"), 5, 9, 1.6)
	player_light.shadow_enabled = false
	add_child(player_light)


func _notification(what: int) -> void:
	# autosave when the window is closed or loses focus, as the browser does on pagehide
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if save:
			save.autosave()


## The title screen and character select. Unreadable saves are copied
## aside and never overwritten; the character keeps its place in the list.
func _show_title() -> void:
	boot_save = {"status": "none"}
	var r := roster.load_roster(func(k): return save.read(k))
	var note := ""
	if r.get("legacyUnreadable"):
		note = "Your previous save could not be read. It has been kept aside and will not be overwritten."
		save.quarantine(save.read(save.key).get("raw"), save.key)
	for c in roster.list:
		var rs := save.read(c.key)
		if rs.status == "invalid":
			save.quarantine(rs.get("raw"), c.key)
			push_warning("Save for %s rejected: %s" % [c.name, rs.get("errors")])
	hud.show_title(note)


## Play as a character from the roster: their own save, or a fresh start.
func enter_world(id: String) -> void:
	var c = roster.by_id(id)
	if c == null or started:
		return
	save.key = c.key
	save.autosave_enabled = true
	boot_save = save.read()
	if boot_save.status == "invalid":
		return # the select screen does not offer it
	character = c
	# the class decides stats, resources, spellbook, bar and starting gear
	archetype_id = DB.CONFIG.player.archetype
	for k in DB.text.title.classes:
		if k.id == c.classId:
			archetype_id = k.archetype
	roster.touch(id)
	hud.set_character(c)
	start_game(boot_save.status == "ok")
	load_world()


## The warm-up behind the loading screen. The whole world already exists and
## simulates as one (as a server would for every player); rendering is the
## local player's view only. This draws everything that view can show once,
## so shaders are compiled, models loaded, sounds made and portraits painted
## before the player can move, instead of stalling the first fight.
func load_world() -> void:
	hud.show_loading()
	var tree := get_tree()
	# the sounds still to make (begun on the title screen)
	var total := maxi(1, audio.warm.size())
	while not audio.warm.is_empty():
		audio.warm_some(25000)
		hud.loading.show_progress("Gathering sounds…", 0.4 * (1.0 - float(audio.warm.size()) / total))
		await tree.process_frame
	# every model and effect drawn once in front of the camera, behind the screen
	hud.loading.show_progress("Raising the world…", 0.45)
	var shelf := _model_shelf()
	fx.prewarm(camera_target)
	await tree.process_frame
	await tree.process_frame
	shelf.queue_free()
	# target-frame portraits for everyone you can meet
	var models := {}
	for e in enemies.list:
		models[e.cfg.model] = true
	for n in npcs.list:
		if n.def.get("model"):
			models[n.def.model] = true
	var i := 0
	for m in models:
		hud.icons.portrait(m)
		i += 1
		if i % 4 == 0:
			hud.loading.show_progress("Painting faces…", 0.6 + 0.3 * i / models.size())
			await tree.process_frame
	hud.loading.show_progress("Lighting the lamps…", 1.0)
	await tree.process_frame
	await tree.process_frame
	hud.hide_loading()


## One of every model in assets/models in a grid in front of the camera, so
## each is loaded and its shaders (and shadow shaders) compiled now.
func _model_shelf() -> Node3D:
	var shelf := Node3D.new()
	shelf.name = "ModelShelf"
	scene.add_child(shelf)
	var names: Array = []
	for f in ResourceLoader.list_directory("res://assets/models/"):
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	var cols := ceili(sqrt(names.size()))
	for k in names.size():
		var m := Assets.instance(names[k])
		m.position = camera_target + Vector3((k % cols - cols / 2.0) * 1.2, 0, (k / cols - cols / 2.0) * 1.2)
		shelf.add_child(m)
	return shelf


## Back to character select: the scene is reloaded for a clean slate.
func log_out() -> void:
	if player.dead:
		hud.toast("You cannot leave while defeated.")
		return
	var r := save.save(true)
	if not r.ok:
		hud.toast(r.reason)
		return
	save.autosave_enabled = false
	to_select = true
	get_tree().reload_current_scene()


func _hook_click(n: Node) -> void:
	var b := n as BaseButton
	if b and not b.pressed.is_connected(_ui_click):
		b.pressed.connect(_ui_click)


func _ui_click() -> void:
	if audio:
		audio.click()


func start_game(resume: bool) -> void:
	audio.start()
	world_state.reset()
	progression.apply({"level": 1, "xp": 0})
	inventory.reset()
	dialogue.close()
	merchant.close()
	merchant.buyback = []
	quests.start_new()
	region = null # named again, quietly, from wherever the Warden stands
	afterlife.reset()
	skills.reset()
	builds.reset()
	law.reset()
	boons.reset()
	reputation.reset()
	titles.reset()
	pending_death = null
	telegraphs.clear()
	hud.clear_numbers()
	action_bar.reset()
	targeting.clear()
	recompute_max_health()
	player.health = player.max_health
	player.revive(Layout.player_start.position[0], Layout.player_start.position[1])
	player.facing = PI

	var resumed := false
	if resume and boot_save.status == "ok":
		save.apply(boot_save.data)
		resumed = true
	# the model wears what the class starts with (or the save has on), not
	# the warden's sword it was built with
	player.show_equipment(inventory.equipment)
	recompute_max_health()
	camp.show()
	enemies.spawn_all()
	loot.spawn_all()
	chests.spawn_all()
	mining.spawn_all()
	hud.hide_title()
	started = true
	_snap_camera()
	if resumed:
		hud.log_line("You take up the road again.", "lore")
	else:
		hud.log_line("The Fallen Road. Somewhere ahead lies the old watch post.", "lore")


# ----------------------------------------------------------- game events
func on_player_death(killer = null) -> void:
	var coins: int = inventory.coins
	var loss := mini(DB.CONFIG.death.coinLossCap, int(floor(coins * DB.CONFIG.death.coinLossFraction)))
	pending_death = {"loss": loss, "timer": DB.CONFIG.death.screenDelay}
	afterlife.on_death(killer, loss)
	events.emit("playerDied", {})
	hud.close_modal(true)
	hud.log_line("You fall.", "hurt")


## Leave the body and walk as a spirit (systems/afterlife.gd).
func release_spirit() -> bool:
	if not player.dead or pending_death == null:
		return false
	pending_death = null
	hud.hide_death()
	afterlife.release()
	_snap_camera()
	return true


## Release and return to life at once at the rest point, coins lost.
func respawn() -> void:
	if release_spirit():
		afterlife.revive_here()


func set_ghost_look(on: bool) -> void:
	env.adjustment_enabled = on
	env.adjustment_saturation = 0.15
	env.adjustment_brightness = 0.85
	env.adjustment_contrast = 1.1


## Pixels between a world point and the mouse, or INF behind the camera.
func _screen_dist(p: Vector3) -> float:
	if camera.is_position_behind(p):
		return INF
	var s := camera.unproject_position(p)
	return U.hyp(s.x - input.mouse.x, s.y - input.mouse.y)


## What is under the cursor: a body or drop to loot, a living enemy, or a
## townsperson. A living enemy wins a close call: fighting comes first.
func _pick_under_cursor():
	var best = null
	var best_d: float = DB.CONFIG.targeting.clickRadius
	# (lambdas capture by value: collect the candidates, then choose)
	var cands := []
	if player.ghost:
		for c in interaction.click_points():
			var d := _screen_dist(Vector3(c.x, Terrain.height_at(c.x, c.z) + 0.6, c.z))
			if d < best_d:
				best_d = d
				best = {"kind": "point", "obj": c}
		return best
	for e in enemies.list:
		# the body and the feet both count, so tall and short foes are easy to click
		if e.alive:
			cands.append(["enemy", e, minf(_screen_dist(e.position + Vector3(0, 1, 0)), _screen_dist(e.position + Vector3(0, 0.3, 0))) - 6])
	for n in npcs.list:
		cands.append(["npc", n, _screen_dist(n.position + Vector3(0, 1, 0))])
	for c in chests.list:
		if not chests.opened(c):
			cands.append(["chest", c, _screen_dist(Vector3(c.x, Terrain.height_at(c.x, c.z) + 0.4, c.z))])
	for sp in Layout.signposts:
		var x: float = sp.position[0]
		var z: float = sp.position[1]
		var y := Terrain.height_at(x, z)
		cands.append(["sign", sp, minf(_screen_dist(Vector3(x, y + 1.0, z)), _screen_dist(Vector3(x, y + 1.9, z)))])
	for l in loot.lootables() + loot.skinnables():
		var d := _screen_dist(Vector3(l.x, Terrain.height_at(l.x, l.z) + 0.3, l.z))
		if d < DB.CONFIG.loot.clickRadius:
			cands.append(["loot", l, d])
	for v in mining.veins():
		var d := _screen_dist(Vector3(v.x, Terrain.height_at(v.x, v.z) + 0.5, v.z))
		if d < DB.CONFIG.loot.clickRadius:
			cands.append(["vein", v, d])
	for c in interaction.click_points():
		var d := _screen_dist(Vector3(c.x, Terrain.height_at(c.x, c.z) + 0.6, c.z))
		if d < DB.CONFIG.loot.clickRadius:
			cands.append(["point", c, d])
	for c in cands:
		if c[2] < best_d:
			best_d = c[2]
			best = {"kind": c[0], "obj": c[1]}
	return best


## is the mouse on (or near) the fishing bob?
func _over_bob() -> bool:
	var bob = fishing.bob_position
	if bob == null:
		return false
	return _screen_dist(bob) < DB.CONFIG.fishing.clickRadius


## The mouse cursor says what a click would do (WoW): a sword over an
## enemy, a speech bubble over a townsperson (grey until you are close
## enough to talk), a hand over loot, a hook over your fishing bob.
func _cursor_for(pick) -> void:
	var c := ""
	if input.mouse.onCanvas and _over_bob():
		c = "fish"
	elif pick != null:
		var p := player.position
		var o = pick.obj
		match pick.kind:
			"enemy":
				c = "attack"
			"npc":
				var near := U.hyp(o.position.x - p.x, o.position.z - p.z) <= DB.CONFIG.shop.talkRange + 0.5 and not collision.wall_between(p.x, p.z, o.position.x, o.position.z)
				c = "talk" if near else "talkFar"
			"loot", "chest":
				var reach: float = 2.4 if pick.kind == "chest" else DB.CONFIG.loot.reach
				c = "loot" if U.hyp(o.x - p.x, o.z - p.z) <= reach else "lootFar"
			"vein":
				c = "mineFar" if _far(o.x, o.z, Mining.tuning().get("reach", 2.6)) else "mine"
			"point":
				c = "lootFar" if _far(o.x, o.z, o.get("reach", DB.CONFIG.interaction.radius)) else "loot"
	if c != cursor:
		cursor = c
		Cursors.show(c)


func _far(x: float, z: float, reach: float) -> bool:
	return U.hyp(x - player.position.x, z - player.position.z) > reach or collision.wall_between(player.position.x, player.position.z, x, z)


## out of reach: walk up and act on arrival (click to move), or say so
func _reach_or(x: float, z: float, reach: float, act: Callable, too_far: Callable, walk: bool) -> void:
	if not _far(x, z, reach):
		act.call()
	elif walk:
		move_to = {"x": x, "z": z, "reach": reach - 0.3, "then": act}
	else:
		too_far.call()


## Left click selects, right click acts (WoW): right on an enemy starts
## auto attack, on a townsperson talks, and either button loots.
func _click(button: String) -> bool:
	# a click on (or near) the fishing bob strikes
	if _over_bob():
		return fishing.strike()
	var pick = _pick_under_cursor()
	# With click to move (Settings) a click on the ground walks there, and a
	# click on something out of reach walks up to it and then acts.
	var walk: bool = settings.get_value("clickToMove")
	move_to = null
	# a left click on the ground lets go of the target; a right click does not.
	# With mouse aim a left click there attacks whoever is near the cursor.
	if pick == null:
		if button == "left" and mouse_aim:
			_engage_near_cursor()
		elif button == "left":
			targeting.clear()
		var at = _aim_point() if walk and input.mouse.onCanvas else null
		if at != null:
			# holding the button keeps walking towards the cursor (Diablo / WoW)
			move_to = {"x": at.x, "z": at.z, "reach": 0.25, "hold": button}
			fx.move_marker(at.x, at.z)
		return false
	var closer := func(): hud.error("You need to be closer to interact with that target.")
	var o = pick.obj
	match pick.kind:
		"sign":
			hud.show_signpost(o)
		"chest":
			_reach_or(o.x, o.z, 2.4, func(): chests.open(o), closer, walk)
		"loot":
			_reach_or(o.x, o.z, DB.CONFIG.loot.reach, func(): loot.start_skin(o) if o.kind == "skin" else loot.loot_area(o), func(): events.emit("log", {"text": "Too far away to loot that.", "kind": "muted", "throttle": "loot-far"}), walk)
		"vein":
			_reach_or(o.x, o.z, Mining.tuning().get("reach", 2.6), func(): mining.start(o.o), closer, walk)
		"point":
			_reach_or(o.x, o.z, o.get("reach", DB.CONFIG.interaction.radius), func(): o.run.call(), closer, walk)
		"enemy":
			if button == "right" or mouse_aim:
				targeting.engage(o)
				# walking in, the Warden follows the enemy until it is in reach
				if not targeting.target_in_reach and walk and not targeting.target_in_shot:
					move_to = {"follow": o, "reach": 0.0}
				elif not targeting.target_in_reach and not targeting.target_in_shot:
					hud.error("Out of range")
			else:
				targeting.select(o)
		"npc":
			# either button selects a townsperson and talks to them, if close enough
			targeting.select_friendly(o)
			_reach_or(o.position.x, o.position.z, DB.CONFIG.shop.talkRange + 0.5, func(): npcs.talk(o), closer, walk)
	return true


## Mouse aim, left button on open ground (or held): engage the enemy nearest
## the cursor within reach of your weapon, if you are not already fighting.
func _engage_near_cursor() -> void:
	if targeting.attacking and targeting.current != null and targeting.current.alive:
		return
	var reach: float = stats.ranged_reach if stats.has_ranged else DB.abilities.strike.range + 1
	var e = targeting.soft_target(raw_aim, reach)
	if e != null:
		targeting.engage(e)


## Mouse aim, right button: on someone or something to use it acts as it
## always did (talk, loot, the bob); anywhere else it fires spell slot 1.
func _right_click_aim() -> void:
	if not _over_bob():
		var pick = _pick_under_cursor()
		if pick == null or pick.kind == "enemy":
			input.pressed["MouseRight"] = true
			return
	_click("right")


## Click to move: the way to walk this frame, or null. Arriving runs the
## action the walk was for; any movement key takes over and ends it.
func _click_move(keys_move: Dictionary):
	var m = move_to
	if m == null:
		return null
	if keys_move.x or keys_move.z or player.dead:
		move_to = null
		return null
	var p := player.position
	if m.has("follow"):
		if not m.follow.alive or targeting.current != m.follow or targeting.target_in_reach:
			move_to = null
			return null
		m.x = m.follow.position.x
		m.z = m.follow.position.z
	elif m.has("hold"):
		var held: bool = input.mouse.leftHeld if m.hold == "left" else input.mouse.rightHeld
		var at = _aim_point() if held and input.mouse.onCanvas else null
		if at != null:
			m.x = at.x
			m.z = at.z
			# keep walking while held, however close the cursor is
			if U.hyp(m.x - p.x, m.z - p.z) <= 0.4:
				return null
		else:
			# let go: the marker shows where the walk ends
			m.erase("hold")
			fx.move_marker(m.x, m.z)
	var dx: float = m.x - p.x
	var dz: float = m.z - p.z
	var d := U.hyp(dx, dz)
	if d <= maxf(0.2, m.reach):
		move_to = null
		if m.has("then"):
			m.then.call()
		return null
	return {"x": dx / d, "z": dz / d}


## Maximum health comes from level plus worn gear (the helm).
func recompute_max_health() -> void:
	# current health stays as it is (60/100 becomes 60/150): changing gear
	# never heals; only a lower maximum can cut it
	player.max_health = stats.max_health
	player.health = minf(player.health, player.max_health)
	events.emit("statsChanged", {})


func respawn_point() -> Dictionary:
	return afterlife.rest_point()


func rest_at_shrine(shrine = null) -> void:
	if shrine == null:
		shrine = Layout.shrines[0]
	var first: bool = not world_state.examined.has("shrine")
	world_state.examined["shrine"] = true
	player.health = player.max_health
	# respawn just in front of the shrine, on the road side
	world_state.respawn = {"x": shrine.position[0] - 1.8, "z": shrine.position[1]}
	world_state.shrine_activated = shrine.id
	world_state.rest_point = "shrine"
	events.emit("shrineRest", {})
	if first:
		hud.log_line(DB.examine_text("shrine_first"), "lore")
	hud.log_line("You rest a while. Your wounds close, and you will return here if you fall.", "heal")
	hud.toast("Rested at the shrine")


func manual_save() -> Dictionary:
	var result := save.save(true)
	if result.ok:
		hud.toast("Game saved")
		hud.log_line("Game saved.", "muted")
	else:
		hud.toast(result.reason, "bad")
		hud.log_line(result.reason, "hurt")
	return result


# -------------------------------------------------------------- the loop
func _aim_point():
	var m := Vector2(input.mouse.x, input.mouse.y)
	var plane := Plane(Vector3.UP, player.position.y + 0.5)
	return plane.intersects_ray(camera.project_ray_origin(m), camera.project_ray_normal(m))


## Aim for pad play: the right stick if pushed, otherwise straight ahead
## (or the way the left stick points), a few metres out.
func _pad_aim() -> Vector3:
	var p := player.position
	var r := pad.right
	var l := pad.left
	var dir: Vector2
	if r.z > 0.3:
		dir = Vector2(r.x, r.y)
	elif l.z > 0.3:
		dir = Vector2(l.x, l.y)
	else:
		dir = Vector2(sin(player.facing), cos(player.facing))
	var n := dir.normalized() if dir.length() > 0 else Vector2(0, 1)
	return Vector3(p.x + n.x * 4, p.y, p.z + n.y * 4)


func _handle_input(dt: float):
	var B := Pad.BUTTONS
	pad.poll()
	# switch prompts to whichever device was touched last
	if pad.active and pad.now.any(func(v): return v):
		hud.set_pad_mode(true)
	if not input.pressed.is_empty() or input.mouse.clicked:
		hud.set_pad_mode(false)

	var notches := input.consume_wheel()
	if notches and started:
		var c: Dictionary = DB.CONFIG.camera
		zoom = clampf(zoom + notches * c.zoomStep, c.zoomMin, _zoom_max())
	if hud.modal == "title":
		hud.title.update(dt)
		return null
	if hud.modal == "loading":
		return null
	if input.consume("Escape") and not hud.close_modal():
		targeting.clear()
	if hud.modal == "death":
		if input.consume("Enter") or keys.pressed("interact") or pad.pressed(B.A):
			release_spirit()
		return null
	if hud.modal == "document":
		if pad.pressed(B.B) or pad.pressed(B.A):
			hud.close_modal()
		return null
	if keys.pressed("bags") or pad.pressed(B.START):
		hud.toggle_panel("bags")
	if keys.pressed("character") or pad.pressed(B.VIEW):
		hud.toggle_panel("character")
	for w in ["spellbook", "talents", "skills", "settings"]:
		if keys.pressed(w):
			hud.toggle_panel(w)
	# D-pad right opens and closes the log (it moves the highlight in the bags)
	if keys.pressed("map"):
		hud.toggle_world_map()
	if keys.pressed("quests") or (not hud.any_window_open and not dialogue.is_open and pad.pressed(B.RIGHT)):
		hud.toggle_panel("quests")
	# With a window open the pad drives the window; the world keeps running
	# and the keyboard and mouse still play, as in WoW.
	var pad_menu: bool = hud.any_window_open
	if pad_menu:
		hud.window_gamepad(pad, dt)
	elif pad.pressed(B.UP):
		hud.toggle_panel("spellbook")
	if keys.pressed("save") or (not pad_menu and pad.pressed(B.DOWN)):
		manual_save()
	if hud.blocks_gameplay:
		return null
	if keys.pressed("interact") or (not pad_menu and not pad.held(B.LEFT) and pad.pressed(B.A)):
		if fishing.active:
			fishing.strike()
		else:
			interaction.interact()
	var pad_on := not pad_menu
	# a spirit only walks
	if player.ghost:
		# a click on your body or the rest point acts, as Space does
		var hover = _pick_under_cursor() if input.mouse.onCanvas else null
		_cursor_for(hover)
		var clicked := input.consume_click()
		if input.consume_right_click() or clicked:
			if hover != null:
				_reach_or(hover.obj.x, hover.obj.z, hover.obj.get("reach", DB.CONFIG.interaction.radius), func(): hover.obj.run.call(), func(): hud.error("You need to be closer to interact with that target."), false)
		var gm := input.move_axis()
		return {"move": {"x": pad.left.x, "z": pad.left.y} if pad_on and pad.left.z > 0 else {"x": gm.x, "z": gm.y}, "aim": null, "actions": {}}
	if player.dead:
		return null
	if keys.pressed("sheathe"):
		player.set_sheathed(not player.sheathed)
	if keys.pressed("sit"):
		player.set_sitting(not player.sitting)

	var km := input.move_axis()
	var keys_move: Dictionary = {"x": pad.left.x, "z": pad.left.y} if pad_on and pad.left.z > 0 else {"x": km.x, "z": km.y}
	var cm = _click_move(keys_move)
	var move: Dictionary = cm if cm != null else keys_move
	# keyboard turning: the keys turn and walk you, relative to your facing
	var tank = null
	if tank_controls and cm == null and not (pad_on and pad.left.z > 0):
		tank = input.tank_axis()
	var using_pad := pad_on and (pad.left.z > 0 or pad.right.z > 0 or hud.pad_mode)
	var p := func(b: int) -> bool: return pad_on and pad.pressed(b)
	var aim_now = _pad_aim() if using_pad else _aim_point()
	raw_aim = aim_now
	var tg := targeting
	# Tab / R3 cycle targets; RT engages whoever is selected or ahead
	if keys.pressed("cycleTarget") or p.call(B.RS):
		tg.cycle(aim_now)
	if p.call(B.RT):
		var who = tg.current if tg.current != null else tg.soft_target(aim_now, DB.CONFIG.targeting.range)
		if tg.engage(who) and not tg.target_in_reach:
			hud.error("Out of range")
	# hovering over anyone in the world shows who they are
	if not using_pad:
		var hover = _pick_under_cursor() if input.mouse.onCanvas else null
		hud.world_tip(hover)
		_cursor_for(hover)
	# classic: left click selects, right click attacks, talks or loots.
	# Mouse aim: left click attacks, talks or loots, right click is slot 1.
	if input.consume_click():
		_click("left")
	if input.consume_right_click():
		if mouse_aim:
			_right_click_aim()
		else:
			_click("right")
	# Mouse aim: the left button held aims you at the cursor (or at your
	# target, once you are swinging at it); so does the right stick
	var face_aim = null
	if mouse_aim:
		if using_pad:
			face_aim = aim_now if pad_on and pad.right.z > 0.3 else null
		elif input.mouse.leftHeld and aim_now != null:
			_engage_near_cursor()
			var t = tg.current
			face_aim = t.position if tg.attacking and t != null and (tg.target_in_reach or tg.target_in_shot) else aim_now
	# each spell-bar slot has a fixed key; whatever ability sits there fires
	var util := pad_on and pad.held(B.LEFT)
	var slots := [
		keys.pressed("bar0") or (not util and p.call(B.X)),
		keys.pressed("bar1") or (not util and p.call(B.Y)),
		keys.pressed("bar2") or p.call(B.RB),
		keys.pressed("bar3") or p.call(B.LB),
		keys.pressed("bar4") or p.call(B.LT),
		keys.pressed("bar5") or (not util and p.call(B.B)),
		# utility slots: 6-9, or D-pad left held with a face button
		keys.pressed("bar6") or (util and p.call(B.X)),
		keys.pressed("bar7") or (util and p.call(B.Y)),
		keys.pressed("bar8") or (util and p.call(B.A)),
		keys.pressed("bar9") or (util and p.call(B.B)),
	]
	var actions: Dictionary = action_bar.actions(slots)
	# Auto attack (WoW): once engaged the Warden swings whenever the target
	# is in reach, in front of him, and his weapon is ready. It is not on the bar.
	actions.strike = tg.attacking and tg.target_in_reach
	# beyond it, with a bow in the ranged slot, Auto Shot
	actions.shoot = tg.attacking and tg.target_in_shot
	return {
		"move": move,
		"aim": tg.current.position if actions.strike or actions.shoot else tg.aim_for(aim_now, DB.abilities.strike.range),
		"rawAim": aim_now,
		"faceAim": face_aim,
		"tank": tank,
		"actions": actions,
	}


func _process(delta: float) -> void:
	step(minf(delta, 0.1)) # clamp long stalls


## One simulation step. Exposed so tests can advance time deterministically.
func step(dt: float) -> void:
	var controls = _handle_input(dt) # also runs on the title screen, for the pad
	input.end_frame()
	var paused: bool = not started or hud.blocks_gameplay
	if not paused:
		time += dt
		player.update(dt, controls)
		spells.update(dt)
		combat.update_arrows(dt)
		resources.update(dt)
		camp.update(dt, time)
		fishing.update(dt)
		cooking.update(dt)
		mining.update(dt, time)
		law.update(dt)
		boons.update(dt)
		water_and_dark.update(dt, time)
		discovery.update(dt)
		enemies.update(dt)
		npcs.update(dt)
		merchant.update()
		dialogue.update()
		telegraphs.update(dt)
		targeting.update(dt, raw_aim, DB.abilities.strike.range + 1)
		interaction.update()
		loot.update(dt, time)
		sparkles.update(dt)
		fx.update(dt)
		audio.update(dt)
		if pending_death != null and hud.modal != "death":
			pending_death.timer -= dt
			if pending_death.timer <= 0:
				hud.show_death(pending_death.loss, respawn_point().kind)
	world.update(dt, Time.get_ticks_msec() / 1000.0)
	_update_region(dt)
	world.update_indoors(dt, player.position)
	_update_camera(dt)
	if started:
		hud.update(dt)


## Which region and named place the Warden is in, and the air there: the
## fog and light shade smoothly into the gloom of the Blackwood and other
## dark woods. The region is looked up every few metres, and a new one only
## counts once you are a little way into it, so a border does not flicker.
func _update_region(dt: float) -> void:
	var p := player.position
	var k := move_toward(_bwk, Terrain.gloom(p.x, p.z), dt * 0.6) if _bwk >= 0.0 else Terrain.gloom(p.x, p.z)
	if k != _bwk:
		_bwk = k
		var bw: Dictionary = DB.CONFIG.blackwood
		var fog: Dictionary = DB.CONFIG.fog
		fog_base = {"near": lerpf(fog.near, bw.fogNear, k), "far": lerpf(fog.far, bw.fogFar, k)}
		env.fog_light_color = (fog.color as Color).lerp(bw.fogColor, k)
		env.background_color = env.fog_light_color
		var light := lerpf(1, bw.light, k)
		env.ambient_light_energy = HEMI * Tex.LIGHT_SCALE * light
		sun.light_energy = SUN * Tex.LIGHT_SCALE * SUN_MATCH * SUN_BOOST * light
	if region != null and Vector2(p.x - _region_at.x, p.z - _region_at.y).length() < 2.0:
		return
	_region_at = Vector2(p.x, p.z)
	var r := DB.region_at(p.x, p.z)
	if region != null and r.id != region.id:
		# only once a few metres in (looking ahead along the way you walk)
		var ahead := Vector2(p.x - _region_from.x, p.z - _region_from.y).normalized() * 6.0
		if DB.region_at(p.x - ahead.x, p.z - ahead.y).id != r.id:
			r = region
	_region_from = Vector2(p.x, p.z)
	if region == null or r.id != region.id:
		var first: bool = region != null
		region = r
		events.emit("regionChanged", {"region": r, "announce": first and started})
	var sub := WorldMap.subzone_at(p.x, p.z)
	if sub != subzone:
		subzone = sub
		events.emit("subzoneChanged", {"name": sub, "announce": started})


func _snap_camera() -> void:
	camera_target = player.position
	world.update_indoors(0, player.position)
	_place_camera()


func _update_camera(dt: float) -> void:
	# exponential smoothing: the same feel at any frame rate
	var k := 1 - exp(-DB.CONFIG.camera.followSharpness * dt)
	camera_target = camera_target.lerp(player.position, k)
	_place_camera(dt)


## a kick of the camera when a blow lands (see CONFIG.impact)
func shake_camera(amount: float) -> void:
	shake = maxf(shake, amount)


## character select and creation: the camera stands in front of the
## character, low, so they fill the middle of the screen
func _place_showcase() -> void:
	var p := player.position
	var fx_ := sin(player.facing)
	var fz := cos(player.facing)
	var d: Dictionary = DB.CONFIG.camera.showcase
	camera.position = Vector3(p.x + fx_ * d.distance - fz * d.side, p.y + d.height, p.z + fz * d.distance + fx_ * d.side)
	camera.look_at(Vector3(p.x - fz * d.side * 0.5, p.y + d.lookHeight, p.z + fx_ * d.side * 0.5))
	_place_sun(p)
	player_light.position = Vector3(p.x + fx_ * 1.5, p.y + 2.2, p.z + fz * 1.5)
	world.set_cutaway(camera.position, p + Vector3(0, 1.2, 0))


## the sun sits up and to the west of the target, as three.js placed it
func _place_sun(t: Vector3) -> void:
	sun.position = Vector3(t.x - 14, t.y + 26, t.z + 6)
	sun.look_at(t)


func _classic_camera() -> bool:
	return settings != null and settings.get_value("classicCamera")


func _zoom_max() -> float:
	var c: Dictionary = DB.CONFIG.camera
	return c.zoomMax if _classic_camera() else c.tilt.zoomMax


## Where the camera sits from the player at distance scale `z`. Classic: one
## angle (CONFIG.camera.offset). Otherwise the angle follows the zoom: low
## and close for towns and exploring, steeper further out for fights.
func _camera_offset(z: float) -> Vector3:
	var c: Dictionary = DB.CONFIG.camera
	if _classic_camera():
		return c.offset * z
	var k: Dictionary = c.tilt
	var pitch: float
	if zoom <= 1.0:
		pitch = lerpf(k.pitchNear, k.pitchMid, clampf(inverse_lerp(c.zoomMin, 1.0, zoom), 0, 1))
	else:
		pitch = lerpf(k.pitchMid, k.pitchFar, clampf(inverse_lerp(1.0, k.zoomMax, zoom), 0, 1))
	var d: float = (c.offset as Vector3).length() * k.distance * z
	var a := deg_to_rad(pitch)
	return Vector3(0, sin(a) * d, cos(a) * d)


func _place_camera(dt := 0.0) -> void:
	if not started and hud and hud.showcase:
		_place_showcase()
		return
	# a fixed isometric view: the scenes are composed for this one angle;
	# indoors the camera closes in a little, under where the roof was
	zoom = minf(zoom, _zoom_max())
	var z := zoom * (1 - DB.CONFIG.camera.indoorZoom * world.indoor_blend)
	var o := _camera_offset(z)
	var t := camera_target
	var sx := 0.0
	var sy := 0.0
	if shake > 0.001:
		sx = sin(time * 71) * shake
		sy = cos(time * 53) * shake
		shake *= exp(-DB.CONFIG.impact.shakeDecay * dt)
	else:
		shake = 0
	camera.position = Vector3(t.x + o.x + sx, t.y + o.y + sy, t.z + o.z)
	# fog is measured from the camera: zooming moves it with the camera, so
	# the Warden's surroundings stay as clear at any zoom
	if fog_base != null:
		var extra: float = o.length() - (DB.CONFIG.camera.offset as Vector3).length()
		env.fog_depth_begin = fog_base.near + extra
		env.fog_depth_end = fog_base.far + extra
		camera.far = env.fog_depth_end + 6
	camera.look_at(Vector3(t.x + sx, t.y + 1.0 + sy, t.z - DB.CONFIG.camera.lookAhead * z)) # a little ahead, up the road
	_place_sun(t)
	var p := player.position
	player_light.position = Vector3(p.x, p.y + 2.4, p.z + 0.6)
	world.set_cutaway(camera.position, p + Vector3(0, 1.2, 0))
