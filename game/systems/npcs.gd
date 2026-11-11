class_name Npcs
extends RefCounted
## Townsfolk (src/systems/npcs.js). Each NPC stands at its post, works (Mara
## hammers at her anvil) and turns to face the player when they talk to them
## (Dan, 2026-10-21: not just for walking past).
## Talking to one opens a conversation (dialogue.gd), which leads to quests
## and the shop. A spawn with `goneWhen` (a dialogue condition, such as a
## story flag) is absent while it holds.
##
## Routines (foundations step 3, Dan 2026-11-04): someone with a `routine`
## (npcs.json; a timetable from npcs.json `routines`, or their own list of
## blocks) keeps hours by the world clock (WorldState.hour): at work at their
## post, at the inn of an evening, at home overnight, walking between. A
## block is {from: hour, at: place}; the place is "work" (their post), "inn"
## (a seat in the nearest inn, a building with `rest`), "home" (the door of
## their house; they go in and are out of sight, but you can knock and they
## still answer), or a name in their spawn's `places` ({name: [x, z]}).
## Without an inn or a house near enough, that block keeps them at work.
## Anyone players come to for something (keeps_post: quests, shops, the
## forge, the bank, a bed) stays at their post round the clock while
## CONFIG.routine.servicesKeepPost is on (Dan 2026-11-11: quest givers must be
## easy to find at any hour), so only ambient townsfolk keep a routine.
##
## Simulation and drawing are separate, as for enemies (WorldStream): every
## routine runs for the whole world (a few sums per person per frame; a path
## is found once per walk, a few a frame at most), and a body is in the scene
## only near the player (WorldStream.VIEW_IN / VIEW_OUT) and out of doors.
##
## Town life (Dan 2026-11-11: "people drinking, shopping, out travelling,
## wandering merchants"): background folk from the town_life overlay
## (tools/world/new_map/town_life.py). They share a few `ambient` npcs.json
## entries; each spawn's `person` gives them their own id and name (Layout).
## Drinkers and shoppers keep routines like anyone else (a shopper's places
## are the shop fronts of their town); travellers and pedlars walk a road
## between two towns (the spawn's `path`), rest a while at each end and stay
## put overnight. Their bodies are only built the first time they come into
## view, so a hundred of them cost a few sums a frame until you meet them,
## and they are left off the minimap.

## seats in an inn (the walk-in kit's room, 12 x 9 m, door in the south wall),
## relative to its middle, clear of the tables, bar and beds
const INN_SEATS := [[0.0, 0.8], [-2.8, 2.6], [2.8, 0.6], [-3.6, -0.6], [0.6, -2.2], [-0.4, 3.0], [3.2, -1.4], [-1.8, -0.2]]
const SNAP_HOURS := 0.25 ## a clock jump bigger than this (a load, a night's sleep) puts people straight where they would be
const PATHS_PER_FRAME := 2
const PRESENCE_EVERY := 15 ## frames between quest checks for whether someone is about
const FAR_EVERY := 4 ## off-screen people update every 4th frame


