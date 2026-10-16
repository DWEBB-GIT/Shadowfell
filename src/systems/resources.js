// What abilities are paid with: mana, drawn from Intellect, refilling slowly
// (fast out of combat), and the class gauge (the Warden's Resolve), built by
// weapon blows, blocks and hits taken, fading once the fight is over.
// Amounts and rates live in data/archetypes.json; ability costs in
// data/abilities.json (`cost`, and `gain` for openers such as Lunge).

export class Resources {
  constructor(game) {
    this.game = game;
    this.mana = this.maxMana;
    this.gauge = 0;
    this.sinceCombat = Infinity; // seconds since you last dealt or took a blow
    const ev = game.events;
    const fight = () => (this.sinceCombat = 0);
    ev.on('enemyHit', (e) => {
      fight();
      if (e.swing) this.add(this.gaugeCfg?.id, this.gaugeCfg?.perSwing * (e.hand === 'off' ? this.game.config.stats.offHandResolve : 1));
    });
    ev.on('playerHurt', (e) => {
      fight();
      this.add(this.gaugeCfg?.id, this.gaugeCfg?.perHitTaken + (e.blocked ? this.gaugeCfg?.perBlock : 0));
    });
    ev.on('braceBlock', () => {
      fight();
      this.add(this.gaugeCfg?.id, this.gaugeCfg?.perBlock);
    });
    ev.on('playerDied', () => (this.gauge = 0));
  }

  get cfg() {
    return this.game.stats.archetype.resources || {};
  }

  get gaugeCfg() {
    return this.cfg.gauge || null;
  }

  get maxMana() {
    return this.game.stats.maxMana;
  }

  get inCombat() {
    return this.sinceCombat < (this.gaugeCfg?.decayAfter ?? 6);
  }

  // how much of a resource you have now
  amount(id) {
    if (id === 'mana') return this.mana;
    if (this.gaugeCfg && id === this.gaugeCfg.id) return this.gauge;
    return 0;
  }

  nameOf(id) {
    return id === 'mana' ? 'mana' : this.gaugeCfg?.id === id ? this.gaugeCfg.name : id;
  }

  add(id, n) {
    if (!id || !(n > 0)) return;
    if (id === 'mana') this.mana = Math.min(this.maxMana, this.mana + n);
    else if (this.gaugeCfg && id === this.gaugeCfg.id) this.gauge = Math.min(this.gaugeCfg.max, this.gauge + n);
  }

  // the first resource an ability needs and you lack, or null
  lacking(ability) {
    for (const [id, n] of Object.entries(ability.cost || {})) if (this.amount(id) < n) return id;
    return null;
  }

  canAfford(ability) {
    return this.unlimited || !this.lacking(ability);
  }

  // refuse with WoW's red message if short; true if it can be paid
  check(ability) {
    const short = !this.unlimited && this.lacking(ability);
    if (short) this.game.hud.error(`Not enough ${this.nameOf(short)}`);
    return !short;
  }

  // pay an ability's cost and take its gain
  spend(ability) {
    if (!this.unlimited) {
      for (const [id, n] of Object.entries(ability.cost || {})) {
        if (id === 'mana') this.mana = Math.max(0, this.mana - n);
        else this.gauge = Math.max(0, this.gauge - n);
      }
    }
    for (const [id, n] of Object.entries(ability.gain || {})) this.add(id, n);
    if (ability.cost || ability.gain) this.sinceCombat = Math.min(this.sinceCombat, 0.001);
  }

  update(dt) {
    if (this.game.player.dead) return;
    this.sinceCombat += dt;
    const m = this.cfg.mana;
    if (m) this.mana = Math.min(this.maxMana, this.mana + (this.inCombat ? m.regenPerSecond : m.regenOutOfCombat) * dt);
    const g = this.gaugeCfg;
    if (g && !this.inCombat) this.gauge = Math.max(0, this.gauge - g.decayPerSecond * dt);
  }

  // back to full mana and an empty gauge (respawn, load)
  reset() {
    this.mana = this.maxMana;
    this.gauge = 0;
    this.sinceCombat = Infinity;
  }
}
