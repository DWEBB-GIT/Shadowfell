import { CONFIG } from '../config.js';
import { SHRINES, PLAYER_START, BUILDINGS } from '../world/layout.js';
import { heightAt } from '../world/terrain.js';
import { moneyText } from '../ui/money.js';

// Death, WoW style. When the Warrior falls, their body stays where it fell and
// their spirit rises at the last place they rested: their camp, or the last
// shrine. From there the ghost (fast, unseen by enemies, unable to fight) can
// either run back to the body and rise there for free, or return to life at
// once where it stands, a few coins lighter.
//
// The enemy that killed the Warrior is remembered (`worldState.nemesis`): it
// carries a skull over its head and on the minimap, the Warrior deals extra
// damage to it, and killing it pays a revenge bonus.

export class Afterlife {
  constructor(game) {
    this.game = game;
    this.ghost = false;
    this.corpse = null; // { x, z, mesh }
    this.coinLoss = 0;
  }

  // ------------------------------------------------------------- rest point
  // Where the spirit rises: the camp or shrine rested at last, else the road's start.
  restPoint() {
    const ws = this.game.worldState;
    if (ws.restPoint === 'camp' && ws.camp) return { x: ws.camp.x + 1.4, z: ws.camp.z, label: 'by your camp', kind: 'camp' };
    // an inn you made your home: you wake by its hearth
    const inn = ws.restPoint?.startsWith('inn:') && BUILDINGS.find((b) => b.rest);
    if (inn) return { x: inn.position[0] + inn.light[0] + 1.2, z: inn.position[1] + inn.light[1] + 1.4, label: `at ${inn.name}`, kind: 'inn' };
    const sh = SHRINES.find((x) => x.id === ws.shrineActivated) || SHRINES[0];
    if (ws.respawn) return { x: ws.respawn.x, z: ws.respawn.z, label: sh.label, kind: 'shrine' };
    return { x: PLAYER_START.position[0], z: PLAYER_START.position[1], label: "at the road's end", kind: 'start' };
  }

  // --------------------------------------------------------------- dying
  onDeath(killer, coinLoss) {
    const ws = this.game.worldState;
    this.coinLoss = coinLoss;
    // dying wears your gear, as in WoW
    this.game.inventory.wear(CONFIG.durability.deathLoss);
    this.game.events.emit('log', { text: `Your equipment is damaged (−${CONFIG.durability.deathLoss}% durability).`, kind: 'muted' });
    if (killer && killer.alive && killer.id) {
      ws.nemesis = killer.id;
      this.game.events.emit('log', { text: `The ${killer.cfg.name} will remember this. So will you.`, kind: 'hurt' });
    }
  }

  // Leave the body: the spirit rises at the rest point.
  release() {
    const { player, enemies, targeting, telegraphs, hud } = this.game;
    if (!player.dead || this.ghost) return false;
    const at = player.position;
    this._placeCorpse(at.x, at.z, player.facing);
    const dest = this.restPoint();
    telegraphs.clear();
    hud.numbers.clear();
    targeting.clear();
    enemies.resetSurvivors();
    this.ghost = true;
    player.becomeGhost(dest.x, dest.z);
    this._ghostLook(true);
    this.game.events.emit('ghost', { on: true });
    this.game.events.emit('log', { text: `Your spirit rises ${dest.label}. Return to your body to live again, or rest here to return at once${this.coinLoss ? `, ${moneyText(this.coinLoss)} lighter` : ''}.`, kind: 'lore' });
    return true;
  }

  // Rise at the body: half health, nothing lost.
  reviveAtCorpse() {
    if (!this.ghost || !this.corpse || !this.nearCorpse) return false;
    const { player } = this.game;
    const c = this.corpse;
    this._end();
    player.revive(c.x, c.z, CONFIG.death.corpseHealth);
    this.game.events.emit('log', { text: 'You return to your body. Your wounds are still with you.', kind: 'heal' });
    return true;
  }

  // Return to life where the spirit stands (at the rest point), coins lost.
  reviveHere() {
    const { player, inventory, events } = this.game;
    if (!this.ghost) return false;
    const lost = inventory.loseCoins(this.coinLoss);
    const at = player.position.clone();
    this._end();
    player.revive(at.x, at.z);
    events.emit('log', { text: `You return to life ${this.restPoint().label}.${lost ? ` ${moneyText(lost)} gone.` : ''}`, kind: 'lore' });
    return true;
  }

  get nearCorpse() {
    const c = this.corpse;
    const p = this.game.player.position;
    return !!c && Math.hypot(p.x - c.x, p.z - c.z) <= CONFIG.death.corpseReach;
  }

  get nearRestPoint() {
    const r = this.restPoint();
    const p = this.game.player.position;
    return Math.hypot(p.x - r.x, p.z - r.z) <= CONFIG.death.restReach;
  }

  // what the interaction system offers a ghost
  interactions() {
    if (!this.ghost) return [];
    const out = [];
    if (this.corpse) out.push({ key: 'corpse', x: this.corpse.x, z: this.corpse.z, bias: -1, reach: CONFIG.death.corpseReach, prompt: 'Return to your body', run: () => this.reviveAtCorpse() });
    const r = this.restPoint();
    out.push({ key: 'revive-here', x: r.x, z: r.z, bias: 0, reach: CONFIG.death.restReach, prompt: this.coinLoss ? `Return to life here (lose ${moneyText(this.coinLoss)})` : 'Return to life here', run: () => this.reviveHere() });
    return out;
  }

  _end() {
    this.ghost = false;
    if (this.corpse) this.game.scene.remove(this.corpse.mesh);
    this.corpse = null;
    this._ghostLook(false);
    this.game.events.emit('ghost', { on: false });
  }

  // a new game or a load: no ghost, no body
  reset() {
    if (this.ghost || this.corpse) this._end();
    this.coinLoss = 0;
  }

  _placeCorpse(x, z, facing) {
    const mesh = this.game.assets.instance('warden');
    mesh.rotation.set(-(Math.PI / 2) * 0.95, facing, 0, 'YXZ');
    mesh.position.set(x, heightAt(x, z) + 0.15, z);
    mesh.name = 'Corpse';
    this.game.scene.add(mesh);
    this.corpse = { x, z, mesh };
  }

  // the world goes grey while you walk as a spirit
  _ghostLook(on) {
    const c = this.game.renderer.domElement;
    c.style.filter = on ? 'grayscale(0.85) brightness(0.85) contrast(1.1)' : '';
    document.body.classList.toggle('ghost', on);
  }

  // ------------------------------------------------------------- revenge
  isNemesis(enemy) {
    return !!enemy && enemy.id === this.game.worldState.nemesis;
  }

  // extra damage dealt to the enemy that killed you
  damageScaleAgainst(enemy) {
    return this.isNemesis(enemy) ? 1 + CONFIG.death.revengeBonus / 100 : 1;
  }

  // called when an enemy falls: revenge pays
  onEnemyDefeated(enemy) {
    if (!this.isNemesis(enemy)) return;
    const { worldState, progression, events, hud } = this.game;
    worldState.nemesis = null;
    const bonus = Math.round(enemy.cfg.xp * CONFIG.death.revengeXp);
    events.emit('log', { text: `Revenge. The ${enemy.cfg.name} that killed you lies still.`, kind: 'level' });
    hud.toast('Revenge!');
    if (bonus) progression.addXp(bonus);
  }
}
