import { DB } from '../data/db.js';
import { CONFIG } from '../config.js';
import { computeHit, enemyBlock, weaponRoll, swingRoll } from './stats.js';

// The spell engine. Abilities in data/abilities.json with a `kind` are run
// here from their data alone, so a new spell is a new record, not new code:
//
//   cast     a cast bar (moving interrupts it), then a bolt flies at the
//            target; `ranged: true` makes it a held bow draw (Long Shot)
//   dot      a bleed, burn or rot on the target: ticks every `tickInterval`
//            for `duration` seconds; using it again refreshes it. It rolls
//            the weapon (`tickMultiplier` x a weapon roll), the bow, or its
//            own `damageMin`-`damageMax` (Rot)
//   instant  damage on the target at once
//   aoe      consecrates the ground around you (or, `target: 'ground'`, at
//            the cursor): enemies in it take a tick of damage every
//            `tickInterval` for `duration` seconds. `healPercent` heals you
//            while you stand in it (Hallowed Ground); `spreads` puts a dot on
//            everything inside each tick (Grave Bloom spreads Rot)
//   cleave   a wide swing hitting up to `maxTargets` enemies in front of you;
//            `spins: 2` swings twice (360 degrees for a spin)
//   burst    a blow around you (Shield Break, Divine Storm): every enemy
//            within `radius` is hit, staggered and knocked back;
//            `interrupts: 1` stops their ordinary attacks
//   guard    Brace, Guile: for `window` seconds blows are turned aside:
//            `blocks` of them (0 = all), or with `reduction` they hurt that
//            % less instead; `miss: 1` words it as misses
//   interrupt a word that breaks the target's interruptible cast and locks
//            it out of attacking for `lockout` seconds (Rebuke)
//   control  only its `applies` aura: Sleep, Hex of Withering, Bring to Kneel
//   charge   a dash of `distance` metres at the target (or the cursor) over
//            `duration` seconds that strikes on arrival (Lunge)
//   leap     a jump of `distance` metres away from your target (Disengage)
//   buff     raises all your damage by `damageBonus` % for `duration` seconds
//   stealth  Shadow: enemies lose sight of you until you attack or are hit
//   trap     a trap at your feet (up to `maxTraps`, each for `lifetime` s);
//            the first enemy within `triggerRadius` springs it into a pool
//            `radius` m across that slows enemies in it by `slow` % for
//            `duration` seconds (Tar Trap)
//   purge    spends all of its `spendsAll` bar: heals `healPerPoint` % of
//            your health a point, and your dots and curses last `extend`
//            seconds longer (Purge)
//   channel  a channelled drain on the target for `castTime` seconds, a tick
//            every `tickInterval`; each heals you `healPercent` % of the
//            damage (Siphon Life). Moving breaks it
//   shield   absorbs damage up to `absorbPercent` % of your health for
//            `duration` seconds (Light Shield)
//   camp     Set Camp: a cast, then the camp is pitched (systems/camp.js)
//
// What else a record may say:
//   applies   an aura on the target where the spell lands: { name, duration,
//             slow %, damageTaken %, damageDealt %, stun: 1, sleep: 1,
//             then: { another aura when it ends } }. Bosses are never
//             stunned or slept: control fills their stagger bar instead
//             (src/entities/enemy.js)
//   follow    another ability whose effect lands on the target too (Light's
//             Hammer's burn)
//   inShadow  the ability used instead while in Shadow (Strike -> Ambush)
//   spendsAll a bar it spends all of (combo points); tuning.perPoint adds
//             to its damageMultiplier for each point spent
//   bonusVs   { aura, percent }: more damage on a target with that aura
//   stacks    a stacking buff each hit gives you: { id, name, max, duration,
//             critBonus }; your next crit uses all the stacks (Righteous)
//   loadouts  tuning (and gain) by what you hold: twoHand (a weapon alone),
//             dualWield, shield (the Warrior's Weapon Master)
//
// Damage is either weapon based (`damageMultiplier` / `tickMultiplier` x a
// weapon roll, as Strike; `bothHands: 1` adds an off-hand roll when dual
// wielding) or a spell's own `damageMin`-`damageMax` (at level 1; it grows
// with level as (level + 4) / 5, see src/data/scaling.js) plus spell power.
// Spells trigger the global cooldown unless `offGlobalCooldown`; a spell's
// own cooldown starts when it goes off (after the cast, for cast spells).
//
// `ranged: true` makes an instant, dot or cast a bow shot (Quick Shot, Venom
// Arrow, Long Shot): it needs a bow in the ranged slot and an arrow,
// reaches as far as the bow does, and lands when its arrow arrives. Its
// damage is a bow roll (with the arrow's own damage) x `damageMultiplier` /
// `tickMultiplier`. `maxTargets` and `spread` shoot more arrows at enemies
// near the target (Triple Shot).
//
// `requires` names gear the ability cannot be used without: 'shield' (a
// working shield in the off hand: Shield Break), 'weapon' (a working
// melee weapon in the main hand, not bare fists) or a weapon type
// ('sword', 'dagger'...) in the main hand. Without it the bar slot dims and
// pressing it says what is missing, as WoW's "Requires Shield".
//
// Class traits (archetypes.json `trait`) are applied here too: Opportunist
// (crits from behind or from Shadow), Leech (dots heal), Empowered Light
// (swings echo with holy damage).
//
// Enemy spells go to the selected target, or the soft target near your aim
// (which then becomes selected), as in WoW.

export const SPELLS = Object.fromEntries(Object.values(DB.abilities).filter((a) => a.kind).map((a) => [a.id, a]));

