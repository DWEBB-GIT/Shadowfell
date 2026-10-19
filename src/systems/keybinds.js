// Key bindings (Settings, O). Every action has one or more keys; players can
// change them in the Settings window, or use Quick bind (as WoW's /kb): hover
// a spell or utility bar slot and press a key. Bindings are kept in the
// browser with the other settings. Movement stays on WASD and the arrow keys.
// A key held with Shift is its own binding, written 'Shift+Digit1'.
//
// Defaults (Dan, 2026-10-19): six spell slots on 1 2 3 4 Q E, the four
// utility slots on Shift-1 to Shift-4, and Space to interact.

// (v2: the 2026-10-19 layout; bindings saved under the old key are dropped
// so everyone gets it)
const KEY = 'shadowfall.keys.v2';

export const KEY_ACTIONS = [
  { id: 'bar0', label: 'Spell bar 1', group: 'Spell bar', keys: ['Digit1'] },
  { id: 'bar1', label: 'Spell bar 2', group: 'Spell bar', keys: ['Digit2'] },
  { id: 'bar2', label: 'Spell bar 3', group: 'Spell bar', keys: ['Digit3'] },
  { id: 'bar3', label: 'Spell bar 4', group: 'Spell bar', keys: ['Digit4'] },
  { id: 'bar4', label: 'Spell bar 5', group: 'Spell bar', keys: ['KeyQ'] },
  { id: 'bar5', label: 'Spell bar 6', group: 'Spell bar', keys: ['KeyE'] },
  { id: 'bar6', label: 'Utility 1', group: 'Utility bar', keys: ['Shift+Digit1'] },
  { id: 'bar7', label: 'Utility 2', group: 'Utility bar', keys: ['Shift+Digit2'] },
  { id: 'bar8', label: 'Utility 3', group: 'Utility bar', keys: ['Shift+Digit3'] },
  { id: 'bar9', label: 'Utility 4', group: 'Utility bar', keys: ['Shift+Digit4'] },
  { id: 'interact', label: 'Interact', group: 'Actions', keys: ['Space'] },
  { id: 'cycleTarget', label: 'Next target', group: 'Actions', keys: ['Tab'] },
  { id: 'character', label: 'Character', group: 'Menus', keys: ['KeyC'] },
  { id: 'spellbook', label: 'Spells', group: 'Menus', keys: ['KeyP'] },
  { id: 'talents', label: 'Talents', group: 'Menus', keys: ['KeyN'] },
  { id: 'quests', label: 'Quest log', group: 'Menus', keys: ['KeyL'] },
  { id: 'settings', label: 'Settings', group: 'Menus', keys: ['KeyO'] },
  { id: 'bags', label: 'Bags', group: 'Menus', keys: ['KeyB', 'KeyI'] },
  { id: 'skills', label: 'Professions', group: 'Menus', keys: ['KeyU'] },
  { id: 'save', label: 'Save the game', group: 'Menus', keys: ['KeyK'] },
];

// keys nobody may take: movement, Escape and the mouse
const RESERVED = new Set(['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Escape']);

// The binding a key press makes: Shift held turns Digit1 into Shift+Digit1
// (Shift itself, pressed alone, stays Shift).
export function comboOf(e) {
  return e.shiftKey && !e.code.startsWith('Shift') ? 'Shift+' + e.code : e.code;
}

// how a key code reads on a button: Digit1 -> 1, KeyQ -> Q, Space -> Space,
// Shift+Digit1 -> Shift-1
export function keyLabel(code) {
  if (!code) return '';
  if (code.startsWith('Shift+')) return 'Shift-' + keyLabel(code.slice(6));
  if (code.startsWith('Digit')) return code.slice(5);
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Numpad')) return 'N' + code.slice(6);
  const names = { Space: 'Space', Backquote: '`', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/', Backslash: '\\', ShiftLeft: 'Shift', ShiftRight: 'RShift', ControlLeft: 'Ctrl', AltLeft: 'Alt', Tab: 'Tab', CapsLock: 'Caps', Enter: 'Enter' };
  return names[code] || code;
}

export class Keybinds {
  constructor(game) {
    this.game = game;
    this.map = Object.fromEntries(KEY_ACTIONS.map((a) => [a.id, [...a.keys]]));
    try {
      const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
      for (const a of KEY_ACTIONS) if (Array.isArray(saved[a.id]) && saved[a.id].every((k) => typeof k === 'string')) this.map[a.id] = saved[a.id];
    } catch {
      // defaults
    }
  }

  keys(id) {
    return this.map[id] || [];
  }

  label(id) {
    return this.keys(id).map(keyLabel).join(' / ');
  }

  isBound(code) {
    return Object.values(this.map).some((k) => k.includes(code));
  }

  // was this action's key pressed this frame? (consumes the press)
  pressed(id) {
    const input = this.game.input;
    let hit = false;
    for (const k of this.keys(id)) if (input.consume(k)) hit = true;
    return hit;
  }

  // Bind a key to an action, taking it from anything else that had it.
  // Returns false for keys that cannot be bound.
  bind(id, code) {
    if (RESERVED.has(code.replace('Shift+', '')) || !this.map[id]) return false;
    for (const k of Object.keys(this.map)) this.map[k] = this.map[k].filter((c) => c !== code);
    this.map[id] = [code];
    this._save();
    return true;
  }

  unbind(id) {
    if (!this.map[id]) return;
    this.map[id] = [];
    this._save();
  }

  resetAll() {
    this.map = Object.fromEntries(KEY_ACTIONS.map((a) => [a.id, [...a.keys]]));
    this._save();
  }

  _save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.map));
    } catch {
      // still applies this session
    }
    this.game.events.emit('keysChanged', {});
  }
}
