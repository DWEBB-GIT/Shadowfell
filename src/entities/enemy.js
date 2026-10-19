import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { Rig, setEmissive, FLASH_RED, FLASH_WHITE } from './rig.js';
import { heightAt } from '../world/terrain.js';
import { spawnHealth } from '../data/scaling.js';

// One undead enemy. AI states: idle -> chase -> attack, return home when the
// player escapes, dead when health reaches zero. Deliberately simple.
//
// What an enemy can do comes from its config: a melee swing (every enemy),
// a telegraphed cleave and special (the brute), a pack that wakes together
// (hounds), an aimed shot down a painted line that keeps its distance
// (archers, and the seer's bolt), and a circle cast under the Warden's feet
// that costs mana (the seer). Out of mana, a caster closes to melee.

export class Enemy {
  constructor(game, spawn) {
    this.game = game;
    this.id = spawn.id;
    this.type = spawn.type;
    this.cfg = CONFIG.enemies[spawn.type];
    this.home = new THREE.Vector3(spawn.position[0], 0, spawn.position[1]);
    this.position = this.home.clone();
    this.position.y = heightAt(this.position.x, this.position.z);
    this.facing = Math.random() * Math.PI * 2;
    this.radius = this.cfg.radius;
    // each spawn point's enemy is a little leaner or bigger than its type (+-10%)
    this.maxHealth = this.cfg.type === 'boss' || this.cfg.dummy ? this.cfg.health : spawnHealth(this.cfg.health, this.id);
    this.health = this.maxHealth;
    this.mana = this.cfg.mana || 0; // only enemies whose config gives them mana have any
    this.state = 'idle';
    this.attackTimer = 0.6;
    this.windup = 0; // > 0 while an attack is being telegraphed
    this.casting = null; // ground-telegraphed attack in progress: { kind, telegraph }
    this.specialTimer = 3; // first Grave Slam comes a few seconds into a fight
    this.circleTimer = 2.5; // first circle spell, likewise
    this.stagger = 0;
    this.knock = new THREE.Vector3();
    this.flash = 0;
    this.flashColor = FLASH_RED;
    this.engaged = 0; // seconds to keep showing the health bar
    this.dead = false;
    this.wander = { t: Math.random() * 3, target: this.home.clone() };

    this.group = new THREE.Group();
    this.group.name = 'Enemy_' + this.id;
    this.model = game.assets.instance(this.cfg.model);
    this.group.add(this.model);
    this.rig = new Rig(this.model, this.type);
    this.materials = Rig.isolateMaterials(this.model);
    // a rare elite reuses its kin's model, sized and tinted
    if (this.cfg.scale) this.model.scale.multiplyScalar(this.cfg.scale);
    if (this.cfg.tint) for (const m of this.materials) m.color.multiply(new THREE.Color(this.cfg.tint));
    this._sync();
  }

  get alive() {
    return !this.dead;
  }

  _sync() {
    this.group.position.copy(this.position);
    this.group.rotation.y = this.facing;
  }

  reset() {
    // used on player respawn: surviving enemies return to their posts
    if (this.dead) return;
    this.position.copy(this.home);
    this.position.y = heightAt(this.home.x, this.home.z);
    this.health = this.maxHealth;
    this.mana = this.cfg.mana || 0;
    this.state = 'idle';
    this.windup = 0;
    this._cancelCast();
    this.specialTimer = 3;
    this.circleTimer = 2.5;
    this.stagger = 0;
    this.engaged = 0;
    this.rig.action = null;
    this._sync();
  }

  // `quiet`: the damage only; its flash and flinch are shown later
  hurt(amount, { stagger = 0.15, knockFrom = null, knockback = 0, heavy = false, quiet = false } = {}) {
    if (this.dead) return 0;
    const dealt = Math.min(this.health, amount);
    this.health -= dealt;
    this.engaged = 6;
    if (!quiet) {
      this.flash = 1;
      this.flashColor = heavy ? FLASH_WHITE : FLASH_RED;
      this.rig.hit();
    }
    this.stagger = Math.max(this.stagger, stagger);
    if (heavy && !(this.casting && !this.casting.interruptible)) {
      // a heavy blow interrupts an ordinary swing or an interruptible cast;
      // casts marked `interruptible: false` in the data (Grave Slam) go on
      this.windup = 0;
      this.rig.action = null;
      this._cancelCast();
    }
    if (knockFrom && knockback > 0) {
      const dir = new THREE.Vector3(this.position.x - knockFrom.x, 0, this.position.z - knockFrom.z);
      if (dir.lengthSq() > 0.0001) this.knock.copy(dir.normalize().multiplyScalar(knockback * 6));
    }
    if (!this.cfg.dummy && (this.state === 'idle' || this.state === 'return')) {
      this.state = 'chase';
      this._wakePack();
    }
    if (this.health <= 0 && this.cfg.dummy) {
      // the training dummy never dies: it is whole again
      this.health = this.maxHealth;
    } else if (this.health <= 0) {
      this.dead = true;
      this.state = 'dead';
      this.windup = 0;
      this._cancelCast();
      this.rig.die();
    }
    return dealt;
  }

