class_name Spells
extends RefCounted
## The spell engine (src/systems/spells.js). Abilities in data/abilities/abilities.json
## with a `kind` are run here from their data alone, so a new spell is a new
## record, not new code. The kinds and the keys a record may carry are
## documented at the top of src/systems/spells.js; this is a line-by-line
## port of it.

const AURA_EFFECTS := ["slow", "damageTaken", "damageDealt", "stun", "sleep"]

var game
var buffs := {} ## id -> { name, icon, left, total, damageBonus, stacks, critBonus, absorb }
var dots: Array = [] ## { enemy, id, left, next, ammo }
var auras: Array = [] ## your auras on enemies
var zones: Array = [] ## { id, x, z, left, next, radius, slow, damage }
var ally_hots: Array = [] ## heals over time on someone else: { id, on, left, next }
var traps: Array = [] ## { id, key, x, z, arm, left }
var bolts: Array = [] ## { enemy, id, t, ammo, spell }
var blows: Array = [] ## cleaves and bursts on their way to the impact frame
var ranged_windups: Array = []
var queued = null ## a spell pressed in the queue window: { id, left }
var shadow_grace := 0.0 ## seconds that still count as striking from Shadow


## What an ability needs, worded for its tooltip, or "".
static func requirement_text(ability) -> String:
	if ability == null:
		return ""
	if ability.get("ranged"):
		return "Requires a bow in your ranged slot, and arrows"
	var need = ability.get("requires")
	if not need:
		return ""
	if need == "dualWield":
		return "Requires a one-handed weapon in each hand"
	if need == "shield":
		return "Requires a shield in your off hand"
	if need == "weapon":
		return "Requires a melee weapon in your main hand"
	return "Requires %s %s in your main hand" % [U.article(need), need]


## What the ability needs and is missing, or "".
static func missing_gear(g, ability) -> String:
	if ability == null:
		return ""
	if ability.get("ranged"):
		if not g.stats.has_ranged:
			return requirement_text(ability).replace(", and arrows", "")
		return "" if g.inventory.ammo else "Out of Ammo"
	var need = ability.get("requires")
	if not need:
		return ""
	var inv = g.inventory
	if need == "dualWield":
		return "" if g.stats.dual_wielding else requirement_text(ability)
	if need == "shield":
		var s = inv.equipment.offHand
		if s != null and Items.get_def(s.id).get("kind") == "shield" and not Items.view(s).get("broken", false):
			return ""
		return requirement_text(ability)
	var stack = inv.equipment.mainHand
	var def := Items.get_def(stack.id) if stack != null else {}
	if def.is_empty() or def.kind != "weapon" or Items.view(stack).get("broken", false):
		return requirement_text(ability)
	if need != "weapon" and def.get("weaponType") != need:
		return requirement_text(ability)
	return ""


## A bow ability, or a spell at an enemy from beyond melee reach (not a charge).
static func is_ranged_attack(spell) -> bool:
	return spell != null and spell.get("target") == "enemy" and spell.kind != "charge" and (spell.get("ranged", false) or spell.get("range", 0) > DB.attack.range + 1)


## What you hold, for Weapon Master: 'shield', 'dualWield' or 'twoHand'.
static func loadout_of(g) -> String:
	var off = g.inventory.equipment.offHand
	if off != null and Items.get_def(off.id).get("kind") == "shield":
		return "shield"
	return "dualWield" if g.stats.dual_wielding else "twoHand"


func _init(g) -> void:
	game = g
	reset()
	# pushback (WoW Classic): a blow taken while casting sets the cast bar
	# back by `castPushback` seconds, at most `maxPushbacks` times a cast.
	# A channel is not pushed back.
	game.events.on("playerHurt", func(e):
		if e.damage > 0:
			break_shadow()
		# thorns: whoever lands a blow on you takes damage back
		if e.get("enemy") != null and (e.damage > 0 or e.get("blocked")):
			_thorns(e.enemy)
		var c = game.player.casting if game.player else null
		if c == null or c.channel or not (e.damage > 0) or c.pushbacks >= DB.max_pushbacks:
			return
		c.t = maxf(0, c.t - DB.cast_pushback)
		c.pushbacks += 1
		game.events.emit("castPushback", {"id": c.id}))
	# any blow you deal brings you out of Shadow
	game.events.on("enemyHit", func(e):
		if not e.get("periodic") and not e.get("echo"):
			break_shadow()
		if buffs.has("berserk") and e.get("damage",0) > 0 and not e.get("periodic") and not e.get("echo"):
			var b: Dictionary = buffs.berserk
			b.left = minf(b.total - b.age, b.left + DB.spells.berserk.tuning.extension))
	game.events.on("autoAttack", func(e):
		if e.on:
			break_shadow())


func reset() -> void:
	buffs = {}
	ally_hots = []
	dots = []
	auras = []
	zones = []
	traps = []
	bolts = []
	blows = []
	ranged_windups = []
	queued = null
	shadow_grace = 0.0
	reprisal = 0.0
	reprisal_cap = 14.0
	mobile.clear()
	echoes.clear()
	if game.get("runes"):
		game.runes.reset()


var trait_: Dictionary:
	get:
		return game.stats.archetype.get("trait", {})


# ---------------------------------------------------------- state for the HUD
## all damage you deal is scaled by active buffs (and Overcorrupted)
var damage_scale: float:
	get:
		var s := 1.0
		for b in buffs.values():
			s *= 1 + b.get("damageBonus", 0) / 100.0
		var bonus: float = game.resources.damage_bonus if game.resources else 0.0
		return s * (1 + bonus / 100.0)

var hidden: bool:
	get:
		return buffs.has("shadow")


## [{ id, icon, name, left, total }] for the buff row under the health bar
func buff_list() -> Array:
	var list := []
	for id in buffs:
		var b: Dictionary = buffs[id]
		list.append({"id": id, "icon": b.get("icon"), "name": "%s (%d)" % [b.name, b.stacks] if b.get("stacks") else b.name, "left": b.left, "total": b.total})
	var o = game.resources.overload if game.resources else null
	if o:
		list.append({"id": "overload", "icon": "purge", "name": o.name, "left": INF, "total": INF})
	return list


## [{ id, left, total }] of your effects on one enemy, for the target frame
func dots_on(enemy) -> Array:
	var out := []
	for d in dots:
		if d.enemy == enemy:
			out.append({"id": d.id, "left": d.left, "total": tuned(d.id).tuning.duration, "status": DB.spells[d.id].get("status", "")})
	for a in auras:
		if a.enemy == enemy:
			out.append({"id": a.id.split(":")[0], "name": a.name, "left": a.left, "total": a.total, "status": a.get("status", "slowed" if a.get("slow", 0) > 0 else "")})
	return out


func has_aura(enemy, id: String) -> bool:
	for a in auras:
		if a.enemy == enemy and a.id == id:
			return true
	for d in dots:
		if d.enemy == enemy and d.id == id:
			return true
	return false


## the nearest living enemy within 8 metres of a dead one that does not
## already carry this effect (Contagion, Wildfire, Virulent)
func _spread_target(from, id: String):
	var best = null
	var bd := 8.0
	for e in game.enemies.list:
		if not e.alive or e.protected or e == from or has_aura(e, id):
			continue
		var d := U.hyp(e.position.x - from.position.x, e.position.z - from.position.z)
		if d <= bd:
			best = e
			bd = d
	return best


## the spell as it is now: Weapon Master's loadout changes, and the Shadow
## version of an ability (Strike becomes Ambush)
func tuned(id):
	if id == "shadow" and not hidden and (game.resources.in_combat or game.targeting.attacking):
		id = "vanish"
	var spell = DB.spells.get(id)
	if spell == null:
		return null
	if spell.get("inShadow") and hidden and DB.spells.has(spell.inShadow):
		spell = DB.spells[spell.inShadow]
	var lo = spell.get("loadouts", {}).get(loadout_of(game))
	if lo:
		spell = spell.duplicate()
		spell.tuning = U.merged(spell.tuning, lo.get("tuning", {}))
		spell.gain = lo.get("gain", spell.get("gain"))
	# path upgrades, forks and legendary powers (builds.gd)
	if game.builds:
		for c in game.builds.changes_for(spell.id):
			spell = Builds.apply_change(spell, c)
	if id in ["flurry", "crosscut"] and buffs.has("twinOpening"):
		spell = spell.duplicate(true)
		spell.cost.resolve *= 1.0 - buffs.twinOpening.discount / 100.0
	return spell


# ------------------------------------------------------------ status tags
## Does `enemy` carry a status (data/abilities/builds.json `statuses`)? Damage over
## time and auras name theirs (`status`); the rest are read off what an
## effect does: a slow is Slowed, a stun or sleep Stunned, more damage taken
## Vulnerable, less dealt Weakened, a full stagger bar Staggered.
func has_status(enemy, status: String) -> bool:
	if enemy == null or not enemy.alive:
		return false
	match status:
		"staggered":
			return enemy.staggered > 0
		"slowed":
			if enemy.mods.get("slow", 0.0) > 0:
				return true
	for d in dots:
		if d.enemy == enemy and DB.spells[d.id].get("status") == status:
			return true
	if game.runes and game.runes.has_status(enemy, status):
		return true
	for a in auras:
		if a.enemy != enemy:
			continue
		if a.get("status", "") == status:
			return true
		match status:
			"slowed":
				if a.slow > 0:
					return true
			"stunned":
				if a.stun or a.sleep:
					return true
			"vulnerable":
				if a.damageTaken > 0:
					return true
			"weakened":
				if a.damageDealt < 0:
					return true
	return false


## % less damage you take from Fortified (Rallying Cry, Bulwark)
var fortify: float:
	get:
		var n := 0.0
		for b in buffs.values():
			n += b.get("reduction", 0)
		return minf(60, n)


## what a spell going off does for your key passive: Zeal stacks
## The spell's own cast pose (data/abilities/spell_fx.json `anim`), else the kind's
## `type`. `keep_timing`: a blow that lands on its own clock (a sweep, a
## burst, a charge) takes only the pose, so blow and pose stay together.
## `key` "windupAnim" takes the look's `windupAnim` pose (the held part of a cast)
## when it has one.
func _anim(spell: Dictionary, type: String, duration: float, impact: float, keep_timing := false, key := "anim") -> void:
	var look: Dictionary = DB.spell_fx.get(spell.id, {})
	var a = look.get(key, look.get("anim"))
	if a == null:
		game.player.rig.play(type, duration, impact)
		_trail(spell)
		return
	if not keep_timing:
		var d = a.get("duration", duration)
		duration = spell.tuning.get(d, duration) if typeof(d) == TYPE_STRING else d
		impact = a.get("impact", impact)
	game.player.rig.play(a.type, duration, impact)
	_trail(spell)


## a weapon ability's blade leaves a trail (Fx.weapon_trail)
func _trail(spell: Dictionary) -> void:
	if spell.get("school", "physical") == "physical" and not spell.get("ranged") and game.player.rig.action != null:
		game.player.rig.action.trail = true


## The spell's own effects (data/abilities/spell_fx.json): `windup` on you while a
## cast is drawn out, `cast` on you as it goes, `impact` where it lands.
func _show(spell: Dictionary, phase: String, at: Vector3, facing: float, follow = null) -> void:
	if DB.spell_fx.has(spell.id):
		game.events.emit("spellFx", {"id": spell.id, "phase": phase, "position": at, "facing": facing, "follow": follow, "tuning": spell.tuning})


## facing from you to an enemy
func _facing_to(enemy) -> float:
	var p: Vector3 = game.player.position
	return atan2(enemy.position.x - p.x, enemy.position.z - p.z)


