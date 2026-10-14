import * as THREE from 'three';
import { DB } from '../data/db.js';
import { ITEMS } from '../data/items.js';
import { BUTTONS } from '../core/gamepad.js';
import { QuestLog, MAX_TRACKED } from '../systems/quests.js';

// The quest side of the HUD: the dialogue window, the quest log (L), the
// tracked objectives under the minimap, and the ! and ? over townsfolk.
// Like the bags, none of these pause the game.
//
// Gamepad: in the dialogue window up and down pick a choice, A takes it and
// B goes back. In the quest log up and down pick a quest, X tracks or
// untracks it, Y abandons it (press twice), and B closes.

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const MARK = { ready: '?', available: '!', active: '?' };
const OPTION_ICON = { ready: '?', available: '!', active: '?', talk: '&#10077;', shop: '&#9878;', bye: '&#10005;', accept: '&#10003;', back: '&#8617;' };

export class QuestUI {
  constructor(game, hud) {
    this.game = game;
    this.hud = hud;
    this.logOpen = false;
    this.selected = null; // quest shown in the log
    this.choice = 0; // gamepad highlight in the dialogue window
    this.confirmAbandon = null;
    this.marks = new Map(); // npc id -> element
    this.tmp = new THREE.Vector3();
    this.el = {
      dialogue: $('dialogue-window'),
      dlgName: $('dlg-name'),
      dlgTitle: $('dlg-title'),
      dlgHead: $('dlg-qhead'),
      dlgText: $('dlg-text'),
      dlgQuest: $('dlg-quest'),
      dlgOptions: $('dlg-options'),
      dlgHint: $('dlg-hint'),
      log: $('questlog-window'),
      logList: $('ql-list'),
      logDetail: $('ql-detail'),
      logCount: $('ql-count'),
      logHint: $('ql-hint'),
      tracker: $('objective'),
      marks: $('npc-marks'),
    };

    $('dlg-close').addEventListener('click', () => game.dialogue.close());
    $('ql-close').addEventListener('click', () => this.toggleLog(false));
    $('btn-quests').addEventListener('click', () => this.toggleLog());
    this.el.dlgOptions.addEventListener('click', (e) => {
      const b = e.target.closest('[data-option]');
      if (b) game.dialogue.choose(b.dataset.option);
    });
    this.el.logList.addEventListener('click', (e) => {
      const b = e.target.closest('[data-quest]');
      if (b) this.select(b.dataset.quest);
    });
    this.el.logDetail.addEventListener('click', (e) => {
      const b = e.target.closest('[data-act]');
      if (!b) return;
      if (b.dataset.act === 'track') game.quests.setTracked(this.selected, !game.quests.tracked.has(this.selected));
      if (b.dataset.act === 'abandon') this.abandon();
    });
    // tracked quests open in the log when clicked, as in WoW
    this.el.tracker.addEventListener('click', (e) => {
      const b = e.target.closest('[data-quest]');
      if (b) {
        this.selected = b.dataset.quest;
        this.toggleLog(true);
      }
    });

    const ev = game.events;
    ev.on('dialogueChanged', () => {
      this.choice = 0;
      this.renderDialogue();
    });
    ev.on('questsChanged', () => this.render());
    ev.on('inventoryChanged', () => this.game.dialogue.isOpen && this.renderDialogue());
  }

  get anyOpen() {
    return this.logOpen || this.game.dialogue.isOpen;
  }

  closeAll() {
    const was = this.anyOpen;
    this.game.dialogue.close();
    this.toggleLog(false);
    return was;
  }

  toggleLog(on = !this.logOpen) {
    this.logOpen = on;
    this.confirmAbandon = null;
    if (on && (!this.selected || !this.game.quests.active.includes(this.selected))) this.selected = this.game.quests.active[0] || null;
    this.renderLog();
  }

  select(id) {
    this.selected = id;
    this.confirmAbandon = null;
    this.renderLog();
  }

  abandon() {
    const id = this.selected;
    if (!id) return;
    if (DB.quests[id].autoAccept) {
      this.game.events.emit('log', { text: 'That is the road you are on. It cannot be abandoned.', kind: 'muted', throttle: 'abandon' });
      return;
    }
    if (this.confirmAbandon !== id) {
      this.confirmAbandon = id;
      this.renderLog();
      return;
    }
    this.game.quests.abandon(id);
    this.selected = this.game.quests.active[0] || null;
    this.confirmAbandon = null;
    this.renderLog();
  }

