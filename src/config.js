// Engine tuning: the numbers that shape how the game plays and looks.
// Content (items, enemies, abilities, quests, the world...) lives in /data;
// see src/data/db.js. For convenience CONFIG also exposes the archetypes,
// enemies and ability tuning from there under their old names, so gameplay
// code reads every number from one place.

import { DB } from './data/db.js';
import { SCALING, scaledEnemy } from './data/scaling.js';

export const CONFIG = {
  player: {
    archetype: 'warrior',
    speed: 5.6, // metres per second: a run (Dan, 2026-10-16: 6.5 felt too fast)
    runGait: 1.3, // the run animation: quicker, longer strides than a walk
    radius: 0.4,
    startCoins: 8,
    startDraughts: 1,
  },
  shop: {
    sellFraction: 0.25, // merchants pay a quarter of their price, as in WoW
    buybackSlots: 6, // things you sold this session can be bought back at what you got
    talkRange: 3.0, // how close to stand to talk to a merchant
    leaveRange: 6.0, // walking further than this closes the shop
  },
  death: {
    coinLossFraction: 0.2, // lost only by returning to life at the rest point, not at your body
    coinLossCap: 5,
    screenDelay: 1.3,
    ghostSpeed: 1.5, // a spirit moves this much faster than the living
    corpseReach: 3.5, // how close a spirit must come to its body to rise there
    restReach: 4, // ...or to the rest point to return to life there
    corpseHealth: 0.5, // rising at the body: this share of health
    revengeBonus: 25, // percent more damage to the enemy that killed you
    revengeXp: 0.5, // killing it pays this share of its experience again
  },
  fishing: {
    castTime: 0.6, // the bob's flight
    duration: 20, // seconds a cast lasts (the fishing bar); no bite by then and nothing was biting
    biteMin: 3, // a bite comes this many seconds into the cast, at least...
    biteMax: 16, // ...and at most
    biteWindow: 1.4, // how long the bob stays under: strike now
    biteBase: 35, // percent chance a cast gets a bite at all...
    bitePerSkill: 1.2, // ...plus this per point of fishing skill (rank + rod + bait), up to biteCap
    biteCap: 95,
    baseChance: 65, // percent chance to land it on a timely strike...
    chancePerRank: 0.6, // ...plus this per point of fishing skill
    clickRadius: 60, // pixels: a click this close to the bob strikes
  },
  camp: {
    clearRadius: 14, // no camp with a living enemy this close, or any enemy engaged
    restRadius: 4, // rest within this of the fire to build rested experience
    restedPerSecond: 0.01, // share of a level's experience rested per second by the fire
    restedCap: 1, // at most one level's worth of rested experience
  },
  progression: {
    firstLevelXp: 100,
    xpGrowthPerLevel: 60, // level 2 -> 3 needs 160, then 220, ...
  },
  // Stats and damage (see docs/stats-and-damage.md). One formula for every
  // hit: base x multiplier x level gap, then crit, then armour or resistance,
  // then block. Everything that grows with level (the armour constant, the
  // level gap, item budgets, the enemy table) is in `scaling` below.
  stats: {
    healthBase: 40,
    healthPerStamina: 6,
    manaPerIntellect: 10,
    rangedPowerShare: 0.5, // bows: Agility x powerPerMainStat x this is ranged power
    powerPerMainStat: 0.25, // damage added to every weapon hit (per 0.6 s of swing time)
    spellPowerPerIntellect: 0.25,
    critBase: 5, // percent, plus Agility / (scaling.critAgility x (level + 4))
    critMultiplier: 1.5,
    mitigationCap: 75, // percent: armour and resistance never stop more
    blockCap: 50, // percent
    blockReduction: 30, // a block stops this % of the blow (Brace stops all of it)
    hasteCap: 30, // percent; haste divides swing time, windups, casts and the GCD
    gcdFloor: 1.0, // seconds: haste never takes the global cooldown below this
    enemyVariance: 0.15, // enemy blows land within +-15% of their damage
    fistDamage: [1, 2], // bare hands (or a broken weapon), per swing
    fistSpeed: 2.0, // seconds between bare-handed swings
    offHandDamage: 0.5, // an off-hand weapon's swings do half damage (WoW)
    offHandResolve: 0.5, // and build half the Resolve of a main-hand swing
  },
  interaction: {
    radius: 2.2,
  },
  // gear wears when you die; at 0% it is broken (no stats) until mended
  durability: {
    deathLoss: 10, // percent off every worn weapon and piece of armour
    repairFraction: 0.5, // mending 100% costs half the item's price (silver)
  },
  // how a landed blow feels: a camera kick (no hit-stop: the action never pauses)
  impact: {
    shake: 0.07, // metres of camera kick
    critShake: 0.16,
    shakeDecay: 9, // per second
  },
  fog: { color: 0x3a4244, near: 14, far: 40 }, // linear view-distance fog, in metres from the camera
  // the Blackwood closes in: nearer, darker fog and dimmer light under the pines
  blackwood: { fogColor: 0x1d2725, fogNear: 9, fogFar: 32, light: 0.68 },
  camera: {
    offset: [0, 11, 10],
    indoorZoom: 0.22, // how much closer the camera comes inside a building
    fov: 45,
    followSharpness: 8, // higher = tighter follow
    renderScale: 0.62, // chunky, period-appropriate pixels
    showcase: { distance: 5.2, side: 1.3, height: 1.7, lookHeight: 1.0 }, // character select: in front of the character, a little to one side
  },
  targeting: {
    range: 26, // Tab / R3 cycle through enemies this close
    dropRange: 34, // a selected target further away than this is let go
    clickRadius: 46, // pixels: how close a click must be to an enemy or townsperson
    softArc: 60, // soft lock: degrees either side of your aim
    softAimRadius: 2.5, // ...or an enemy this close to the cursor point
  },
  loot: {
    areaRadius: 5, // looting one thing also loots everything this close to it
    clickRadius: 40, // pixels: how close a click must be to a corpse or drop
    reach: 3.2, // how close the Warrior must be to loot by clicking
  },
};


// content from /data, under the names gameplay code uses
const tuning = (id) => DB.abilities[id].tuning;
Object.assign(CONFIG, {
  attack: tuning('strike'),
  autoShot: tuning('autoShot'),
  shieldBreak: tuning('shieldBreak'),
  lunge: tuning('lunge'),
  brace: tuning('brace'),
  draught: tuning('draught'),
  globalCooldown: DB.globalCooldown,
  // WoW's spell queue: an ability pressed this close to the end of the global
  // cooldown (or its own) goes off the moment it can
  spellQueueWindow: DB.spellQueueWindow,
  // being hit while casting sets the cast bar back (WoW Classic's pushback)
  castPushback: DB.castPushback,
  maxPushbacks: DB.maxPushbacks,
  armourTypes: DB.armourTypes,
  archetypes: DB.archetypes,
  // each enemy's numbers from its level and type (src/data/scaling.js)
  enemies: {
    ...Object.fromEntries(Object.entries(DB.enemies).map(([id, e]) => [id, scaledEnemy(e, CONFIG.stats, tuning('strike').abilityWeaponSeconds)])),
    leashDistance: DB.leashDistance,
  },
  scaling: SCALING,
});

export function xpForNextLevel(level) {
  return CONFIG.progression.firstLevelXp + (level - 1) * CONFIG.progression.xpGrowthPerLevel;
}