  // An interrupt (Rebuke): breaks an interruptible cast and holds off the
  // next attack for `lockout` seconds. Returns what was broken, or null.
  interrupt(lockout) {
    if (this.dead || !this.casting) return null;
    if (!this.casting.interruptible) return false;
    const label = this.casting.label;
    this._cancelCast();
    this.rig.action = null;
    this.attackTimer = Math.max(this.attackTimer || 0, lockout);
    if (this.circleTimer !== undefined) this.circleTimer = Math.max(this.circleTimer, lockout);
    return label;
  }

  _cancelCast() {
    if (this.casting) this.game.telegraphs.cancel(this.casting.telegraph);
    this.casting = null;
  }

  // A hound that wakes brings the rest of its pack.
  _wakePack() {
    if (!this.cfg.pack) return;
    for (const o of this.game.enemies.list) {
      if (o === this || !o.alive || o.type !== this.type || o.state !== 'idle') continue;
      if (Math.hypot(o.position.x - this.position.x, o.position.z - this.position.z) <= this.cfg.pack) o.state = 'chase';
    }
  }

  // An aimed shot: a line is painted towards the Warden; when it fills, the
  // arrow (or bolt) flies down it and hits whoever is still on it.
  _startShot(player) {
    const r = this.cfg.ranged;
    const angle = Math.atan2(player.position.x - this.position.x, player.position.z - this.position.z);
    this.facing = angle;
    const bolt = r.projectile === 'bolt';
    const telegraph = this.game.telegraphs.line(this, {
      angle,
      length: r.range + 1,
      width: r.width,
      duration: r.windup,
      color: bolt ? 0x8a6cff : 0xe8a040,
      onComplete: (shape) => {
        this.casting = null;
        const end = { x: shape.x + Math.sin(angle) * shape.length, z: shape.z + Math.cos(angle) * shape.length };
        const p = this.game.player.position;
        const onLine = shape.contains(p.x, p.z, this.game.player.radius);
        // the shot stops at the Warden if it hits, otherwise flies on
        const to = onLine ? { x: p.x, z: p.z } : end;
        this.game.events.emit('projectile', { kind: r.projectile, from: { x: this.position.x, z: this.position.z, y: this.position.y + 1.3 }, to, speed: r.speed });
        this.game.combat.resolveTelegraph(this, shape, r.damage, r.name, { canCrit: true, canBlock: true, school: r.school || 'physical' });
      },
    });
    if (r.mana) this.mana -= r.mana;
    this.casting = { kind: 'shot', telegraph, label: r.name, interruptible: r.interruptible !== false };
    this.attackTimer = r.interval;
    this.rig.play(bolt ? 'cast' : 'shoot', r.windup + 0.25, r.windup / (r.windup + 0.25));
    this.game.events.emit('enemyWindup', { enemy: this });
  }

  // A circle under the Warden's feet that fills, then strikes; walk out of it.
  _startCircle(player) {
    const c = this.cfg.circle;
    this.facing = Math.atan2(player.position.x - this.position.x, player.position.z - this.position.z);
    const telegraph = this.game.telegraphs.circle(this, {
      x: player.position.x,
      z: player.position.z,
      radius: c.radius,
      duration: c.windup,
      onComplete: (shape) => {
        this.casting = null;
        this.game.events.emit('darkCircle', { x: shape.x, z: shape.z, radius: shape.range });
        this.game.combat.resolveTelegraph(this, shape, c.damage, c.name, { canCrit: false, canBlock: false, school: c.school || 'physical' });
      },
    });
    this.mana -= c.mana;
    this.circleTimer = c.cooldown;
    this.attackTimer = Math.max(this.attackTimer, c.windup + 0.5);
    this.casting = { kind: 'circle', telegraph, label: c.name, interruptible: c.interruptible !== false };
    this.rig.play('cast', c.windup + 0.3, c.windup / (c.windup + 0.3));
    this.game.events.emit('log', { text: `The ${this.cfg.name} calls the dark up out of the earth. Move!`, kind: 'hurt', throttle: 'circle-warn' });
    this.game.events.emit('enemyWindup', { enemy: this, special: true });
  }

