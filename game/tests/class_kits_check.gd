extends SceneTree
## Runs every class ability through casting, then checks the interactions
## that cannot be covered by the content/schema validator.

var game
var foes := []
var failed := 0
var checks := 0
var damage := []
var impacts := []
var original_enemies := []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL ", message)


func _run() -> void:
	Store.dir = "user://class_kits_check_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made: Dictionary = game.roster.create("Kitcheck", "wizard")
	check(made.ok, "Wizard can be created from the real roster")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:
		await process_frame
	game.save.autosave_enabled = false
	game.set_process(false)
	game.random = func() -> float: return 0.5
	for enemy in game.enemies.list:
		if not enemy.protected and not enemy.cfg.get("dummy", false):
			foes.append(enemy)
		if foes.size() == 3:
			break
	check(foes.size() == 3, "World supplies three ordinary enemies")
	original_enemies = game.enemies.list
	game.enemies.list = foes
	game.events.on("enemyHit", func(e): damage.append(e))
	game.events.on("spellFx", func(e): impacts.append(e))
	for sex in ["male", "female"]:
		var look := ForgeCharacter.defaults()
		look.sex = sex
		game.player.set_appearance(look)
		for id in DB.archetypes:
			_select_class(id)
			_structure(id)
			for ability in game.stats.archetype.abilities:
				_cast_ability(id, ability)
	_warrior()
	_paladin()
	_rogue()
	_ranger()
	_occultist()
	_wizard()
	_legacy_and_swaps()
	print("class_kits_check: %d checks, %d failures" % [checks, failed])
	game.spells.reset()
	game.fx.update(1000)
	game.enemies.list = original_enemies
	game.enemies.clear()
	damage.clear()
	impacts.clear()
	foes.clear()
	original_enemies = []
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)


func _select_class(id: String) -> void:
	game.progression.level = 10
	game.archetype_id = id
	game.skills.reset()
	game.builds.reset()
	game.inventory.reset()
	game.resources.reset()
	game.spells.reset()
	game.player.casting = null
	game.player.lunge = null
	game.player.pending = null
	game.player.pending_off = null
	game.player.pending_shot = null
	game.player.health = game.player.max_health
	game.player.moving = false
	game.targeting.stop_attack()
	game.action_bar.reset()
	_ready_cast()


func _ready_cast() -> void:
	for key in game.player.cooldowns:
		game.player.cooldowns[key] = 0.0
	game.player.casting = null
	game.player.lunge = null
	game.spells.queued = null
	game.spells.mobile.clear()
	game.resources.since_combat = INF
	game.resources.engaged = false
	game.targeting.stop_attack()
	game.targeting.current = foes[0]
	for i in foes.size():
		var enemy = foes[i]
		enemy.dead = false
		enemy.state = "idle"
		enemy.engaged = 0.0
		enemy.max_health = 10000.0
		enemy.health = 10000.0
		enemy.root_left = 0.0
		enemy.stagger = 0.0
		enemy._reset_control()
		enemy.position = game.player.position + Vector3(1.6 + i * 0.5, 0, 0)
	game.player.facing = PI / 2
	game.raw_aim = foes[0].position
	damage.clear()
	impacts.clear()


func _fill_resources() -> void:
	game.resources.mana = game.resources.max_mana
	for bar in game.resources.bars:
		game.resources.add(bar.id, bar.max)


func _equip_pair() -> void:
	game.inventory.equipment.mainHand = {"id":"oak_club", "count":1}
	game.inventory.equipment.offHand = {"id":"ironwood_club", "count":1}
	game.inventory._equipment_changed()