func _cast_effects(spell: Dictionary) -> void:
	# a class quest counts the ability going off (`use` objectives): on the
	# enemy you target, or the person you heal
	if game.quests:
		var on = game.targeting.current if game.targeting else null
		var ally = heal_target(spell)
		game.quests.count_use(spell.id, ally.id if ally != null else on.type if on != null and is_instance_valid(on) else "")
	if not game.builds:
		return
	for e in game.builds.effects("critBuild"):
		if spell.get("school") != e.school:
			continue
		var b = buffs.get("critBuild")
		var n := mini(int(e.max), (int(b.get("stacks", 0)) if b else 0) + 1)
		buffs["critBuild"] = {"name": e.name, "icon": spell.id, "left": e.duration, "total": e.duration, "stacks": n, "critBonus": e.percent}


# --------------------------------------------------------------- casting
## Try to use a spell; false (with a word in the log, where WoW would say
## one) if it cannot go off now.
func try_cast(id: String) -> bool:
	var cast := _try_cast(id)
	if not cast and queued == null and game.player.casting == null and DB.spells.has(id) and not game.player.dead:
		game.events.emit("classCastFailed", {"id": id})
	return cast


func _try_cast(id: String) -> bool:
	var player = game.player
	var events: Events = game.events
	var stats = game.stats
	# Nothing about auto attack blocks an ability: only another cast, a
	# charge in flight, or the global cooldown does.
	if not DB.spells.has(id) or player.dead:
		return false
	# pressed in the last moments of a cast or a charge, it waits in the
	# spell queue and goes the instant that ends (Dan, 2026-11-02)
	if not mobile.is_empty() and mobile.spell.id == id:
		mobile.clear()
		return true
	var busy = player.casting if player.casting != null else player.lunge
	if busy != null:
		var left: float = (busy.get("total", busy.get("duration", 0.0)) - busy.t) if not busy.get("channel", false) else INF
		# the same spell again queues too (Blight Bolt, Blight Bolt...); it
		# waits out the rest of the cast and any global cooldown after it
		if left <= DB.spell_queue_window + 0.02:
			var after := maxf(player.cooldowns.gcd - left, player.cooldowns.get(id, 0.0) - left)
			queued = {"id": id, "left": left + maxf(0.0, after) + 0.15}
		return false
	if not game.skills.knows_ability(id):
		return false
	var spell: Dictionary = tuned(id)
	if id == "shadow" and spell.id == "vanish":
		id = "vanish"
	var t: Dictionary = spell.tuning
	if spell.kind == "stealth" and hidden:
		# casting Shadow again steps out of it
		break_shadow()
		shadow_grace = 0.0
		game.events.emit("log", {"text": "You step out of Shadow.", "kind": "muted"})
		return true
	# Shadow is not a vanish: it cannot be entered mid-fight unless the
	# spell says so ("inCombat": true in its tuning)
	if spell.kind == "stealth" and (game.resources.in_combat or game.targeting.attacking) and not t.get("inCombat", false):
		game.hud.error("You can't hide while in combat")
		return false
	var off_gcd: bool = t.get("offGlobalCooldown", false)
	# WoW's spell queue: pressed in the last moments of the global cooldown
	# (or its own), it goes off the instant it can, with no error.
	var own: float = player.cooldowns.get(id, 0.0)
	var wait := maxf(0.0 if off_gcd else player.cooldowns.gcd, own)
	if wait > 0:
		if wait <= DB.spell_queue_window + 0.02:
			queued = {"id": id, "left": wait + 0.15}
		elif own > 0:
			game.hud.error("%s is not ready yet" % spell.name)
		return false
	if queued != null and queued.id == id:
		queued = null
	if spell.kind == "camp" and game.camp.enemies_near:
		game.hud.error("You cannot make camp with enemies close by")
		return false
	if spell.kind == "portal" and not game.camp.portal_ok(spell.portal):
		return false
	var casts: bool = spell.kind in ["cast", "groundCast"] or spell.kind == "camp" or spell.kind == "portal" or spell.kind == "channel" or (spell.kind == "heal" and t.get("castTime", 0) > 0)
	if casts and player.moving:
		game.hud.error("You can't do that while moving")
		return false
	var missing := missing_gear(game, spell)
	if missing != "":
		game.hud.error(missing)
		return false
	if not game.resources.check(spell):
		return false
	# a heal goes to your friendly target when you have one (Dan, 2026-11-04)
	var ally = heal_target(spell)
	if ally != null and U.hyp(ally.position.x - player.position.x, ally.position.z - player.position.z) > float(spell.get("range", ALLY_HEAL_RANGE)):
		game.hud.error("Out of range")
		return false
	# a heal that consumes a heal over time needs one on you (Swiftmend)
	if spell.get("consumes") and not buffs.has(spell.consumes):
		game.hud.error("No %s to consume" % DB.spells.get(spell.consumes, {}).get("name", spell.consumes))
		return false
	var target = null
	if spell.kind == "charge":
		# a charge only ever goes at an enemy, never away from one
		target = _target_for(spell)
		if not target:
			return false
		if not _class_ready(spell, target):
			return false
		game.resources.spend(spell)
		return _charge(spell, target, id)
	if spell.kind == "leap":
		game.resources.spend(spell)
		return _leap(spell, id)
	if spell.get("target") == "enemy":
		target = _target_for(spell)
		if not target:
			return false
		if not _class_ready(spell, target):
			return false
		# Selecting an enemy never turns the player; hostile spells require
		# the target to remain in the player's facing cone.
		if not player.can_hit_while_moving(target.position.x, target.position.z):
			game.hud.error("Target needs to be in front of you.")
			return false
		if spell.get("mechanic") != "distract":
			break_shadow()
			if not spell.get("applies", {}).get("sleep") and spell.get("mechanic") != "fear":
				game.targeting.engage(target)
			elif game.targeting.current == target:
				game.targeting.stop_attack()
	elif not _class_ready(spell, null):
		return false
	if not off_gcd:
		player.cooldowns.gcd = stats.global_cooldown
	# a cast pays when it finishes (WoW); everything else pays now
	if not casts or spell.kind == "channel":
		var points: float = game.resources.spend(spell)
		if spell.get("spendsAll"):
			spell = spell.duplicate()
			spell.points = points
			spell.tuning = t.duplicate()
			if t.has("damageMultiplier") or t.has("perPoint"):
				spell.tuning.damageMultiplier = t.get("damageMultiplier", 0) + t.get("perPoint", 0) * points
		spell = _prepare_class_cast(spell, points)
		t = spell.tuning
	if casts:
		# casting stops the swing: a swing or shot on its way is dropped, and
		# the timers start again when the cast ends (WoW Classic)
		if player.pending != null and player.pending.type == "strike":
			player.pending = null
		player.pending_off = null
		player.pending_shot = null
		player.draw_weapons("ranged" if spell.get("ranged",false) else "melee")
		var channel: bool = spell.kind == "channel"
		player.casting = {"id": id, "spell": spell, "t": 0.0, "total": stats.hasted(t.castTime), "target": target, "pushbacks": 0, "channel": channel, "next": t.tickInterval if channel else 0.0}
		if spell.kind == "groundCast":
			var at := _ground_point(spell.range)
			spell = spell.duplicate()
			spell["groundAt"] = at
			player.casting.spell = spell
			game.events.emit("zone", {"id":spell.id,"x":at.x,"z":at.z,"radius":t.radius,"duration":player.casting.total,"school":"fire","key":"meteorWarning"})
		if channel:
			player.cooldowns[id] = t.cooldown
		_anim(spell, "shoot" if spell.get("ranged") else "brace", player.casting.total, 0.9, true, "windupAnim")
		_show(spell, "windup", player.position, player.facing, player)
		events.emit("castStart", {"id": id})
		return true
	if spell.kind == "cleave" or spell.kind == "burst":
		# mouse aim: the sweep goes where the cursor (or right stick) points
		if game.mouse_aim and game.raw_aim != null:
			player.face_towards(game.raw_aim.x, game.raw_aim.z)
		# the blow lands at its animation's impact frame, a moment after the
		# key press; it locks nothing and leaves the swing timer alone (WoW)
		var windup: float = stats.hasted(t.windup)
		var anim := windup + (0.35 if spell.kind == "burst" else 0.3)
		blows.append({"id": spell.id, "t": windup, "spell": spell})
		# a second spin (Cleave with two weapons) follows the first
		for k in range(1, int(t.get("spins", 1))):
			blows.append({"id": spell.id, "t": windup + 0.3 * k, "spell": spell})
		_anim(spell, "slam" if spell.kind == "burst" else "strike", anim, windup / anim, true)
		_show(spell, "cast", player.position, player.facing, player)
		player.cooldowns[id] = t.cooldown
		_cast_effects(spell)
		return true
	player.cooldowns[id] = t.cooldown
	_go(spell, target)
	return true


## the selected enemy if in range, else the soft target near the aim.
## `optional`: no target is fine (null); out of range is still refused (false).
func _target_for(spell: Dictionary, optional := false):
	var targeting = game.targeting
	var player = game.player
	var range_: float = minf(game.stats.ranged_reach,spell.range) if spell.get("ranged") and spell.get("mechanic") == "interruptArrow" else game.stats.ranged_reach if spell.get("ranged") else spell.range
	var in_range := func(e): return e != null and e.alive and U.hyp(e.position.x - player.position.x, e.position.z - player.position.z) <= range_ + e.radius * 0.6
	var cur = targeting.current
	if cur != null and cur.alive:
		# livestock and the watch: only with the crime key held (Alt)
		if not game.law.may_attack(cur):
			return false if optional else null
		if game.collision.wall_between(player.position.x, player.position.z, cur.position.x, cur.position.z):
			game.hud.error("Your target is behind cover.")
			return false if optional else null
		if in_range.call(cur):
			return cur
		game.hud.error("Out of range")
		return false if optional else null
	var soft = targeting.soft_target(game.raw_aim if game.raw_aim != null else player.position, range_)
	if in_range.call(soft):
		if game.collision.wall_between(player.position.x, player.position.z, soft.position.x, soft.position.z):
			game.hud.error("Your target is behind cover.")
			return false if optional else null
		targeting.select(soft)
		return soft
	if optional:
		return null
	game.hud.error("You have no target.")
	return null


## Lunge and other charges: dash at the target, strike on arrival.
func _charge(spell: Dictionary, target, id: String) -> bool:
	var player = game.player
	var t: Dictionary = spell.tuning
	var aim = target.position if target else game.raw_aim
	var dir := Vector2(sin(player.facing), cos(player.facing))
	if aim != null:
		var dx: float = aim.x - player.position.x
		var dz: float = aim.z - player.position.z
		var len := U.hyp(dx, dz)
		if len > 0.3:
			dir = Vector2(dx / len, dz / len)
	if target:
		break_shadow()
		game.targeting.engage(target)
	player.facing = atan2(dir.x, dir.y)
	player.cooldowns[id] = t.cooldown
	player.cooldowns.gcd = game.stats.global_cooldown
	player.cooldowns.attack = maxf(player.cooldowns.attack, t.duration + 0.2)
	player.cooldowns.attackOff = maxf(player.cooldowns.attackOff, t.duration + 0.2)
	player.lunge = {"t": 0.0, "dir": {"x": dir.x, "z": dir.y}, "id": spell.id, "speed": t.distance / t.duration, "duration": t.duration}
	_anim(spell, "strike", t.duration + 0.25, 0.7, true)
	_show(spell, "cast", player.position, player.facing, player)
	game.events.emit("playerLunge", {})
	return true


