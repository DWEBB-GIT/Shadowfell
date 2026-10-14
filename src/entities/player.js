import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { ITEMS } from '../data/items.js';
import { Rig } from './rig.js';
import { heightAt } from '../world/terrain.js';
import { PLAYER_START } from '../world/layout.js';

// Player controller: movement, facing, Brace and the timing of abilities.
// Whether an attack hits is decided by the combat system, not here.
//
// Ability timing follows classic WoW: Shield Break and Lunge share a global
// cooldown (GCD) on top of their own cooldowns. The basic Strike, Brace and
// draughts are off the GCD, like Diablo's primary skill and WoW potions.
//
// There is one defensive button (Space), filled by the archetype: the
// Warden's Brace raises the shield and turns aside the next blow. There is
// no dodge roll or sprint.

export class Player {
  constructor(game) {
    this.game = game;
    this.group = new THREE.Group();
    this.group.name = 'Player';
    this.model = game.assets.instance('warden');
    this.group.add(this.model);
    this.rig = new Rig(this.model, 'warden');
    this.weaponPart = this.model.getObjectByName('Weapon');
    this.defaultWeaponMesh = this.weaponPart;

    const blob = new THREE.Mesh(
      new THREE.PlaneGeometry(1.3, 1.3),
      new THREE.MeshBasicMaterial({ map: game.textures.blob, transparent: true, depthWrite: false }),
    );
    blob.rotation.x = -Math.PI / 2;
    blob.position.y = 0.03;
    this.group.add(blob);

    this.position = new THREE.Vector3();
    this.facing = 0; // radians; 0 faces +z (south)
    this.radius = CONFIG.player.radius;
    this.maxHealth = 100; // set from stats once the game is assembled
    this.health = this.maxHealth;
    this.dead = false;
    this.deadTime = 0;
    this.cooldowns = freshCooldowns();
    this.braced = 0; // seconds left with the shield raised
    this.lunge = null; // { t, dir }
    this.pending = null; // queued attack waiting for its impact frame
    this.moving = false;

    this.placeAt(PLAYER_START.position[0], PLAYER_START.position[1], PLAYER_START.facing * (Math.PI / 180));
  }

  placeAt(x, z, facing = this.facing) {
    this.position.set(x, heightAt(x, z), z);
    this.facing = facing;
    this.lunge = null;
    this.braced = 0;
    this.pending = null;
    this._sync();
  }

  _sync() {
    this.group.position.copy(this.position);
    this.group.rotation.y = this.facing;
  }

  // Show what is equipped: the blade in hand (or none) and a helm if worn.
  showEquipment(equipment) {
    const arm = this.model.getObjectByName('Arm_R');
    const head = this.model.getObjectByName('Head');
    if (arm && this.defaultWeaponMesh) {
      if (this.weaponPart && this.weaponPart !== this.defaultWeaponMesh) arm.remove(this.weaponPart);
      const id = equipment.mainHand ? equipment.mainHand.id : null;
      this.defaultWeaponMesh.visible = id === 'worn_longsword';
      this.weaponPart = this.defaultWeaponMesh;
      if (id && id !== 'worn_longsword') {
        const blade = this.game.assets.instance(ITEMS[id].model);
        blade.position.copy(this.defaultWeaponMesh.position);
        blade.quaternion.copy(this.defaultWeaponMesh.quaternion);
        arm.add(blade);
        this.weaponPart = blade;
      }
    }
    if (head) {
      if (this.helm) head.remove(this.helm);
      this.helm = null;
      if (equipment.head && equipment.head.id === 'watch_helm') {
        this.helm = this.game.assets.instance('watch_helm');
        this.helm.position.set(0, 0.2, 0.02);
        this.helm.scale.setScalar(1.15);
        head.add(this.helm);
      }
    }
    // a shield in the off hand rides on the left forearm, face outwards
    const larm = this.model.getObjectByName('Arm_L');
    if (larm) {
      if (this.shield) larm.remove(this.shield);
      this.shield = null;
      const off = equipment.offHand && ITEMS[equipment.offHand.id];
      if (off && off.kind === 'shield') {
        this.shield = this.game.assets.instance(off.model);
        this.shieldId = equipment.offHand.id;
        this.shield.position.set(0.11, -0.42, 0.04);
        this.shield.rotation.set(0, 1.25, 0);
        this.shield.scale.setScalar(0.95);
        larm.add(this.shield);
      }
    }
  }

