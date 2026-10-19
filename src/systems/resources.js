// What abilities are paid with. Mana is drawn from Intellect and refills
// slowly in combat (fast out of it). Every other resource is a class bar,
// one system with different numbers per class (data/archetypes.json
// `resources.bars`):
//
//   max, start ('empty' | 'full'), colour
//   regenPerSecond     refills this much a second in combat (Energy, Focus)
//   regenOutOfCombat   ...and this much out of combat
//   stillBonus         refills this much faster standing still (Focus: 0.5)
//   shadowMultiplier   refills this many times faster in Shadow (Energy: 3)
//   perSwing, perHitTaken, perBlock   built by trading blows (Resolve)
//   perDotTick         built by every tick of your damage over time (Corruption)
//   decayAfter         seconds after the last blow that still count as combat
//   decayPerSecond     drains this fast out of combat (Resolve, Corruption)
//   points: true       whole points (combo points), gone `fadeAfter` seconds
//                      after your last hit, but kept while you are in Shadow
//   healPerSpent       spending it heals you this % of your health a point
//                      (Resolve: 0.2, so 2% per 10)
//   overload           at max: { name, damageBonus %, healthLossPercent a
//                      second } until it drops below max (Overcorrupted)
//
// Ability costs live in data/abilities.json (`cost`, `gain`, and
// `spendsAll` for finishers such as Double Cut and Purge).

export class Resources {
  constructor(game) {
    this.game = game;
    this.values = {};
    this.mana = 0;
    this.reset();
    const ev = game.events;
    const fight = () => (this.sinceCombat = 0);
    ev.on('enemyHit', (e) => {
      fight();
      this.sinceHit = 0;
      if (!e.swing) return;
      const off = e.hand === 'off' ? this.game.config.stats.offHandResolve : 1;
      for (const b of this.bars) if (b.perSwing) this.add(b.id, b.perSwing * off);
    });
    ev.on('playerHurt', (e) => {
      fight();
      for (const b of this.bars) this.add(b.id, (b.perHitTaken || 0) + (e.blocked ? b.perBlock || 0 : 0));
    });
    ev.on('braceBlock', () => {
      fight();
      for (const b of this.bars) this.add(b.id, b.perBlock);
    });
    ev.on('dotTick', () => {
      fight();
      for (const b of this.bars) this.add(b.id, b.perDotTick);
    });
    ev.on('playerDied', () => this.reset());
  }

  get cfg() {
    return this.game.stats.archetype.resources || {};
  }

  get bars() {
    return this.cfg.bars || [];
  }

  bar(id) {
    return this.bars.find((b) => b.id === id) || null;
  }

  // the class's main bar (Resolve, Energy, Focus, Corruption), for the HUD
  get gaugeCfg() {
    return this.bars.find((b) => !b.points) || null;
  }

  // its amount (tests and older code call this the gauge)
  get gauge() {
    return this.gaugeCfg ? this.values[this.gaugeCfg.id] || 0 : 0;
  }

  set gauge(v) {
    if (this.gaugeCfg) this.values[this.gaugeCfg.id] = v;
  }

  // combo points, if the class has them
  get pointsCfg() {
    return this.bars.find((b) => b.points) || null;
  }

  get maxMana() {
    return this.game.stats.maxMana;
  }

  get inCombat() {
    return this.sinceCombat < (this.gaugeCfg?.decayAfter ?? 6);
  }

  // a bar at its max with an `overload` (Overcorrupted), or null
  get overload() {
    for (const b of this.bars) if (b.overload && (this.values[b.id] || 0) >= b.max) return b.overload;
    return null;
  }

  // extra damage, in %, from an overloaded bar
  get damageBonus() {
    return this.overload?.damageBonus || 0;
  }

  // how much of a resource you have now
  amount(id) {
    if (id === 'mana') return this.mana;
    return this.values[id] || 0;
  }

  nameOf(id) {
    return id === 'mana' ? 'mana' : this.bar(id)?.name || id;
  }

