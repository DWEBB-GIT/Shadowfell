import { CONFIG } from '../config.js';
import { heightAt } from '../world/terrain.js';
import * as THREE from 'three';

// Restrained visual feedback: a ground shockwave for Shield Break, small
// sparks on hits, dust, and a faint pillar on level-up. Effects are pooled
// per type and disposed when finished.

export class Effects {
  constructor(game) {
    this.game = game;
    this.items = [];
    this.ringGeo = new THREE.PlaneGeometry(1, 1);
    this.dustGeo = new THREE.BoxGeometry(0.12, 0.12, 0.12);
    this.dustMat = new THREE.MeshLambertMaterial({ color: 0x6a5c48 });

    const ev = game.events;
    ev.on('burst', ({ position, radius }) => this.shockwave(position, radius));
    ev.on('enemyHit', ({ enemy, kind, crit }) => this.sparks(enemy.position, crit ? 14 : kind === 'strike' ? 7 : 8));
    // the weight of a landed blow: the camera kicks (nothing ever pauses)
    ev.on('hitImpact', ({ crit, heavy }) => {
      if (heavy || crit) this.game.shakeCamera(crit ? CONFIG.impact.critShake : CONFIG.impact.shake);
    });
    ev.on('playerHurt', ({ heavy }) => this.game.shakeCamera(heavy ? CONFIG.impact.critShake : CONFIG.impact.shake * 0.6));
    ev.on('playerHurt', () => this.game.hud.flashDamage());
    ev.on('levelUp', () => this.pillar(this.game.player.position));
    ev.on('enemyDefeated', ({ enemy }) => this.dust(enemy.position, 10));
    // the Grave Slam lands where the telegraph was painted
    ev.on('graveSlam', ({ shape }) => {
      const a = shape.angle;
      const r = shape.range * 0.55;
      const pos = new THREE.Vector3(shape.x + Math.sin(a) * r, this.game.player.position.y, shape.z + Math.cos(a) * r);
      this.shockwave(pos, shape.range * 0.6);
    });
    ev.on('playerLunge', () => this.dust(this.game.player.position, 6, 0.3));
    ev.on('braceBlock', () => this.sparks(this.game.player.position, 10));
    ev.on('anvilStrike', ({ x, z }) => {
      const p = this.game.player.position;
      if (Math.hypot(p.x - x, p.z - z) < 25) this.sparks({ x, y: heightAt(x, z) - 0.3, z }, 5);
    });
    ev.on('playerBrace', () => this.braceGlow());
    ev.on('projectile', (p) => this.projectile(p));
    ev.on('darkCircle', ({ x, z, radius }) => {
      const pos = new THREE.Vector3(x, heightAt(x, z), z);
      this.shockwave(pos, radius, 0x9a7cff);
    });
    // spells (src/systems/spells.js)
    ev.on('spellFlash', ({ position }) => this.flash(position, 0xffe08a));
    ev.on('zone', ({ x, z, radius, duration }) => this.zone(x, z, radius, duration));
    ev.on('cleave', ({ position, facing, range }) => {
      const r = range * 0.5;
      this.shockwave(new THREE.Vector3(position.x + Math.sin(facing) * r, position.y, position.z + Math.cos(facing) * r), range * 0.7, 0xffc890);
    });
    ev.on('buff', () => this.pillar(this.game.player.position, 0xff9a5a));
    ev.on('splash', ({ x, y, z, small }) => this.splash(x, y, z, small));
    ev.on('campPitched', ({ x, z }) => this.dust({ x, y: heightAt(x, z), z }, 10, 0.6));
    ev.on('itemDropped', ({ item }) => this.dust({ x: item.x, y: this.game.player.position.y, z: item.z }, 4, 0.2));
  }

  _add(obj, life, update) {
    this.game.scene.add(obj);
    this.items.push({ obj, life, age: 0, update });
  }

