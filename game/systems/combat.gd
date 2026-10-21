class_name Combat
extends RefCounted
## Combat rules (src/systems/combat.js): who a blow hits, how much it hurts,
## and what follows from a defeat. Entities ask; this system decides.

var game
var arrows: Array = [] ## Auto Shot arrows in flight: { target, t, ammo }
var shown_later: Array = [] ## opener hits whose visuals wait for the windup: { t, fn }


func _init(g) -> void:
	game = g


## average damage of each weapon ability before the target's armour
var basic_damage: int:
	get:
		return game.stats.ability_average(1)


## A weapon hit from the player on `enemy`: roll, crit, armour; applies it.
## o.swing: an auto attack, which rolls the weapon's own per-swing damage;
## abilities roll the normalised range. o.show: delay the hit's visuals
## (flinch, knockback, number) by this many seconds; the damage lands now.
func _player_hit(enemy, mult: float, hurt_opts: Dictionary, o := {}) -> Dictionary:
	var stats = game.stats
	var events: Events = game.events
	var r: Callable = game.random
	var swing: bool = o.get("swing", false)
	var hand: String = o.get("hand", "main")
	var show: float = o.get("show", 0.0)
	var base: float = (Stats.swing_roll(r, stats, hand) if swing else Stats.weapon_roll(r, stats)) + o.get("bonus", 0.0)
	var sp = game.spells
	var m: Dictionary = sp.hit_mods(enemy) if sp else {"mult": 1.0, "critBonus": 0.0, "forceCrit": false}
	var hit := Stats.compute_hit(r, stats.stat_block, Stats.enemy_block(enemy.cfg), {"base": base, "mult": mult * m.mult * (sp.damage_scale if sp else 1.0) * game.afterlife.damage_scale_against(enemy), "critBonus": m.critBonus, "forceCrit": m.forceCrit})
	if sp:
		sp.after_hit(hit)
	var visuals := func():
		events.emit("damageNumber", {"target": enemy, "amount": hit.amount, "crit": hit.crit, "kind": "dealt", "hand": "ranged" if hand == "ranged" else "main"})
		events.emit("hitImpact", {"enemy": enemy, "crit": hit.crit, "heavy": hurt_opts.get("heavy", false) or swing})
	if show > 0:
		enemy.hurt(hit.amount, {"stagger": 0.0, "quiet": true})
		shown_later.append({"t": show, "fn": func():
			if not enemy.dead:
				enemy.hurt(0, hurt_opts)
			visuals.call()})
	else:
		enemy.hurt(hit.amount, hurt_opts)
		visuals.call()
	return hit


func update_shown(dt: float) -> void:
	for s in shown_later:
		s.t -= dt
	var due := shown_later.filter(func(s): return s.t <= 1e-6)
	shown_later = shown_later.filter(func(s): return s.t > 1e-6)
	for s in due:
		s.fn.call()


## A blow from an enemy on the player: variance, crit, armour, block, then
## what a curse (Hex), a guard (Brace) and a shield of light take off it.
func _enemy_hit(enemy, damage: float, o := {}) -> Dictionary:
	var stats = game.stats
	var player = game.player
	var r: Callable = game.random
	var mult: float = enemy.damage_dealt_scale * (1 - player.damage_reduction / 100.0)
	var hit := Stats.compute_hit(r, Stats.enemy_block(enemy.cfg), stats.stat_block, {"base": Stats.enemy_roll(r, damage), "mult": mult, "canCrit": o.get("canCrit", true), "canBlock": o.get("canBlock", true), "school": o.get("school", "physical")})
	var left: int = game.spells.absorb(hit.amount) if game.spells else hit.amount
	if left < hit.amount:
		hit.absorbed = hit.amount - left
	hit.amount = left
	if hit.amount > 0:
		player.take_damage(hit.amount)
	game.events.emit("damageNumber", {"target": player, "amount": hit.amount, "crit": hit.crit, "blocked": hit.blocked, "kind": "taken", "usual": enemy.cfg.damage})
	return hit


func _crit_text(hit: Dictionary) -> String:
	return " A critical blow!" if hit.crit else ""


## The hard-locked target, if it is alive and within reach.
func _selected_in_reach(range_: float):
	var t = game.targeting.current if game.targeting else null
	if t == null or not t.alive:
		return null
	var p: Vector3 = game.player.position
	return t if U.hyp(t.position.x - p.x, t.position.z - p.z) <= range_ + t.radius * 0.6 else null


