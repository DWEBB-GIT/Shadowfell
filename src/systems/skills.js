import { freeSlot } from './actionBar.js';
import { moneyText } from '../ui/money.js';
import { DB } from '../data/db.js';

// Skills learned from trainers (data/skills.json): camping and fishing. A
// skill unlocks the abilities it `teaches` (they appear in the spellbook and
// can go on the bar). Skills with a `maxRank` rise with use, as WoW's
// professions do: fishing goes up by one with each catch.

export class Skills {
  constructor(game) {
    this.game = game;
    this.ranks = new Map(); // skill id -> rank (1 when learned)
  }

  reset() {
    this.ranks = new Map();
  }

  has(id) {
    return this.ranks.has(id);
  }

  rank(id) {
    return this.ranks.get(id) || 0;
  }

  // May the Warrior use this ability? Abilities with no `skill` always.
  knowsAbility(ability) {
    const a = DB.abilities[ability];
    return !!a && (!a.skill || this.has(a.skill));
  }

  // What a trainer offers that the Warrior has not learned.
  offeredBy(npcId) {
    return Object.values(DB.skills).filter((s) => s.trainer === npcId && !this.has(s.id));
  }

  // Pay the trainer and learn; false (with a word why) if it cannot be done.
  learn(id) {
    const s = DB.skills[id];
    const { inventory, events, actionBar, hud } = this.game;
    if (!s || this.has(id)) return false;
    if (inventory.coins < s.cost) {
      events.emit('log', { text: `You need ${moneyText(s.cost)} to learn ${s.name}.`, kind: 'muted', throttle: 'train-coins' });
      return false;
    }
    inventory.loseCoins(s.cost);
    this.ranks.set(id, 1);
    // what it teaches goes onto an empty slot of the bar, if there is one
    for (const ab of s.teaches || []) {
      const free = freeSlot(actionBar.slots);
      if (free >= 0) actionBar.place(ab, free);
    }
    const names = (s.teaches || []).map((ab) => DB.abilities[ab].name).join(' and ');
    events.emit('log', { text: `You learn ${s.name}.${names ? ` ${names} is under Professions (U).` : ''}`, kind: 'level' });
    hud?.toast(`Learned: ${s.name}`);
    events.emit('skillsChanged', { id });
    return true;
  }

  // One step up a skill that rises with use (up to its maxRank).
  raise(id) {
    const s = DB.skills[id];
    if (!s || !s.maxRank || !this.has(id) || this.rank(id) >= s.maxRank) return false;
    this.ranks.set(id, this.rank(id) + 1);
    this.game.events.emit('log', { text: `Your skill in ${s.name} rises to ${this.rank(id)}.`, kind: 'level' });
    this.game.events.emit('skillsChanged', { id });
    return true;
  }

  serialize() {
    return Object.fromEntries(this.ranks);
  }

  apply(data) {
    this.reset();
    for (const [id, r] of Object.entries(data || {})) if (DB.skills[id] && Number.isInteger(r) && r >= 1) this.ranks.set(id, Math.min(r, DB.skills[id].maxRank || 1));
  }
}
