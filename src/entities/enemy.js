import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { Rig, setEmissive, FLASH_RED, FLASH_WHITE } from './rig.js';
import { heightAt } from '../world/terrain.js';

// One undead enemy. AI states: idle -> chase -> attack, return home when the
// player escapes, dead when health reaches zero. Deliberately simple.

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
    this.health = this.cfg.health;
    this.mana = this.cfg.mana || 0; // only enemies whose config gives them mana have any
    this.state = 'idle';
    this.attackTimer = 0.6;
    this.windup = 0; // > 0 while an attack is being telegraphed
    this.casting = null; // ground-telegraphed attack in progress: { kind, telegraph }
    this.specialTimer = 3; // first Grave Slam comes a few seconds into a fight
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
    this.health = this.cfg.health;
    this.mana = this.cfg.mana || 0;
    this.state = 'idle';
    this.windup = 0;
    this._cancelCast();
    this.specialTimer = 3;
    this.stagger = 0;
    this.engaged = 0;
    this.rig.action = null;
    this._sync();
  }

  hurt(amount, { stagger = 0.15, knockFrom = null, knockback = 0, heavy = false } = {}) {
    if (this.dead) return 0;
    const dealt = Math.min(this.health, amount);
    this.health -= dealt;
    this.flash = 1;
    this.flashColor = heavy ? FLASH_WHITE : FLASH_RED;
    this.engaged = 6;
    this.rig.hit();
    this.stagger = Math.max(this.stagger, stagger);
    if (heavy && !(this.casting && this.casting.kind === 'special')) {
      // a heavy blow interrupts an ordinary swing; the elite's slam cannot be stopped
      this.windup = 0;
      this.rig.action = null;
      this._cancelCast();
    }
    if (knockFrom && knockback > 0) {
      const dir = new THREE.Vector3(this.position.x - knockFrom.x, 0, this.position.z - knockFrom.z);
      if (dir.lengthSq() > 0.0001) this.knock.copy(dir.normalize().multiplyScalar(knockback * 6));
    }
    if (this.state === 'idle' || this.state === 'return') this.state = 'chase';
    if (this.health <= 0) {
      this.dead = true;
      this.state = 'dead';
      this.windup = 0;
      this._cancelCast();
      this.rig.die();
    }
    return dealt;
  }

  _cancelCast() {
    if (this.casting) this.game.telegraphs.cancel(this.casting.telegraph);
    this.casting = null;
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
    this.casting = { kind, telegraph, label: special ? sp.name : 'Cleave' };
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

    if (this.dead) {
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

    // knockback slides
    if (this.knock.lengthSq() > 0.001) {
      this.position.addScaledVector(this.knock, dt);
      this.knock.multiplyScalar(Math.max(0, 1 - dt * 9));
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
    if (player.dead && this.casting) this._cancelCast();

    if (this.casting) {
      // committed: hold position while the telegraph fills
      speed01 = 0;
    } else if (this.stagger <= 0 && !player.dead) {
      const sp = cfg.special;
      if (sp && this.specialTimer <= 0 && dist < sp.trigger && (this.state === 'chase' || this.state === 'attack')) {
        this._startCast('special', player);
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
          this.rig.play(this.type === 'brute' ? 'cleave' : 'claw', cfg.windup + 0.3, cfg.windup / (cfg.windup + 0.3));
          this.game.events.emit('enemyWindup', { enemy: this });
        }
      }
    }
    if (this.casting) {
      // nothing else moves while committed to a telegraphed attack
    } else if (this.state === 'return' && this.stagger <= 0) {
      this._moveTowards(this.home.x, this.home.z, cfg.speed * 0.8, dt, 0.3);
      speed01 = 0.8;
      this.health = Math.min(cfg.health, this.health + dt * 6);
    } else if (this.state === 'idle') {
      speed01 = this._idleShuffle(dt);
    }

    this.game.collision.resolve(this.position, this.radius);
    this.position.y = heightAt(this.position.x, this.position.z);
    this.rig.update(dt, speed01 * (this.type === 'brute' ? 0.8 : 0.7));
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
      const r = Math.random() * 2;
      w.target.set(this.home.x + Math.cos(a) * r, 0, this.home.z + Math.sin(a) * r);
    }
    const d = Math.hypot(w.target.x - this.position.x, w.target.z - this.position.z);
    if (d > 0.2) {
      this._moveTowards(w.target.x, w.target.z, this.cfg.speed * 0.25, dt, 0.1);
      return 0.35;
    }
    return 0;
  }
}
