import { DB } from '../data/db.js';
import { computeHit, enemyBlock, weaponRoll } from './stats.js';

// The spell engine. Abilities in data/abilities.json with a `kind` are run
// here from their data alone, so a new spell is a new record, not new code:
//
//   cast     a cast bar (moving interrupts it), then a bolt flies at the target
//   dot      a bleed or burn on the target: ticks every `tickInterval` for
//            `duration` seconds; using it again refreshes it
//   instant  damage on the target at once
//   aoe      consecrates the ground around you; enemies in it take a tick
//            of damage every `tickInterval` for `duration` seconds
//   cleave   a wide swing hitting up to `maxTargets` enemies in front of you
//   burst    a blow around you (Shield Break): every enemy within `radius`
//            is hit, staggered and knocked back; `interrupts: 1` stops
//            their ordinary attacks
//   guard    Brace: the next blow within `window` seconds is turned aside
//   interrupt a word that breaks the target's interruptible cast and locks
//            it out of attacking for `lockout` seconds (Rebuke)
//   charge   a dash of `distance` metres at the target (or the cursor) over
//            `duration` seconds that strikes on arrival (Lunge)
//   buff     raises all your damage by `damageBonus` % for `duration` seconds
//   camp     Set Camp: a cast, then the camp is pitched (systems/camp.js)
//
// Damage is either weapon based (`damageMultiplier` / `tickMultiplier` x a
// weapon roll, as Strike) or a spell's own `damageMin`-`damageMax` (at
// level 1; it grows with level as (level + 4) / 5, see src/data/scaling.js)
// plus spell power. Every spell triggers the global cooldown; a spell's own cooldown
// starts when it goes off (after the cast, for cast spells).
//
// Enemy spells go to the selected target, or the soft target near your aim
// (which then becomes selected), as in WoW.

export const SPELLS = Object.fromEntries(Object.values(DB.abilities).filter((a) => a.kind).map((a) => [a.id, a]));

export class Spells {
  constructor(game) {
    this.game = game;
    this.reset();
  }

  reset() {
    this.buffs = new Map(); // id -> { left, total }
    this.dots = []; // { enemy, id, left, next }
    this.zones = []; // { id, x, z, left, next }
    this.bolts = []; // { enemy, id, t }
  }

  // ---------------------------------------------------------- state for the HUD
  // all damage the Warden deals is scaled by active buffs
  get damageScale() {
    let s = 1;
    for (const id of this.buffs.keys()) s *= 1 + (SPELLS[id].tuning.damageBonus || 0) / 100;
    return s;
  }

  // [{ id, left, total }] for the buff row under the health bar
  buffList() {
    return [...this.buffs].map(([id, b]) => ({ id, left: b.left, total: b.total }));
  }

  // [{ id, left, total }] of your effects on one enemy, for the target frame
  dotsOn(enemy) {
    return this.dots.filter((d) => d.enemy === enemy).map((d) => ({ id: d.id, left: d.left, total: SPELLS[d.id].tuning.duration }));
  }

