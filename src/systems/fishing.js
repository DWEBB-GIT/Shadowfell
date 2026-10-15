import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { DB } from '../data/db.js';
import { ITEMS, rollLoot } from '../data/items.js';
import { waterAt, waterLevel } from '../world/terrain.js';

// Fishing, WoW style. With the Fishing skill (from Old Tam) and a rod in the
// bags, the Fishing ability casts a bob into the water you face. After a
// while the bob dips: strike then (click the bob, or E / A) for a chance to
// land a fish from that water's loot table (data: world.json `water`
// `fishTable`). Too soon or too late and it gets away. The chance rises with
// skill rank, and bait in the bags (an item with `bait`: a bonus in percent,
// one used per strike) adds to it. Fish are never seen in the water.
//
// Phases: 'cast' (the bob flies) -> 'wait' -> 'bite' (strike now) -> done.

export class Fishing {
  constructor(game) {
    this.game = game;
    this.state = null; // { phase, t, wait, x, z, water, bob }
  }

  get active() {
    return !!this.state;
  }

  get biting() {
    return this.state && this.state.phase === 'bite';
  }

  // Cast towards the aim point (or straight ahead) if it is water within reach.
  cast(aim) {
    const { player, skills, inventory, events } = this.game;
    const say = (text, key) => events.emit('log', { text, kind: 'muted', throttle: key });
    if (!skills.has('fishing')) return say('You do not know how to fish. Old Tam by the mere can teach you.', 'fish-skill'), false;
    if (inventory.count(DB.abilities.fish.requiresItem) < 1) return say('You need a fishing rod in your bags.', 'fish-rod'), false;
    if (player.casting || player.pending) return false;
    this.stop(true);
    const range = DB.abilities.fish.range;
    const p = player.position;
    let spot = null;
    if (aim && Math.hypot(aim.x - p.x, aim.z - p.z) <= range && waterAt(aim.x, aim.z, 0.6)) spot = { x: aim.x, z: aim.z };
    else {
      const fx = Math.sin(player.facing);
      const fz = Math.cos(player.facing);
      for (let d = 2.5; d <= range && !spot; d += 0.5) if (waterAt(p.x + fx * d, p.z + fz * d, 0.6)) spot = { x: p.x + fx * (d + 1), z: p.z + fz * (d + 1) };
    }
    const water = spot && waterAt(spot.x, spot.z, 0.3);
    if (!water) return say('Face open water to fish.', 'fish-water'), false;
    player.faceTowards(spot.x, spot.z);
    player.holdRod(true);
    player.rig.play('castLine', 0.7, 0.45);
    const cfg = CONFIG.fishing;
    const wait = cfg.biteMin + (cfg.biteMax - cfg.biteMin) * this.game.random();
    this.state = { phase: 'cast', t: 0, wait, x: spot.x, z: spot.z, water, bob: this._makeBob(), line: this._makeLine(), from: p.clone() };
    events.emit('fishCast', { x: spot.x, z: spot.z });
    return true;
  }

  // The catch chance in percent for the next strike.
  get chance() {
    const cfg = CONFIG.fishing;
    const bait = this._bait();
    return Math.min(100, cfg.baseChance + this.game.skills.rank('fishing') * cfg.chancePerRank + (bait ? ITEMS[bait].bait : 0));
  }

  _bait() {
    const inv = this.game.inventory;
    return Object.keys(ITEMS).find((id) => ITEMS[id].bait && inv.count(id) > 0) || null;
  }

  // Click the bob, or E / A: strike.
  strike() {
    const s = this.state;
    if (!s) return false;
    const { events, inventory, skills } = this.game;
    if (s.phase !== 'bite') {
      events.emit('log', { text: 'You strike too soon. Whatever was there is gone.', kind: 'muted' });
      this.stop();
      return true;
    }
    const bait = this._bait();
    const chance = this.chance;
    if (bait) inventory.removeCount(bait, 1);
    if (this.game.random() * 100 >= chance) {
      events.emit('log', { text: 'The fish slips the hook.', kind: 'muted' });
      this.stop();
      return true;
    }
    const caught = rollLoot(DB.lootTables[s.water.fishTable], this.game.random);
    for (const c of caught) {
      if (inventory.roomFor(c.id) < c.count) {
        events.emit('log', { text: 'Your bags are full. You let it go.', kind: 'muted' });
        continue;
      }
      inventory.addItem(c.id, c.count);
      const name = ITEMS[c.id].name;
      events.emit('log', { text: `You catch ${/^[aeiou]/i.test(name) ? 'an' : 'a'} ${name}.`, kind: 'loot', rarity: c.rarity });
    }
    events.emit('fishCaught', { items: caught });
    skills.raise('fishing');
    this.stop();
    return true;
  }

