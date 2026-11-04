@tool
extends RefCounted
## Every numeric option consumed by the spell engine. Empty kinds = all spells.
## [default, kinds, explanation]. Flags stay numeric for the shared JSON schema.
const FIELDS := {
	"cooldown": [6, [], "Seconds before this ability can be used again."],
	"offGlobalCooldown": [1, [], "1 bypasses the global cooldown; 0 uses it."],
	"damageMin": [1, ["cast", "instant", "interrupt", "aoe", "channel", "dot", "healZone", "healBurst"], "Minimum fixed spell damage. Instant weapon strikes use damageMultiplier instead."],
	"damageMax": [2, ["cast", "instant", "interrupt", "aoe", "channel", "dot", "healZone", "healBurst"], "Maximum fixed spell damage; at least damageMin."],
	"damageMultiplier": [1, ["instant", "cast", "cleave", "burst", "charge"], "Weapon/bow damage multiplier: 1 = 100%. Cast uses this only with From a bow."],
	"spellPower": [1, ["cast", "instant", "interrupt", "aoe", "channel", "dot", "cleave", "burst", "charge", "healZone", "healBurst", "thorns"], "Share of spell power added to damage (1 = 100%). Spells default to 1, weapon abilities and thorns to 0. Set in Scaling."],
	"healMin": [3, ["heal", "hot", "healZone", "healBurst"], "Minimum base healing (per tick for a heal over time or a zone). Set in Scaling."],
	"healMax": [5, ["heal", "hot", "healZone", "healBurst"], "Maximum base healing; at least healMin. Set in Scaling."],
	"healPower": [1, ["heal", "hot", "healZone", "healBurst"], "Share of spell power added to each heal or tick (1 = 100%). Default 1. Set in Scaling."],
	"consumePercent": [100, ["heal"], "With Consumes set: the heal adds this percent of what the consumed heal over time still had to give."],
	"thornsMin": [2, ["thorns"], "Minimum damage each attacker takes back. Set in Scaling."],
	"thornsMax": [3, ["thorns"], "Maximum damage each attacker takes back. Set in Scaling."],
	"weaponDamage": [0.35, ["cast", "instant", "interrupt", "aoe", "channel", "dot"], "Share of a weapon roll a spell adds (1 = 100%). Set in Scaling."],
	"perPoint": [0.2, ["instant", "cleave", "burst"], "Adds this much weapon multiplier per point spent. Also choose Spends all in Needs and effects."],
	"bothHands": [1, ["instant", "cleave"], "1 adds off-hand damage while dual wielding; 0 uses the main hand."],
	"castTime": [1.5, ["cast", "channel", "portal", "camp", "heal"], "Seconds spent casting or channelling; haste shortens this. A heal with 0 is instant."],
	"projectileSpeed": [20, ["cast"], "Spell projectile speed in metres/second (non-bow casts)."],
	"duration": [6, ["dot", "aoe", "trap", "buff", "shield", "charge", "leap", "hot", "healZone", "thorns"], "Effect duration, or movement duration for charge/leap, in seconds."],
	"tickInterval": [1, ["dot", "aoe", "channel", "hot", "healZone"], "Seconds between ticks; must be greater than zero."],
	"tickMultiplier": [0.3, ["dot"], "Damage per tick as a share of the weapon/bow roll, or fixed spell damage when damageMin/Max are present."],
	"radius": [4, ["aoe", "burst", "trap", "healZone", "healBurst"], "Effect radius in metres."],
	"range": [3, ["cleave"], "Cleave reach in metres; target range is a separate Ability setting."],
	"coneDegrees": [90, ["cleave"], "Cleave arc: 90 in front, 360 all around."],
	"maxTargets": [3, ["cleave", "instant", "cast"], "Cleave target limit, or number of arrows for a bow ability."],
	"spread": [5, ["instant", "cast"], "For multi-target bow attacks: search radius around the primary target."],
	"windup": [0.25, ["cleave", "burst"], "Delay before the hit lands, in seconds."],
	"spins": [2, ["cleave", "burst"], "Number of blows; additional blows repeat after the windup."],
	"stagger": [0.7, ["burst"], "Stagger strength of each burst hit."],
	"knockback": [1, ["burst"], "Burst knockback strength."],
	"interrupts": [1, ["burst"], "1 makes the burst a heavy interrupting hit."],
	"healPerHit": [2, ["burst"], "Heal this percent of maximum health per enemy hit."],
	"distance": [5, ["charge", "leap"], "Movement distance in metres."],
	"hitRadius": [2, ["charge"], "Radius searched for an enemy when the charge ends."],
	"window": [3, ["guard"], "How long the guard remains active, in seconds."],
	"blocks": [0, ["guard"], "Hits blocked during the guard. 0 means unlimited hits for the window."],
	"reduction": [40, ["guard", "buff"], "Percent damage reduction while the guard or buff lasts."],
	"miss": [1, ["guard"], "1 makes guarded attacks miss (dodge)."],
	"lockout": [3, ["interrupt"], "Seconds the interrupted enemy cannot cast again."],
	"damageBonus": [10, ["buff"], "Percent bonus to player damage."],
	"inCombat": [1, ["stealth"], "1 allows entering stealth during combat."],
	"armTime": [1, ["trap"], "Seconds until a placed trap can trigger."],
	"triggerRadius": [1.5, ["trap"], "How close an enemy must come to trigger the trap."],
	"lifetime": [30, ["trap"], "Seconds an untriggered trap remains."],
	"maxTraps": [3, ["trap"], "Maximum traps of this ability; oldest is replaced."],
	"slow": [0.5, ["trap", "aoe", "healZone"], "Movement slow as a fraction: 0.5 = 50%, 1 = fully slowed."],
	"healPercent": [2, ["channel", "aoe"], "AoE: percent maximum health per tick inside it. Channel: percent of damage returned as health."],
	"healPerPoint": [5, ["purge"], "Heal this percent maximum health per resource point spent."],
	"extend": [3, ["purge"], "Extra seconds added to existing damage-over-time effects and non-control auras."],
	"absorbPercent": [20, ["shield"], "Shield amount as a percent of player maximum health."],
	"abilityWeaponSeconds": [2.4, ["custom"], "Attack system only: normalised weapon seconds used when calculating ability damage."],
	"swingAnimation": [0.8, ["custom"], "Attack system only: swing animation length."],
	"turnRate": [6, ["custom"], "Attack system only: player turning speed."],
	"catchUp": [0.25, ["custom"], "Attack system only: swing timer catch-up allowance."],
	"readyWindup": [0.12, ["custom"], "Attack system only: windup for an attack already ready."],
	"openerWindup": [0.3, ["custom"], "Attack system only: windup for the opening attack."],
	"staggerGap": [0.2, ["custom"], "Attack system only: time separating main- and off-hand hits."],
	"movingLeeway": [1, ["custom"], "Attack system only: extra reach allowance while moving."],
	"draw": [0.45, ["custom"], "Auto Shot system only: bow draw time."],
	"arrowSpeed": [30, ["custom"], "Auto Shot system only: arrow speed in metres per second."],
	"fireRange": [4, ["custom"], "Cooking system only: reach of a campfire."],
	"wellFedAfter": [10, ["custom"], "Food system only: eating time needed for Well Fed."],
	"wellFedSeconds": [600, ["custom"], "Food system only: Well Fed buff duration."],
	"wellFedStamina": [2, ["custom"], "Food system only: stamina granted by Well Fed."]
}


static func applicable(key: String, ability: Dictionary) -> bool:
	if not FIELDS.has(key):
		return true # custom-system tuning remains editable
	if not ability.has("kind"):
		return true
	return FIELDS[key][1].is_empty() or ability.kind in FIELDS[key][1]


static func help(key: String) -> String:
	if not FIELDS.has(key):
		return "Custom system option; used by this ability's own implementation."
	return str(FIELDS[key][2]) + (" Used by: " + ", ".join(FIELDS[key][1]) + "." if not FIELDS[key][1].is_empty() else "")


static func default_value(key: String):
	return FIELDS[key][0] if FIELDS.has(key) else 0
