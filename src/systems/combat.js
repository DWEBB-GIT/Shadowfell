import { CONFIG } from '../config.js';
import { computeHit, enemyBlock, weaponRoll, swingRoll, enemyRoll } from './stats.js';
import { ITEMS } from '../data/items.js';

// Combat rules: who a blow hits, how much it hurts, and what follows from a
// defeat. Entities ask; this system decides.

export class Combat {
  constructor(game) {
    this.game = game;
    this.arrows = []; // Auto Shot arrows in flight: { target, t }
    this.shownLater = []; // opener hits whose visuals wait for the windup: { t, fn }
  }

  // average damage of each weapon ability before the target's armour (for
  // the character panel); hits roll within `stats.abilityRange(mult)`
  get basicDamage() {
    return this.game.stats.abilityAverage(1);
  }


  // A weapon hit from the player on `enemy`: roll, crit, armour; applies it.
  // `swing`: an auto attack, which rolls the weapon's own per-swing damage;
  // abilities roll the normalised range (see Stats.abilityWeaponRange).
  // `show`: delay the hit's visuals (flinch, knockback, number, hit-stop)
  // by this many seconds; the damage itself lands now.
  _playerHit(enemy, mult, hurtOpts, { swing = false, hand = 'main', bonus = 0, show = 0 } = {}) {
    const { stats, events } = this.game;
    const r = this.game.random;
    const base = (swing ? swingRoll(r, stats, hand) : weaponRoll(r, stats)) + bonus;
    const sp = this.game.spells;
    const m = sp ? sp.hitMods(enemy) : { mult: 1, critBonus: 0, forceCrit: false };
    const hit = computeHit(r, stats.statBlock, enemyBlock(enemy.cfg), { base, mult: mult * m.mult * (sp ? sp.damageScale : 1) * this.game.afterlife.damageScaleAgainst(enemy), critBonus: m.critBonus, forceCrit: m.forceCrit });
    sp?.afterHit(hit);
    const visuals = () => {
      events.emit('damageNumber', { target: enemy, amount: hit.amount, crit: hit.crit, kind: 'dealt', hand: hand === 'ranged' ? 'ranged' : 'main' });
      events.emit('hitImpact', { enemy, crit: hit.crit, heavy: !!(hurtOpts && hurtOpts.heavy) || swing });
    };
    if (show > 0) {
      enemy.hurt(hit.amount, { stagger: 0, quiet: true });
      this.shownLater.push({ t: show, fn: () => { if (!enemy.dead) enemy.hurt(0, hurtOpts); visuals(); } });
    } else {
      enemy.hurt(hit.amount, hurtOpts);
      visuals();
    }
    return hit;
  }

  updateShown(dt) {
    for (const s of this.shownLater) s.t -= dt;
    const due = this.shownLater.filter((s) => s.t <= 1e-6);
    this.shownLater = this.shownLater.filter((s) => s.t > 1e-6);
    due.forEach((s) => s.fn());
  }

  // A blow from an enemy on the player: variance, crit, armour, block, then
  // what a curse (Hex), a guard (Brace with a weapon alone) and a shield of
  // light (Light Shield) take off it.
  _enemyHit(enemy, damage, { canCrit = true, canBlock = true, school = 'physical' } = {}) {
    const { stats, player, events } = this.game;
    const r = this.game.random;
    const mult = (enemy.damageDealtScale ?? 1) * (1 - player.damageReduction / 100);
    const hit = computeHit(r, enemyBlock(enemy.cfg), stats.statBlock, { base: enemyRoll(r, damage), mult, canCrit, canBlock, school });
    const left = this.game.spells ? this.game.spells.absorb(hit.amount) : hit.amount;
    if (left < hit.amount) hit.absorbed = hit.amount - left;
    hit.amount = left;
    if (hit.amount > 0) player.takeDamage(hit.amount);
    events.emit('damageNumber', { target: player, amount: hit.amount, crit: hit.crit, blocked: hit.blocked, kind: 'taken', usual: enemy.cfg.damage });
    return hit;
  }

  _critText(hit) {
    return hit.crit ? ' A critical blow!' : '';
  }


  // The hard-locked target, if it is alive and within reach.
  _selectedInReach(range) {
    const t = this.game.targeting && this.game.targeting.current;
    if (!t || !t.alive) return null;
    const p = this.game.player.position;
    return Math.hypot(t.position.x - p.x, t.position.z - p.z) <= range + t.radius * 0.6 ? t : null;
  }

