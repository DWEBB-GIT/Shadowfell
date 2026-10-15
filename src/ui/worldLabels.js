import * as THREE from 'three';
import { ITEMS, RARITY, itemView } from '../data/items.js';

// Text over things in the world, kept in one pooled HTML layer: the names of
// items lying on the ground in their rarity colour (as in WoW and Diablo),
// and (see `sources`) anything else that wants a floating label.

const RANGE = 18; // metres from the Warden

export class WorldLabels {
  constructor(game, layer) {
    this.game = game;
    this.layer = layer;
    this.pool = [];
    this.tmp = new THREE.Vector3();
    // each source returns [{ key, text, colour, x, y, z, cls }]
    this.sources = [() => this._groundItems()];
  }

  _groundItems() {
    const out = [];
    for (const l of this.game.loot.active) {
      const r = l.def.reward;
      if (!r || !r.item || !ITEMS[r.item]) continue;
      const v = itemView({ id: r.item, rolls: r.rolls });
      out.push({ text: `${v.name}${r.count > 1 ? ` ×${r.count}` : ''}`, colour: RARITY[v.rarity].colour, x: l.x, y: l.baseY + 0.75, z: l.z, cls: 'loot-label' });
    }
    return out;
  }

  update() {
    const { camera, renderer, player } = this.game;
    const w = renderer.domElement.clientWidth;
    const h = renderer.domElement.clientHeight;
    const p = player.position;
    let n = 0;
    for (const src of this.sources) {
      for (const lab of src()) {
        if (Math.hypot(lab.x - p.x, lab.z - p.z) > RANGE) continue;
        this.tmp.set(lab.x, lab.y, lab.z).project(camera);
        if (this.tmp.z > 1 || Math.abs(this.tmp.x) > 1.1 || Math.abs(this.tmp.y) > 1.1) continue;
        let el = this.pool[n];
        if (!el) {
          el = this.pool[n] = document.createElement('div');
          this.layer.appendChild(el);
        }
        if (el.textContent !== lab.text) el.textContent = lab.text;
        const cls = 'wlabel ' + (lab.cls || '');
        if (el.className !== cls) el.className = cls;
        el.style.color = lab.colour || '';
        el.style.transform = `translate(${((this.tmp.x + 1) / 2) * w}px, ${((1 - this.tmp.y) / 2) * h}px) translate(-50%, -100%)`;
        el.hidden = false;
        n++;
      }
    }
    for (let i = n; i < this.pool.length; i++) this.pool[i].hidden = true;
  }
}
