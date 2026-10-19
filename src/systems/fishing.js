import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { DB } from '../data/db.js';
import { ITEMS, rollLoot } from '../data/items.js';
import { waterAt, waterLevel } from '../world/terrain.js';

// Fishing, WoW style. With the Fishing skill (from Old Tam) and a rod in the
// bags, the Fishing ability casts a bob into the water you face, and the
// fishing bar runs for `duration` seconds. Whether anything bites is rolled
// at the cast: the chance rises with your fishing skill, which is your rank
// plus your best rod's `fishingSkill` plus bait's (`bait`, one used per
// cast). If something bites, the bob dips at some moment in the cast: strike
// then (click the bob, or E / A) for a chance to land a fish from that
// water's loot table (data: world.json `water` `fishTable`). Too soon or too
// late and it gets away; if the bar runs out with no bite, nothing was
// biting. Fish are never seen in the water. As in WoW and RuneScape, skill
// comes only from a real attempt: landing something (fish or junk) or a
// strike on a real bite that slips the hook. Reeling in, striking before the
// bite, letting the bite pass or an empty cast teach nothing (Dan,
// 2026-10-19). Any rod
// (an item with `rod: true`) will do, in the bags or the tool pack.
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
    if (!this.hasRod) return say('You need a fishing rod in your bags.', 'fish-rod'), false;
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
    // bait goes on the hook now, and counts for this cast
    const bait = this._bait();
    const skill = this.skill;
    if (bait) inventory.removeCount(bait, 1);
    const bites = this.game.random() * 100 < this.biteChanceFor(skill);
    const wait = bites ? cfg.biteMin + (cfg.biteMax - cfg.biteMin) * this.game.random() : Infinity;
    this.state = { phase: 'cast', t: 0, elapsed: 0, wait, skill, x: spot.x, z: spot.z, water, bob: this._makeBob(), line: this._makeLine(), from: p.clone() };
    events.emit('fishCast', { x: spot.x, z: spot.z });
    return true;
  }

  // any rod carried
  get hasRod() {
    const inv = this.game.inventory;
    return Object.keys(ITEMS).some((id) => ITEMS[id].rod && inv.count(id) > 0);
  }

  // Fishing skill: rank, plus the best rod in your bags, plus bait if you
  // have some (it is used up when you cast)
  get skill() {
    const inv = this.game.inventory;
    const rod = Math.max(0, ...Object.keys(ITEMS).filter((id) => ITEMS[id].rod && ITEMS[id].fishingSkill && inv.count(id) > 0).map((id) => ITEMS[id].fishingSkill));
    const bait = this._bait();
    return this.game.skills.rank('fishing') + rod + (bait ? ITEMS[bait].bait : 0);
  }

  // percent chance that a cast gets a bite
  biteChanceFor(skill = this.skill) {
    const cfg = CONFIG.fishing;
    return Math.min(cfg.biteCap, cfg.biteBase + skill * cfg.bitePerSkill);
  }

  // The catch chance in percent for a timely strike.
  get chance() {
    const cfg = CONFIG.fishing;
    return Math.min(100, cfg.baseChance + (this.state?.skill ?? this.skill) * cfg.chancePerRank);
  }

  // the best bait in your bags
  _bait() {
    const inv = this.game.inventory;
    const have = Object.keys(ITEMS).filter((id) => ITEMS[id].bait && inv.count(id) > 0);
    return have.sort((a, b) => ITEMS[b].bait - ITEMS[a].bait)[0] || null;
  }

  // the fishing bar: { t, total }
  get bar() {
    return this.state ? { t: this.state.elapsed, total: CONFIG.fishing.duration } : null;
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
    if (this.game.random() * 100 >= this.chance) {
      events.emit('log', { text: 'The fish slips the hook.', kind: 'muted' });
      this._practice();
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

  // a strike on a real bite that slips the hook still teaches you something
  _practice() {
    this.game.skills.raise('fishing');
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
    s.elapsed += dt;
    const cfg = CONFIG.fishing;
    // the fishing bar has run out with nothing on the line
    if (s.elapsed >= cfg.duration && s.phase !== 'bite') {
      events.emit('log', { text: 'Nothing is biting. You reel in your line.', kind: 'muted' });
      this.game.hud?.error?.('Nothing is biting');
      this.stop();
      return;
    }
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