## Disengage: a jump back, away from the target (or from where you face);
## you keep facing the way you were.
func _leap(spell: Dictionary, id: String) -> bool:
	var player = game.player
	var t: Dictionary = spell.tuning
	var cur = game.targeting.current
	var from = cur.position if cur != null and cur.alive else null
	var dir := Vector2(-sin(player.facing), -cos(player.facing))
	if from != null:
		var dx: float = player.position.x - from.x
		var dz: float = player.position.z - from.z
		var len := U.hyp(dx, dz)
		if len > 0.3:
			dir = Vector2(dx / len, dz / len)
	player.cooldowns[id] = t.cooldown
	if not t.get("offGlobalCooldown"):
		player.cooldowns.gcd = game.stats.global_cooldown
	player.lunge = {"t": 0.0, "dir": {"x": dir.x, "z": dir.y}, "id": spell.id, "speed": t.distance / t.duration, "duration": t.duration}
	_anim(spell, "brace", t.duration + 0.2, 0.5, true)
	_show(spell, "cast", player.position, player.facing, player)
	game.events.emit("playerLunge", {})
	game.events.emit("log", {"text": "%s!" % spell.name, "kind": "muted"})
	return true


## a spell going off: instant effects now, bolts and zones over time
func _go(spell: Dictionary, target) -> void:
	var player = game.player
	var events: Events = game.events
	var t: Dictionary = spell.tuning
	_cast_effects(spell)
	_show(spell, "cast", player.position, player.facing, player)
	if spell.get("ranged"):
		_queue_shot(spell, target)
		return
	if _class_release(spell, target):
		return
	# kinds with no pose of their own take a look's pose
	if spell.kind in ["stealth", "purge"] and DB.spell_fx.get(spell.id, {}).has("anim"):
		_anim(spell, "brace", 0.5, 0.4)
	match spell.kind:
		"groundCast":
			var at: Vector3 = spell.groundAt
			at.y = Terrain.height_at(at.x,at.z)
			_anim(spell, "slam", 0.55, 0.4)
			for enemy in _near_enemies(at,t.radius):
				_damage(spell,enemy,_spell_base(t),"",1.0,{"periodic":true})
			game.events.emit("classImpact", {"position":at,"radius":t.radius,"school":spell.school})
			_show(spell,"impact",at,player.facing)
		"cast":
			var sigil = buffs.get("echoSigil")
			if sigil != null and game.archetype_id == "wizard" and U.hyp(player.position.x-sigil.at.x,player.position.z-sigil.at.z) <= sigil.radius:
				spell = spell.duplicate()
				spell["sigilEcho"] = {"at":sigil.at,"scale":sigil.scale}
				buffs.erase("echoSigil")
			var d := U.hyp(target.position.x - player.position.x, target.position.z - player.position.z)
			bolts.append({"enemy": target, "id": spell.id, "t": d / t.projectileSpeed, "spell": spell})
			events.emit("projectile", {"kind": "holy" if spell.get("school") == "holy" else "bolt", "from": player.position + Vector3(0, 1.3, 0), "to": target.position, "speed": t.projectileSpeed, "follow": target, "life": d / t.projectileSpeed, "look": spell.id})
			# the release: a look's own pose as the bolt leaves the hands
			if DB.spell_fx.get(spell.id, {}).has("anim"):
				_anim(spell, "cast", 0.4, 0.3)
		"instant":
			_anim(spell, "strike", 0.4, 0.4)
			_show(spell, "impact", target.position, _facing_to(target))
			# a weapon strike (`damageMultiplier`, e.g. Sinister Strike) rolls the weapon
			if t.has("damageMultiplier"):
				var hit := _damage(spell, target, _weapon_base(t), "Your %s hits the {name} for {n}." % spell.name, t.damageMultiplier * _bonus_vs(spell, target), {"stagger": 0.25, "knockFrom": player.position, "knockback": 0.3})
				_landed(spell, target, hit)
				return
			events.emit("spellFlash", {"position": target.position, "school": spell.get("school")})
			var hit := _damage(spell, target, _spell_base(t), "Your %s hits the {name} for {n}." % spell.name)
			_landed(spell, target, hit)
			if spell.get("mechanic") == "conviction" and hit.amount > 0:
				_schedule_holy_echoes(spell,[{"enemy":target,"amount":hit.amount,"crit":hit.crit}])
		"dot":
			_anim(spell, "strike", 0.45, 0.4)
			_show(spell, "impact", target.position, _facing_to(target))
			_apply_dot(spell, target)
		"control":
			_anim(spell, "brace", 0.45, 0.4)
			_show(spell, "impact", target.position, _facing_to(target))
			events.emit("spellFlash", {"position": target.position, "school": spell.get("school")})
			_landed(spell, target, null)
		"aoe":
			_anim(spell, "slam", 0.5, 0.5)
			var at = _ground_point(spell.range) if spell.get("target") == "ground" else player.position
			zones.append({"id": spell.id, "x": at.x, "z": at.z, "left": t.duration, "next": 0.0, "radius": t.radius, "slow": t.get("slow", 0), "damage": t.get("damageMax", 0) > 0})
			events.emit("zone", {"id": spell.id, "x": at.x, "z": at.z, "radius": t.radius, "duration": t.duration, "school": spell.get("school")})
			_show(spell, "impact", Vector3(at.x, Terrain.height_at(at.x, at.z), at.z), player.facing)
			events.emit("log", {"text": "%s takes root." % spell.name if spell.get("target") == "ground" else "You consecrate the ground: %s." % spell.name, "kind": "hit"})
		"guard":
			player.braced = t.window
			player.guard_rule = {"blocks": t.get("blocks", 1), "reduction": t.get("reduction", 0), "miss": t.get("miss", false), "name": spell.name}
			_anim(spell, "brace", 0.5, 0.4)
			events.emit("playerBrace", {"id": spell.id, "window": t.window})
		"interrupt":
			_anim(spell, "brace", 0.35, 0.4)
			_show(spell, "impact", target.position, _facing_to(target))
			var broke = target.interrupt(t.lockout)
			events.emit("spellFlash", {"position": target.position, "school": spell.get("school")})
			_damage(spell, target, _spell_base(t), "")
			if typeof(broke) == TYPE_STRING:
				events.emit("interrupted", {"enemy": target})
				events.emit("log", {"text": "You interrupt the %s's %s." % [target.cfg.name, broke], "kind": "level"})
				game.hud.toast("Interrupted!")
			elif typeof(broke) == TYPE_BOOL and broke == false:
				game.hud.error("%s's attack cannot be interrupted" % target.cfg.name)
			else:
				events.emit("log", {"text": "%s: the %s was not casting." % [spell.name, target.cfg.name], "kind": "muted"})
		"camp":
			game.camp.pitch(player.position.x, player.position.z)
			# the fire is lit: cooking opens with it, one belt slot for both
			# (Dan, 2026-11-02)
			if game.hud and game.skills.knows_ability("cook") and not game.hud.panel_open("cooking"):
				game.hud.toggle_window("cooking")
		"portal":
			game.camp.portal(spell.id, spell.portal, t.cooldown)
		"buff":
			_anim(spell, "brace", 0.6, 0.4)
			buffs[spell.id] = {"name": spell.name, "left": t.duration, "total": t.duration, "damageBonus": t.damageBonus, "reduction": t.get("reduction", 0)}
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "%s: your damage is raised by %s%% for %s seconds." % [spell.name, U.n(t.damageBonus), U.n(t.duration)], "kind": "hit"})
		"stealth":
			_enter_shadow(spell)
		"trap":
			_anim(spell, "slam", 0.45, 0.5)
			var key := "%s-%.3f" % [spell.id, game.time]
			var arm: float = t.armTime
			for e in (game.builds.effects("trap") if game.builds else []):
				arm = minf(arm, e.get("armTime", arm))
			traps.append({"id": spell.id, "key": key, "x": player.position.x, "z": player.position.z, "arm": arm, "left": t.lifetime})
			while traps.filter(func(x): return x.id == spell.id).size() > t.maxTraps:
				var old = null
				for x in traps:
					if x.id == spell.id:
						old = x
						break
				traps.erase(old)
				events.emit("trapGone", {"key": old.key})
			events.emit("trap", {"key": key, "x": player.position.x, "z": player.position.z, "radius": t.triggerRadius, "duration": t.lifetime})
			events.emit("log", {"text": "You set a %s." % spell.name, "kind": "muted"})
		"purge":
			var points: float = spell.get("points", 0)
			var healed: float = player.heal(player.max_health * t.healPerPoint * points / 100.0)
			for d in dots:
				if d.id == "rot":
					d.left += t.extend
			for a in auras:
				if not a.stun and not a.sleep:
					a.left += t.extend
			if healed >= 1:
				events.emit("damageNumber", {"target": player, "amount": U.jround(healed), "kind": "heal"})
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "You purge %d Corruption and heal %d." % [U.jround(points), U.jround(healed)], "kind": "hit"})
		"heal":
			_anim(spell, "brace", 0.5, 0.4)
			var amount := _heal_roll(t)
			var used := ""
			# Swiftmend: eat a heal over time for a share of what it had left
			var hot = buffs.get(spell.get("consumes", ""))
			if hot != null and hot.get("hot"):
				amount += hot_left(spell.consumes, hot) * t.get("consumePercent", 100) / 100.0
				buffs.erase(spell.consumes)
				used = " (%s consumed)" % hot.name
			var ally = heal_target(spell)
			if ally != null:
				var given := _heal_ally(ally, amount)
				events.emit("log", {"text": "Your %s heals %s for %d.%s" % [spell.name, ally.name, U.jround(given), used], "kind": "hit"})
				return
			var healed := _heal_player(amount)
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "Your %s heals you for %d.%s" % [spell.name, U.jround(healed), used], "kind": "hit"})
		"hot":
			_anim(spell, "brace", 0.5, 0.4)
			var ally = heal_target(spell)
			if ally != null:
				ally_hots = ally_hots.filter(func(h): return not (h.id == spell.id and h.on == ally))
				ally_hots.append({"id": spell.id, "on": ally, "left": t.duration, "next": t.tickInterval})
				events.emit("log", {"text": "%s: %s heals every %s seconds for %s seconds." % [spell.name, ally.name, U.n(t.tickInterval), U.n(t.duration)], "kind": "hit"})
				return
			buffs[spell.id] = {"name": spell.name, "left": t.duration, "total": t.duration, "hot": true, "next": t.tickInterval}
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "%s: you heal every %s seconds for %s seconds." % [spell.name, U.n(t.tickInterval), U.n(t.duration)], "kind": "hit"})
		"healZone":
			_anim(spell, "slam", 0.5, 0.5)
			var at = _ground_point(spell.range) if spell.get("target") == "ground" else player.position
			zones.append({"id": spell.id, "x": at.x, "z": at.z, "left": t.duration, "next": 0.0, "radius": t.radius, "slow": t.get("slow", 0), "damage": _hurts(t), "heal": true})
			events.emit("zone", {"id": spell.id, "x": at.x, "z": at.z, "radius": t.radius, "duration": t.duration, "school": spell.get("school", "holy")})
			_show(spell, "impact", Vector3(at.x, Terrain.height_at(at.x, at.z), at.z), player.facing)
			events.emit("log", {"text": "%s blooms on the ground." % spell.name, "kind": "hit"})
		"healBurst":
			_anim(spell, "slam", 0.5, 0.5)
			var at = _ground_point(spell.range) if spell.get("target") == "ground" else player.position
			var hits := []
			if _hurts(t):
				hits = game.enemies.list.filter(func(e): return e.alive and not e.protected and U.hyp(e.position.x - at.x, e.position.z - at.z) - e.radius * 0.5 <= t.radius)
				for e in hits:
					_landed(spell, e, _damage(spell, e, _spell_base(t), "", 1, {"stagger": 0.0}))
			var healed := 0.0
			if U.hyp(player.position.x - at.x, player.position.z - at.z) <= t.radius + player.radius:
				healed = _heal_player(_heal_roll(t))
			events.emit("burst", {"id": spell.id, "position": Vector3(at.x, Terrain.height_at(at.x, at.z), at.z), "radius": t.radius, "hits": hits, "school": spell.get("school", "holy")})
			_show(spell, "impact", Vector3(at.x, Terrain.height_at(at.x, at.z), at.z), player.facing)
			var parts := []
			if healed >= 1:
				parts.append("heals you for %d" % U.jround(healed))
			if not hits.is_empty():
				parts.append("strikes %s" % ("the " + hits[0].cfg.name if hits.size() == 1 else "%d foes" % hits.size()))
			events.emit("log", {"text": "%s %s." % [spell.name, " and ".join(parts) if not parts.is_empty() else "bursts"], "kind": "hit"})
		"thorns":
			_anim(spell, "brace", 0.5, 0.4)
			buffs[spell.id] = {"name": spell.name, "left": t.duration, "total": t.duration, "thorns": true}
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "%s: whatever strikes you is hurt for %s seconds." % [spell.name, U.n(t.duration)], "kind": "hit"})
		"shield":
			_anim(spell, "brace", 0.5, 0.4)
			var absorb := U.jround(player.max_health * t.absorbPercent / 100.0)
			if spell.id == "lightShield":
				reprisal_cap = t.get("reprisalCap",14.0)
			buffs[spell.id] = {"name": spell.name, "icon":spell.id, "left": t.duration, "total": t.duration, "absorb": absorb, "reprisalStore":t.get("reprisalStore",0.0)}
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "%s will absorb %d damage." % [spell.name, absorb], "kind": "hit"})


