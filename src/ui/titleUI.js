import { TITLE, INTRO } from '../data/text.js';
import { BUILD_LABEL } from '../buildInfo.js';
import { BUTTONS } from '../core/gamepad.js';
import { regionAt } from '../world/layout.js';
import { tidyName } from '../systems/characters.js';

// The title screen, character select and character creation (alpha).
// One modal with three views; mouse, keyboard and gamepad all drive it.
// Every view keeps a list of controls marked data-nav: the D-pad, the left
// stick or the arrow keys move between them, and A / Enter / Space presses
// the one in focus. B / Esc goes back.

const $ = (id) => document.getElementById(id);
const CLASSES = TITLE.classes;
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

function ago(t) {
  const s = Math.max(0, (Date.now() - t) / 1000);
  if (s < 90) return 'just now';
  if (s < 5400) return `${Math.round(s / 60)} minutes ago`;
  if (s < 129600) return `${Math.round(s / 3600)} hours ago`;
  return `${Math.round(s / 86400)} days ago`;
}

export class TitleScreen {
  constructor(game) {
    this.game = game;
    this.view = null;
    this.selected = null; // character id on the select screen
    this.classId = CLASSES.find((c) => c.archetype).id;
    this.confirmDelete = false;
    this.focusEl = null;
    this.stickWait = 0;
    this.note = '';

    $('title-tagline').textContent = TITLE.tagline;
    $('title-build').textContent = TITLE.build;
    $('title-foot-build').textContent = `Shadowfall ${TITLE.build}`;
    $('title-version').textContent = BUILD_LABEL;
    $('intro-text').textContent = INTRO;

    const on = (id, fn) => $(id).addEventListener('click', fn);
    on('continue-btn', () => this.game.roster.last && this.game.enterWorld(this.game.roster.last));
    on('chars-btn', () => this.show('select'));
    on('new-btn', () => this.show('create'));
    on('controls-btn', () => {
      const c = $('title-controls');
      c.hidden = !c.hidden;
    });
    on('create-new-btn', () => this.show('create'));
    on('select-back', () => this.back());
    on('enter-btn', () => this.enterSelected());
    on('delete-btn', () => this.askDelete());
    on('delete-no', () => this.cancelDelete());
    on('delete-yes', () => this.doDelete());
    on('create-back', () => this.back());
    on('create-confirm', () => this.create());
    on('name-random', () => this.randomName());
    const name = $('char-name');
    name.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') this.create();
      else if (e.key === 'Escape') name.blur();
      else return;
      e.preventDefault();
    });
    name.addEventListener('input', () => ($('create-error').textContent = ''));
    name.addEventListener('focus', () => (this.focusEl = name));

    $('title-screen').addEventListener('mousemove', (e) => {
      const el = e.target.closest('[data-nav]');
      if (el && this._navList().includes(el) && el !== this.focusEl && document.activeElement !== $('char-name')) this.focus(el, { fromMouse: true });
    });
  }

  get isOpen() {
    return this.view !== null;
  }

  // ------------------------------------------------------------ views
  open({ note = '', view = 'main' } = {}) {
    this.note = note;
    this.game.hud.modal = 'title';
    $('title-screen').hidden = false;
    $('hud').hidden = true;
    this.show(view === 'select' && this.game.roster.list.length ? 'select' : 'main');
  }

  close() {
    $('title-screen').hidden = true;
    this.view = null;
  }

  show(view) {
    this.view = view;
    this.confirmDelete = false;
    for (const v of ['main', 'select', 'create']) $(`title-${v}`).hidden = v !== view;
    $('title-screen').classList.toggle('showcase', view !== 'main');
    if (view === 'main') this._renderMain();
    if (view === 'select') this._renderSelect();
    if (view === 'create') this._renderCreate();
    this._labels();
  }

  back() {
    if (this.view === 'select' && this.confirmDelete) return this.cancelDelete();
    if (this.view === 'create' && this.game.roster.list.length) return this.show('select');
    if (this.view !== 'main') this.show('main');
  }

  // ------------------------------------------------------------- main
  _renderMain() {
    const roster = this.game.roster;
    const last = roster.byId(roster.last);
    const info = last && this.info(last);
    const canContinue = !!(info && info.ok);
    $('continue-btn').hidden = !canContinue;
    $('continue-who').textContent = canContinue ? `${last.name} · level ${info.level} ${this.className(last)}` : '';
    $('chars-btn').hidden = !roster.list.length;
    let note = this.note;
    const broken = roster.list.find((c) => !this.info(c).ok);
    if (!note && broken) note = `${broken.name}'s save could not be read. It has been kept aside and will not be overwritten.`;
    $('title-note').textContent = note;
    $('title-note').hidden = !note;
    this.focus(canContinue ? $('continue-btn') : $('new-btn'));
  }

  // ------------------------------------------------------------ select
  info(c) {
    const r = this.game.save.read(c.key);
    if (r.status === 'ok') {
      const d = r.data;
      return { ok: true, level: d.progression.level, where: regionAt(d.player.position.z).name };
    }
    if (r.status === 'none') return { ok: true, level: 1, where: 'Not yet set out' };
    return { ok: false, level: '?', where: 'Save unreadable' };
  }

  className(c) {
    return (CLASSES.find((k) => k.id === c.classId) || CLASSES[0]).name;
  }

  _renderSelect() {
    const roster = this.game.roster;
    if (!roster.byId(this.selected)) this.selected = roster.last || roster.list[0]?.id || null;
    // most recently played first
    const list = [...roster.list].sort((a, b) => b.lastPlayed - a.lastPlayed);
    $('char-count').textContent = `${roster.list.length} of ${roster.max}`;
    $('char-list').innerHTML = list
      .map((c) => {
        const i = this.info(c);
        return `<button class="char-card${i.ok ? '' : ' broken'}" data-nav data-char="${esc(c.id)}">
          <span class="cc-name">${esc(c.name)}</span>
          <span class="cc-line">Level ${i.level} ${esc(this.className(c))}</span>
          <span class="cc-where">${esc(i.where)}</span>
        </button>`;
      })
      .join('');
    $('char-list').querySelectorAll('.char-card').forEach((b) => {
      b.addEventListener('click', () => this.select(b.dataset.char));
      b.addEventListener('dblclick', () => this.enterSelected());
    });
    $('create-new-btn').disabled = roster.full;
    $('delete-confirm').hidden = true;
    this.select(this.selected);
  }

  select(id) {
    this.selected = id;
    const c = this.game.roster.byId(id);
    $('char-list').querySelectorAll('.char-card').forEach((b) => b.classList.toggle('selected', b.dataset.char === id));
    const i = c && this.info(c);
    $('sel-name').textContent = c ? c.name : '';
    $('sel-line').textContent = c ? `Level ${i.level} ${this.className(c)} · ${i.where} · played ${ago(c.lastPlayed)}` : 'No characters yet';
    $('enter-btn').disabled = !c || !i.ok;
    $('delete-btn').disabled = !c;
    const card = $('char-list').querySelector(`[data-char="${id}"]`);
    this.focus(card || $('create-new-btn'));
  }

  enterSelected() {
    const c = this.game.roster.byId(this.selected);
    if (c && this.info(c).ok) this.game.enterWorld(c.id);
  }

  askDelete() {
    const c = this.game.roster.byId(this.selected);
    if (!c) return;
    this.confirmDelete = true;
    $('delete-text').textContent = `Delete ${c.name}? Their save is removed from this browser and cannot be brought back.`;
    $('delete-confirm').hidden = false;
    this.focus($('delete-no'));
  }

  cancelDelete() {
    this.confirmDelete = false;
    $('delete-confirm').hidden = true;
    this.focus($('delete-btn'));
  }

  doDelete() {
    this.game.roster.remove(this.selected);
    this.selected = null;
    if (this.game.roster.list.length) this.show('select');
    else this.show('main');
  }

  // ------------------------------------------------------------ create
  _renderCreate() {
    $('class-list').innerHTML = CLASSES.map(
      (c) => `<button class="class-card${c.archetype ? '' : ' locked'}" data-nav data-class="${esc(c.id)}">
        <span class="cc-name">${esc(c.name)}</span><span class="cc-line">${c.archetype ? esc(c.role) : 'Coming later'}</span>
      </button>`,
    ).join('');
    $('class-list').querySelectorAll('.class-card').forEach((b) => b.addEventListener('click', () => this.pickClass(b.dataset.class)));
    this.pickClass(this.classId, false);
    const roster = this.game.roster;
    $('create-error').textContent = roster.full ? `You can keep ${roster.max} characters. Delete one to make room.` : '';
    $('create-confirm').disabled = roster.full;
    if (!$('char-name').value || roster.nameProblem($('char-name').value)) $('char-name').value = roster.randomName(this.game.random);
    this.focus($('create-confirm'));
  }

  pickClass(id, focus = true) {
    const c = CLASSES.find((k) => k.id === id);
    $('class-list').querySelectorAll('.class-card').forEach((b) => b.classList.toggle('selected', b.dataset.class === id));
    $('class-detail').innerHTML = `<div class="cd-head"><span class="cd-name">${esc(c.name)}</span><span class="cd-role">${esc(c.role)}</span></div>
      <p>${esc(c.blurb)}</p>
      <ul>${c.traits.map((t) => `<li>${esc(t)}</li>`).join('')}</ul>
      ${c.archetype ? '' : '<div class="cd-locked">This class arrives in a later build.</div>'}`;
    if (c.archetype) this.classId = id;
    $('create-confirm').disabled = !c.archetype || this.game.roster.full;
    if (focus) this.focus($('class-list').querySelector(`[data-class="${id}"]`));
  }

  randomName() {
    $('char-name').value = this.game.roster.randomName();
    $('create-error').textContent = '';
  }

  create() {
    const cls = CLASSES.find((k) => k.id === this.classId);
    if (!cls || !cls.archetype) return;
    const r = this.game.roster.create(tidyName($('char-name').value), cls.id);
    if (!r.ok) {
      $('create-error').textContent = r.reason;
      return;
    }
    $('char-name').value = '';
    this.game.enterWorld(r.character.id);
  }

  // ------------------------------------------------------------ focus and input
  _navList() {
    const view = $(`title-${this.view}`);
    if (!view) return [];
    const scope = this.view === 'select' && this.confirmDelete ? $('delete-confirm') : view;
    return [...scope.querySelectorAll('[data-nav]')].filter((el) => !el.disabled && el.offsetParent !== null && !(this.view === 'select' && !this.confirmDelete && el.closest('#delete-confirm')));
  }

  focus(el, { fromMouse = false } = {}) {
    if (!el) return;
    this.focusEl = el;
    document.querySelectorAll('#title-screen .nav-focus').forEach((x) => x.classList.remove('nav-focus'));
    el.classList.add('nav-focus');
    if (!fromMouse && el.tagName !== 'INPUT') el.focus({ preventScroll: true });
    if (!fromMouse) el.scrollIntoView?.({ block: 'nearest' });
    // moving onto a character or a class shows it
    if (el.dataset.char && el.dataset.char !== this.selected && !fromMouse) this.select(el.dataset.char);
    if (el.dataset.class && !fromMouse) this.pickClass(el.dataset.class, false);
  }

  move(step) {
    const list = this._navList();
    if (!list.length) return;
    let i = list.indexOf(this.focusEl);
    i = i < 0 ? 0 : (i + step + list.length) % list.length;
    this.focus(list[i]);
  }

  press() {
    const el = this.focusEl;
    if (!el || el.disabled) return;
    if (el.tagName === 'INPUT') return this.create();
    if (el.dataset.char) return this.enterSelected(); // A on a character plays them
    el.click();
  }

  _labels() {
    const pad = this.game.hud.padMode;
    document.querySelectorAll('#title-screen .key-hint').forEach((k) => (k.textContent = pad ? k.dataset.pad : k.dataset.kbm));
  }

  // Called each frame while the title is open, before anything else reads input.
  update(dt) {
    const { input, pad } = this.game;
    if (this._pad !== this.game.hud.padMode) {
      this._pad = this.game.hud.padMode;
      this._labels();
    }
    if (document.activeElement === $('char-name')) return; // typing a name
    const up = input.consume('ArrowUp') || input.consume('ArrowLeft') || pad.pressed(BUTTONS.UP) || pad.pressed(BUTTONS.LEFT);
    const down = input.consume('ArrowDown') || input.consume('ArrowRight') || input.consume('Tab') || pad.pressed(BUTTONS.DOWN) || pad.pressed(BUTTONS.RIGHT);
    // the left stick moves too, repeating while held
    const sy = pad.left?.m > 0.5 ? pad.left.y : 0;
    this.stickWait -= dt;
    if (!sy) this.stickWait = 0;
    else if (this.stickWait <= 0) {
      this.move(sy > 0 ? 1 : -1);
      this.stickWait = 0.22;
    }
    if (up) this.move(-1);
    if (down) this.move(1);
    if (input.consume('Enter') || input.consume('Space') || pad.pressed(BUTTONS.A)) this.press();
    if (input.consume('Escape') || pad.pressed(BUTTONS.B)) this.back();
    if (pad.pressed(BUTTONS.Y) || input.consume('Delete')) {
      if (this.view === 'select' && !this.confirmDelete) this.askDelete();
      else if (this.view === 'create') this.randomName();
    }
  }
}