// What an ability needs, worded for its tooltip ('Requires a shield in your
// off hand'), or null. Bow abilities (`ranged`) need a bow and arrows.
export function requirementText(ability) {
  if (ability?.ranged) return 'Requires a bow in your ranged slot, and arrows';
  const need = ability?.requires;
  if (!need) return null;
  if (need === 'shield') return 'Requires a shield in your off hand';
  if (need === 'weapon') return 'Requires a melee weapon in your main hand';
  return `Requires ${/^[aeiou]/i.test(need) ? 'an' : 'a'} ${need} in your main hand`;
}

// What the ability needs and is missing (the requirement, as above, or
// 'You have no arrows'), or null.
export function missingGear(game, ability) {
  if (ability?.ranged) {
    if (!game.stats.hasRanged) return requirementText(ability).replace(', and arrows', '');
    return game.inventory.ammo ? null : 'You have no arrows';
  }
  const need = ability?.requires;
  if (!need) return null;
  const inv = game.inventory;
  if (need === 'shield') {
    const s = inv.equipment.offHand;
    const v = s && DB.items[s.id]?.kind === 'shield' && game.itemView(s);
    return v && !v.broken ? null : requirementText(ability);
  }
  // (an item view has no id: the item's id is on the stack)
  const stack = inv.equipment.mainHand;
  const def = stack && DB.items[stack.id];
  if (!def || def.kind !== 'weapon' || game.itemView(stack).broken) return requirementText(ability);
  if (need !== 'weapon' && def.weaponType !== need) return requirementText(ability);
  return null;
}

// A bow ability, or a spell at an enemy from beyond melee reach (not a charge).
export function isRangedAttack(spell) {
  return !!spell && spell.target === 'enemy' && spell.kind !== 'charge' && (spell.ranged || spell.range > CONFIG.attack.range + 1);
}

// What you hold, for Weapon Master: 'shield', 'dualWield' or 'twoHand' (a
// weapon on its own).
export function loadoutOf(game) {
  const off = game.inventory.equipment.offHand;
  if (off && DB.items[off.id]?.kind === 'shield') return 'shield';
  return game.stats.dualWielding ? 'dualWield' : 'twoHand';
}

const AURA_EFFECTS = ['slow', 'damageTaken', 'damageDealt', 'stun', 'sleep'];

export class Spells {
  constructor(game) {
    this.game = game;
    this.reset();
    // pushback (WoW Classic): a blow taken while casting sets the cast bar
    // back by `castPushback` seconds, at most `maxPushbacks` times a cast.
    // A channel is not pushed back.
    game.events.on('playerHurt', (e) => {
      if (e.damage > 0) this.breakShadow();
      const c = game.player?.casting;
      const cfg = game.config;
      if (!c || c.channel || !(e.damage > 0) || c.pushbacks >= cfg.maxPushbacks) return;
      c.t = Math.max(0, c.t - cfg.castPushback);
      c.pushbacks += 1;
      game.events.emit('castPushback', { id: c.id });
    });
    // any blow you deal brings you out of Shadow
    game.events.on('enemyHit', () => this.breakShadow());
    game.events.on('autoAttack', ({ on }) => on && this.breakShadow());
  }

  reset() {
    this.buffs = new Map(); // id -> { name, icon, left, total, damageBonus, stacks, critBonus, absorb }
    this.dots = []; // { enemy, id, left, next }
    this.auras = []; // your auras on enemies: { enemy, id, name, left, total, slow, damageTaken, damageDealt, stun, sleep, then }
    this.zones = []; // { id, x, z, left, next, radius, slow, damage }
    this.traps = []; // { id, x, z, arm, left }
    this.bolts = []; // { enemy, id, t }
    this.blows = []; // cleaves and bursts on their way to the impact frame: { id, t, spell }
    this.queued = null; // a spell pressed in the queue window: { id, left }
    this.shadowGrace = 0; // seconds that still count as striking from Shadow
  }

  get trait() {
    return this.game.stats.archetype.trait || {};
  }

  // ---------------------------------------------------------- state for the HUD
  // all damage you deal is scaled by active buffs (and Overcorrupted)
  get damageScale() {
    let s = 1;
    for (const b of this.buffs.values()) s *= 1 + (b.damageBonus || 0) / 100;
    return s * (1 + (this.game.resources?.damageBonus || 0) / 100);
  }

  get hidden() {
    return this.buffs.has('shadow');
  }

  // [{ id, left, total }] for the buff row under the health bar
  buffList() {
    const list = [...this.buffs].map(([id, b]) => ({ id, icon: b.icon, name: b.stacks ? `${b.name} (${b.stacks})` : b.name, left: b.left, total: b.total }));
    const o = this.game.resources?.overload;
    if (o) list.push({ id: 'overload', icon: 'purge', name: o.name, left: Infinity, total: Infinity });
    return list;
  }

  // [{ id, left, total }] of your effects on one enemy, for the target frame
  dotsOn(enemy) {
    return [
      ...this.dots.filter((d) => d.enemy === enemy).map((d) => ({ id: d.id, left: d.left, total: SPELLS[d.id].tuning.duration })),
      ...this.auras.filter((a) => a.enemy === enemy).map((a) => ({ id: a.id.split(':')[0], name: a.name, left: a.left, total: a.total })),
    ];
  }

  hasAura(enemy, id) {
    return this.auras.some((a) => a.enemy === enemy && a.id === id) || this.dots.some((d) => d.enemy === enemy && d.id === id);
  }

  // the spell as it is now: Weapon Master's loadout changes, and the
  // Shadow version of an ability (Strike becomes Ambush)
  tuned(id) {
    let spell = SPELLS[id];
    if (!spell) return null;
    if (spell.inShadow && this.hidden && SPELLS[spell.inShadow]) spell = SPELLS[spell.inShadow];
    const lo = spell.loadouts?.[loadoutOf(this.game)];
    if (lo) spell = { ...spell, tuning: { ...spell.tuning, ...lo.tuning }, gain: lo.gain || spell.gain };
    return spell;
  }

