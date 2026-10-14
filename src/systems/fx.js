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
    ev.on('shieldBreak', ({ position, radius }) => this.shockwave(position, radius));
    ev.on('enemyHit', ({ enemy, kind }) => this.sparks(enemy.position, kind === 'strike' ? 5 : 8));
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
    ev.on('playerBrace', () => this.braceGlow());
    ev.on('itemDropped', ({ item }) => this.dust({ x: item.x, y: this.game.player.position.y, z: item.z }, 4, 0.2));
  }

  _add(obj, life, update) {
    this.game.scene.add(obj);
    this.items.push({ obj, life, age: 0, update });
  }

  shockwave(pos, radius) {
    const mat = new THREE.MeshBasicMaterial({
      map: this.game.textures.ring,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      color: 0xffd9a0,
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

  pillar(pos) {
    const mat = new THREE.MeshBasicMaterial({ color: 0xffe2a8, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 });
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
