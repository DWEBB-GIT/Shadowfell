import { xpForNextLevel } from '../config.js';

// Experience and levels. Owns level, xp and the stat bonuses they grant.

export class Progression {
  constructor(game) {
    this.game = game;
    this.level = 1;
    this.xp = 0; // experience towards the next level
    this.rested = 0; // rested experience (built at a camp): kills pay double until it is spent
    this.lastGains = null; // { level, gains: [{ id, label, from, to, diff }] } from the last level-up
  }

  get xpToNext() {
    return xpForNextLevel(this.level);
  }

  // `kill`: experience from a kill, which rested experience doubles.
  addXp(amount, { kill = false } = {}) {
    const { events, player } = this.game;
    const bonus = kill ? Math.min(Math.floor(this.rested), amount) : 0;
    this.rested = Math.max(0, this.rested - bonus);
    amount += bonus;
    this.xp += amount;
    events.emit('log', { text: bonus ? `+${amount} experience (${bonus} rested bonus).` : `+${amount} experience.`, kind: 'xp' });
    while (this.xp >= this.xpToNext) {
      const before = this.game.stats.snapshot();
      this.xp -= this.xpToNext;
      this.level += 1;
      this.game.recomputeMaxHealth();
      player.health = player.maxHealth; // a level-up restores health
      // every stat that rose, with its old and new value
      const after = this.game.stats.snapshot();
      const gains = Object.keys(after)
        .filter((k) => after[k].v > before[k].v)
        .map((k) => ({ id: k, label: after[k].label, from: before[k].text ?? before[k].v, to: after[k].text ?? after[k].v, diff: +(after[k].v - before[k].v).toFixed(1) }));
      this.lastGains = { level: this.level, gains };
      events.emit('levelUp', { level: this.level, gains });
      events.emit('log', {
        text: `You feel steadier. Level ${this.level}: ${gains.map((g) => `${g.label} +${g.diff}`).join(', ')}.`,
        kind: 'level',
      });
    }
    events.emit('statsChanged', {});
  }

  serialize() {
    return { level: this.level, xp: this.xp, rested: Math.floor(this.rested) };
  }

  apply(data) {
    this.level = data.level;
    this.xp = data.xp;
    this.rested = Number.isFinite(data.rested) && data.rested > 0 ? data.rested : 0;
  }
}
