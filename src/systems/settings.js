// Player preferences (the Settings window, O). Kept in the browser apart
// from the save, so they hold across characters; a browser that refuses
// storage just gets the defaults. A setting is a checkbox, or a slider when
// it has `min` and `max` (volumes, in percent).

const KEY = 'shadowfall.settings';
export const SETTINGS = [
  { id: 'names', label: 'Show names over characters', default: true },
  { id: 'playerName', label: 'Show your own name over your character', default: true },
  { id: 'lootNames', label: 'Show names of items on the ground', default: true },
  { id: 'clickToMove', label: 'Click on the ground to walk there', default: false },
  { id: 'volMaster', label: 'Master volume', group: 'Sound', default: 70, min: 0, max: 100 },
  { id: 'volEffects', label: 'Effects', group: 'Sound', default: 100, min: 0, max: 100 },
  { id: 'volAmbience', label: 'Ambience (wind, birds, bells)', group: 'Sound', default: 100, min: 0, max: 100 },
];

const BY_ID = Object.fromEntries(SETTINGS.map((s) => [s.id, s]));
const isSlider = (s) => s.min !== undefined;

// a stored value made safe: the right type, and inside a slider's range
function clean(s, v) {
  if (isSlider(s)) return Number.isFinite(v) ? Math.min(s.max, Math.max(s.min, Math.round(v))) : s.default;
  return typeof v === 'boolean' ? v : s.default;
}

export class Settings {
  constructor(game) {
    this.game = game;
    this.values = Object.fromEntries(SETTINGS.map((s) => [s.id, s.default]));
    try {
      const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
      for (const s of SETTINGS) if (saved[s.id] !== undefined) this.values[s.id] = clean(s, saved[s.id]);
    } catch {
      // defaults
    }
  }

  get(id) {
    return this.values[id];
  }

  set(id, v) {
    const s = BY_ID[id];
    if (!s) return;
    const value = clean(s, isSlider(s) ? Number(v) : !!v);
    this.values[id] = value;
    try {
      localStorage.setItem(KEY, JSON.stringify(this.values));
    } catch {
      // not saved; still applies this session
    }
    this.game.events.emit('settingsChanged', { id, value });
  }
}