class Npc:
	extends RefCounted
	var game
	var def: Dictionary
	var id: String
	var name: String
	var position: Vector3
	var post: Vector3 ## where their spawn stands them: their place of work
	var rest_facing: float
	var facing: float
	var radius := 0.4
	var group: Node3D
	var model: Node3D
	var rig: Rig
	var board := false ## a notice board: never turns or works
	var rest_timer := 0.0 ## a smith's break between bouts at the anvil
	var bout := 6 ## blows left in this bout
	var work_timer: float
	var present := true
	# ---- the daily routine
	var routine: Array = [] ## blocks {from, at}, by `from`
	var shift := 0.0 ## hours this person keeps early (-) or late (+)
	var places := {} ## name -> {at: Vector2, via: Array of Vector2 (outside first), inside: bool, facing: float}
	var place := "work" ## where they are, or are walking to
	var from_place := "" ## where a walk being planned starts ("" from wherever they stand)
	var route: Array = [] ## waypoints (Vector2) still to walk
	var walking := false
	var waiting := false ## a walk is asked for and its path not yet found
	var inside := false ## gone in at home: out of sight, but answers a knock
	var speed := 0.0 ## m/s this frame, for the walk cycle
	# ---- a road walker (town life): back and forth along `path`
	var path := PackedVector2Array()
	var path_i := 0 ## the waypoint they are walking to
	var path_dir := 1
	var linger := 0.0 ## seconds left resting at the end of the road

	func _init(g, d: Dictionary) -> void:
		game = g
		def = d
		id = d.id
		name = d.name
		position = Vector3(d.position[0], 0, d.position[1])
		position.y = Terrain.height_at(position.x, position.z)
		post = position
		rest_facing = deg_to_rad(d.get("facing", 0))
		facing = rest_facing
		group = Node3D.new()
		group.name = "Npc_" + id
		group.add_to_group(World.MOVING_GROUP)
		group.position = position
		# no collider: the player (and enemies) walk straight through townsfolk (Dan, 2026-11-04)
		places.work = {"at": Vector2(post.x, post.z), "via": [], "inside": false, "facing": rest_facing}
		board = d.get("board", false)
		work_timer = 1 + randf()
		for q in d.get("path", []):
			path.append(Vector2(q[0], q[1]))
		if path.size() >= 2:
			_start_on_road()
		# background folk get a body when they first come into view
		if not d.get("ambient"):
			build_body()

	func build_body() -> void:
		if model != null:
			return
		var d := def
		model = Assets.instance(d.model)
		group.add_child(model)
		if d.get("tool"):
			var hand := model.find_child("Arm_R", true, false) as Node3D
			if hand:
				var built_in := model.find_child("Weapon", true, false) as Node3D
				if built_in:
					built_in.visible = false
				var tool := Assets.instance(d.tool)
				tool.name = "WorkTool"
				tool.position = Vector3(0, -0.55, 0.04)
				tool.rotation_degrees.x = -25
				tool.scale = Vector3.ONE * d.get("toolScale", 0.8)
				hand.add_child(tool)
		rig = Rig.new(model, "warden")
		# townsfolk who share a model are told apart by a tint
		if d.get("tint"):
			Rig.tint(Rig.isolate_materials(model), Color(d.tint))

	## somewhere along their road, the same every load: spread out, half of
	## them each way
	func _start_on_road() -> void:
		var hh := absi(hash(id))
		var n := path.size()
		var at: int = hh % n
		path_dir = 1 if (hh / n) % 2 == 0 else -1
		position = Vector3(path[at].x, 0, path[at].y)
		position.y = Terrain.height_at(position.x, position.z)
		path_i = clampi(at + path_dir, 0, n - 1)
		if path_i == at:
			path_dir = -path_dir
			path_i = at + path_dir
		facing = atan2(path[path_i].x - position.x, path[path_i].y - position.z)
		post = position
		group.position = position

	## a road walker's day: along the road, a rest at each end, and no
	## setting out after dark (they wait for morning where they are)
	func walk_road(dt: float, hour: float) -> void:
		var life: Dictionary = DB.CONFIG.life
		speed = 0.0
		if busy():
			return
		if linger > 0.0:
			linger -= dt
			if linger <= 0.0 and (hour >= float(life.nightFrom) or hour < float(life.dawn)):
				linger = 20.0
			return
		var step: float = float(DB.CONFIG.routine.walkSpeed) * dt
		speed = float(DB.CONFIG.routine.walkSpeed)
		while step > 0.0:
			var to: Vector2 = path[path_i]
			var d := Vector2(to.x - position.x, to.y - position.z)
			var l := d.length()
			if l > 0.001:
				facing = atan2(d.x, d.y)
			if l > step:
				position.x += d.x / l * step
				position.z += d.y / l * step
				break
			position.x = to.x
			position.z = to.y
			step -= l
			path_i += path_dir
			if path_i < 0 or path_i >= path.size():
				# the end of the road: rest in town, then turn back
				path_dir = -path_dir
				path_i = clampi(path_i + path_dir * 2, 0, path.size() - 1)
				linger = float(life.endRest) * (0.7 + 0.6 * float(absi(hash(id + str(path_dir))) % 100) / 99.0)
				speed = 0.0
				break
		position.y = Terrain.height_at(position.x, position.z)

	## Is this person here, given the story so far?
	func update_presence() -> void:
		present = not d_gone()

	func d_gone() -> bool:
		return def.get("goneWhen") != null and Quests.condition_holds(game, def.goneWhen)

	## the place their routine has them at `hour`
	func place_at(hour: float) -> String:
		if routine.is_empty():
			return "work"
		var h := fposmod(hour - shift, 24.0)
		var at: String = routine[-1].at # before the first block: still the last one of yesterday
		for b in routine:
			if float(b.from) <= h:
				at = b.at
		return at if places.has(at) else "work"

	## talking with the player: they stop where they are
	func busy() -> bool:
		return is_same(game.dialogue.npc, self) or is_same(game.merchant.npc, self) or is_same(game.bank.npc, self)

	## put them straight where they would be (no walk)
	func snap_to(p: String) -> void:
		place = p
		var pl: Dictionary = places[p]
		route = []
		walking = false
		waiting = false
		_arrive(pl)

	func _arrive(pl: Dictionary) -> void:
		position = Vector3(pl.at.x, Terrain.height_at(pl.at.x, pl.at.y), pl.at.y)
		facing = pl.facing
		inside = pl.inside
		walking = false

	## the way from where they are to place `p`: out of the building they are
	## in, then a path to the next one's door, then in
	func leg_ends(p: String) -> Dictionary:
		var from: Dictionary = places.get(from_place, {"via": []})
		var out := []
		var start := Vector2(position.x, position.z)
		if not from.via.is_empty():
			for i in range(from.via.size() - 1, -1, -1):
				out.append(from.via[i])
			start = from.via[0]
		var to: Dictionary = places[p]
		var goal: Vector2 = to.via[0] if not to.via.is_empty() else to.at
		return {"exit": out, "start": start, "goal": goal, "enter": to.via.slice(1) + [to.at]}

	## the routine, run for everyone whether drawn or not
	func simulate(dt: float, want: String) -> bool:
		if want != place and not waiting:
			from_place = "" if walking else place
			place = want
			waiting = true
			walking = false
			route = []
			inside = false # they come out to go
			return true # a path is wanted
		if walking and not busy():
			var step: float = float(DB.CONFIG.routine.walkSpeed) * dt
			speed = float(DB.CONFIG.routine.walkSpeed)
			while step > 0.0 and not route.is_empty():
				var to: Vector2 = route[0]
				var d := Vector2(to.x - position.x, to.y - position.z)
				var l := d.length()
				if l > 0.001:
					facing = atan2(d.x, d.y)
				if l <= step:
					position.x = to.x
					position.z = to.y
					step -= l
					route.pop_front()
				else:
					position.x += d.x / l * step
					position.z += d.y / l * step
					step = 0.0
			position.y = Terrain.height_at(position.x, position.z)
			if route.is_empty():
				_arrive(places[place])
		else:
			speed = 0.0
		return false

	## standing at their post
	func at_post() -> bool:
		return place == "work" and not walking and not waiting

	func update(dt: float, player) -> void:
		var dx: float = player.position.x - position.x
		var dz: float = player.position.z - position.z
		# only someone you are talking to turns to you, and keeps an eye on
		# you until you walk off
		var near: bool = busy() and U.hyp(dx, dz) < 8 and not player.dead
		var anvil = def.get("anvil", def.get("workAt")) if at_post() else null
		var moving: bool = walking or speed > 0.0
		if rig != null:
			rig.pose = def.get("idlePose") if not near and not moving else null
		var want: float
		if board:
			want = rest_facing
		elif near:
			want = atan2(dx, dz)
		elif moving or path.size() >= 2:
			want = facing
		elif anvil and rest_timer <= 0:
			want = atan2(anvil[0] - position.x, anvil[1] - position.z)
		else:
			want = places[place].facing
		if not moving or near:
			var d := want - facing
			d = atan2(sin(d), cos(d))
			facing += d * minf(1, dt * 5)
		# at work: a hammer blow every so often, unless someone wants a word
		# in bouts: a run of blows, then a breather looking about (Dan,
		# 2026-11-03: the constant hammering wore thin)
		if anvil and not near and rest_timer > 0:
			rest_timer -= dt
			if rest_timer <= 0:
				bout = 4 + randi() % 6
		elif anvil and not near:
			work_timer -= dt
			if work_timer <= 0:
				work_timer = 1.5 + randf() * 0.8
				bout -= 1
				if bout <= 0:
					rest_timer = 8.0 + randf() * 10.0
				if rig != null:
					rig.play(def.get("workAnimation", "strike"), 0.6, 0.45)
				if def.has("anvil"):
					game.events.emit("anvilStrike", {"npc": self, "x": anvil[0], "z": anvil[1]})
		# limbs only move where the camera could see them
		if rig != null and U.hyp(dx, dz) < Enemy.ANIMATE_RANGE:
			rig.update(dt, speed / float(DB.CONFIG.player.speed) * 1.6 if speed > 0 and not near else 0.0)
		group.position = position
		group.rotation.y = facing


