import { DB } from '../data/db.js';
import { BOUNDS, REGIONS, PROPS, CLEARINGS, SHRINES, WATER, OBSCURED } from '../world/layout.js';

// A round minimap in the top-right corner, north up (the camera never turns,
// so up on the map is up on the screen). The ground, roads, trees and props
// are painted once into a picture of the whole world; each frame draws the
// part around the Warden, then the markers on top: townsfolk with their
// quest marks, shrines, the places current objectives point to, and the
// Warden as an arrow. Quest marks out of range sit on the rim, pointing the way.

const SIZE = 168; // CSS pixels across
const PX = 4; // picture pixels per metre
const ZOOMS = [2.2, 3.2, 4.6]; // screen pixels per metre
const PAD = 24; // metres painted beyond the world's edge (the woods go on)

const GROUND = { fallen_road: '#4a4634', blackwood: '#26302a' };
const PROP_STYLE = {
  watch_post: ['rect', '#8a6a44', 4.5],
  forge: ['rect', '#8a6a44', 3],
  awning: ['rect', '#7a5c3a', 3],
  palisade: ['rect', '#5e4a32', 2.4],
  fence: ['rect', '#5e4a32', 1.4],
  ruin_wall: ['rect', '#77736a', 2],
  cart: ['rect', '#9a7a4a', 1.8],
  standing_stone: ['dot', '#a8a89c', 0.9],
  grave0: ['dot', '#8c877a', 0.55],
  grave1: ['dot', '#8c877a', 0.55],
  rock0: ['dot', '#6c6a62', 1],
  rock1: ['dot', '#6c6a62', 0.8],
  bone_pile: ['dot', '#b0a890', 0.6],
};

export class Minimap {
  constructor(game) {
    this.game = game;
    this.canvas = document.getElementById('minimap');
    this.zoom = 1;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.dpr = dpr;
    this.canvas.width = this.canvas.height = SIZE * dpr;
    this.canvas.style.width = this.canvas.style.height = SIZE + 'px';
    this.ctx = this.canvas.getContext('2d');
    this.picture = this._paint();
    document.getElementById('minimap-in').addEventListener('click', () => this.setZoom(this.zoom + 1));
    document.getElementById('minimap-out').addEventListener('click', () => this.setZoom(this.zoom - 1));
  }

  setZoom(z) {
    this.zoom = Math.max(0, Math.min(ZOOMS.length - 1, z));
  }

  // ------------------------------------------------- the world, painted once
  _paint() {
    const minX = BOUNDS.minX - PAD;
    const minZ = BOUNDS.minZ - PAD;
    const w = (BOUNDS.maxX - BOUNDS.minX + PAD * 2) * PX;
    const h = (BOUNDS.maxZ - BOUNDS.minZ + PAD * 2) * PX;
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const g = c.getContext('2d');
    const X = (x) => (x - minX) * PX;
    const Z = (z) => (z - minZ) * PX;
    this.origin = { minX, minZ };

    // ground by region, blended across the border
    const border = REGIONS[0].minZ;
    const grad = g.createLinearGradient(0, Z(border - 6), 0, Z(border + 6));
    grad.addColorStop(0, GROUND.blackwood);
    grad.addColorStop(1, GROUND.fallen_road);
    g.fillStyle = grad;
    g.fillRect(0, 0, w, h);
    // clearings read a little lighter
    g.fillStyle = 'rgba(160, 150, 110, 0.10)';
    for (const [x, z, r] of CLEARINGS) {
      g.beginPath();
      g.arc(X(x), Z(z), r * PX, 0, Math.PI * 2);
      g.fill();
    }
    // trees: dark dots, darker in the Blackwood
    for (const [x, z] of this.game.world.mapTrees || []) {
      g.fillStyle = z < border ? 'rgba(8, 14, 10, 0.75)' : 'rgba(22, 30, 18, 0.7)';
      g.beginPath();
      g.arc(X(x), Z(z), 1.3 * PX, 0, Math.PI * 2);
      g.fill();
    }
    // roads
    g.lineCap = g.lineJoin = 'round';
    for (const road of DB.world.roads) {
      g.strokeStyle = road.id === 'fallen_road' ? '#9c8358' : '#7a6848';
      g.lineWidth = road.halfWidth * 1.6 * PX;
      g.beginPath();
      road.points.forEach(([x, z], i) => (i ? g.lineTo(X(x), Z(z)) : g.moveTo(X(x), Z(z))));
      g.stroke();
    }
    // props
    for (const p of PROPS) {
      const style = PROP_STYLE[p.model];
      if (!style) continue;
      const [shape, colour, size] = style;
      g.fillStyle = colour;
      const [x, z] = p.position;
      if (shape === 'dot') {
        g.beginPath();
        g.arc(X(x), Z(z), size * PX, 0, Math.PI * 2);
        g.fill();
      } else {
        g.save();
        g.translate(X(x), Z(z));
        g.rotate(-((p.rotation || 0) * Math.PI) / 180);
        g.fillRect(-size * PX, -size * 0.6 * PX, size * 2 * PX, size * 1.2 * PX);
        g.restore();
      }
    }
    // ponds, and the places too dark to see into
    for (const w of WATER) {
      g.fillStyle = '#2c5056';
      g.beginPath();
      g.arc(X(w.position[0]), Z(w.position[1]), w.radius * PX, 0, Math.PI * 2);
      g.fill();
    }
    for (const o of OBSCURED) {
      g.fillStyle = 'rgba(0, 0, 0, 0.85)';
      g.beginPath();
      g.arc(X(o.position[0]), Z(o.position[1]), o.radius * PX, 0, Math.PI * 2);
      g.fill();
    }
    // beyond the world's edge: darkness
    g.fillStyle = 'rgba(0, 0, 0, 0.55)';
    g.fillRect(0, 0, w, Z(BOUNDS.minZ));
    g.fillRect(0, Z(BOUNDS.maxZ), w, h - Z(BOUNDS.maxZ));
    g.fillRect(0, Z(BOUNDS.minZ), X(BOUNDS.minX), Z(BOUNDS.maxZ) - Z(BOUNDS.minZ));
    g.fillRect(X(BOUNDS.maxX), Z(BOUNDS.minZ), w - X(BOUNDS.maxX), Z(BOUNDS.maxZ) - Z(BOUNDS.minZ));
    return c;
  }

