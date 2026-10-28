class_name Spells
extends RefCounted
## The spell engine (src/systems/spells.js). Abilities in data/abilities.json
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
var traps: Array = [] ## { id, key, x, z, arm, left }
var bolts: Array = [] ## { enemy, id, t, ammo, spell }
var blows: Array = [] ## cleaves and bursts on their way to the impact frame
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
		var c = game.player.casting if game.player else null
		if c == null or c.channel or not (e.damage > 0) or c.pushbacks >= DB.max_pushbacks:
			return
		c.t = maxf(0, c.t - DB.cast_pushback)
		c.pushbacks += 1
		game.events.emit("castPushback", {"id": c.id}))
	# any blow you deal brings you out of Shadow
	game.events.on("enemyHit", func(_e): break_shadow())
	game.events.on("autoAttack", func(e):
		if e.on:
			break_shadow())


func reset() -> void:
	buffs = {}
	dots = []
	auras = []
	zones = []
	traps = []
	bolts = []
	blows = []
	queued = null
	shadow_grace = 0.0


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
	return spell


# ------------------------------------------------------------ status tags
## Does `enemy` carry a status (data/builds.json `statuses`)? Damage over
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
## The spell's own cast pose (data/spell_fx.json `anim`), else the kind's
## `type`. `keep_timing`: a blow that lands on its own clock (a sweep, a
## burst, a charge) takes only the pose, so blow and pose stay together.
## `key` "windupAnim" takes the look's `windupAnim` pose (the held part of a cast)
## when it has one.
func _anim(spell: Dictionary, type: String, duration: float, impact: float, keep_timing := false, key := "anim") -> void:
	var look: Dictionary = DB.spell_fx.get(spell.id, {})
	var a = look.get(key, look.get("anim"))
	if a == null:
		game.player.rig.play(type, duration, impact)
		return
	if not keep_timing:
		var d = a.get("duration", duration)
		duration = spell.tuning.get(d, duration) if typeof(d) == TYPE_STRING else d
		impact = a.get("impact", impact)
	game.player.rig.play(a.type, duration, impact)


## The spell's own effects (data/spell_fx.json): `windup` on you while a
## cast is drawn out, `cast` on you as it goes, `impact` where it lands.
func _show(spell: Dictionary, phase: String, at: Vector3, facing: float, follow = null) -> void:
	if DB.spell_fx.has(spell.id):
		game.events.emit("spellFx", {"id": spell.id, "phase": phase, "position": at, "facing": facing, "follow": follow, "tuning": spell.tuning})


## facing from you to an enemy
func _facing_to(enemy) -> float:
	var p: Vector3 = game.player.position
	return atan2(enemy.position.x - p.x, enemy.position.z - p.z)


