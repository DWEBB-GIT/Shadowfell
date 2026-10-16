import * as THREE from 'three';
import { ITEMS } from '../data/items.js';
import { heightAt } from '../world/terrain.js';

// A few gold motes rising from things worth walking over to: unopened
// chests, quest items lying in the world and places still to examine.
// One shared Points cloud, refilled from the sources every frame.

const PER = 9; // motes per thing
const MAX = 40; // things at once
const RANGE = 30; // metres from the Warrior

export class Sparkles {
  constructor(game) {
    this.game = game;
    this.positions = new Float32Array(PER * MAX * 3);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.positions, 3));
    geo.setDrawRange(0, 0);
    const mat = new THREE.PointsMaterial({
      size: 0.22,
      map: game.textures.glint,
      color: 0xffd27a,
      transparent: true,
      opacity: 0.9,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    this.points = new THREE.Points(geo, mat);
    this.points.frustumCulled = false;
    this.points.name = 'Sparkles';
    game.scene.add(this.points);
    this.t = 0;
  }

  // [{ x, z, y }] of everything that sparkles right now
  spots() {
    const { chests, loot, world, worldState } = this.game;
    const out = [];
    for (const c of chests.list) if (!chests.opened(c)) out.push({ x: c.x, z: c.z, y: 0.5 });
    for (const l of loot.active) {
      const id = l.def.reward && l.def.reward.item;
      if (!l.def.ground && id && ITEMS[id] && ITEMS[id].quest) out.push({ x: l.x, z: l.z, y: (l.def.heightOffset || 0) + 0.2 });
    }
    for (const p of world.examinePoints) if (!worldState.examined.has(p.id)) out.push({ x: p.x, z: p.z, y: 0.6 });
    return out;
  }

  update(dt) {
    this.t += dt;
    const p = this.game.player.position;
    const spots = this.spots().filter((s) => Math.hypot(s.x - p.x, s.z - p.z) < RANGE).slice(0, MAX);
    let n = 0;
    spots.forEach((s, i) => {
      const base = heightAt(s.x, s.z) + s.y;
      for (let k = 0; k < PER; k++) {
        // each mote rises over 1.6 s on its own phase, drifting round the spot
        const ph = (this.t / 1.6 + k / PER + i * 0.37) % 1;
        const a = k * 2.4 + this.t * 0.8;
        const r = 0.35 + 0.15 * Math.sin(k * 1.7);
        this.positions[n * 3] = s.x + Math.cos(a) * r;
        this.positions[n * 3 + 1] = base + ph * 1.1;
        this.positions[n * 3 + 2] = s.z + Math.sin(a) * r;
        n++;
      }
    });
    this.points.geometry.attributes.position.needsUpdate = true;
    this.points.geometry.setDrawRange(0, n);
  }
}
