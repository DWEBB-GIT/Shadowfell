import * as THREE from 'three';
import { ITEMS, RARITY, itemView } from '../data/items.js';

// Text over things in the world, kept in one pooled HTML layer: the names of
// items lying on the ground in their rarity colour (as in WoW and Diablo),
// and nameplates over townsfolk (with their title) and enemies (until their
// health bar, which carries the name, takes over), and your own name over
// your character. Settings (O) hide each. Nothing shows through a roof: a
// label inside a building only shows while you are in there too.

const RANGE = 18; // metres from the Warden

export class WorldLabels {
  constructor(game, layer) {
    this.game = game;
    this.layer = layer;
    this.pool = [];
    this.tmp = new THREE.Vector3();
    // each source returns [{ key, text, colour, x, y, z, cls }]
    this.sources = [() => this._groundItems(), () => this._names()];
  }

  _names() {
    const out = [];
    const { settings, npcs, enemies, hud, player, character } = this.game;
    if (settings.get('playerName') && character?.name && !player.dead) {
      out.push({ text: character.name, colour: '#f0e6c8', x: player.position.x, y: player.position.y + 2.15, z: player.position.z, cls: 'name-label player' });
    }
    if (!settings.get('names')) return out;
    for (const n of npcs.list) {
      const title = n.def.title ? `<${n.def.title}>` : '';
      out.push({ text: n.name, sub: title, colour: '#9ee070', x: n.position.x, y: n.position.y + 2.15, z: n.position.z, cls: 'name-label friendly' });
    }
    for (const e of enemies.list) {
      if (!e.alive || hud.enemyBars.has(e.id)) continue;
      out.push({ text: e.cfg.name, colour: e.cfg.elite ? '#ff8a50' : '#e8604a', x: e.position.x, y: e.position.y + (e.cfg.barHeight || (e.cfg.elite ? 3.0 : 2.1)), z: e.position.z, cls: 'name-label hostile' });
    }
    return out;
  }

  _groundItems() {
    const out = [];
    if (!this.game.settings.get('lootNames')) return out;
    for (const l of this.game.loot.active) {
      const r = l.def.reward;
      // quest pick-ups (firewood, ore...) carry no name: their sparkle and
      // the quest log show them (Dan, 2026-10-19)
      if (l.def.quest) continue;
      const ok = this.game.loot.available(l);
      if (!r || !r.item || !ITEMS[r.item] || !ok) continue;
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
        if (this.game.world?.roofOver?.(lab.x, lab.z)) continue; // indoors, under a roof you can see
        this.tmp.set(lab.x, lab.y, lab.z).project(camera);
        if (this.tmp.z > 1 || Math.abs(this.tmp.x) > 1.1 || Math.abs(this.tmp.y) > 1.1) continue;
        let el = this.pool[n];
        if (!el) {
          el = this.pool[n] = document.createElement('div');
          this.layer.appendChild(el);
        }
        const html = lab.sub ? `${esc(lab.text)}<small>${esc(lab.sub)}</small>` : esc(lab.text);
        if (el._html !== html) el.innerHTML = el._html = html;
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

const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
