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
    coinLossFraction: 0.2,
    coinLossCap: 5,
    screenDelay: 1.3,
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
    fistDamage: [1, 3],
  },
  interaction: {
    radius: 2.2,
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
    range: 26, // a hard lock (Tab / R3) considers enemies this close
    dropRange: 34, // a locked target further away than this is let go
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
