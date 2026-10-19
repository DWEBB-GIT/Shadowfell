import { DB } from '../data/db.js';

// Titles, Fable style (data/titles.json). You start a nobody, and townsfolk
// greet you with "Hello there." or "Hey you!". Renown, kept with reputation
// (systems/reputation.js), says how known you are; once it (and a title's own
// conditions, such as a fishing rank) allows it, you
// may choose a title in the character window, and NPCs then call you by it:
// "Hello, Master Angler.", "Farewell, Adventurer.", now and then mockingly.

export class Titles {
  constructor(game) {
    this.game = game;
    this.reset();
    const ev = game.events;
    ev.on('enemyDefeated', ({ enemy }) => this._slay(enemy.type, enemy.cfg));
    ev.on('dummyBeaten', ({ enemy }) => this._slay(enemy.type, enemy.cfg));
    for (const e of ['skillsChanged', 'reputationChanged']) ev.on(e, () => this._checkNew());
  }

  reset() {
    this.chosen = null; // title id, or null for none
    this.slain = new Set(); // enemy types beaten at least once
    this.known = new Set(); // titles already announced as available
  }

  _slay(type, cfg) {
    if (this.slain.has(type)) return;
    this.slain.add(type);
    if (cfg.elite) this.game.reputation.addRenown(DB.renown.firstEliteKill, `for felling the ${cfg.name}`);
    this._checkNew();
  }

  // Why a title cannot be chosen yet ('' when it can).
  lockedBecause(id) {
    const t = DB.titles[id];
    const { skills, reputation, quests, progression } = this.game;
    if (reputation.renown < t.renown) return `Requires ${t.renown} renown`;
    for (const r of t.requires || []) {
      if (r.skill && skills.rank(r.skill) < r.rank) return `Requires ${DB.skills[r.skill].name} ${r.rank}`;
      if (r.slain && !this.slain.has(r.slain)) return `Defeat ${DB.enemies[r.slain].name}`;
      if (r.faction) {
        const need = DB.standings.findIndex((s) => s.id === r.standing);
        if (DB.standings.findIndex((s) => s.id === reputation.standing(r.faction).id) < need) return `Requires ${DB.standings[need].name} with ${DB.factions[r.faction].name}`;
      }
      if (r.quest && !quests.done.has(r.quest)) return `Complete ${DB.quests[r.quest].name}`;
      if (r.level && progression.level < r.level) return `Requires level ${r.level}`;
    }
    return '';
  }

  available(id) {
    return !!DB.titles[id] && !this.lockedBecause(id);
  }

  // every title in data order: { id, name, desc, locked, chosen }
  get list() {
    return Object.entries(DB.titles).map(([id, t]) => ({ id, name: t.name, desc: t.desc, locked: this.lockedBecause(id), chosen: this.chosen === id }));
  }

  // the chosen title's name, or '' for none
  get name() {
    return this.chosen ? DB.titles[this.chosen].name : '';
  }

  choose(id) {
    if (id && !this.available(id)) return false;
    this.chosen = id || null;
    this.game.events.emit('log', { text: id ? `You are now known as ${this.name}.` : 'You go without a title.', kind: 'level' });
    this.game.events.emit('titlesChanged', {});
    return true;
  }

  _checkNew() {
    for (const id of Object.keys(DB.titles)) {
      if (this.known.has(id) || !this.available(id)) continue;
      this.known.add(id);
      this.game.events.emit('log', { text: `New title available: ${DB.titles[id].name}. Choose it in the character window (Titles).`, kind: 'level' });
      this.game.hud?.toast(`Title available: ${DB.titles[id].name}`);
      this.game.events.emit('titlesChanged', {});
    }
  }

  // What an NPC calls out: kind 'greetings' or 'farewells'. Untitled folk get
  // a plain line; a title is used, and sometimes mocked.
  address(kind) {
    const lines = DB.titleLines[kind];
    const pick = (list) => list[Math.floor(Math.random() * list.length) % list.length];
    if (!this.chosen) return pick(lines.untitled);
    const t = DB.titles[this.chosen];
    const mock = Math.random() < (t.mock ?? DB.mockChance);
    const line = !mock ? pick(lines.titled) : kind === 'greetings' && t.mocks?.length && Math.random() < 0.5 ? pick(t.mocks) : pick(lines.mocking);
    return line.replaceAll('{title}', t.name);
  }

  serialize() {
    return { chosen: this.chosen, slain: [...this.slain], known: [...this.known] };
  }

  apply(data) {
    this.reset();
    if (!data) return;
    this.slain = new Set((data.slain || []).filter((id) => DB.enemies[id]));
    this.known = new Set((data.known || []).filter((id) => DB.titles[id]));
    this.chosen = data.chosen && DB.titles[data.chosen] ? data.chosen : null;
  }
}