## where a ground spell lands: the cursor, no further than its range
func _ground_point(range_: float) -> Vector3:
	var p: Vector3 = game.player.position
	var aim = game.raw_aim
	if aim == null:
		aim = Vector3(p.x + sin(game.player.facing) * 4, 0, p.z + cos(game.player.facing) * 4)
	var dx: float = aim.x - p.x
	var dz: float = aim.z - p.z
	var d := U.hyp(dx, dz)
	var k := range_ / d if d > range_ else 1.0
	return Vector3(p.x + dx * k, 0, p.z + dz * k)


## a weapon roll for an ability; `bothHands` adds the off hand's when dual wielding
func _weapon_base(t: Dictionary) -> float:
	var stats = game.stats
	var base := Stats.weapon_roll(game.random, stats)
	if t.get("bothHands") and stats.dual_wielding:
		var off_normalization: float = DB.attack.abilityWeaponSeconds / stats.hand_speed("off")
		base += Stats.swing_roll(game.random, stats, "off") * off_normalization * DB.CONFIG.stats.offHandDamage
	return base + _gear_extra(t, t.get("damageMultiplier", 1.0))


## A weapon ability's extra from the editor's Scaling numbers: a base roll
## (`damageMin`-`damageMax`) and a share of spell power (`spellPower`, none
## unless stated), divided by the multiplier the weapon roll gets so they
## land as stated (Dan, 2026-11-02: every ability can scale with both)
func _gear_extra(t: Dictionary, mult: float) -> float:
	var extra: float = t.get("spellPower", 0.0) * game.stats.spell_power
	if t.has("damageMin"):
		extra += t.damageMin + (t.get("damageMax", t.damageMin) - t.damageMin) * game.random.call()
	return extra / mult if mult > 0 else 0.0


func _bonus_vs(spell: Dictionary, enemy) -> float:
	var bv = spell.get("bonusVs")
	if not bv:
		return 1.0
	var has: bool = has_status(enemy, bv.status) if bv.has("status") else has_aura(enemy, bv.get("aura", ""))
	return 1 + bv.percent / 100.0 if has else 1.0


## what follows a spell's hit on its target: its aura, a follow-up effect,
## and the stacks it gives you
func _landed(spell: Dictionary, enemy, hit) -> void:
	if hit != null and hit.amount > 0:
		for resource in spell.get("hitGain",{}):
			game.resources.add(resource, spell.hitGain[resource])
	if not enemy.alive and hit != null or hit != null and hit.get("miss"):
		return
	if spell.get("applies"):
		apply_aura(spell.id, enemy, spell.applies, spell.get("spreadsOnDeath", false))
	var f = tuned(spell.get("follow", ""))
	if f != null and enemy.alive:
		if f.kind == "dot":
			_apply_dot(f, enemy, null, true)
		elif f.get("applies"):
			apply_aura(f.id, enemy, f.applies, f.get("spreadsOnDeath", false))
	if spell.get("stacks") and hit != null:
		var s: Dictionary = spell.stacks
		var b = buffs.get(s.id)
		var stacks := mini(int(s.max), (int(b.get("stacks", 0)) if b else 0) + 1)
		buffs[s.id] = {"name": s.name, "icon": spell.id, "left": s.duration, "total": s.duration, "stacks": stacks, "critBonus": s.critBonus}


## Put an aura on an enemy (or refresh it). Stuns and sleeps go through
## the enemy's control rules: a boss only staggers, an elite wears it off.
func apply_aura(id: String, enemy, aura: Dictionary, spreads := false) -> void:
	if not enemy.alive:
		return
	var left: float = aura.duration
	if aura.get("root"):
		if not _ordinary(enemy):
			return
		enemy.root_left = maxf(enemy.root_left, left)
	if aura.get("stun") or aura.get("sleep"):
		left = enemy.control("sleep" if aura.get("sleep") else "stun", aura.duration)
		if left <= 0:
			var text := "The %s cannot be %s: it staggers." % [enemy.cfg.name, "slept" if aura.get("sleep") else "stunned"] if enemy.stagger_bar != null else "The %s shrugs it off." % enemy.cfg.name
			game.events.emit("log", {"text": text, "kind": "muted", "throttle": "cc-immune"})
			return
	var had = null
	for a in auras:
		if a.enemy == enemy and a.id == id:
			had = a
	var rec := {"enemy": enemy, "id": id, "name": aura.name, "left": left, "total": left, "then": aura.get("then"), "status": aura.get("status", ""), "spreads": spreads, "aura": aura}
	for k in AURA_EFFECTS:
		rec[k] = aura.get(k, 0)
	if had != null:
		had.merge(rec, true)
	else:
		auras.append(rec)
		game.events.emit("log", {"text": "The %s is %s." % [enemy.cfg.name, aura.name.to_lower()], "kind": "hit"})


## a dot takes hold (or is refreshed)
func _apply_dot(spell: Dictionary, target, ammo = null, quiet := false) -> void:
	var t: Dictionary = spell.tuning
	var had = null
	for d in dots:
		if d.enemy == target and d.id == spell.id:
			had = d
	if had != null:
		had.left = t.duration
		had.ammo = ammo
		had.erase("strength")
	else:
		dots.append({"enemy": target, "id": spell.id, "left": t.duration, "next": t.tickInterval, "ammo": ammo})
	if spell.get("applies"):
		apply_aura(spell.id, target, spell.applies)
	game.events.emit("classAffliction", {"position":target.position,"school":spell.get("school","nature")})
	if quiet:
		return
	target.hurt(0, {"stagger": 0.1}) # they notice
	game.events.emit("enemyHit", {"enemy": target, "damage": 0, "kind": "strike"})
	var text := "%s refreshed on the %s." % [spell.name, target.cfg.name] if had != null else "The %s is afflicted by %s." % [target.cfg.name, spell.name]
	game.events.emit("log", {"text": text, "kind": "hit"})


## A bow ability: the bow comes to hand, one arrow is loosed, and the
## spell's effect lands when it arrives. Triple Shot looses more arrows at
## enemies near the target.
func cancel_ranged_windup() -> void:
	ranged_windups.clear()
	if game.player.casting != null and game.player.casting.spell.get("ranged"):
		var id: String=game.player.casting.id
		game.player.casting=null
		game.events.emit("castEnd",{"id":id,"done":false})

func _queue_shot(spell: Dictionary,target) -> void:
	var player=game.player
	player.pending_shot=null
	player.cooldowns.ranged=maxf(player.cooldowns.ranged,game.stats.attack_cooldown_for("ranged"))
	player.ranged_ready_at=maxf(player.ranged_ready_at,game.time+player.cooldowns.ranged)
	player.last_swing_at=game.time
	player.draw_weapons("ranged")
	_anim(spell,"shoot",0.45,0.27)
	if player.rig.action != null:player.rig.action.ranged=true
	ranged_windups.append({"spell":spell,"target":target,"left":0.12})

func _shoot(spell: Dictionary, target) -> void:
	var player = game.player
	var inventory = game.inventory
	var ammo = inventory.ammo
	if ammo:
		inventory.spend_arrow(ammo)
	player.pending_shot = null
	player.hold_bow(true)
	var from: Vector3 = player.bow_muzzle()
	var speed: float = DB.auto_shot.arrowSpeed
	var t: Dictionary = spell.tuning
	var targets := [target]
	if t.get("maxTargets", 1) > 1:
		var dist := func(e): return U.hyp(e.position.x - target.position.x, e.position.z - target.position.z)
		var near: Array = game.enemies.list.filter(func(e): return e.alive and not e.protected and e != target and dist.call(e) <= t.spread)
		if spell.get("mechanic") == "pierce":
			var axis := Vector2(target.position.x-from.x,target.position.z-from.z).normalized()
			near = near.filter(func(e):
				var offset := Vector2(e.position.x-target.position.x,e.position.z-target.position.z)
				return offset.dot(axis) > 0.0 and absf(offset.cross(axis)) <= 0.8 + e.radius)
		near.sort_custom(func(a, b): return dist.call(a) < dist.call(b))
		targets.append_array(near.slice(0, int(t.maxTargets) - 1))
	for e in targets:
		var life := U.hyp(e.position.x - from.x, e.position.z - from.z) / speed
		bolts.append({"enemy": e, "id": spell.id, "t": life, "ammo": ammo, "spell": spell})
		game.events.emit("projectile", {"kind": "arrow", "from": from, "to": e.position, "follow": e, "speed": speed, "life": life, "look": spell.id})
	game.events.emit("playerShot", {})


## a bow roll plus the arrow's own damage (as Auto Shot's)
func _bow_roll(ammo) -> float:
	var stats = game.stats
	return Stats.swing_roll(game.random, stats, "ranged") + (Items.get_def(ammo).get("ammoDps", 0) if ammo else 0.0) * stats.hand_speed("ranged")


## a bow ability's arrow has arrived
func _arrow_lands(spell: Dictionary, enemy, ammo) -> void:
	game.events.emit("spellFlash", {"position": enemy.position, "school": spell.get("school")})
	_show(spell, "impact", enemy.position, _facing_to(enemy))
	if spell.kind == "dot":
		if spell.get("mechanic") != "ignite" or not _ignite_tar(enemy):
			_apply_dot(spell, enemy, ammo)
		return
	var hit := _damage(spell, enemy, _bow_roll(ammo) + _gear_extra(spell.tuning, spell.tuning.damageMultiplier), "Your %s hits the {name} for {n}." % spell.name, spell.tuning.damageMultiplier, {"stagger": 0.15, "knockFrom": game.player.position, "knockback": 0.1})
	_landed(spell, enemy, hit)
	if hit.amount > 0 and enemy.alive and spell.get("mechanic") == "interruptArrow":
		if enemy.interrupt(spell.tuning.lockout) is String:
			game.hud.toast("Interrupted!")


