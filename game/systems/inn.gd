class_name Inn
extends RefCounted
## A bed at an inn. Any npc with `innkeeper: true` rents one (npcs.json
## `bedPrice`, else CONFIG.inn.bedPrice). The screen fades out, you sleep,
## and wake whole: full health and mana, wounds mended, some rested
## experience, and the inn as the place your spirit rises if you fall.
## Sitting under an inn's roof still builds rested experience and mends
## wounds slowly (camp.gd, afterlife.gd); the bed is the quick way.

var game


func _init(g) -> void:
	game = g


static func bed_price(npc_id: String) -> int:
	return int(DB.npcs.get(npc_id, {}).get("bedPrice", DB.CONFIG.inn.bedPrice))


## pay for the bed, then sleep through a fade (or at once, with no HUD)
func sleep(npc_id: String) -> bool:
	var price := bed_price(npc_id)
	if game.inventory.coins < price or game.player.dead:
		return false
	game.inventory.lose_coins(price)
	if game.hud and game.hud.is_inside_tree():
		game.hud.fade_through(func(): wake(npc_id), DB.CONFIG.inn.fade, DB.CONFIG.inn.hold)
	else:
		wake(npc_id)
	return true


## the night's rest itself
func wake(npc_id: String) -> void:
	var cfg: Dictionary = DB.CONFIG.inn
	var name: String = DB.npcs.get(npc_id, {}).get("name", "The innkeeper")
	game.afterlife.heal_wounds("A good rest in a proper bed, and your wounds have closed.")
	game.player.health = game.player.max_health
	game.resources.mana = game.resources.max_mana
	var prog = game.progression
	var cap: float = prog.xp_to_next * DB.CONFIG.camp.restedCap
	prog.rested = minf(cap, prog.rested + prog.xp_to_next * cfg.restedShare)
	game.world_state.rest_point = "inn:" + npc_id
	game.events.emit("innRest", {"npc": npc_id})
	game.events.emit("statsChanged", {})
	game.events.emit("log", {"text": "Yawn. Much better. It feels like no time has passed at all... If you fall, you will wake at %s's inn." % name.split(" ")[0], "kind": "heal"})
	if game.hud:
		game.hud.toast("Rested at the inn")