var game
var all: Array = []
var _paths := [] ## people waiting for a path, first come first served
var _last_hour := -100.0
var _frame := 0
var services_keep_post: bool = DB.CONFIG.routine.get("servicesKeepPost", true)


func _init(g) -> void:
	game = g
	var inn_use := {}
	for d in Layout.npcs:
		var n := Npc.new(game, d)
		all.append(n)
		_plan(n, inn_use)


## plan everyone's hours again, quest and service folk kept at their post or not
func replan(keep_post: bool) -> void:
	services_keep_post = keep_post
	var inn_use := {}
	for n in all:
		n.routine = []
		n.places = {"work": n.places.work}
		_plan(n, inn_use)
		n.snap_to(n.place_at(game.world_state.hour))


## who keeps what hours, and where their inn and home are
func _plan(n: Npc, inn_use: Dictionary) -> void:
	if n.board:
		return
	if services_keep_post and keeps_post(n.id, n.def):
		return
	var r = n.def.get("routine")
	var blocks = DB.routines.get(r, {}).get("blocks", []) if r is String else r
	if not blocks is Array or blocks.is_empty():
		return
	n.routine = blocks.duplicate(true)
	n.routine.sort_custom(func(a, b): return float(a.from) < float(b.from))
	# a steady few minutes early or late, the same every day and every load
	var spread: float = DB.CONFIG.routine.spread
	n.shift = (float(absi(hash(n.id)) % 1000) / 999.0 * 2.0 - 1.0) * spread
	var p := Vector2(n.post.x, n.post.z)
	var wants := {}
	for b in n.routine:
		wants[b.at] = true
	if wants.has("inn"):
		var inn = _nearest_inn(p)
		if inn != null:
			var seat_i: int = inn_use.get(inn.id, 0)
			inn_use[inn.id] = seat_i + 1
			var c := Vector2(inn.position[0], inn.position[1])
			var seat: Array = INN_SEATS[seat_i % INN_SEATS.size()]
			var at := c + Vector2(seat[0], seat[1]) + Vector2(0.4, 0.3) * float(seat_i / INN_SEATS.size())
			var door := inn_door(inn)
			n.places.inn = {"at": at, "via": [c + door[0], c + door[1]], "inside": false,
				"facing": atan2(c.x - at.x, c.y - at.y) + PI * 0.15}
	if wants.has("home"):
		var door = _home_door(n, p)
		if door != null:
			n.places.home = {"at": door.at, "via": [], "inside": true, "facing": door.facing}
	for k in n.def.get("places", {}):
		var q: Array = n.def.places[k]
		# [x, z] or [x, z, facing in degrees]
		var f: float = deg_to_rad(float(q[2])) if q.size() > 2 else n.rest_facing
		n.places[k] = {"at": Vector2(q[0], q[1]), "via": [], "inside": false, "facing": f}


