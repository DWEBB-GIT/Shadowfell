import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { NPCS } from '../world/layout.js';
import { Rig } from '../entities/rig.js';
import { heightAt } from '../world/terrain.js';
import { conditionHolds } from './quests.js';

// Townsfolk. Each NPC stands at its post, works (Mara hammers at her anvil)
// and turns to face the Warden when they come close. Talking to one opens a
// conversation (src/systems/dialogue.js), which leads to quests and the shop.
// A spawn with `goneWhen` (a dialogue condition, such as a story flag) is
// absent while it holds: the world shows what the Warden's choices did.

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
    // townsfolk who share a model are told apart by a tint
    if (def.tint) for (const m of Rig.isolateMaterials(this.model)) m.color.multiply(new THREE.Color(def.tint));
    this.board = !!def.board; // a notice board: never turns or works
    this.workTimer = 1 + Math.random();
    this.group.position.copy(this.position);
    this.collider = game.collision.add(this.position.x, this.position.z, this.radius);
    this.present = true;
  }

  // Is this person here, given the story so far?
  updatePresence() {
    const here = !this.def.goneWhen || !conditionHolds(this.game, this.def.goneWhen);
    if (here === this.present) return;
    this.present = here;
    this.group.visible = here;
    this.collider.off = !here;
  }

  update(dt, player) {
    const dx = player.position.x - this.position.x;
    const dz = player.position.z - this.position.z;
    const near = Math.hypot(dx, dz) < 4.5 && !player.dead;
    const want = this.board ? this.restFacing : near ? Math.atan2(dx, dz) : this.def.anvil ? Math.atan2(this.def.anvil[0] - this.position.x, this.def.anvil[1] - this.position.z) : this.restFacing;
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
    this.all = NPCS.map((d) => new Npc(game, d));
    for (const n of this.all) game.scene.add(n.group);
  }

  // the townsfolk who are here now
  get list() {
    return this.all.filter((n) => n.present);
  }

  byId(id) {
    return this.list.find((n) => n.id === id) || null;
  }

  update(dt) {
    for (const n of this.all) n.updatePresence();
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
    // a notice board stays as it was put up; people turn to you
    if (!n.board) n.facing = Math.atan2(this.game.player.position.x - n.position.x, this.game.player.position.z - n.position.z);
    this.game.dialogue.open(n);
  }
}