  render() {
    this.renderTracker();
    this.renderLog();
    if (this.game.dialogue.isOpen) this.renderDialogue();
  }

  // ------------------------------------------------------------ pieces
  _objectivesHTML(objs) {
    return `<ul class="q-objectives">${objs.map((o) => `<li class="${o.done ? 'done' : ''}">${esc(QuestLog.line(o))}</li>`).join('')}</ul>`;
  }

  _rewardHTML(r) {
    const parts = [];
    if (r.coins) parts.push(`<span class="q-reward"><span class="coin-dot"></span>${r.coins} coins</span>`);
    if (r.xp) parts.push(`<span class="q-reward">${r.xp} experience</span>`);
    for (const g of r.items || []) {
      const def = ITEMS[g.item];
      const icon = this.hud.items.icons[def.model];
      parts.push(`<span class="q-reward q-item q-${def.quality}">${icon ? `<img src="${icon}" alt="">` : ''}${esc(def.name)}${(g.count || 1) > 1 ? ` ×${g.count}` : ''}</span>`);
    }
    return parts.length ? `<div class="q-sub">Rewards</div><div class="q-rewards">${parts.join('')}</div>` : '';
  }

  // ---------------------------------------------------------- dialogue
  renderDialogue() {
    const page = this.game.dialogue.page;
    this.el.dialogue.hidden = !page;
    if (!page) return;
    this.el.dlgName.textContent = page.name;
    this.el.dlgTitle.textContent = page.title;
    this.el.dlgText.textContent = page.text;
    const q = page.quest;
    if (q) {
      const head = q.status === 'ready' ? 'Ready to hand in' : q.status === 'available' ? 'New quest' : 'In progress';
      this.el.dlgHead.innerHTML = `<div class="q-name">${esc(q.name)}</div><div class="q-state ${q.status}">${head}</div>`;
      this.el.dlgQuest.innerHTML = `<div class="q-sub">Objectives</div>${this._objectivesHTML(q.objectives)}${this._rewardHTML(q.reward)}`;
    } else {
      this.el.dlgHead.innerHTML = '';
      this.el.dlgQuest.innerHTML = '';
    }
    this.el.dlgHead.hidden = this.el.dlgQuest.hidden = !q;
    this.choice = Math.min(this.choice, page.options.length - 1);
    this.el.dlgOptions.innerHTML = page.options
      .map((o, i) => `<button class="dlg-option ${o.icon}${this.hud.padMode && i === this.choice ? ' focus' : ''}" data-option="${esc(o.id)}"><span class="dlg-icon">${OPTION_ICON[o.icon] || ''}</span>${esc(o.text)}</button>`)
      .join('');
    this.el.dlgHint.textContent = this.hud.padMode ? 'A: choose   B: back' : 'Click a choice. Esc or walking away ends the conversation.';
  }

  // --------------------------------------------------------- quest log
  renderLog() {
    const ql = this.game.quests;
    this.el.log.hidden = !this.logOpen;
    if (!this.logOpen) return;
    const active = ql.active;
    this.el.logCount.textContent = `${active.length} in hand · ${ql.done.size} done`;
    this.el.logList.innerHTML = active.length
      ? active
          .map((id) => {
            const s = ql.status(id);
            return `<button class="ql-row${id === this.selected ? ' sel' : ''}" data-quest="${id}"><span class="ql-track">${ql.tracked.has(id) ? '&#9670;' : ''}</span>${esc(DB.quests[id].name)}${s === 'ready' ? ' <span class="ql-ready">(Complete)</span>' : ''}</button>`;
          })
          .join('')
      : '<p class="dim small">No quests in hand. Look for a <b class="mark-avail">!</b> over someone\'s head.</p>';
    const id = this.selected;
    if (!id || !active.includes(id)) {
      this.el.logDetail.innerHTML = ql.done.size ? `<div class="q-sub">Completed</div>${[...ql.done].map((d) => `<div class="dim small">${esc(DB.quests[d].name)}</div>`).join('')}` : '';
    } else {
      const q = DB.quests[id];
      const s = ql.status(id);
      const turnIn = DB.npcs[q.turnIn].name;
      const tracked = ql.tracked.has(id);
      this.el.logDetail.innerHTML =
        `<div class="q-name">${esc(q.name)}</div>` +
        `<p class="q-summary">${esc(q.summary)}</p>` +
        `<div class="q-sub">Objectives</div>${this._objectivesHTML(ql.objectives(id))}` +
        (s === 'ready' ? `<p class="ql-ready">Return to ${esc(turnIn)}.</p>` : `<p class="dim small">Hand in to ${esc(turnIn)}.</p>`) +
        this._rewardHTML(q.reward || {}) +
        `<div class="ql-actions"><button class="btn small" data-act="track">${tracked ? 'Untrack' : 'Track'}</button>` +
        (q.autoAccept ? '' : `<button class="btn small${this.confirmAbandon === id ? ' danger' : ''}" data-act="abandon">${this.confirmAbandon === id ? 'Really abandon?' : 'Abandon'}</button>`) +
        '</div>';
    }
    this.el.logHint.textContent = this.hud.padMode
      ? `Up/down: choose   X: track (up to ${MAX_TRACKED})   Y: abandon   B: close`
      : `Tracked quests (up to ${MAX_TRACKED}) show under the map. L or Esc closes.`;
  }