func _structure(id: String) -> void:
	var archetype: Dictionary = DB.archetypes[id]
	check(archetype.bar.size() == 6 and archetype.swapPool.size() == 6, id + " has six core and six swap spells")
	check(archetype.abilities.size() == 12, id + " has twelve distinct abilities")
	for entry in archetype.trained:
		check(game.npcs.all.any(func(npc): return DB.taught_by(entry, npc.id)), entry.ability + " has a trainer placed in the active world")
	check(game.action_bar.slots == ActionBar.default_bar(archetype,game.progression.level), id + " starts with its level-appropriate core bar")
	for ability in archetype.bar:
		check(game.skills.knows_ability(ability) == (int(archetype.coreLevels[ability])<=game.progression.level), ability + " has the correct core unlock")
	for ability in archetype.abilities:
		var look: Dictionary = DB.spell_fx.get(ability, {})
		check(game.hud.icons.abilities.get(ability) != null, ability + " has an imported icon")
		check(look.has("anim") and look.has("sound"), ability + " has an animation and sound profile")
		check(look.has("cast") or look.has("impact"), ability + " has a visible effect")
		for phase in ["cast", "impact"]:
			var sound = game.audio.cache.get("ability:"+ability+":"+phase)
			check(sound != null and sound.data.size() > 0, ability + " has a pre-generated " + phase + " sound")
	check(not ActionBar.bar_ability(game, "strike") and not ActionBar.bar_ability(game, "autoShot"), "Auto attacks remain outside the six slots")


func _cast_ability(class_id: String, id: String) -> void:
	var animation_count: int = game.player.rig.play_count
	game.spells.reset()
	_ready_cast()
	game.skills.all_spells = true
	_fill_resources()
	if DB.abilities[id].get("requires") == "dualWield":
		_equip_pair()
	if id == "deathVenom":
		game.spells._apply_dot(game.spells.tuned("poisonedBladeToxin"), foes[0], null, true)
	elif id == "reap" or id == "erupt":
		game.spells._apply_dot(game.spells.tuned("rot"), foes[0], null, true)
	elif id == "collapseWard":
		game.spells.buffs.arcaneWard = {"name":"Ward", "left":8.0, "absorb":20.0}
	elif id == "quickMend":
		game.spells.buffs.mendingPrayer = {"name":"Prayer", "left":5.0, "next":1.0}
	check(game.spells.try_cast(id), class_id + " casts " + id + " through the normal spell entry point")
	for step in 210:
		game.spells.update(1.0 / 60.0)
		game.player.rig.update(1.0 / 60.0, 0.0)
		game.fx.update(1.0 / 60.0)
		if game.player.lunge != null:
			game.spells.resolve(id)
			game.player.lunge = null
	check(impacts.any(func(e): return e.id == id), id + " emits its own visual/audio event")
	check(game.player.rig.play_count > animation_count, id + " triggers actual rig playback through normal casting")
	check(game.player.rig.last_action_clip != "A_TPose", id + " never selects a T-pose")
	game.skills.all_spells = false


func _warrior() -> void:
	_select_class("warden")
	check(game.inventory.can_wear(DB.items.oak_club, "mainHand"), "Warrior can wear a club")
	check(game.inventory.can_wear(DB.items.travelling_clothes, "chest"), "Ravager can wear leather")
	_equip_pair()
	check(game.stats.dual_wielding, "Two clubs enable dual wielding")
	check(not game.inventory.can_wear(DB.items.roadwarden_greatsword, "mainHand"), "Two-handed weapon refuses an occupied off hand")
	game.inventory.equipment.offHand = null
	check(game.inventory.can_wear(DB.items.roadwarden_greatsword, "mainHand"), "Two-handed weapon fits with a free off hand")
	game.inventory.equipment.mainHand = {"id":"roadwarden_greatsword", "count":1}
	check(not game.inventory.can_wear(DB.items.oak_club, "offHand"), "Two-handed weapon blocks an off-hand club")
	game.resources.values.resolve = 0.0
	game.events.emit("enemyHit", {"enemy":foes[0],"damage":1,"swing":true,"hand":"main"})
	var single_rate: float = game.resources.amount("resolve") / game.stats.attack_cooldown_for("main")
	_equip_pair()
	game.resources.values.resolve = 0.0
	game.events.emit("enemyHit", {"enemy":foes[0],"damage":1,"swing":true,"hand":"main"})
	var dual_rate: float = game.resources.amount("resolve") / game.stats.attack_cooldown_for("main")
	game.resources.values.resolve = 0.0
	game.events.emit("enemyHit", {"enemy":foes[0],"damage":1,"swing":true,"hand":"off"})
	dual_rate += game.resources.amount("resolve") / game.stats.attack_cooldown_for("off")
	check(is_equal_approx(single_rate, dual_rate), "Fury generation is normalized across one and two weapons")
	game.spells._class_release(DB.spells.twinFang, foes[0])
	check(game.spells.buffs.has("twinOpening"), "Both Twin Fang hits open the discount")
	check(game.spells.tuned("crosscut").cost.resolve == 15, "Crosscut consumes the discounted Fury cost")
	game.spells.buffs.clear()
	check(not game.spells._class_ready(DB.spells.berserk, null), "Berserk refuses less than full Fury")
	game.resources.add("resolve", 100)
	game.spells._class_release(DB.spells.berserk, null)
	for hit in 40:
		game.events.emit("enemyHit", {"enemy":foes[0],"damage":1})
	check(game.spells.buffs.berserk.left <= 10, "Berserk extension has a ten-second cap")
	game.spells._class_tick(1)
	check(game.resources.amount("resolve") == 85, "Berserk drains Fury over time")
	game.skills.all_spells = true
	_ready_cast()
	_fill_resources()
	check(game.spells.try_cast("flurry"), "Mobile Flurry starts")
	check(game.spells.movement_scale == 0.5, "Flurry slows movement")
	check(game.spells.try_cast("flurry") and game.spells.mobile.is_empty(), "Pressing Flurry again cancels it")
	game.skills.all_spells = false
	game.resources.values.resolve = 0.0
	game.progression.level = 1 # retain a nonzero miss chance for this boundary case
	game.random = func() -> float: return 0.0
	var missed: Dictionary = game.spells._damage(DB.spells.heavyStrike, foes[0], 10, "")
	game.spells._landed(DB.spells.heavyStrike, foes[0], missed)
	check(missed.get("miss", false) and game.resources.amount("resolve") == 0, "A missed Heavy Strike grants no Fury")
	game.random = func() -> float: return 0.5


