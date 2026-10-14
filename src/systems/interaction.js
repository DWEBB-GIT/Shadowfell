import { CONFIG } from '../config.js';
import { SHRINES } from '../world/layout.js';
import { EXAMINE } from '../data/text.js';

// Finds the nearest thing the player can act on and runs it when E is
// pressed. The HUD shows `current.prompt`.

export class Interaction {
  constructor(game) {
    this.game = game;
    this.current = null;
  }

  _candidates() {
    const { loot, world, worldState } = this.game;
    const list = [];
    // bodies and loot: using one loots everything close by
    for (const l of loot.lootables()) {
      const n = loot.areaCount(l);
      const own = l.kind === 'corpse' ? `Loot the ${l.name}` : l.entry.def.prompt;
      list.push({ key: 'loot:' + l.id, x: l.x, z: l.z, bias: -0.4, loot: l, prompt: n > 1 ? `${own} (and ${n - 1} more nearby)` : own, run: () => loot.lootArea(l) });
    }
    list.push(...this.game.npcs.interactions());
    for (const sh of SHRINES) {
      list.push({
        key: sh.id === 'shrine_road' ? 'shrine' : 'shrine:' + sh.id,
        x: sh.position[0],
        z: sh.position[1],
        bias: 0,
        reach: 2.6,
        prompt: 'Rest at the shrine',
        run: () => this.game.restAtShrine(sh),
      });
    }
    for (const p of world.examinePoints) {
      const seen = worldState.examined.has(p.id);
      list.push({
        key: 'examine:' + p.id,
        x: p.x,
        z: p.z,
        bias: seen ? 0.6 : 0.2, // once read, other interactions win ties
        reach: p.id === 'watch_post' ? 3.2 : undefined,
        prompt: p.id === 'cart' ? 'Examine the cart' : 'Examine',
        run: () => this.examine(p.id),
      });
    }
    return list;
  }

  examine(id) {
    const { worldState, events } = this.game;
    const first = !worldState.examined.has(id);
    worldState.examined.add(id);
    events.emit('log', { text: EXAMINE[id], kind: 'lore' });
    if (first) events.emit('examined', { id });
  }

  update() {
    const { player } = this.game;
    if (player.dead) {
      this.current = null;
      return;
    }
    let best = null;
    let bestScore = Infinity;
    for (const c of this._candidates()) {
      const d = Math.hypot(c.x - player.position.x, c.z - player.position.z);
      if (d > (c.reach || CONFIG.interaction.radius)) continue;
      const score = d + c.bias;
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
    this.current = best;
  }

  interact() {
    this.update(); // use the player's position this frame, not last frame's
    if (!this.current) return false;
    const c = this.current;
    c.run();
    this.update();
    return true;
  }
}
