import { CONFIG } from '../config.js';
import { DB } from '../data/db.js';
import { conditionHolds } from './quests.js';

// Talking to townsfolk, in the WoW gossip style: a greeting with its choices
// grouped and marked by kind (Dan, 2026-10-16: each action clear at a
// glance): quests (! and ?), things to ask, then services (the shop, the
// trainer, the inn) and Goodbye. A quest opens its own page: the offer with
// objectives and rewards and Accept, or the hand-in with Complete quest.
// Topics open small dialogue trees from data/dialogue.json. Training opens
// the trainer window (view 'train'): every skill and recipe this person
// teaches, with what it needs and costs. The shop and the trainer window
// both have Back, to the greeting.
//
// This system owns where the conversation is; the HUD (questUI) shows it and
// passes choices back. Walking away ends it, as with a shop.

export class Dialogue {
  constructor(game) {
    this.game = game;
    this.npc = null; // the Npc spoken to
    this.view = null; // { kind: 'menu' } | { kind: 'node', id } | { kind: 'quest', id } | { kind: 'train' }
  }

  get isOpen() {
    return !!this.npc;
  }

  open(npc) {
    this.game.merchant.close();
    this.npc = npc;
    this.view = { kind: 'menu' };
    // how they hail you: "Hey you!" while you are nobody, your title once
    // you have chosen one (the notice board says nothing)
    this.salutation = DB.npcs[npc.id].board ? '' : this.game.titles.address('greetings');
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

  // Everything this person teaches, for the trainer window:
  // [{ id: 'train:x' | 'recipe:y', name, kind, icon, need, cost, state }],
  // state 'learn' | 'known' | 'locked' (with `need` saying why).
  trainRows(npcId = this.npc?.id) {
    const { skills, cooking, inventory } = this.game;
    const rows = [];
    for (const s of Object.values(DB.skills).filter((x) => x.trainer === npcId)) {
      const known = skills.has(s.id);
      rows.push({ id: 'train:' + s.id, name: s.name, kind: 'Skill', ability: (s.teaches || [])[0], desc: s.desc, need: known ? '' : 'Teaches a new skill', cost: s.cost, state: known ? 'known' : inventory.coins < s.cost ? 'poor' : 'learn' });
    }
    for (const r of Object.values(DB.recipes).filter((x) => x.trainer === npcId)) {
      const skill = DB.skills[r.skill];
      const known = cooking.learned.has(r.id);
      const locked = !skills.has(r.skill) ? `Requires ${skill.name}` : cooking.rank(r.skill) < r.rank ? `Requires ${skill.name} ${r.rank}` : '';
      rows.push({ id: 'recipe:' + r.id, name: DB.items[r.output.item].name, kind: `${skill.name} recipe`, item: r.output.item, need: locked || `${skill.name} ${r.rank}`, cost: r.cost, state: known ? 'known' : locked ? 'locked' : inventory.coins < r.cost ? 'poor' : 'learn' });
    }
    return rows;
  }

  // What the window shows now: { name, title, text, quest?, options: [{ id, text, icon, group }] }
  get page() {
    if (!this.npc) return null;
    const npc = DB.npcs[this.npc.id];
    const page = { name: npc.name, title: npc.title || '', text: '', options: [] };
    const v = this.view;
    const d = this._data;
    if (v.kind === 'menu') {
      const greet = d ? d.greetings.filter((g) => conditionHolds(this.game, g.when)) : [];
      page.text = greet.length ? greet[greet.length - 1].text : '';
      page.salutation = this.salutation;
      for (const q of this.game.quests.forNpc(this.npc.id)) {
        page.options.push({ id: 'quest:' + q.id, text: DB.quests[q.id].name, icon: q.status, group: 'quest' });
      }
      for (const t of d ? d.topics || [] : []) {
        if (conditionHolds(this.game, t.when)) page.options.push({ id: 'node:' + t.node, text: t.prompt, icon: 'talk', group: 'talk' });
      }
      if (npc.shop) page.options.push({ id: 'shop', text: 'Browse goods', icon: 'shop', group: 'service' });
      // a trainer: one way in to the trainer window, saying what is new
      const rows = this.trainRows();
      if (rows.length) {
        const n = rows.filter((r) => r.state === 'learn' || r.state === 'poor').length;
        page.options.push({ id: 'train', text: n ? `Train (${n} to learn)` : 'Train', icon: 'train', group: 'service' });
      }
      if (npc.innkeeper && this.game.worldState.restPoint !== 'inn:' + this.npc.id) page.options.push({ id: 'home', text: 'Make this inn your home', icon: 'home', group: 'service' });
      page.options.push({ id: 'bye', text: 'Goodbye', icon: 'bye', group: 'bye' });
    } else if (v.kind === 'train') {
      page.train = this.trainRows();
      page.text = page.train.some((r) => r.state === 'learn') ? 'What would you learn?' : 'There is nothing more I can teach you just now.';
      for (const r of page.train) page.options.push({ id: r.id, text: r.name, icon: 'train', disabled: r.state !== 'learn' });
      page.options.push({ id: 'menu', text: 'Back', icon: 'back' });
    } else if (v.kind === 'node') {
      const node = d.nodes.find((n) => n.id === v.id);
      page.text = node.text;
      node.replies.forEach((r) => page.options.push({ id: r.node ? 'node:' + r.node : 'menu', text: r.text, icon: 'talk' }));
    } else if (v.kind === 'quest') {
      const q = DB.quests[v.id];
      const status = this.game.quests.status(v.id);
      page.quest = { id: q.id, name: q.name, status, objectives: this.game.quests.objectives(q.id), reward: q.reward || {}, choice: !!q.choice };
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
    if (id === 'bye') {
      if (!DB.npcs[this.npc.id].board) events.emit('log', { text: `${DB.npcs[this.npc.id].name}: "${this.game.titles.address('farewells')}"`, kind: 'say' });
      return this.close();
    }
    if (id === 'menu') this.view = { kind: 'menu' };
    else if (id === 'train') this.view = { kind: 'train' };
    else if (id === 'shop') {
      const npc = this.npc;
      this.close();
      merchant.open(DB.npcs[npc.id].shop, npc);
      return true;
    } else if (id.startsWith('train:')) {
      if (!this.game.skills.learn(id.slice(6))) return false;
    } else if (id.startsWith('recipe:')) {
      if (!this.game.cooking.learnRecipe(id.slice(7))) return false;
    } else if (id === 'home') {
      this.game.worldState.restPoint = 'inn:' + this.npc.id;
      events.emit('log', { text: `${DB.npcs[this.npc.id].name} keeps a bed for you. If you fall, you will wake at the inn.`, kind: 'heal' });
      this.game.hud.toast('This inn is now your home');
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
