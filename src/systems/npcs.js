import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { NPCS } from '../world/layout.js';
import { Rig } from '../entities/rig.js';
import { heightAt } from '../world/terrain.js';

// Townsfolk. Each NPC stands at its post, works (Mara hammers at her anvil)
// and turns to face the Warden when they come close. Talking to one with a
// `merchant` entry opens that merchant's shop.

const DEG = Math.PI / 180;

class Npc {
  constructor(game, def) {
    this.game = game;
    this.def = def;
    this.id = def.id;
    this.name = def.name;
    this.position = new THREE.Vector3(def.position[0], 0, def.position[1]);
    this.position.y = heightAt(this.position.x, this.position.z);
    this.restFacing = def.facing * DEG;
    this.facing = this.restFacing;
    this.radius = 0.4;
    this.group = new THREE.Group();
    this.group.name = 'Npc_' + def.id;
    this.model = game.assets.instance(def.model);
    this.group.add(this.model);
    this.rig = new Rig(this.model, 'warden');
    this.workTimer = 1 + Math.random();
    this.group.position.copy(this.position);
    game.collision.add(this.position.x, this.position.z, this.radius);
  }

  update(dt, player) {
    const dx = player.position.x - this.position.x;
    const dz = player.position.z - this.position.z;
    const near = Math.hypot(dx, dz) < 4.5 && !player.dead;
    const want = near ? Math.atan2(dx, dz) : this.def.anvil ? Math.atan2(this.def.anvil[0] - this.position.x, this.def.anvil[1] - this.position.z) : this.restFacing;
    let d = want - this.facing;
    d = Math.atan2(Math.sin(d), Math.cos(d));
    this.facing += d * Math.min(1, dt * 5);
    // at work: a hammer blow every so often, unless someone wants a word
    if (this.def.anvil && !near) {
      this.workTimer -= dt;
      if (this.workTimer <= 0) {
        this.workTimer = 1.5 + Math.random() * 0.8;
        this.rig.play('strike', 0.6, 0.45);
        this.game.events.emit('anvilStrike', { npc: this, x: this.def.anvil[0], z: this.def.anvil[1] });
      }
    }
    this.rig.update(dt, 0);
    this.group.position.copy(this.position);
    this.group.rotation.y = this.facing;
  }
}

export class NpcManager {
  constructor(game) {
    this.game = game;
    this.list = NPCS.map((d) => new Npc(game, d));
    for (const n of this.list) game.scene.add(n.group);
  }

  byId(id) {
    return this.list.find((n) => n.id === id) || null;
  }

  update(dt) {
    for (const n of this.list) n.update(dt, this.game.player);
  }

  // what the interaction system offers for each NPC
  interactions() {
    return this.list.map((n) => ({
      key: 'npc:' + n.id,
      x: n.position.x,
      z: n.position.z,
      bias: -0.6, // people come before props
      reach: CONFIG.shop.talkRange,
      prompt: `Talk to ${n.name}`,
      run: () => this.talk(n),
    }));
  }

  talk(n) {
    n.facing = Math.atan2(this.game.player.position.x - n.position.x, this.game.player.position.z - n.position.z);
    if (n.def.merchant) this.game.merchant.open(n.def.merchant, n);
  }
}
