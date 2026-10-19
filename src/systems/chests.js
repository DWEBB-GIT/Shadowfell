import * as THREE from 'three';
import { DB } from '../data/db.js';
import { ITEMS } from '../data/items.js';
import { heightAt } from '../world/terrain.js';


// Chests in the world (data/world.json `chests`). Walk up and open one (E,
// or click it): what it holds goes into your bags (onto the ground beside
// it if they are full) and its silver into your purse. A chest with a
// `lock` needs its key in your bags, or Lockpicking of at least `pick`
// (taught by Old Tam) and a set of lockpicks; each lock picked raises the
// skill. Opened chests stay open: the world state remembers them.

const REACH = 2.4;

export class Chests {
  constructor(game) {
    this.game = game;
    this.list = (DB.world.chests || []).map((def) => ({ def, x: def.position[0], z: def.position[1], group: null }));
  }

  spawnAll() {
    const { scene, assets, collision } = this.game;
    for (const c of this.list) {
      if (c.group) scene.remove(c.group);
      c.group = new THREE.Group();
      c.group.add(assets.instance('chest'));
      c.group.position.set(c.x, heightAt(c.x, c.z), c.z);
      c.group.rotation.y = ((c.def.facing || 0) * Math.PI) / 180;
      scene.add(c.group);
      if (!c.collider) collision.add(c.x, c.z, 0.45);
      c.collider = true;
      this._look(c);
    }
  }

  opened(c) {
    return this.game.worldState.isCollected('chest:' + c.def.id);
  }

  // an opened chest is shown open: tipped lid colour, darker
  _look(c) {
    const open = this.opened(c);
    c.group.traverse((o) => {
      if (o.isMesh) {
        o.material = o.material.clone();
        o.material.color.multiplyScalar(open ? 0.55 : 1);
      }
    });
  }

  // what stops this chest opening: null, or { text, error }
  _lockState(c) {
    const lock = c.def.lock;
    if (!lock) return null;
    const { inventory, skills } = this.game;
    if (lock.key && inventory.count(lock.key) > 0) return null;
    if (lock.pick && skills.has('lockpicking') && skills.rank('lockpicking') >= lock.pick && inventory.count('lockpicks') > 0) return null;
    const ways = [];
    if (lock.key) ways.push(`the ${ITEMS[lock.key].name}`);
    if (lock.pick) ways.push(`Lockpicking ${lock.pick} and lockpicks`);
    return { error: `It's locked. You need ${ways.join(' or ')}.` };
  }

  interactions() {
    const out = [];
    for (const c of this.list) {
      if (this.opened(c)) continue;
      const lock = c.def.lock;
      const blocked = this._lockState(c);
      let prompt = `Open the ${c.def.name}`;
      if (lock && !blocked) prompt = lock.key && this.game.inventory.count(lock.key) > 0 ? `Unlock the ${c.def.name} (${ITEMS[lock.key].name})` : `Pick the lock (Lockpicking ${lock.pick})`;
      if (blocked) prompt = `${c.def.name} (locked)`;
      out.push({ key: 'chest:' + c.def.id, x: c.x, z: c.z, bias: -0.2, reach: REACH, prompt, chest: c, run: () => this.open(c) });
    }
    return out;
  }

  open(c) {
    const { worldState, inventory, events, hud, skills, loot } = this.game;
    if (this.opened(c)) return false;
    const blocked = this._lockState(c);
    if (blocked) {
      hud.error(blocked.error);
      return false;
    }
    const lock = c.def.lock;
    if (lock && !(lock.key && inventory.count(lock.key) > 0)) {
      events.emit('log', { text: `You pick the lock of the ${c.def.name}.`, kind: 'level' });
      skills.raise('lockpicking');
    }
    worldState.markCollected('chest:' + c.def.id);
    for (const it of c.def.items || []) {
      if (!inventory.addItem(it.id, it.count || 1)) loot.dropAt({ id: it.id, count: it.count || 1 }, { x: c.x + 0.9, z: c.z + 0.4 });
    }
    if (c.def.coins) inventory.addCoins(c.def.coins, `in the ${c.def.name}`);
    events.emit('log', { text: `You open the ${c.def.name}.`, kind: 'loot' });
    events.emit('chestOpened', { id: c.def.id });
    this._look(c);
    return true;
  }

  near(x, z) {
    return this.list.find((c) => Math.hypot(c.x - x, c.z - z) < 1.2) || null;
  }
}

