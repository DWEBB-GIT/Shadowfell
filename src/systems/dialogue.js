import { moneyText } from '../ui/money.js';
import { CONFIG } from '../config.js';
import { DB } from '../data/db.js';
import { conditionHolds } from './quests.js';

// Talking to townsfolk, in the WoW gossip style: a greeting with a list of
// choices (quests first, then things to ask, the shop, and Goodbye). A quest
// opens its own page: the offer with objectives and rewards and Accept, or
// the hand-in with Complete quest. Topics open small dialogue trees from
// data/dialogue.json.
//
// This system owns where the conversation is; the HUD (questUI) shows it and
// passes choices back. Walking away ends it, as with a shop.

export class Dialogue {
  constructor(game) {
    this.game = game;
    this.npc = null; // the Npc spoken to
    this.view = null; // { kind: 'menu' } | { kind: 'node', id } | { kind: 'quest', id }
  }

  get isOpen() {
    return !!this.npc;
  }

  open(npc) {
    this.game.merchant.close();
    this.npc = npc;
    this.view = { kind: 'menu' };
    this.game.events.emit('dialogueChanged', {});
  }

  close() {
    if (!this.npc) return false;
    this.npc = null;
    this.view = null;
    this.game.events.emit('dialogueChanged', {});
    return true;
  }

  back() {
    if (!this.npc) return false;
    if (this.view.kind === 'menu') return this.close();
    this.view = { kind: 'menu' };
    this.game.events.emit('dialogueChanged', {});
    return true;
  }

  update() {
    if (!this.npc) return;
    const p = this.game.player.position;
    if (this.game.player.dead || Math.hypot(p.x - this.npc.position.x, p.z - this.npc.position.z) > CONFIG.shop.leaveRange) this.close();
  }

  get _data() {
    const id = this.npc && DB.npcs[this.npc.id].dialogue;
    return id ? DB.dialogues[id] : null;
  }

  // What the window shows now: { name, title, text, quest?, options: [{ id, text, icon }] }
  get page() {
    if (!this.npc) return null;
    const npc = DB.npcs[this.npc.id];
    const page = { name: npc.name, title: npc.title || '', text: '', options: [] };
    const v = this.view;
    const d = this._data;
    if (v.kind === 'menu') {
      const greet = d ? d.greetings.filter((g) => conditionHolds(this.game, g.when)) : [];
      page.text = greet.length ? greet[greet.length - 1].text : '';
      for (const q of this.game.quests.forNpc(this.npc.id)) {
        page.options.push({ id: 'quest:' + q.id, text: DB.quests[q.id].name, icon: q.status });
      }
      for (const t of d ? d.topics || [] : []) {
        if (conditionHolds(this.game, t.when)) page.options.push({ id: 'node:' + t.node, text: t.prompt, icon: 'talk' });
      }
      // trainers offer what they teach and the Warden has not learned
      for (const s of this.game.skills.offeredBy(this.npc.id)) page.options.push({ id: 'train:' + s.id, text: `Teach me ${s.name} (${moneyText(s.cost)}).`, icon: 'train' });
      if (npc.shop) page.options.push({ id: 'shop', text: 'Let me see your wares.', icon: 'shop' });
      page.options.push({ id: 'bye', text: 'Goodbye.', icon: 'bye' });
    } else if (v.kind === 'node') {
      const node = d.nodes.find((n) => n.id === v.id);
      page.text = node.text;
      node.replies.forEach((r) => page.options.push({ id: r.node ? 'node:' + r.node : 'menu', text: r.text, icon: 'talk' }));
    } else if (v.kind === 'quest') {
      const q = DB.quests[v.id];
      const status = this.game.quests.status(v.id);
      page.quest = { id: q.id, name: q.name, status, objectives: this.game.quests.objectives(q.id), reward: q.reward || {} };
      if (status === 'available') {
        page.text = q.offer;
        page.options.push({ id: 'accept', text: 'Accept', icon: 'accept' }, { id: 'menu', text: 'Decline', icon: 'back' });
      } else if (status === 'ready') {
        page.text = q.complete;
        page.options.push({ id: 'complete', text: 'Complete quest', icon: 'accept' }, { id: 'menu', text: 'Back', icon: 'back' });
      } else {
        page.text = q.progress;
        page.options.push({ id: 'menu', text: 'Back', icon: 'back' });
      }
    }
    return page;
  }

  // Act on an option id from `page.options`.
  choose(id) {
    if (!this.npc) return false;
    const { quests, merchant, events } = this.game;
    const v = this.view;
    if (id === 'bye') return this.close();
    if (id === 'menu') this.view = { kind: 'menu' };
    else if (id === 'shop') {
      const npc = this.npc;
      this.close();
      merchant.open(DB.npcs[npc.id].shop, npc);
      return true;
    } else if (id.startsWith('train:')) {
      if (!this.game.skills.learn(id.slice(6))) return false;
    } else if (id.startsWith('quest:')) this.view = { kind: 'quest', id: id.slice(6) };
    else if (id.startsWith('node:')) this.view = { kind: 'node', id: id.slice(5) };
    else if (id === 'accept' && v.kind === 'quest') {
      if (!quests.accept(v.id)) return false;
      this.view = { kind: 'menu' };
    } else if (id === 'complete' && v.kind === 'quest') {
      if (!quests.complete(v.id)) return false;
      this.view = { kind: 'menu' };
    } else return false;
    events.emit('dialogueChanged', {});
    return true;
  }
}
