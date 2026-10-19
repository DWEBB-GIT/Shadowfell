import { DB } from '../data/db.js';

// Reputation, WoW style: points with each faction (data/factions.json),
// earned from quests and from what the Warden does in a faction's area
// (killing the dead on the road earns the Road Wardens' thanks). Standings
// are named tiers; a faction's vendors give a discount from Friendly up.
// Reputation-gated stock and places will read `standing()` later.
//
// Renown (Fable style, factions.json `renown`) is the standing that spans
// every faction: how known you are at all. It grows with quests done, levels
// gained, first elite kills and every bit of faction reputation earned, and
// titles (systems/titles.js) unlock from it.

export class Reputation {
  constructor(game) {
    this.game = game;
    this.reset();
    game.events.on('questComplete', () => this.addRenown(DB.renown.perQuest, 'for your deeds'));
    game.events.on('levelUp', () => this.addRenown(DB.renown.perLevel, 'as you grow in strength'));
  }

  reset() {
    this.points = {};
    this.renown = 0;
    this.carry = 0; // reputation earned toward the next point of renown
  }

  // how known you are: { id, name, desc, min, next, into, span }
  get renownTier() {
    const tiers = DB.renown.tiers;
    let i = 0;
    while (i + 1 < tiers.length && this.renown >= tiers[i + 1].min) i++;
    const next = tiers[i + 1];
    return { ...tiers[i], next: next ? next.name : null, into: this.renown - tiers[i].min, span: next ? next.min - tiers[i].min : 0 };
  }

  addRenown(n, why = '') {
    if (!n) return;
    const before = this.renownTier.id;
    this.renown += n;
    const { events, hud } = this.game;
    events.emit('log', { text: `Your renown grows by ${n}${why ? ' ' + why : ''}.`, kind: 'rep' });
    const t = this.renownTier;
    if (t.id !== before) {
      events.emit('log', { text: `You are now ${t.name}. ${t.desc}`, kind: 'level' });
      hud?.toast(`Renown: ${t.name}`);
    }
    events.emit('reputationChanged', { id: 'renown' });
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
    // word spreads: reputation earned with anyone adds to renown
    if (n > 0) {
      this.carry += n;
      const whole = Math.floor(this.carry / DB.renown.perReputation);
      this.carry -= whole * DB.renown.perReputation;
      if (whole) this.addRenown(whole, 'as word of you spreads');
    }
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

  serializeRenown() {
    return { points: this.renown, carry: this.carry };
  }

  apply(data, renown) {
    this.points = {};
    for (const [id, n] of Object.entries(data || {})) if (DB.factions[id] && Number.isFinite(n)) this.points[id] = n;
    this.renown = renown?.points || 0;
    this.carry = renown?.carry || 0;
  }
}