  // --------------------------------------------------------------- casting
  // Try to use a spell; false (with a word in the log, where WoW would say
  // one) if it cannot go off now.
  tryCast(id) {
    const { player, events, stats } = this.game;
    // Nothing about auto attack blocks an ability: a swing or a shot on its
    // way never eats a key press (WoW). Only another cast, a charge in
    // flight, or the global cooldown does.
    if (!SPELLS[id] || player.dead || player.lunge || player.casting) return false;
    if (!this.game.skills.knowsAbility(id)) return false;
    let spell = this.tuned(id);
    const offGcd = !!spell.tuning.offGlobalCooldown;
    // WoW's spell queue: pressed in the last moments of the global cooldown
    // (or its own), it goes off the instant it can, with no error. The
    // cooldown is the bar ability's (Ambush shares Strike's).
    const wait = Math.max(offGcd ? 0 : player.cooldowns.gcd, player.cooldowns[id] || 0);
    if (wait > 0) {
      if (wait <= this.game.config.spellQueueWindow) this.queued = { id, left: wait + 0.05 };
      else if (player.cooldowns[id] > 0) this.game.hud.error(`${spell.name} is not ready yet`);
      return false;
    }
    if (this.queued?.id === id) this.queued = null;
    if (spell.kind === 'camp' && this.game.camp.enemiesNear) {
      this.game.hud.error('You cannot make camp with enemies close by');
      return false;
    }
    const casts = spell.kind === 'cast' || spell.kind === 'camp' || spell.kind === 'channel';
    if (casts && player.moving) {
      this.game.hud.error("You can't do that while moving");
      return false;
    }
    if (spell.kind === 'stealth' && this.hidden) return false;
    const missing = missingGear(this.game, spell);
    if (missing) {
      this.game.hud.error(missing);
      return false;
    }
    if (!this.game.resources.check(spell)) return false;
    let target = null;
    if (spell.kind === 'charge') {
      // a charge only ever goes at an enemy, never away from one
      target = this._targetFor(spell);
      if (!target) return false;
      this.game.resources.spend(spell);
      return this._charge(spell, target, id);
    }
    if (spell.kind === 'leap') {
      this.game.resources.spend(spell);
      return this._leap(spell, id);
    }
    if (spell.target === 'enemy') {
      target = this._targetFor(spell);
      if (!target) return false;
      // ranged attacks (bow abilities and spells cast from afar) need the
      // target in front of you, in the same arc as Auto Shot; melee ones
      // turn you to it
      if (isRangedAttack(spell)) {
        if (!player.facingPoint(target.position.x, target.position.z, CONFIG.attack.coneDegrees / 2)) {
          this.game.hud.error('You must be facing your target');
          return false;
        }
      } else player.faceTowards(target.position.x, target.position.z);
      // striking from Shadow: the blow still counts as from Shadow (Opportunist)
      this.breakShadow();
      // a spell at an enemy engages it: auto attack follows once in reach
      // (not Sleep: a swing would wake it)
      if (!spell.applies?.sleep) this.game.targeting.engage(target);
      else if (this.game.targeting.current === target) this.game.targeting.stopAttack();
    }
    if (!offGcd) player.cooldowns.gcd = stats.globalCooldown;
    const t = spell.tuning;
    // a cast pays when it finishes (WoW); everything else pays now
    if (spell.kind !== 'cast' && spell.kind !== 'camp') {
      const points = this.game.resources.spend(spell);
      if (spell.spendsAll) spell = { ...spell, points, tuning: { ...t, damageMultiplier: (t.damageMultiplier || 0) + (t.perPoint || 0) * points } };
    }
    if (casts) {
      // casting stops the swing: a swing or shot on its way is dropped, and
      // the timers start again when the cast ends (WoW Classic)
      if (player.pending && player.pending.type === 'strike') player.pending = null;
      player.pendingOff = null;
      player.pendingShot = null;
      player.holdBow(!!spell.ranged);
      const channel = spell.kind === 'channel';
      player.casting = { id, spell, t: 0, total: stats.hasted(t.castTime), target, pushbacks: 0, channel, next: channel ? t.tickInterval : 0 };
      if (channel) player.cooldowns[id] = t.cooldown;
      player.rig.play(spell.ranged ? 'shoot' : 'brace', player.casting.total, 0.9);
      events.emit('castStart', { id });
      return true;
    }
    if (spell.kind === 'cleave' || spell.kind === 'burst') {
      // the blow lands at its animation's impact frame, a moment after the
      // key press; it locks nothing and leaves the swing timer alone (WoW)
      const windup = stats.hasted(t.windup);
      const anim = spell.kind === 'burst' ? windup + 0.35 : windup + 0.3;
      this.blows.push({ id: spell.id, t: windup, spell });
      // a second spin (Cleave with two weapons) follows the first
      for (let k = 1; k < (t.spins || 1); k++) this.blows.push({ id: spell.id, t: windup + 0.3 * k, spell });
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
    const range = spell.ranged ? this.game.stats.rangedReach : spell.range;
    const inRange = (e) => e && e.alive && Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z) <= range + e.radius * 0.6;
    const cur = targeting.current;
    if (cur && cur.alive) {
      if (inRange(cur)) return cur;
      this.game.hud.error('Out of range');
      return optional ? false : null;
    }
    const soft = targeting.softTarget(this.game.rawAim || player.position, range);
    if (inRange(soft)) {
      targeting.select(soft);
      return soft;
    }
    if (optional) return null;
    this.game.hud.error('You have no target.');
    return null;
  }

