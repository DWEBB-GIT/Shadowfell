import * as THREE from 'three';
import { heightAt } from '../world/terrain.js';

// Ground telegraphs, after Final Fantasy XIV: before a big enemy's heavy
// attack lands, its area is painted on the ground and fills up as the
// wind-up runs. Whoever is still inside when it fills is hit. The marked
// area is fixed when the wind-up starts, so stepping or rolling out works.

export class ConeShape {
  constructor(x, z, angle, range, arcDeg) {
    this.x = x;
    this.z = z;
    this.angle = angle; // facing, radians (0 = +z)
    this.range = range;
    this.half = (arcDeg * Math.PI) / 360;
  }

  contains(px, pz, radius = 0) {
    const dx = px - this.x;
    const dz = pz - this.z;
    const d = Math.hypot(dx, dz);
    if (d > this.range + radius) return false;
    if (d < 0.6) return true;
    let diff = Math.atan2(dx, dz) - this.angle;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    // allow the player's body to clip the edge of the arc
    return Math.abs(diff) <= this.half + Math.asin(Math.min(1, radius / Math.max(d, radius)));
  }
}

// A strip from the caster along a direction: arrows and bolts fly down it.
export class LineShape {
  constructor(x, z, angle, length, width) {
    this.x = x;
    this.z = z;
    this.angle = angle;
    this.length = length;
    this.width = width;
  }

  contains(px, pz, radius = 0) {
    const dx = px - this.x;
    const dz = pz - this.z;
    const along = dx * Math.sin(this.angle) + dz * Math.cos(this.angle);
    const across = dx * Math.cos(this.angle) - dz * Math.sin(this.angle);
    return along >= -radius && along <= this.length + radius && Math.abs(across) <= this.width / 2 + radius;
  }
}

export class CircleShape {
  constructor(x, z, radius) {
    this.x = x;
    this.z = z;
    this.range = radius;
  }

  contains(px, pz, radius = 0) {
    return Math.hypot(px - this.x, pz - this.z) <= this.range + radius;
  }
}

const vertexShader = `
  attribute float aRad;
  varying float vRad;
  varying float vEdge;
  attribute float aEdge;
  void main() {
    vRad = aRad;
    vEdge = aEdge;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const fragmentShader = `
  uniform float uProgress;
  uniform vec3 uColor;
  uniform float uOpacity;
  varying float vRad;
  varying float vEdge;
  void main() {
    float base = 0.16;
    float fill = step(vRad, uProgress) * 0.34;
    float front = smoothstep(0.035, 0.0, abs(vRad - uProgress)) * 0.5;
    float rim = smoothstep(0.93, 1.0, max(vRad, vEdge)) * 0.6;
    gl_FragColor = vec4(uColor, (base + fill + front + rim) * uOpacity);
  }
