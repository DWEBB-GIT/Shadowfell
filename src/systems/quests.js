import { DB } from '../data/db.js';
import { rollCoins } from '../ui/money.js';
import { ENEMIES } from '../world/layout.js';

// Quests, WoW style (data/quests.json). A quest is offered by its giver once
// the quests it requires are done, accepted into the quest log, and handed in
// to its turn-in npc once every objective is met.
//
// Kills are counted per quest from the moment it is taken (WoW): most
// enemies respawn, so the world's list of the fallen cannot be the count.
// Items are read from the bags and examine points from what has been looked
// at. Stored: accepted, done and tracked quests, and the kill counts.
//
// A `talk` objective (go and speak to the turn-in npc) is met at once: the
// quest is handed in by finding them. Quests sharing a `choice` are one
// decision: once one of them is taken (or done) the others are locked, so
// the Warden's word sticks.
//
// Status of a quest: 'done' | 'ready' (all objectives met) | 'active' |
// 'available' (can be accepted now) | 'locked'.

export const MAX_TRACKED = 4;

export class QuestLog {
  constructor(game) {
    this.game = game;
    this.reset();
    const refresh = () => this.refresh();
    for (const ev of ['inventoryChanged', 'examined', 'levelUp']) game.events.on(ev, refresh);
    game.events.on('enemyDefeated', ({ enemy }) => {
      this.countKill(enemy.type);
      this.refresh();
    });
  }

  reset() {
    this.accepted = []; // quest ids, in the order taken
    this.done = new Set();
    this.tracked = new Set();
    this.kills = {}; // questId -> { objectiveId: kills since it was taken }
    this._last = {}; // questId -> progress text, to announce changes
  }

  // An enemy of this type fell: every active quest that wants it counts one.
  countKill(type) {
    for (const id of this.active) {
      for (const o of DB.quests[id].objectives) {
        if (o.type !== 'kill' || o.target !== type) continue;
        const k = (this.kills[id] ||= {});
        k[o.id] = Math.min(o.count || 1, (k[o.id] || 0) + 1);
      }
    }
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
    if (q.choice && this.chosen(q.choice)) return 'locked';
    return (q.requires || []).every((r) => this.done.has(r)) ? 'available' : 'locked';
  }

  // The quest taken (or done) for a choice, or null while it is still open.
  chosen(choice) {
    return [...this.accepted, ...this.done].find((id) => DB.quests[id]?.choice === choice) || null;
  }

  // Each objective with how far along it is: { id, label, have, need, done, location }
  objectives(id) {
    const { worldState, inventory } = this.game;
    return DB.quests[id].objectives.map((o) => {
      const need = o.count || 1;
      let have = 0;
      if (o.type === 'kill') have = this.kills[id]?.[o.id] || 0;
      else if (o.type === 'collect') have = inventory.count(o.target);
      else if (o.type === 'examine') have = worldState.examined.has(o.target) ? 1 : 0;
      else if (o.type === 'talk') have = need;
      have = Math.min(have, need);
      return { id: o.id, type: o.type, label: o.label, have, need, done: have >= need, location: o.location || null };
    });
  }

  // Does a quest the player has taken still need this item? (a quest drop
  // only falls while it does)
  needsItem(id, item) {
    if (this.status(id) !== 'active') return false;
    return this.objectives(id).some((o, i) => !o.done && DB.quests[id].objectives[i].type === 'collect' && DB.quests[id].objectives[i].target === item);
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
    delete this.kills[id];
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
    delete this.kills[id];
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
    delete this.kills[id];
    if (q.setsFlag) worldState.flags.add(q.setsFlag);
    if (q.turnInLog) events.emit('log', { text: q.turnInLog, kind: 'lore' });
    events.emit('log', { text: `Quest complete: ${q.name}.`, kind: 'quest' });
    const coins = rollCoins(r.coins, this.game.random);
    if (coins) inventory.addCoins(coins, `from ${DB.npcs[q.turnIn].name}`);
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
    return { accepted: [...this.accepted], done: [...this.done], tracked: [...this.tracked], kills: JSON.parse(JSON.stringify(this.kills)) };
  }

  // Saves from before the quest log carry only the story flag.
  apply(data, flags) {
    this.reset();
    if (data) {
      const known = (id) => !!DB.quests[id];
      this.done = new Set(data.done.filter(known));
      this.accepted = data.accepted.filter((id) => known(id) && !this.done.has(id));
      this.tracked = new Set(data.tracked.filter((id) => this.accepted.includes(id)));
      // kill counts; a save from before them counts the bodies still down
      const typeOf = Object.fromEntries(ENEMIES.map((e) => [e.id, e.type]));
      const fallen = [...this.game.worldState.defeated].map((s) => typeOf[s]);
      for (const id of this.accepted) {
        const saved = data.kills ? data.kills[id] : Object.fromEntries(DB.quests[id].objectives.map((o) => [o.id, fallen.filter((t) => t === o.target).length]));
        if (!saved || typeof saved !== 'object') continue;
        for (const o of DB.quests[id].objectives) {
          const n = saved[o.id];
          if (o.type === 'kill' && Number.isInteger(n) && n > 0) (this.kills[id] ||= {})[o.id] = Math.min(n, o.count || 1);
        }
      }
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