  shockwave(pos, radius, color = 0xffd9a0) {
    const mat = new THREE.MeshBasicMaterial({
      map: this.game.textures.ring,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      color,
    });
    const ring = new THREE.Mesh(this.ringGeo, mat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(pos.x, pos.y + 0.12, pos.z);
    this._add(ring, 0.45, (o, k) => {
      const s = radius * 2 * (0.3 + k * 0.8);
      o.scale.set(s, s, s);
      o.material.opacity = 1 - k;
    });
    this.dust(pos, 14, radius * 0.7);
  }

  sparks(pos, n) {
    for (let i = 0; i < n; i++) {
      const mat = new THREE.SpriteMaterial({
        map: this.game.textures.glint,
        color: 0xffc890,
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
      });
      const s = new THREE.Sprite(mat);
      s.scale.setScalar(0.25);
      const v = new THREE.Vector3((Math.random() - 0.5) * 4, 1.5 + Math.random() * 2.5, (Math.random() - 0.5) * 4);
      s.position.set(pos.x, pos.y + 1.1, pos.z);
      this._add(s, 0.3 + Math.random() * 0.15, (o, k, dt) => {
        o.position.addScaledVector(v, dt);
        v.y -= 12 * dt;
        o.material.opacity = 1 - k;
      });
    }
  }

  dust(pos, n, spread = 0.6) {
    for (let i = 0; i < n; i++) {
      const m = new THREE.Mesh(this.dustGeo, this.dustMat);
      const a = Math.random() * Math.PI * 2;
      const v = new THREE.Vector3(Math.cos(a) * (1 + Math.random() * 2), 1 + Math.random() * 1.5, Math.sin(a) * (1 + Math.random() * 2));
      m.position.set(pos.x + Math.cos(a) * spread * Math.random(), pos.y + 0.1, pos.z + Math.sin(a) * spread * Math.random());
      this._add(m, 0.6, (o, k, dt) => {
        o.position.addScaledVector(v, dt);
        v.y -= 6 * dt;
        o.scale.setScalar(1 - k);
      });
    }
  }

  // An arrow (a thin shaft) or a bolt (a glowing mote) flying from -> to.
  // With `follow` (an enemy), it homes in on it as it moves, as WoW's
  // arrows and bolts do, and arrives after `life` seconds.
  projectile({ kind, from, to, speed, follow = null, life = null }) {
    const bolt = kind === 'bolt' || kind === 'holy';
    const model = !bolt && follow && this.game.assets.instance?.('arrow');
    const obj = bolt
      ? new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.textures.glint, color: kind === 'holy' ? 0xffd98a : 0x9a7cff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }))
      : model || new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, 0.7), new THREE.MeshBasicMaterial({ color: 0xd8c8a0 }));
    if (bolt) obj.scale.setScalar(0.6);
    const a = new THREE.Vector3(from.x, from.y, from.z);
    const b = new THREE.Vector3(to.x, heightAt(to.x, to.z) + 1.0, to.z);
    obj.position.copy(a);
    if (!bolt) obj.lookAt(b);
    const time = life ?? Math.max(0.08, a.distanceTo(b) / speed);
    this._add(obj, Math.max(0.05, time), (o, k) => {
      if (follow) b.set(follow.position.x, heightAt(follow.position.x, follow.position.z) + 1.0, follow.position.z);
      o.position.lerpVectors(a, b, k);
      // a slight arc for arrows
      if (!bolt) {
        o.position.y += Math.sin(k * Math.PI) * Math.min(1.2, a.distanceTo(b) * 0.04);
        o.lookAt(b);
      }
    });
  }

  // a pale shield of light in front of the Warden while Brace is up
  braceGlow() {
    const player = this.game.player;
    const mat = new THREE.SpriteMaterial({ map: this.game.textures.glint, color: 0x9cc4ff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 });
    const s = new THREE.Sprite(mat);
    s.scale.set(1.4, 1.8, 1);
    this._add(s, this.game.config.brace.window, (o) => {
      const f = player.facing;
      o.position.set(player.position.x + Math.sin(f) * 0.6, player.position.y + 1.1, player.position.z + Math.cos(f) * 0.6);
      o.material.opacity = player.isBraced ? 0.5 : 0;
    });
  }

  // rings on the water where the bob lands or a fish takes it
  splash(x, y, z, small) {
    for (let i = 0; i < (small ? 1 : 3); i++) {
      const mat = new THREE.MeshBasicMaterial({ map: this.game.textures.ring, color: 0xcfe6e0, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending });
      const ring = new THREE.Mesh(this.ringGeo, mat);
      ring.rotation.x = -Math.PI / 2;
      ring.position.set(x, y + 0.03, z);
      const delay = i * 0.12;
      this._add(ring, 0.8 + delay, (o, k) => {
        const t = Math.max(0, (k * (0.8 + delay) - delay) / 0.8);
        o.scale.setScalar((small ? 0.4 : 0.6) + t * (small ? 0.8 : 1.6));
        o.material.opacity = t > 0 ? 0.8 * (1 - t) : 0;
      });
    }
  }

  // a quick burst of light on a target (Smite)
  flash(pos, color) {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.textures.glint, color, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
    this._add(s, 0.4, (o, k) => {
      o.position.set(pos.x, pos.y + 1.2 + k * 0.6, pos.z);
      o.scale.setScalar(1.6 * (1 - k * 0.5));
      o.material.opacity = 1 - k;
    });
  }

  // consecrated ground: a glowing ring that stays for the spell's duration
  zone(x, z, radius, duration) {
    const mat = new THREE.MeshBasicMaterial({ map: this.game.textures.ring, color: 0xffd070, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending });
    const ring = new THREE.Mesh(this.ringGeo, mat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(x, heightAt(x, z) + 0.1, z);
    ring.scale.setScalar(radius * 2);
    this._add(ring, duration, (o, k) => {
      o.material.opacity = (0.55 + 0.25 * Math.sin(k * duration * Math.PI * 2)) * Math.min(1, (1 - k) * 6);
    });
  }

  pillar(pos, color = 0xffe2a8) {
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 });
    const col = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 0.8, 4, 10, 1, true), mat);
    col.position.set(pos.x, pos.y + 2, pos.z);
    this._add(col, 1.4, (o, k) => {
      o.material.opacity = Math.sin(k * Math.PI) * 0.25;
      o.position.copy(this.game.player.position);
      o.position.y += 2 + k;
    });
  }

  update(dt) {
    for (const it of [...this.items]) {
      it.age += dt;
      const k = Math.min(1, it.age / it.life);
      it.update(it.obj, k, dt);
      if (k >= 1) {
        this.game.scene.remove(it.obj);
        if (it.obj.material && it.obj.material !== this.dustMat) it.obj.material.dispose();
        if (!it.obj.isSprite && it.obj.geometry && it.obj.geometry !== this.ringGeo && it.obj.geometry !== this.dustGeo) it.obj.geometry.dispose();
        this.items.splice(this.items.indexOf(it), 1);
      }
    }
  }
}
