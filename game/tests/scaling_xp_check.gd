extends SceneTree
## Monster and XP formulas (Dan, 2026-11-03, "Monster scaling and XP
## formulas"): every enemy's kill XP, every quest's XP and every level's XP
## come from the constants in scaling.gd and db.gd `progression`.
var failures := 0


func _initialize() -> void:
	DB.ensure()
	var S := Scaling.S
	var pr: Dictionary = DB.CONFIG.progression
	# the XP curve follows the pacing plan at every level 1-49
	check(pr.levelMinutes.size() == pr.maxLevel - 1, "a planned time for every level-up 1-49")
	check(DB.xp_for_next_level(1) == 280, "level 1 to 2 still takes 280 XP")
	var total := 0
	var rising := true
	for lv in range(1, pr.maxLevel):
		var need := DB.xp_for_next_level(lv)
		var want := U.jround(pr.levelMinutes[lv - 1] * pr.pace * Scaling.kill_xp_base({}, lv))
		if need != want:
			check(need == want, "level %d: XP to next = minutes x pace x kill XP (%d)" % [lv, need])
		if lv > 1 and need < DB.xp_for_next_level(lv - 1):
			rising = false
		total += need
	check(rising, "XP to next never falls as levels rise")
	print("total XP 1 to 50: ", total)
	check(total > 1000000 and total < 2000000, "about 1.45 million XP to reach 50")
	# every enemy: same level and type, same XP; nothing typed by hand
	var by_key := {}
	for id in DB.enemies:
		var e: Dictionary = DB.enemies[id]
		if e.has("xp"):
			check(not e.has("xp"), "%s has no hand-typed xp" % id)
		var c: Dictionary = DB.enemy_cfg[id]
		if not c.has("xp"):
			check(c.has("xp"), "%s has kill XP from the formula" % id)
		if e.get("noXp", false):
			check(c.xp == 0, "%s (noXp) pays nothing" % id)
			continue
		if c.xp <= 0:
			check(c.xp > 0, "%s pays XP" % id)
		if e.has("xpScale"):
			continue
		var k := "%s@%d" % [e.get("type", "normal"), int(e.get("level", 1))]
		if by_key.has(k):
			if by_key[k] != c.xp:
				check(by_key[k] == c.xp, "%s pays the same as other %s" % [id, k])
		by_key[k] = c.xp
	var normal30 := Scaling.kill_xp_base({"type": "normal"}, 30)
	check(normal30 == U.jround(28 * 34 / 5.0), "a level 30 normal enemy pays 190 (%d)" % normal30)
	check(absi(Scaling.kill_xp_base({"type": "elite"}, 30) - 2 * normal30) <= 1, "an elite pays twice a normal")
	# monster numbers: an even normal fight lasts fightSeconds and costs fight_cost(level)
	for lv in [1, 5, 8, 20, 40]:
		var p := Scaling.par(lv, DB.CONFIG.stats, DB.attack.abilityWeaponSeconds)
		var e := Scaling.scaled_enemy({"type": "normal", "level": lv}, DB.CONFIG.stats, DB.attack.abilityWeaponSeconds)
		var cost: float = e.damage / e.attackInterval * S.fightSeconds / p.health
		var want: float = Scaling.fight_cost(lv) * S.enemyDamage
		check(absf(cost - want) < 0.03, "level %d normal fight costs %.0f%% of par health (%.2f)" % [lv, want * 100, cost])
		check(absf(e.health / p.dps - S.fightSeconds) < 0.5, "level %d normal enemy lasts %d s" % [lv, S.fightSeconds])
	check(Scaling.fight_cost(1) <= 0.2 and Scaling.fight_cost(8) >= 0.4 and Scaling.fight_cost(50) < Scaling.fight_cost(8), "fights cost 10-20% at level 1, about 45% at 6-10, less later")
	# the level gap: a much higher foe one-shots you, never softer than x1
	check(Scaling.level_gap(7, 44) == 1.0 and absf(Scaling.level_gap(12, 7) - pow(1.2, 5)) < 0.001, "level gap is 1.2^levels above, x1 below")
	var big := Scaling.scaled_enemy({"type": "normal", "level": 44}, DB.CONFIG.stats, DB.attack.abilityWeaponSeconds)
	var p7 := Scaling.par(7, DB.CONFIG.stats, DB.attack.abilityWeaponSeconds)
	var blow: float = big.damage * 0.65 * Scaling.level_gap(44, 7) * (1 - Stats.mitigation(1000, 7) / 100.0)
	check(blow > p7.health * 3, "a level 44 normal's softest blow kills a well-armoured level 7 outright (%d vs %d health)" % [blow, p7.health])
	# every quest: XP from its size, none typed
	for id in DB.quests:
		var r: Dictionary = DB.quests[id].get("reward", {})
		if r.has("xp"):
			check(not r.has("xp"), "%s has no hand-typed xp" % id)
	var std := DB.quest_xp_base({"size": "standard"}, 10)
	check(std == U.jround(DB.xp_for_next_level(10) * 0.07), "a standard level 10 quest is 7%% of the bar (%d)" % std)
	check(absi(DB.quest_xp_base({"size": "standard", "xpScale": 1.5}, 10) - U.jround(std * 1.5)) <= 1, "xpScale lengthens a quest's reward")
	print("failures: ", failures)
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if ok:
		print("ok: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)
