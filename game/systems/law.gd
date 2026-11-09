class_name Law
extends RefCounted
## Crime, Bounty and Infamy, after Fable (data/npcs/infamy.json).
##
## A crime only counts if someone sees it. A seen crime puts a Bounty on you
## with that place's reeve (local, and it clears: pay it, or serve your
## time) and may add Infamy (lasting: it fades only through atonement). You
## show Amber for a minute while the nearest watchman comes over to have a
## word: a warning for a first small offence, else a fine, the lock-up, or a
## fight if you resist. Resisting, or a big enough bounty, makes you Wanted
## there (red): the watch attacks on sight, and if you fall you wake in the
## lock-up with the fine taken from your purse. Enough Infamy makes you an
## Outlaw everywhere (purple): no merchant will serve you, and Thatch Corrow,
## the reeve's hound, comes for you on the roads, a little stronger every
## time you beat him.
##
## No accidental crimes: livestock and the watch (`lawful` enemies) can only
## be attacked while the crime key (Alt) is held.
##
## PK points, after Conquer Online (infamy.json `pk`): killing an innocent
## player adds points; 30 makes a red name, 100 a black one, and a red or
## black name may drop worn gear on death. Striking an innocent makes you
## flash (blue) for a while: anyone may hit you then without PK points. The
## rules are worked out from a player's points alone (pk_name_of,
## pk_fair_game), so any client can colour another player's name; the
## multiplayer server calls pk_struck / pk_killed when one player hits or
## kills another.

var game
var bounty := {} ## jurisdiction id -> coins owed
var wanted := {} ## jurisdiction id -> true: Wanted there (resisted, or fought the watch)
var warned := {} ## jurisdiction id -> true: the one warning is spent
var infamy := 0.0
var crimes := {} ## crime id -> times seen
var amber := 0.0 ## seconds left of Amber (seen in the act)
var summoned = null ## the watchman (Enemy) on his way over
var hunter = null ## the hunter (Enemy) while he is out
var scars := 0 ## times the hunter has been beaten
var hunter_at := -1.0 ## world time the hunter next comes (-1: not yet set)
var talk = null ## Talk while a watchman has his say
var pk := 0.0 ## PK points (player kills)
var flash := 0.0 ## seconds left flashing (struck an innocent player)
var pk_clock := 0.0 ## seconds alive towards the next PK point fading
var rng := RandomNumberGenerator.new() ## gear drop rolls (tests seed it)


## A watchman in the conversation window (the dialogue system talks to it
## like a townsperson; it stands wherever the watchman stands).
class Talk:
	extends RefCounted
	var id := "watch"
	var enemy
	var name: String
	var board := false
	var position: Vector3:
		get:
			return enemy.position
	func _init(e) -> void:
		enemy = e
		name = e.cfg.name


func _init(g) -> void:
	game = g
	if not DB.npcs.has("watch"):
		DB.npcs["watch"] = {"id": "watch", "name": "Watchman", "title": "The Watch", "level": 15, "model": "warden"}
	var ev: Events = game.events
	ev.on("enemyHit", func(e): _struck(e.enemy))
	ev.on("enemyMissed", func(e): _struck(e.enemy))
	ev.on("enemyDefeated", func(e): _killed(e.enemy))
	ev.on("playerDied", func(_e): _player_fell())


static func file() -> Dictionary:
	return DB.infamy


func reset() -> void:
	bounty = {}
	wanted = {}
	warned = {}
	infamy = 0.0
	crimes = {}
	amber = 0.0
	summoned = null
	hunter = null
	scars = 0
	hunter_at = -1.0
	talk = null
	pk = 0.0
	flash = 0.0
	pk_clock = 0.0


static func crime_def(id: String) -> Dictionary:
	for c in file().get("crimes", []):
		if c.id == id:
			return c
	return {}


## The jurisdiction (a reeve's area) at a place, or {} where there is no law.
static func jurisdiction_at(x: float, z: float) -> Dictionary:
	var r := DB.region_at(x, z)
	for j in file().get("jurisdictions", []):
		if j.regions.has(r.get("id", "")):
			return j
	return {}


func here() -> Dictionary:
	return jurisdiction_at(game.player.position.x, game.player.position.z)


