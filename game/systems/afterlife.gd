class_name Afterlife
extends RefCounted
## Death, WoW style (src/systems/afterlife.js). When the player falls, their
## body stays where it fell and their spirit rises at the last place they
## rested: their camp, an inn, or the last shrine. From there the ghost can
## either run back to the body and rise there, or return to life at once
## where it stands. What they carried waits in a grave by the body (grave.gd).
## Either way they come back Wounded: less health until they rest at an inn
## or pay a healer (Dan, 2026-10-27).
##
## The enemy that killed the player is remembered (`world_state.nemesis`): it
## carries a skull until it falls. It gives no extra damage or XP (Dan,
## 2026-10-27: dying must never pay), so `revengeBonus` and `revengeXp` are 0.

var game
var ghost := false
var corpse = null ## { x, z, mesh }
var coin_loss := 0
var wounds := 0 ## each revival adds one, up to death.maxWounds
var wound_rest := 0.0 ## seconds rested at an inn towards healing them


func _init(g) -> void:
	game = g


# ------------------------------------------------------------- rest point
## Where the spirit rises: the camp or shrine rested at last, else the road's start.
func rest_point() -> Dictionary:
	var ws = game.world_state
	if ws.rest_point == "camp" and ws.camp != null:
		return {"x": ws.camp.x + 1.4, "z": ws.camp.z, "label": "by your camp", "kind": "camp"}
	# an inn you made your home: you wake by its hearth
	if typeof(ws.rest_point) == TYPE_STRING and ws.rest_point.begins_with("inn:"):
		var inn := inn_point()
		if not inn.is_empty():
			return {"x": inn.x, "z": inn.z, "label": "at %s" % inn.label, "kind": "inn"}
	var sh = Layout.shrines[0]
	for x in Layout.shrines:
		if x.id == ws.shrine_activated:
			sh = x
	if ws.respawn != null:
		return {"x": ws.respawn.x, "z": ws.respawn.z, "label": sh.label, "kind": "shrine"}
	return {"x": Layout.player_start.position[0], "z": Layout.player_start.position[1], "label": "at the road's end", "kind": "start"}


## by the inn's hearth, as { x, z, label }, or {} if there is no inn
func inn_point() -> Dictionary:
	for b in Layout.buildings:
		if b.get("rest"):
			return {"x": b.position[0] + b.light[0] + 1.2, "z": b.position[1] + b.light[1] + 1.4, "label": b.name}
	return {}


# --------------------------------------------------------------- dying
func on_death(killer, loss: int) -> void:
	var ws = game.world_state
	coin_loss = loss
	game.grave.on_death(game.player.position)
	# dying wears your gear, as in WoW
	game.inventory.wear(DB.CONFIG.durability.deathLoss)
	game.events.emit("log", {"text": "Your equipment is damaged (−%s%% durability)." % U.n(DB.CONFIG.durability.deathLoss), "kind": "muted"})
	if killer != null and killer.alive and killer.id:
		ws.nemesis = killer.id
		game.events.emit("log", {"text": "The %s will remember this. So will you." % killer.cfg.name, "kind": "hurt"})


## Leave the body: the spirit rises at the rest point.
func release() -> bool:
	var player = game.player
	if not player.dead or ghost:
		return false
	# fallen while Wanted here: you wake in the lock-up instead (law.gd)
	if game.law != null and game.law.jail_on_death():
		return true
	var at: Vector3 = player.position
	_place_corpse(at.x, at.z, player.facing)
	var dest := rest_point()
	game.telegraphs.clear()
	game.hud.clear_numbers()
	game.targeting.clear()
	game.enemies.reset_engaged()
	ghost = true
	player.become_ghost(dest.x, dest.z)
	game.set_ghost_look(true)
	game.events.emit("ghost", {"on": true})
	game.events.emit("log", {"text": "Your spirit rises %s. Return to your body to live again, or rest here to return at once%s." % [dest.label, ", %s lighter" % U.money(coin_loss) if coin_loss else ""], "kind": "lore"})
	return true


## Rise at the body: half health, nothing lost.
func revive_at_corpse() -> bool:
	if not ghost or corpse == null or not near_corpse:
		return false
	var c: Dictionary = corpse
	_end()
	_wound()
	game.player.revive(c.x, c.z, DB.CONFIG.death.corpseHealth)
	game.events.emit("log", {"text": "You return to your body, wounded. Rest at an inn or find a healer.", "kind": "heal"})
	return true


## Return to life where the spirit stands (at the rest point), wounded.
func revive_here() -> bool:
	if not ghost:
		return false
	var at: Vector3 = game.player.position
	_end()
	_wound()
	game.player.revive(at.x, at.z)
	game.events.emit("log", {"text": "You return to life %s, wounded. Rest at an inn or find a healer." % rest_point().label, "kind": "lore"})
	return true


# --------------------------------------------------------------- wounds
func _wound() -> void:
	wounds = mini(int(DB.CONFIG.death.maxWounds), wounds + 1)
	wound_rest = 0.0
	game.recompute_max_health()