## Called by the player when a pending spell blow lands (cleave, burst, charge).
func resolve(id: String, spell = null) -> Array:
	if spell == null:
		spell = tuned(id)
	var player = game.player
	if player.dead or spell == null:
		return []
	if spell.kind == "burst":
		return _burst(spell)
	if spell.kind == "charge":
		return _charge_hit(spell)
	if spell.kind != "cleave":
		return []
	var events: Events = game.events
	var t: Dictionary = spell.tuning
	var fx := sin(player.facing)
	var fz := cos(player.facing)
	var cos_limit := cos(deg_to_rad(t.coneDegrees / 2.0))
	var in_cone := []
	for e in game.enemies.list:
		if not e.alive or e.protected:
			continue
		var dx: float = e.position.x - player.position.x
		var dz: float = e.position.z - player.position.z
		var d := U.hyp(dx, dz)
		if d - e.radius * 0.6 > t.range:
			continue
		if t.coneDegrees < 360 and d > 0.8 and (dx * fx + dz * fz) / d < cos_limit:
			continue
		in_cone.append([d, e])
	in_cone.sort_custom(func(a, b): return a[0] < b[0])
	var hits := in_cone.slice(0, int(t.maxTargets)).map(func(p): return p[1])
	events.emit("cleave", {"id": spell.id, "position": player.position, "facing": player.facing, "range": t.range, "degrees": t.coneDegrees})
	_show(spell, "impact", player.position, player.facing)
	if hits.is_empty():
		events.emit("log", {"text": "%s cuts only air." % spell.name, "kind": "muted"})
		return []
	var most := 0
	for e in hits:
		var hit := _damage(spell, e, _weapon_base(t), "", t.damageMultiplier, {"stagger": 0.2, "knockFrom": player.position, "knockback": 0.3})
		most = maxi(most, hit.amount)
		_landed(spell, e, hit)
	events.emit("log", {"text": "%s hits %s for %d." % [spell.name, "the " + hits[0].cfg.name if hits.size() == 1 else "%d foes" % hits.size(), most], "kind": "hit"})
	return hits


func _burst(spell: Dictionary) -> Array:
	var player = game.player
	var events: Events = game.events
	var t: Dictionary = spell.tuning
	var hits: Array = game.enemies.list.filter(func(e): return e.alive and not e.protected and U.hyp(e.position.x - player.position.x, e.position.z - player.position.z) - e.radius * 0.5 <= t.radius)
	var most := 0
	var initial_hits := []
	for e in hits:
		if spell.get("mechanic") == "erupt":
			_cash_out(spell, e)
			continue
		var base: float = spell.get("wardDamage", _weapon_base(t) if t.damageMultiplier > 0 else _spell_base(t))
		var multiplier: float = t.damageMultiplier if t.damageMultiplier > 0 else 1.0
		var hit := _damage(spell, e, base, "", multiplier, {"stagger": t.stagger, "knockFrom": player.position, "knockback": t.knockback, "heavy": bool(t.get("interrupts", false))})
		most = maxi(most, hit.amount)
		_landed(spell, e, hit)
		if hit.amount > 0:
			initial_hits.append({"enemy":e,"amount":hit.amount,"crit":hit.crit})
	if spell.get("mechanic") == "conviction":
		_schedule_holy_echoes(spell,initial_hits)
	# Healing Storm: a share of your health for each enemy hit
	if t.get("healPerHit") and not hits.is_empty():
		_heal_number(player.heal(player.max_health * t.healPerHit * hits.size() / 100.0))
	events.emit("burst", {"id": spell.id, "position": player.position, "radius": t.radius, "hits": hits, "school": spell.get("school")})
	_show(spell, "impact", player.position, player.facing)
	# striking engages: auto attack the target, or the first foe left standing
	var tg = game.targeting
	var alive := hits.filter(func(e): return e.alive)
	if not alive.is_empty():
		tg.engage(tg.current if tg.current != null and alive.has(tg.current) else alive[0])
	if not hits.is_empty():
		events.emit("log", {"text": "%s %s %s for %d." % [spell.name, "staggers" if t.get("interrupts") else "hits", "the " + hits[0].cfg.name if hits.size() == 1 else "%d foes" % hits.size(), most], "kind": "hit"})
	else:
		events.emit("log", {"text": "%s strikes only earth." % spell.name, "kind": "muted"})
	return hits


## the charge has arrived: strike the target if close, else the nearest foe
func _charge_hit(spell: Dictionary) -> Array:
	var player = game.player
	var targeting = game.targeting
	var t: Dictionary = spell.tuning
	var dist := func(e): return U.hyp(e.position.x - player.position.x, e.position.z - player.position.z) - e.radius
	var cur = targeting.current
	var best = cur if cur != null and cur.alive and dist.call(cur) <= t.hitRadius + 0.4 else null
	if best == null:
		for e in game.enemies.list:
			if e.alive and not e.protected and dist.call(e) <= t.hitRadius and (best == null or dist.call(e) < dist.call(best)):
				best = e
	if best == null:
		game.events.emit("playerMiss", {})
		return []
	targeting.engage(best)
	var hit := _damage(spell, best, Stats.weapon_roll(game.random, game.stats), "", t.damageMultiplier, {"stagger": 0.3, "knockFrom": player.position, "knockback": 0.4})
	_show(spell, "impact", best.position, player.facing)
	game.events.emit("log", {"text": "You %s into the %s for %d.%s" % [spell.name.to_lower(), best.cfg.name, hit.amount, " A critical blow!" if hit.crit else ""], "kind": "hit"})
	_landed(spell, best, hit)
	return [best]


## A spell's hit before multipliers: its base roll, plus a share of your
## spell power (`spellPower`, 1 = all of it) and of a weapon roll
## (`weaponDamage`), as WoW coefficients (Dan, 2026-11-02): every spell grows
## with gear, so weapons and caster weapons matter to every class
func _spell_base(t: Dictionary) -> float:
	var base: float = (t.damageMin + (t.damageMax - t.damageMin) * game.random.call()) * game.stats.spell_scale
	base += t.get("spellPower", 1.0) * game.stats.spell_power
	if t.get("weaponDamage", 0):
		base += t.weaponDamage * Stats.weapon_roll(game.random, game.stats)
	return base


# ------------------------------------------------------- your hits, any source
## What changes a hit of yours on `enemy`: its auras (Marked), a boss's
## stagger, Righteous stacks, and Opportunist. `weapon`: a weapon or bow
## blow (Opportunist crits only those).
func hit_mods(enemy, weapon := true) -> Dictionary:
	var player = game.player
	var crit_bonus := 0.0
	var accuracy := 0.0
	for b in buffs.values():
		crit_bonus += b.get("critBonus", 0) * b.get("stacks", 1)
		accuracy += b.get("accuracy", 0) * b.get("stacks", 1)
	var force_crit := false
	if weapon and trait_.get("id") == "opportunist":
		# from behind: you stand in the half of the ground the enemy faces away from
		var dx: float = player.position.x - enemy.position.x
		var dz: float = player.position.z - enemy.position.z
		var behind: bool = dx * sin(enemy.facing) + dz * cos(enemy.facing) < 0
		force_crit = shadow_grace > 0 or hidden or behind
	var mult: float = enemy.damage_taken_scale
	if game.builds:
		for e in game.builds.effects("statusDamage"):
			if has_status(enemy, e.status):
				mult *= 1 + e.percent / 100.0
	return {"mult": mult, "critBonus": crit_bonus, "forceCrit": force_crit, "accuracy": accuracy}


## after a hit of yours: a crit uses up the Righteous stacks
func after_hit(hit) -> void:
	if hit == null:
		return
	# Bloodlust: every hit that lands adds a stack
	if game.builds and hit.amount > 0:
		for e in game.builds.effects("hitStacks"):
			var b = buffs.get("hitStacks")
			var n := mini(int(e.max), (int(b.get("stacks", 0)) if b else 0) + 1)
			buffs["hitStacks"] = {"name": e.name, "icon": "battleCry", "left": e.duration, "total": e.duration, "stacks": n, "damageBonus": e.percent * n}
	if not hit.crit:
		return
	for id in buffs.keys():
		if buffs[id].get("critBonus"):
			buffs.erase(id)


## One hit of a spell on an enemy: the shared damage formula, the number,
## the log line ({name} and {n} filled in), and the kill.
## `carry`: a dot passes itself, so its tick keeps the fraction of a point
## left over for the next tick (see Stats.compute_hit)
## A direct hit can miss (Stats.miss_chance); a tick (dot, channel, ground
## zone: `carry` or hurt_opts.periodic) never does.
func _damage(spell: Dictionary, enemy, base: float, line: String, mult := 1.0, hurt_opts := {"stagger": 0.12}, carry = null) -> Dictionary:
	var t: Dictionary = spell.tuning
	var weapon: bool = spell.get("ranged", false) or t.has("damageMultiplier") or (t.has("tickMultiplier") and not t.has("damageMin"))
	var m := hit_mods(enemy, weapon)
	mult *= _execute_scale(spell, enemy) * _class_damage_scale(spell) * spell.get("classMultiplier",1.0)
	if spell.get("mechanic") == "consumeAim":
		for a in auras:
			if a.enemy == enemy and a.id == "quickShot":
				mult *= 1.0 + t.aimBonus
				auras.erase(a)
				break
	var school: String = spell.get("school", "physical")
	if carry == null and not hurt_opts.get("periodic", false) and not spell.get("fullReprisal", false) and Stats.rolls_miss(game.random, game.stats.stat_block, Stats.enemy_block(enemy.cfg), m.accuracy):
		var miss: Dictionary = game.combat.missed(enemy, "Your %s misses" % spell.name)
		if not (spell.kind in ["dot", "thorns"]) and not game.targeting.attacking:
			game.targeting.engage(enemy)
		return miss
	var o := {"base": base, "mult": mult * m.mult * damage_scale * game.afterlife.damage_scale_against(enemy), "school": school, "critBonus": m.critBonus, "forceCrit": m.forceCrit or spell.get("fullReprisal",false)}
	if carry != null:
		o.carry = carry.get("carry", 0.0)
	var hit := Stats.compute_hit(game.random, game.stats.stat_block, Stats.enemy_block(enemy.cfg), o)
	if carry != null:
		carry.carry = hit.carry
		if hit.amount <= 0:
			return hit
	after_hit(hit)
	# spells never stop an enemy in its tracks (Dan, 2026-11-02: Blight Bolt
	# halted what it hit) unless the spell's data asks for it: `stagger`
	# (seconds) and `knockback` in its tuning, as Shield Bash does
	var opts: Dictionary = hurt_opts.duplicate()
	# Damage ticks retain their numbers and spell effects without replaying
	# a weapon contact, flinch, hit-stop or camera kick on every tick.
	opts.periodic = carry != null or hurt_opts.get("periodic", false)
	if opts.periodic:
		opts.quiet = true
	opts.stagger = float(t.get("stagger", 0.0))
	opts.knockback = float(t.get("knockback", 0.0))
	if spell.get("mechanic") == "ordinaryPush" and not _ordinary(enemy):
		opts.knockback = 0.0
	if spell.get("mechanic") == "ordinaryPush":
		opts.knockFrom = game.player.position
	if spell.get("mechanic") == "heavy":
		opts.heavy = true
	enemy.hurt(hit.amount, opts)
	var events: Events = game.events
	events.emit("damageNumber", {"target": enemy, "amount": hit.amount, "crit": hit.crit, "kind": "dealt", "hand": "ranged" if spell.get("ranged") else "main", "ability": true})
	events.emit("enemyHit", {"enemy": enemy, "damage": hit.amount, "crit": hit.crit, "kind": "strike" if school == "physical" else "spell", "school": school, "hand": "ranged" if spell.get("ranged") else hurt_opts.get("hand","main"), "periodic": carry != null or hurt_opts.get("periodic",false)})
	if not opts.periodic and hit.amount > 0:
		events.emit("hitImpact", {"enemy": enemy, "crit": hit.crit, "heavy": opts.get("heavy", false) or opts.knockback > 0})
	if line != "":
		events.emit("log", {"text": line.replace("{name}", enemy.cfg.name).replace("{n}", str(hit.amount)) + (" A critical blow!" if hit.crit else ""), "kind": "hit"})
	# a rune answers the spell (a bow's for bow abilities, else the main hand's)
	if game.runes and not hurt_opts.get("periodic", false) and spell.kind != "dot":
		game.runes.on_spell_hit(enemy, hit.amount, spell.get("ranged", false))
	if enemy.dead:
		game.combat.on_enemy_defeated(enemy)
	# hitting an enemy with nothing engaged starts auto attack on it
	elif not (spell.kind in ["dot", "thorns"]) and not (hidden and hurt_opts.get("periodic",false)) and not game.targeting.attacking:
		game.targeting.engage(enemy)
	return hit


