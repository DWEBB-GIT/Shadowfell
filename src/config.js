// Tunable values from the design document (section 9.7 and onwards).
// Gameplay code reads numbers from here only, so balance passes stay in one file.

export const CONFIG = {
  player: {
    archetype: 'warden',
    speed: 5.0, // metres per second
    radius: 0.4,
    startCoins: 8,
    startDraughts: 1,
  },
  attack: {
    range: 2.1, // centre-to-centre reach of a sword strike
    coneDegrees: 110, // targets must sit roughly in front of the swing
    cooldown: 0.6,
    windup: 0.16, // seconds between click and impact
  },
  shieldBreak: {
    damageMultiplier: 2, // 18 -> 36 with the starting sword
    radius: 2.8,
    cooldown: 4.0,
    windup: 0.28,
    stagger: 0.7,
    knockback: 1.6,
  },
  globalCooldown: 1.5, // shared by Shield Break and Lunge, as in classic WoW
  lunge: {
    damageMultiplier: 1.5,
    distance: 5.0,
    duration: 0.26,
    cooldown: 8.0,
    hitRadius: 1.6, // enemies this close to the end of the lunge are struck
  },
  // The defensive button (Space). Each archetype brings its own; the
  // Warden's is Brace: raise the shield and turn aside the next blow.
  brace: {
    cooldown: 7.0,
    window: 2.5, // seconds the shield stays up waiting for a hit
  },
  draught: {
    heal: 42,
    cooldown: 1.0,
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
  // Armour types: heavier types carry more armour; each archetype may wear
  // only some of them (as in WoW). Shields are their own kind (off hand).
  armourTypes: {
    cloth: { name: 'Cloth' },
    leather: { name: 'Leather' },
    mail: { name: 'Mail' },
    plate: { name: 'Plate' },
  },
  // Each archetype: base attributes at level 1, gains per level, the main
  // attribute that feeds its damage, the armour it may wear, whether it can
  // use a shield, its resource and its defensive ability.
  archetypes: {
    warden: {
      name: 'Warden',
      mainStat: 'might',
      base: { might: 4, finesse: 2, intellect: 1, vitality: 10, armour: 0, resistance: 0, block: 0, blockRating: 0, haste: 0 },
      perLevel: { might: 2, vitality: 2 },
      armourTypes: ['cloth', 'leather', 'mail', 'plate'],
      shields: true,
      resource: null, // casters would have 'mana', rogues 'energy'
      defensive: 'brace',
    },
  },
  enemies: {
    ghoul: {
      name: 'Ashen Ghoul',
      model: 'ghoul',
      level: 1,
      health: 48,
      damage: 11, // before the player's armour
      armour: 0,
      crit: 5,
      attackInterval: 1.35,
      windup: 0.45,
      detection: 8,
      meleeRange: 1.25,
      speed: 3.0,
      radius: 0.45,
      xp: 28,
      coins: 3,
      elite: false,
    },
    brute: {
      name: 'Gravebound Brute',
      model: 'brute',
      level: 3,
      health: 96,
      damage: 17,
      armour: 10,
      crit: 5,
      attackInterval: 1.05,
      windup: 0.5,
      detection: 8,
      meleeRange: 1.25,
      speed: 2.6,
      radius: 0.75,
      xp: 65,
      coins: 9,
      elite: true,
      telegraph: true, // its normal swing is marked on the ground
      special: {
        name: 'Grave Slam',
        windup: 1.4, // long, readable ground telegraph
        cooldown: 7.0,
        trigger: 3.4, // used when the player is this close
        range: 4.2,
        arc: 110, // degrees
        damage: 31, // cannot crit or be blocked; only Brace stops it
      },
    },
    leashDistance: 18, // give up and return home beyond this distance from home
  },
  interaction: {
    radius: 2.2,
  },
  fog: { color: 0x3a4244, near: 14, far: 40 }, // linear view-distance fog, in metres from the camera
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


export function xpForNextLevel(level) {
  return CONFIG.progression.firstLevelXp + (level - 1) * CONFIG.progression.xpGrowthPerLevel;
}