## The way in to an inn, relative to its middle: [just outside, just
## inside] the gap in its `walls` (the walk-in kit's door is in the west
## wall), or the middle of the south wall when it has no wall list.
static func inn_door(b: Dictionary) -> Array:
	var hw: float = float(b.size[0]) * 0.5
	var hd: float = float(b.size[1]) * 0.5
	var walls = b.get("walls")
	if walls is Array:
		# per side, the stretches of wall along it; a side in two or more
		# pieces has the door in its first gap
		var sides := {"n": [], "s": [], "w": [], "e": []}
		for s in walls:
			if not s is Array or s.size() < 4:
				continue
			if is_equal_approx(float(s[0]), float(s[2])):
				var k := "w" if float(s[0]) < 0 else "e"
				sides[k].append([minf(s[1], s[3]), maxf(s[1], s[3])])
			elif is_equal_approx(float(s[1]), float(s[3])):
				var k := "n" if float(s[1]) < 0 else "s"
				sides[k].append([minf(s[0], s[2]), maxf(s[0], s[2])])
		for k in sides:
			var runs: Array = sides[k]
			if runs.size() < 2:
				continue
			runs.sort_custom(func(a, c): return a[0] < c[0])
			var mid: float = (float(runs[0][1]) + float(runs[1][0])) * 0.5
			match k:
				"w": return [Vector2(-hw - 1.6, mid), Vector2(-hw + 1.4, mid)]
				"e": return [Vector2(hw + 1.6, mid), Vector2(hw - 1.4, mid)]
				"n": return [Vector2(mid, -hd - 1.6), Vector2(mid, -hd + 1.4)]
				_: return [Vector2(mid, hd + 1.6), Vector2(mid, hd - 1.4)]
	return [Vector2(0, hd + 1.6), Vector2(0, hd - 1.4)]