func _cast_effects(spell: Dictionary) -> void:
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
	var player = game.player
	var events: Events = game.events
	var stats = game.stats
	# Nothing about auto attack blocks an ability: only another cast, a
	# charge in flight, or the global cooldown does.
	if not DB.spells.has(id) or player.dead or player.lunge != null or player.casting != null:
		return false
	if not game.skills.knows_ability(id):
		return false
	var spell: Dictionary = tuned(id)
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
		if wait <= DB.spell_queue_window:
			queued = {"id": id, "left": wait + 0.05}
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
	var casts: bool = spell.kind == "cast" or spell.kind == "camp" or spell.kind == "portal" or spell.kind == "channel"
	if casts and player.moving:
		game.hud.error("You can't do that while moving")
		return false
	var missing := missing_gear(game, spell)
	if missing != "":
		game.hud.error(missing)
		return false
	if not game.resources.check(spell):
		return false
	var target = null
	if spell.kind == "charge":
		# a charge only ever goes at an enemy, never away from one
		target = _target_for(spell)
		if not target:
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
		# a spell at an enemy turns you to it (Diablo): facing never blocks a cast
		player.face_towards(target.position.x, target.position.z)
		# striking from Shadow: the blow still counts as from Shadow (Opportunist)
		break_shadow()
		# a spell at an enemy engages it (not Sleep: a swing would wake it)
		if not spell.get("applies", {}).get("sleep"):
			game.targeting.engage(target)
		elif game.targeting.current == target:
			game.targeting.stop_attack()
	if not off_gcd:
		player.cooldowns.gcd = stats.global_cooldown
	# a cast pays when it finishes (WoW); everything else pays now
	if spell.kind != "cast" and spell.kind != "camp" and spell.kind != "portal":
		var points: float = game.resources.spend(spell)
		if spell.get("spendsAll"):
			spell = spell.duplicate()
			spell.points = points
			spell.tuning = t.duplicate()
			spell.tuning.damageMultiplier = t.get("damageMultiplier", 0) + t.get("perPoint", 0) * points
			t = spell.tuning
	if casts:
		# casting stops the swing: a swing or shot on its way is dropped, and
		# the timers start again when the cast ends (WoW Classic)
		if player.pending != null and player.pending.type == "strike":
			player.pending = null
		player.pending_off = null
		player.pending_shot = null
		player.hold_bow(spell.get("ranged", false))
		var channel: bool = spell.kind == "channel"
		player.casting = {"id": id, "spell": spell, "t": 0.0, "total": stats.hasted(t.castTime), "target": target, "pushbacks": 0, "channel": channel, "next": t.tickInterval if channel else 0.0}
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
	var range_: float = game.stats.ranged_reach if spell.get("ranged") else spell.range
	var in_range := func(e): return e != null and e.alive and U.hyp(e.position.x - player.position.x, e.position.z - player.position.z) <= range_ + e.radius * 0.6
	var cur = targeting.current
	if cur != null and cur.alive:
		# livestock and the watch: only with the crime key held (Alt)
		if not game.law.may_attack(cur):
			return false if optional else null
		if in_range.call(cur):
			return cur
		game.hud.error("Out of range")
		return false if optional else null
	var soft = targeting.soft_target(game.raw_aim if game.raw_aim != null else player.position, range_)
	if in_range.call(soft):
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
		_shoot(spell, target)
		return
	# kinds with no pose of their own take a look's pose
	if spell.kind in ["stealth", "purge"] and DB.spell_fx.get(spell.id, {}).has("anim"):
		_anim(spell, "brace", 0.5, 0.4)
	match spell.kind:
		"cast":
			var d := U.hyp(target.position.x - player.position.x, target.position.z - player.position.z)
			bolts.append({"enemy": target, "id": spell.id, "t": d / t.projectileSpeed})
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
				d.left += t.extend
			for a in auras:
				if not a.stun and not a.sleep:
					a.left += t.extend
			if healed >= 1:
				events.emit("damageNumber", {"target": player, "amount": U.jround(healed), "kind": "heal"})
			events.emit("buff", {"id": spell.id})
			events.emit("log", {"text": "You purge %d Corruption and heal %d." % [U.jround(points), U.jround(healed)], "kind": "hit"})
		"shield":
			_anim(spell, "brace", 0.5, 0.4)
			var absorb := U.jround(player.max_health * t.absorbPercent / 100.0)
			buffs[spell.id] = {"name": spell.name, "left": t.duration, "total": t.duration, "absorb": absorb}
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
		base += Stats.weapon_roll(game.random, stats) * DB.CONFIG.stats.offHandDamage
	return base


func _bonus_vs(spell: Dictionary, enemy) -> float:
	var bv = spell.get("bonusVs")
	if not bv:
		return 1.0
	var has: bool = has_status(enemy, bv.status) if bv.has("status") else has_aura(enemy, bv.get("aura", ""))
	return 1 + bv.percent / 100.0 if has else 1.0