  // Ground-telegraphed attacks hit whoever stands inside the marked area.
  resolveTelegraph(enemy, shape, damage, label, opts = null) {
    const { player, events } = this.game;
    if (enemy.dead || player.dead) return false;
    if (!shape.contains(player.position.x, player.position.z, player.radius)) {
      events.emit('enemyWhiff', { enemy });
      if (label) events.emit('log', { text: `You are clear of the ${label}.`, kind: 'muted' });
      return false;
    }
    const guard = player.consumeBrace();
    if (guard) {
      events.emit('braceBlock', { enemy, heavy: true });
      const what = label || enemy.cfg.name + "'s blow";
      events.emit('log', { text: guard === 'miss' ? `The ${what} misses you.` : guard === 'parry' ? `You parry the ${what}.` : `You brace and turn aside the ${what}.`, kind: 'hit' });
      return false;
    }
    // the slam cannot crit or be blocked; an ordinary cleave can be both.
    // Shots and spells say for themselves (`opts`).
    const special = !!label;
    const hit = this._enemyHit(enemy, damage, opts || { canCrit: !special, canBlock: !special });
    events.emit('playerHurt', { enemy, damage: hit.amount, crit: hit.crit, blocked: hit.blocked, heavy: !opts || !opts.canBlock });
    const who = opts && label ? `The ${enemy.cfg.name}'s ${label}` : label ? 'The ' + label : `The ${enemy.cfg.name}`;
    events.emit('log', { text: this._hurtText(who, hit), kind: 'hurt' });
    if (player.dead) this.game.onPlayerDeath(enemy);
    return true;
  }

  // Pick a sensible nearby target: living, within reach, roughly in front.
  selectStrikeTarget(aim) {
    const { player, enemies } = this.game;
    let dirX = Math.sin(player.facing);
    let dirZ = Math.cos(player.facing);
    if (aim) {
      const ax = aim.x - player.position.x;
      const az = aim.z - player.position.z;
      const len = Math.hypot(ax, az);
      if (len > 0.3) {
        dirX = ax / len;
        dirZ = az / len;
      }
    }
    const cosLimit = Math.cos(((CONFIG.attack.coneDegrees / 2) * Math.PI) / 180);
    let best = null;
    let bestScore = Infinity;
    for (const e of enemies.list) {
      if (!e.alive) continue;
      const dx = e.position.x - player.position.x;
      const dz = e.position.z - player.position.z;
      const dist = Math.hypot(dx, dz);
      const reach = CONFIG.attack.range + e.radius * 0.6;
      if (dist > reach) continue;
      const facingDot = dist > 0.01 ? (dx * dirX + dz * dirZ) / dist : 1;
      // very close enemies are hit regardless of angle; others must be in the arc
      if (dist > 1.0 && facingDot < cosLimit) continue;
      const score = dist - facingDot;
      if (score < bestScore) {
        bestScore = score;
        best = e;
      }
    }
    return best;
  }

  // `hand`: 'off' for a dual-wielded off-hand swing, which does less damage
  resolvePlayerStrike(aim, hand = 'main', show = 0) {
    const { player, events } = this.game;
    if (player.dead) return null;
    const target = this._selectedInReach(CONFIG.attack.range) || this.selectStrikeTarget(aim);
    if (!target) {
      events.emit('playerMiss', {});
      return null;
    }
    const off = hand === 'off';
    const hit = this._playerHit(target, off ? CONFIG.stats.offHandDamage : 1, { stagger: off ? 0.12 : 0.22, knockFrom: player.position, knockback: off ? 0.15 : 0.3 }, { swing: true, hand, show });
    events.emit('enemyHit', { enemy: target, damage: hit.amount, crit: hit.crit, kind: 'strike', swing: true, hand });
    events.emit('log', { text: `${off ? 'Your off hand strikes' : 'You strike'} the ${target.cfg.name} for ${hit.amount}.${this._critText(hit)}`, kind: 'hit' });
    if (target.dead) this.onEnemyDefeated(target);
    else this.game.spells?.echo(target, hit); // Empowered Light
    return target;
  }


