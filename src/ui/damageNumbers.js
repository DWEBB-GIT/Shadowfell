import * as THREE from 'three';
import { CONFIG } from '../config.js';

// Floating damage numbers: serif figures that drift up and fade.
//   dealt  parchment white      taken  dull red "-n"
//   crit   amber, "!"           block  grey "Block"     heal  green "+n"
//
// Size tells you how hard a hit was (Dan, 2026-10-16): each number is sized
// against your usual white hit (the average auto attack swing of the hand
// that struck, or the enemy's usual blow for damage taken). Bigger than
// usual reads bigger, smaller reads smaller. Crits stay a little longer, and
// a crit of twice your usual hit or more pulses once as it lands. Tuning in
// CONFIG.damageNumbers.

const MAX = 40;

// how big a number is against the usual hit (1 = the base font)
export function numberScale(amount, usual) {
  const t = CONFIG.damageNumbers;
  if (!usual || usual <= 0 || !amount) return 1;
  return Math.min(t.maxScale, Math.max(t.minScale, Math.pow(amount / usual, t.sizePower)));
}

export class DamageNumbers {
  constructor(game, layer) {
    this.game = game;
    this.layer = layer;
    this.items = []; // { el, x, y, z, t, dx, life, pulse }
    this.tmp = new THREE.Vector3();
    game.events.on('damageNumber', (e) => this.add(e));
  }

  // your usual white hit with that hand, before armour
  usualHit(hand = 'main') {
    const st = this.game.stats;
    if (!st) return 0;
    const h = hand === 'ranged' && this.game.inventory.rangedWeapon ? 'ranged' : 'main';
    const [lo, hi] = st.swingRangeFor(h);
    return (lo + hi) / 2;
  }

  add({ target, amount, crit = false, blocked = 0, kind, hand = 'main', usual = 0 }) {
    if (!target) return;
    const t = CONFIG.damageNumbers;
    let text;
    let cls = kind;
    let ratio = 1;
    if (kind === 'heal') {
      if (amount <= 0) return;
      text = `+${amount}`;
    } else if (blocked && amount === 0) {
      text = 'Block';
      cls = 'block';
    } else {
      text = `${kind === 'taken' ? '-' : ''}${amount}${crit ? '!' : ''}`;
      if (blocked) text += ` (${blocked} blocked)`;
      const ref = kind === 'dealt' ? this.usualHit(hand) : usual;
      ratio = ref > 0 ? amount / ref : 1;
    }
    if (crit) cls += ' crit';
    const scale = cls === 'block' ? 0.8 : numberScale(ratio, 1);
    const el = document.createElement('div');
    el.className = 'dmg ' + cls;
    el.textContent = text;
    el.style.fontSize = `${Math.round(t.font * scale)}px`;
    this.layer.appendChild(el);
    const p = target.position;
    const high = target.cfg && target.cfg.elite ? 2.6 : 1.8;
    // spread numbers a little so quick hits do not stack exactly
    const dx = (this.items.length % 3) * 18 - 18;
    const pulse = crit && ratio >= t.pulseAt;
    if (pulse) el.classList.add('big');
    this.items.push({ el, x: p.x, y: p.y + high, z: p.z, t: 0, dx, crit, pulse, life: crit ? t.critLife : t.life });
    while (this.items.length > MAX) this.items.shift().el.remove();
  }

  update(dt) {
    const { camera, renderer } = this.game;
    const w = renderer.domElement.clientWidth;
    const h = renderer.domElement.clientHeight;
    const t = CONFIG.damageNumbers;
    for (let i = this.items.length - 1; i >= 0; i--) {
      const n = this.items[i];
      n.t += dt;
      if (n.t >= n.life) {
        n.el.remove();
        this.items.splice(i, 1);
        continue;
      }
      const k = n.t / n.life;
      this.tmp.set(n.x, n.y, n.z).project(camera);
      const sx = ((this.tmp.x + 1) / 2) * w + n.dx;
      const sy = ((1 - this.tmp.y) / 2) * h - k * 50;
      // crits pop in a touch large and settle; a huge crit swells once
      // more, an impact, after landing
      let scale = n.crit ? 1 + 0.25 * Math.max(0, 1 - n.t * 6) : 1;
      if (n.pulse && n.t < 0.45) scale += t.pulse * Math.sin((n.t / 0.45) * Math.PI);
      n.el.style.transform = `translate(${sx}px, ${sy}px) translate(-50%, -50%) scale(${scale.toFixed(3)})`;
      // everything fades over the last 40% of its life
      n.el.style.opacity = (k < 0.6 ? 1 : 1 - (k - 0.6) / 0.4).toFixed(3);
      n.el.style.display = this.tmp.z < 1 ? '' : 'none';
    }
  }

  clear() {
    for (const n of this.items) n.el.remove();
    this.items = [];
  }
}