## Does anyone come to this person for something? A quest they give, take in
## or are asked about, or a service (shop, forge, bank, bed, trade).
const SERVICES := ["shop", "forge", "banker", "innkeeper", "bedPrice", "jeweller", "refiner", "reeve"]
static var _quest_folk := {}
static var _quest_folk_of := {}


static func keeps_post(id: String, def: Dictionary) -> bool:
	for k in SERVICES:
		if def.get(k):
			return true
	if not is_same(_quest_folk_of, DB.quests):
		_quest_folk = {}
		for q in DB.quests.values():
			for who in [q.get("giver"), q.get("turnIn")]:
				if who is String:
					_quest_folk[who] = true
			for o in q.get("objectives", []):
				if o.get("type") == "talk" and o.get("target") is String:
					_quest_folk[o.target] = true
		_quest_folk_of = DB.quests
	return _quest_folk.has(id)


func _nearest_inn(p: Vector2):
	var best = null
	var best_d: float = DB.CONFIG.routine.innRange
	for b in Layout.buildings:
		if not b.get("rest"):
			continue
		var d := p.distance_to(Vector2(b.position[0], b.position[1]))
		if d < best_d:
			best_d = d
			best = b
	return best


## the door of their house: the spawn's own `home` [x, z], else the nearest
## house (Layout.houses) within CONFIG.routine.homeRange
func _home_door(n: Npc, p: Vector2):
	var own = n.def.get("home")
	if own is Array and own.size() >= 2:
		return {"at": Vector2(own[0], own[1]), "facing": n.rest_facing}
	var best = null
	var best_d: float = DB.CONFIG.routine.homeRange
	for h in Layout.houses:
		var d := p.distance_to(Vector2(h.position[0], h.position[1]))
		if d < best_d:
			best_d = d
			best = h
	if best == null:
		return null
	return house_door(best)