  // Auto Shot: an arrow from the bow to the target. It flies (following the
  // target, as WoW's do) and does its damage when it arrives.
  loosePlayerArrow(target, ammo = null) {
    const { player, events } = this.game;
    const from = { x: player.position.x + Math.sin(player.facing) * 0.4, y: player.position.y + 1.35, z: player.position.z + Math.cos(player.facing) * 0.4 };
    const d = Math.hypot(target.position.x - from.x, target.position.z - from.z);
    const t = d / CONFIG.autoShot.arrowSpeed;
    this.arrows.push({ target, t, ammo });
    events.emit('projectile', { kind: 'arrow', from, to: target.position, follow: target, speed: CONFIG.autoShot.arrowSpeed, life: t });
    events.emit('playerShot', {});
  }

  updateArrows(dt) {
    for (let i = this.arrows.length - 1; i >= 0; i--) {
      const a = this.arrows[i];
      if ((a.t -= dt) > 1e-6) continue;
      this.arrows.splice(i, 1);
      const e = a.target;
      if (!e.alive || this.game.player.dead) continue;
      // the arrow adds its own damage: ammoDps for each second of bow speed
      const bonus = ((a.ammo && ITEMS[a.ammo].ammoDps) || 0) * this.game.stats.handSpeed('ranged');
      const hit = this._playerHit(e, 1, { stagger: 0.12, knockFrom: this.game.player.position, knockback: 0.1 }, { swing: true, hand: 'ranged', bonus });
      this.game.events.emit('enemyHit', { enemy: e, damage: hit.amount, crit: hit.crit, kind: 'strike', swing: true, hand: 'ranged' });
      this.game.events.emit('log', { text: `Your arrow hits the ${e.cfg.name} for ${hit.amount}.${this._critText(hit)}`, kind: 'hit' });
      if (e.dead) this.onEnemyDefeated(e);
    }
  }

  resolveEnemyStrike(enemy) {
    const { player, events } = this.game;
    if (enemy.dead || player.dead) return false;
    const d = Math.hypot(enemy.position.x - player.position.x, enemy.position.z - player.position.z);
    const reach = enemy.cfg.meleeRange + player.radius + enemy.radius * 0.5 + 0.35; // small grace for the swing
    if (d > reach) {
      events.emit('enemyWhiff', { enemy });
      return false;
    }
    const guard = player.consumeBrace();
    if (guard) {
      events.emit('braceBlock', { enemy });
      const who = enemy.cfg.name;
      events.emit('log', { text: guard === 'miss' ? `The ${who}'s blow misses you.` : guard === 'parry' ? `You parry the ${who}'s blow.` : `Your shield takes the ${who}'s blow.`, kind: 'hit' });
      return false;
    }
    const hit = this._enemyHit(enemy, enemy.cfg.damage);
    events.emit('playerHurt', { enemy, damage: hit.amount, crit: hit.crit, blocked: hit.blocked });
    events.emit('log', { text: this._hurtText(`The ${enemy.cfg.name}`, hit), kind: 'hurt' });
    if (player.dead) this.game.onPlayerDeath(enemy);
    return true;
  }

  _hurtText(who, hit) {
    if (hit.blocked && hit.amount === 0) return `You block ${who.replace(/^The/, 'the')}'s blow.`;
    const parts = [`${who} ${hit.crit ? 'critically hits' : 'hits'} you for ${hit.amount}`];
    if (hit.blocked) parts.push(` (${hit.blocked} blocked)`);
    if (hit.absorbed) parts.push(` (${hit.absorbed} absorbed)`);
    return parts.join('') + '.';
  }

  // Rewards are granted exactly once: the world state is the record.
  onEnemyDefeated(enemy) {
    const { worldState, progression, inventory, events, loot } = this.game;
    if (worldState.isDefeated(enemy.id)) return;
    worldState.markDefeated(enemy.id);
    // most enemies come back after their type's respawn time, so there is always something to fight
    if (enemy.cfg.respawn > 0) worldState.respawnAt[enemy.id] = worldState.time + enemy.cfg.respawn;
    events.emit('enemyDefeated', { enemy });
    events.emit('log', { text: `The ${enemy.cfg.name} falls still.`, kind: 'kill' });
    progression.addXp(enemy.cfg.xp, { kill: true });
    if (enemy.cfg.reputation) this.game.reputation.addAll(enemy.cfg.reputation);
    // coins stay on the body until looted (click it, or E / A beside it)
    if (enemy.cfg.coins > 0) loot.addCorpse(enemy, enemy.cfg.coins);
    if (enemy.cfg.uniqueDrop) loot.dropUnique(enemy);
    loot.dropFromEnemy(enemy);
    this.game.afterlife.onEnemyDefeated(enemy);
  }
}