## what follows a spell's hit on its target: its aura, a follow-up effect,
## and the stacks it gives you
func _landed(spell: Dictionary, enemy, hit) -> void:
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
	else:
		dots.append({"enemy": target, "id": spell.id, "left": t.duration, "next": t.tickInterval, "ammo": ammo})
	if spell.get("applies"):
		apply_aura(spell.id, target, spell.applies)
	if quiet:
		return
	target.hurt(0, {"stagger": 0.1}) # they notice
	game.events.emit("enemyHit", {"enemy": target, "damage": 0, "kind": "strike"})
	var text := "%s refreshed on the %s." % [spell.name, target.cfg.name] if had != null else "The %s is afflicted by %s." % [target.cfg.name, spell.name]
	game.events.emit("log", {"text": text, "kind": "hit"})


## A bow ability: the bow comes to hand, one arrow is loosed, and the
## spell's effect lands when it arrives. Triple Shot looses more arrows at
## enemies near the target.
func _shoot(spell: Dictionary, target) -> void:
	var player = game.player
	var inventory = game.inventory
	var ammo = inventory.ammo
	if ammo:
		inventory.remove_count(ammo, 1)
	player.pending_shot = null
	player.hold_bow(true)
	_anim(spell, "shoot", 0.45, 0.25)
	var from := Vector3(player.position.x + sin(player.facing) * 0.4, player.position.y + 1.35, player.position.z + cos(player.facing) * 0.4)
	var speed: float = DB.auto_shot.arrowSpeed
	var t: Dictionary = spell.tuning
	var targets := [target]
	if t.get("maxTargets", 1) > 1:
		var dist := func(e): return U.hyp(e.position.x - target.position.x, e.position.z - target.position.z)
		var near: Array = game.enemies.list.filter(func(e): return e.alive and not e.protected and e != target and dist.call(e) <= t.spread)
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
		_apply_dot(spell, enemy, ammo)
		return
	var hit := _damage(spell, enemy, _bow_roll(ammo), "Your %s hits the {name} for {n}." % spell.name, spell.tuning.damageMultiplier, {"stagger": 0.15, "knockFrom": game.player.position, "knockback": 0.1})
	_landed(spell, enemy, hit)


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
	for e in hits:
		var hit := _damage(spell, e, _weapon_base(t), "", t.damageMultiplier, {"stagger": t.stagger, "knockFrom": player.position, "knockback": t.knockback, "heavy": bool(t.get("interrupts", false))})
		most = maxi(most, hit.amount)
		_landed(spell, e, hit)
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
	player.face_towards(best.position.x, best.position.z)
	targeting.engage(best)
	var hit := _damage(spell, best, Stats.weapon_roll(game.random, game.stats), "", t.damageMultiplier, {"stagger": 0.3, "knockFrom": player.position, "knockback": 0.4})
	_show(spell, "impact", best.position, player.facing)
	game.events.emit("log", {"text": "You %s into the %s for %d.%s" % [spell.name.to_lower(), best.cfg.name, hit.amount, " A critical blow!" if hit.crit else ""], "kind": "hit"})
	_landed(spell, best, hit)
	return [best]