func _paladin() -> void:
	_select_class("paladin")
	game.resources.add("conviction", 5)
	var paid: float = game.resources.spend(DB.spells.lightShield)
	check(paid == 3 and game.resources.amount("conviction") == 2, "A Conviction spender uses three of five charges")
	game.spells._go(game.spells._prepare_class_cast(DB.spells.lightShield.duplicate(true), paid), null)
	game.spells.absorb(100)
	check(game.spells.reprisal == game.spells.reprisal_cap, "Absorbing damage builds capped Reprisal")
	var hammer: Dictionary = game.spells._prepare_class_cast(DB.spells.lightsHammer.duplicate(true), 3)
	hammer.points = 3.0
	check(hammer.fullReprisal and game.spells.reprisal == 0, "Hammer snapshots and spends full Reprisal")
	var hit: Dictionary = game.spells._damage(hammer, foes[0], 10, "")
	check(hit.crit, "Full Reprisal guarantees the original hit crits")
	game.random = func() -> float: return 0.0
	check(game.spells._damage(hammer, foes[0], 10, "").crit, "Full Reprisal stays a guaranteed critical hit at the miss-roll boundary")
	game.spells._schedule_holy_echoes(hammer, [{"enemy":foes[0],"amount":hit.amount,"crit":hit.crit}])
	check(game.spells.echoes.size() == 3, "Successful echo chains stop at three repeats")
	var conviction: float = game.resources.amount("conviction")
	game.spells._class_tick(2)
	check(game.spells.echoes.is_empty() and game.resources.amount("conviction") == conviction, "Echoes resolve without granting Conviction")
	game.random = func() -> float: return 0.3
	hammer.fullReprisal = false
	game.spells._schedule_holy_echoes(hammer, [{"enemy":foes[0],"amount":10,"crit":false}])
	check(game.spells.echoes.is_empty(), "A normal spender fails an echo roll above 25 percent")
	hammer.fullReprisal = true
	game.spells._schedule_holy_echoes(hammer, [{"enemy":foes[0],"amount":10,"crit":true}])
	check(game.spells.echoes.size() == 3, "Full Reprisal raises the echo threshold to 50 percent")
	game.spells.echoes.clear()
	var rolls := [0]
	game.random = func() -> float:
		rolls[0] += 1
		return 0.0
	game.spells._schedule_holy_echoes(hammer, [
		{"enemy":foes[0],"amount":10,"crit":true},
		{"enemy":foes[1],"amount":10,"crit":true},
		{"enemy":foes[2],"amount":10,"crit":true},
	])
	check(rolls[0] == 3 and game.spells.echoes.size() == 3, "Area echoes roll once per chain stage instead of once per victim")
	game.random = func() -> float: return 0.5


