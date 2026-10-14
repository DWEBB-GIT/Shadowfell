import { DB } from '../data/db.js';

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

  // Where a quest has got to: the last of its stages (data/quests.json)
  // whose condition holds. The first stage has none.
  questStage(questId) {
    const q = DB.quests[questId];
    let stage = q.stages[0];
    for (const s of q.stages) if (s.when && this._holds(s.when)) stage = s;
    return stage;
  }

  _holds(when) {
    if (when.examined && !this.examined.has(when.examined)) return false;
    if (when.collected && !this.collected.has(when.collected)) return false;
    if (when.flag && !this.flags.has(when.flag)) return false;
    return true;
  }

  // the objective shown on the HUD: the story's quest
  get objectiveQuest() {
    return DB.quests.missing_delivery;
  }

  get objectiveStage() {
    return this.questStage(this.objectiveQuest.id).id;
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
  }
}