## Executes (Assassinate, Executioner, the Assassin passive): more damage
## to an enemy below a share of its health
func _execute_scale(spell: Dictionary, enemy) -> float:
	var list := []
	if spell.get("execute"):
		list.append(spell.execute)
	if game.builds:
		for e in game.builds.effects("execute"):
			if not e.get("spenders") or spell.get("spendsAll"):
				list.append(e)
	var s := 1.0
	var share: float = 100.0 * enemy.health / maxf(1, enemy.max_health)
	for e in list:
		if share < e.below:
			s *= 1 + e.percent / 100.0
	return s


## Empowered Light: the holy damage a landed swing adds to itself
func echo_amount(hit) -> int:
	var pct: float = trait_.get("echoPercent", 0) if trait_.get("id") == "empoweredLight" else 0.0
	if not pct or hit == null or not (hit.amount > 0):
		return 0
	return maxi(1, U.jround(hit.amount * pct / 100.0))


# ------------------------------------------------------------- Shadow
func _enter_shadow(spell: Dictionary) -> void:
	var player = game.player
	game.targeting.stop_attack()
	if player.pending != null and player.pending.type == "strike":
		player.pending = null
	player.pending_off = null
	player.pending_shot = null
	buffs["shadow"] = {"name": spell.name, "left": INF, "total": INF}
	# whoever was after you loses you
	for e in game.enemies.list:
		if e.alive and (e.state == "chase" or e.state == "attack" or e.state == "flee"):
			e.lose_track(spell.tuning.get("searchTime", 3.0))
	player.set_hidden(true)
	game.events.emit("log", {"text": "You slip into Shadow.", "kind": "muted"})


func break_shadow() -> void:
	if not hidden:
		return
	buffs.erase("shadow")
	shadow_grace = 0.6 # the opening blow still counts as from Shadow
	game.player.set_hidden(false)


# ------------------------------------------------------------- healing
## A heal's roll: its base (`healMin`-`healMax`) plus a share of your spell
## power (`healPower`, 1 = all of it), the same coefficients as damage
func _heal_roll(t: Dictionary) -> float:
	var lo: float = t.get("healMin", 0.0)
	var hi: float = t.get("healMax", lo)
	return lo + (hi - lo) * game.random.call() + t.get("healPower", 1.0) * game.stats.spell_power


## a heal kind that also burns enemies: any base damage above 0
static func _hurts(t: Dictionary) -> bool:
	return t.has("damageMin") and t.get("damageMax", 0) > 0


const ALLY_HEAL_RANGE := 30.0 ## metres, for a heal with no range of its own

## Who a heal goes to: your friendly target (a townsperson now, another
## player once there is multiplayer), or null for yourself. Only single-
## target heals (heal, hot) go to someone else; zones and bursts stay
## where they are cast.
func heal_target(spell: Dictionary):
	if spell.get("kind") != "heal" and spell.get("kind") != "hot":
		return null
	var f = game.targeting.friendly if game.targeting else null
	return f if f != null and f.get("position") != null else null

## Heal someone else: the number shows over them. Townsfolk keep no health
## of their own yet, so the whole heal counts.
func _heal_ally(ally, amount: float, periodic := false) -> float:
	var crit: bool = not periodic and game.random.call() * 100 < game.stats.crit_chance
	if crit:
		amount *= Stats.S().critMultiplier
	game.events.emit("damageNumber", {"target": ally, "amount": U.jround(amount), "kind": "heal", "crit": crit})
	game.events.emit("allyHealed", {"target": ally, "amount": amount})
	return amount

## Heal yourself; a direct heal can crit as a spell does, a tick never does.
## Returns what it healed (overhealing is lost).
func _heal_player(amount: float, periodic := false) -> float:
	var crit: bool = not periodic and game.random.call() * 100 < game.stats.crit_chance
	if crit:
		amount *= Stats.S().critMultiplier
	var healed: float = game.player.heal(amount)
	if healed >= 1:
		game.events.emit("damageNumber", {"target": game.player, "amount": U.jround(healed), "kind": "heal", "crit": crit})
	return healed


## what a heal over time still has to give: its ticks left at an average roll
func hot_left(id: String, b: Dictionary) -> float:
	var t: Dictionary = tuned(id).tuning
	if b.left < b.next - 1e-6:
		return 0.0
	var ticks := 1 + floori((b.left - b.next) / t.tickInterval + 1e-6)
	var avg: float = (t.get("healMin", 0.0) + t.get("healMax", t.get("healMin", 0.0))) / 2.0 + t.get("healPower", 1.0) * game.stats.spell_power
	return ticks * avg


## Thorns: every thorns buff on you hurts the enemy that struck you,
## `thornsMin`-`thornsMax` plus a share of spell power (`spellPower`, none
## unless stated). It never misses and does not start a fight.
func _thorns(enemy) -> void:
	for id in buffs.keys():
		if not buffs[id].get("thorns") or not enemy.alive:
			continue
		var spell = tuned(id)
		if spell == null:
			continue
		var t: Dictionary = spell.tuning
		var lo: float = t.get("thornsMin", 0.0)
		var base: float = lo + (t.get("thornsMax", lo) - lo) * game.random.call() + t.get("spellPower", 0.0) * game.stats.spell_power
		if base > 0:
			_damage(spell, enemy, base, "Your %s hurts the {name} for {n}." % spell.name, 1, {"stagger": 0.0, "periodic": true})


# ------------------------------------------------------------- absorbs
## A blow on you: what a shield (Light Shield) soaks up first. Returns what is left.
func absorb(amount: int) -> int:
	for id in buffs.keys():
		var b: Dictionary = buffs[id]
		if not b.get("absorb") or amount <= 0:
			continue
		var take := mini(int(b.absorb), amount)
		b.absorb -= take
		amount -= take
		if take > 0:
			reprisal = minf(reprisal_cap, reprisal + take * b.get("reprisalStore",0.0))
			game.events.emit("shieldAbsorbed", {"id":id,"amount":take,"position":game.player.position})
		if b.absorb <= 0:
			buffs.erase(id)
			game.events.emit("log", {"text": "%s breaks." % b.name, "kind": "muted"})
	return amount


func _heal_number(healed: float) -> void:
	if healed >= 1:
		game.events.emit("damageNumber", {"target": game.player, "amount": U.jround(healed), "kind": "heal"})


