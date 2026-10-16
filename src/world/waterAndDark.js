import * as THREE from 'three';
import { WATER, OBSCURED } from './layout.js';
import { heightAt, waterLevel } from './terrain.js';

// Ponds and dark places, both from data/world.json.
//
// Water: a still surface over a bowl in the ground (terrain.js dips the land
// under it), which the Warrior cannot walk into. Fishing casts into it.
//
// Obscured areas: a dome of darkness. Without a torch in the off hand the
// Warrior cannot enter (the dark pushes them back); with one, the dark thins
// and the torch lights what was hidden inside.

export class WaterAndDark {
  constructor(game) {
    this.game = game;
    this.ponds = [];
    this.domes = [];
  }

  build() {
    const { scene, collision } = this.game;
    for (const w of WATER) {
      const level = waterLevel(w);
      const mat = new THREE.MeshLambertMaterial({ color: 0x1f3a3c, emissive: 0x0a1618, transparent: true, opacity: 0.88 });
      const surface = new THREE.Mesh(new THREE.CircleGeometry(w.radius + 0.4, 48), mat);
      surface.rotation.x = -Math.PI / 2;
      surface.position.set(w.position[0], level, w.position[1]);
      surface.name = 'Water_' + w.id;
      scene.add(surface);
      // a faint ring of light that drifts across the water
      const sheen = new THREE.Mesh(
        new THREE.RingGeometry(w.radius * 0.35, w.radius * 0.42, 40),
        new THREE.MeshBasicMaterial({ color: 0x8fb8b0, transparent: true, opacity: 0.12, depthWrite: false }),
      );
      sheen.rotation.x = -Math.PI / 2;
      sheen.position.set(w.position[0], level + 0.02, w.position[1]);
      scene.add(sheen);
      collision.add(w.position[0], w.position[1], w.radius - 0.3);
      this.ponds.push({ def: w, surface, sheen, level });
    }
    for (const o of OBSCURED) {
      const [x, z] = o.position;
      const mat = new THREE.MeshBasicMaterial({ color: 0x020304, transparent: true, opacity: 0.94, depthWrite: false, side: THREE.DoubleSide });
      const dome = new THREE.Mesh(new THREE.SphereGeometry(o.radius + 0.6, 32, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat);
      dome.scale.y = 0.75;
      dome.position.set(x, heightAt(x, z) - 0.4, z);
      dome.renderOrder = 4;
      dome.name = 'Obscured_' + o.id;
      scene.add(dome);
      this.domes.push({ def: o, dome, mat });
    }
    return this;
  }

  // the Warrior carries a light (a torch in the off hand)
  get hasLight() {
    return this.game.player.lightRadius > 0;
  }

  obscuredAt(x, z, margin = 0) {
    return OBSCURED.find((o) => Math.hypot(x - o.position[0], z - o.position[1]) <= o.radius + margin) || null;
  }

  update(dt, time) {
    const { player, events } = this.game;
    for (const p of this.ponds) {
      const k = (time * 0.15) % 1;
      p.sheen.scale.setScalar(0.6 + k * 1.2);
      p.sheen.material.opacity = 0.14 * Math.sin(k * Math.PI);
    }
    const lit = this.hasLight;
    for (const d of this.domes) {
      const target = lit ? 0.35 : 0.94;
      d.mat.opacity += (target - d.mat.opacity) * Math.min(1, dt * 3);
      // the dark keeps out anyone without a light
      if (lit) continue;
      const [x, z] = d.def.position;
      const dx = player.position.x - x;
      const dz = player.position.z - z;
      const dist = Math.hypot(dx, dz);
      const edge = d.def.radius + player.radius;
      if (dist < edge) {
        const k = dist > 0.01 ? edge / dist : 1;
        player.position.x = x + (dist > 0.01 ? dx : 1) * k;
        player.position.z = z + (dist > 0.01 ? dz : 0) * k;
        events.emit('log', { text: d.def.text || 'It is too dark to go on without a light.', kind: 'muted', throttle: 'dark-' + d.def.id });
      }
    }
  }
}
