import { KEY_ACTIONS, keyLabel, comboOf } from '../systems/keybinds.js';

// The key bindings list in the Settings window, plus Quick bind: while it is
// on, hovering a spell or utility bar slot and pressing a key binds it there.

export class KeybindUI {
  constructor(game, hud) {
    this.game = game;
    this.hud = hud;
    this.waiting = null; // action id waiting for a key
    this.quick = false;
    this.hovered = null; // bar slot index under the mouse during Quick bind
    const list = document.getElementById('keybind-list');
    list.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-bind]');
      if (b) this.listen(b.dataset.bind);
    });
    document.getElementById('quick-bind').addEventListener('click', () => this.setQuick(!this.quick));
    document.getElementById('keys-reset').addEventListener('click', () => game.keys.resetAll());
    document.addEventListener('mouseover', (e) => {
      const slot = e.target.closest && e.target.closest('.aslot');
      this.hovered = slot ? +slot.dataset.loc.slice(2) : null;
    });
    game.events.on('keysChanged', () => {
      this.render();
      hud._applyKeyLabels();
    });
  }

  render() {
    const keys = this.game.keys;
    let html = '';
    let group = '';
    for (const a of KEY_ACTIONS) {
      if (a.group !== group) html += `<div class="kb-group">${(group = a.group)}</div>`;
      const label = this.waiting === a.id ? 'Press a key…' : keys.label(a.id) || 'Not bound';
      html += `<div class="kb-row"><span>${a.label}</span><button class="btn small${this.waiting === a.id ? ' waiting' : ''}" data-bind="${a.id}">${label}</button></div>`;
    }
    document.getElementById('keybind-list').innerHTML = html;
    document.getElementById('quick-bind').classList.toggle('on', this.quick);
  }

  // wait for the next key and bind it (Escape cancels, Backspace unbinds)
  listen(id) {
    this.waiting = id;
    this.render();
    this.game.input.capture = (e) => {
      if (e.code.startsWith('Shift')) return; // a modifier: wait for the key it goes with
      this.game.input.capture = null;
      this.waiting = null;
      const code = comboOf(e);
      if (e.code === 'Backspace') this.game.keys.unbind(id);
      else if (e.code !== 'Escape' && !this.game.keys.bind(id, code)) this.hud.error(`${keyLabel(code)} cannot be bound`);
      this.render();
    };
  }

  setQuick(on) {
    this.quick = on;
    document.body.classList.toggle('quick-bind', on);
    document.getElementById('quick-bind-banner').hidden = !on;
    this.render();
    this.game.input.capture = on
      ? (e) => {
          if (e.code === 'Escape') return this.setQuick(false);
          if (this.hovered === null || e.code.startsWith('Shift')) return;
          if (!this.game.keys.bind('bar' + this.hovered, comboOf(e))) this.hud.error(`${keyLabel(comboOf(e))} cannot be bound`);
        }
      : null;
  }
}
