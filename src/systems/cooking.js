import { DB } from '../data/db.js';
import { ITEMS } from '../data/items.js';
import { STATIONS } from '../world/layout.js';
import { moneyText } from '../ui/money.js';

// Cooking (data/recipes.json), learned from Hester at the Ford Inn, and the
// food it makes. As in WoW's professions:
//   * a recipe needs a skill rank, its ingredients and a fire close by (your
//     camp or a hearth); the starter recipes come with the skill and the rest
//     are taught by a trainer for coins;
//   * each dish takes a short cast; moving stops it;
//   * a recipe is orange, yellow, green or grey by how easy it now is for
//     you, and so how likely making it is to raise your skill.
// Food is eaten sitting down: it restores health over its time while you
// stay still and out of the fight.

const SKILL_UP_CHANCE = { orange: 1, yellow: 0.75, green: 0.25, grey: 0 };

export class Cooking {
  constructor(game) {
    this.game = game;
    this.learned = new Set(); // taught recipes (the starters need no learning)
    this.crafting = null; // { id, t, total, left }
    game.events.on('playerHurt', () => this.stopEating('You stop eating.'));
    game.events.on('playerDied', () => {
      this.crafting = null;
      this.game.player.eating = null;
    });
  }

  reset() {
    this.learned = new Set();
    this.crafting = null;
  }

  get ability() {
    return DB.abilities.cook;
  }

  rank(skill = 'cooking') {
    return this.game.skills.rank(skill);
  }

  // ------------------------------------------------------------ recipes
  knows(id) {
    const r = DB.recipes[id];
    return !!r && this.game.skills.has(r.skill) && (!r.trainer || this.learned.has(id));
  }

  // every recipe you know for a skill, easiest first
  known(skill = 'cooking') {
    return Object.values(DB.recipes).filter((r) => r.skill === skill && this.knows(r.id)).sort((a, b) => a.rank - b.rank);
  }

  // 'orange' | 'yellow' | 'green' | 'grey' (or 'red' while it is beyond you)
  colour(r) {
    const n = this.rank(r.skill);
    if (n < r.rank) return 'red';
    const [y, g, grey] = r.skillUp;
    return n < y ? 'orange' : n < g ? 'yellow' : n < grey ? 'green' : 'grey';
  }

  // how many times you could make it with what is in your bags
  canMake(r) {
    return Math.min(...r.inputs.map((x) => Math.floor(this.game.inventory.count(x.item) / x.count)));
  }

  get nearFire() {
    const p = this.game.player.position;
    const range = this.ability.tuning.fireRange;
    const camp = this.game.worldState.camp;
    if (camp && Math.hypot(p.x - camp.x, p.z - camp.z) <= range) return 'your camp';
    const s = STATIONS.find((st) => st.kind === 'fire' && Math.hypot(p.x - st.position[0], p.z - st.position[1]) <= st.radius);
    return s ? s.name : null;
  }

  // what a trainer can teach you now (you must know the skill first)
  offeredBy(npcId) {
    return Object.values(DB.recipes).filter((r) => r.trainer === npcId && this.game.skills.has(r.skill) && !this.learned.has(r.id));
  }

  learnRecipe(id) {
    const r = DB.recipes[id];
    const { inventory, events } = this.game;
    if (!r || !r.trainer || this.learned.has(id)) return false;
    const name = ITEMS[r.output.item].name;
    if (this.rank(r.skill) < r.rank) {
      events.emit('log', { text: `You need ${DB.skills[r.skill].name} ${r.rank} to learn ${name}.`, kind: 'muted', throttle: 'recipe-rank' });
      return false;
    }
    if (inventory.coins < r.cost) {
      events.emit('log', { text: `You need ${moneyText(r.cost)} to learn ${name}.`, kind: 'muted', throttle: 'recipe-coins' });
      return false;
    }
    inventory.loseCoins(r.cost);
    this.learned.add(id);
    events.emit('log', { text: `You learn to make ${name}.`, kind: 'level' });
    this.game.hud?.toast(`Recipe: ${name}`);
    events.emit('skillsChanged', { id: r.skill });
    return true;
  }