  // Lunge and other charges: dash at the target, strike on arrival.
  _charge(spell, target, id = spell.id) {
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
    if (target) {
      this.breakShadow();
      this.game.targeting.engage(target);
    }
    player.facing = Math.atan2(dir.x, dir.z);
    player.cooldowns[id] = t.cooldown;
    player.cooldowns.gcd = stats.globalCooldown;
    player.cooldowns.attack = Math.max(player.cooldowns.attack, t.duration + 0.2);
    player.cooldowns.attackOff = Math.max(player.cooldowns.attackOff, t.duration + 0.2);
    player.lunge = { t: 0, dir, id: spell.id, speed: t.distance / t.duration, duration: t.duration };
    player.rig.play('strike', t.duration + 0.25, 0.7);
    events.emit('playerLunge', {});
    return true;
  }

  // Disengage: a jump back, away from the target (or from where you face);
  // you keep facing the way you were.
  _leap(spell, id = spell.id) {
    const { player, events, targeting } = this.game;
    const t = spell.tuning;
    const from = targeting.current?.alive ? targeting.current.position : null;
    let dir = { x: -Math.sin(player.facing), z: -Math.cos(player.facing) };
    if (from) {
      const dx = player.position.x - from.x;
      const dz = player.position.z - from.z;
      const len = Math.hypot(dx, dz);
      if (len > 0.3) dir = { x: dx / len, z: dz / len };
    }
    player.cooldowns[id] = t.cooldown;
    if (!t.offGlobalCooldown) player.cooldowns.gcd = this.game.stats.globalCooldown;
    player.lunge = { t: 0, dir, id: spell.id, speed: t.distance / t.duration, duration: t.duration };
    player.rig.play('brace', t.duration + 0.2, 0.5);
    events.emit('playerLunge', {});
    events.emit('log', { text: `${spell.name}!`, kind: 'muted' });
    return true;
  }

  // a spell going off: instant effects now, bolts and zones over time
  _go(spell, target) {
    const { player, events } = this.game;
    const t = spell.tuning;
    if (spell.ranged) return this._shoot(spell, target);
    if (spell.kind === 'cast') {
      const d = Math.hypot(target.position.x - player.position.x, target.position.z - player.position.z);
      this.bolts.push({ enemy: target, id: spell.id, t: d / t.projectileSpeed });
      events.emit('projectile', { kind: spell.school === 'holy' ? 'holy' : 'bolt', from: { x: player.position.x, y: player.position.y + 1.3, z: player.position.z }, to: target.position, speed: t.projectileSpeed, follow: target, life: d / t.projectileSpeed });
    } else if (spell.kind === 'instant') {
      player.rig.play('strike', 0.4, 0.4);
      // a weapon strike (`damageMultiplier`, e.g. Sinister Strike) rolls the weapon
      if (t.damageMultiplier !== undefined) {
        const hit = this._damage(spell, target, this._weaponBase(t), `Your ${spell.name} hits the {name} for {n}.`, t.damageMultiplier * this._bonusVs(spell, target), { stagger: 0.25, knockFrom: player.position, knockback: 0.3 });
        return void this._landed(spell, target, hit);
      }
      events.emit('spellFlash', { position: target.position, school: spell.school });
      const hit = this._damage(spell, target, this._spellBase(t), `Your ${spell.name} hits the {name} for {n}.`);
      this._landed(spell, target, hit);
    } else if (spell.kind === 'dot') {
      player.rig.play('strike', 0.45, 0.4);
      this._applyDot(spell, target);
    } else if (spell.kind === 'control') {
      player.rig.play('brace', 0.45, 0.4);
      events.emit('spellFlash', { position: target.position, school: spell.school });
      this._landed(spell, target, null);
    } else if (spell.kind === 'aoe') {
      player.rig.play('slam', 0.5, 0.5);
      const at = spell.target === 'ground' ? this._groundPoint(spell.range) : player.position;
      this.zones.push({ id: spell.id, x: at.x, z: at.z, left: t.duration, next: 0, radius: t.radius, damage: t.damageMax > 0 });
      events.emit('zone', { id: spell.id, x: at.x, z: at.z, radius: t.radius, duration: t.duration, school: spell.school });
      events.emit('log', { text: spell.target === 'ground' ? `${spell.name} takes root.` : `You consecrate the ground: ${spell.name}.`, kind: 'hit' });
    } else if (spell.kind === 'guard') {
      player.braced = t.window;
      player.guardRule = { blocks: t.blocks ?? 1, reduction: t.reduction || 0, miss: !!t.miss, name: spell.name };
      player.rig.play('brace', 0.5, 0.4);
      events.emit('playerBrace', { window: t.window });
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
      this.buffs.set(spell.id, { name: spell.name, left: t.duration, total: t.duration, damageBonus: t.damageBonus });
      events.emit('buff', { id: spell.id });
      events.emit('log', { text: `${spell.name}: your damage is raised by ${t.damageBonus}% for ${t.duration} seconds.`, kind: 'hit' });
    } else if (spell.kind === 'stealth') {
      this._enterShadow(spell);
    } else if (spell.kind === 'trap') {
      player.rig.play('slam', 0.45, 0.5);
      const key = `${spell.id}-${this.game.time.toFixed(3)}`;
      this.traps.push({ id: spell.id, key, x: player.position.x, z: player.position.z, arm: t.armTime, left: t.lifetime });
      while (this.traps.filter((x) => x.id === spell.id).length > t.maxTraps) {
        const old = this.traps.find((x) => x.id === spell.id);
        this.traps.splice(this.traps.indexOf(old), 1);
        events.emit('trapGone', { key: old.key });
      }
      events.emit('trap', { key, x: player.position.x, z: player.position.z, radius: t.triggerRadius, duration: t.lifetime });
      events.emit('log', { text: `You set a ${spell.name}.`, kind: 'muted' });
    } else if (spell.kind === 'purge') {
      const points = spell.points || 0;
      const healed = player.heal((player.maxHealth * t.healPerPoint * points) / 100);
      for (const d of this.dots) d.left += t.extend;
      for (const a of this.auras) if (!a.stun && !a.sleep) a.left += t.extend;
      if (healed >= 1) events.emit('damageNumber', { target: player, amount: Math.round(healed), kind: 'heal' });
      events.emit('buff', { id: spell.id });
      events.emit('log', { text: `You purge ${Math.round(points)} Corruption and heal ${Math.round(healed)}.`, kind: 'hit' });
    } else if (spell.kind === 'shield') {
      player.rig.play('brace', 0.5, 0.4);
      const absorb = Math.round((player.maxHealth * t.absorbPercent) / 100);
      this.buffs.set(spell.id, { name: spell.name, left: t.duration, total: t.duration, absorb });
      events.emit('buff', { id: spell.id });
      events.emit('log', { text: `${spell.name} will absorb ${absorb} damage.`, kind: 'hit' });
    }
  }