# ------------------------------------------------------------ standing
var outlaw: bool:
	get:
		return infamy >= file().get("outlawAt", 40)


func wanted_in(jid: String) -> bool:
	return jid != "" and (wanted.has(jid) or bounty.get(jid, 0) >= file().get("wantedAt", 60))


## "clean" | "amber" | "wanted" | "outlaw" (where you stand now)
var status: String:
	get:
		if outlaw:
			return "outlaw"
		if wanted_in(here().get("id", "")):
			return "wanted"
		if amber > 0:
			return "amber"
		return "clean"


func nameplate_colour() -> Color:
	var p: Dictionary = pk_cfg().get("nameplates", {})
	if flash > 0 and p.has("flashing"):
		return Color(p.flashing)
	if pk_name != "white" and p.has(pk_name):
		return Color(p[pk_name])
	return Color(file().get("nameplates", {}).get(status, "#f0e6c8"))


## the buff row's entry while the law is after you
var aura:
	get:
		var j := here()
		match status:
			"outlaw":
				return {"id": "outlaw", "icon": "shadow", "name": "Outlaw", "left": INF, "text": "Infamy %s. No merchant will serve you, the watch attacks on sight, and Thatch Corrow is on your trail." % U.n(floorf(infamy))}
			"wanted":
				return {"id": "wanted", "icon": "rebuke", "name": "Wanted in %s" % j.name, "left": INF, "text": "Bounty %s. The watch attacks on sight. Pay the reeve, or fall and wake in %s." % [U.money(bounty.get(j.id, 0)), j.get("gaolName", "the lock-up")]}
			"amber":
				return {"id": "seen", "icon": "rebuke", "name": "Seen", "left": amber, "text": "Someone saw what you did. The watch is coming for a word."}
		if flash > 0:
			return {"id": "flashing", "icon": "rebuke", "name": "Flashing", "left": flash, "text": "You struck an innocent. Anyone may attack you now without blame."}
		match pk_name:
			"black":
				return {"id": "black_name", "icon": "shadow", "name": "Black name", "left": INF, "text": "PK points %s. The watch attacks on sight, and you may drop your gear when you fall." % U.n(floorf(pk))}
			"red":
				return {"id": "red_name", "icon": "shadow", "name": "Red name", "left": INF, "text": "PK points %s. You may drop your gear when you fall. Points fade with time." % U.n(floorf(pk))}
		return null


## Merchants charge more of the infamous (percent).
var markup: float:
	get:
		var out := 0.0
		for m in file().get("markup", []):
			if infamy >= m.infamy:
				out = m.percent
		return out


func add_infamy(n: float, why := "") -> void:
	if not n:
		return
	var was := outlaw
	infamy = maxf(0, infamy + n)
	game.events.emit("log", {"text": "Your infamy %s by %s%s." % ["grows" if n > 0 else "fades", U.n(absf(n)), " " + why if why != "" else ""], "kind": "hurt" if n > 0 else "rep"})
	if outlaw and not was:
		game.events.emit("log", {"text": "You are an Outlaw. No law will have you now.", "kind": "hurt"})
		if game.hud:
			game.hud.toast("Outlaw", "bad")
	_changed()


# ------------------------------------------------------------ the watch
static func is_guard(e) -> bool:
	return e != null and e.cfg.get("lawful") == "guard"


func guard_jurisdiction(e) -> Dictionary:
	return jurisdiction_at(e.home.x, e.home.z)


## Will this watchman fight you on sight?
func hostile(e) -> bool:
	return is_guard(e) and (outlaw or pk_name == "black" or wanted_in(guard_jurisdiction(e).get("id", "")))


## A lawful enemy you did not mean to attack cannot be harmed.
func protected(e) -> bool:
	return e.cfg.get("lawful", "") != "" and not e.sanctioned and not hostile(e) and not (e.state == "chase" or e.state == "attack")


## May you attack this enemy now? Livestock and a peaceful watch only with
## the crime key held; holding it means you meant it.
func may_attack(e) -> bool:
	if e == null or not protected(e):
		return true
	if game.keys.held("crime"):
		e.sanctioned = true
		return true
	if game.hud:
		game.hud.error("Hold %s to attack the %s. It would be a crime." % [game.keys.label("crime"), e.cfg.name])
	return false