  // --------------------------------------------------------------- casting
  // Try to use a spell; false (with a word in the log, where WoW would say
  // one) if it cannot go off now.
  tryCast(id) {
    const { player, events, stats } = this.game;
    const spell = SPELLS[id];
    // off-GCD spells (Brace, Rebuke) go even mid-swing
    if (!spell || player.dead || player.lunge || player.casting || (player.pending && !spell.tuning.offGlobalCooldown)) return false;
    if (!this.game.skills.knowsAbility(id)) return false;
    const offGcd = !!spell.tuning.offGlobalCooldown;
    if (!offGcd && player.cooldowns.gcd > 0) return false; // queued out silently, as in WoW
    if (player.cooldowns[id] > 0) {
      this.game.hud.error(`${spell.name} is not ready yet`);
      return false;
    }
    if (spell.kind === 'camp' && this.game.camp.enemiesNear) {
      this.game.hud.error('You cannot make camp with enemies close by');
      return false;
    }
    if ((spell.kind === 'cast' || spell.kind === 'camp') && player.moving) {
      this.game.hud.error("You can't do that while moving");
      return false;
    }
    let target = null;
    if (spell.kind === 'charge') {
      // a charge goes at the target in range, or towards the cursor without one
      target = this._targetFor(spell, { optional: true });
      if (target === false) return false;
      return this._charge(spell, target);
    }
    if (spell.target === 'enemy') {
      target = this._targetFor(spell);
      if (!target) return false;
      player.faceTowards(target.position.x, target.position.z);
      // a spell at an enemy engages it: auto attack follows once in reach
      this.game.targeting.engage(target);
    }
    if (!offGcd) player.cooldowns.gcd = stats.globalCooldown;
    const t = spell.tuning;
    if (spell.kind === 'cast' || spell.kind === 'camp') {
      // casting stops the swing: a swing on its way is dropped, and the swing
      // timer starts again when the cast ends (WoW)
      if (player.pending && player.pending.type === 'strike') player.pending = null;
      player.casting = { id, t: 0, total: stats.hasted(t.castTime), target };
      player.rig.play('brace', player.casting.total, 0.9);
      events.emit('castStart', { id });
      return true;
    }
    if (spell.kind === 'cleave' || spell.kind === 'burst') {
      // the blow lands after its windup, like a swing
      const windup = stats.hasted(t.windup);
      const anim = spell.kind === 'burst' ? windup + 0.35 : windup + 0.3;
      player.pending = { type: 'spell', id, t: windup };
      player.cooldowns.attack = Math.max(player.cooldowns.attack, windup + 0.2);
      player.rig.play(spell.kind === 'burst' ? 'slam' : 'strike', anim, windup / anim);
      player.cooldowns[id] = t.cooldown;
      return true;
    }
    player.cooldowns[id] = t.cooldown;
    this._go(spell, target);
    return true;
  }