  // ------------------------------------------------------------ cooking
  // Why a recipe cannot be made now (null if it can).
  blocked(r) {
    const { player } = this.game;
    if (!this.knows(r.id)) return "You don't know how to make that.";
    if (this.rank(r.skill) < r.rank) return `Requires ${DB.skills[r.skill].name} ${r.rank}.`;
    if (this.canMake(r) < 1) return 'You are missing ingredients.';
    if (!this.nearFire) return 'Requires a cooking fire.';
    if (player.dead || player.casting || player.lunge) return "You can't do that now.";
    if (player.moving) return "You can't do that while moving.";
    return null;
  }

  // Start cooking `times` of a recipe (Infinity: as many as you can).
  start(id, times = 1) {
    const r = DB.recipes[id];
    if (!r) return false;
    const why = this.blocked(r);
    if (why) {
      this.game.hud.error(why);
      return false;
    }
    this.stopEating();
    this.crafting = { id, t: 0, total: this.ability.tuning.castTime, left: Math.min(times, this.canMake(r)) };
    this.game.player.rig.play('brace', this.crafting.total, 0.9);
    this.game.events.emit('craftStart', { id });
    return true;
  }

  stop(why) {
    if (!this.crafting) return;
    this.crafting = null;
    this.game.player.rig.action = null;
    if (why) this.game.events.emit('log', { text: why, kind: 'muted', throttle: 'craft-stop' });
    this.game.events.emit('craftEnd', { done: false });
  }

  _finish(r) {
    const { inventory, skills, events } = this.game;
    for (const x of r.inputs) inventory.removeCount(x.item, x.count);
    inventory.addItem(r.output.item, r.output.count, { quiet: true });
    const name = ITEMS[r.output.item].name;
    events.emit('log', { text: `You cook ${r.output.count > 1 ? r.output.count + ' ' : ''}${name}.`, kind: 'loot' });
    const chance = SKILL_UP_CHANCE[this.colour(r)] || 0;
    if (chance > 0 && this.game.random() < chance) skills.raise(r.skill);
    events.emit('craftEnd', { id: r.id, done: true });
  }

  update(dt) {
    const { player } = this.game;
    const c = this.crafting;
    if (c) {
      if (player.dead || player.moving) this.stop('Interrupted.');
      else if ((c.t += dt) >= c.total) {
        const r = DB.recipes[c.id];
        this._finish(r);
        c.left -= 1;
        if (c.left > 0 && this.canMake(r) > 0 && this.nearFire) {
          c.t = 0;
          player.rig.play('brace', c.total, 0.9);
        } else this.crafting = null;
      }
    }
    // eating: health over time while sitting still, out of the fight
    const e = player.eating;
    if (e) {
      if (player.dead || player.moving) this.stopEating('You stop eating.');
      else {
        const step = Math.min(dt, e.left);
        e.left -= step;
        e.carry += e.perSecond * step;
        const whole = Math.floor(e.carry);
        if (whole > 0) {
          e.carry -= whole;
          player.heal(whole);
        }
        if (e.left <= 0 || player.health >= player.maxHealth) this.stopEating(player.health >= player.maxHealth ? 'You feel full.' : null);
      }
    }
  }

  // ------------------------------------------------------------ food
  // Sit and eat a dish from your bags (out of combat only).
  eat(loc) {
    const { player, inventory, events } = this.game;
    const s = inventory.get(loc);
    const food = s && ITEMS[s.id].use?.food;
    if (!food || player.dead) return false;
    if (this.game.resources.inCombat || this.game.targeting.attacking) {
      this.game.hud.error("You can't eat while fighting.");
      return false;
    }
    if (player.health >= player.maxHealth) {
      events.emit('log', { text: 'You are not hungry.', kind: 'muted', throttle: 'not-hungry' });
      return false;
    }
    this.stop();
    inventory.take(loc, 1);
    player.eating = { id: s.id, perSecond: food.heal / food.seconds, left: food.seconds, total: food.seconds, carry: 0 };
    player.rig.pose = 'sit';
    events.emit('log', { text: `You sit and eat the ${ITEMS[s.id].name.toLowerCase()}.`, kind: 'heal' });
    return true;
  }

  stopEating(text = null) {
    const { player } = this.game;
    if (!player.eating) return;
    player.eating = null;
    if (player.rig.pose === 'sit') player.rig.pose = null;
    if (text) this.game.events.emit('log', { text, kind: 'muted', throttle: 'eat-stop' });
  }

  // ------------------------------------------------------------ saving
  serialize() {
    return { recipes: [...this.learned] };
  }

  apply(data) {
    this.reset();
    for (const id of data?.recipes || []) if (DB.recipes[id]?.trainer) this.learned.add(id);
  }
}