# ------------------------------------------------------------ crimes
## Who sees something happen at `at`: townsfolk and the watch, close by and
## with no wall between.
func witnesses(at: Vector3, victim = null) -> Array:
	var r: float = file().get("witnessRange", 16)
	var col = game.collision
	var out := []
	for n in game.npcs.list:
		if n.board:
			continue
		if U.hyp(n.position.x - at.x, n.position.z - at.z) <= r and not col.wall_between(n.position.x, n.position.z, at.x, at.z):
			out.append(n)
	for e in game.enemies.list:
		if not is_guard(e) or not e.alive:
			continue
		if U.hyp(e.position.x - at.x, e.position.z - at.z) <= r and not col.wall_between(e.position.x, e.position.z, at.x, at.z):
			out.append(e)
	return out


## A crime at `at`. Returns true if it was seen (and so counts).
func commit(id: String, at: Vector3, victim = null) -> bool:
	var c := crime_def(id)
	var j := jurisdiction_at(at.x, at.z)
	if c.is_empty() or j.is_empty():
		return false
	var seen := witnesses(at, victim)
	if seen.is_empty():
		game.events.emit("log", {"text": "No one saw that.", "kind": "muted", "throttle": "unseen"})
		return false
	var who = seen[0]
	var who_name: String = who.cfg.name if "cfg" in who else who.name
	crimes[id] = int(crimes.get(id, 0)) + 1
	bounty[j.id] = int(bounty.get(j.id, 0)) + int(c.get("bounty", 0))
	if c.get("wanted"):
		wanted[j.id] = true
	amber = file().get("amberSeconds", 60)
	game.events.emit("log", {"text": "%s saw you %s. You owe %s to the reeve of %s." % [who_name, c.name, U.money(bounty[j.id]), j.name], "kind": "hurt"})
	if game.hud:
		game.hud.toast("Crime seen: %s" % c.name, "bad")
	if c.get("infamy"):
		add_infamy(c.infamy, "for " + c.name)
	game.events.emit("crimeSeen", {"crime": id, "jurisdiction": j.id})
	if not wanted_in(j.id):
		_summon(j)
	_changed()
	return true


## Send the nearest peaceful watchman of the jurisdiction over.
func _summon(j: Dictionary) -> void:
	if summoned != null and summoned.alive:
		return
	var p: Vector3 = game.player.position
	var best = null
	for e in game.enemies.list:
		if not is_guard(e) or not e.alive or e.state != "idle" or guard_jurisdiction(e).get("id") != j.id:
			continue
		if best == null or e.position.distance_to(p) < best.position.distance_to(p):
			best = e
	summoned = best


func _struck(e) -> void:
	if e == null or e.cfg.get("lawful", "") == "":
		return
	# striking a peaceful watchman is assault (once a fight)
	if is_guard(e) and not e.sanctioned_crime:
		e.sanctioned_crime = true
		if not hostile(e):
			commit("assault", e.position, e)


func _killed(e) -> void:
	if e == null:
		return
	if e.cfg.get("lawful") == "livestock":
		commit("livestock", e.position, e)
	elif is_guard(e):
		commit("murder", e.position, e)
	if is_same(e, hunter):
		_hunter_beaten()


# ------------------------------------------------------------ the watchman's word
## A summoned watchman reaches you: he has his say in the dialogue window.
func confront(e) -> void:
	if not is_same(summoned, e):
		return
	summoned = null
	if hostile(e) or game.player.dead:
		return
	var j := guard_jurisdiction(e)
	if int(bounty.get(j.id, 0)) <= 0:
		return
	talk = Talk.new(e)
	game.dialogue.open(talk)


func _line(kind: String) -> String:
	var lines: Array = file().get("guardLines", {}).get(kind, [""])
	return lines[randi() % lines.size()]


