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
    this.pendingShot = null;
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
      } else if (off && off.kind === 'weapon' && this.defaultWeaponMesh) {
        // a second blade, mirrored into the left hand
        this.shield = this.game.assets.instance(off.model);
        this.shieldId = equipment.offHand.id;
        this.shield.position.copy(this.defaultWeaponMesh.position);
        this.shield.position.x *= -1;
        this.shield.quaternion.copy(this.defaultWeaponMesh.quaternion);
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
    this.holdBow(false);
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
    // the swing clocks run on delta time (see tryStrike)
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
      if (this.pending.t <= 1e-6) {
        const p = this.pending;
        this.pending = null;
        if (p.type === 'strike') this._impact('main', p, dt);
        else if (p.type === 'spell') this.game.spells.resolve(p.id);
      }
    }
    // an opener's hit, shown on the windup's impact frame
    if (this.game.combat.shownLater.length) this.game.combat.updateShown(dt);
    // the off hand's blow has its own impact frame
    if (this.pendingOff && (this.pendingOff.t -= dt) <= 1e-6) {
      const p = this.pendingOff;
      this.pendingOff = null;
      this._impact('off', p, dt);
    }
    // and Auto Shot its moment of release
    if (this.pendingShot && (this.pendingShot.t -= dt) <= 1e-6) {
      const p = this.pendingShot;
      this.pendingShot = null;
      this._release(p, dt);
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
      // No animation lock (WoW): swings, shots and abilities play on the
      // upper body while the legs keep going, at full speed. Only a charge
      // carries you, and a cast is broken by moving.
      const mag = Math.min(1, Math.hypot(move.x, move.z)); // analogue sticks can walk slowly
      if (mag > 0) {
        this.position.x += move.x * CONFIG.player.speed * dt;
        this.position.z += move.z * CONFIG.player.speed * dt;
        // fighting, you keep your target in front of you as you move (strafe),
        // so swings and shots carry on; otherwise you face where you go
        const acts = controls.actions || {};
        const look = (acts.strike || acts.shoot) && controls.aim ? Math.atan2(controls.aim.x - this.position.x, controls.aim.z - this.position.z) : Math.atan2(move.x, move.z);
        this.facing = turnTowards(this.facing, look, dt * 14);
        speed01 = mag;
      } else if (controls.actions && (controls.actions.strike || controls.actions.shoot) && controls.aim) {
        // standing still in a fight, the Warden turns (not snaps) to his target
        this.facing = turnTowards(this.facing, Math.atan2(controls.aim.x - this.position.x, controls.aim.z - this.position.z), dt * CONFIG.attack.turnRate);
      }

      const a = controls.actions || {};
      // spells first, so a swing coming due never swallows a key press
      for (const id in a) if (a[id] && SPELLS[id]) this.game.spells.tryCast(id);
      if (a.strike) {
        this.tryStrike(controls.aim);
        this.tryStrikeOff(controls.aim);
      }
      // Auto Shot needs you to stand still (WoW Classic): moving calls off a
      // draw, and the next one starts once you stop
      if (speed01 > 0 && this.pendingShot) this._cancelShot();
      if (a.shoot && speed01 === 0) this.tryShoot(controls.aim);
      if (a.fish) this.game.fishing.cast(controls.rawAim);
      if (a.cook) this.game.hud.items.toggle('cooking');
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

  // Auto attack, as WoW does it. Each hand has a swing clock
  // (cooldowns.attack / attackOff, T = W / (1 + H)) that counts down to the
  // moment the blow lands, so the swing timer bar fills exactly on the hit.
  // The animation starts its windup early, so its impact frame is that same
  // moment; it only starts if the target is in reach and in front of you.
  // A fresh fight's clocks start ready: the first blow lands soon after you
  // reach the target, after a weighty opening windup (`openerWindup`, a
  // fraction of T, not the full timer), then every T. If the
  // target is out of reach when the clock runs out there is no swing: the
  // clock waits, full, and you swing the moment you are back in reach. It
  // restarts from the blow, keeping any overshoot (capped by `catchUp`) so
  // the rhythm holds at low frame rates. Swinging never blocks movement or
  // abilities.
  tryStrike(aim) {
    if (this.pending || this.casting) return false;
    const stats = this.game.stats;
    const windup = stats.swingWindup;
    if (this.cooldowns.attack > windup) return false;
    if (aim && !this.facingPoint(aim.x, aim.z, CONFIG.attack.coneDegrees / 2)) return false;
    const anim = stats.swingAnimation;
    if (this.bowInHand) this.holdBow(false);
    if (this.opener) {
      // a fresh fight's first blow registers the moment you engage in reach
      // (damage, swing clock), as the server does in WoW; what you see is a
      // weighty windup, with the hit shown on its impact frame
      this.opener = false;
      const show = Math.min(CONFIG.attack.openerWindup, anim * 0.7);
      this.rig.play('strike', anim, show / anim);
      this.rig.action.auto = true;
      this.game.events.emit('playerSwing', {});
      this._impact('main', { t: 0, aim: aim ? { x: aim.x, z: aim.z } : null }, 0, show);
      return true;
    }
    const t = Math.max(this.cooldowns.attack, Math.min(windup, CONFIG.attack.readyWindup));
    this.pending = { type: 'strike', t, aim: aim ? { x: aim.x, z: aim.z } : null };
    this.rig.play('strike', anim, t / anim);
    this.rig.action.auto = true;
    this.game.events.emit('playerSwing', {});
    return true;
  }

  // The off hand, when dual wielding: its own clock, its own animation on
  // the left arm, its own impact. The hands stagger: the off hand never lands
  // within `staggerGap` of a main-hand blow; if it would, its clock is pushed
  // back until just after that blow.
  tryStrikeOff(aim) {
    const stats = this.game.stats;
    if (!stats.dualWielding || this.pendingOff || this.casting || this.lunge) return false;
    if (this.pending && this.pending.type === 'spell') return false;
    const windup = stats.swingWindupFor('off');
    if (this.cooldowns.attackOff > windup) return false;
    if (aim && !this.facingPoint(aim.x, aim.z, CONFIG.attack.coneDegrees / 2)) return false;
    const gap = CONFIG.attack.staggerGap;
    const anim = stats.swingAnimationFor('off');
    // the opener's off hand follows the main hand's shown blow
    const ready = this.openerOff ? Math.min(CONFIG.attack.openerWindup, anim * 0.7) + gap : Math.min(windup, CONFIG.attack.readyWindup);
    const t = Math.max(this.cooldowns.attackOff, ready);
    const main = this.pending && this.pending.type === 'strike' ? this.pending.t : this.cooldowns.attack;
    const since = this.game.time - (this.lastMainImpactAt ?? -Infinity);
    if (Math.abs(main - t) < gap) {
      this.cooldowns.attackOff = main + gap;
      return false;
    }
    if (since + t < gap) {
      this.cooldowns.attackOff = gap - since;
      return false;
    }
    this.openerOff = false;
    this.pendingOff = { t, aim: aim ? { x: aim.x, z: aim.z } : null };
    this.rig.playOff(anim, t / anim);
    this.game.events.emit('playerSwing', { hand: 'off' });
    return true;
  }

  // A blow's impact frame: it lands only if the target is still in reach,
  // and the hand's clock starts again from here. Out of reach, the swing is
  // called off and the clock waits at zero.
  // `show`: seconds until the blow is shown (the opener's windup); the
  // damage and the clock still resolve now.
  _impact(hand, p, dt, show = 0) {
    const off = hand === 'off';
    const tg = this.game.targeting;
    if (!tg.attacking || !tg.targetInReach) {
      if (off) this.rig.offAction = null;
      else if (this.rig.action?.type === 'strike') this.rig.action = null;
      return;
    }
    const late = Math.min(-p.t, dt, CONFIG.attack.catchUp);
    this.cooldowns[off ? 'attackOff' : 'attack'] = Math.max(0, this.game.stats.attackCooldownFor(hand) - late);
    this.lastSwingAt = this.game.time;
    if (!off) this.lastMainImpactAt = this.game.time;
    this.game.combat.resolvePlayerStrike(p.aim, hand, show);
  }

  // Auto Shot (WoW): with a bow in the ranged slot, while the target is
  // beyond melee reach and within the bow's range, an arrow is loosed each
  // time the ranged clock (cooldowns.ranged, T = bow speed / (1 + haste))
  // runs out. The draw starts early so the arrow leaves the string as the
  // clock runs out; it flies to the target and does its damage on arrival.
  // You must stand still to shoot (WoW Classic; Dan, 2026-10-16), but
  // nothing locks you in place: moving just calls the draw off.
  tryShoot(aim) {
    if (this.pendingShot || this.casting || this.lunge) return false;
    const stats = this.game.stats;
    // each shot uses an arrow; with none, Auto Shot does nothing
    if (!this.game.inventory.ammo) {
      this.game.events.emit('log', { text: 'You have no arrows. Buy them from Mara or Tam.', kind: 'muted', throttle: 'no-ammo' });
      return false;
    }
    const draw = Math.min(CONFIG.autoShot.draw, stats.attackCooldownFor('ranged') * 0.4);
    if (this.cooldowns.ranged > draw) return false;
    if (aim && !this.facingPoint(aim.x, aim.z, CONFIG.attack.coneDegrees / 2)) return false;
    const t = Math.max(this.cooldowns.ranged, Math.min(draw, CONFIG.attack.readyWindup * 2));
    this.pendingShot = { t };
    this.holdBow(true);
    this.rig.play('shoot', t + 0.35, t / (t + 0.35));
    this.rig.action.auto = true;
    return true;
  }

  _cancelShot() {
    this.pendingShot = null;
    if (this.rig.action?.type === 'shoot') this.rig.action = null;
  }

  // The arrow leaves the string, if the target is still beyond melee reach
  // and within the bow's (else the shot is called off and the clock waits).
  _release(p, dt) {
    const tg = this.game.targeting;
    if (!tg.attacking || !tg.targetInShot) {
      if (this.rig.action?.type === 'shoot') this.rig.action = null;
      this.holdBow(false);
      return;
    }
    const inv = this.game.inventory;
    const ammo = inv.ammo;
    if (!ammo) {
      if (this.rig.action?.type === 'shoot') this.rig.action = null;
      this.holdBow(false);
      return;
    }
    inv.removeCount(ammo, 1);
    const late = Math.min(-p.t, dt, CONFIG.attack.catchUp);
    this.cooldowns.ranged = Math.max(0, this.game.stats.attackCooldownFor('ranged') - late);
    this.lastSwingAt = this.game.time;
    this.game.combat.loosePlayerArrow(tg.current, ammo);
  }

  // The bow rides on the back, and comes to the left hand to shoot (the
  // blade and shield are put away until the next swing).
  holdBow(inHand) {
    const torso = this.model.getObjectByName('Torso');
    const larm = this.model.getObjectByName('Arm_L');
    const id = this.game.inventory.equipment.ranged?.id;
    const want = id && ITEMS[id].kind === 'weapon' ? id : null;
    if (this.bow && (this.bowId !== want || this.bowInHand !== !!inHand)) {
      this.bow.parent?.remove(this.bow);
      this.bow = null;
    }
    if (want && !this.bow) {
      this.bow = this.game.assets.instance(ITEMS[want].model);
      this.bowId = want;
      this.bowInHand = !!inHand;
      if (inHand && larm) {
        this.bow.position.set(0, -0.62, 0.02);
        this.bow.rotation.set(-Math.PI / 2, 0, 0);
        larm.add(this.bow);
      } else if (torso) {
        this.bow.position.set(0, 0.25, -0.2);
        this.bow.rotation.set(0, 0, 0.7);
        torso.add(this.bow);
      }
    }
    if (this.weaponPart) this.weaponPart.visible = !inHand && (this.weaponPart !== this.defaultWeaponMesh || this.game.inventory.equipment.mainHand?.id === 'worn_longsword');
    if (this.shield) this.shield.visible = !inHand;
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
      this.pendingOff = null;
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
  return { attack: 0, attackOff: 0, ranged: 0, shieldBreak: 0, lunge: 0, brace: 0, draught: 0, gcd: 0, ...spells };
}

function turnTowards(current, target, maxStep) {
  let diff = target - current;
  while (diff > Math.PI) diff -= Math.PI * 2;
  while (diff < -Math.PI) diff += Math.PI * 2;
  if (Math.abs(diff) <= maxStep) return target;
  return current + Math.sign(diff) * maxStep;
}
