import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { ITEMS } from '../data/items.js';
import { Rig, setEmissive } from './rig.js';
import { heightAt } from '../world/terrain.js';
import { PLAYER_START } from '../world/layout.js';
import { SPELLS } from '../systems/spells.js';

// Player controller: movement, facing, Brace and the timing of abilities.
// Whether an attack hits is decided by the combat system, not here.
//
// Ability timing follows classic WoW: every spell (Shield Break, Lunge and
// the rest, run by the spell engine) shares a global cooldown (GCD) on top
// of its own cooldown. Auto attack, Brace and draughts are off the GCD.
//
// There is one defensive button (Space), filled by the archetype: the
// Warden's Brace raises the shield and turns aside the next blow. There is
// no dodge roll or sprint.
//
// Spells (abilities with a `kind` in data/abilities.json) are run by the
// spell engine (src/systems/spells.js); the player only holds the cast in
// progress, so nothing else can start while it fills.

export class Player {
  constructor(game) {
    this.game = game;
    this.group = new THREE.Group();
    this.group.name = 'Player';
    this.model = game.assets.instance('warden');
    this.group.add(this.model);
    this.rig = new Rig(this.model, 'warden');
    this.materials = Rig.isolateMaterials(this.model); // so the ghost can fade without touching other models
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
    this.ghost = false; // dead, walking as a spirit (see systems/afterlife.js)
    this.deadTime = 0;
    this.cooldowns = freshCooldowns();
    this.braced = 0; // seconds left with the shield raised
    this.lunge = null; // { t, dir }
    this.pending = null; // queued attack waiting for its impact frame
    this.casting = null; // a spell being cast: { id, t, total, target }
    this.moving = false;
    this.lightRadius = 0; // a torch in the off hand lights the dark (systems: world/waterAndDark.js)
    this.torchLight = new THREE.PointLight(0xffa860, 0, 9, 1.4);
    this.torchLight.position.set(0.3, 1.8, 0.2);
    this.group.add(this.torchLight);

    this.placeAt(PLAYER_START.position[0], PLAYER_START.position[1], PLAYER_START.facing * (Math.PI / 180));
  }