  // where a ground spell lands: the cursor, no further than its range
  _groundPoint(range) {
    const p = this.game.player.position;
    const aim = this.game.rawAim || { x: p.x + Math.sin(this.game.player.facing) * 4, z: p.z + Math.cos(this.game.player.facing) * 4 };
    const dx = aim.x - p.x;
    const dz = aim.z - p.z;
    const d = Math.hypot(dx, dz);
    const k = d > range ? range / d : 1;
    return { x: p.x + dx * k, z: p.z + dz * k };
  }

  // a weapon roll for an ability; `bothHands` adds the off hand's when dual wielding
  _weaponBase(t) {
    const { stats } = this.game;
    let base = weaponRoll(this.game.random, stats);
    if (t.bothHands && stats.dualWielding) base += weaponRoll(this.game.random, stats) * CONFIG.stats.offHandDamage;
    return base;
  }

  _bonusVs(spell, enemy) {
    return spell.bonusVs && this.hasAura(enemy, spell.bonusVs.aura) ? 1 + spell.bonusVs.percent / 100 : 1;
  }

  // what follows a spell's hit on its target: its aura, a follow-up
  // effect, and the stacks it gives you
  _landed(spell, enemy, hit) {
    if (!enemy.alive && hit) return;
    if (spell.applies) this.applyAura(spell.id, enemy, spell.applies);
    const f = spell.follow && SPELLS[spell.follow];
    if (f && enemy.alive) {
      if (f.kind === 'dot') this._applyDot(f, enemy, null, true);
      if (f.applies) this.applyAura(f.id, enemy, f.applies);
    }
    if (spell.stacks && hit) {
      const s = spell.stacks;
      const b = this.buffs.get(s.id);
      const stacks = Math.min(s.max, (b?.stacks || 0) + 1);
      this.buffs.set(s.id, { name: s.name, icon: spell.id, left: s.duration, total: s.duration, stacks, critBonus: s.critBonus });
    }
  }

  // Put an aura on an enemy (or refresh it). Stuns and sleeps go through
  // the enemy's control rules: a boss only staggers, an elite wears it off.
  applyAura(id, enemy, aura) {
    if (!enemy.alive) return;
    let left = aura.duration;
    if (aura.stun || aura.sleep) {
      left = enemy.control(aura.sleep ? 'sleep' : 'stun', aura.duration);
      if (left <= 0) {
        this.game.events.emit('log', { text: enemy.staggerBar ? `The ${enemy.cfg.name} cannot be ${aura.sleep ? 'slept' : 'stunned'}: it staggers.` : `The ${enemy.cfg.name} shrugs it off.`, kind: 'muted', throttle: 'cc-immune' });
        return;
      }
    }
    const had = this.auras.find((a) => a.enemy === enemy && a.id === id);
    const rec = { enemy, id, name: aura.name, left, total: left, then: aura.then || null };
    for (const k of AURA_EFFECTS) rec[k] = aura[k] || 0;
    if (had) Object.assign(had, rec);
    else this.auras.push(rec);
    if (!had) this.game.events.emit('log', { text: `The ${enemy.cfg.name} is ${aura.name.toLowerCase()}.`, kind: 'hit' });
  }

  // a dot takes hold (or is refreshed)
  _applyDot(spell, target, ammo = null, quiet = false) {
    const { events } = this.game;
    const t = spell.tuning;
    const had = this.dots.find((d) => d.enemy === target && d.id === spell.id);
    if (had) Object.assign(had, { left: t.duration, ammo });
    else this.dots.push({ enemy: target, id: spell.id, left: t.duration, next: t.tickInterval, ammo });
    if (quiet) return;
    target.hurt(0, { stagger: 0.1 }); // they notice
    events.emit('enemyHit', { enemy: target, damage: 0, kind: 'strike' });
    events.emit('log', { text: had ? `${spell.name} refreshed on the ${target.cfg.name}.` : `The ${target.cfg.name} is afflicted by ${spell.name}.`, kind: 'hit' });
  }