  // Telegraphed attacks: the area is fixed now and lands when it fills.
  _startCast(kind, player) {
    const cfg = this.cfg;
    const sp = cfg.special;
    const angle = Math.atan2(player.position.x - this.position.x, player.position.z - this.position.z);
    this.facing = angle;
    const special = kind === 'special';
    const duration = special ? sp.windup : cfg.windup;
    const range = special ? sp.range : cfg.meleeRange + this.radius + 0.9;
    const telegraph = this.game.telegraphs.cone(this, {
      angle,
      range,
      arc: special ? sp.arc : 100,
      duration,
      heavy: special,
      onComplete: (shape) => {
        this.casting = null;
        const hit = this.game.combat.resolveTelegraph(this, shape, special ? sp.damage : cfg.damage, special ? sp.name : null);
        if (special) this.game.events.emit('graveSlam', { enemy: this, shape, hit });
      },
    });
    this.casting = { kind, telegraph, label: special ? sp.name : 'Cleave', interruptible: special ? sp.interruptible !== false : true };
    if (special) {
      this.specialTimer = sp.cooldown;
      this.attackTimer = Math.max(this.attackTimer, sp.windup + 0.6);
      this.rig.play('slam', sp.windup + 0.4, sp.windup / (sp.windup + 0.4));
      this.game.events.emit('log', { text: `The ${cfg.name} raises its cleaver high. Get clear!`, kind: 'hurt', throttle: 'slam-warn' });
    } else {
      this.attackTimer = cfg.attackInterval;
      this.rig.play('cleave', duration + 0.3, duration / (duration + 0.3));
    }
    this.game.events.emit('enemyWindup', { enemy: this, special });
  }

