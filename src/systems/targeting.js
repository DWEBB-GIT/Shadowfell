import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { heightAt } from '../world/terrain.js';

// Targeting, WoW style.
//
// Selecting: left-click an enemy (or Tab / R3 to cycle through those near
// you) to make it your target. A red ring marks it and the HUD shows its
// frame. Left-clicking a townsperson selects them as a friendly target.
// Escape clears the target.
//
// Auto attack: right-click an enemy (RT on a pad), or use any ability on it,
// to engage it. The Warden swings at it each time his weapon is ready (its
// speed, less haste) while it is in reach and in front of him, until it
// falls, you pick another target, or you clear it (Escape). Right-clicking
// selects without turning him: standing still he turns to it at a walk's
// pace; moving, he faces where he goes.
//
// Abilities go to the selected enemy; with nothing selected they go to the
// enemy nearest your aim (the cursor, or ahead of you on a pad), which a faint
// ring shows. Ground spells use the raw aim point (see `aimFor`).

export class Targeting {
  constructor(game) {
    this.game = game;
    this.current = null; // the selected enemy, or null
    this.friendly = null; // a selected townsperson (Npc), or null
    this.attacking = false; // auto attack on the selected enemy
    this.soft = null; // who an ability would go to with nothing selected
    // the selection ring: yellow for anyone selected (left click), red once
    // you are fighting it (right click, or an ability on it)
    this.marker = this._ring(0xffd040, 'TargetMarker');
    this.softMarker = this._ring(0xd8d0c0, 'SoftTargetMarker');
    this.softMarker.material.opacity = 0.3;
  }

  _ring(color, name) {
    const mat = new THREE.MeshBasicMaterial({
      map: this.game.textures.ring,
      color,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), mat);
    m.rotation.x = -Math.PI / 2;
    m.renderOrder = 3;
    m.visible = false;
    m.name = name;
    this.game.scene.add(m);
    return m;
  }

  _dist(e) {
    const p = this.game.player.position;
    return Math.hypot(e.position.x - p.x, e.position.z - p.z);
  }

  // The enemy a soft lock picks for an ability with reach `range`, given an
  // aim point: inside the arc around the aim direction (or right under the
  // cursor), favouring the smallest angle and then the nearest.
  softTarget(aim, range) {
    const { player, enemies } = this.game;
    const p = player.position;
    let ax = aim ? aim.x - p.x : Math.sin(player.facing);
    let az = aim ? aim.z - p.z : Math.cos(player.facing);
    const al = Math.hypot(ax, az);
    if (al < 0.6) {
      ax = Math.sin(player.facing); // cursor on the Warden: use facing
      az = Math.cos(player.facing);
    } else {
      ax /= al;
      az /= al;
    }
    const arc = (CONFIG.targeting.softArc * Math.PI) / 180;
    let best = null;
    let bestScore = Infinity;
    for (const e of enemies.list) {
      if (!e.alive) continue;
      const dx = e.position.x - p.x;
      const dz = e.position.z - p.z;
      const d = Math.hypot(dx, dz);
      if (d > range + e.radius) continue;
      const nearCursor = aim && Math.hypot(e.position.x - aim.x, e.position.z - aim.z) <= CONFIG.targeting.softAimRadius;
      const angle = d > 0.01 ? Math.acos(Math.max(-1, Math.min(1, (dx * ax + dz * az) / d))) : 0;
      if (angle > arc && !nearCursor) continue;
      const score = (nearCursor ? 0 : angle) + d * 0.04;
      if (score < bestScore) {
        bestScore = score;
        best = e;
      }
    }
    return best;
  }

  // Where an ability should go. `kind`: 'enemy' (melee or ranged at a
  // target), 'ground' (lands at the aim point) or 'self'.
  aimFor(rawAim, range, kind = 'enemy') {
    if (kind === 'ground' || kind === 'self') return rawAim;
    const t = this.current && this._dist(this.current) <= CONFIG.targeting.dropRange ? this.current : this.softTarget(rawAim, range);
    return t ? t.position.clone() : rawAim;
  }

