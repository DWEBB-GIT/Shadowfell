// Player preferences (the Settings window, O). Kept in the browser apart
// from the save, so they hold across characters; a browser that refuses
// storage just gets the defaults.

const KEY = 'shadowfall.settings';
export const SETTINGS = [
  { id: 'names', label: 'Show names over characters', default: true },
  { id: 'playerName', label: 'Show your own name over your character', default: true },
  { id: 'lootNames', label: 'Show names of items on the ground', default: true },
];

export class Settings {
  constructor(game) {
    this.game = game;
    this.values = Object.fromEntries(SETTINGS.map((s) => [s.id, s.default]));
    try {
      const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
      for (const s of SETTINGS) if (typeof saved[s.id] === 'boolean') this.values[s.id] = saved[s.id];
    } catch {
      // defaults
    }
  }

  get(id) {
    return this.values[id];
  }

  set(id, v) {
    this.values[id] = !!v;
    try {
      localStorage.setItem(KEY, JSON.stringify(this.values));
    } catch {
      // not saved; still applies this session
    }
    this.game.events.emit('settingsChanged', { id, value: !!v });
  }
}
