import { CONFIG } from '../config.js';
import { ITEMS, itemView } from '../data/items.js';

// Character stats and the one damage formula every hit goes through.
// See docs/stats-and-damage.md. The numbers all live in CONFIG.stats, the
// archetype entry and the item definitions.

const ATTRS = ['stamina', 'strength', 'agility', 'intellect'];
const S = () => CONFIG.stats;

// percent reduction from armour or resistance against an attacker of a level
export function mitigation(value, attackerLevel = 1) {
  if (!value || value <= 0) return 0;
  const k = S().armourConstant + S().armourPerLevel * attackerLevel;
  return Math.min(S().mitigationCap, (100 * value) / (value + k));
}

// The player's stats: archetype base + level gains + worn gear.
export class Stats {
  constructor(game) {
    this.game = game;
  }

  get archetype() {
    return CONFIG.archetypes[CONFIG.player.archetype];
  }

  // every attribute and gear stat, summed
  get totals() {
    const a = this.archetype;
    const lv = this.game.progression.level - 1;
    const t = { ...a.base };
    for (const [k, v] of Object.entries(a.perLevel)) t[k] = (t[k] || 0) + v * lv;
    for (const s of Object.values(this.game.inventory.equipment)) {
      const st = s && itemView(s).stats;
      if (st) for (const [k, v] of Object.entries(st)) t[k] = (t[k] || 0) + v;
    }
    for (const k of ATTRS) t[k] = t[k] || 0;
    return t;
  }

  get maxHealth() {
    return S().healthBase + this.totals.stamina * S().healthPerStamina;
  }

  get maxMana() {
    return this.archetype.resource === 'mana' ? this.totals.intellect * S().manaPerIntellect : 0;
  }

  get power() {
    return this.totals[this.archetype.mainStat] * S().powerPerMainStat;
  }

  get spellPower() {
    return this.totals.intellect * S().spellPowerPerIntellect;
  }

  get critChance() {
    return S().critBase + this.totals.agility * S().critPerAgility;
  }

  get armour() {
    return this.totals.armour;
  }

  // a shield's block chance plus block rating from gear; no shield, no block
  get blockChance() {
    const t = this.totals;
    const shield = this.game.inventory.equipment.offHand;
    if (!shield || ITEMS[shield.id].kind !== 'shield') return 0;
    return Math.min(S().blockCap, (t.block || 0) + (t.blockRating || 0) / S().blockRatingPerPercent);
  }

  get haste() {
    return Math.min(S().hasteCap, this.totals.haste || 0);
  }

  // haste divides swing time, windups, cast times and the GCD (to its floor)
  get speed() {
    return 1 + this.haste / 100;
  }

  hasted(seconds) {
    return seconds / this.speed;
  }

  // Auto attack swings once every weapon speed seconds, shortened by haste.
  get attackCooldown() {
    return this.hasted(this.weaponSpeed);
  }

  get weaponSpeed() {
    return this.game.inventory.weapon.speed || S().fistSpeed;
  }

  get globalCooldown() {
    return Math.max(S().gcdFloor, this.hasted(CONFIG.globalCooldown));
  }

  // the weapon's damage per swing
  get weaponRange() {
    const w = this.game.inventory.weapon;
    return w.damage || S().fistDamage;
  }

  // Abilities use the weapon's damage normalised, as in WoW: a slow, heavy
  // weapon and a quick light one of the same damage per second make Shield
  // Break, Lunge and the rest hit equally hard. They hit for
  // `abilityWeaponSeconds` (strike tuning) worth of the weapon's damage.
  get abilityWeaponRange() {
    const k = CONFIG.attack.abilityWeaponSeconds / this.weaponSpeed;
    const [lo, hi] = this.weaponRange;
    return [lo * k, hi * k];
  }

  // Power adds to every swing in proportion to the weapon's speed, so it is
  // worth the same per second on a slow weapon as on a quick one.
  get swingPower() {
    return (this.power * this.weaponSpeed) / CONFIG.attack.abilityWeaponSeconds;
  }