  // Make an enemy the target. Picking a different one stops auto attack.
  select(enemy) {
    const next = enemy && enemy.alive ? enemy : null;
    if (next) this.friendly = null;
    if (next === this.current) return next;
    this.current = next;
    this.attacking = false;
    this.game.events.emit('targetChanged', { target: this.current });
    return this.current;
  }

  selectFriendly(npc) {
    this.select(null);
    this.friendly = npc;
    this.game.events.emit('targetChanged', { target: null, friendly: npc });
  }

  clear() {
    this.friendly = null;
    return this.select(null);
  }

  // Select an enemy and start swinging at it.
  engage(enemy) {
    if (!this.select(enemy)) return false;
    if (!this.attacking) {
      this.attacking = true;
      // the first swing of a fight waits a full swing time, as Dan asked: no
      // instant opener. Switching targets mid-fight keeps the running clock.
      const p = this.game.player;
      const T = this.game.stats.attackCooldown;
      const midFight = p.lastSwingAt !== undefined && this.game.time - p.lastSwingAt < T;
      if (!midFight) {
        p.cooldowns.attack = Math.max(p.cooldowns.attack, T);
        // dual wielding, the off hand opens half a main-hand swing later, so
        // the two blades alternate from the start
        p.cooldowns.attackOff = Math.max(p.cooldowns.attackOff, this.game.stats.attackCooldownFor('off') + T / 2);
      }
      this.game.events.emit('autoAttack', { on: true, target: enemy });
    }
    return true;
  }

  stopAttack() {
    if (!this.attacking) return;
    this.attacking = false;
    this.game.events.emit('autoAttack', { on: false });
  }

  // Is the target close enough to hit with a swing?
  get targetInReach() {
    const t = this.current;
    return !!t && t.alive && this._dist(t) <= CONFIG.attack.range + t.radius * 0.6;
  }

  // Tab / R3: the enemy you are aiming at first, then the next nearest each
  // press, round all those in range.
  cycle(aim) {
    const near = this.game.enemies.list.filter((e) => e.alive && this._dist(e) <= CONFIG.targeting.range).sort((a, b) => this._dist(a) - this._dist(b));
    if (!near.length) return this.select(null);
    if (!this.current || !near.includes(this.current)) return this.select(this.softTarget(aim, CONFIG.targeting.range) || near[0]);
    return this.select(near[(near.indexOf(this.current) + 1) % near.length]);
  }

  _nearest() {
    let best = null;
    for (const e of this.game.enemies.list) {
      if (e.alive && this._dist(e) <= CONFIG.targeting.range && (!best || this._dist(e) < this._dist(best))) best = e;
    }
    return best;
  }

  // Called each frame with the raw aim, to show the soft-lock ring.
  update(dt, rawAim = null, softRange = 0) {
    const t = this.current;
    if (t && (!t.alive || this._dist(t) > CONFIG.targeting.dropRange || this.game.player.dead)) this.select(null);
    const f = this.friendly;
    if (f && Math.hypot(f.position.x - this.game.player.position.x, f.position.z - this.game.player.position.z) > CONFIG.targeting.dropRange) this.friendly = null;
    this.soft = !this.current && softRange > 0 ? this.softTarget(rawAim, softRange) : null;
    this.marker.material.color.setHex(this.current && this.attacking ? 0xff4a30 : 0xffd040);
    this._place(this.marker, this.current || this.friendly, dt);
    this._place(this.softMarker, this.soft, dt);
  }

  _place(m, e, dt) {
    m.visible = !!e;
    if (!e) return;
    const s = (e.radius || 0.45) * 2.6;
    m.scale.set(s, s, s);
    m.position.set(e.position.x, heightAt(e.position.x, e.position.z) + 0.08, e.position.z);
    m.rotation.z += dt * 0.8;
  }
}