  // Reel in (moving, fighting or a new cast ends it).
  stop(quiet = false) {
    if (!this.state) return;
    this.game.scene.remove(this.state.bob);
    this.game.scene.remove(this.state.line);
    this.state.line.geometry.dispose();
    this.state = null;
    this.game.player.holdRod(false);
    if (!quiet) this.game.events.emit('fishEnd', {});
  }

  update(dt) {
    const s = this.state;
    if (!s) return;
    const { player, events } = this.game;
    if (player.dead || player.pending || player.casting || player.position.distanceTo(s.from) > 0.6) {
      this.stop();
      return;
    }
    s.t += dt;
    const cfg = CONFIG.fishing;
    const level = waterLevel(s.water);
    const bob = s.bob;
    if (s.phase === 'cast') {
      // the bob arcs out from the rod tip and lands
      const k = Math.min(1, s.t / cfg.castTime);
      bob.position.set(THREE.MathUtils.lerp(s.from.x, s.x, k), THREE.MathUtils.lerp(s.from.y + 2, level, k) + Math.sin(k * Math.PI) * 1.5, THREE.MathUtils.lerp(s.from.z, s.z, k));
      if (k >= 1) {
        s.phase = 'wait';
        s.t = 0;
        events.emit('splash', { x: s.x, y: level, z: s.z, small: true });
      }
    } else if (s.phase === 'wait') {
      bob.position.set(s.x, level + 0.04 + Math.sin(s.t * 2.2) * 0.02, s.z);
      if (s.t >= s.wait) {
        s.phase = 'bite';
        s.t = 0;
        events.emit('splash', { x: s.x, y: level, z: s.z });
        events.emit('fishBite', {});
      }
    } else if (s.phase === 'bite') {
      bob.position.set(s.x, level - 0.06 + Math.sin(s.t * 28) * 0.05, s.z);
      if (s.t >= cfg.biteWindow) {
        events.emit('log', { text: 'The bob rises again. It got away.', kind: 'muted' });
        this.stop();
        return;
      }
    }
    this._drawLine(s, s.phase === 'cast' ? 0.1 : s.phase === 'bite' ? 0.05 : 0.35);
  }

  // the line, from the rod tip to the bob, sagging a little when slack
  _drawLine(s, sag) {
    const a = this.game.player.rodTipPosition(this._tip || (this._tip = new THREE.Vector3()));
    const b = s.bob.position;
    const pos = s.line.geometry.attributes.position;
    const n = pos.count - 1;
    for (let i = 0; i <= n; i++) {
      const k = i / n;
      const droop = Math.sin(k * Math.PI) * sag * a.distanceTo(b) * 0.25;
      pos.setXYZ(i, a.x + (b.x - a.x) * k, a.y + (b.y + 0.08 - a.y) * k - droop, a.z + (b.z - a.z) * k);
    }
    pos.needsUpdate = true;
    s.line.geometry.computeBoundingSphere();
  }

  _makeLine() {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(16 * 3), 3));
    const line = new THREE.Line(geo, new THREE.LineBasicMaterial({ color: 0xd8d2c0, transparent: true, opacity: 0.75 }));
    line.name = 'FishingLine';
    line.frustumCulled = false;
    this.game.scene.add(line);
    return line;
  }

  // the bob's place on screen, for clicking it
  get bobPosition() {
    return this.state ? this.state.bob.position : null;
  }

  _makeBob() {
    const g = new THREE.Group();
    g.name = 'FishingBob';
    const red = new THREE.Mesh(new THREE.SphereGeometry(0.09, 8, 6, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0xc83a2a, emissive: 0x3a0a06 }));
    const white = new THREE.Mesh(new THREE.SphereGeometry(0.09, 8, 6, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0xe8e0d0 }));
    red.position.y = 0.04;
    white.position.y = 0.04;
    g.add(red, white);
    this.game.scene.add(g);
    return g;
  }
}