  // kept for older callers
  showWeapon(id) {
    this.showEquipment({ mainHand: id ? { id, count: 1 } : null, head: this.helm ? { id: 'watch_helm' } : null, offHand: this.shield ? { id: this.shieldId } : null });
  }

  faceTowards(x, z) {
    const dx = x - this.position.x;
    const dz = z - this.position.z;
    if (dx * dx + dz * dz > 0.0001) this.facing = Math.atan2(dx, dz);
  }

  update(dt, controls) {
    const { combat, collision } = this.game;
    for (const k of Object.keys(this.cooldowns)) this.cooldowns[k] = Math.max(0, this.cooldowns[k] - dt);
    this.braced = Math.max(0, this.braced - dt);

    if (this.dead) {
      this.deadTime += dt;
      this.rig.update(dt, 0);
      this._sync();
      return;
    }

    // queued attacks land after a short windup, independent of frame rate
    if (this.pending) {
      this.pending.t -= dt;
      if (this.pending.t <= 0) {
        const p = this.pending;
        this.pending = null;
        if (p.type === 'strike') combat.resolvePlayerStrike(p.aim);
        else if (p.type === 'lunge') combat.resolveLunge();
        else combat.resolveShieldBreak();
      }
    }

    let speed01 = 0;
    if (this.lunge) {
      const d = this.lunge;
      const cfg = CONFIG.lunge;
      d.t += dt;
      const speed = cfg.distance / cfg.duration;
      this.position.x += d.dir.x * speed * dt;
      this.position.z += d.dir.z * speed * dt;
      if (d.t >= cfg.duration) {
        this.pending = { type: 'lunge', t: 0 };
        this.lunge = null;
      }
      speed01 = 1;
    } else if (controls) {
      const move = controls.move;
      const attacking = this.pending || (this.rig.action && this.rig.action.type !== 'drink');
      const slow = attacking ? 0.35 : 1;
      const mag = Math.min(1, Math.hypot(move.x, move.z)); // analogue sticks can walk slowly
      if (mag > 0) {
        this.position.x += move.x * CONFIG.player.speed * slow * dt;
        this.position.z += move.z * CONFIG.player.speed * slow * dt;
        if (!attacking && !controls.lockOn) this.facing = turnTowards(this.facing, Math.atan2(move.x, move.z), dt * 14);
        speed01 = slow * mag;
      }
      // a hard lock keeps the Warden facing the target, strafing as he moves
      if (controls.lockOn && !this.pending) {
        const l = controls.lockOn;
        this.facing = turnTowards(this.facing, Math.atan2(l.x - this.position.x, l.z - this.position.z), dt * 12);
      }

      const a = controls.actions || {};
      if (a.brace) this.tryBrace();
      if (a.shieldBreak) this.tryShieldBreak();
      else if (a.lunge) this.tryLunge(controls.lungeAim || controls.aim);
      else if (a.strike) this.tryStrike(controls.aim);
      if (a.draught) this.game.inventory.useDraught();
    }

    collision.resolve(this.position, this.radius);
    this.position.y = heightAt(this.position.x, this.position.z);
    this.moving = speed01 > 0;
    this.rig.update(dt, speed01);
    this._sync();
  }

  // Brace (the Warden's defensive button): the shield goes up and the next
  // blow, telegraphed or not, is turned aside. Off the GCD.
  tryBrace() {
    if (this.cooldowns.brace > 0) return false;
    this.cooldowns.brace = CONFIG.brace.cooldown;
    this.braced = CONFIG.brace.window;
    this.rig.play('brace', 0.5, 0.4);
    this.game.events.emit('playerBrace', {});
    return true;
  }

  get isBraced() {
    return this.braced > 0;
  }

