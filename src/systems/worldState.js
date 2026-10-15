// Persistent facts about the world, keyed by stable ids so a save written
// today still means the same thing after the layout is tweaked.

export class WorldState {
  constructor(game) {
    this.game = game;
    this.reset();
  }

  reset() {
    this.defeated = new Set();
    this.collected = new Set();
    this.examined = new Set();
    this.drops = {}; // itemId -> { x, z } for loot dropped by enemies
    this.shrineActivated = null; // shrine id or null
    this.respawn = null; // { x, z } or null (falls back to the road's start)
    this.ground = []; // items the player dropped: { uid, id, count, x, z }
    this.corpses = {}; // enemyId -> { x, z, coins } for bodies not yet looted
    this.nextGroundUid = 1;
    this.flags = new Set(); // story facts, e.g. 'manifest_delivered'
    this.camp = null; // { x, z } of the Warden's camp, if one is pitched
    this.restPoint = 'shrine'; // where the spirit rises: 'camp' or 'shrine' (the last rested at)
    this.nemesis = null; // the enemy spawn id that last killed the Warden
  }

  isDefeated(id) {
    return this.defeated.has(id);
  }

  markDefeated(id) {
    this.defeated.add(id);
  }

  isCollected(id) {
    return this.collected.has(id);
  }

  markCollected(id) {
    this.collected.add(id);
    delete this.drops[id];
  }

  get manifestCollected() {
    return this.collected.has('manifest');
  }

  serialize() {
    return {
      defeated: [...this.defeated],
      collected: [...this.collected],
      examined: [...this.examined],
      drops: { ...this.drops },
      shrineActivated: this.shrineActivated,
      respawn: this.respawn ? { ...this.respawn } : null,
      manifestCollected: this.manifestCollected,
      ground: this.ground.map((g) => ({ ...g })),
      corpses: Object.fromEntries(Object.entries(this.corpses).map(([k, v]) => [k, { ...v }])),
      flags: [...this.flags],
      camp: this.camp ? { ...this.camp } : null,
      restPoint: this.restPoint,
      nemesis: this.nemesis,
    };
  }

  apply(data) {
    this.defeated = new Set(data.defeated);
    this.collected = new Set(data.collected);
    this.examined = new Set(data.examined);
    this.drops = { ...data.drops };
    this.shrineActivated = data.shrineActivated;
    this.respawn = data.respawn ? { ...data.respawn } : null;
    this.ground = (data.ground || []).map((g) => ({ ...g }));
    this.corpses = Object.fromEntries(Object.entries(data.corpses || {}).map(([k, v]) => [k, { ...v }]));
    this.nextGroundUid = this.ground.reduce((m, g) => Math.max(m, g.uid + 1), 1);
    this.flags = new Set(Array.isArray(data.flags) ? data.flags.filter((f) => typeof f === 'string') : []);
    this.camp = data.camp ? { ...data.camp } : null;
    this.restPoint = data.restPoint === 'camp' && this.camp ? 'camp' : 'shrine';
    this.nemesis = typeof data.nemesis === 'string' ? data.nemesis : null;
  }
}
