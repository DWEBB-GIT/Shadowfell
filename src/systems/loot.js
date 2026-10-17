import * as THREE from 'three';
import { LOOT, UNIQUE_DROPS, ITEMS, RARITY, itemView, rollItem, rollLoot } from '../data/items.js';
import { DB } from '../data/db.js';
import { heightAt } from '../world/terrain.js';
import { CONFIG } from '../config.js';
import { AMMO_LOC } from './inventory.js';

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
    this.regrow = []; // { def, at }: gathering nodes waiting to respawn
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
    if (!stack || loc === AMMO_LOC) return null; // the ammo slot only names arrows
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

  // Leave a stack on the ground at a point (a chest's overflow).
  dropAt(stack, pos) {
    this.game.collision.resolve(pos, 0.2);
    return this._spawnGround(this._addGround(stack, pos));
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
  // Roll the enemy's loot table (rarity first, then the item) and lay what
  // drops around the body.
  dropFromEnemy(enemy) {
    const rand = this.game.random;
    const out = [];
    for (const { id, count, rarity } of rollLoot(DB.lootTables[enemy.cfg.lootTable], rand)) {
      const a = out.length * 2.1 + enemy.facing;
      const pos = { x: enemy.position.x + Math.sin(a) * 0.8, z: enemy.position.z + Math.cos(a) * 0.8 };
      this.game.collision.resolve(pos, 0.2);
      const rolls = rollItem(id, rand, rarity);
      const g = this._addGround(rolls ? { id, count, rolls } : { id, count }, pos);
      this._spawnGround(g);
      out.push(g);
    }
    for (const g of out) {
      const v = itemView(g);
      if (ITEMS[g.id].kind === 'material') continue;
      const tag = v.rarity === 'common' || v.rarity === 'junk' ? '' : ` (${RARITY[v.rarity].name})`;
      this.game.events.emit('log', { text: `The ${enemy.cfg.name} drops ${/^[aeiou]/i.test(v.name) ? 'an' : 'a'} ${v.name}${tag}.`, kind: 'loot', rarity: v.rarity });
    }
    return out;
  }

  clear() {
    for (const l of this.active) this.game.scene.remove(l.group);
    this.active = [];
    this.regrow = [];
  }

  _spawn(def, x, z) {
    const group = new THREE.Group();
    const model = this.game.assets.instance(def.model);
    if (def.scale) model.scale.multiplyScalar(def.scale);
    if (def.kind === 'weapon') {
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
    // gear above common glints in its rarity's colour, and rare and better glint brighter
    const item = def.reward && def.reward.item;
    if (item && ITEMS[item]) {
      const rarity = itemView({ id: item, rolls: def.ground ? def.ground.rolls : null }).rarity;
      if (!['junk', 'common', 'quest'].includes(rarity)) glint.material.color.set(RARITY[rarity].colour);
      if (['rare', 'epic', 'legendary'].includes(rarity)) glint.scale.setScalar(1.1);
    }
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
  // A gathering node tied to a quest (`quest`) can only be taken, and only
  // sparkles, while that quest is active and still needs its item.
  gatherable(def) {
    if (!def.quest) return true;
    const q = this.game.quests;
    if (q.status(def.quest) !== 'active') return false;
    return q.objectives(def.quest).some((o) => !o.done && o.type === 'collect' && DB.quests[def.quest].objectives.find((d) => d.id === o.id).target === def.reward.item);
  }

  lootables() {
    const { worldState, enemies } = this.game;
    const out = [];
    for (const [id, c] of Object.entries(worldState.corpses)) {
      const e = enemies.byId(id);
      out.push({ kind: 'corpse', id, x: c.x, z: c.z, name: e ? e.cfg.name : 'body', coins: c.coins });
    }
    // only what fell in a fight (or was dropped) is area-looted; things placed
    // in the world, like the manifest, are taken one at a time
    for (const l of this.active) if (this.gatherable(l.def)) out.push({ kind: 'item', id: l.def.id, x: l.x, z: l.z, entry: l, area: !!(l.def.ground || UNIQUE_DROPS[l.def.id] === l.def) });
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
    if (!this.gatherable(def)) return false;
    const r = def.reward;
    // a full bag leaves the item where it lies
    if (r.item && !inventory.addItem(r.item, r.count || 1, { rolls: r.rolls || null })) return false;
    if (r.coins) inventory.addCoins(r.coins, 'in a purse');
    if (def.ground) worldState.ground.splice(worldState.ground.indexOf(def.ground), 1);
    else if (def.respawn) this.regrow.push({ def, at: this.game.time + def.respawn }); // a gathering node grows back
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
    for (let i = this.regrow.length - 1; i >= 0; i--) {
      const r = this.regrow[i];
      if (time < r.at) continue;
      this.regrow.splice(i, 1);
      this._spawn(r.def, r.def.position[0], r.def.position[1]);
    }
    for (const l of this.active) {
      if (l.def.quest) l.glint.visible = this.gatherable(l.def);
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