  placeAt(x, z, facing = this.facing) {
    this.position.set(x, heightAt(x, z), z);
    this.facing = facing;
    this.lunge = null;
    this.braced = 0;
    this.pending = null;
    this.casting = null;
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
      this.lightRadius = off && off.kind === 'torch' ? off.light || 8 : 0;
      this.torchLight.distance = this.lightRadius;
      this.torchLight.intensity = this.lightRadius ? 3 : 0;
      if (off && off.kind === 'torch') {
        // held up in the left hand, flame forward
        this.shield = this.game.assets.instance(off.model);
        this.shieldId = equipment.offHand.id;
        this.shield.position.set(0, -0.62, 0.02);
        this.shield.rotation.set(-0.5, 0, 0);
        larm.add(this.shield);
      } else if (off && off.kind === 'shield') {
        this.shield = this.game.assets.instance(off.model);
        this.shieldId = equipment.offHand.id;
        this.shield.position.set(0.11, -0.42, 0.04);
        this.shield.rotation.set(0, 1.25, 0);
        this.shield.scale.setScalar(0.95);
        larm.add(this.shield);
      }
    }
  }

  // Fishing: the rod in the right hand (the weapon put away) and the
  // fishing pose; off again puts the weapon back.
  holdRod(on) {
    const arm = this.model.getObjectByName('Arm_R');
    if (!arm) return;
    if (on && !this.rod) {
      this.rod = this.game.assets.instance('fishing_rod');
      this.rod.name = 'HeldRod';
      this.rod.position.set(0, -0.62, 0.04);
      this.rod.rotation.set(1.875, 0, 0); // out and up over the water once the arm is raised
      this.rodTip = new THREE.Object3D();
      this.rodTip.position.set(0, 1.42, 0);
      this.rod.add(this.rodTip);
      arm.add(this.rod);
    } else if (!on && this.rod) {
      arm.remove(this.rod);
      this.rod = null;
      this.rodTip = null;
    }
    this.rig.pose = on ? 'fish' : null;
    if (on && this.weaponPart) this.weaponPart.visible = false; // the sword is put away
    else if (!on) this.showEquipment(this.game.inventory.equipment);
  }

  // where the line leaves the rod, in world space
  rodTipPosition(out = new THREE.Vector3()) {
    if (!this.rodTip) return out.copy(this.position).setY(this.position.y + 1.8);
    this.group.updateMatrixWorld(true);
    return this.rodTip.getWorldPosition(out);
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

    if (this.ghost) {
      // a spirit walks fast, fights nothing and passes unseen
      const move = controls ? controls.move : { x: 0, z: 0 };
      const mag = Math.min(1, Math.hypot(move.x, move.z));
      if (mag > 0) {
        const sp = CONFIG.player.speed * CONFIG.death.ghostSpeed;
        this.position.x += move.x * sp * dt;
        this.position.z += move.z * sp * dt;
        this.facing = turnTowards(this.facing, Math.atan2(move.x, move.z), dt * 14);
      }
      collision.resolve(this.position, this.radius);
      this.position.y = heightAt(this.position.x, this.position.z) + 0.15 + Math.sin(this.game.time * 2) * 0.06;
      this.moving = mag > 0;
      this.rig.update(dt, mag);
      this._sync();
      return;
    }
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
        else if (p.type === 'spell') this.game.spells.resolve(p.id);
      }
    }

    let speed01 = 0;
    if (this.lunge) {
      // a charge spell (Lunge) carries the Warden, then strikes on arrival
      const d = this.lunge;
      d.t += dt;
      this.position.x += d.dir.x * d.speed * dt;
      this.position.z += d.dir.z * d.speed * dt;
      if (d.t >= d.duration) {
        this.pending = { type: 'spell', id: d.id, t: 0 };
        this.lunge = null;
      }
      speed01 = 1;
    } else if (controls) {
      const move = controls.move;
      // abilities slow the Warden while they play out; auto attack swings
      // do not (as in WoW, you can swing on the move)
      const swinging = this.pending ? this.pending.type === 'strike' : this.rig.action && this.rig.action.type === 'strike' && this.rig.action.auto;
      const attacking = !swinging && (this.pending || (this.rig.action && this.rig.action.type !== 'drink'));
      const slow = attacking ? 0.35 : 1;
      const mag = Math.min(1, Math.hypot(move.x, move.z)); // analogue sticks can walk slowly
      if (mag > 0) {
        this.position.x += move.x * CONFIG.player.speed * slow * dt;
        this.position.z += move.z * CONFIG.player.speed * slow * dt;
        if (!attacking) this.facing = turnTowards(this.facing, Math.atan2(move.x, move.z), dt * 14);
        speed01 = slow * mag;
      } else if (controls.actions && controls.actions.strike && controls.aim && !this.pending) {
        // standing still in a fight, the Warden turns (not snaps) to his target
        this.facing = turnTowards(this.facing, Math.atan2(controls.aim.x - this.position.x, controls.aim.z - this.position.z), dt * CONFIG.attack.turnRate);
      }

      const a = controls.actions || {};
      // spells first, so a swing coming due never swallows a key press
      for (const id in a) if (a[id] && SPELLS[id]) this.game.spells.tryCast(id);
      if (a.strike) this.tryStrike(controls.aim);
      if (a.draught) this.game.inventory.useDraught();
      if (a.fish) this.game.fishing.cast(controls.rawAim);
    }

    collision.resolve(this.position, this.radius);
    this.position.y = heightAt(this.position.x, this.position.z);
    this.moving = speed01 > 0;
    this.rig.update(dt, speed01 * CONFIG.player.runGait);
    this._sync();
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

  // An auto attack swing, when the weapon is ready and the target is in
  // front of the Warden (he does not snap round to it).
  tryStrike(aim) {
    if (this.cooldowns.attack > 0 || this.pending || this.casting) return false;
    if (aim && !this.facingPoint(aim.x, aim.z, CONFIG.attack.coneDegrees / 2)) return false;
    // haste shortens the swing timer, the windup and the swing itself
    const stats = this.game.stats;
    const windup = stats.hasted(CONFIG.attack.windup);
    const anim = Math.max(windup + 0.2, stats.hasted(CONFIG.attack.swingAnimation));
    this.cooldowns.attack = stats.attackCooldown;
    this.pending = { type: 'strike', t: windup, aim: aim ? { x: aim.x, z: aim.z } : null };
    this.rig.play('strike', anim, windup / anim);
    this.rig.action.auto = true;
    this.game.events.emit('playerSwing', {});
    return true;
  }

  // is (x, z) within `halfDegrees` of where the Warden faces? (very close counts)
  facingPoint(x, z, halfDegrees) {
    const dx = x - this.position.x;
    const dz = z - this.position.z;
    const d = Math.hypot(dx, dz);
    if (d < 0.8) return true;
    return (dx * Math.sin(this.facing) + dz * Math.cos(this.facing)) / d >= Math.cos((halfDegrees * Math.PI) / 180);
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
      this.casting = null;
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

  // Rise as a spirit at (x, z): see systems/afterlife.js.
  becomeGhost(x, z) {
    this.ghost = true;
    this.rig.revive();
    this.placeAt(x, z, Math.PI);
    for (const m of this.materials) {
      m.transparent = true;
      m.opacity = 0.45;
      m.depthWrite = false;
    }
    setEmissive(this.materials, { r: 0.35, g: 0.55, b: 0.8 }, 1);
  }

  revive(x, z, healthFraction = 1) {
    this.dead = false;
    if (this.ghost) {
      this.ghost = false;
      for (const m of this.materials) {
        m.transparent = false;
        m.opacity = 1;
        m.depthWrite = true;
      }
      setEmissive(this.materials, { r: 0, g: 0, b: 0 }, 0);
    }
    this.health = Math.max(1, Math.round(this.maxHealth * healthFraction));
    this.rig.revive();
    this.cooldowns = freshCooldowns();
    this.game.spells?.reset();
    this.game.resources?.reset();
    this.placeAt(x, z, Math.PI);
  }
}

function freshCooldowns() {
  const spells = Object.fromEntries(Object.keys(SPELLS).map((id) => [id, 0]));
  return { attack: 0, shieldBreak: 0, lunge: 0, brace: 0, draught: 0, gcd: 0, ...spells };
}

function turnTowards(current, target, maxStep) {
  let diff = target - current;
  while (diff > Math.PI) diff -= Math.PI * 2;
  while (diff < -Math.PI) diff += Math.PI * 2;
  if (Math.abs(diff) <= maxStep) return target;
  return current + Math.sign(diff) * maxStep;
}
