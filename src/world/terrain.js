import * as THREE from 'three';
import { BOUNDS, ROAD, TRACK, ROAD_HALF_WIDTH } from './layout.js';

// Analytic terrain so gameplay code can ask for the ground height anywhere
// without raycasting. The mesh is built from the same function.

function distToSegment(px, pz, ax, az, bx, bz) {
  const dx = bx - ax;
  const dz = bz - az;
  const len2 = dx * dx + dz * dz;
  let t = len2 > 0 ? ((px - ax) * dx + (pz - az) * dz) / len2 : 0;
  t = Math.max(0, Math.min(1, t));
  const cx = ax + dx * t;
  const cz = az + dz * t;
  return Math.hypot(px - cx, pz - cz);
}

function distanceToLine(line, x, z) {
  let best = Infinity;
  for (let i = 0; i < line.length - 1; i++) {
    const d = distToSegment(x, z, line[i][0], line[i][1], line[i + 1][0], line[i + 1][1]);
    if (d < best) best = d;
  }
  return best;
}

// The Fallen Road alone (the original woodland is laid out around it).
export const distanceToMainRoad = (x, z) => distanceToLine(ROAD, x, z);

// The road or the forest track, whichever is nearer.
export function distanceToRoad(x, z) {
  return Math.min(distanceToLine(ROAD, x, z), distanceToLine(TRACK, x, z));
}

// 0 on the Fallen Road, rising to 1 a little way into the Blackwood.
export const blackwoodness = (z) => THREE.MathUtils.smoothstep(-z, 52, 66);

function rawHeight(x, z) {
  let h =
    Math.sin(x * 0.11) * Math.cos(z * 0.09) * 0.9 +
    Math.sin(x * 0.27 + 1.3) * Math.sin(z * 0.23 + 0.7) * 0.35 +
    Math.cos(x * 0.6 + z * 0.4) * 0.08;
  // the land climbs towards the watch post in the north-east, levels off
  // beyond it, and sinks into the Blackwood's hollow
  h += Math.max(0, (Math.min(-z, 56) - 20) * 0.06) * Math.max(0, (x + 10) / 40);
  h -= THREE.MathUtils.smoothstep(-z, 56, 76) * 1.4;
  // hills rise outside the playable area so the edge reads as natural terrain
  const ex = Math.max(0, BOUNDS.minX + 4 - x, x - (BOUNDS.maxX - 4));
  const ez = Math.max(0, BOUNDS.minZ + 4 - z, z - (BOUNDS.maxZ - 4));
  const e = Math.hypot(ex, ez);
  h += e * e * 0.05;
  return h;
}

export function heightAt(x, z) {
  const h = rawHeight(x, z);
  // flatten the road bed a little
  const d = distanceToRoad(x, z);
  const k = THREE.MathUtils.smoothstep(d, ROAD_HALF_WIDTH * 0.6, ROAD_HALF_WIDTH * 2.5);
  return THREE.MathUtils.lerp(h * 0.55 - 0.05, h, k);
}

// Seeded random so the woodland is identical on every launch.
export function seededRandom(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function buildTerrain(textures) {
  const width = BOUNDS.maxX - BOUNDS.minX + 70;
  const depth = BOUNDS.maxZ - BOUNDS.minZ + 70;
  const segX = Math.round(width / 1.25);
  const segZ = Math.round(depth / 1.25);
  const geo = new THREE.PlaneGeometry(width, depth, segX, segZ);
  geo.rotateX(-Math.PI / 2);
  const cx = (BOUNDS.minX + BOUNDS.maxX) / 2;
  const cz = (BOUNDS.minZ + BOUNDS.maxZ) / 2;
  geo.translate(cx, 0, cz);

  const pos = geo.attributes.position;
  const colors = new Float32Array(pos.count * 3);
  const rand = seededRandom(42);
  const grass = new THREE.Color(0x3b4a2c);
  const grassDark = new THREE.Color(0x2a3622);
  const dirt = new THREE.Color(0x5a4a36);
  const roadCol = new THREE.Color(0x6a5c48);
  const bwFloor = new THREE.Color(0x1f2419);
  const bwMoss = new THREE.Color(0x2a3a22);
  const c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);
    pos.setY(i, heightAt(x, z));
    const d = distanceToRoad(x, z);
    c.copy(grass).lerp(grassDark, rand() * 0.7);
    if (rand() < 0.12) c.lerp(dirt, 0.5);
    const roadK = 1 - THREE.MathUtils.smoothstep(d, ROAD_HALF_WIDTH * 0.7, ROAD_HALF_WIDTH * 1.35);
    c.lerp(roadCol, roadK * (0.75 + rand() * 0.25));
    // the Blackwood floor: dark needles and moss
    const bw = blackwoodness(z);
    if (bw > 0) c.lerp(rand() < 0.3 ? bwMoss : bwFloor, bw * 0.75);
    // turned earth around Hallow Cut
    const hc = Math.hypot(x - 22.5, z + 19.5);
    if (hc < 7) c.lerp(dirt, (1 - hc / 7) * 0.6);
    colors[i * 3] = c.r;
    colors[i * 3 + 1] = c.g;
    colors[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  // world-space UVs so the detail texture tiles at a fixed scale
  const uv = geo.attributes.uv;
  for (let i = 0; i < pos.count; i++) uv.setXY(i, pos.getX(i) / 6, pos.getZ(i) / 6);
  geo.computeVertexNormals();

  const mat = new THREE.MeshLambertMaterial({
    vertexColors: true,
    map: textures.groundDetail,
    flatShading: true,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.name = 'Terrain';
  return mesh;
}