## The dialogue window's page while a watchman talks: { name, title, text, options }
func page() -> Dictionary:
	var e = talk.enemy if talk != null else null
	var pg := {"name": e.cfg.name if e else "Watchman", "title": "The Watch", "text": "", "options": []}
	if e == null:
		return pg
	var j := guard_jurisdiction(e)
	var owed := int(bounty.get(j.id, 0))
	if not warned.has(j.id) and owed < file().get("warnBelow", 30):
		pg.text = _line("warn")
		pg.options.append({"id": "sorry", "text": "It won't happen again.", "icon": "accept"})
		return pg
	pg.text = _line("fine").replace("{bounty}", U.money(owed))
	pg.options.append({"id": "pay", "text": "Pay the fine (%s)" % U.money(owed), "icon": "accept", "disabled": game.inventory.coins < owed})
	pg.options.append({"id": "gaol", "text": "Come quietly (a night in %s)" % j.get("gaolName", "the lock-up"), "icon": "talk"})
	pg.options.append({"id": "resist", "text": "Resist", "icon": "bye"})
	return pg


func choose(id: String) -> bool:
	var e = talk.enemy if talk != null else null
	if e == null:
		return false
	var j := guard_jurisdiction(e)
	match id:
		"sorry":
			warned[j.id] = true
			bounty.erase(j.id)
			amber = 0.0
			game.events.emit("log", {"text": "The watchman lets it go, this once.", "kind": "muted"})
		"pay":
			if not pay(j):
				return false
		"gaol":
			jail(j)
		"resist":
			commit("resisting", e.position, e)
			wanted[j.id] = true
			e.state = "chase"
			game.events.emit("log", {"text": "You resist. The watch will not ask again.", "kind": "hurt"})
		_:
			return false
	talk = null
	game.dialogue.close()
	_changed()
	return true


## Pay what you owe in a jurisdiction; the watch stands down.
func pay(j: Dictionary) -> bool:
	var owed := int(bounty.get(j.id, 0))
	if game.inventory.coins < owed:
		if game.hud:
			game.hud.error("You cannot pay %s" % U.money(owed))
		return false
	game.inventory.lose_coins(owed)
	_clear(j)
	game.events.emit("log", {"text": "You pay %s to the reeve of %s. The watch stands down." % [U.money(owed), j.name], "kind": "rep"})
	return true


func _clear(j: Dictionary) -> void:
	bounty.erase(j.id)
	wanted.erase(j.id)
	amber = 0.0
	summoned = null
	# the watch stops chasing you
	for e in game.enemies.list:
		if is_guard(e) and e.alive and guard_jurisdiction(e).get("id") == j.id and not outlaw:
			e.sanctioned = false
			e.sanctioned_crime = false
			if e.state == "chase" or e.state == "attack":
				e.state = "return"
	_changed()


## A night in the lock-up: the fine comes out of your purse (what there is
## of it) and the slate is clean.
func jail(j: Dictionary) -> void:
	var owed := int(bounty.get(j.id, 0))
	var paid: int = game.inventory.lose_coins(owed)
	_clear(j)
	var g: Array = j.get("gaol", [0, 0])
	var player = game.player
	player.place_at(g[0], g[1], player.facing)
	player.health = player.max_health
	game.targeting.clear()
	game.events.emit("log", {"text": "You spend the night in %s.%s The slate is clean, in %s at least." % [j.get("gaolName", "the lock-up"), " %s of your fine comes out of your purse." % U.money(paid) if paid else "", j.name], "kind": "lore"})
	if game.hud:
		game.hud.toast("A night in the lock-up")


## Falling while Wanted where you stand: you wake in the lock-up, not as a
## spirit. Returns true if it took you there (afterlife.gd asks first).
func jail_on_death() -> bool:
	var j := here()
	if j.is_empty() or not wanted_in(j.id):
		return false
	game.telegraphs.clear()
	game.hud.clear_numbers()
	game.enemies.reset_survivors()
	var g: Array = j.get("gaol", [0, 0])
	game.player.revive(g[0], g[1])
	jail(j)
	return true


## Atonement at the reeve: coins to the widows' fund, Infamy fades.
func atone_price(points: float) -> int:
	return U.jround(points * file().get("atone", {}).get("coinsPerPoint", 4))


func atone(points: float) -> bool:
	points = minf(points, infamy)
	var price := atone_price(points)
	if points <= 0:
		return false
	if game.inventory.coins < price:
		if game.hud:
			game.hud.error("You cannot afford that")
		return false
	game.inventory.lose_coins(price)
	add_infamy(-points, "as you make amends")
	return true