func _rogue() -> void:
	_select_class("rogue")
	check(game.spells.try_cast("shadow"), "Shared stealth slot enters Shadow")
	check(game.spells.tuned("quickStrike").id == "ambush", "Strike becomes Ambush in Shadow")
	game.spells.break_shadow()
	_ready_cast()
	game.spells._apply_dot(DB.spells.poisonedBladeToxin, foes[0], null, true)
	check(game.spells.poison_remaining(foes[0]) > 0, "Poison estimate contains remaining ticks")
	game.resources.since_combat = 0
	foes[0].state = "chase"
	game.player.pending = {"type":"strike"}
	game.player.pending_off = {"type":"strike"}
	check(game.spells.try_cast("shadow"), "Shared stealth slot uses Vanish in combat")
	check(game.player.pending == null and game.player.pending_off == null and not game.targeting.attacking, "Vanish cancels pending auto attacks")
	check(game.player.cooldowns.get("vanish", 0) > 0 and foes[0].state == "search", "Vanish has its own cooldown and a search phase")
	var before: float = foes[0].health
	game.spells.update(2.01)
	check(game.spells.hidden and foes[0].health < before, "Existing poison ticks while the Rogue stays hidden")
	foes[0].update(4.1, game.player)
	check(foes[0].state == "return", "Searching ends in evade and return")
	_ready_cast()
	game.spells.break_shadow()
	game.spells.apply_aura("sleep", foes[0], DB.spells.sleep.applies)
	check(foes[0].asleep, "Sleep controls an ordinary enemy")
	foes[0].hurt(1)
	check(not foes[0].asleep, "Damage wakes a sleeping enemy")
	game.spells.zones.append({"id":"smokeBomb","x":0.0,"z":0.0,"radius":3.0})
	check(game.spells.smoke_blocks(Vector3(-5,0,0),Vector3(5,0,0)), "Smoke blocks a ranged line through its area")
	check(not game.spells.smoke_blocks(Vector3(-5,0,8),Vector3(5,0,8)), "Smoke leaves distant ranged lines clear")


func _ranger() -> void:
	_select_class("ranger")
	game.spells.apply_aura("quickShot", foes[0], DB.spells.quickShot.applies)
	var aimed: Dictionary = game.spells._damage(DB.spells.longShot, foes[0], 10, "", 1, {"periodic":true})
	var plain: Dictionary = game.spells._damage(DB.spells.longShot, foes[0], 10, "", 1, {"periodic":true})
	check(aimed.amount > plain.amount and not game.spells.has_aura(foes[0], "quickShot"), "Long Shot consumes same-target Aim for bonus damage")
	game.spells.zones.append({"id":"tarTrap","x":foes[0].position.x,"z":foes[0].position.z,"radius":3.0,"slow":50.0,"left":6.0,"next":1.0})
	check(game.spells._ignite_tar(foes[0]), "Flaming Arrow can ignite tar")
	check(game.spells.zones[0].id == "burningTar" and game.spells.zones[0].slow == 0, "Ignited tar replaces its slow with damage")
	game.spells.apply_aura("pinningShot", foes[0], DB.spells.pinningShot.applies)
	check(foes[0].move_speed == 0, "Pinning Shot roots an ordinary enemy")
	var cfg: Dictionary = foes[1].cfg
	foes[1].cfg = cfg.duplicate()
	foes[1].cfg.elite = true
	game.spells.apply_aura("pinningShot", foes[1], DB.spells.pinningShot.applies)
	check(foes[1].root_left == 0, "Pinning Shot respects elite immunity")
	foes[1].cfg = cfg