  update(dt, player) {
    this.flash = Math.max(0, this.flash - dt * 5);
    setEmissive(this.materials, this.flashColor, this.flash * (this.flashColor === FLASH_WHITE ? 0.35 : 0.6));
    this.engaged = Math.max(0, this.engaged - dt);

    if (this.dead || this.cfg.dummy) {
      // the dummy just stands there, and mends a few seconds after the last hit
      if (this.cfg.dummy && this.engaged <= 0) this.health = this.maxHealth;
      // ...and never leaves its post: no knockback, no shoving
      if (this.cfg.dummy) {
        this.knock.set(0, 0, 0);
        this.position.x = this.home.x;
        this.position.z = this.home.z;
      }
      this.rig.update(dt, 0);
      this._sync();
      return;
    }

    const cfg = this.cfg;
    const dx = player.position.x - this.position.x;
    const dz = player.position.z - this.position.z;
    const dist = Math.hypot(dx, dz);
    const fromHome = Math.hypot(this.position.x - this.home.x, this.position.z - this.home.z);
    const reach = cfg.meleeRange + player.radius + this.radius * 0.5;
    let speed01 = 0;

    // knockback slides, easing out exponentially so the distance is the same
    // at any frame rate
    if (this.knock.lengthSq() > 0.001) {
      const fade = Math.exp(-9 * dt);
      this.position.addScaledVector(this.knock, (1 - fade) / 9);
      this.knock.multiplyScalar(fade);
    }

    if (this.stagger > 0) {
      this.stagger -= dt;
    } else if (player.dead) {
      if (this.state !== 'idle') this.state = 'return';
    } else {
      switch (this.state) {
        case 'idle':
          if (dist < cfg.detection) {
            this.state = 'chase';
            this.game.events.emit('enemyAlert', { enemy: this });
            this._wakePack();
          }
          break;
        case 'chase':
        case 'attack':
          if (fromHome > CONFIG.enemies.leashDistance || dist > cfg.detection * 2) {
            this.state = 'return';
            this.windup = 0;
            break;
          }
          this.state = dist <= reach ? 'attack' : 'chase';
          this.engaged = Math.max(this.engaged, 2);
          break;
        case 'return':
          if (dist < cfg.detection * 0.8 && fromHome < CONFIG.enemies.leashDistance * 0.6) this.state = 'chase';
          else if (fromHome < 0.6) this.state = 'idle';
          break;
        default:
          break;
      }
    }

    this.attackTimer = Math.max(0, this.attackTimer - dt);
    this.specialTimer = Math.max(0, this.specialTimer - dt);
    this.circleTimer = Math.max(0, this.circleTimer - dt);
    if (cfg.mana) this.mana = Math.min(cfg.mana, this.mana + (cfg.manaRegen || 0) * dt);
    if (player.dead && this.casting) this._cancelCast();
    const fighting = this.state === 'chase' || this.state === 'attack';
    const rg = cfg.ranged;
    const canShoot = rg && this.mana >= (rg.mana || 0);
    const cc = cfg.circle;

    if (this.casting) {
      // committed: hold position while the telegraph fills
      speed01 = 0;
    } else if (this.stagger <= 0 && !player.dead) {
      const sp = cfg.special;
      if (sp && this.specialTimer <= 0 && dist < sp.trigger && fighting) {
        this._startCast('special', player);
      } else if (cc && fighting && this.circleTimer <= 0 && this.mana >= cc.mana && dist <= cc.range) {
        this._startCircle(player);
      } else if (canShoot && fighting && dist > reach) {
        // a ranged enemy holds its distance: closes to range, backs off
        // when the Warden gets close, and shoots when it is ready
        this.facing = Math.atan2(dx, dz);
        if (dist > rg.range * 0.9) {
          this._moveTowards(player.position.x, player.position.z, cfg.speed, dt, rg.range * 0.8);
          speed01 = 1;
        } else if (dist < rg.keep) {
          this.position.x -= (dx / dist) * cfg.speed * 0.75 * dt;
          this.position.z -= (dz / dist) * cfg.speed * 0.75 * dt;
          speed01 = 0.7;
          if (this.attackTimer <= 0) this._startShot(player);
        } else if (this.attackTimer <= 0) {
          this._startShot(player);
        }
      } else if (this.state === 'chase') {
        this._moveTowards(player.position.x, player.position.z, cfg.speed, dt, reach * 0.85);
        speed01 = 1;
        if (this.windup > 0) this.windup = 0;
      } else if (this.state === 'attack' && cfg.telegraph) {
        this.facing = Math.atan2(dx, dz);
        if (this.attackTimer <= 0) this._startCast('normal', player);
      } else if (this.state === 'attack') {
        this.facing = Math.atan2(dx, dz);
        if (this.windup > 0) {
          this.windup -= dt;
          if (this.windup <= 0) {
            this.windup = 0;
            this.game.combat.resolveEnemyStrike(this);
          }
        } else if (this.attackTimer <= 0) {
          // telegraph, then strike; the interval runs from the start of the swing
          this.windup = cfg.windup;
          this.attackTimer = cfg.attackInterval;
          this.rig.play(cfg.meleeAnim || (this.type === 'brute' ? 'cleave' : 'claw'), cfg.windup + 0.3, cfg.windup / (cfg.windup + 0.3));
          this.game.events.emit('enemyWindup', { enemy: this });
        }
      }
    }
    if (this.casting) {
      // nothing else moves while committed to a telegraphed attack
    } else if (this.state === 'return' && this.stagger <= 0) {
      this._moveTowards(this.home.x, this.home.z, cfg.speed * 0.8, dt, 0.3);
      speed01 = 0.8;
      this.health = Math.min(this.maxHealth, this.health + dt * 6);
    } else if (this.state === 'idle') {
      speed01 = this._idleShuffle(dt);
    }

    this.game.collision.resolve(this.position, this.radius);
    this.position.y = heightAt(this.position.x, this.position.z);
    this.rig.update(dt, speed01 * (this.type === 'brute' ? 0.8 : this.type === 'hound' ? 1 : 0.7));
    this._sync();
  }

  _moveTowards(x, z, speed, dt, stopAt) {
    const dx = x - this.position.x;
    const dz = z - this.position.z;
    const d = Math.hypot(dx, dz);
    if (d < 0.0001) return;
    this.facing = Math.atan2(dx, dz);
    if (d <= stopAt) return;
    const step = Math.min(d - stopAt, speed * dt);
    this.position.x += (dx / d) * step;
    this.position.z += (dz / d) * step;
  }

  _idleShuffle(dt) {
    // stay near the post, shuffling now and then
    const w = this.wander;
    w.t -= dt;
    if (w.t <= 0) {
      w.t = 3 + Math.random() * 4;
      const a = Math.random() * Math.PI * 2;
      // `roam` (metres): wanders that far from its post instead of shuffling
      const r = Math.random() * (this.cfg.roam || 2);
      w.target.set(this.home.x + Math.cos(a) * r, 0, this.home.z + Math.sin(a) * r);
    }
    const d = Math.hypot(w.target.x - this.position.x, w.target.z - this.position.z);
    if (d > 0.2) {
      const pace = this.cfg.roam ? 0.45 : 0.25;
      this._moveTowards(w.target.x, w.target.z, this.cfg.speed * pace, dt, 0.1);
      return pace + 0.1;
    }
    return 0;
  }
}