# ----------------------------------------------------------------- time
func update(dt: float) -> void:
	var player = game.player
	var events: Events = game.events
	var enemies: Array = game.enemies.list
	shadow_grace = maxf(0, shadow_grace - dt)
	_class_tick(dt)
	for i in range(ranged_windups.size()-1,-1,-1):
		var shot: Dictionary=ranged_windups[i]
		shot.left-=dt
		if shot.left>0:continue
		ranged_windups.remove_at(i)
		if not player.dead and shot.target != null and shot.target.alive and player.can_hit_while_moving(shot.target.position.x,shot.target.position.z) and player.position.distance_to(shot.target.position)<=game.stats.ranged_reach+shot.target.radius*0.6 and game.inventory.ammo:
			_shoot(shot.spell,shot.target)
	# the cast bar: moving or dying breaks it, as in WoW
	var c = player.casting
	if c != null:
		var gone: bool = c.target != null and not c.target.alive
		var turned: bool = c.target != null and c.target.alive and not player.can_hit_while_moving(c.target.position.x,c.target.position.z)
		var covered: bool = c.target != null and c.target.alive and game.collision.wall_between(player.position.x, player.position.z, c.target.position.x, c.target.position.z)
		if player.dead or player.moving or gone or turned or covered:
			player.casting = null
			if c.spell.kind == "groundCast":
				events.emit("zoneGone", {"key":"meteorWarning"})
			player.rig.action = null
			if c.spell.get("ranged"):
				player.hold_bow(player.weapon_stance=="ranged" and not player.sheathed)
			if not player.dead:
				events.emit("log", {"text": "Your target is gone." if gone else "Your target moved behind cover." if covered else "Interrupted.", "kind": "muted", "throttle": "interrupted"})
			events.emit("castEnd", {"id": c.id, "done": false})
		elif c.channel:
			# a channel ticks as it goes and ends when the bar runs out
			c.t += dt
			var spell: Dictionary = c.spell
			var t: Dictionary = spell.tuning
			while c.t >= c.next - 1e-6 and c.next <= c.total + 1e-6:
				c.next += game.stats.hasted(t.tickInterval)
				if not c.target.alive:
					break
				var hit := _damage(spell, c.target, _spell_base(t), "", 1, {"stagger": 0.0, "periodic": true})
				_heal_number(player.heal(hit.amount * t.healPercent / 100.0))
				if hit.amount > 0 and t.get("corruptionGain"):
					game.resources.add("corruption", t.corruptionGain)
					_show(spell,"impact",c.target.position,_facing_to(c.target))
					var distance: float = c.target.position.distance_to(player.position)
					events.emit("projectile", {"kind":"bolt", "from":c.target.position+Vector3.UP, "to":player.position, "follow":player, "speed":18.0, "life":distance/18.0, "look":spell.id})
			if c.t >= c.total:
				player.casting = null
				events.emit("castEnd", {"id": c.id, "done": true})
		else:
			c.t += dt
			if c.t >= c.total:
				player.casting = null
				var spell: Dictionary = c.spell
				var missing := missing_gear(game, spell) if spell.get("ranged") else ""
				if missing != "" or not game.resources.check(spell):
					if missing != "":
						game.hud.error(missing)
					events.emit("castEnd", {"id": c.id, "done": false})
				else:
					game.resources.spend(spell)
					var st = game.stats
					player.cooldowns[c.id] = spell.tuning.cooldown
					player.cooldowns.attack = maxf(player.cooldowns.attack, st.attack_cooldown)
					player.cooldowns.attackOff = maxf(player.cooldowns.attackOff, st.attack_cooldown_for("off"))
					if st.has_ranged:
						player.cooldowns.ranged = maxf(player.cooldowns.ranged, st.attack_cooldown_for("ranged"))
					events.emit("castEnd", {"id": c.id, "done": true})
					_go(spell, c.target)

	# cleaves and bursts land at their impact frame
	for i in range(blows.size() - 1, -1, -1):
		var b: Dictionary = blows[i]
		b.t -= dt
		if b.t > 1e-6:
			continue
		blows.remove_at(i)
		resolve(b.id, b.spell)

	# the spell queue: a spell pressed just before it was ready goes now
	if queued != null:
		queued.left -= dt
	if queued != null and player.casting == null and player.lunge == null:
		var q: Dictionary = queued
		if q.left <= 0:
			queued = null
		var wait := maxf(0.0 if DB.spells[q.id].tuning.get("offGlobalCooldown") else player.cooldowns.gcd, player.cooldowns.get(q.id, 0.0))
		if wait <= 0:
			queued = null
			try_cast(q.id)

	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		b.t -= dt
		if b.t > 0:
			continue
		bolts.remove_at(i)
		if not b.enemy.alive:
			continue
		var spell: Dictionary = b.get("spell", DB.spells[b.id])
		if spell.get("ranged"):
			_arrow_lands(spell, b.enemy, b.get("ammo"))
		else:
			_show(spell, "impact", b.enemy.position, _facing_to(b.enemy))
			var hit := _damage(spell, b.enemy, _spell_base(spell.tuning), "Your %s hits the {name} for {n}." % spell.name)
			_landed(spell, b.enemy, hit)
			if hit.amount > 0:
				_projectile_interactions(spell,b.enemy,hit)

	for id in buffs.keys():
		var b: Dictionary = buffs[id]
		b.left -= dt
		# a heal over time ticks as it goes; its last tick lands as it ends
		if b.get("hot"):
			b.next -= dt
			var hs = tuned(id)
			while b.next <= 1e-6 and hs != null:
				b.next += hs.tuning.tickInterval
				_heal_player(_heal_roll(hs.tuning), true)
		if b.left <= 1e-6:
			buffs.erase(id)
			events.emit("log", {"text": "%s fades." % b.name, "kind": "muted"})

	# heals over time on someone else
	for i in range(ally_hots.size() - 1, -1, -1):
		var h: Dictionary = ally_hots[i]
		var hs = tuned(h.id)
		h.left -= dt
		h.next -= dt
		while h.next <= 1e-6 and hs != null:
			h.next += hs.tuning.tickInterval
			_heal_ally(h.on, _heal_roll(hs.tuning), true)
		if h.left <= 1e-6 or hs == null:
			ally_hots.remove_at(i)

	# Rotheart: damage over time ticks faster while Overcorrupted
	var dot_rate := 1.0
	if game.builds:
		for e in game.builds.effects("dotHaste"):
			if not e.get("whileOverload") or game.resources.overload:
				dot_rate += e.percent / 100.0
	for i in range(dots.size() - 1, -1, -1):
		if i >= dots.size():
			continue
		var d: Dictionary = dots[i]
		var spell: Dictionary = tuned(d.id)
		if not d.enemy.alive:
			dots.remove_at(i)
			if spell.get("spreadsOnDeath"):
				var to = _spread_target(d.enemy, d.id)
				if to != null:
					_apply_dot(spell, to, d.get("ammo"), true)
					events.emit("log", {"text": "%s spreads to the %s." % [spell.name, to.cfg.name], "kind": "hit"})
			continue
		d.left -= dt
		d.next -= dt * dot_rate
		if d.next <= 1e-6:
			var t: Dictionary = spell.tuning
			d.next += t.tickInterval
			var base: float
			if spell.get("ranged"):
				base = _bow_roll(d.get("ammo")) + _gear_extra(t, 1.0)
			elif t.has("damageMin"):
				base = _spell_base(t)
			else:
				base = Stats.weapon_roll(game.random, game.stats) + _gear_extra(t, 1.0)
			var hit := _damage(spell, d.enemy, base, "", t.tickMultiplier * d.get("strength",1.0), {"stagger": 0.0,"periodic":true}, d)
			events.emit("dotTick", {"id": d.id, "damage": hit.amount})
			if d.id == "rot" and hit.amount > 0:
				var targets := dots.filter(func(dot): return dot.id == "rot" and dot.enemy.alive).size()
				game.resources.add("corruption", t.corruptionGain / sqrt(maxi(1, targets)))
			# Leech: a share of every tick heals you
			var leech: float = trait_.get("dotHealPercent", 0) if trait_.get("id") == "leech" else 0.0
			if leech and hit.amount > 0:
				_heal_number(player.heal(hit.amount * leech / 100.0))
		if d.left <= 1e-6:
			dots.erase(d)

	# auras on enemies: they wear off (a sleep ends when the sleeper wakes),
	# and some hand over to the next (Bring to Kneel: slowed, then stunned)
	for i in range(auras.size() - 1, -1, -1):
		var a: Dictionary = auras[i]
		a.left -= dt
		var woke: bool = a.sleep and not a.enemy.asleep
		if not a.enemy.alive and a.get("spreads"):
			var to = _spread_target(a.enemy, a.id)
			if to != null:
				apply_aura(a.id, to, a.aura, true)
		if not a.enemy.alive or woke or a.left <= 1e-6:
			auras.remove_at(i)
			if a.then and a.enemy.alive and not woke:
				apply_aura(a.id + ":then", a.enemy, a.then)

	# traps arm, wait, and spring on the first enemy to step on one
	for i in range(traps.size() - 1, -1, -1):
		var tr: Dictionary = traps[i]
		var spell: Dictionary = tuned(tr.id)
		var t: Dictionary = spell.tuning
		tr.arm -= dt
		tr.left -= dt
		var prey = null
		if tr.arm <= 0:
			for e in enemies:
				if e.alive and not e.protected and U.hyp(e.position.x - tr.x, e.position.z - tr.z) - e.radius * 0.5 <= t.triggerRadius:
					prey = e
					break
		if prey != null or tr.left <= 0:
			traps.remove_at(i)
			events.emit("trapGone", {"key": tr.key})
		if prey != null:
			if spell.get("mechanic") == "tripwire":
				apply_aura(tr.id,prey,{"name":"Tripped","duration":t.duration,"root":1})
				_show(spell,"impact",prey.position,_facing_to(prey))
				continue
			zones.append({"id": tr.id, "key":tr.key, "x": tr.x, "z": tr.z, "left": t.duration, "next": INF, "radius": t.radius, "slow": t.slow, "damage": false})
			events.emit("zone", {"id": tr.id, "x": tr.x, "z": tr.z, "radius": t.radius, "duration": t.duration, "school": "tar", "key":tr.key})
			events.emit("log", {"text": "The %s springs your %s." % [prey.cfg.name, spell.name], "kind": "hit"})
			_show(spell, "impact", Vector3(tr.x, Terrain.height_at(tr.x, tr.z), tr.z), game.player.facing)
			for e in (game.builds.effects("trap") if game.builds else []):
				if e.get("applies"):
					apply_aura(tr.id + ":snare", prey, e.applies)

	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		var spell: Dictionary = tuned(z.id)
		var t: Dictionary = spell.tuning
		z.left -= dt
		z.next -= dt
		if z.next <= 1e-6:
			z.next += t.tickInterval
			var spread = DB.spells.get(spell.get("spreads", ""))
			for e in enemies:
				if not e.alive or U.hyp(e.position.x - z.x, e.position.z - z.z) - e.radius * 0.5 > z.radius:
					continue
				if z.damage:
					_damage(spell, e, _spell_base(t), "", 1, {"stagger": 0.0, "periodic": true})
				if spread != null and e.alive and _find_dot(e, spread.id).is_empty():
					_apply_dot(spread, e)
			# Hallowed Ground heals you while you stand in it
			var inside: bool = U.hyp(player.position.x - z.x, player.position.z - z.z) <= z.radius
			if t.get("healPercent") and inside:
				_heal_number(player.heal(player.max_health * t.healPercent / 100.0))
			# a healing zone (Healing Grove) heals its roll every tick
			if z.get("heal") and inside:
				_heal_player(_heal_roll(t), true)
			# Bulwark: Fortified while you stand in it
			for e in (game.builds.effects("zoneFortify") if game.builds and inside else []):
				if e.spell == z.id:
					buffs["fortified"] = {"name": "Fortified", "icon": z.id, "left": t.tickInterval + 0.25, "total": t.tickInterval + 0.25, "reduction": e.percent}
		if z.left <= 1e-6:
			zones.erase(z)

	# what your auras and zones do to enemies this frame: slows, damage taken and dealt
	for e in enemies:
		e.mods = {"slow": 0.0, "taken": 1.0, "dealt": 1.0}
	for a in auras:
		var m: Dictionary = a.enemy.mods
		m.slow = maxf(m.slow, a.slow)
		m.taken *= 1 + a.damageTaken / 100.0
		m.dealt *= 1 + a.damageDealt / 100.0
	for z in zones:
		if not z.slow:
			continue
		for e in enemies:
			if e.alive and U.hyp(e.position.x - z.x, e.position.z - z.z) - e.radius * 0.5 <= z.radius:
				e.mods.slow = maxf(e.mods.slow, z.slow)


# Class interactions share the normal spell resolution and damage paths.
var reprisal := 0.0
var reprisal_cap := 14.0
var mobile := {}
var echoes: Array = []

var movement_scale: float:
	get:
		return mobile.get("spell", {}).get("tuning", {}).get("movementScale", 1.0)


func _class_ready(spell: Dictionary, target) -> bool:
	var reason := ""
	match spell.get("mechanic", ""):
		"berserk":
			if game.resources.amount("resolve") < 100 and not game.resources.unlimited:
				reason = "Berserk needs full Fury."
		"venom", "reap":
			var dot_id := "poisonedBladeToxin" if spell.mechanic == "venom" else "rot"
			if _find_dot(target, dot_id).is_empty():
				reason = "Your poison must already be on the target." if dot_id == "poisonedBladeToxin" else "The target needs your Rot."
		"distract":
			if target == null or target.state != "idle" or target.engaged > 0:
				reason = "Distract needs an unaware enemy."
		"fear":
			if not _ordinary(target):
				reason = "That enemy cannot be frightened."
		"collapseWard":
			if buffs.get("arcaneWard", {}).get("absorb", 0) <= 0:
				reason = "Raise Arcane Ward first."
		"bloodPact":
			if game.player.health <= 1 + game.player.max_health * spell.tuning.healthCost / 100.0:
				reason = "You are too wounded for Blood Pact."
	if reason != "":
		game.hud.error(reason)
	return reason == ""


func _ordinary(enemy) -> bool:
	return enemy != null and enemy.alive and not enemy.protected and not enemy.is_elite and enemy.stagger_bar == null and not enemy.cfg.get("dummy", false)


func _prepare_class_cast(spell: Dictionary, points: float) -> Dictionary:
	var mechanic: String = spell.get("mechanic", "")
	if mechanic == "conviction" or mechanic == "soulWard":
		spell = spell.duplicate(true)
		if spell.kind == "shield":
			spell.tuning.absorbPercent += spell.tuning.perCharge * points
		else:
			spell["classMultiplier"] = 1.0 + spell.tuning.perCharge * points + spell.tuning.reprisalBonus * reprisal / reprisal_cap
			spell["fullReprisal"] = reprisal >= reprisal_cap
			reprisal = 0.0
	elif mechanic == "collapseWard":
		spell = spell.duplicate()
		spell["wardDamage"] = buffs.arcaneWard.absorb * spell.tuning.wardScale
		buffs.erase("arcaneWard")
	if spell.id in ["flurry", "crosscut"]:
		buffs.erase("twinOpening")
	return spell


