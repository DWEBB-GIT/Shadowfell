import { CONFIG } from '../config.js';
import { ITEMS, itemView } from '../data/items.js';
import { armourK, growth, levelGapFactor, spellScale } from '../data/scaling.js';

// Character stats and the one damage formula every hit goes through.
// See docs/stats-and-damage.md. The numbers all live in CONFIG.stats, the
// archetype entry and the item definitions.

const ATTRS = ['stamina', 'strength', 'agility', 'intellect'];
const S = () => CONFIG.stats;

// Percent reduction from armour or resistance: armour / (armour + K), where
// K grows with the defender's OWN level (400 + 100 x level), so the number
// on the character panel is what it stops against everyone. Level gaps are
// a separate rule (levelGapFactor, in computeHit).
export function mitigation(value, defenderLevel = 1) {
  if (!value || value <= 0) return 0;
  return Math.min(S().mitigationCap, (100 * value) / (value + armourK(defenderLevel)));
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
    t.stamina += this.game.cooking?.wellFedStamina || 0;
    return t;
  }

  get maxHealth() {
    return S().healthBase + this.totals.stamina * S().healthPerStamina;
  }

  get maxMana() {
    const m = this.archetype.resources?.mana;
    return m ? Math.round(m.base + this.totals.intellect * m.perIntellect) : 0;
  }

  get power() {
    return this.totals[this.archetype.mainStat] * S().powerPerMainStat;
  }

  // Ranged attack power comes from Agility, at half the rate of a main stat
  // (a WoW warrior's 1 per Agility against a hunter's 2): a Strength
  // fighter's bow is for pulling, not for killing
  get rangedPower() {
    return this.totals.agility * S().powerPerMainStat * S().rangedPowerShare;
  }

  get spellPower() {
    return this.totals.intellect * S().spellPowerPerIntellect;
  }

  // Agility's crit converts by level, so an Agility character keeps about
  // the same crit as it levels: 0.5% a point at level 1, less later
  get critChance() {
    return S().critBase + this.totals.agility / this.agilityPerCrit;
  }

  // Agility for 1% crit at this level: 0.4 x (level + 4)
  get agilityPerCrit() {
    return CONFIG.scaling.critAgility * growth(this.game.progression.level);
  }

  // player spells grow with level, as weapons grow with item level
  get spellScale() {
    return spellScale(this.game.progression.level);
  }

  get armour() {
    return this.totals.armour;
  }

  // a shield's own block chance plus block chance from other gear; no shield, no block
  get blockChance() {
    const shield = this.game.inventory.equipment.offHand;
    if (!shield || ITEMS[shield.id].kind !== 'shield') return 0;
    return Math.min(S().blockCap, this.totals.block || 0);
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

  // The swing timer (Dan's formula): T = W / (1 + H), W the weapon's speed
  // and H haste as a fraction. 2.5 s at 20% haste swings every 2.083 s.
  // Each hand has its own: `hand` is 'main' or 'off' (dual wielding).
  get attackCooldown() {
    return this.attackCooldownFor('main');
  }

  attackCooldownFor(hand) {
    // a quiver quickens Auto Shot on top of haste (as in WoW Classic)
    const quiver = hand === 'ranged' ? 1 + this.game.inventory.quiverHaste / 100 : 1;
    return this.handSpeed(hand) / this.speed / quiver;
  }

  // Seconds from the start of a swing to its impact frame. Haste shortens the
  // time between swings, not the swing itself: the animation keeps its own
  // timing unless the interval is too short for it, then it is squeezed in.
  get swingWindup() {
    return this.swingWindupFor('main');
  }

  swingWindupFor(hand) {
    return Math.min(CONFIG.attack.windup, this.attackCooldownFor(hand) * 0.4);
  }

  get swingAnimation() {
    return this.swingAnimationFor('main');
  }

  swingAnimationFor(hand) {
    return Math.min(CONFIG.attack.swingAnimation, this.attackCooldownFor(hand) * 0.9);
  }

  get weaponSpeed() {
    return this.handSpeed('main');
  }

  // ---- dual wielding: a working one-handed weapon in the off hand
  get dualWielding() {
    return !!this.game.inventory.offWeapon;
  }

  // `hand`: 'main', 'off' (dual wielding) or 'ranged' (the bow)
  handWeapon(hand) {
    const inv = this.game.inventory;
    return hand === 'off' ? inv.offWeapon : hand === 'ranged' ? inv.rangedWeapon : inv.weapon;
  }

  // ---- the ranged slot: Auto Shot at targets beyond melee reach
  get hasRanged() {
    return !!this.game.inventory.rangedWeapon;
  }

  get rangedReach() {
    return this.game.inventory.rangedWeapon?.range || 0;
  }

  handSpeed(hand) {
    return this.handWeapon(hand)?.speed || S().fistSpeed;
  }

  // a hand's weapon damage per swing, before power (the off hand's penalty
  // applies to the whole blow, in combat)
  weaponRangeFor(hand) {
    return this.handWeapon(hand)?.damage || S().fistDamage;
  }

  swingPowerFor(hand) {
    return ((hand === 'ranged' ? this.rangedPower : this.power) * this.handSpeed(hand)) / CONFIG.attack.abilityWeaponSeconds;
  }

  // what one swing of that hand does before crits and armour
  swingRangeFor(hand) {
    const [lo, hi] = this.weaponRangeFor(hand);
    const p = this.swingPowerFor(hand);
    const k = hand === 'off' ? S().offHandDamage : 1;
    return [Math.round((lo + p) * k), Math.round((hi + p) * k)];
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

  // damage per second from auto attack, haste and the off hand included
  get dps() {
    const per = (hand) => {
      const [lo, hi] = this.swingRangeFor(hand);
      return (lo + hi) / 2 / this.attackCooldownFor(hand);
    };
    return per('main') + (this.dualWielding ? per('off') : 0);
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
//   x multiplier x level gap (1.2 per level the attacker is above, /1.2 per
//   level below) -> crit? -> armour or resistance (by the defender's own
//   level) -> block? (stops blockReduction % of what is left) -> round, at
//   least 1
export function computeHit(rand, attacker, defender, { base, mult = 1, school = 'physical', canCrit = true, canBlock = false }) {
  let dmg = base * mult * levelGapFactor(attacker.level, defender.level);
  const crit = canCrit && rand() * 100 < attacker.crit;
  if (crit) dmg *= attacker.critMultiplier;
  dmg *= 1 - mitigation(school === 'physical' ? defender.armour : defender.resistance, defender.level) / 100;
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

// An auto attack swing: anywhere in that hand's weapon range, plus swing power.
export function swingRoll(rand, stats, hand = 'main') {
  const [lo, hi] = stats.weaponRangeFor(hand);
  return lo + (hi - lo) * rand() + stats.swingPowerFor(hand);
}

// An enemy blow's raw damage, varied a little either side.
export function enemyRoll(rand, damage) {
  return damage * (1 + S().enemyVariance * (2 * rand() - 1));
}
