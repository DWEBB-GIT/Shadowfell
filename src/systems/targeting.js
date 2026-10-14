import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { heightAt } from '../world/terrain.js';

// Targeting: soft lock by default, with an optional hard lock.
//
// Soft lock: abilities go to the enemy nearest your aim (the cursor, or the
// direction of the stick) that is within that ability's range, so you never
// have to select anything. A faint ring shows who the next blow will go to.
//
// Hard lock: Tab or R3 locks onto one enemy and keeps the Warden facing it;
// everything then goes to that enemy. Pressing again releases it. A red ring
// marks it and the HUD shows its frame.
//
// Ranged and targeted spells use the same rule with their own range; ground
// spells use the raw aim point instead (see `aimFor`).

export class Targeting {
  constructor(game) {
    this.game = game;
    this.current = null; // the hard-locked enemy, or null
    this.soft = null; // the enemy the soft lock would pick right now
    this.marker = this._ring(0xff5a3a, 'TargetMarker');
    this.softMarker = this._ring(0xf0c070, 'SoftTargetMarker');
    this.softMarker.material.opacity = 0.45;
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

  select(enemy) {
    if (enemy === this.current) return enemy;
    this.current = enemy && enemy.alive ? enemy : null;
    this.game.events.emit('targetChanged', { target: this.current });
    return this.current;
  }

  clear() {
    return this.select(null);
  }

  // Tab / R3: lock onto the enemy you are aiming at (or the nearest one in
  // range); pressing again releases the lock.
  toggleLock(aim) {
    if (this.current) return this.clear();
    const pick = this.softTarget(aim, CONFIG.targeting.range) || this._nearest();
    return this.select(pick);
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
    if (t && (!t.alive || this._dist(t) > CONFIG.targeting.dropRange || this.game.player.dead)) this.clear();
    this.soft = !this.current && softRange > 0 ? this.softTarget(rawAim, softRange) : null;
    this._place(this.marker, this.current, dt);
    this._place(this.softMarker, this.soft, dt);
  }

  _place(m, e, dt) {
    m.visible = !!e;
    if (!e) return;
    const s = e.radius * 2.6;
    m.scale.set(s, s, s);
    m.position.set(e.position.x, heightAt(e.position.x, e.position.z) + 0.08, e.position.z);
    m.rotation.z += dt * 0.8;
  }
}
