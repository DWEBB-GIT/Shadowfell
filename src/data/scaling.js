// Growth by level. Everything that gets bigger with level grows on one
// straight line, n = level + 4 (level 1 is 5, level 10 is 14, level 40 is
// 44): the armour constant, the armour on items, every item's stat budget,
// weapon damage, player spell damage, and the enemy table's health and hits.
// Percentages (damage reduction, haste, block, crit) do not grow; their price
// on an item does. When levels differ, one rule takes over: every hit is x1.2
// for each level the attacker is above its target, and /1.2 for each below.
//
// This file holds those constants and the formulas that turn an item's level,
// slot, armour type and rarity into its numbers, and an enemy's level and
// type into its. It has no imports, so the data check (tests/validate-data.mjs)
// runs the same formulas in Node. The design and its tables are in
// docs/stats-and-damage.md; CONFIG.scaling is this object.

export const SCALING = {
  levelOffset: 4, // n = level + 4

  // ---- combat
  // damage reduction = armour / (armour + K), K = 400 + 100 x the DEFENDER'S
  // OWN level (that is, 100 x n), capped at CONFIG.stats.mitigationCap
  armourConstant: 400,
  armourPerLevel: 100,
  levelGap: 1.2, // every hit x 1.2 ^ (attacker's level - target's level)
  critAgility: 0.4, // crit chance = 5% + Agility / (0.4 x n)

  // ---- items (each gear item states its itemLevel)
  // one weight per slot sets both an item's armour and its stat points; a
  // full set (14 slots, trinkets aside) weighs 10
  slotWeights: {
    head: 1, chest: 1, legs: 1, mainHand: 1,
    shoulders: 0.75, hands: 0.75, waist: 0.75, feet: 0.75,
    wrists: 0.5, back: 0.5, neck: 0.5, finger: 0.5, offHand: 0.5,
    trinket: 0, // trinkets carry effects only, outside the budget
  },
  // armour = type factor x slot weight x n x rarity main; a cloak is cloth for
  // every wearer, and a shield has its own (more than a plate chest)
  armourFactors: { cloth: 3, leather: 6, mail: 9, plate: 12 },
  shieldArmour: 20, // x n x rarity main
  shieldBlock: 10, // percent block chance built into every shield, x rarity main
  weaponDps: 0.45, // weapon damage a second = 0.45 x n x rarity main
  weaponSpread: 0.4, // a swing (dps x speed) rolls within +-40% of its average
  // `budget` scales an item's stat points; `main` its armour, weapon damage
  // and a shield's block chance. White (common) gear has no stats.
  rarity: {
    junk: { budget: 0, main: 1 },
    common: { budget: 0, main: 1 },
    enhanced: { budget: 1, main: 1 },
    rare: { budget: 1.3, main: 1.1 },
    epic: { budget: 1.6, main: 1.2 },
    legendary: { budget: 2, main: 1.3 },
    quest: { budget: 0, main: 1 },
  },
  budgetPerLevel: 0.4, // stat points = 0.4 x slot weight x n x rarity budget
  // what one of a stat costs in points: attributes 1, bonus armour and
  // resistance 1 per 50, and the percentages by item level (n / 15 points
  // for 1% haste, n / 50 for 1% block), so they read the same at any level
  statCost: { strength: 1, agility: 1, intellect: 1, stamina: 1, armour: 0.02, resistance: 0.02 },
  statCostPerLevel: { haste: 1 / 15, block: 1 / 50 },
  budgetTolerance: 0.1, // the data check flags an item more than 10% over its budget

  // ---- enemies: fixed by their own level and type, never by the player's
  // Each level's normal enemy is sized against "par": a character of that
  // level with only its own attributes (the Warden's) and white gear.
  par: { mainStat: 4, mainStatPerLevel: 2, stamina: 10, staminaPerLevel: 2 },
  enemyHealthSeconds: 4.5, // a normal enemy has the health of 4.5 s of par damage
  enemyHitShare: 18, // ...hits for par health / 18...
  enemyHealthRoll: 0.1, // ...and each spawn point's enemy has +-10% health
  // a type multiplies its level's normal enemy; `special` sizes a telegraphed
  // special from par health (a quarter for an elite, half for a heavy)
  enemyTypes: {
    fodder: { health: 0.5, hit: 0.5, interval: 1.35, armour: 'none' },
    pack_beast: { health: 0.6, hit: 0.6, interval: 0.95, armour: 'none' },
    normal: { health: 1, hit: 1, interval: 1.35, armour: 'none' },
    skirmisher: { health: 0.6, hit: 1.75, interval: 2.5, armour: 'light' },
    armoured: { health: 1.25, hit: 1, interval: 1.35, armour: 'heavy' },
    elite: { health: 1.7, hit: 1.375, interval: 1.2, armour: 'armoured', special: 0.25 },
    heavy: { health: 4, hit: 3, interval: 2.2, armour: 'armoured', special: 0.5 },
    boss: { health: 15, armour: 'armoured', special: 0.5 }, // its hits are designed per fight
  },
  // enemy armour as a share of K at the enemy's own level
  armourClasses: { none: 0, light: 0.1, armoured: 0.2, heavy: 0.4 },
};