  // the selected enemy if in range, else the soft target near the aim.
  // `optional`: no target is fine (null); out of range is still refused (false).
  _targetFor(spell, { optional = false } = {}) {
    const { targeting, player } = this.game;
    const inRange = (e) => e && e.alive && Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z) <= spell.range + e.radius * 0.6;
    const cur = targeting.current;
    if (cur && cur.alive) {
      if (inRange(cur)) return cur;
      this.game.hud.error('Out of range');
      return optional ? false : null;
    }
    const soft = targeting.softTarget(this.game.rawAim || player.position, spell.range);
    if (inRange(soft)) {
      targeting.select(soft);
      return soft;
    }
    if (optional) return null;
    this.game.hud.error('You have no target.');
    return null;
  }

  // Lunge and other charges: dash at the target (or the cursor), strike on arrival.
  _charge(spell, target) {
    const { player, stats, events } = this.game;
    const t = spell.tuning;
    const aim = target ? target.position : this.game.rawAim;
    let dir = { x: Math.sin(player.facing), z: Math.cos(player.facing) };
    if (aim) {
      const dx = aim.x - player.position.x;
      const dz = aim.z - player.position.z;
      const len = Math.hypot(dx, dz);
      if (len > 0.3) dir = { x: dx / len, z: dz / len };
    }
    if (target) this.game.targeting.engage(target);
    player.facing = Math.atan2(dir.x, dir.z);
    player.cooldowns[spell.id] = t.cooldown;
    player.cooldowns.gcd = stats.globalCooldown;
    player.cooldowns.attack = Math.max(player.cooldowns.attack, t.duration + 0.2);
    player.lunge = { t: 0, dir, id: spell.id, speed: t.distance / t.duration, duration: t.duration };
    player.rig.play('strike', t.duration + 0.25, 0.7);
    events.emit('playerLunge', {});
    return true;
  }

  // a spell going off: instant effects now, bolts and zones over time
  _go(spell, target) {
    const { player, events } = this.game;
    const t = spell.tuning;
    if (spell.kind === 'cast') {
      const d = Math.hypot(target.position.x - player.position.x, target.position.z - player.position.z);
      this.bolts.push({ enemy: target, id: spell.id, t: d / t.projectileSpeed });
      events.emit('projectile', { kind: 'holy', from: { x: player.position.x, y: player.position.y + 1.3, z: player.position.z }, to: target.position, speed: t.projectileSpeed });
    } else if (spell.kind === 'instant') {
      player.rig.play('strike', 0.4, 0.4);
      events.emit('spellFlash', { position: target.position, school: spell.school });
      this._damage(spell, target, this._spellBase(t), `Your ${spell.name} hits the {name} for {n}.`);
    } else if (spell.kind === 'dot') {
      player.rig.play('strike', 0.45, 0.4);
      const had = this.dots.find((d) => d.enemy === target && d.id === spell.id);
      if (had) had.left = t.duration;
      else this.dots.push({ enemy: target, id: spell.id, left: t.duration, next: t.tickInterval });
      target.hurt(0, { stagger: 0.1 }); // they notice
      events.emit('enemyHit', { enemy: target, damage: 0, kind: 'strike' });
      events.emit('log', { text: had ? `${spell.name} refreshed on the ${target.cfg.name}.` : `The ${target.cfg.name} is afflicted by ${spell.name}.`, kind: 'hit' });
    } else if (spell.kind === 'aoe') {
      player.rig.play('slam', 0.5, 0.5);
      this.zones.push({ id: spell.id, x: player.position.x, z: player.position.z, left: t.duration, next: 0 });
      events.emit('zone', { id: spell.id, x: player.position.x, z: player.position.z, radius: t.radius, duration: t.duration });
      events.emit('log', { text: `You consecrate the ground: ${spell.name}.`, kind: 'hit' });
    } else if (spell.kind === 'guard') {
      player.braced = t.window;
      player.rig.play('brace', 0.5, 0.4);
      events.emit('playerBrace', {});
    } else if (spell.kind === 'interrupt') {
      player.rig.play('brace', 0.35, 0.4);
      const broke = target.interrupt(t.lockout);
      events.emit('spellFlash', { position: target.position, school: spell.school });
      this._damage(spell, target, this._spellBase(t), null);
      if (broke) {
        events.emit('interrupted', { enemy: target });
        events.emit('log', { text: `You interrupt the ${target.cfg.name}'s ${broke}.`, kind: 'level' });
        this.game.hud.toast('Interrupted!');
      } else if (broke === false) this.game.hud.error(`${target.cfg.name}'s attack cannot be interrupted`);
      else events.emit('log', { text: `${spell.name}: the ${target.cfg.name} was not casting.`, kind: 'muted' });
    } else if (spell.kind === 'camp') {
      this.game.camp.pitch(player.position.x, player.position.z);
    } else if (spell.kind === 'buff') {
      player.rig.play('brace', 0.6, 0.4);
      this.buffs.set(spell.id, { left: t.duration, total: t.duration });
      events.emit('buff', { id: spell.id });
      events.emit('log', { text: `${spell.name}: your damage is raised by ${t.damageBonus}% for ${t.duration} seconds.`, kind: 'hit' });
    }
  }

  // Called by the player when a pending spell blow lands (cleave, burst, charge).
  resolve(id) {
    const spell = SPELLS[id];
    const { player } = this.game;
    if (player.dead) return [];
    if (spell.kind === 'burst') return this._burst(spell);
    if (spell.kind === 'charge') return this._chargeHit(spell);
    if (spell.kind !== 'cleave') return [];
    const { enemies, events } = this.game;
    const t = spell.tuning;
    const fx = Math.sin(player.facing);
    const fz = Math.cos(player.facing);
    const cosLimit = Math.cos(((t.coneDegrees / 2) * Math.PI) / 180);
    const inCone = [];
    for (const e of enemies.list) {
      if (!e.alive) continue;
      const dx = e.position.x - player.position.x;
      const dz = e.position.z - player.position.z;
      const d = Math.hypot(dx, dz);
      if (d - e.radius * 0.6 > t.range) continue;
      if (d > 0.8 && (dx * fx + dz * fz) / d < cosLimit) continue;
      inCone.push([d, e]);
    }
    inCone.sort((a, b) => a[0] - b[0]);
    const hits = inCone.slice(0, t.maxTargets).map(([, e]) => e);
    events.emit('cleave', { position: player.position.clone(), facing: player.facing, range: t.range, degrees: t.coneDegrees });
    if (!hits.length) {
      events.emit('log', { text: `${spell.name} cuts only air.`, kind: 'muted' });
      return [];
    }
    let most = 0;
    for (const e of hits) most = Math.max(most, this._damage(spell, e, weaponRoll(this.game.random, this.game.stats), null, t.damageMultiplier, { stagger: 0.2, knockFrom: player.position, knockback: 0.3 }).amount);
    events.emit('log', { text: `${spell.name} hits ${hits.length === 1 ? 'the ' + hits[0].cfg.name : hits.length + ' foes'} for ${most}.`, kind: 'hit' });
    return hits;
  }

  _burst(spell) {
    const { player, enemies, events } = this.game;
    const t = spell.tuning;
    const hits = enemies.list.filter((e) => e.alive && Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z) - e.radius * 0.5 <= t.radius);
    let most = 0;
    for (const e of hits) most = Math.max(most, this._damage(spell, e, weaponRoll(this.game.random, this.game.stats), null, t.damageMultiplier, { stagger: t.stagger, knockFrom: player.position, knockback: t.knockback, heavy: !!t.interrupts }).amount);
    events.emit('burst', { id: spell.id, position: player.position.clone(), radius: t.radius, hits });
    // striking engages: auto attack the target, or the first foe left standing
    const tg = this.game.targeting;
    const alive = hits.filter((e) => e.alive);
    if (alive.length) tg.engage(tg.current && alive.includes(tg.current) ? tg.current : alive[0]);
    if (hits.length) events.emit('log', { text: `${spell.name} ${t.interrupts ? 'staggers' : 'hits'} ${hits.length === 1 ? 'the ' + hits[0].cfg.name : hits.length + ' foes'} for ${most}.`, kind: 'hit' });
    else events.emit('log', { text: `${spell.name} strikes only earth.`, kind: 'muted' });
    return hits;
  }

  // the charge has arrived: strike the target if close, else the nearest foe
  _chargeHit(spell) {
    const { player, enemies, events, targeting } = this.game;
    const t = spell.tuning;
    const dist = (e) => Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z) - e.radius;
    let best = targeting.current && targeting.current.alive && dist(targeting.current) <= t.hitRadius + 0.4 ? targeting.current : null;
    if (!best) for (const e of enemies.list) if (e.alive && dist(e) <= t.hitRadius && (!best || dist(e) < dist(best))) best = e;
    if (!best) {
      events.emit('playerMiss', {});
      return [];
    }
    player.faceTowards(best.position.x, best.position.z);
    targeting.engage(best);
    const hit = this._damage(spell, best, weaponRoll(this.game.random, this.game.stats), null, t.damageMultiplier, { stagger: 0.3, knockFrom: player.position, knockback: 0.4 });
    events.emit('log', { text: `You ${spell.name.toLowerCase()} into the ${best.cfg.name} for ${hit.amount}.${hit.crit ? ' A critical blow!' : ''}`, kind: 'hit' });
    return [best];
  }

  _spellBase(t) {
    return (t.damageMin + (t.damageMax - t.damageMin) * this.game.random()) * this.game.stats.spellScale + this.game.stats.spellPower;
  }

  // One hit of a spell on an enemy: the shared damage formula, the number,
  // the log line ({name} and {n} filled in), and the kill.
  _damage(spell, enemy, base, line, mult = 1, hurtOpts = { stagger: 0.12 }) {
    const { stats, events, combat } = this.game;
    const hit = computeHit(this.game.random, stats.statBlock, enemyBlock(enemy.cfg), { base, mult: mult * this.damageScale * this.game.afterlife.damageScaleAgainst(enemy), school: spell.school || 'physical' });
    enemy.hurt(hit.amount, hurtOpts);
    events.emit('damageNumber', { target: enemy, amount: hit.amount, crit: hit.crit, kind: 'dealt' });
    events.emit('enemyHit', { enemy, damage: hit.amount, crit: hit.crit, kind: (spell.school || 'physical') === 'physical' ? 'strike' : 'spell' });
    events.emit('hitImpact', { enemy, crit: hit.crit, heavy: (hurtOpts.knockback || 0) > 0 });
    if (line) events.emit('log', { text: line.replace('{name}', enemy.cfg.name).replace('{n}', hit.amount) + (hit.crit ? ' A critical blow!' : ''), kind: 'hit' });
    if (enemy.dead) combat.onEnemyDefeated(enemy);
    // hitting an enemy with nothing engaged starts auto attack on it
    else if (spell.kind !== 'dot' && !this.game.targeting.attacking) this.game.targeting.engage(enemy);
    return hit;
  }

  // ----------------------------------------------------------------- time
  update(dt) {
    const { player, enemies, events } = this.game;
    // the cast bar: moving or dying breaks it, as in WoW
    const c = player.casting;
    if (c) {
      const gone = c.target && !c.target.alive;
      if (player.dead || player.moving || gone) {
        player.casting = null;
        player.rig.action = null;
        if (!player.dead) events.emit('log', { text: gone ? 'Your target is gone.' : 'Interrupted.', kind: 'muted', throttle: 'interrupted' });
        events.emit('castEnd', { id: c.id, done: false });
      } else if ((c.t += dt) >= c.total) {
        player.casting = null;
        const spell = SPELLS[c.id];
        player.cooldowns[c.id] = spell.tuning.cooldown;
        player.cooldowns.attack = Math.max(player.cooldowns.attack, this.game.stats.attackCooldown);
        events.emit('castEnd', { id: c.id, done: true });
        this._go(spell, c.target);
      }
    }

    for (let i = this.bolts.length - 1; i >= 0; i--) {
      const b = this.bolts[i];
      if ((b.t -= dt) > 0) continue;
      this.bolts.splice(i, 1);
      if (b.enemy.alive) this._damage(SPELLS[b.id], b.enemy, this._spellBase(SPELLS[b.id].tuning), `Your ${SPELLS[b.id].name} hits the {name} for {n}.`);
    }

    for (const [id, b] of this.buffs) {
      if ((b.left -= dt) <= 0) {
        this.buffs.delete(id);
        events.emit('log', { text: `${SPELLS[id].name} fades.`, kind: 'muted' });
      }
    }

    for (let i = this.dots.length - 1; i >= 0; i--) {
      const d = this.dots[i];
      const spell = SPELLS[d.id];
      if (!d.enemy.alive) {
        this.dots.splice(i, 1);
        continue;
      }
      d.left -= dt;
      d.next -= dt;
      if (d.next <= 1e-6) {
        d.next += spell.tuning.tickInterval;
        this._damage(spell, d.enemy, weaponRoll(this.game.random, this.game.stats), null, spell.tuning.tickMultiplier, { stagger: 0 });
      }
      if (d.left <= 1e-6) this.dots.splice(i, 1);
    }

    for (let i = this.zones.length - 1; i >= 0; i--) {
      const z = this.zones[i];
      const spell = SPELLS[z.id];
      const t = spell.tuning;
      z.left -= dt;
      z.next -= dt;
      if (z.next <= 1e-6) {
        z.next += t.tickInterval;
        for (const e of enemies.list) {
          if (e.alive && Math.hypot(e.position.x - z.x, e.position.z - z.z) - e.radius * 0.5 <= t.radius) this._damage(spell, e, this._spellBase(t), null, 1, { stagger: 0 });
        }
      }
      if (z.left <= 1e-6) this.zones.splice(i, 1);
    }
  }
}