  // ------------------------------------------------------------ markers
  // Every marker for the current state, in world metres:
  // { x, z, kind: 'npc' | 'shrine' | 'area' | 'ready' | 'available' | 'active', r?, label? }
  markers() {
    const { npcs, quests } = this.game;
    const out = [];
    for (const s of SHRINES) out.push({ x: s.position[0], z: s.position[1], kind: 'shrine' });
    // where open objectives point
    const areas = new Map();
    for (const id of quests.active) {
      if (quests.status(id) !== 'active') continue;
      for (const o of quests.objectives(id)) {
        if (o.done || !o.location || areas.has(o.location)) continue;
        const l = DB.locations[o.location];
        areas.set(o.location, { x: l.position[0], z: l.position[1], r: l.radius, kind: 'area', label: l.name, tracked: quests.tracked.has(id) });
      }
    }
    out.push(...areas.values());
    for (const n of npcs.list) {
      const status = quests.markerFor(n.id);
      out.push({ x: n.position.x, z: n.position.z, kind: status || 'npc', label: n.name });
    }
    // the enemy that killed you, and your body while you walk as a spirit
    const { afterlife, enemies, worldState } = this.game;
    const foe = worldState.nemesis && enemies.list.find((e) => e.id === worldState.nemesis && e.alive);
    if (foe) out.push({ x: foe.position.x, z: foe.position.z, kind: 'nemesis', label: foe.cfg.name });
    if (afterlife.corpse) out.push({ x: afterlife.corpse.x, z: afterlife.corpse.z, kind: 'corpse', label: 'Your body' });
    if (worldState.camp) out.push({ x: worldState.camp.x, z: worldState.camp.z, kind: 'camp', label: 'Your camp' });
    return out;
  }