## the share of maximum health your wounds take away
var wound_factor: float:
	get:
		return maxf(0.1, 1 - wounds * DB.CONFIG.death.woundHealth / 100.0)


func heal_wounds(how: String) -> void:
	if wounds <= 0:
		return
	wounds = 0
	wound_rest = 0.0
	game.recompute_max_health()
	game.events.emit("log", {"text": how, "kind": "heal"})
	game.hud.toast("Your wounds are healed")


## resting under an inn's roof mends you (camp.gd calls this while you rest)
func rest_tick(dt: float, where: String) -> void:
	if wounds <= 0 or where != "inn":
		wound_rest = 0.0
		return
	wound_rest += dt
	if wound_rest >= DB.CONFIG.death.woundRestSeconds:
		heal_wounds("A night's rest under a roof, and your wounds have closed.")


var wound_aura:
	get:
		if wounds <= 0:
			return null
		return {"id": "wounded", "name": "Wounded" + (" ×%d" % wounds if wounds > 1 else ""), "text": "%d%% less maximum health. Rest at an inn or pay a healer to mend it." % roundi(100 - wound_factor * 100)}


var near_corpse: bool:
	get:
		var p: Vector3 = game.player.position
		return corpse != null and U.hyp(p.x - corpse.x, p.z - corpse.z) <= DB.CONFIG.death.corpseReach

var near_rest_point: bool:
	get:
		var r := rest_point()
		var p: Vector3 = game.player.position
		return U.hyp(p.x - r.x, p.z - r.z) <= DB.CONFIG.death.restReach


## what the interaction system offers a ghost
func interactions() -> Array:
	if not ghost:
		return []
	var out := []
	if corpse != null:
		out.append({"key": "corpse", "x": corpse.x, "z": corpse.z, "bias": -1.0, "reach": DB.CONFIG.death.corpseReach, "prompt": "Return to your body", "big": true, "run": func(): revive_at_corpse()})
	var r := rest_point()
	out.append({"key": "revive-here", "x": r.x, "z": r.z, "bias": 0.0, "reach": DB.CONFIG.death.restReach, "prompt": "Return to life here", "run": func(): revive_here()})
	return out


func _end() -> void:
	ghost = false
	if corpse != null:
		corpse.mesh.queue_free()
	corpse = null
	game.set_ghost_look(false)
	game.events.emit("ghost", {"on": false})


## a new game or a load: no ghost, no body
func reset() -> void:
	if ghost or corpse != null:
		_end()
	coin_loss = 0
	wounds = 0
	wound_rest = 0.0


func _place_corpse(x: float, z: float, facing: float) -> void:
	var mesh := Assets.instance("warden")
	mesh.rotation_order = EULER_ORDER_YXZ
	mesh.rotation = Vector3(-(PI / 2) * 0.95, facing, 0)
	mesh.position = Vector3(x, Terrain.height_at(x, z) + 0.15, z)
	mesh.name = "Corpse"
	game.scene.add_child(mesh)
	_make_glow(mesh)
	corpse = {"x": x, "z": z, "mesh": mesh}


## The body glows and a pale beacon rises over it, so a spirit can find it
## from far off through the grey of death.
func _make_glow(mesh: Node3D) -> void:
	var colour := Color("bfe4ff")
	var overlay := Tex.fx_material(null, Color(colour, 0.3))
	var stack: Array = [mesh]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			n.material_overlay = overlay
		stack.append_array(n.get_children())
	# the beacon stands upright whatever way the body lies
	var holder := Node3D.new()
	holder.top_level = true
	mesh.add_child(holder)
	holder.global_position = mesh.global_position
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.7
	cm.height = 24
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = Tex.fx_material(null, Color(colour, 0.22))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 12
	holder.add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 2.5
	light.omni_range = 7
	light.position.y = 1.2
	holder.add_child(light)
	var tw := holder.create_tween().set_loops()
	tw.tween_property(beam.material_override, "albedo_color:a", 0.08, 0.9).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(overlay, "albedo_color:a", 0.12, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(beam.material_override, "albedo_color:a", 0.22, 0.9).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(overlay, "albedo_color:a", 0.3, 0.9).set_trans(Tween.TRANS_SINE)


# ------------------------------------------------------------- revenge
func is_nemesis(enemy) -> bool:
	return enemy != null and enemy.id == game.world_state.nemesis


## extra damage dealt to the enemy that killed you
func damage_scale_against(enemy) -> float:
	return 1 + DB.CONFIG.death.revengeBonus / 100.0 if is_nemesis(enemy) else 1.0


## called when an enemy falls: revenge pays
func on_enemy_defeated(enemy) -> void:
	if not is_nemesis(enemy):
		return
	game.world_state.nemesis = null
	var bonus := U.jround(enemy.cfg.xp * DB.CONFIG.death.revengeXp)
	game.events.emit("log", {"text": "Revenge. The %s that killed you lies still." % enemy.cfg.name, "kind": "level"})
	game.hud.toast("Revenge!")
	if bonus:
		game.progression.add_xp(bonus)
