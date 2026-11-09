class_name Bank
extends RefCounted
## The bank (Dan, 2026-11-03), as in WoW: a banker opens your vault, a grid
## of slots beside your bags. Drag between them, or right-click to move a
## stack across. What is in it is kept per character (Inventory.bank, saved
## with the bags) and never lost on death. Walking away shuts it.

var game
var npc = null ## the banker while the vault is open


func _init(g) -> void:
	game = g


var is_open: bool:
	get:
		return npc != null


func open(n) -> void:
	game.merchant.close()
	npc = n
	game.audio.sfx("bag", 0.7)
	game.events.emit("bankOpened", {})


func close() -> void:
	if npc == null:
		return
	npc = null
	game.events.emit("bankClosed", {})


## walking away (or dying) shuts the vault
func update() -> void:
	if npc == null:
		return
	var p: Vector3 = game.player.position
	if game.player.dead or U.hyp(p.x - npc.position.x, p.z - npc.position.z) > DB.CONFIG.bank.leaveRange:
		close()