## the spot outside a house's door (`door`: n, s, e or w; turned with it)
static func house_door(h: Dictionary) -> Dictionary:
	var w: float = h.size[0]
	var d: float = h.size[1]
	var side: String = h.get("door", "s")
	var o := Vector2(0, d / 2 + 0.8)
	match side:
		"n": o = Vector2(0, -d / 2 - 0.8)
		"e": o = Vector2(w / 2 + 0.8, 0)
		"w": o = Vector2(-w / 2 - 0.8, 0)
	var r := deg_to_rad(h.get("rotation", 0))
	var at := Vector2(h.position[0] + o.x * cos(r) + o.y * sin(r), h.position[1] - o.x * sin(r) + o.y * cos(r))
	# facing the door from the doorstep
	return {"at": at, "facing": atan2(h.position[0] - at.x, h.position[1] - at.y)}


## the townsfolk who are here now, out and about (not gone in at home)
var list: Array:
	get:
		return all.filter(func(n): return n.present and not n.inside)


## everyone here today, at home or not (quest markers find them at their door)
var here: Array:
	get:
		return all.filter(func(n): return n.present)


func by_id(id: String):
	for n in all:
		if n.present and n.id == id:
			return n
	return null


func update(dt: float) -> void:
	var hour: float = game.world_state.hour
	var jump := absf(hour - _last_hour)
	var snap := minf(jump, 24.0 - jump) > SNAP_HOURS
	_last_hour = hour
	_frame += 1
	for i in all.size():
		var n: Npc = all[i]
		# presence is a quest check: a few times a second is plenty
		if snap or (_frame + i) % PRESENCE_EVERY == 0:
			n.update_presence()
		if not n.present:
			continue
		# people out of view walk their day at a quarter of the rate
		# (staggered), so a town full of folk costs little off screen
		var step := dt
		if n.group.get_parent() == null and not snap:
			if (_frame + i) % FAR_EVERY != 0:
				continue
			step = dt * FAR_EVERY
		if n.path.size() >= 2:
			n.walk_road(step, hour)
			continue
		if n.routine.is_empty():
			continue
		var want: String = n.place_at(hour)
		if snap:
			n.snap_to(want)
			_paths.erase(n)
		elif n.simulate(step, want):
			_paths.append(n)
	for i in mini(PATHS_PER_FRAME, _paths.size()):
		_route(_paths.pop_front())
	var player = game.player
	for n in all:
		var d2: float = n.position.distance_squared_to(player.position)
		var shown: bool = n.group.get_parent() != null
		var want: bool = n.present and not n.inside and (d2 < WorldStream.VIEW_IN * WorldStream.VIEW_IN
			or (shown and d2 < WorldStream.VIEW_OUT * WorldStream.VIEW_OUT))
		if want != shown:
			if want:
				n.build_body()
				game.scene.add_child(n.group)
			else:
				n.group.get_parent().remove_child(n.group)
		if want:
			n.update(dt, player)


## find the way for a walk that was asked for
func _route(n: Npc) -> void:
	# the hour may have moved on while they waited: go where it says now
	n.place = n.place_at(game.world_state.hour)
	var legs := n.leg_ends(n.place)
	var path: Array = game.collision.find_path(legs.start.x, legs.start.y, legs.goal.x, legs.goal.y, 0.3)
	if path.is_empty():
		path = [legs.goal]
	n.route = legs.exit + path + legs.enter
	n.waiting = false
	n.walking = true
	n.inside = false


## bodies in the scene now (checks and the F3 readout)
func shown_count() -> int:
	var n := 0
	for p in all:
		if p.group.get_parent() != null:
			n += 1
	return n


## what the interaction system offers for each NPC: a word, or a knock at
## the door of someone gone in for the night
func interactions() -> Array:
	var out := []
	for n in here:
		var prompt := ("Knock for %s" if n.inside else "Talk to %s") % n.name
		out.append({"key": "npc:" + n.id, "x": n.position.x, "z": n.position.z, "bias": -0.6, "reach": DB.CONFIG.shop.talkRange, "prompt": prompt, "run": func(): talk(n)})
	return out


func talk(n) -> void:
	# a notice board stays as it was put up; people turn to you
	if not n.board:
		n.facing = atan2(game.player.position.x - n.position.x, game.player.position.z - n.position.z)
	game.dialogue.open(n)