# ------------------------------------------------------------ PK points
static func pk_cfg() -> Dictionary:
	return file().get("pk", {})


## "white" | "red" | "black" for a player's PK points.
static func pk_name_of(points: float) -> String:
	var c := pk_cfg()
	if points >= float(c.get("black", 100)):
		return "black"
	if points >= float(c.get("red", 30)):
		return "red"
	return "white"


## Does a player with these PK points wear the skull over their head?
## (red name or worse, Dan 2026-11-09)
static func pk_skull(points: float) -> bool:
	return pk_name_of(points) != "white"


var pk_name: String:
	get:
		return pk_name_of(pk)


## May a player with these PK points, flashing or not, be struck without
## blame? (red and black names, and anyone flashing)
static func pk_fair_game(points: float, flashing: bool) -> bool:
	return flashing or pk_name_of(points) != "white"


static func _victim_fair(victim: Dictionary) -> bool:
	return pk_fair_game(float(victim.get("pk", 0)), float(victim.get("flash", 0)) > 0)


## You struck another player, `victim` {"pk": points, "flash": seconds}.
## Striking an innocent makes you flash.
func pk_struck(victim: Dictionary) -> void:
	if _victim_fair(victim):
		return
	if flash <= 0:
		game.events.emit("log", {"text": "You struck an innocent. You are flashing: anyone may attack you.", "kind": "hurt"})
	flash = float(pk_cfg().get("flashSeconds", 60))
	_changed()


## You killed another player. An innocent's death adds PK points (and
## Infamy). Returns the points added.
func pk_killed(victim: Dictionary) -> int:
	if _victim_fair(victim):
		return 0
	var c := pk_cfg()
	var n := int(c.get("perKill", 10))
	var was := pk_name
	pk += n
	game.events.emit("log", {"text": "You killed an innocent. PK points +%d (%s)." % [n, U.n(floorf(pk))], "kind": "hurt"})
	add_infamy(float(c.get("infamy", 0)), "for the killing")
	if pk_name != was:
		game.events.emit("log", {"text": "Your name burns %s. %s" % [pk_name, "The watch will cut you down on sight." if pk_name == "black" else "Fall now and you may drop your gear."], "kind": "hurt"})
		if game.hud:
			game.hud.toast("%s name" % pk_name.capitalize(), "bad")
	_changed()
	return n


## Worn pieces a red or black name drops on death, onto the ground where
## they fell (the world's ground, so anyone may take them). Returns the
## stacks dropped.
func pk_drop_gear() -> Array:
	var chance: float = pk_cfg().get("drops", {}).get(pk_name, 0.0)
	if chance <= 0:
		return []
	var most := int(pk_cfg().get("drops", {}).get("max", 2))
	var inv = game.inventory
	var out := []
	for slot in inv.equipment.keys():
		if out.size() >= most:
			break
		var s = inv.equipment[slot]
		if s == null:
			continue
		var d := Items.get_def(s.id)
		if d.get("quest") or d.get("toolPack") or d.get("cosmetic"):
			continue
		if rng.randf() >= chance:
			continue
		var taken = inv.take("e:" + slot)
		if taken == null:
			continue
		var p: Vector3 = game.player.position
		var a := rng.randf() * TAU
		game.loot.drop_at(taken, Vector3(p.x + sin(a) * 1.1, 0, p.z + cos(a) * 1.1))
		out.append(taken)
	if not out.is_empty():
		var names: Array = out.map(func(t): return Items.view(t).name)
		game.events.emit("log", {"text": "Your %s name costs you: %s, left where you fell." % [pk_name, ", ".join(names)], "kind": "hurt"})
	return out


# ------------------------------------------------------------ the hunter
func _player_fell() -> void:
	pk_drop_gear()
	# the hunter takes his win and goes; he will be back
	if hunter != null and hunter.alive:
		hunter.group.queue_free()
		game.enemies.list.erase(hunter)
		hunter = null
		_next_hunt()
	summoned = null


func _next_hunt() -> void:
	var every: Array = file().get("hunter", {}).get("every", [300, 600])
	hunter_at = game.world_state.time + float(every[0]) + randf() * (float(every[1]) - float(every[0]))