const S = SCALING;

// the growth line: n = level + 4
export const growth = (level) => level + S.levelOffset;

// K, the armour constant, for a defender of this level
export const armourK = (level) => S.armourConstant + S.armourPerLevel * level;

// every hit is multiplied by this: 1.2 per level the attacker is above its target
export const levelGapFactor = (attackerLevel, targetLevel) => S.levelGap ** ((attackerLevel || 1) - (targetLevel || 1));

// player spell damage grows with the caster as weapons grow with item level
export const spellScale = (level) => growth(level) / growth(1);

const GEAR = ['weapon', 'armor', 'shield', 'jewellery'];
export const isScaledItem = (d) => !!d && GEAR.includes(d.kind) && d.itemLevel !== undefined;

const rarityOf = (d) => S.rarity[d.rarity] || S.rarity.common;
export const slotWeight = (d) => S.slotWeights[d.slot] ?? 0;

// what one of stat `k` costs in points at item level `itemLevel`
export function statCost(k, itemLevel = 1) {
  if (S.statCost[k] !== undefined) return S.statCost[k];
  if (S.statCostPerLevel[k] !== undefined) return S.statCostPerLevel[k] * growth(itemLevel);
  return 1;
}

// the stat points an item of this level, slot and rarity may spend
export function itemBudget(d, rarity = d.rarity) {
  return S.budgetPerLevel * slotWeight(d) * growth(d.itemLevel ?? 1) * (S.rarity[rarity] || S.rarity.common).budget;
}

// What an item is worth before any stats: armour (and a shield's own block
// chance), and a weapon's damage per swing at its speed.
export function itemMain(d) {
  const n = growth(d.itemLevel);
  const main = rarityOf(d).main;
  const stats = {};
  let damage = null;
  if (d.kind === 'armor') {
    const factor = d.slot === 'back' ? S.armourFactors.cloth : S.armourFactors[d.armourType] || 0;
    stats.armour = Math.round(factor * slotWeight(d) * n * main);
  } else if (d.kind === 'shield') {
    stats.armour = Math.round(S.shieldArmour * n * main);
    stats.block = Math.round(S.shieldBlock * main);
  } else if (d.kind === 'weapon') {
    const swing = S.weaponDps * n * main * d.speed;
    damage = [Math.max(1, Math.round(swing * (1 - S.weaponSpread))), Math.max(1, Math.round(swing * (1 + S.weaponSpread)))];
  }
  return { stats, damage };
}

// Spend `points` across `split` (shares, e.g. { strength: 1, stamina: 1 }),
// each stat at its price: { strength: 2, stamina: 2 }.
export function spendPoints(points, split, itemLevel) {
  const out = {};
  const shares = Object.values(split || {}).reduce((a, v) => a + v, 0);
  if (!(points > 0) || !(shares > 0)) return out;
  for (const [k, share] of Object.entries(split)) {
    const v = Math.round((points * share) / shares / statCost(k, itemLevel));
    if (v > 0) out[k] = v;
  }
  return out;
}