  // Called by combat when a blow lands; true if the shield took it.
  consumeBrace() {
    if (this.braced <= 0) return false;
    this.braced = 0;
    this.rig.play('brace', 0.35, 0.2);
    return true;
  }

  tryStrike(aim) {
    if (this.cooldowns.attack > 0 || this.pending) return false;
    if (aim) this.faceTowards(aim.x, aim.z);
    // haste shortens the swing and its windup alike
    const stats = this.game.stats;
    const swing = stats.attackCooldown;
    const windup = stats.hasted(CONFIG.attack.windup);
    this.cooldowns.attack = swing;
    this.pending = { type: 'strike', t: windup, aim: aim ? { x: aim.x, z: aim.z } : null };
    this.rig.play('strike', swing * 0.85, windup / (swing * 0.85));
    this.game.events.emit('playerSwing', {});
    return true;
  }

  _gcdReady(name) {
    if (this.cooldowns.gcd > 0) return false; // silently queued out, as in WoW
    if (this.cooldowns[name] > 0) {
      const label = name === 'shieldBreak' ? 'Shield Break' : 'Lunge';
      this.game.events.emit('log', { text: `${label} is not ready.`, kind: 'muted', throttle: name + '-ready' });
      return false;
    }
    return true;
  }

  tryShieldBreak() {
    if (this.pending || this.lunge) return false;
    if (!this._gcdReady('shieldBreak')) return false;
    const windup = this.game.stats.hasted(CONFIG.shieldBreak.windup);
    this.cooldowns.shieldBreak = CONFIG.shieldBreak.cooldown;
    this.cooldowns.gcd = this.game.stats.globalCooldown;
    this.cooldowns.attack = Math.max(this.cooldowns.attack, windup + 0.2);
    this.pending = { type: 'shieldBreak', t: windup };
    this.rig.play('slam', windup + 0.35, windup / (windup + 0.35));
    return true;
  }

  // Lunge: a short charge towards the aim point that strikes on arrival.
  tryLunge(aim) {
    if (this.pending || this.lunge) return false;
    if (!this._gcdReady('lunge')) return false;
    let dir = { x: Math.sin(this.facing), z: Math.cos(this.facing) };
    if (aim) {
      const dx = aim.x - this.position.x;
      const dz = aim.z - this.position.z;
      const len = Math.hypot(dx, dz);
      if (len > 0.3) dir = { x: dx / len, z: dz / len };
    }
    this.facing = Math.atan2(dir.x, dir.z);
    this.cooldowns.lunge = CONFIG.lunge.cooldown;
    this.cooldowns.gcd = this.game.stats.globalCooldown;
    this.cooldowns.attack = Math.max(this.cooldowns.attack, CONFIG.lunge.duration + 0.2);
    this.lunge = { t: 0, dir };
    this.rig.play('strike', CONFIG.lunge.duration + 0.25, 0.7);
    this.game.events.emit('playerLunge', {});
    return true;
  }

  takeDamage(amount) {
    if (this.dead) return false;
    this.health = Math.max(0, this.health - amount);
    this.rig.hit();
    if (this.health <= 0) {
      this.dead = true;
      this.deadTime = 0;
      this.pending = null;
      this.lunge = null;
      this.braced = 0;
      this.rig.die();
    }
    return true;
  }

  heal(amount) {
    const before = this.health;
    this.health = Math.min(this.maxHealth, this.health + amount);
    return this.health - before;
  }

  revive(x, z) {
    this.dead = false;
    this.health = this.maxHealth;
    this.rig.revive();
    this.cooldowns = freshCooldowns();
    this.placeAt(x, z, Math.PI);
  }
}

function freshCooldowns() {
  return { attack: 0, shieldBreak: 0, lunge: 0, brace: 0, draught: 0, gcd: 0 };
}

function turnTowards(current, target, maxStep) {
  let diff = target - current;
  while (diff > Math.PI) diff -= Math.PI * 2;
  while (diff < -Math.PI) diff += Math.PI * 2;
  if (Math.abs(diff) <= maxStep) return target;
  return current + Math.sign(diff) * maxStep;
}
