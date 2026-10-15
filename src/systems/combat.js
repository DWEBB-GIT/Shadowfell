import { CONFIG } from '../config.js';
import { computeHit, enemyBlock, weaponRoll, swingRoll, enemyRoll } from './stats.js';

// Combat rules: who a blow hits, how much it hurts, and what follows from a
// defeat. Entities ask; this system decides.

export class Combat {
  constructor(game) {
    this.game = game;
  }

  // average damage of each weapon ability before the target's armour (for
  // the character panel); hits roll within `stats.abilityRange(mult)`
  get basicDamage() {
    return this.game.stats.abilityAverage(1);
  }

  get shieldBreakDamage() {
    return this.game.stats.abilityAverage(CONFIG.shieldBreak.damageMultiplier);
  }

  get lungeDamage() {
    return this.game.stats.abilityAverage(CONFIG.lunge.damageMultiplier);
  }

  // A weapon hit from the player on `enemy`: roll, crit, armour; applies it.
  // `swing`: an auto attack, which rolls the weapon's own per-swing damage;
  // abilities roll the normalised range (see Stats.abilityWeaponRange).
  _playerHit(enemy, mult, hurtOpts, { swing = false } = {}) {
    const { stats, events } = this.game;
    const r = this.game.random;
    const base = swing ? swingRoll(r, stats) : weaponRoll(r, stats);
    const hit = computeHit(r, stats.statBlock, enemyBlock(enemy.cfg), { base, mult: mult * (this.game.spells ? this.game.spells.damageScale : 1) * this.game.afterlife.damageScaleAgainst(enemy) });
    enemy.hurt(hit.amount, hurtOpts);
    events.emit('damageNumber', { target: enemy, amount: hit.amount, crit: hit.crit, kind: 'dealt' });
    events.emit('hitImpact', { enemy, crit: hit.crit, heavy: !!(hurtOpts && hurtOpts.heavy) || swing });
    return hit;
  }

  // A blow from an enemy on the player: variance, crit, armour, block.
  _enemyHit(enemy, damage, { canCrit = true, canBlock = true, school = 'physical' } = {}) {
    const { stats, player, events } = this.game;
    const r = this.game.random;
    const hit = computeHit(r, enemyBlock(enemy.cfg), stats.statBlock, { base: enemyRoll(r, damage), canCrit, canBlock, school });
    if (hit.amount > 0) player.takeDamage(hit.amount);
    events.emit('damageNumber', { target: player, amount: hit.amount, crit: hit.crit, blocked: hit.blocked, kind: 'taken' });
    return hit;
  }

  _critText(hit) {
    return hit.crit ? ' A critical blow!' : '';
  }

  // Lunge lands on the nearest living enemy around the end of the charge.
  resolveLunge() {
    const { player, enemies, events } = this.game;
    if (player.dead) return null;
    let best = this._selectedInReach(CONFIG.lunge.hitRadius + 0.4);
    let bestD = best ? -Infinity : Infinity;
    for (const e of enemies.list) {
      if (!e.alive || best === e) continue;
      const d = Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z) - e.radius;
      if (d <= CONFIG.lunge.hitRadius && d < bestD) {
        best = e;
        bestD = d;
      }
    }
    if (!best) {
      events.emit('playerMiss', {});
      return null;
    }
    player.faceTowards(best.position.x, best.position.z);
    this.game.targeting.engage(best);
    const hit = this._playerHit(best, CONFIG.lunge.damageMultiplier, { stagger: 0.3, knockFrom: player.position, knockback: 0.4 });
    events.emit('enemyHit', { enemy: best, damage: hit.amount, crit: hit.crit, kind: 'strike' });
    events.emit('log', { text: `You lunge into the ${best.cfg.name} for ${hit.amount}.${this._critText(hit)}`, kind: 'hit' });
    if (best.dead) this.onEnemyDefeated(best);
    return best;
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
    if (player.consumeBrace()) {
      events.emit('braceBlock', { enemy, heavy: true });
      events.emit('log', { text: `You brace and turn aside the ${label || enemy.cfg.name + "'s blow"}.`, kind: 'hit' });
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

  resolvePlayerStrike(aim) {
    const { player, events } = this.game;
    if (player.dead) return null;
    const target = this._selectedInReach(CONFIG.attack.range) || this.selectStrikeTarget(aim);
    if (!target) {
      events.emit('playerMiss', {});
      return null;
    }
    const hit = this._playerHit(target, 1, { stagger: 0.22, knockFrom: player.position, knockback: 0.3 }, { swing: true });
    events.emit('enemyHit', { enemy: target, damage: hit.amount, crit: hit.crit, kind: 'strike' });
    events.emit('log', { text: `You strike the ${target.cfg.name} for ${hit.amount}.${this._critText(hit)}`, kind: 'hit' });
    if (target.dead) this.onEnemyDefeated(target);
    return target;
  }

  resolveShieldBreak() {
    const { player, enemies, events } = this.game;
    if (player.dead) return [];
    const hits = [];
    const dealt = [];
    for (const e of enemies.list) {
      if (!e.alive) continue;
      const d = Math.hypot(e.position.x - player.position.x, e.position.z - player.position.z);
      if (d - e.radius * 0.5 > CONFIG.shieldBreak.radius) continue;
      const hit = this._playerHit(e, CONFIG.shieldBreak.damageMultiplier, { stagger: CONFIG.shieldBreak.stagger, knockFrom: player.position, knockback: CONFIG.shieldBreak.knockback, heavy: true });
      hits.push(e);
      dealt.push(hit.amount);
    }
    const dmg = dealt.length ? Math.max(...dealt) : 0;
    // striking engages: auto attack the target, or the first foe hit
    const tg = this.game.targeting;
    const alive = hits.filter((e) => e.alive);
    if (alive.length) tg.engage(tg.current && alive.includes(tg.current) ? tg.current : alive[0]);
    events.emit('shieldBreak', { position: player.position.clone(), radius: CONFIG.shieldBreak.radius, hits });
    if (hits.length) {
      const names = hits.length === 1 ? `the ${hits[0].cfg.name}` : `${hits.length} foes`;
      events.emit('log', { text: `Shield Break staggers ${names} for ${dmg}.`, kind: 'hit' });
    } else {
      events.emit('log', { text: 'Shield Break strikes only earth.', kind: 'muted' });
    }
    for (const e of hits) if (e.dead) this.onEnemyDefeated(e);
    return hits;
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
    if (player.consumeBrace()) {
      events.emit('braceBlock', { enemy });
      events.emit('log', { text: `Your shield takes the ${enemy.cfg.name}'s blow.`, kind: 'hit' });
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
    return parts.join('') + '.';
  }

  // Rewards are granted exactly once: the world state is the record.
  onEnemyDefeated(enemy) {
    const { worldState, progression, inventory, events, loot } = this.game;
    if (worldState.isDefeated(enemy.id)) return;
    worldState.markDefeated(enemy.id);
    events.emit('enemyDefeated', { enemy });
    events.emit('log', { text: `The ${enemy.cfg.name} falls still.`, kind: 'kill' });
    progression.addXp(enemy.cfg.xp, { kill: true });
    // coins stay on the body until looted (click it, or E / A beside it)
    if (enemy.cfg.coins > 0) loot.addCorpse(enemy, enemy.cfg.coins);
    if (enemy.cfg.uniqueDrop) loot.dropUnique(enemy);
    loot.dropFromEnemy(enemy);
    this.game.afterlife.onEnemyDefeated(enemy);
  }
}
