import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { heightAt } from '../world/terrain.js';

// The Warden's camp (Set Camp, learned from Old Tam). One camp at a time:
// pitching a new one strikes the old. The camp is where the spirit rises
// after a death, and resting beside it, with no enemy near, builds rested
// experience: kills then pay double until the rested pool is spent, as in WoW.

export class Camp {
  constructor(game) {
    this.game = game;
    this.mesh = null;
    this.light = null;
  }

  // Is anything hostile close enough to stop the Warden making camp?
  get enemiesNear() {
    const p = this.game.player.position;
    return this.game.enemies.list.some((e) => e.alive && (e.engaged > 0 || Math.hypot(e.position.x - p.x, e.position.z - p.z) < CONFIG.camp.clearRadius));
  }

  pitch(x, z) {
    const { worldState, events, hud } = this.game;
    worldState.camp = { x: +x.toFixed(2), z: +z.toFixed(2) };
    worldState.restPoint = 'camp';
    this.show();
    events.emit('campPitched', { x, z });
    events.emit('log', { text: 'You make camp. If you fall, your spirit will rise here.', kind: 'heal' });
    hud?.toast('Camp made');
  }

  // Put the camp's model where the world state says it is (also after a load).
  show() {
    const c = this.game.worldState.camp;
    if (this.mesh) this.game.scene.remove(this.mesh);
    this.mesh = null;
    if (!c) return;
    this.mesh = new THREE.Group();
    this.mesh.name = 'Camp';
    this.mesh.add(this.game.assets.instance('camp'));
    this.light = new THREE.PointLight(0xffa050, 2.2, 9, 1.6);
    this.light.position.set(0, 0.8, 0);
    this.mesh.add(this.light);
    this.mesh.position.set(c.x, heightAt(c.x, c.z), c.z);
    this.game.scene.add(this.mesh);
  }

  get resting() {
    const c = this.game.worldState.camp;
    const { player } = this.game;
    return !!c && !player.dead && Math.hypot(player.position.x - c.x, player.position.z - c.z) <= CONFIG.camp.restRadius && !this.enemiesNear;
  }

  update(dt, time) {
    if (this.light) this.light.intensity = 2.0 + Math.sin(time * 9) * 0.25 + Math.sin(time * 23) * 0.15;
    // rested experience builds while you sit by the fire
    const prog = this.game.progression;
    if (this.resting) {
      const cap = prog.xpToNext * CONFIG.camp.restedCap;
      if (prog.rested < cap) {
        const was = prog.rested;
        prog.rested = Math.min(cap, prog.rested + prog.xpToNext * CONFIG.camp.restedPerSecond * dt);
        if (was === 0) this.game.events.emit('log', { text: 'You rest by the fire. You feel rested.', kind: 'heal', throttle: 'rested' });
      }
    }
  }
}
