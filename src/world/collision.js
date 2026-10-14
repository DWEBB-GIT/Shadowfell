import { BOUNDS } from './layout.js';

// Static obstacles are circles on the ground plane. That is enough for trees,
// rocks, ruins and the cart, and is cheap and predictable to resolve.

export class Collision {
  constructor() {
    this.circles = [];
    this.cellSize = 6;
    this.grid = new Map();
  }

  _key(cx, cz) {
    return cx * 10007 + cz;
  }

  add(x, z, r) {
    const c = { x, z, r };
    this.circles.push(c);
    const minX = Math.floor((x - r) / this.cellSize);
    const maxX = Math.floor((x + r) / this.cellSize);
    const minZ = Math.floor((z - r) / this.cellSize);
    const maxZ = Math.floor((z + r) / this.cellSize);
    for (let i = minX; i <= maxX; i++) {
      for (let j = minZ; j <= maxZ; j++) {
        const k = this._key(i, j);
        if (!this.grid.has(k)) this.grid.set(k, []);
        this.grid.get(k).push(c);
      }
    }
  }

  _nearby(x, z, r) {
    const out = new Set();
    const minX = Math.floor((x - r) / this.cellSize);
    const maxX = Math.floor((x + r) / this.cellSize);
    const minZ = Math.floor((z - r) / this.cellSize);
    const maxZ = Math.floor((z + r) / this.cellSize);
    for (let i = minX; i <= maxX; i++) {
      for (let j = minZ; j <= maxZ; j++) {
        const list = this.grid.get(this._key(i, j));
        if (list) for (const c of list) out.add(c);
      }
    }
    return out;
  }

  // Push a moving circle out of obstacles and keep it inside the region.
  resolve(pos, radius) {
    for (let pass = 0; pass < 2; pass++) {
      for (const c of this._nearby(pos.x, pos.z, radius + 2)) {
        const dx = pos.x - c.x;
        const dz = pos.z - c.z;
        const min = c.r + radius;
        const d2 = dx * dx + dz * dz;
        if (d2 < min * min) {
          const d = Math.sqrt(d2) || 0.0001;
          pos.x = c.x + (dx / d) * min;
          pos.z = c.z + (dz / d) * min;
        }
      }
    }
    this.clampToBounds(pos, radius);
    return pos;
  }

  clampToBounds(pos, radius = 0) {
    pos.x = Math.min(BOUNDS.maxX - radius, Math.max(BOUNDS.minX + radius, pos.x));
    pos.z = Math.min(BOUNDS.maxZ - radius, Math.max(BOUNDS.minZ + radius, pos.z));
    return pos;
  }

  isInside(x, z) {
    return x >= BOUNDS.minX && x <= BOUNDS.maxX && z >= BOUNDS.minZ && z <= BOUNDS.maxZ;
  }
}
