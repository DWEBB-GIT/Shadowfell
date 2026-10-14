import { CONFIG } from '../config.js';
import { ITEMS, sellPrice, itemView } from '../data/items.js';
import { DB } from '../data/db.js';

// Buying and selling, WoW style. A shop (data/shops.json) sells its stock at
// the item database's price and buys at CONFIG.shop.sellFraction of it.
// Anything sold this session can be bought back for what it fetched. Quest
// items are never sold. The shopkeeper also talks about, and takes the
// turn-in for, any quest they give (data/quests.json).

export class Merchant {
  constructor(game) {
    this.game = game;
    this.current = null; // shop id while a shop is open
    this.npc = null;
    this.buyback = []; // [{ id, count, rolls?, paid }]
  }

  // what the shop window shows: who keeps it, what kind of vendor, the stock
  get def() {
    if (!this.current) return null;
    const shop = DB.shops[this.current];
    const keeper = this.npc && DB.npcs[this.npc.id];
    return { name: keeper ? keeper.name : shop.name, title: DB.vendorTypes[shop.vendorType].name, stock: shop.stock };
  }

  get stock() {
    return this.current ? DB.shops[this.current].stock : [];
  }

  open(id, npc) {
    this.current = id;
    this.npc = npc;
    this.game.events.emit('merchantOpened', { id });
  }

  close() {
    if (!this.current) return;
    this.current = null;
    this.npc = null;
    this.game.events.emit('merchantClosed', {});
  }

  // walking away closes the shop
  update() {
    if (!this.current || !this.npc) return;
    const p = this.game.player.position;
    if (this.game.player.dead || Math.hypot(p.x - this.npc.position.x, p.z - this.npc.position.z) > CONFIG.shop.leaveRange) this.close();
  }

  priceOf(id) {
    return ITEMS[id].price;
  }

  buy(id) {
    const { inventory, events } = this.game;
    if (!this.current || !this.stock.includes(id)) return false;
    const price = this.priceOf(id);
    const name = ITEMS[id].name;
    if (inventory.coins < price) {
      events.emit('log', { text: `You cannot afford the ${name} (${price} coins).`, kind: 'muted', throttle: 'shop-refuse' });
      return false;
    }
    if (!inventory.addItem(id, 1, { quiet: true })) return false; // bags full: addItem says so
    inventory.coins -= price;
    events.emit('coins', { amount: -price });
    events.emit('itemBought', { id, price });
    events.emit('log', { text: `Bought: ${name} for ${price} coin${price === 1 ? '' : 's'}.`, kind: 'loot' });
    inventory._changed();
    return true;
  }

  // Sell the whole stack at an inventory location.
  sell(loc) {
    const { inventory, events } = this.game;
    if (!this.current) return false;
    const stack = inventory.get(loc);
    if (!stack || loc.startsWith('s:')) return false;
    const def = itemView(stack);
    if (def.quest) {
      events.emit('log', { text: `${this.def.name} has no use for that, and you should not part with it.`, kind: 'muted', throttle: 'shop-refuse' });
      return false;
    }
    const each = sellPrice(stack, CONFIG.shop.sellFraction);
    const taken = inventory.take(loc);
    if (!taken) return false;
    const paid = each * taken.count;
    inventory.coins += paid;
    this.buyback.unshift({ ...taken, paid });
    this.buyback.length = Math.min(this.buyback.length, CONFIG.shop.buybackSlots);
    events.emit('coins', { amount: paid });
    events.emit('itemSold', { id: taken.id, count: taken.count, paid });
    events.emit('log', { text: `Sold: ${def.name}${taken.count > 1 ? ` ×${taken.count}` : ''} for ${paid} coin${paid === 1 ? '' : 's'}.`, kind: 'loot' });
    if (loc.startsWith('e:')) inventory._equipmentChanged();
    inventory._changed();
    return true;
  }

  buyBack(index) {
    const { inventory, events } = this.game;
    const b = this.buyback[index];
    if (!this.current || !b) return false;
    if (inventory.coins < b.paid) {
      events.emit('log', { text: 'You cannot afford to buy that back.', kind: 'muted', throttle: 'shop-refuse' });
      return false;
    }
    if (!inventory.addItem(b.id, b.count, { quiet: true, rolls: b.rolls || null })) return false;
    inventory.coins -= b.paid;
    this.buyback.splice(index, 1);
    events.emit('log', { text: `Bought back: ${itemView(b).name}.`, kind: 'loot' });
    inventory._changed();
    return true;
  }

  // ------------------------------------------------------------ quests
  // The quests this shopkeeper gives, as data records.
  get _quests() {
    const keeper = this.npc && DB.npcs[this.npc.id];
    return keeper ? (keeper.quests || []).map((id) => DB.quests[id]) : [];
  }

  // What the shopkeeper says right now, and whether a quest item can be
  // handed in: the quest's current stage decides.
  get dialogue() {
    const { worldState, inventory } = this.game;
    for (const q of this._quests) {
      const stage = worldState.questStage(q.id);
      const t = q.turnIn;
      if (t && worldState.flags.has(t.setsFlag) && this.justThanked === q.id) return { text: t.thanks };
      if (t && stage.id === t.atStage && inventory.count(t.item) > 0) return { text: stage.giver, handIn: { quest: q.id, action: t.action } };
      if (stage.giver) return { text: stage.giver };
    }
    return { text: '' };
  }

  // Hand over a quest's item for its reward (data/quests.json turnIn).
  turnIn(questId) {
    const { worldState, inventory, progression, events } = this.game;
    const q = DB.quests[questId];
    const t = q && q.turnIn;
    if (!t || !this._quests.includes(q)) return false;
    if (worldState.flags.has(t.setsFlag) || worldState.questStage(q.id).id !== t.atStage || inventory.count(t.item) < 1) return false;
    inventory.removeAll(t.item);
    worldState.flags.add(t.setsFlag);
    this.justThanked = q.id;
    if (t.log) events.emit('log', { text: t.log, kind: 'lore' });
    const r = q.reward || {};
    if (r.coins) inventory.addCoins(r.coins, `from ${DB.npcs[t.npc].name}`);
    if (r.xp) progression.addXp(r.xp);
    events.emit('questComplete', { id: q.id });
    events.emit('objectiveChanged', {});
    inventory._changed();
    return true;
  }

  // (kept for scripts and tests written before quests were data)
  handInManifest() {
    return this.turnIn('missing_delivery');
  }
}
