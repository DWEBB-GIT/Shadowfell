import { Enemy } from '../entities/enemy.js';
import { ENEMIES } from '../world/layout.js';
import { heightAt } from '../world/terrain.js';

// Spawns and updates the region's enemies. A defeat lives in the world state
// and is saved; enemies whose type has a `respawn` time (enemies.json) come
// back at their spawn point once it has passed, WoW style, so the Warden
// can grind them. Those with 0 (bosses, story enemies) stay dead.

export class EnemyManager {
  constructor(game) {
    this.game = game;
    this.list = [];
  }

  spawnAll() {
    this.clear();
    const ws = this.game.worldState;
    for (const spawn of ENEMIES) {
      const corpse = ws.corpses[spawn.id];
      if (ws.isDefeated(spawn.id) && !corpse) continue;
      const e = new Enemy(this.game, spawn);
      if (ws.isDefeated(spawn.id)) {
        // a body from a saved game, still waiting to be looted
        e.position.set(corpse.x, heightAt(corpse.x, corpse.z), corpse.z);
        e.dead = true;
        e.health = 0;
        e.state = 'dead';
        e.corpse = true;
        e.rig.die();
        e.rig.death = 2.0;
        e._sync();
      }
      this.list.push(e);
      this.game.scene.add(e.group);
    }
  }

  clear() {
    for (const e of this.list) {
      this.game.scene.remove(e.group);
      e.materials.forEach((m) => m.dispose());
    }
    this.list = [];
  }

  byId(id) {
    return this.list.find((e) => e.id === id);
  }

  resetSurvivors() {
    for (const e of this.list) e.reset();
  }

  update(dt) {
    const player = this.game.player;
    this._respawn(dt);
    for (const e of this.list) e.update(dt, player);
    this._separate();
    // a body with loot stays down until looted; then it sinks away
    for (const e of [...this.list]) {
      if (e.dead && e.corpse && e.rig.death > 2.0) e.rig.death = 2.0;
      if (e.dead && !e.corpse && e.rig.death > 5.5) {
        this.game.scene.remove(e.group);
        e.materials.forEach((m) => m.dispose());
        this.list.splice(this.list.indexOf(e), 1);
      }
    }
  }

  _respawn(dt) {
    const ws = this.game.worldState;
    ws.time += dt;
    for (const [id, at] of Object.entries(ws.respawnAt)) {
      if (ws.time < at) continue;
      delete ws.respawnAt[id];
      const spawn = ENEMIES.find((s) => s.id === id);
      if (!spawn) continue;
      // an unlooted body goes when its enemy comes back
      const old = this.byId(id);
      if (old) {
        this.game.scene.remove(old.group);
        old.materials.forEach((m) => m.dispose());
        this.list.splice(this.list.indexOf(old), 1);
      }
      delete ws.corpses[id];
      ws.defeated.delete(id);
      const e = new Enemy(this.game, spawn);
      this.list.push(e);
      this.game.scene.add(e.group);
      this.game.events.emit('enemyRespawned', { enemy: e });
    }
  }

  _separate() {
    const player = this.game.player;
    const living = this.list.filter((e) => e.alive);
    for (let i = 0; i < living.length; i++) {
      const a = living[i];
      for (let j = i + 1; j < living.length; j++) {
        pushApart(a.position, a.radius, living[j].position, living[j].radius, 0.5);
      }
      if (!player.dead) pushApart(player.position, player.radius, a.position, a.radius, 0.85);
    }
  }
}

// Move two circles apart; `bias` is the share of the correction given to b.
function pushApart(pa, ra, pb, rb, bias) {
  const dx = pb.x - pa.x;
  const dz = pb.z - pa.z;
  const min = ra + rb;
  const d2 = dx * dx + dz * dz;
  if (d2 >= min * min || d2 === 0) return;
  const d = Math.sqrt(d2);
  const push = min - d;
  pa.x -= (dx / d) * push * (1 - bias);
  pa.z -= (dz / d) * push * (1 - bias);
  pb.x += (dx / d) * push * bias;
  pb.z += (dz / d) * push * bias;
}
