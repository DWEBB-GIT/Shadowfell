import { DB } from '../data/db.js';
import { ENEMIES } from '../world/layout.js';

// Quests, WoW style (data/quests.json). A quest is offered by its giver once
// the quests it requires are done, accepted into the quest log, and handed in
// to its turn-in npc once every objective is met.
//
// Progress is read from the world rather than counted separately: kills from
// the defeated enemies (enemies do not respawn, so one slain before the quest
// was taken still counts), items from the bags, examine points from what has
// been looked at. Only what the player chose is stored: accepted, done and
// tracked quests.
//
// Status of a quest: 'done' | 'ready' (all objectives met) | 'active' |
// 'available' (can be accepted now) | 'locked'.

export const MAX_TRACKED = 4;

const typeOfSpawn = Object.fromEntries(ENEMIES.map((e) => [e.id, e.type]));

export class QuestLog {
  constructor(game) {
    this.game = game;
    this.reset();
    const refresh = () => this.refresh();
    for (const ev of ['enemyDefeated', 'inventoryChanged', 'examined', 'levelUp']) game.events.on(ev, refresh);
  }

  reset() {
    this.accepted = []; // quest ids, in the order taken
    this.done = new Set();
    this.tracked = new Set();
    this._last = {}; // questId -> progress text, to announce changes
  }

  // A brand-new game takes the opening quest (the intro sets it).
  startNew() {
    this.reset();
    for (const q of Object.values(DB.quests)) if (q.autoAccept && this.status(q.id) === 'available') this.accept(q.id, { quiet: true });
    this._snapshot();
  }

  // ------------------------------------------------------------ state
  status(id) {
    const q = DB.quests[id];
    if (!q) return 'locked';
    if (this.done.has(id)) return 'done';
    if (this.accepted.includes(id)) return this.objectives(id).every((o) => o.done) ? 'ready' : 'active';
    return (q.requires || []).every((r) => this.done.has(r)) ? 'available' : 'locked';
  }

  // Each objective with how far along it is: { id, label, have, need, done, location }
  objectives(id) {
    const { worldState, inventory } = this.game;
    return DB.quests[id].objectives.map((o) => {
      const need = o.count || 1;
      let have = 0;
      if (o.type === 'kill') have = [...worldState.defeated].filter((s) => typeOfSpawn[s] === o.target).length;
      else if (o.type === 'collect') have = inventory.count(o.target);
      else if (o.type === 'examine') have = worldState.examined.has(o.target) ? 1 : 0;
      have = Math.min(have, need);
      return { id: o.id, type: o.type, label: o.label, have, need, done: have >= need, location: o.location || null };
    });
  }

  // "Barrow Hounds slain: 2/3", or the bare label for one-off objectives
  static line(o) {
    return o.need > 1 || o.type === 'kill' ? `${o.label}: ${o.have}/${o.need}` : o.label;
  }

  get active() {
    return this.accepted.filter((id) => !this.done.has(id));
  }

  // The quests an npc has something to say about, best first:
  // ready to hand in, then new ones to offer, then ones still in hand.
  forNpc(npcId) {
    const out = [];
    for (const q of Object.values(DB.quests)) {
      const s = this.status(q.id);
      if (s === 'ready' && q.turnIn === npcId) out.push({ id: q.id, status: s });
      else if (s === 'available' && q.giver === npcId) out.push({ id: q.id, status: s });
      else if (s === 'active' && q.turnIn === npcId) out.push({ id: q.id, status: s });
    }
    const order = { ready: 0, available: 1, active: 2 };
    return out.sort((a, b) => order[a.status] - order[b.status]);
  }

  // What floats over an npc: '?' gold to hand in, '!' gold to take, '?' grey in hand.
  markerFor(npcId) {
    const list = this.forNpc(npcId);
    return list.length ? list[0].status : null;
  }

  // ---------------------------------------------------------- actions
  accept(id, { quiet = false } = {}) {
    if (this.status(id) !== 'available') return false;
    const q = DB.quests[id];
    this.accepted.push(id);
    if (this.tracked.size < MAX_TRACKED) this.tracked.add(id);
    this._last[id] = this._text(id);
    if (!quiet) {
      this.game.events.emit('log', { text: `Quest accepted: ${q.name}.`, kind: 'quest' });
      this.game.hud?.toast(`Quest accepted: ${q.name}`);
    }
    this.game.events.emit('questAccepted', { id });
    this._changed();
    return true;
  }

  abandon(id) {
    if (this.status(id) !== 'active' && this.status(id) !== 'ready') return false;
    if (DB.quests[id].autoAccept) return false; // the story quest cannot be dropped
    this.accepted = this.accepted.filter((q) => q !== id);
    this.tracked.delete(id);
    delete this._last[id];
    this.game.events.emit('log', { text: `Quest abandoned: ${DB.quests[id].name}.`, kind: 'muted' });
    this._changed();
    return true;
  }

