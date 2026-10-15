import { DB } from '../data/db.js';

// Reputation, WoW style: points with each faction (data/factions.json),
// earned from quests and from what the Warden does in a faction's area
// (killing the dead on the road earns the Road Wardens' thanks). Standings
// are named tiers; a faction's vendors give a discount from Friendly up.
// Reputation-gated stock and places will read `standing()` later.

export class Reputation {
  constructor(game) {
    this.game = game;
    this.points = {};
  }

  reset() {
    this.points = {};
  }

  get(id) {
    return this.points[id] || 0;
  }

  // the standing tier for a faction, plus progress through it
  standing(id) {
    const tiers = DB.standings;
    const p = this.get(id);
    let i = 0;
    while (i + 1 < tiers.length && p >= tiers[i + 1].min) i++;
    const tier = tiers[i];
    const next = tiers[i + 1];
    return { ...tier, points: p, into: p - tier.min, span: next ? next.min - tier.min : 0, next: next ? next.name : null };
  }

  // percent off at this faction's vendors
  discount(id) {
    return id ? this.standing(id).discount : 0;
  }

  add(id, n, { quiet = false } = {}) {
    const f = DB.factions[id];
    if (!f || !n) return;
    const before = this.standing(id).id;
    this.points[id] = this.get(id) + n;
    if (!quiet) this.game.events.emit('log', { text: `Reputation with ${f.name} ${n > 0 ? 'increased' : 'decreased'} by ${Math.abs(n)}.`, kind: 'rep' });
    const after = this.standing(id);
    if (after.id !== before) {
      this.game.events.emit('log', { text: `You are now ${after.name} with ${f.name}.`, kind: 'level' });
      this.game.hud.toast(`${f.name}: ${after.name}`);
    }
    this.game.events.emit('reputationChanged', { id });
  }

  addAll(map, opts) {
    for (const [id, n] of Object.entries(map || {})) this.add(id, n, opts);
  }

  serialize() {
    return { ...this.points };
  }

  apply(data) {
    this.points = {};
    for (const [id, n] of Object.entries(data || {})) if (DB.factions[id] && Number.isFinite(n)) this.points[id] = n;
  }
}
