import { CONFIG } from '../config.js';
import { ITEMS, sellPrice, itemView } from '../data/items.js';
import MERCHANTS from '../data/merchants.json';
import { MARA } from '../data/text.js';

// Buying and selling, WoW style. A merchant sells from a fixed stock at the
// item database's price and buys at CONFIG.shop.sellFraction of it. Anything
// sold this session can be bought back for what it fetched. Quest items are
// never sold. The manifest is handed to Mara here for her reward.

export class Merchant {
  constructor(game) {
    this.game = game;
    this.current = null; // merchant id while a shop is open
    this.npc = null;
    this.buyback = []; // [{ id, count, rolls?, paid }]
  }

  get def() {
    return this.current ? MERCHANTS.merchants[this.current] : null;
  }

  get stock() {
    return this.def ? this.def.stock : [];
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

  // ------------------------------------------------------------ Mara's story
  // What Mara says right now, and whether the manifest can be handed in.
  get dialogue() {
    const { worldState, inventory } = this.game;
    if (this.current !== 'mara') return { text: '' };
    if (worldState.flags.has('manifest_delivered')) return { text: this.justThanked ? MARA.thanks : MARA.done };
    if (inventory.count('manifest') > 0) return { text: MARA.complete, handIn: MARA.handIn };
    return { text: worldState.examined.has('cart') ? MARA.cartFound : MARA.start };
  }

  handInManifest() {
    const { worldState, inventory, progression, events } = this.game;
    if (this.current !== 'mara' || worldState.flags.has('manifest_delivered') || inventory.count('manifest') < 1) return false;
    inventory.removeAll('manifest');
    worldState.flags.add('manifest_delivered');
    this.justThanked = true;
    const r = CONFIG.quests.manifest;
    events.emit('log', { text: 'You hand Mara the manifest. She reads it twice.', kind: 'lore' });
    inventory.addCoins(r.coins, 'from Mara Venn');
    progression.addXp(r.xp);
    events.emit('questComplete', { id: 'manifest' });
    events.emit('objectiveChanged', {});
    inventory._changed();
    return true;
  }
}