// A gear record with its numbers filled in from its item level: armour, block,
// weapon damage, and stat points spent by its `statSplit`. An item can still
// state exact numbers: a stated `damage`, or a stat in `stats`, wins.
export function scaledItem(d) {
  if (!isScaledItem(d)) return d;
  const main = itemMain(d);
  const stats = { ...main.stats };
  for (const [k, v] of Object.entries(spendPoints(itemBudget(d), d.statSplit, d.itemLevel))) stats[k] = (stats[k] || 0) + v;
  Object.assign(stats, d.stats || {});
  const out = { ...d, stats };
  if (d.damage || main.damage) out.damage = d.damage || main.damage;
  return out;
}

// What an item spends against its budget: every stat beyond its own armour
// and a shield's own block chance, at its price, plus stated weapon damage
// above the formula's.
export function itemSpend(d) {
  const s = scaledItem(d);
  const main = itemMain(d);
  let spent = 0;
  for (const [k, v] of Object.entries(s.stats || {})) spent += Math.max(0, v - (main.stats[k] || 0)) * statCost(k, d.itemLevel);
  const over = d.damage && main.damage ? (d.damage[0] + d.damage[1]) / (main.damage[0] + main.damage[1]) - 1 : 0;
  return { budget: itemBudget(d), spent, damageOver: Math.max(0, over) };
}

// Is it more than budgetTolerance over (and by more than the half point
// rounding can add)? Items marked `budgetException` may be.
export function overBudget(d) {
  if (!isScaledItem(d) || d.budgetException) return false;
  const { budget, spent, damageOver } = itemSpend(d);
  return (spent > budget * (1 + S.budgetTolerance) && spent - budget > 0.5) || damageOver > S.budgetTolerance;
}

// ---------------------------------------------------------------- enemies
// Par at a level: damage a second (an on-level white weapon plus power) and
// health. `stats` is CONFIG.stats; `weaponSeconds` is abilityWeaponSeconds.
export function par(level, stats, weaponSeconds) {
  const p = S.par;
  const main = p.mainStat + p.mainStatPerLevel * (level - 1);
  const stamina = p.stamina + p.staminaPerLevel * (level - 1);
  return {
    dps: S.weaponDps * growth(level) + (main * stats.powerPerMainStat) / weaponSeconds,
    health: stats.healthBase + stamina * stats.healthPerStamina,
  };
}

// An enemy record with its numbers filled in from its level and `type`:
// health, damage, attackInterval, armour (from its type's armour class, or
// its own `armourClass`), a special's damage and an aimed shot's damage and
// interval. Any number stated in the record wins.
export function scaledEnemy(e, stats, weaponSeconds) {
  const t = S.enemyTypes[e.type];
  if (!t) return e;
  const level = e.level || 1;
  const p = par(level, stats, weaponSeconds);
  const health = S.enemyHealthSeconds * p.dps * t.health;
  const hit = t.hit === undefined ? undefined : Math.round((p.health / S.enemyHitShare) * t.hit);
  const out = {
    health: Math.round(health),
    damage: hit,
    attackInterval: t.interval,
    armour: Math.round((S.armourClasses[e.armourClass || t.armour] || 0) * armourK(level)),
    ...e,
  };
  if (e.special && t.special) out.special = { damage: Math.round(p.health * t.special), ...e.special };
  if (e.ranged) out.ranged = { damage: hit, interval: t.interval, ...e.ranged };
  return out;
}

// Each spawn point's enemy has its own health, +-enemyHealthRoll around its
// type's, fixed by the spawn's id: a lean hound and a big one, the same each
// time it comes back.
export function spawnHealth(health, spawnId) {
  let h = 2166136261;
  for (let i = 0; i < spawnId.length; i++) h = Math.imul(h ^ spawnId.charCodeAt(i), 16777619) >>> 0;
  const u = h / 4294967296;
  return Math.max(1, Math.round(health * (1 + S.enemyHealthRoll * (2 * u - 1))));
}
