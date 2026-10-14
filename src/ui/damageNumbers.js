import * as THREE from 'three';

// Floating damage numbers. Restrained, as the design asks: small serif
// figures in muted colours that drift up and fade, not bright arcade text.
//   dealt  parchment white      taken  dull red
//   crit   larger amber, "!"    block  grey "Block"     heal  green "+n"

const LIFE = 1.1; // seconds on screen
const MAX = 40;

export class DamageNumbers {
  constructor(game, layer) {
    this.game = game;
    this.layer = layer;
    this.items = []; // { el, x, y, z, t, dx }
    this.tmp = new THREE.Vector3();
    game.events.on('damageNumber', (e) => this.add(e));
  }

  add({ target, amount, crit = false, blocked = 0, kind }) {
    if (!target) return;
    let text;
    let cls = kind;
    if (kind === 'heal') {
      if (amount <= 0) return;
      text = `+${amount}`;
    } else if (blocked && amount === 0) {
      text = 'Block';
      cls = 'block';
    } else {
      text = `${amount}${crit ? '!' : ''}`;
      if (blocked) text += ` (${blocked} blocked)`;
    }
    if (crit) cls += ' crit';
    const el = document.createElement('div');
    el.className = 'dmg ' + cls;
    el.textContent = text;
    this.layer.appendChild(el);
    const p = target.position;
    const high = target.cfg && target.cfg.elite ? 2.6 : 1.8;
    // spread numbers a little so quick hits do not stack exactly
    const dx = (this.items.length % 3) * 14 - 14;
    this.items.push({ el, x: p.x, y: p.y + high, z: p.z, t: 0, dx, crit });
    while (this.items.length > MAX) this.items.shift().el.remove();
  }

  update(dt) {
    const { camera, renderer } = this.game;
    const w = renderer.domElement.clientWidth;
    const h = renderer.domElement.clientHeight;
    for (let i = this.items.length - 1; i >= 0; i--) {
      const n = this.items[i];
      n.t += dt;
      if (n.t >= LIFE) {
        n.el.remove();
        this.items.splice(i, 1);
        continue;
      }
      const k = n.t / LIFE;
      this.tmp.set(n.x, n.y, n.z).project(camera);
      const sx = ((this.tmp.x + 1) / 2) * w + n.dx;
      const sy = ((1 - this.tmp.y) / 2) * h - k * 46;
      // crits swell briefly, everything fades over the last half
      const scale = n.crit ? 1 + 0.35 * Math.max(0, 1 - n.t * 6) : 1;
      n.el.style.transform = `translate(${sx}px, ${sy}px) translate(-50%, -50%) scale(${scale.toFixed(3)})`;
      n.el.style.opacity = (k < 0.5 ? 1 : 1 - (k - 0.5) * 2).toFixed(3);
      n.el.style.display = this.tmp.z < 1 ? '' : 'none';
    }
  }

  clear() {
    for (const n of this.items) n.el.remove();
    this.items = [];
  }
}