## Ground-telegraphed attacks hit whoever stands inside the marked area.
func resolve_telegraph(enemy, shape, damage: float, label, opts = null) -> bool:
	var player = game.player
	var events: Events = game.events
	if enemy.dead or player.dead:
		return false
	if not shape.contains(player.position.x, player.position.z, player.radius):
		events.emit("enemyWhiff", {"enemy": enemy})
		if label:
			events.emit("log", {"text": "You are clear of the %s." % label, "kind": "muted"})
		return false
	var guard: String = player.consume_brace()
	if guard != "":
		events.emit("braceBlock", {"enemy": enemy, "heavy": true})
		var what: String = label if label else enemy.cfg.name + "'s blow"
		var text := "The %s misses you." % what if guard == "miss" else "You parry the %s." % what if guard == "parry" else "You brace and turn aside the %s." % what
		events.emit("log", {"text": text, "kind": "hit"})
		return false
	# the slam cannot crit or be blocked; an ordinary cleave can be both.
	# Shots and spells say for themselves (`opts`).
	var special: bool = label != null
	var hit := _enemy_hit(enemy, damage, opts if opts != null else {"canCrit": not special, "canBlock": not special})
	events.emit("playerHurt", {"enemy": enemy, "damage": hit.amount, "crit": hit.crit, "blocked": hit.blocked, "heavy": opts == null or not opts.get("canBlock", true)})
	var who: String = "The %s's %s" % [enemy.cfg.name, label] if opts != null and label else "The " + label if label else "The %s" % enemy.cfg.name
	events.emit("log", {"text": _hurt_text(who, hit), "kind": "hurt"})
	if player.dead:
		game.on_player_death(enemy)
	return true


## Pick a sensible nearby target: living, within reach, roughly in front.
func select_strike_target(aim):
	var player = game.player
	var dir_x := sin(player.facing)
	var dir_z := cos(player.facing)
	if aim != null:
		var ax: float = aim.x - player.position.x
		var az: float = aim.z - player.position.z
		var len := U.hyp(ax, az)
		if len > 0.3:
			dir_x = ax / len
			dir_z = az / len
	var cos_limit := cos(deg_to_rad(DB.attack.coneDegrees / 2.0))
	var best = null
	var best_score := INF
	for e in game.enemies.list:
		if not e.alive:
			continue
		var dx: float = e.position.x - player.position.x
		var dz: float = e.position.z - player.position.z
		var dist := U.hyp(dx, dz)
		var reach: float = DB.attack.range + e.radius * 0.6
		if dist > reach:
			continue
		var facing_dot := (dx * dir_x + dz * dir_z) / dist if dist > 0.01 else 1.0
		# very close enemies are hit regardless of angle; others must be in the arc
		if dist > 1.0 and facing_dot < cos_limit:
			continue
		var score := dist - facing_dot
		if score < best_score:
			best_score = score
			best = e
	return best


## `hand`: 'off' for a dual-wielded off-hand swing, which does less damage
func resolve_player_strike(aim, hand := "main", show := 0.0):
	var player = game.player
	var events: Events = game.events
	if player.dead:
		return null
	var target = _selected_in_reach(DB.attack.range)
	if target == null:
		target = select_strike_target(aim)
	if target == null:
		events.emit("playerMiss", {})
		return null
	var off := hand == "off"
	var hit := _player_hit(target, DB.CONFIG.stats.offHandDamage if off else 1.0, {"stagger": 0.12 if off else 0.22, "knockFrom": player.position, "knockback": 0.15 if off else 0.3}, {"swing": true, "hand": hand, "show": show})
	events.emit("enemyHit", {"enemy": target, "damage": hit.amount, "crit": hit.crit, "kind": "strike", "swing": true, "hand": hand})
	events.emit("log", {"text": "%s the %s for %d.%s" % ["Your off hand strikes" if off else "You strike", target.cfg.name, hit.amount, _crit_text(hit)], "kind": "hit"})
	if target.dead:
		on_enemy_defeated(target)
	elif game.spells:
		game.spells.echo(target, hit) # Empowered Light
	return target