func _class_release(spell: Dictionary, target) -> bool:
	var t: Dictionary = spell.tuning
	var player = game.player
	match spell.get("mechanic", ""):
		"pair":
			_anim(spell, "strike", 0.5, 0.35)
			var landed := 0
			for hand in ["main", "off"]:
				if not target.alive:
					break
				var hit := _damage(spell, target, Stats.swing_roll(game.random, game.stats, hand), "", t.damageMultiplier, {"hand": hand})
				if hit.amount > 0:
					landed += 1
					_show(spell, "impact", target.position, _facing_to(target) + (0.35 if hand == "off" else -0.35))
			if landed == 2 and t.has("comboDiscount"):
				buffs["twinOpening"] = {"name":"Twin Opening", "icon":spell.id, "left":6.0, "total":6.0, "discount":t.comboDiscount}
		"mobile":
			mobile = {"spell":spell, "next":0.0, "pulse":0}
			_anim(spell, "sweep", t.tickInterval, 0.35)
		"berserk":
			buffs[spell.id] = {"name":spell.name,"icon":spell.id,"left":t.duration,"total":t.maxDuration,"damageBonus":t.damageBonus,"age":0.0}
			_anim(spell, "brace", 0.65, 0.4)
			game.events.emit("buff", {"id":spell.id})
		"venom":
			var poison := _find_dot(target, "poisonedBladeToxin")
			if not poison.is_empty():
				poison["strength"] = 1.0 + t.venomPerPoint * spell.points
				poison.left += t.extend
				_show(spell, "impact", target.position, _facing_to(target))
			_anim(spell, "strike", 0.4, 0.4)
		"reap":
			_anim(spell, "cast", 0.45, 0.4)
			_cash_out(spell, target)
		"distract":
			var at := _ground_point(spell.range)
			target.distract_at(at)
			_anim(spell, "brace", 0.35, 0.4)
			_show(spell, "impact", target.position, 0.0)
		"fear":
			target.frighten(t.get("fearTime", 3.0))
			_anim(spell, "cast", 0.5, 0.4)
			_show(spell, "impact", target.position, _facing_to(target))
		"bloodPact":
			player.health -= player.max_health * t.healthCost / 100.0
			buffs[spell.id] = {"name":spell.name,"icon":spell.id,"left":t.duration,"total":t.duration,"drainBonus":t.drainBonus}
			_anim(spell, "brace", 0.55, 0.4)
		"blink":
			var start: Vector3 = player.position
			var at := _ground_point(t.distance)
			var direction := Vector3(at.x - start.x, 0, at.z - start.z)
			var landing := start
			for i in range(1, 25):
				var step := start + direction * float(i) / 24.0
				if Terrain.walk_at(step.x, step.z) < 0.5 or game.collision.wall_between(landing.x, landing.z, step.x, step.z):
					break
				if game.collision.resolve(step, player.radius).distance_to(step) > 0.15:
					break
				landing = step
			player.place_at(landing.x, landing.z, player.facing)
			game.move_to = null
			_anim(spell, "brace", 0.35, 0.45)
			_show(spell, "impact", player.position, player.facing)
		"sigil":
			var at := _ground_point(spell.range)
			buffs[spell.id] = {"name":spell.name,"icon":spell.id,"left":t.duration,"total":t.duration,"at":at,"radius":t.radius,"scale":t.echoScale}
			game.events.emit("zone", {"id":spell.id,"x":at.x,"z":at.z,"radius":t.radius,"duration":t.duration,"school":"arcane"})
			_anim(spell, "cast", 0.5, 0.4)
		_:
			return false
	return true


func _class_tick(dt: float) -> void:
	if game.player.dead:
		mobile.clear()
		echoes.clear()
		return
	if buffs.has("berserk"):
		var b: Dictionary = buffs.berserk
		b.age += dt
		game.resources._take("resolve", DB.spells.berserk.tuning.drain * dt)
		if b.age >= b.total or game.resources.amount("resolve") <= 0:
			buffs.erase("berserk")
	if not mobile.is_empty():
		mobile.next -= dt
		if mobile.next <= 0:
			_mobile_pulse()
	for i in range(echoes.size() - 1, -1, -1):
		var wave: Dictionary = echoes[i]
		wave.left -= dt
		if wave.left > 0:
			continue
		echoes.remove_at(i)
		if wave.get("radius", 0.0) > 0:
			game.events.emit("classImpact", {"position":wave.at,"radius":wave.radius,"school":wave.school})
		for record in wave.hits:
			if record.enemy.alive and not record.enemy.protected:
				_echo_hit(wave, record)


func _mobile_pulse() -> void:
	var spell: Dictionary = mobile.spell
	var t: Dictionary = spell.tuning
	var pulse: int = mobile.pulse
	var cost: float = t.get("pulseCost", 0.0)
	if missing_gear(game, spell) != "" or (pulse > 0 and game.resources.amount("resolve") < cost and not game.resources.unlimited):
		mobile.clear()
		return
	if pulse > 0 and cost and not game.resources.unlimited:
		game.resources._take("resolve", cost)
	var player = game.player
	var hand := "off" if spell.id == "flurry" and pulse % 2 else "main"
	var near := _near_enemies(player.position, t.radius)
	if spell.id == "flurry":
		var target = game.targeting.current
		near = [target] if target != null and near.has(target) else near.slice(0, 1)
	_anim(spell, "sweep" if spell.id == "whirlwind" else "strike", t.tickInterval, 0.4)
	if hand == "off":
		player.rig.play_off(t.tickInterval, 0.4)
	if player.rig.action != null:
		player.rig.action["trailHand"] = hand
	for enemy in near:
		_damage(spell, enemy, Stats.swing_roll(game.random, game.stats, hand), "", t.damageMultiplier, {"hand":hand})
		_show(spell, "impact", enemy.position, _facing_to(enemy) + (0.35 if hand == "off" else -0.35))
	if spell.id == "whirlwind":
		game.events.emit("classImpact", {"position":player.position,"radius":t.radius,"school":"physical"})
	mobile.pulse += 1
	mobile.next += t.tickInterval
	if mobile.pulse >= int(t.pulses):
		mobile.clear()


func _find_dot(enemy, id: String) -> Dictionary:
	for d in dots:
		if d.enemy == enemy and d.id == id:
			return d
	return {}


func _dot_remaining(dot: Dictionary) -> float:
	var spell: Dictionary = tuned(dot.id)
	var t: Dictionary = spell.tuning
	var count := maxi(0, 1 + floori((dot.left - dot.next) / t.tickInterval + 0.0001))
	var base: float
	if t.has("damageMin"):
		base = (t.damageMin + t.get("damageMax",t.damageMin)) * 0.5 + t.get("spellPower",1.0) * game.stats.spell_power
	else:
		base = game.stats.ability_average()
	return count * base * t.tickMultiplier * dot.get("strength",1.0) * _class_damage_scale(spell)


func poison_remaining(enemy) -> float:
	var dot := _find_dot(enemy, "poisonedBladeToxin")
	return _dot_remaining(dot) if not dot.is_empty() else 0.0


func _cash_out(spell: Dictionary, enemy) -> void:
	var dot := _find_dot(enemy, "rot")
	if dot.is_empty() or not enemy.alive:
		return
	var amount := minf(spell.tuning.cashoutCap, _dot_remaining(dot) * spell.tuning.cashoutScale)
	dots.erase(dot)
	if amount > 0:
		_damage(spell, enemy, amount, "", 1.0, {"periodic":true})
		_show(spell, "impact", enemy.position, _facing_to(enemy))


func _class_damage_scale(spell: Dictionary) -> float:
	if spell.get("mechanic", "") not in ["rot", "drain"]:
		return 1.0
	var corruption: float = game.resources.amount("corruption")
	var pact: float = buffs.get("bloodPact", {}).get("drainBonus",0.0) if spell.mechanic == "drain" else 0.0
	return (1.0 + corruption * 0.0035) * (1.0 + pact / 100.0)


func _near_enemies(at: Vector3, radius: float) -> Array:
	return game.enemies.list.filter(func(e): return e.alive and not e.protected and U.hyp(e.position.x - at.x, e.position.z - at.z) <= radius + e.radius * 0.5)


func _ignite_tar(enemy) -> bool:
	for z in zones:
		if z.id != "tarTrap" or U.hyp(enemy.position.x-z.x,enemy.position.z-z.z) > z.radius:
			continue
		z.id = "burningTar"
		z.slow = 0.0
		z.damage = true
		z.next = 0.0
		game.events.emit("zoneGone", {"key":z.get("key", "")})
		game.events.emit("zone", {"id":z.id,"x":z.x,"z":z.z,"radius":z.radius,"duration":z.left,"school":"fire"})
		game.events.emit("tarIgnited", {"position":Vector3(z.x,Terrain.height_at(z.x,z.z),z.z)})
		return true
	return false


func smoke_blocks(from: Vector3, to: Vector3) -> bool:
	var a := Vector2(from.x,from.z)
	var b := Vector2(to.x,to.z)
	for z in zones:
		if z.id == "smokeBomb":
			var centre := Vector2(z.x,z.z)
			if centre.distance_to(Geometry2D.get_closest_point_to_segment(centre,a,b)) <= z.radius:
				return true
	return false


func _schedule_holy_echoes(spell: Dictionary, hits: Array) -> void:
	if spell.get("points",0.0) < 3 or hits.is_empty():
		return
	var chance := 0.50 if spell.get("fullReprisal",false) else 0.25
	var at: Vector3 = game.player.position
	for i in range(1,4):
		if game.random.call() >= chance:
			break
		echoes.append({"spell":spell,"hits":hits,"left":0.35*i,"scale":0.35,"school":"holy","at":at,"radius":spell.tuning.get("radius",0.0)})


func _echo_hit(wave: Dictionary, record: Dictionary) -> void:
	var enemy = record.enemy
	var amount := maxi(1,roundi(record.amount * wave.scale))
	enemy.hurt(amount, {"stagger":0.0,"periodic":true})
	game.events.emit("damageNumber", {"target":enemy,"amount":amount,"crit":record.crit,"kind":"dealt","ability":true})
	game.events.emit("enemyHit", {"enemy":enemy,"damage":amount,"crit":record.crit,"kind":"spell","school":wave.school,"echo":true})
	if wave.get("radius",0.0) == 0:
		_show(wave.spell, "impact", enemy.position, _facing_to(enemy))
	if enemy.dead:
		game.combat.on_enemy_defeated(enemy)



func _projectile_interactions(spell: Dictionary, enemy, hit: Dictionary) -> void:
	var t: Dictionary = spell.tuning
	var mechanic: String = spell.get("mechanic", "")
	if mechanic == "steam":
		for a in auras:
			if a.enemy != enemy or a.id != "frostLance":
				continue
			auras.erase(a)
			for nearby in _near_enemies(enemy.position,2.5):
				_damage(spell,nearby,2.0+game.stats.spell_power*0.3,"",1.0,{"periodic":true})
			game.events.emit("classImpact", {"position":enemy.position,"radius":2.5,"school":"steam"})
			break
	elif mechanic == "chain":
		var visited := [enemy]
		var from = enemy
		for jump in range(1,int(t.maxTargets)):
			var near := _near_enemies(from.position,t.spread).filter(func(other): return not visited.has(other))
			if near.is_empty():
				break
			near.sort_custom(func(a,b): return a.position.distance_squared_to(from.position) < b.position.distance_squared_to(from.position))
			var to = near[0]
			visited.append(to)
			game.events.emit("projectile", {"kind":"bolt","from":from.position+Vector3.UP,"to":to.position,"follow":to,"speed":37.0,"life":0.12,"look":spell.id})
			_damage(spell,to,_spell_base(t),"",pow(t.jumpScale,jump),{"periodic":true})
			_show(spell,"impact",to.position,_facing_to(to))
			from = to
	var sigil: Dictionary = spell.get("sigilEcho", {})
	if not sigil.is_empty() and enemy.alive:
		var player = game.player
		game.events.emit("projectile", {"kind":"bolt", "from":player.position+Vector3.UP, "to":enemy.position, "follow":enemy, "speed":30.0, "life":0.32, "look":spell.id})
		echoes.append({"spell":spell,"hits":[{"enemy":enemy,"amount":hit.amount,"crit":hit.crit}],"left":0.32,"scale":sigil.scale,"school":spell.school,"at":sigil.at,"radius":0.0})