func _occultist() -> void:
	_select_class("occultist")
	game.spells._apply_dot(DB.spells.rot, foes[0], null, true)
	game.spells.update(2.01)
	check(game.resources.amount("corruption") > 0, "Rot generates Corruption on a successful tick")
	game.resources.values.corruption = 100.0
	check(is_equal_approx(game.spells._class_damage_scale(DB.spells.rot), 1.35), "Full Corruption grants 35 percent to curses")
	check(game.spells._class_damage_scale(DB.spells.blightBolt) == 1, "Corruption scaling is limited to curses and drains")
	var health: float = game.player.health
	game.resources.update(1)
	check(is_equal_approx(health-game.player.health,game.player.max_health*0.02), "Overcorruption drains two percent health per second")
	check(game.resources.spend(DB.spells.soulWard) == 40 and game.resources.amount("corruption") == 60, "Soul Ward spends at most forty Corruption")
	game.spells._cash_out(DB.spells.reap, foes[0])
	check(game.spells._find_dot(foes[0], "rot").is_empty(), "Reap consumes Rot")
	game.spells.dots.clear()
	game.resources.values.corruption = 0.0
	game.spells._apply_dot(DB.spells.rot, foes[0], null, true)
	game.spells.update(2.01)
	var single_gain: float = game.resources.amount("corruption")
	game.spells.dots.clear()
	game.resources.values.corruption = 0.0
	for enemy in foes:
		game.spells._apply_dot(DB.spells.rot, enemy, null, true)
	game.spells.update(2.01)
	var pack_gain: float = game.resources.amount("corruption")
	check(pack_gain > single_gain and pack_gain < single_gain*3, "Rot has diminishing Corruption returns across a pack")


func _wizard() -> void:
	_select_class("wizard")
	game.spells.apply_aura("frostLance", foes[0], DB.spells.frostLance.applies)
	game.spells._projectile_interactions(DB.spells.firebolt, foes[0], {"amount":10,"crit":false})
	check(not game.spells.has_aura(foes[0],"frostLance"), "Firebolt consumes Chill for steam")
	game.spells._class_release(DB.spells.echoSigil, null)
	game.spells._go(DB.spells.arcaneBolt, foes[0])
	check(not game.spells.buffs.has("echoSigil") and game.spells.bolts[-1].spell.has("sigilEcho"), "Sigil attaches to exactly the next released projectile")
	game.spells.update(0.2)
	check(game.spells.echoes.size() == 1, "Sigil schedules exactly one projectile repeat")
	game.spells.echoes.clear()
	game.spells.bolts.clear()
	damage.clear()
	game.spells._damage(DB.spells.chainLightning, foes[0], 10, "")
	game.spells._projectile_interactions(DB.spells.chainLightning, foes[0], {"amount":10,"crit":false})
	check(damage.size() == 3, "Chain Lightning hits exactly three distinct enemies in a pack")
	_ready_cast()
	_fill_resources()
	game.skills.all_spells = true
	var at: Vector3 = game.raw_aim
	check(game.spells.try_cast("meteor"), "Meteor begins a ground-targeted cast")
	game.raw_aim = game.player.position + Vector3(-8, 0, 0)
	check(game.player.casting.spell.groundAt == Vector3(at.x,0,at.z), "Meteor locks its ground point when casting starts")
	game.spells.update(3)
	check(game.player.casting == null, "Meteor finishes through the cast update")
	_ready_cast()
	_fill_resources()
	var mana: float = game.resources.mana
	game.spells.try_cast("meteor")
	game.player.moving = true
	game.spells.update(0.1)
	check(game.player.casting == null and game.resources.mana == mana, "Movement cancels Meteor before its mana is spent")
	game.player.moving = false
	game.skills.all_spells = false


func _legacy_and_swaps() -> void:
	_select_class("warden")
	game.progression.level = 10
	check(game.skills.learn_spell("twinFang"), "A class trainer can unlock a swap ability")
	game.action_bar.place("twinFang", 1)
	check(game.action_bar.slots[1] == "twinFang", "Learned swap replaces a core ability outside combat")
	game.resources.since_combat = 0
	game.action_bar.place("cleave", 1)
	game.action_bar.remove(1)
	game.action_bar.move(0, 1)
	game.action_bar.place_item("healing_draught", 1)
	check(game.action_bar.slots[1] == "twinFang", "All spellbar edits are refused in combat")
	var saved: Array = game.action_bar.serialize()
	game.resources.since_combat = INF
	game.action_bar.apply(saved)
	check(game.action_bar.slots == saved, "A customized spellbar survives loading")
	var legacy: Array = game.stats.archetype.get("legacyAbilities", [])
	if not legacy.is_empty():
		saved[0] = legacy[0]
		game.action_bar.apply(saved)
		check(game.action_bar.slots[0] == legacy[0] and game.skills.knows_ability(legacy[0]), "Existing equipped legacy abilities are retained")
