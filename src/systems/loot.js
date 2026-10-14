import * as THREE from 'three';
import { LOOT, UNIQUE_DROPS, ITEMS, itemView, rollItem } from '../data/items.js';
import { DB } from '../data/db.js';
import { heightAt } from '../world/terrain.js';
import { CONFIG } from '../config.js';

// Loot represented in the world. Collected loot is removed from the scene and
// recorded in the world state so it never reappears.
//
// Items the player drops (RuneScape style) become ground items: they stay
// where they fell, are saved with the world, and can be picked up again.
//
// Defeated enemies leave a body holding their coins. Looting anything (a
// click on it, or E / A beside it) also loots every body and drop within
// CONFIG.loot.areaRadius, so a pack of kills is cleared in one go.

export class LootSystem {
  constructor(game) {
    this.game = game;
    this.active = []; // { def, x, z, group, glint, baseY }
  }

  spawnAll() {
    this.clear();
    const ws = this.game.worldState;
    for (const def of LOOT) {
      if (!ws.isCollected(def.id)) this._spawn(def, def.position[0], def.position[1]);
    }
    for (const [id, pos] of Object.entries(ws.drops)) {
      if (UNIQUE_DROPS[id] && !ws.isCollected(id)) this._spawn(UNIQUE_DROPS[id], pos.x, pos.z);
    }
    for (const g of ws.ground) this._spawnGround(g);
  }

  _groundDef(g) {
    const item = ITEMS[g.id];
    return {
      id: 'ground:' + g.uid,
      ground: g,
      model: item.model,
      prompt: `Pick up ${itemView(g).name}${g.count > 1 ? ` ×${g.count}` : ''}`,
      reward: { item: g.id, count: g.count, rolls: g.rolls || null },
    };
  }

  _spawnGround(g) {
    const entry = this._spawn(this._groundDef(g), g.x, g.z);
    entry.group.rotation.y = g.uid * 2.39;
    return entry;
  }

  // Drop the stack at an inventory location at the player's feet.
  dropFromInventory(loc) {
    const { inventory, player, worldState, events, collision } = this.game;
    if (player.dead) return null;
    const stack = inventory.get(loc);
    if (!stack) return null;
    if (ITEMS[stack.id].quest) {
      events.emit('log', { text: `You keep hold of the ${ITEMS[stack.id].name}. Someone will want it.`, kind: 'muted', throttle: 'inv-refuse' });
      return null;
    }
    const taken = inventory.take(loc);
    if (!taken) {
      events.emit('log', { text: 'Empty that bag before dropping it.', kind: 'muted', throttle: 'inv-refuse' });
      return null;
    }
    // scatter drops a little in front of the player so they don't stack exactly
    const n = worldState.ground.length;
    const a = player.facing + ((n % 5) - 2) * 0.5;
    const pos = { x: player.position.x + Math.sin(a) * 0.9, z: player.position.z + Math.cos(a) * 0.9 };
    collision.resolve(pos, 0.2);
    const g = this._addGround(taken, pos);
    const entry = this._spawnGround(g);
    events.emit('itemDropped', { item: g });
    events.emit('log', { text: `Dropped: ${itemView(g).name}${g.count > 1 ? ` ×${g.count}` : ''}.`, kind: 'muted' });
    return entry;
  }

  _addGround(stack, pos) {
    const ws = this.game.worldState;
    const g = { uid: ws.nextGroundUid++, id: stack.id, count: stack.count, x: +pos.x.toFixed(2), z: +pos.z.toFixed(2) };
    if (stack.rolls) g.rolls = stack.rolls;
    ws.ground.push(g);
    return g;
  }

  // Gear and materials an enemy drops, from its table in data/drops.json.
  // Gear rolls its stats as it drops. Drops lie beside the body and are
  // saved like anything else on the ground, so they wait to be looted.
  dropFromEnemy(enemy) {
    const table = DB.lootTables[enemy.cfg.lootTable];
    if (!table) return [];
    const rand = this.game.random;
    const out = [];
    const place = (id, count) => {
      const a = out.length * 2.1 + enemy.facing;
      const pos = { x: enemy.position.x + Math.sin(a) * 0.8, z: enemy.position.z + Math.cos(a) * 0.8 };
      this.game.collision.resolve(pos, 0.2);
      const rolls = rollItem(id, rand);
      const g = this._addGround(rolls ? { id, count, rolls } : { id, count }, pos);
      this._spawnGround(g);
      out.push(g);
    };
    for (const { item, min, max } of table.always || []) {
      const n = min + Math.floor(rand() * (max - min + 1));
      if (n > 0) place(item, n);
    }
    if (table.gear && rand() < table.gear.chance) {
      const entries = table.gear.entries;
      let pick = rand() * entries.reduce((a, e) => a + e.weight, 0);
      const hit = entries.find((e) => (pick -= e.weight) < 0) || entries[entries.length - 1];
      place(hit.item, 1);
    }
    for (const g of out) {
      const v = itemView(g);
      if (ITEMS[g.id].kind !== 'material') this.game.events.emit('log', { text: `The ${enemy.cfg.name} drops ${/^[aeiou]/i.test(v.name) ? 'an' : 'a'} ${v.name}.`, kind: 'loot' });
    }
    return out;
  }

  clear() {
    for (const l of this.active) this.game.scene.remove(l.group);
    this.active = [];
  }