  // ---------------------------------------------------------------- draw
  draw() {
    const { ctx, dpr } = this;
    const p = this.game.player;
    const scale = ZOOMS[this.zoom];
    const R = SIZE / 2;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, SIZE, SIZE);
    ctx.save();
    ctx.beginPath();
    ctx.arc(R, R, R - 1, 0, Math.PI * 2);
    ctx.clip();
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, SIZE, SIZE);
    // the painted world around the Warden
    const k = scale / PX;
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.picture, R - (p.position.x - this.origin.minX) * scale, R - (p.position.z - this.origin.minZ) * scale, this.picture.width * k, this.picture.height * k);

    const toMap = (x, z) => ({ x: R + (x - p.position.x) * scale, y: R + (z - p.position.z) * scale });
    const markers = this.markers();
    // objective areas first, under everything else
    for (const m of markers.filter((m) => m.kind === 'area')) {
      const s = toMap(m.x, m.z);
      ctx.beginPath();
      ctx.arc(s.x, s.y, Math.max(5, m.r * scale), 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(240, 200, 80, 0.16)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(240, 200, 80, 0.7)';
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    for (const m of markers) {
      if (m.kind === 'area') continue;
      const s = toMap(m.x, m.z);
      if (m.kind === 'shrine') {
        if (Math.hypot(s.x - R, s.y - R) > R - 4) continue;
        ctx.fillStyle = '#9fd0ff';
        ctx.beginPath();
        ctx.moveTo(s.x, s.y - 4);
        ctx.lineTo(s.x + 3, s.y);
        ctx.lineTo(s.x, s.y + 4);
        ctx.lineTo(s.x - 3, s.y);
        ctx.fill();
      } else if (m.kind === 'npc') {
        if (Math.hypot(s.x - R, s.y - R) > R - 4) continue;
        ctx.fillStyle = '#e8d8a0';
        ctx.beginPath();
        ctx.arc(s.x, s.y, 2.6, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    // the areas that are off the map get a pointer on the rim
    for (const m of markers.filter((m) => m.kind === 'area' && m.tracked)) this._rim(toMap(m.x, m.z), R, '#f0c850', null, m.r * scale);
    // quest marks last, so they sit on top; out of range ones on the rim
    for (const m of markers.filter((m) => m.kind === 'ready' || m.kind === 'available' || m.kind === 'active')) {
      const s = toMap(m.x, m.z);
      const glyph = m.kind === 'available' ? '!' : '?';
      const colour = m.kind === 'active' ? '#a8a8a8' : '#ffd23c';
      if (Math.hypot(s.x - R, s.y - R) <= R - 8) this._glyph(s.x, s.y, glyph, colour, 15);
      else this._rim(s, R, colour, glyph);
    }
    // your camp, your killer and your body: always shown, on the rim when far
    for (const m of markers) {
      const s = toMap(m.x, m.z);
      const inside = Math.hypot(s.x - R, s.y - R) <= R - 8;
      if (m.kind === 'camp') {
        if (inside) this._glyph(s.x, s.y, '\u25B2', '#ff9a40', 11);
      } else if (m.kind === 'nemesis') {
        if (inside) this._glyph(s.x, s.y, '\u2620', '#ff4a3a', 15);
        else this._rim(s, R, '#ff4a3a', '\u2620');
      } else if (m.kind === 'corpse') {
        if (inside) this._glyph(s.x, s.y, '\u271D', '#cfe6ff', 15);
        else this._rim(s, R, '#cfe6ff', null);
      }
    }
    // the Warden, at the centre, pointing the way they face
    ctx.save();
    ctx.translate(R, R);
    ctx.rotate(Math.PI - p.facing);
    ctx.beginPath();
    ctx.moveTo(0, -7);
    ctx.lineTo(5, 6);
    ctx.lineTo(0, 3);
    ctx.lineTo(-5, 6);
    ctx.closePath();
    ctx.fillStyle = '#ffffff';
    ctx.strokeStyle = '#000';
    ctx.lineWidth = 1.5;
    ctx.stroke();
    ctx.fill();
    ctx.restore();
    ctx.restore();
  }

  _glyph(x, y, glyph, colour, size) {
    const { ctx } = this;
    ctx.font = `bold ${size}px Georgia, serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 3;
    ctx.strokeStyle = '#000';
    ctx.strokeText(glyph, x, y);
    ctx.fillStyle = colour;
    ctx.fillText(glyph, x, y);
  }

  // A marker beyond the edge: a small arrow on the rim pointing at it.
  _rim(s, R, colour, glyph, reach = 0) {
    const dx = s.x - R;
    const dy = s.y - R;
    const d = Math.hypot(dx, dy);
    if (d - reach <= R - 4) return;
    const a = Math.atan2(dy, dx);
    const r = R - 9;
    const x = R + Math.cos(a) * r;
    const y = R + Math.sin(a) * r;
    const { ctx } = this;
    if (glyph) {
      this._glyph(x, y, glyph, colour, 12);
      return;
    }
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(a);
    ctx.beginPath();
    ctx.moveTo(5, 0);
    ctx.lineTo(-3, -4);
    ctx.lineTo(-3, 4);
    ctx.closePath();
    ctx.fillStyle = colour;
    ctx.strokeStyle = '#000';
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.fill();
    ctx.restore();
  }
}