  // A bow ability: the bow comes to hand, one arrow is loosed, and the
  // spell's effect lands when it arrives. The Auto Shot timer is left alone.
  // Triple Shot looses more arrows at enemies near the target.
  _shoot(spell, target) {
    const { player, events, inventory, enemies } = this.game;
    const ammo = inventory.ammo;
    if (ammo) inventory.removeCount(ammo, 1);
    player.pendingShot = null;
    player.holdBow(true);
    player.rig.play('shoot', 0.45, 0.25);
    const from = { x: player.position.x + Math.sin(player.facing) * 0.4, y: player.position.y + 1.35, z: player.position.z + Math.cos(player.facing) * 0.4 };
    const speed = this.game.config.autoShot.arrowSpeed;
    const t = spell.tuning;
    const targets = [target];
    if (t.maxTargets > 1) {
      const near = enemies.list
        .filter((e) => e.alive && e !== target && Math.hypot(e.position.x - target.position.x, e.position.z - target.position.z) <= t.spread)
        .sort((a, b) => Math.hypot(a.position.x - target.position.x, a.position.z - target.position.z) - Math.hypot(b.position.x - target.position.x, b.position.z - target.position.z));
      targets.push(...near.slice(0, t.maxTargets - 1));
    }
    for (const e of targets) {
      const life = Math.hypot(e.position.x - from.x, e.position.z - from.z) / speed;
      this.bolts.push({ enemy: e, id: spell.id, t: life, ammo, spell });
      events.emit('projectile', { kind: 'arrow', from, to: e.position, follow: e, speed, life });
    }
    events.emit('playerShot', {});
  }

  // a bow roll plus the arrow's own damage (as Auto Shot's)
  _bowRoll(ammo) {
    const { stats } = this.game;
    return swingRoll(this.game.random, stats, 'ranged') + ((ammo && DB.items[ammo]?.ammoDps) || 0) * stats.handSpeed('ranged');
  }

  // a bow ability's arrow has arrived
  _arrowLands(spell, enemy, ammo) {
    this.game.events.emit('spellFlash', { position: enemy.position, school: spell.school });
    if (spell.kind === 'dot') return this._applyDot(spell, enemy, ammo);
    const hit = this._damage(spell, enemy, this._bowRoll(ammo), `Your ${spell.name} hits the {name} for {n}.`, spell.tuning.damageMultiplier, { stagger: 0.15, knockFrom: this.game.player.position, knockback: 0.1 });
    this._landed(spell, enemy, hit);
  }

  // Called by the player when a pending spell blow lands (cleave, burst, charge).
  resolve(id, spell = this.tuned(id)) {
    const { player } = this.game;
    if (player.dead || !spell) return [];
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
      if (t.coneDegrees < 360 && d > 0.8 && (dx * fx + dz * fz) / d < cosLimit) continue;
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
    for (const e of hits) most = Math.max(most, this._damage(spell, e, this._weaponBase(t), null, t.damageMultiplier, { stagger: 0.2, knockFrom: player.position, knockback: 0.3 }).amount);
    events.emit('log', { text: `${spell.name} hits ${hits.length === 1 ? 'the ' + hits[0].cfg.name : hits.length + ' foes'} for ${most}.`, kind: 'hit' });
    return hits;
  }