## Auto Shot: an arrow from the bow to the target. It flies (following the
## target) and does its damage when it arrives.
func loose_player_arrow(target, ammo = null) -> void:
	var player = game.player
	var from := Vector3(player.position.x + sin(player.facing) * 0.4, player.position.y + 1.35, player.position.z + cos(player.facing) * 0.4)
	var d := U.hyp(target.position.x - from.x, target.position.z - from.z)
	var t: float = d / DB.auto_shot.arrowSpeed
	arrows.append({"target": target, "t": t, "ammo": ammo})
	game.events.emit("projectile", {"kind": "arrow", "from": from, "to": target.position, "follow": target, "speed": DB.auto_shot.arrowSpeed, "life": t})
	game.events.emit("playerShot", {})


func update_arrows(dt: float) -> void:
	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		a.t -= dt
		if a.t > 1e-6:
			continue
		arrows.remove_at(i)
		var e = a.target
		if not e.alive or game.player.dead:
			continue
		# the arrow adds its own damage: ammoDps for each second of bow speed
		var bonus: float = (Items.get_def(a.ammo).get("ammoDps", 0) if a.ammo else 0.0) * game.stats.hand_speed("ranged")
		var hit := _player_hit(e, 1, {"stagger": 0.12, "knockFrom": game.player.position, "knockback": 0.1}, {"swing": true, "hand": "ranged", "bonus": bonus})
		game.events.emit("enemyHit", {"enemy": e, "damage": hit.amount, "crit": hit.crit, "kind": "strike", "swing": true, "hand": "ranged"})
		game.events.emit("log", {"text": "Your arrow hits the %s for %d.%s" % [e.cfg.name, hit.amount, _crit_text(hit)], "kind": "hit"})
		if e.dead:
			on_enemy_defeated(e)


func resolve_enemy_strike(enemy) -> bool:
	var player = game.player
	var events: Events = game.events
	if enemy.dead or player.dead:
		return false
	var d := U.hyp(enemy.position.x - player.position.x, enemy.position.z - player.position.z)
	var reach: float = enemy.cfg.meleeRange + player.radius + enemy.radius * 0.5 + 0.35 # small grace for the swing
	if d > reach:
		events.emit("enemyWhiff", {"enemy": enemy})
		return false
	var guard: String = player.consume_brace()
	if guard != "":
		events.emit("braceBlock", {"enemy": enemy})
		var who: String = enemy.cfg.name
		var text := "The %s's blow misses you." % who if guard == "miss" else "You parry the %s's blow." % who if guard == "parry" else "Your shield takes the %s's blow." % who
		events.emit("log", {"text": text, "kind": "hit"})
		return false
	var hit := _enemy_hit(enemy, enemy.cfg.damage)
	events.emit("playerHurt", {"enemy": enemy, "damage": hit.amount, "crit": hit.crit, "blocked": hit.blocked})
	events.emit("log", {"text": _hurt_text("The %s" % enemy.cfg.name, hit), "kind": "hurt"})
	if player.dead:
		game.on_player_death(enemy)
	return true


func _hurt_text(who: String, hit: Dictionary) -> String:
	if hit.blocked and hit.amount == 0:
		var w := "the" + who.substr(3) if who.begins_with("The") else who
		return "You block %s's blow." % w
	var s := "%s %s you for %d" % [who, "critically hits" if hit.crit else "hits", hit.amount]
	if hit.blocked:
		s += " (%d blocked)" % hit.blocked
	if hit.get("absorbed"):
		s += " (%d absorbed)" % hit.absorbed
	return s + "."


## Rewards are granted exactly once: the world state is the record.
func on_enemy_defeated(enemy) -> void:
	var ws = game.world_state
	var loot = game.loot
	if ws.is_defeated(enemy.id):
		return
	ws.mark_defeated(enemy.id)
	# most enemies come back after their type's respawn time
	if enemy.cfg.get("respawn", 0) > 0:
		ws.respawn_at[enemy.id] = ws.time + enemy.cfg.respawn
	game.events.emit("enemyDefeated", {"enemy": enemy})
	game.events.emit("log", {"text": "The %s falls still." % enemy.cfg.name, "kind": "kill"})
	game.progression.add_xp(enemy.cfg.xp, true)
	if enemy.cfg.get("reputation"):
		game.reputation.add_all(enemy.cfg.reputation)
	# coins stay on the body until looted; a beast's body also waits for a skinner
	if enemy.cfg.get("coins", 0) > 0 or loot.keep_for_skinning(enemy):
		loot.add_corpse(enemy, enemy.cfg.get("coins", 0))
	if enemy.cfg.get("uniqueDrop"):
		loot.drop_unique(enemy)
	loot.drop_from_enemy(enemy)
	game.afterlife.on_enemy_defeated(enemy)