func _spell_base(t: Dictionary) -> float:
	return (t.damageMin + (t.damageMax - t.damageMin) * game.random.call()) * game.stats.spell_scale + game.stats.spell_power


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
	mult *= _execute_scale(spell, enemy)
	var school: String = spell.get("school", "physical")
	if carry == null and not hurt_opts.get("periodic", false) and Stats.rolls_miss(game.random, game.stats.stat_block, Stats.enemy_block(enemy.cfg), m.accuracy):
		var miss: Dictionary = game.combat.missed(enemy, "Your %s misses" % spell.name)
		if spell.kind != "dot" and not game.targeting.attacking:
			game.targeting.engage(enemy)
		return miss
	var o := {"base": base, "mult": mult * m.mult * damage_scale * game.afterlife.damage_scale_against(enemy), "school": school, "critBonus": m.critBonus, "forceCrit": m.forceCrit}
	if carry != null:
		o.carry = carry.get("carry", 0.0)
	var hit := Stats.compute_hit(game.random, game.stats.stat_block, Stats.enemy_block(enemy.cfg), o)
	if carry != null:
		carry.carry = hit.carry
		if hit.amount <= 0:
			return hit
	after_hit(hit)
	enemy.hurt(hit.amount, hurt_opts)
	var events: Events = game.events
	events.emit("damageNumber", {"target": enemy, "amount": hit.amount, "crit": hit.crit, "kind": "dealt", "hand": "ranged" if spell.get("ranged") else "main"})
	events.emit("enemyHit", {"enemy": enemy, "damage": hit.amount, "crit": hit.crit, "kind": "strike" if school == "physical" else "spell"})
	events.emit("hitImpact", {"enemy": enemy, "crit": hit.crit, "heavy": hurt_opts.get("knockback", 0) > 0})
	if line != "":
		events.emit("log", {"text": line.replace("{name}", enemy.cfg.name).replace("{n}", str(hit.amount)) + (" A critical blow!" if hit.crit else ""), "kind": "hit"})
	if enemy.dead:
		game.combat.on_enemy_defeated(enemy)
	# hitting an enemy with nothing engaged starts auto attack on it
	elif spell.kind != "dot" and not game.targeting.attacking:
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
		if e.alive and (e.state == "chase" or e.state == "attack"):
			e.lose_track()
	player.set_hidden(true)
	game.events.emit("log", {"text": "You slip into Shadow.", "kind": "muted"})


func break_shadow() -> void:
	if not hidden:
		return
	buffs.erase("shadow")
	shadow_grace = 0.6 # the opening blow still counts as from Shadow
	game.player.set_hidden(false)


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
	# the cast bar: moving or dying breaks it, as in WoW
	var c = player.casting
	if c != null:
		var gone: bool = c.target != null and not c.target.alive
		if player.dead or player.moving or gone:
			player.casting = null
			player.rig.action = null
			if c.spell.get("ranged"):
				player.hold_bow(false)
			if not player.dead:
				events.emit("log", {"text": "Your target is gone." if gone else "Interrupted.", "kind": "muted", "throttle": "interrupted"})
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
					# it lands facing its target, wherever you turned meanwhile
					if c.target != null:
						player.face_towards(c.target.position.x, c.target.position.z)
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
	if queued != null and player.casting == null and player.lunge == null:
		var q: Dictionary = queued
		q.left -= dt
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
			_landed(spell, b.enemy, _damage(spell, b.enemy, _spell_base(spell.tuning), "Your %s hits the {name} for {n}." % spell.name))

	for id in buffs.keys():
		var b: Dictionary = buffs[id]
		b.left -= dt
		if b.left <= 0:
			buffs.erase(id)
			events.emit("log", {"text": "%s fades." % b.name, "kind": "muted"})

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
				base = _bow_roll(d.get("ammo"))
			elif t.has("damageMin"):
				base = _spell_base(t)
			else:
				base = Stats.weapon_roll(game.random, game.stats)
			var hit := _damage(spell, d.enemy, base, "", t.tickMultiplier, {"stagger": 0.0}, d)
			events.emit("dotTick", {"id": d.id, "damage": hit.amount})
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
				if e.alive and U.hyp(e.position.x - tr.x, e.position.z - tr.z) - e.radius * 0.5 <= t.triggerRadius:
					prey = e
					break
		if prey != null or tr.left <= 0:
			traps.remove_at(i)
			events.emit("trapGone", {"key": tr.key})
		if prey != null:
			zones.append({"id": tr.id, "x": tr.x, "z": tr.z, "left": t.duration, "next": INF, "radius": t.radius, "slow": t.slow, "damage": false})
			events.emit("zone", {"id": tr.id, "x": tr.x, "z": tr.z, "radius": t.radius, "duration": t.duration, "school": "tar"})
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
				if spread != null and e.alive:
					_apply_dot(spread, e, null, dots.any(func(d): return d.enemy == e and d.id == spread.id))
			# Hallowed Ground heals you while you stand in it
			var inside: bool = U.hyp(player.position.x - z.x, player.position.z - z.z) <= z.radius
			if t.get("healPercent") and inside:
				_heal_number(player.heal(player.max_health * t.healPercent / 100.0))
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