  // what an auto attack swing does before crits and the target's armour
  get swingRange() {
    const [lo, hi] = this.weaponRange;
    return [Math.round(lo + this.swingPower), Math.round(hi + this.swingPower)];
  }

  // damage per second from auto attack, haste included
  get dps() {
    const [lo, hi] = this.swingRange;
    return (lo + hi) / 2 / this.attackCooldown;
  }

  // what a weapon ability does before crits and the target's armour
  abilityRange(mult = 1) {
    const [lo, hi] = this.abilityWeaponRange;
    return [Math.round((lo + this.power) * mult), Math.round((hi + this.power) * mult)];
  }

  abilityAverage(mult = 1) {
    const [lo, hi] = this.abilityWeaponRange;
    return Math.round(((lo + hi) / 2 + this.power) * mult);
  }

  // What a level-up compares: label, value, and how to show it.
  snapshot() {
    const t = this.totals;
    return {
      stamina: { label: 'Stamina', v: t.stamina },
      strength: { label: 'Strength', v: t.strength },
      agility: { label: 'Agility', v: t.agility },
      intellect: { label: 'Intellect', v: t.intellect },
      health: { label: 'Maximum health', v: this.maxHealth },
      mana: { label: 'Maximum mana', v: this.maxMana },
      dps: { label: 'Auto attack', v: this.dps, text: `${this.dps.toFixed(1)} per second` },
      crit: { label: 'Crit', v: this.critChance, text: `${this.critChance.toFixed(1)}%` },
      spellPower: { label: 'Spell power', v: this.spellPower },
      block: { label: 'Block chance', v: this.blockChance, text: `${this.blockChance}%` },
      haste: { label: 'Haste', v: this.haste, text: `${this.haste}%` },
    };
  }

  // A stat block for the damage formula.
  get statBlock() {
    const t = this.totals;
    return {
      level: this.game.progression.level,
      crit: this.critChance,
      critMultiplier: S().critMultiplier,
      armour: t.armour,
      resistance: t.resistance || 0,
      block: this.blockChance,
    };
  }
}

// An enemy's stat block, straight from its config.
export function enemyBlock(cfg) {
  return {
    level: cfg.level || 1,
    crit: cfg.crit || 0,
    critMultiplier: S().critMultiplier,
    armour: cfg.armour || 0,
    resistance: cfg.resistance || 0,
    block: cfg.block || 0,
  };
}

// The damage formula. `base` is the hit before anything else (a weapon roll
// plus power, a spell's base plus spell power, or an enemy's damage).
//   x multiplier -> crit? -> armour or resistance (by attacker level)
//   -> block? (stops blockReduction % of what is left) -> round
export function computeHit(rand, attacker, defender, { base, mult = 1, school = 'physical', canCrit = true, canBlock = false }) {
  let dmg = base * mult;
  const crit = canCrit && rand() * 100 < attacker.crit;
  if (crit) dmg *= attacker.critMultiplier;
  dmg *= 1 - mitigation(school === 'physical' ? defender.armour : defender.resistance, attacker.level) / 100;
  let blocked = 0;
  if (canBlock && defender.block > 0 && rand() * 100 < defender.block) {
    blocked = Math.round((dmg * S().blockReduction) / 100);
  }
  const amount = Math.max(1, Math.round(dmg) - blocked);
  return { amount, crit, blocked, school };
}

// A weapon roll for an ability: anywhere in the normalised weapon range, plus power.
export function weaponRoll(rand, stats) {
  const [lo, hi] = stats.abilityWeaponRange;
  return lo + (hi - lo) * rand() + stats.power;
}

// An auto attack swing: anywhere in the weapon's own range, plus swing power.
export function swingRoll(rand, stats) {
  const [lo, hi] = stats.weaponRange;
  return lo + (hi - lo) * rand() + stats.swingPower;
}

// An enemy blow's raw damage, varied a little either side.
export function enemyRoll(rand, damage) {
  return damage * (1 + S().enemyVariance * (2 * rand() - 1));
}