  // Hand the quest in: take collected items, pay the reward. Returns false
  // (and says why) if it cannot be done yet.
  complete(id) {
    const { inventory, progression, events, worldState } = this.game;
    if (this.status(id) !== 'ready') return false;
    const q = DB.quests[id];
    const r = q.reward || {};
    const gifts = r.items || [];
    if (gifts.some((g) => inventory.roomFor(g.item) < (g.count || 1))) {
      events.emit('log', { text: 'Make room in your bags for the reward first.', kind: 'muted', throttle: 'quest-room' });
      return false;
    }
    for (const o of q.objectives) if (o.type === 'collect' && !o.keep) inventory.removeCount(o.target, o.count || 1);
    this.done.add(id);
    this.tracked.delete(id);
    delete this._last[id];
    if (q.setsFlag) worldState.flags.add(q.setsFlag);
    if (q.turnInLog) events.emit('log', { text: q.turnInLog, kind: 'lore' });
    events.emit('log', { text: `Quest complete: ${q.name}.`, kind: 'quest' });
    if (r.coins) inventory.addCoins(r.coins, `from ${DB.npcs[q.turnIn].name}`);
    for (const g of gifts) inventory.addItem(g.item, g.count || 1);
    if (r.xp) progression.addXp(r.xp);
    if (r.reputation) this.game.reputation.addAll(r.reputation);
    this.game.hud?.toast(`Quest complete: ${q.name}`);
    events.emit('questComplete', { id });
    this._changed();
    return true;
  }

  setTracked(id, on) {
    if (!this.active.includes(id)) return false;
    if (on && this.tracked.size >= MAX_TRACKED && !this.tracked.has(id)) {
      this.game.events.emit('log', { text: `You can track up to ${MAX_TRACKED} quests.`, kind: 'muted', throttle: 'track-max' });
      return false;
    }
    if (on) this.tracked.add(id);
    else this.tracked.delete(id);
    this._changed();
    return true;
  }

  // ---------------------------------------------------- progress news
  _text(id) {
    return this.objectives(id).map((o) => `${o.have}/${o.need}`).join(' ');
  }

  _snapshot() {
    this._last = Object.fromEntries(this.active.map((id) => [id, this._text(id)]));
  }

  // Called when anything a quest counts may have moved. Announces each
  // objective that advanced, and a quest that has become ready.
  refresh() {
    let changed = false;
    for (const id of this.active) {
      const now = this._text(id);
      if (now === this._last[id]) continue;
      const before = (this._last[id] || '').split(' ');
      this._last[id] = now;
      changed = true;
      const objs = this.objectives(id);
      objs.forEach((o, i) => {
        const was = before[i] ? +before[i].split('/')[0] : 0;
        if (o.have > was) this.game.events.emit('log', { text: QuestLog.line(o) + (o.done ? ' (done)' : ''), kind: 'quest' });
      });
      if (objs.every((o) => o.done)) {
        const q = DB.quests[id];
        this.game.events.emit('log', { text: `${q.name}: complete. Return to ${DB.npcs[q.turnIn].name}.`, kind: 'quest' });
        this.game.hud?.toast(`${q.name}: complete`);
      }
    }
    if (changed) this._changed();
  }

  _changed() {
    this.game.events.emit('questsChanged', {});
    this.game.events.emit('objectiveChanged', {});
  }

  // ------------------------------------------------------------- save
  serialize() {
    return { accepted: [...this.accepted], done: [...this.done], tracked: [...this.tracked] };
  }

  // Saves from before the quest log carry only the story flag.
  apply(data, flags) {
    this.reset();
    if (data) {
      const known = (id) => !!DB.quests[id];
      this.done = new Set(data.done.filter(known));
      this.accepted = data.accepted.filter((id) => known(id) && !this.done.has(id));
      this.tracked = new Set(data.tracked.filter((id) => this.accepted.includes(id)));
    } else if (flags && flags.has('manifest_delivered')) {
      this.done.add('missing_delivery');
    } else {
      this.accepted.push('missing_delivery');
      this.tracked.add('missing_delivery');
    }
    this._snapshot();
    this._changed();
  }
}

// Conditions in dialogue data: { quest, status } | { flag } | { examined }.
export function conditionHolds(game, when) {
  if (!when) return true;
  if (when.quest) {
    const s = game.quests.status(when.quest);
    const status = s === 'locked' || s === 'available' ? (when.status === 'not_started' ? 'not_started' : s) : s;
    if (status !== when.status) return false;
  }
  if (when.flag && !game.worldState.flags.has(when.flag)) return false;
  if (when.examined && !game.worldState.examined.has(when.examined)) return false;
  return true;
}
