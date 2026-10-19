import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { heightAt } from '../world/terrain.js';

// The Warden's camp (Set Camp, learned from Old Tam). One camp at a time:
// pitching a new one strikes the old. The camp is where the spirit rises
// after a death, and resting beside it, with no enemy near, builds rested
// experience: kills then pay double until the rested pool is spent, as in WoW.
// A faint ring on the ground shows how close you must stay to rest
// (`CONFIG.camp.restRadius`); it glows brighter while you rest.

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
    this.mesh = this.ring = null;
    if (!c) return;
    this.mesh = new THREE.Group();
    this.mesh.name = 'Camp';
    this.mesh.add(this.game.assets.instance('camp'));
    this.light = new THREE.PointLight(0xffa050, 2.2, 9, 1.6);
    this.light.position.set(0, 0.8, 0);
    this.mesh.add(this.light);
    this.mesh.position.set(c.x, heightAt(c.x, c.z), c.z);
    this.mesh.add((this.ring = this._ring(c)));
    this.game.scene.add(this.mesh);
  }

  // the rest circle: a thin band laid over the ground around the fire
  _ring(c) {
    const r = CONFIG.camp.restRadius;
    const geo = new THREE.RingGeometry(r - 0.07, r + 0.07, 72, 1);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    const base = heightAt(c.x, c.z);
    for (let i = 0; i < pos.count; i++) pos.setY(i, heightAt(c.x + pos.getX(i), c.z + pos.getZ(i)) - base + 0.06);
    const mat = new THREE.MeshBasicMaterial({ color: 0xffb060, transparent: true, opacity: 0.35, depthWrite: false, side: THREE.DoubleSide });
    const m = new THREE.Mesh(geo, mat);
    m.name = 'CampRestRing';
    m.renderOrder = 2;
    return m;
  }

  // 'camp' by your fire, 'inn' under an inn's roof (no enemy near), else null
  get resting() {
    const c = this.game.worldState.camp;
    const { player, world } = this.game;
    if (player.dead || this.enemiesNear) return null;
    if (world?.indoors?.def.rest) return 'inn';
    return c && Math.hypot(player.position.x - c.x, player.position.z - c.z) <= CONFIG.camp.restRadius ? 'camp' : null;
  }

  update(dt, time) {
    if (this.light) this.light.intensity = 2.0 + Math.sin(time * 9) * 0.25 + Math.sin(time * 23) * 0.15;
    // rested experience builds while you sit by the fire
    const prog = this.game.progression;
    const where = this.resting;
    if (this.ring) this.ring.material.opacity = where === 'camp' ? 0.6 + Math.sin(time * 3) * 0.1 : 0.3;
    if (where) {
      const cap = prog.xpToNext * CONFIG.camp.restedCap;
      if (prog.rested < cap) {
        const was = prog.rested;
        prog.rested = Math.min(cap, prog.rested + prog.xpToNext * CONFIG.camp.restedPerSecond * dt);
        if (was === 0) {
          const text = where === 'inn' ? 'You rest at the inn. You feel rested.' : 'You rest by the fire. You feel rested.';
          this.game.events.emit('log', { text, kind: 'heal', throttle: 'rested' });
        }
      }
    }
  }
}
