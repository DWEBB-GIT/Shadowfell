import { SAVE_KEY } from './save.js';
import { TITLE } from '../data/text.js';

// The character roster: who has been made in this browser, which class each
// is, and where each one's save lives. Saves stay in localStorage, one key per
// character; the roster itself is a small list under its own key.
//
// The first character takes the original save key, so a save made before the
// roster existed becomes a character of its own the first time the title
// screen opens (named "Warden" until there is a way to rename).

export const ROSTER_KEY = 'shadowfall.characters';
export const NAME_RULE = /^[A-Z][a-z]{1,11}( [A-Z][a-z]{1,11})?$/;

export function tidyName(raw) {
  return String(raw || '')
    .trim()
    .replace(/\s+/g, ' ')
    .split(' ')
    .map((w) => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w))
    .join(' ');
}

export class Roster {
  constructor(storage = globalThis.localStorage) {
    this.storage = storage;
    this.list = [];
    this.last = null;
  }

  get max() {
    return TITLE.maxCharacters;
  }

  get full() {
    return this.list.length >= this.max;
  }

  // Read the roster. Returns { legacyUnreadable } when an old save sits
  // under the original key but could not be adopted (the caller decides
  // what to tell the player).
  load(readSave) {
    let data = null;
    try {
      data = JSON.parse(this.storage.getItem(ROSTER_KEY) || 'null');
    } catch {
      data = null;
    }
    const ok = data && Array.isArray(data.list) && data.list.every((c) => c && typeof c.id === 'string' && typeof c.name === 'string' && typeof c.key === 'string');
    this.list = ok ? data.list : [];
    this.last = ok && this.byId(data.last) ? data.last : this.list[0]?.id || null;

    // adopt a save made before the roster existed
    let legacyUnreadable = false;
    if (!this.list.some((c) => c.key === SAVE_KEY) && this._has(SAVE_KEY)) {
      if (readSave(SAVE_KEY).status === 'ok') {
        const c = { id: this._newId(), name: 'Warden', classId: 'warden', key: SAVE_KEY, createdAt: Date.now(), lastPlayed: Date.now() };
        this.list.unshift(c);
        this.last = c.id;
        this._write();
      } else legacyUnreadable = true;
    }
    return { legacyUnreadable };
  }

  byId(id) {
    return this.list.find((c) => c.id === id) || null;
  }

  // null when the name is fine, otherwise why not
  nameProblem(raw) {
    const name = tidyName(raw);
    if (!name) return 'Your character needs a name.';
    if (!NAME_RULE.test(name)) return 'Use letters only: one or two words of 2 to 12 letters.';
    if (this.list.some((c) => c.name.toLowerCase() === name.toLowerCase())) return `There is already a character called ${name}.`;
    return null;
  }

  randomName(random = Math.random) {
    const { first, last } = TITLE.names;
    for (let i = 0; i < 40; i++) {
      const name = `${first[Math.floor(random() * first.length)]} ${last[Math.floor(random() * last.length)]}`;
      if (!this.nameProblem(name)) return name;
      random = Math.random; // a pinned roll would repeat the same clash
    }
    return '';
  }

  create(rawName, classId) {
    const name = tidyName(rawName);
    const problem = this.full ? `You can keep ${this.max} characters. Delete one to make room.` : this.nameProblem(name);
    if (problem) return { ok: false, reason: problem };
    const id = this._newId();
    // the original key is free: the first character (or one after it was deleted) takes it
    const key = this.list.some((c) => c.key === SAVE_KEY) || this._has(SAVE_KEY) ? `${SAVE_KEY}.${id}` : SAVE_KEY;
    const c = { id, name, classId, key, createdAt: Date.now(), lastPlayed: Date.now() };
    this.list.push(c);
    this.last = id;
    if (!this._write()) {
      this.list.pop();
      return { ok: false, reason: 'Browser storage is full or disabled, so no character can be made.' };
    }
    return { ok: true, character: c };
  }

  // Deleting removes the character's save for good.
  remove(id) {
    const c = this.byId(id);
    if (!c) return false;
    this.list = this.list.filter((x) => x !== c);
    try {
      this.storage.removeItem(c.key);
    } catch {
      /* nothing more to do */
    }
    if (this.last === id) this.last = this.list[0]?.id || null;
    this._write();
    return true;
  }

  touch(id) {
    const c = this.byId(id);
    if (!c) return;
    c.lastPlayed = Date.now();
    this.last = id;
    this._write();
  }

  _has(key) {
    try {
      return this.storage.getItem(key) !== null;
    } catch {
      return false;
    }
  }

  _newId() {
    let n = this.list.length + 1;
    while (this.list.some((c) => c.id === `c${n}`)) n++;
    return `c${n}`;
  }

  _write() {
    try {
      this.storage.setItem(ROSTER_KEY, JSON.stringify({ version: 1, last: this.last, list: this.list }));
      return true;
    } catch {
      return false;
    }
  }
}