  add(id, n) {
    if (!id || !(n > 0)) return;
    if (id === 'mana') return void (this.mana = Math.min(this.maxMana, this.mana + n));
    const b = this.bar(id);
    if (b) this.values[id] = Math.min(b.max, (this.values[id] || 0) + n);
  }

  // the first resource an ability needs and you lack, or null
  lacking(ability) {
    for (const [id, n] of Object.entries(ability.cost || {})) if (this.amount(id) < n) return id;
    if (ability.spendsAll && this.amount(ability.spendsAll) < 1) return ability.spendsAll;
    return null;
  }

  canAfford(ability) {
    return this.unlimited || !this.lacking(ability);
  }

  // refuse with WoW's red message if short; true if it can be paid
  check(ability) {
    const short = !this.unlimited && this.lacking(ability);
    if (short) this.game.hud.error(ability.spendsAll === short && !ability.cost?.[short] ? `You have no ${this.nameOf(short)}` : `Not enough ${this.nameOf(short)}`);
    return !short;
  }

  // Pay an ability's cost and take its gain. Returns how much of its
  // `spendsAll` resource it spent (the combo points behind a Double Cut).
  spend(ability, gain = ability.gain) {
    let all = 0;
    const take = (id, n) => {
      const had = this.amount(id);
      const paid = Math.min(had, n);
      if (id === 'mana') this.mana = had - paid;
      else this.values[id] = had - paid;
      const heal = this.bar(id)?.healPerSpent;
      if (heal && paid > 0) {
        const p = this.game.player;
        const healed = p.heal((p.maxHealth * heal * paid) / 100);
        if (healed >= 1) this.game.events.emit('damageNumber', { target: p, amount: Math.round(healed), kind: 'heal' });
      }
      return paid;
    };
    if (!this.unlimited) for (const [id, n] of Object.entries(ability.cost || {})) take(id, n);
    if (ability.spendsAll) all = this.unlimited ? Math.max(1, this.amount(ability.spendsAll)) : take(ability.spendsAll, this.amount(ability.spendsAll));
    for (const [id, n] of Object.entries(gain || {})) this.add(id, n);
    if (ability.cost || gain || ability.spendsAll) this.sinceCombat = Math.min(this.sinceCombat, 0.001);
    return all;
  }

  update(dt) {
    const { player } = this.game;
    if (player.dead) return;
    this.sinceCombat += dt;
    this.sinceHit += dt;
    const fighting = this.inCombat;
    const hidden = !!this.game.spells?.hidden;
    const m = this.cfg.mana;
    if (m) this.mana = Math.min(this.maxMana, this.mana + (fighting ? m.regenPerSecond : m.regenOutOfCombat) * dt);
    for (const b of this.bars) {
      let v = this.values[b.id] || 0;
      const regen = fighting ? b.regenPerSecond || 0 : (b.regenOutOfCombat ?? b.regenPerSecond) || 0;
      if (regen) v += regen * (hidden ? b.shadowMultiplier || 1 : 1) * (player.moving ? 1 : 1 + (b.stillBonus || 0)) * dt;
      if (b.decayPerSecond && !fighting) v -= b.decayPerSecond * dt;
      if (b.points && b.fadeAfter && this.sinceHit > b.fadeAfter && !hidden) v = 0;
      this.values[b.id] = Math.max(0, Math.min(b.max, v));
    }
    // Overcorrupted: health bleeds away until the bar drops (never below 1)
    const o = this.overload;
    if (o) player.health = Math.max(1, player.health - (player.maxHealth * o.healthLossPercent * dt) / 100);
  }

  // back to full mana and each bar at its start (respawn, load, a new character)
  reset() {
    this.mana = this.maxMana;
    this.values = {};
    for (const b of this.bars) this.values[b.id] = b.start === 'full' ? b.max : 0;
    this.sinceCombat = Infinity;
    this.sinceHit = Infinity;
  }
}