func _spawn_hunter() -> void:
	var h: Dictionary = file().get("hunter", {})
	var p: Vector3 = game.player.position
	var b: Dictionary = Layout.bounds
	var d: float = h.get("spawnDistance", 24)
	var a := randf() * TAU
	var x := clampf(p.x + sin(a) * d, b.minX + 2, b.maxX - 2)
	var z := clampf(p.z + cos(a) * d, b.minZ + 2, b.maxZ - 2)
	var at: Vector3 = game.collision.resolve(Vector3(x, 0, z), 0.5)
	var base: Dictionary = DB.enemies[h.enemy]
	var e := Enemy.new(game, {"id": "hunter_%d" % scars, "type": h.enemy, "position": [at.x, at.z], "level": int(base.level) + scars * int(h.get("scarLevels", 1))})
	var names: Array = h.get("names", [])
	if not names.is_empty():
		e.cfg = e.cfg.duplicate()
		e.cfg.name = names[mini(scars, names.size() - 1)]
	e.state = "chase"
	game.enemies.list.append(e)
	game.scene.add_child(e.group)
	hunter = e
	game.events.emit("log", {"text": "%s has found your trail." % e.cfg.name, "kind": "hurt"})
	if game.hud:
		game.hud.toast("You are hunted", "bad")


func _hunter_beaten() -> void:
	game.events.emit("log", {"text": "%s crawls off into the hedge, bleeding. He will be back, and he will remember." % hunter.cfg.name, "kind": "level"})
	scars += 1
	hunter = null
	_next_hunt()


# ------------------------------------------------------------ each frame
func update(dt: float) -> void:
	if flash > 0:
		flash = maxf(0, flash - dt)
		if flash == 0:
			_changed()
	if pk > 0 and not game.player.dead:
		var d: Dictionary = pk_cfg().get("decay", {})
		var every := float(d.get("seconds", 360))
		pk_clock += dt
		if every > 0 and pk_clock >= every:
			pk_clock -= every
			var was := pk_name
			pk = maxf(0, pk - float(d.get("points", 1)))
			if pk_name != was:
				game.events.emit("log", {"text": "Your name cools to %s." % pk_name, "kind": "rep"})
			_changed()
	if amber > 0:
		amber = maxf(0, amber - dt)
		if amber == 0:
			# out of sight long enough: the watchman goes back to his post
			summoned = null
			_changed()
	if summoned != null and (not summoned.alive or hostile(summoned)):
		summoned = null
	if outlaw and not game.player.dead and (hunter == null or not hunter.alive):
		if hunter_at < 0:
			_next_hunt()
		elif game.world_state.time >= hunter_at:
			_spawn_hunter()


func _changed() -> void:
	game.events.emit("lawChanged", {})


# ------------------------------------------------------------ saving
func serialize() -> Dictionary:
	return {"bounty": bounty.duplicate(), "wanted": wanted.keys(), "warned": warned.keys(), "infamy": snappedf(infamy, 0.01), "crimes": crimes.duplicate(), "scars": scars, "pk": snappedf(pk, 0.01), "pkClock": snappedf(pk_clock, 0.1), "flash": snappedf(flash, 0.1)}


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var known: Array = file().get("jurisdictions", []).map(func(j): return j.id)
	var b = data.get("bounty", {})
	if typeof(b) == TYPE_DICTIONARY:
		for k in b:
			if known.has(k) and (typeof(b[k]) == TYPE_INT or typeof(b[k]) == TYPE_FLOAT) and b[k] > 0:
				bounty[k] = int(b[k])
	for k in data.get("wanted", []):
		if known.has(k):
			wanted[k] = true
	for k in data.get("warned", []):
		if known.has(k):
			warned[k] = true
	var inf = data.get("infamy", 0)
	infamy = maxf(0, float(inf)) if typeof(inf) == TYPE_INT or typeof(inf) == TYPE_FLOAT else 0.0
	var c = data.get("crimes", {})
	if typeof(c) == TYPE_DICTIONARY:
		for k in c:
			if not crime_def(k).is_empty():
				crimes[k] = int(c[k])
	scars = int(data.get("scars", 0))
	pk = _num(data.get("pk", 0))
	pk_clock = _num(data.get("pkClock", 0))
	flash = _num(data.get("flash", 0))


static func _num(v) -> float:
	return maxf(0, float(v)) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0.0