`;

// A sector mesh that follows the terrain, with per-vertex radial distance.
// A full circle is a sector of 360 degrees with no side edges.
function sectorGeometry(shape, rings = 10, segs = 24) {
  const pos = [];
  const rad = [];
  const edge = [];
  const idx = [];
  const full = shape.half === undefined;
  const half = full ? Math.PI : shape.half;
  const start = (shape.angle || 0) - half;
  const step = (half * 2) / segs;
  for (let r = 0; r <= rings; r++) {
    const k = r / rings;
    for (let s = 0; s <= segs; s++) {
      const a = start + step * s;
      const x = shape.x + Math.sin(a) * shape.range * k;
      const z = shape.z + Math.cos(a) * shape.range * k;
      pos.push(x, heightAt(x, z) + 0.06, z);
      rad.push(k);
      edge.push(!full && (s === 0 || s === segs) ? 1 : 0);
    }
  }
  for (let r = 0; r < rings; r++) {
    for (let s = 0; s < segs; s++) {
      const a = r * (segs + 1) + s;
      const b = a + segs + 1;
      idx.push(a, b, a + 1, a + 1, b, b + 1);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('aRad', new THREE.Float32BufferAttribute(rad, 1));
  g.setAttribute('aEdge', new THREE.Float32BufferAttribute(edge, 1));
  g.setIndex(idx);
  return g;
}

// A strip mesh: the fill runs from the caster to the far end.
function lineGeometry(shape, rows = 16) {
  const pos = [];
  const rad = [];
  const edge = [];
  const idx = [];
  const fx = Math.sin(shape.angle);
  const fz = Math.cos(shape.angle);
  for (let r = 0; r <= rows; r++) {
    const k = r / rows;
    for (let c = 0; c <= 2; c++) {
      const side = (c - 1) * (shape.width / 2);
      const x = shape.x + fx * shape.length * k + fz * side;
      const z = shape.z + fz * shape.length * k - fx * side;
      pos.push(x, heightAt(x, z) + 0.07, z);
      rad.push(k);
      edge.push(c === 1 ? 0 : 1);
    }
  }
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < 2; c++) {
      const a = r * 3 + c;
      const b = a + 3;
      idx.push(a, b, a + 1, a + 1, b, b + 1);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('aRad', new THREE.Float32BufferAttribute(rad, 1));
  g.setAttribute('aEdge', new THREE.Float32BufferAttribute(edge, 1));
  g.setIndex(idx);
  return g;
}

export class Telegraphs {
  constructor(game) {
    this.game = game;
    this.active = [];
  }

  // Starts a telegraph; `onComplete(shape)` runs when it fills.
  cone(owner, { angle, range, arc, duration, heavy = false, onComplete }) {
    const shape = new ConeShape(owner.position.x, owner.position.z, angle, range, arc);
    return this._start(owner, shape, sectorGeometry(shape), { duration, heavy, onComplete });
  }

  // An aimed line from the owner: an archer's shot or a seer's bolt.
  line(owner, { angle, length, width, duration, color = 0xe8a040, onComplete }) {
    const shape = new LineShape(owner.position.x, owner.position.z, angle, length, width);
    return this._start(owner, shape, lineGeometry(shape), { duration, color, onComplete });
  }

  // A circle on the ground anywhere (a spell under the Warden's feet).
  circle(owner, { x, z, radius, duration, color = 0x9a5cff, heavy = true, onComplete }) {
    const shape = new CircleShape(x, z, radius);
    return this._start(owner, shape, sectorGeometry(shape, 10, 32), { duration, heavy, color, onComplete });
  }

  _start(owner, shape, geometry, { duration, heavy = false, color = null, onComplete }) {
    const mat = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      uniforms: {
        uProgress: { value: 0 },
        uOpacity: { value: 1 },
        uColor: { value: new THREE.Color(color ?? (heavy ? 0xff6a1a : 0xe8a040)) },
      },
    });
    const mesh = new THREE.Mesh(geometry, mat);
    mesh.renderOrder = 2;
    this.game.scene.add(mesh);
    const t = { owner, shape, mesh, t: 0, duration, heavy, onComplete, done: false };
    this.active.push(t);
    this.game.events.emit('telegraph', { owner, heavy });
    return t;
  }

  cancel(t) {
    if (!t || t.done) return;
    t.done = true;
    this._remove(t);
  }

  cancelFor(owner) {
    for (const t of [...this.active]) if (t.owner === owner) this.cancel(t);
  }

  _remove(t) {
    this.game.scene.remove(t.mesh);
    t.mesh.geometry.dispose();
    t.mesh.material.dispose();
    const i = this.active.indexOf(t);
    if (i >= 0) this.active.splice(i, 1);
  }

  clear() {
    for (const t of [...this.active]) this.cancel(t);
  }

  update(dt) {
    for (const t of [...this.active]) {
      if (t.owner.dead) {
        this.cancel(t);
        continue;
      }
      t.t += dt;
      const k = Math.min(1, t.t / t.duration);
      t.mesh.material.uniforms.uProgress.value = k;
      if (k >= 1 && !t.done) {
        t.done = true;
        try {
          t.onComplete && t.onComplete(t.shape);
        } finally {
          this._remove(t);
        }
      }
    }
  }
}
