class_name RuneForge
extends RefCounted
## The rune forge (Dan, 2026-11-03): runes are fused to weapons at a forge
## in the world, not dragged on from the bags. Click the forge and a window
## opens with two slots: drop the weapon in the first, the rune beside it,
## press Fuse. A few seconds' channel (standing still), then a flash of magic
## and the rune is in the weapon (Runes.apply does the fusing).
##
## The slots hold references to stacks still in your bags or worn (never
## moved out), so nothing can be lost if the window closes or the game is
## saved mid-way. A stack moved elsewhere in the bags is followed by identity.

const CHANNEL := 3.0 ## seconds the fusing takes
const KIND := "runeforge" ## the station kind (spawns.json / world.json `stations`)

var game
var station = null ## the station dict the window is open at
var weapon = null ## the weapon stack in the first slot
var rune = null ## the rune scroll stack in the second
var channel = null ## {t, total, rid, weapon_loc} while fusing


func _init(g) -> void:
	game = g


## Open the forge's window at station `st`.
func open_at(st: Dictionary) -> void:
	if station != st:
		weapon = null
		rune = null
	station = st
	game.hud.show_window(KIND)
	# the bags open with it, so there is something to drag from
	game.hud.show_window("bags")


func close() -> void:
	stop("")
	station = null
	weapon = null
	rune = null


## Where a slotted stack is now ("" if it is gone from your bags and gear).
func loc_of(stack) -> String:
	if stack == null:
		return ""
	var inv = game.inventory
	for slot in inv.equipment:
		if is_same(inv.equipment[slot], stack):
			return "e:" + slot
	for loc in inv.bag_locations():
		if is_same(inv.get_at(loc), stack):
			return loc
	return ""


## The real inventory loc behind a forge slot ("f:weapon" / "f:rune").
func slot_loc(slot: String) -> String:
	return loc_of(weapon if slot == "f:weapon" else rune if slot == "f:rune" else null)


## The stack in a forge slot, if it is still yours.
func in_slot(slot: String):
	var loc := slot_loc(slot)
	return game.inventory.get_at(loc) if loc != "" else null


static func is_weapon(stack) -> bool:
	return stack != null and Items.get_def(stack.id).get("kind") == "weapon"


static func is_rune(stack) -> bool:
	return stack != null and not Runes.def(String(Items.get_def(stack.id).get("rune", ""))).is_empty()


## Put the stack at `from` into the forge: into `slot` when given (a drop on
## that slot), else whichever slot it fits (a right click from the bags).
func put(from: String, slot := "") -> bool:
	if channel != null:
		return false
	var st = game.inventory.get_at(from)
	if st == null:
		return false
	if slot == "":
		slot = "f:weapon" if is_weapon(st) else "f:rune" if is_rune(st) else ""
	if slot == "f:weapon" and is_weapon(st):
		weapon = st
	elif slot == "f:rune" and is_rune(st):
		rune = st
	else:
		game.inventory._refuse("The weapon goes in the first slot, the rune beside it." if slot != "" else "Only weapons and runes go in the rune forge.")
		return false
	game.audio.sfx("bag", 0.5)
	game.events.emit("runeForgeChanged", {})
	return true


func clear(slot: String) -> void:
	if channel != null:
		return
	if slot == "f:weapon":
		weapon = null
	elif slot == "f:rune":
		rune = null
	game.events.emit("runeForgeChanged", {})


## Why the Fuse button can't be pressed now, or "".
func blocked() -> String:
	var w = in_slot("f:weapon")
	var r = in_slot("f:rune")
	if w == null:
		return "Place a weapon in the forge."
	if r == null:
		return "Place a rune beside it."
	var rid: String = Items.get_def(r.id).rune
	if Runes.of(w) == rid:
		return "That weapon already bears the %s rune." % Runes.def(rid).name
	if channel != null:
		return "The forge is already at work."
	if not near():
		return "You are too far from the rune forge."
	return ""


func near() -> bool:
	if station == null:
		return false
	var p = game.player.position
	return U.hyp(p.x - station.position[0], p.z - station.position[1]) <= float(station.get("radius", 3.0)) + 1.5


## Press Fuse: asks first when the weapon already bears another rune.
func fuse() -> bool:
	var why := blocked()
	if why != "":
		game.hud.error(why)
		return false
	var w = in_slot("f:weapon")
	var rid: String = Items.get_def(in_slot("f:rune").id).rune
	var had := Runes.of(w)
	if had != "" and game.hud and game.hud.has_method("confirm"):
		game.hud.confirm("Replace the %s rune on your %s with %s?" % [Runes.def(had).name, Items.view(w).name, Runes.def(rid).name], func(): _begin(rid))
		return true
	_begin(rid)
	return true


func _begin(rid: String) -> void:
	if blocked() != "":
		return
	game.cooking.stop_eating()
	channel = {"t": 0.0, "total": CHANNEL, "rid": rid}
	game.player.rig.play("brace", CHANNEL, 0.9)
	game.audio.sfx("panel", 0.5)
	game.events.emit("runeForgeChanged", {"started": true})
	if game.world and game.world.has_method("rune_forge_glow"):
		game.world.rune_forge_glow(station.id, Color(Runes.def(rid).glow.colour), 1.0)


func stop(why := "") -> void:
	if channel == null:
		return
	channel = null
	game.player.rig.action = null
	if station != null and game.world and game.world.has_method("rune_forge_glow"):
		game.world.rune_forge_glow(station.id, Color(), 0.0)
	if why != "":
		game.events.emit("log", {"text": why, "kind": "muted", "throttle": "runeforge-stop"})
	game.events.emit("runeForgeChanged", {})


## The cast bar's view of the channel, or null.
func bar():
	if channel == null:
		return null
	return {"t": channel.t, "total": channel.total, "name": "Fusing the %s rune" % Runes.def(channel.rid).name}


func update(dt: float) -> void:
	if station == null:
		return
	var player = game.player
	# walking away (or closing the window) puts the forge down
	var shown: bool = game.hud.items.open.get(KIND, false)
	if not near() or player.dead or not shown:
		if channel != null:
			stop("The rune forge falls quiet.")
		if shown and not near():
			game.hud.items.close(KIND)
		close()
		return
	if channel == null:
		return
	if player.moving:
		stop("Interrupted.")
		return
	# a weapon or rune taken away mid-fuse stops it
	if in_slot("f:weapon") == null or in_slot("f:rune") == null:
		stop("Interrupted.")
		return
	channel.t += dt
	if channel.t >= channel.total:
		_finish()


func _finish() -> void:
	var rid: String = channel.rid
	channel = null
	player_rig_rest()
	var ok: bool = game.runes.apply(slot_loc("f:rune"), rid, slot_loc("f:weapon"))
	if ok:
		var c := Color(Runes.def(rid).glow.colour)
		var at := Vector3(station.position[0], game.player.position.y + 1.0, station.position[1])
		# the flash of magic: at the forge as well as on you
		game.events.emit("spellFlash", {"position": at, "colour": Runes.def(rid).glow.colour})
		game.events.emit("runeForged", {"station": station.id, "rune": rid})
		if game.world and game.world.has_method("rune_forge_glow"):
			game.world.rune_forge_glow(station.id, c, 3.0)
	# the rune is spent; the weapon stays in place to admire
	if in_slot("f:rune") == null:
		rune = null
	game.events.emit("runeForgeChanged", {"done": ok})


func player_rig_rest() -> void:
	game.player.rig.action = null
