class_name Refinery
extends RefCounted
## The refining window (Dan, 2026-11-03), in the manner of WoW's item upgrade
## panel: drop a piece of gear into the slot, see what the next rank gives
## (item level, damage and stats before and after), what it costs and its
## chance, and press Refine. A short channel, then a flash: gold when the
## refine takes, a grey-violet puff when it fails. Forge.temper does the work.
##
## Opened at a refining altar (station kind `refining`) or from a Refiner's
## "Refine gear". Like the rune forge, the slot holds a reference to a stack
## still in your bags or worn, never moves it.

const CHANNEL := 2.5 ## seconds a refine takes
const KIND := "refining" ## the station kind, and the window's id
const NPC_REACH := 4.5 ## how far from a Refiner the window stays open

var game
var at = null ## {id, position, radius} where the window is open (a station, or a Refiner)
var item = null ## the stack in the slot
var channel = null ## {t, total, rank}
var last := "" ## "ok" / "slip" after a try, for the window's line


func _init(g) -> void:
	game = g


## Open at station `st` (or a Refiner, as {id, position, radius}).
func open_at(st: Dictionary) -> void:
	if at == null or at.get("id") != st.get("id"):
		item = null
	at = st
	last = ""
	game.hud.show_window(KIND)
	game.hud.show_window("bags")


## Open at a Refiner npc (the dialogue's "Refine gear").
func open_at_npc(n) -> void:
	open_at({"id": "npc:" + String(n.id), "position": [n.position.x, n.position.z], "radius": NPC_REACH, "npc": true})


func close() -> void:
	stop("")
	at = null
	item = null
	last = ""


## Where the slotted stack is now ("" if it is gone).
func loc() -> String:
	if item == null:
		return ""
	var inv = game.inventory
	for slot in inv.equipment:
		if is_same(inv.equipment[slot], item):
			return "e:" + slot
	for l in inv.bag_locations():
		if is_same(inv.get_at(l), item):
			return l
	return ""


func stack():
	var l := loc()
	return game.inventory.get_at(l) if l != "" else null


## Can this stack go in the slot? "" if so, else why not.
func refuse_reason(st) -> String:
	if st == null:
		return ""
	var d := Items.get_def(st.id)
	if not Items.ROLLED_KINDS.has(d.get("kind")) or d.get("quest", false):
		return "Only gear can be refined."
	if game.forge.temper_cap(st) == 0:
		return "Plain gear has no magic to refine."
	if game.forge.temper_cost(st).is_empty():
		return "That holds all the refining it can."
	return ""


func put(from: String) -> bool:
	if channel != null:
		return false
	var st = game.inventory.get_at(from)
	if st == null:
		return false
	var why := refuse_reason(st)
	if why != "":
		game.inventory._refuse(why)
		return false
	item = st
	last = ""
	game.audio.sfx("bag", 0.5)
	game.events.emit("refineryChanged", {})
	return true


func clear() -> void:
	if channel != null:
		return
	item = null
	last = ""
	game.events.emit("refineryChanged", {})


## The next rank's cost for the slotted item ({} if none).
func cost() -> Dictionary:
	var st = stack()
	return game.forge.temper_cost(st) if st != null else {}


## The slotted item as it would be one rank higher (a view), or {}.
func preview() -> Dictionary:
	var st = stack()
	var c := cost()
	if st == null or c.is_empty():
		return {}
	var copy: Dictionary = st.duplicate(true)
	var r = copy.get("rolls")
	r = r if typeof(r) == TYPE_DICTIONARY else {}
	r.temper = c.rank
	copy.rolls = r
	return Items.view(copy)


func blocked() -> String:
	var st = stack()
	if st == null:
		return "Place a piece of gear in the slot."
	var why := refuse_reason(st)
	if why != "":
		return why
	if not game.forge.affordable(cost()):
		return "You don't have what this needs."
	if channel != null:
		return "Already refining."
	if not near():
		return "You are too far away."
	return ""


func near() -> bool:
	if at == null:
		return false
	var p = game.player.position
	return U.hyp(p.x - at.position[0], p.z - at.position[1]) <= float(at.get("radius", 3.0)) + 1.5


func refine() -> bool:
	var why := blocked()
	if why != "":
		game.hud.error(why)
		return false
	game.cooking.stop_eating()
	channel = {"t": 0.0, "total": CHANNEL, "rank": cost().rank}
	last = ""
	game.player.rig.play("brace", CHANNEL, 0.9)
	game.audio.sfx("panel", 0.5)
	_glow(Color("ffd890"), 1.0)
	game.events.emit("refineryChanged", {"started": true})
	return true


func stop(why := "") -> void:
	if channel == null:
		return
	channel = null
	game.player.rig.action = null
	_glow(Color(), 0.0)
	if why != "":
		game.events.emit("log", {"text": why, "kind": "muted", "throttle": "refine-stop"})
	game.events.emit("refineryChanged", {})


func bar():
	if channel == null:
		return null
	var st = stack()
	return {"t": channel.t, "total": channel.total, "name": "Refining %s to +%d" % [Items.view(st).name if st != null else "", channel.rank]}


func update(dt: float) -> void:
	if at == null:
		return
	var player = game.player
	var shown: bool = game.hud.items.open.get(KIND, false)
	if not near() or player.dead or not shown:
		if channel != null:
			stop("The refine is interrupted.")
		if shown and not near():
			game.hud.items.close(KIND)
		close()
		return
	if channel == null:
		return
	if player.moving:
		stop("Interrupted.")
		return
	if stack() == null:
		stop("Interrupted.")
		return
	channel.t += dt
	if channel.t >= channel.total:
		_finish()


func _finish() -> void:
	channel = null
	game.player.rig.action = null
	var ok: bool = game.forge.temper(loc())
	last = "ok" if ok else "slip"
	var c := Color("ffe6a0") if ok else Color("7a6a90")
	_glow(c, 3.0 if ok else 1.5)
	game.events.emit("refined", {"ok": ok, "position": [at.position[0], at.position[1]], "npc": at.get("npc", false)})
	game.events.emit("refineryChanged", {"done": ok})


## Tint the altar (if this is one): 1 while working, above 1 a flare, 0 rest.
func _glow(c: Color, strength: float) -> void:
	if at != null and not at.get("npc", false) and game.world and game.world.has_method("rune_forge_glow"):
		game.world.rune_forge_glow(at.id, c, strength)