  _burst(spell) {
    const { player, enemies, events } = this.game;
    const t = spell.tuning;
    const hits = enemies.list.filter((e) => e.alive && Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z) - e.radius * 0.5 <= t.radius);
    let most = 0;
    for (const e of hits) most = Math.max(most, this._damage(spell, e, this._weaponBase(t), null, t.damageMultiplier, { stagger: t.stagger, knockFrom: player.position, knockback: t.knockback, heavy: !!t.interrupts }).amount);
    events.emit('burst', { id: spell.id, position: player.position.clone(), radius: t.radius, hits, school: spell.school });
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
    this._landed(spell, best, hit);
    return [best];
  }

  _spellBase(t) {
    return (t.damageMin + (t.damageMax - t.damageMin) * this.game.random()) * this.game.stats.spellScale + this.game.stats.spellPower;
  }

  // ------------------------------------------------------- your hits, any source
  // What changes a hit of yours on `enemy`: its auras (Marked), a boss's
  // stagger, Righteous stacks, and Opportunist. `weapon`: a weapon or bow
  // blow (Opportunist crits only those).
  hitMods(enemy, weapon = true) {
    const { player } = this.game;
    let critBonus = 0;
    for (const b of this.buffs.values()) critBonus += (b.critBonus || 0) * (b.stacks || 1);
    let forceCrit = false;
    if (weapon && this.trait.id === 'opportunist') {
      // from behind: you stand in the half of the ground the enemy faces away from
      const dx = player.position.x - enemy.position.x;
      const dz = player.position.z - enemy.position.z;
      const behind = dx * Math.sin(enemy.facing) + dz * Math.cos(enemy.facing) < 0;
      forceCrit = this.shadowGrace > 0 || this.hidden || behind;
    }
    return { mult: enemy.damageTakenScale, critBonus, forceCrit };
  }

  // after a hit of yours: a crit uses up the Righteous stacks
  afterHit(hit) {
    if (!hit?.crit) return;
    for (const [id, b] of this.buffs) if (b.critBonus) this.buffs.delete(id);
  }

  // One hit of a spell on an enemy: the shared damage formula, the number,
  // the log line ({name} and {n} filled in), and the kill.
  _damage(spell, enemy, base, line, mult = 1, hurtOpts = { stagger: 0.12 }) {
    const { stats, events, combat } = this.game;
    const weapon = !!spell.ranged || spell.tuning.damageMultiplier !== undefined || (spell.tuning.tickMultiplier !== undefined && spell.tuning.damageMin === undefined);
    const m = this.hitMods(enemy, weapon);
    const hit = computeHit(this.game.random, stats.statBlock, enemyBlock(enemy.cfg), { base, mult: mult * m.mult * this.damageScale * this.game.afterlife.damageScaleAgainst(enemy), school: spell.school || 'physical', critBonus: m.critBonus, forceCrit: m.forceCrit });
    this.afterHit(hit);
    enemy.hurt(hit.amount, hurtOpts);
    events.emit('damageNumber', { target: enemy, amount: hit.amount, crit: hit.crit, kind: 'dealt', hand: spell.ranged ? 'ranged' : 'main' });
    events.emit('enemyHit', { enemy, damage: hit.amount, crit: hit.crit, kind: (spell.school || 'physical') === 'physical' ? 'strike' : 'spell' });
    events.emit('hitImpact', { enemy, crit: hit.crit, heavy: (hurtOpts.knockback || 0) > 0 });
    if (line) events.emit('log', { text: line.replace('{name}', enemy.cfg.name).replace('{n}', hit.amount) + (hit.crit ? ' A critical blow!' : ''), kind: 'hit' });
    if (enemy.dead) combat.onEnemyDefeated(enemy);
    // hitting an enemy with nothing engaged starts auto attack on it
    else if (spell.kind !== 'dot' && !this.game.targeting.attacking) this.game.targeting.engage(enemy);
    return hit;
  }

  // Empowered Light: a swing that landed echoes with holy damage
  echo(enemy, hit) {
    const pct = this.trait.id === 'empoweredLight' ? this.trait.echoPercent : 0;
    if (!pct || !enemy.alive || !(hit?.amount > 0)) return;
    const n = Math.max(1, Math.round((hit.amount * pct) / 100));
    enemy.hurt(n, { stagger: 0, quiet: true });
    this.game.events.emit('damageNumber', { target: enemy, amount: n, crit: false, kind: 'dealt', hand: 'off' });
    this.game.events.emit('spellFlash', { position: enemy.position, school: 'holy' });
    if (enemy.dead) this.game.combat.onEnemyDefeated(enemy);
  }

  // ------------------------------------------------------------- Shadow
  _enterShadow(spell) {
    const { player, events, targeting, enemies } = this.game;
    targeting.stopAttack();
    player.pending = player.pending?.type === 'strike' ? null : player.pending;
    player.pendingOff = null;
    player.pendingShot = null;
    this.buffs.set('shadow', { name: spell.name, left: Infinity, total: Infinity });
    // whoever was after you loses you
    for (const e of enemies.list) if (e.alive && (e.state === 'chase' || e.state === 'attack')) e.loseTrack();
    player.setHidden(true);
    events.emit('log', { text: 'You slip into Shadow.', kind: 'muted' });
  }

  breakShadow() {
    if (!this.hidden) return;
    this.buffs.delete('shadow');
    this.shadowGrace = 0.6; // the opening blow still counts as from Shadow
    this.game.player.setHidden(false);
  }

  // ------------------------------------------------------------- absorbs
  // A blow on you: what a shield (Light Shield) soaks up first. Returns what is left.
  absorb(amount) {
    for (const [id, b] of this.buffs) {
      if (!b.absorb || amount <= 0) continue;
      const take = Math.min(b.absorb, amount);
      b.absorb -= take;
      amount -= take;
      if (b.absorb <= 0) {
        this.buffs.delete(id);
        this.game.events.emit('log', { text: `${b.name} breaks.`, kind: 'muted' });
      }
    }
    return amount;
  }

  // ----------------------------------------------------------------- time
  update(dt) {
    const { player, enemies, events } = this.game;
    this.shadowGrace = Math.max(0, this.shadowGrace - dt);
    // the cast bar: moving or dying breaks it, as in WoW
    const c = player.casting;
    if (c) {
      const gone = c.target && !c.target.alive;
      if (player.dead || player.moving || gone) {
        player.casting = null;
        player.rig.action = null;
        if (c.spell?.ranged) player.holdBow(false);
        if (!player.dead) events.emit('log', { text: gone ? 'Your target is gone.' : 'Interrupted.', kind: 'muted', throttle: 'interrupted' });
        events.emit('castEnd', { id: c.id, done: false });
      } else if (c.channel) {
        // a channel ticks as it goes and ends when the bar runs out
        c.t += dt;
        const spell = c.spell;
        const t = spell.tuning;
        while (c.t >= c.next - 1e-6 && c.next <= c.total + 1e-6) {
          c.next += this.game.stats.hasted(t.tickInterval);
          if (!c.target.alive) break;
          const hit = this._damage(spell, c.target, this._spellBase(t), null, 1, { stagger: 0 });
          const healed = player.heal((hit.amount * t.healPercent) / 100);
          if (healed >= 1) events.emit('damageNumber', { target: player, amount: Math.round(healed), kind: 'heal' });
        }
        if (c.t >= c.total) {
          player.casting = null;
          events.emit('castEnd', { id: c.id, done: true });
        }
      } else if ((c.t += dt) >= c.total) {
        player.casting = null;
        const spell = c.spell || SPELLS[c.id];
        const missing = spell.ranged && missingGear(this.game, spell);
        if (missing || !this.game.resources.check(spell)) {
          if (missing) this.game.hud.error(missing);
          events.emit('castEnd', { id: c.id, done: false });
        } else {
          this.game.resources.spend(spell);
          player.cooldowns[c.id] = spell.tuning.cooldown;
          player.cooldowns.attack = Math.max(player.cooldowns.attack, this.game.stats.attackCooldown);
          player.cooldowns.attackOff = Math.max(player.cooldowns.attackOff, this.game.stats.attackCooldownFor('off'));
          if (this.game.stats.hasRanged) player.cooldowns.ranged = Math.max(player.cooldowns.ranged, this.game.stats.attackCooldownFor('ranged'));
          events.emit('castEnd', { id: c.id, done: true });
          this._go(spell, c.target);
        }
      }
    }

    // cleaves and bursts land at their impact frame
    for (let i = this.blows.length - 1; i >= 0; i--) {
      const b = this.blows[i];
      if ((b.t -= dt) > 1e-6) continue;
      this.blows.splice(i, 1);
      this.resolve(b.id, b.spell);
    }

    // the spell queue: a spell pressed just before it was ready goes now
    if (this.queued && !player.casting && !player.lunge) {
      const q = this.queued;
      if ((q.left -= dt) <= 0) this.queued = null;
      const wait = Math.max(SPELLS[q.id].tuning.offGlobalCooldown ? 0 : player.cooldowns.gcd, player.cooldowns[q.id] || 0);
      if (wait <= 0) {
        this.queued = null;
        this.tryCast(q.id);
      }
    }

    for (let i = this.bolts.length - 1; i >= 0; i--) {
      const b = this.bolts[i];
      if ((b.t -= dt) > 0) continue;
      this.bolts.splice(i, 1);
      if (!b.enemy.alive) continue;
      const spell = b.spell || SPELLS[b.id];
      if (spell.ranged) this._arrowLands(spell, b.enemy, b.ammo);
      else this._landed(spell, b.enemy, this._damage(spell, b.enemy, this._spellBase(spell.tuning), `Your ${spell.name} hits the {name} for {n}.`));
    }

    for (const [id, b] of this.buffs) {
      if ((b.left -= dt) <= 0) {
        this.buffs.delete(id);
        events.emit('log', { text: `${b.name} fades.`, kind: 'muted' });
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
        const t = spell.tuning;
        const base = spell.ranged ? this._bowRoll(d.ammo) : t.damageMin !== undefined ? this._spellBase(t) : weaponRoll(this.game.random, this.game.stats);
        const hit = this._damage(spell, d.enemy, base, null, t.tickMultiplier, { stagger: 0 });
        events.emit('dotTick', { id: d.id, damage: hit.amount });
        // Leech: a share of every tick heals you
        const leech = this.trait.id === 'leech' ? this.trait.dotHealPercent : 0;
        if (leech) {
          const healed = player.heal((hit.amount * leech) / 100);
          if (healed >= 1) events.emit('damageNumber', { target: player, amount: Math.round(healed), kind: 'heal' });
        }
      }
      if (d.left <= 1e-6) this.dots.splice(i, 1);
    }

    // auras on enemies: they wear off (a sleep ends when the sleeper wakes),
    // and some hand over to the next (Bring to Kneel: slowed, then stunned)
    for (let i = this.auras.length - 1; i >= 0; i--) {
      const a = this.auras[i];
      a.left -= dt;
      const woke = a.sleep && !a.enemy.asleep;
      if (!a.enemy.alive || woke || a.left <= 1e-6) {
        this.auras.splice(i, 1);
        if (a.then && a.enemy.alive && !woke) this.applyAura(a.id + ':then', a.enemy, a.then);
      }
    }

    // traps arm, wait, and spring on the first enemy to step on one
    for (let i = this.traps.length - 1; i >= 0; i--) {
      const tr = this.traps[i];
      const spell = SPELLS[tr.id];
      const t = spell.tuning;
      tr.arm -= dt;
      tr.left -= dt;
      const prey = tr.arm <= 0 && enemies.list.find((e) => e.alive && Math.hypot(e.position.x - tr.x, e.position.z - tr.z) - e.radius * 0.5 <= t.triggerRadius);
      if (prey || tr.left <= 0) {
        this.traps.splice(i, 1);
        events.emit('trapGone', { key: tr.key });
      }
      if (prey) {
        this.zones.push({ id: tr.id, x: tr.x, z: tr.z, left: t.duration, next: Infinity, radius: t.radius, slow: t.slow, damage: false });
        events.emit('zone', { id: tr.id, x: tr.x, z: tr.z, radius: t.radius, duration: t.duration, school: 'tar' });
        events.emit('log', { text: `The ${prey.cfg.name} springs your ${spell.name}.`, kind: 'hit' });
      }
    }

    for (let i = this.zones.length - 1; i >= 0; i--) {
      const z = this.zones[i];
      const spell = SPELLS[z.id];
      const t = spell.tuning;
      z.left -= dt;
      z.next -= dt;
      if (z.next <= 1e-6) {
        z.next += t.tickInterval;
        const spread = spell.spreads && SPELLS[spell.spreads];
        for (const e of enemies.list) {
          if (!e.alive || Math.hypot(e.position.x - z.x, e.position.z - z.z) - e.radius * 0.5 > z.radius) continue;
          if (z.damage) this._damage(spell, e, this._spellBase(t), null, 1, { stagger: 0 });
          if (spread && e.alive) this._applyDot(spread, e, null, this.dots.some((d) => d.enemy === e && d.id === spread.id));
        }
        // Hallowed Ground heals you while you stand in it
        if (t.healPercent && Math.hypot(player.position.x - z.x, player.position.z - z.z) <= z.radius) {
          const healed = player.heal((player.maxHealth * t.healPercent) / 100);
          if (healed >= 1) events.emit('damageNumber', { target: player, amount: Math.round(healed), kind: 'heal' });
        }
      }
      if (z.left <= 1e-6) this.zones.splice(i, 1);
    }

    // what your auras and zones do to enemies this frame: slows, damage taken and dealt
    for (const e of enemies.list) e.mods = { slow: 0, taken: 1, dealt: 1 };
    for (const a of this.auras) {
      const m = a.enemy.mods;
      m.slow = Math.max(m.slow, a.slow);
      m.taken *= 1 + a.damageTaken / 100;
      m.dealt *= 1 + a.damageDealt / 100;
    }
    for (const z of this.zones) {
      if (!z.slow) continue;
      for (const e of enemies.list) if (e.alive && Math.hypot(e.position.x - z.x, e.position.z - z.z) - e.radius * 0.5 <= z.radius) e.mods.slow = Math.max(e.mods.slow, z.slow);
    }
  }
}