  // ---------------------------------------------------- tracked quests
  renderTracker() {
    const ql = this.game.quests;
    const ids = ql.active.filter((id) => ql.tracked.has(id));
    this.el.tracker.hidden = ids.length === 0;
    this.el.tracker.innerHTML = ids
      .map((id) => {
        const q = DB.quests[id];
        const s = ql.status(id);
        const body =
          s === 'ready'
            ? `<div class="tr-ready">Return to ${esc(DB.npcs[q.turnIn].name)}</div>`
            : `<ul class="q-objectives">${ql
                .objectives(id)
                .map((o) => `<li class="${o.done ? 'done' : ''}">${esc(QuestLog.line(o))}</li>`)
                .join('')}</ul>`;
        return `<div class="tr-quest ${s}" data-quest="${id}"><div class="tr-name">${esc(q.name)}${s === 'ready' ? ' <span class="tr-tag">Complete</span>' : ''}</div>${body}</div>`;
      })
      .join('');
  }

  // ------------------------------------------------- ! and ? over heads
  updateMarks() {
    const { npcs, camera, renderer, quests } = this.game;
    const w = renderer.domElement.clientWidth;
    const h = renderer.domElement.clientHeight;
    for (const n of npcs.list) {
      const status = quests.markerFor(n.id);
      let el = this.marks.get(n.id);
      if (!el) {
        el = document.createElement('div');
        el.className = 'npc-mark';
        this.el.marks.appendChild(el);
        this.marks.set(n.id, el);
      }
      if (!status) {
        el.style.display = 'none';
        continue;
      }
      if (el.dataset.status !== status) {
        el.dataset.status = status;
        el.textContent = MARK[status];
        el.className = 'npc-mark ' + status;
      }
      this.tmp.set(n.position.x, n.position.y + 2.55, n.position.z).project(camera);
      const visible = this.tmp.z < 1 && Math.abs(this.tmp.x) < 1.05 && Math.abs(this.tmp.y) < 1.05;
      el.style.display = visible ? '' : 'none';
      el.style.transform = `translate(${((this.tmp.x + 1) / 2) * w}px, ${((1 - this.tmp.y) / 2) * h}px) translate(-50%, -100%)`;
    }
  }

  // --------------------------------------------------------- gamepad
  // Returns true while the quest windows have the pad.
  gamepad(pad, dt) {
    const dlg = this.game.dialogue;
    if (dlg.isOpen) {
      const page = dlg.page;
      const dir = pad.navDirection(dt);
      if (dir === 'up') this.choice = (this.choice + page.options.length - 1) % page.options.length;
      if (dir === 'down') this.choice = (this.choice + 1) % page.options.length;
      if (dir) this.renderDialogue();
      if (pad.pressed(BUTTONS.A)) dlg.choose(page.options[this.choice].id);
      else if (pad.pressed(BUTTONS.B)) dlg.back();
      return true;
    }
    if (this.logOpen) {
      const list = this.game.quests.active;
      const dir = pad.navDirection(dt);
      if ((dir === 'up' || dir === 'down') && list.length) {
        const i = list.indexOf(this.selected);
        this.select(list[(i + (dir === 'up' ? list.length - 1 : 1)) % list.length]);
      }
      if (pad.pressed(BUTTONS.X) && this.selected) this.game.quests.setTracked(this.selected, !this.game.quests.tracked.has(this.selected));
      if (pad.pressed(BUTTONS.Y)) this.abandon();
      if (pad.pressed(BUTTONS.B)) this.toggleLog(false);
      return true;
    }
    return false;
  }
}
