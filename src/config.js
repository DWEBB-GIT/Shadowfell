// Engine tuning: the numbers that shape how the game plays and looks.
// Content (items, enemies, abilities, quests, the world...) lives in /data;
// see src/data/db.js. For convenience CONFIG also exposes the archetypes,
// enemies and ability tuning from there under their old names, so gameplay
// code reads every number from one place.

import { DB } from './data/db.js';

export const CONFIG = {
  player: {
    archetype: 'warden',
    speed: 5.0, // metres per second
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
    biteMin: 3, // seconds before a bite, at least...
    biteMax: 9, // ...and at most
    biteWindow: 1.4, // how long the bob stays under: strike now
    baseChance: 65, // percent chance to land it on a timely strike...
    chancePerRank: 0.6, // ...plus this per rank of Fishing (bait adds its own)
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
  // hit: base x multiplier, then crit, then armour or resistance, then block.
  stats: {
    healthBase: 40,
    healthPerVitality: 6,
    manaPerIntellect: 10,
    powerPerMainStat: 1, // flat damage added to every weapon hit
    spellPowerPerIntellect: 1,
    critBase: 5, // percent
    critPerFinesse: 0.5,
    critMultiplier: 1.5,
    // reduction = armour / (armour + armourConstant + armourPerLevel x attacker
    // level), as in WoW and Diablo III: armour keeps its worth as levels rise
    armourConstant: 40,
    armourPerLevel: 10,
    mitigationCap: 75, // percent
    blockCap: 50, // percent
    blockRatingPerPercent: 10, // 10 block rating = +1% block chance
    blockReduction: 30, // a block stops this % of the blow (Brace stops all of it)
    hasteCap: 30, // percent; haste divides swing time, windups, casts and the GCD
    gcdFloor: 1.0, // seconds: haste never takes the global cooldown below this
    enemyVariance: 0.15, // enemy blows land within +-15% of their damage
    fistDamage: [3, 10], // bare hands, per swing
    fistSpeed: 2.0, // seconds between bare-handed swings
  },
  interaction: {
    radius: 2.2,
  },
  // how a landed blow feels: a short hit-stop on both bodies, a camera kick
  impact: {
    hitStop: 0.07, // seconds; crits hold longer
    shake: 0.07, // metres of camera kick
    critShake: 0.16,
    shakeDecay: 9, // per second
  },
  fog: { color: 0x3a4244, near: 14, far: 40 }, // linear view-distance fog, in metres from the camera
  // the Blackwood closes in: nearer, darker fog and dimmer light under the pines
  blackwood: { fogColor: 0x1d2725, fogNear: 9, fogFar: 32, light: 0.68 },
  camera: {
    offset: [0, 11, 10],
    fov: 45,
    followSharpness: 8, // higher = tighter follow
    renderScale: 0.62, // chunky, period-appropriate pixels
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
    reach: 3.2, // how close the Warden must be to loot by clicking
  },
};


// content from /data, under the names gameplay code uses
const tuning = (id) => DB.abilities[id].tuning;
Object.assign(CONFIG, {
  attack: tuning('strike'),
  shieldBreak: tuning('shieldBreak'),
  lunge: tuning('lunge'),
  brace: tuning('brace'),
  draught: tuning('draught'),
  globalCooldown: DB.globalCooldown,
  armourTypes: DB.armourTypes,
  archetypes: DB.archetypes,
  enemies: { ...DB.enemies, leashDistance: DB.leashDistance },
});

export function xpForNextLevel(level) {
  return CONFIG.progression.firstLevelXp + (level - 1) * CONFIG.progression.xpGrowthPerLevel;
}