  _spawn(def, x, z) {
    const group = new THREE.Group();
    const model = this.game.assets.instance(def.model);
    if (['watchmans_edge', 'worn_sword', 'rusted_falchion', 'blackwood_cleaver'].includes(def.model)) {
      model.rotation.set(Math.PI / 2, 0, 0.6); // lying on the ground
      model.position.y = 0.06;
    }
    if (def.model === 'kite_shield' || def.model === 'iron_shield') {
      model.rotation.set(-Math.PI / 2 + 0.12, 0, 0.4); // lying face up
      model.position.y = 0.05;
    }
    group.add(model);
    const glint = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: this.game.textures.glint, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.6 }),
    );
    glint.scale.setScalar(0.7);
    glint.position.y = 0.35;
    group.add(glint);
    const baseY = heightAt(x, z) + (def.heightOffset || 0);
    group.position.set(x, baseY, z);
    group.rotation.y = (x * 13.7 + z * 7.1) % (Math.PI * 2);
    this.game.scene.add(group);
    const entry = { def, x, z, group, glint, baseY, seed: Math.random() * 6 };
    this.active.push(entry);
    return entry;
  }

  // ------------------------------------------------------------ corpses
  addCorpse(enemy, coins) {
    const ws = this.game.worldState;
    ws.corpses[enemy.id] = { x: +enemy.position.x.toFixed(2), z: +enemy.position.z.toFixed(2), coins };
    enemy.corpse = true;
  }

  // Everything that can be looted right now: bodies and loot in the world.
  lootables() {
    const { worldState, enemies } = this.game;
    const out = [];
    for (const [id, c] of Object.entries(worldState.corpses)) {
      const e = enemies.byId(id);
      out.push({ kind: 'corpse', id, x: c.x, z: c.z, name: e ? e.cfg.name : 'body', coins: c.coins });
    }
    // only what fell in a fight (or was dropped) is area-looted; things placed
    // in the world, like the manifest, are taken one at a time
    for (const l of this.active) out.push({ kind: 'item', id: l.def.id, x: l.x, z: l.z, entry: l, area: !!(l.def.ground || UNIQUE_DROPS[l.def.id] === l.def) });
    return out;
  }

  _area(origin) {
    const r = CONFIG.loot.areaRadius;
    const all = this.lootables();
    const self = all.filter((l) => l.id === origin.id);
    if (origin.kind === 'item' && !origin.area) return self;
    return self.concat(all.filter((l) => l.id !== origin.id && (l.kind === 'corpse' || l.area) && Math.hypot(l.x - origin.x, l.z - origin.z) <= r));
  }

  // Loot `origin` and everything else lootable within the area radius of it.
  lootArea(origin) {
    const list = this._area(origin);
    let n = 0;
    for (const l of list) if (l.kind === 'corpse' ? this.lootCorpse(l.id) : this.collect(l.entry)) n++;
    if (n > 1) this.game.events.emit('log', { text: `You loot ${n} things nearby.`, kind: 'loot' });
    return n;
  }

  // How many things a loot at `origin` would take (for the prompt).
  areaCount(origin) {
    return this._area(origin).length;
  }

  lootCorpse(id) {
    const { worldState, inventory, enemies, events } = this.game;
    const c = worldState.corpses[id];
    if (!c) return false;
    delete worldState.corpses[id];
    const e = enemies.byId(id);
    if (c.coins > 0) inventory.addCoins(c.coins, `from the ${e ? e.cfg.name : 'body'}`);
    if (e) {
      e.corpse = false; // the body can now sink away
      e.rig.death = Math.max(e.rig.death, 2.5);
    }
    events.emit('corpseLooted', { id });
    return true;
  }

  // An enemy's unique drop (data/enemies.json uniqueDrop), left once where it fell.
  dropUnique(enemy) {
    const ws = this.game.worldState;
    const def = UNIQUE_DROPS[enemy.cfg.uniqueDrop];
    if (!def || ws.isCollected(def.id) || ws.drops[def.id]) return;
    const { x, z } = enemy.position;
    ws.drops[def.id] = { x, z };
    this._spawn(def, x, z);
    this.game.events.emit('log', { text: `Something glints where the ${def.droppedBy} fell.`, kind: 'loot' });
  }


  collect(entry) {
    const { worldState, inventory, events, hud } = this.game;
    const def = entry.def;
    if (!def.ground && worldState.isCollected(def.id)) return false;
    const r = def.reward;
    // a full bag leaves the item where it lies
    if (r.item && !inventory.addItem(r.item, r.count || 1, { rolls: r.rolls || null })) return false;
    if (r.coins) inventory.addCoins(r.coins, 'in a purse');
    if (def.ground) worldState.ground.splice(worldState.ground.indexOf(def.ground), 1);
    else worldState.markCollected(def.id);
    this.game.scene.remove(entry.group);
    entry.group.traverse((o) => {
      if (o.isSprite) o.material.dispose();
    });
    this.active.splice(this.active.indexOf(entry), 1);
    events.emit('lootCollected', { id: def.id });
    if (def.opensDocument && !def.ground) {
      hud.openDocument(def.opensDocument);
      events.emit('objectiveChanged', {});
    }
    return true;
  }

  update(dt, time) {
    for (const l of this.active) {
      const pulse = 0.45 + Math.sin(time * 2.2 + l.seed) * 0.2;
      l.glint.material.opacity = pulse;
      l.glint.position.y = 0.3 + Math.sin(time * 1.5 + l.seed) * 0.05;
    }
  }

  describe(entry) {
    const r = entry.def.reward;
    return r.item ? itemView({ id: r.item, rolls: r.rolls }).name : undefined;
  }
}
