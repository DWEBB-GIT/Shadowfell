import { ITEMS, EQUIP_SLOTS, BAG_SOCKETS, sellPrice, itemView } from '../data/items.js';
import { BUTTONS } from '../core/gamepad.js';
import { ABILITIES } from '../systems/actionBar.js';
import { CONFIG } from '../config.js';
import { mitigation } from '../systems/stats.js';

const STAT_LABEL = { might: 'Might', finesse: 'Finesse', intellect: 'Intellect', vitality: 'Vitality', armour: 'armour', resistance: 'resistance', block: '% block chance', blockRating: 'block rating', haste: '% haste' };

// Bags, the character panel, the spellbook, and the bag slots and spell bar
// on the bottom bar. None of these pause the game.
//
// Each bag opens and closes on its own (click its bag slot, or its ×); B
// opens or closes them all, as in WoW. Spells are dragged between bar slots,
// off the bar to remove them, and from the spellbook back onto it.
//
// Mouse: drag an item between slots to move, swap, equip or unequip it; drag
// it out over the world to drop it on the ground; right-click to use/equip.
// Gamepad: a highlight moves between slots; A picks up and puts down,
// X uses or equips, Y drops on the ground, B cancels or closes.
//
// Every action is a request to the Inventory, which decides what is allowed.

const $ = (id) => document.getElementById(id);
const KIND_LABEL = { weapon: 'Weapon', armor: 'Armour', shield: 'Shield', bag: 'Bag', consumable: 'Consumable', material: 'Material', document: 'Document' };

export class ItemUI {
  constructor(game, hud) {
    this.game = game;
    this.hud = hud;
    this.openBags = new Set(); // socket indices whose bag window is open
    this.open = { character: false, spellbook: false };
    this.icons = {};
    this.drag = null; // { from, x0, y0, moved }
    this.focus = null; // gamepad highlight: a location string
    this.carry = null; // gamepad: location of the item being carried
    this.el = {
      bags: $('bags-window'),
      frames: $('bags-frames'),
      character: $('character-window'),
      left: $('equip-left'),
      right: $('equip-right'),
      stats: $('char-stats'),
      hint: $('char-hint'),
      sockets: $('bag-sockets'),
      spellbook: $('spellbook-window'),
      spellList: $('spellbook-list'),
      spellHint: $('spellbook-hint'),
      shop: $('shop-window'),
      shopName: $('shop-name'),
      shopTitle: $('shop-title'),
      shopTalk: $('shop-talk'),
      shopHandIn: $('shop-handin'),
      shopStock: $('shop-stock'),
      shopBuyback: $('shop-buyback'),
      shopCoins: $('shop-coins'),
      shopHint: $('shop-hint'),
      tooltip: $('tooltip'),
      ghost: $('drag-ghost'),
    };

    $('btn-character').addEventListener('click', () => this.toggle('character'));
    $('btn-spellbook').addEventListener('click', () => this.toggle('spellbook'));
    $('btn-save').addEventListener('click', () => game.manualSave());
    $('shop-close').addEventListener('click', () => game.merchant.close());
    // a merchant opens your bags with it (and closes the ones it opened)
    game.events.on('merchantOpened', () => {
      this.shopOpenedBags = !this.bagsOpen;
      if (this.shopOpenedBags) this._sockets().forEach((i) => this.openBags.add(i));
      this.focus = null;
      this._afterChange('shop');
    });
    game.events.on('merchantClosed', () => {
      if (this.shopOpenedBags) this.openBags.clear();
      this.shopOpenedBags = false;
      this._afterChange(null);
    });
    document.querySelectorAll('[data-close-panel]').forEach((b) => b.addEventListener('click', () => this.close(b.dataset.closePanel)));
    this.el.frames.addEventListener('click', (e) => {
      const b = e.target.closest('[data-close-bag]');
      if (b) this.toggleBag(+b.dataset.closeBag);
    });

    // one set of listeners for every slot, present and future
    document.addEventListener('pointerdown', (e) => this._down(e));
    window.addEventListener('pointermove', (e) => this._move(e));
    window.addEventListener('pointerup', (e) => this._up(e));
    document.addEventListener('contextmenu', (e) => {
      const slot = e.target.closest && e.target.closest('.islot, .aslot');
      if (slot) {
        e.preventDefault();
        const loc = slot.dataset.loc || '';
        if (loc.startsWith('a:') || loc.startsWith('k:')) return;
        if (this._shopClick(loc)) return;
        // with a shop open, right-clicking something you carry sells it (WoW)
        if (game.merchant.current && (loc.startsWith('b:') || loc.startsWith('e:'))) game.merchant.sell(loc);
        else if (loc.startsWith('s:')) this.toggleBag(+loc.slice(2));
        else if (loc) game.inventory.use(loc);
      }
    });
    document.addEventListener('mouseover', (e) => {
      const slot = e.target.closest && e.target.closest('.islot, .aslot');
      if (slot && !this.drag) this._tooltip(slot.dataset.loc, slot);
    });
    document.addEventListener('mouseout', (e) => {
      if (e.target.closest && e.target.closest('.islot, .aslot')) this.el.tooltip.hidden = true;
    });

    game.events.on('inventoryChanged', () => this.render());
    game.events.on('equipmentChanged', () => this.render());
    game.events.on('levelUp', () => this.render());
    game.events.on('barChanged', () => this.render());
  }

  setIcons(icons) {
    this.icons = icons;
    this.render();
  }

  get anyOpen() {
    return this.openBags.size > 0 || this.open.character || this.open.spellbook || !!this.game.merchant.current;
  }

  // shop slots: m:<item> buys, y:<n> buys back, q:<quest> hands its item in
  _shopClick(loc) {
    const m = this.game.merchant;
    if (loc.startsWith('m:')) m.buy(loc.slice(2));
    else if (loc.startsWith('y:')) m.buyBack(+loc.slice(2));
    else if (loc.startsWith('q:')) m.turnIn(loc.slice(2));
    else return false;
    this.render();
    return true;
  }

  get bagsOpen() {
    return this.openBags.size > 0;
  }

  _sockets() {
    return this.game.inventory.sockets.map((s, i) => (s ? i : -1)).filter((i) => i >= 0);
  }

  // 'bags' toggles every bag at once (WoW's B); the others toggle one window.
  toggle(which) {
    if (which === 'bags') {
      if (this.bagsOpen) this.openBags.clear();
      else this._sockets().forEach((i) => this.openBags.add(i));
      this._afterChange('bags');
      return;
    }
    this.open[which] = !this.open[which];
    this._afterChange(which);
  }

  show(which) {
    if (which === 'bags') this._sockets().forEach((i) => this.openBags.add(i));
    else this.open[which] = true;
    this._afterChange(which);
  }

  toggleBag(i) {
    if (!this.game.inventory.sockets[i]) return;
    if (this.openBags.has(i)) this.openBags.delete(i);
    else this.openBags.add(i);
    this._afterChange('bags');
  }

  close(which) {
    if (which === 'bags') this.openBags.clear();
    else this.open[which] = false;
    this._afterChange(which);
  }

  closeAll() {
    const was = this.anyOpen;
    this.openBags.clear();
    this.open.character = this.open.spellbook = false;
    this.shopOpenedBags = false;
    this.game.merchant.close();
    this._afterChange(null);
    return was;
  }

  _afterChange(which) {
    if (!this.anyOpen) {
      this.carry = null;
      this.focus = null;
      this.el.tooltip.hidden = true;
    }
    this.render();
    if (this.anyOpen && (!this.focus || !this._visibleLocs().includes(this.focus))) this.focus = this._defaultFocus(which);
    this._paintFocus();
  }

  // ------------------------------------------------------------- render
  _iconFor(id) {
    const def = ITEMS[id];
    return def && this.icons[def.model];
  }

  _slotHTML(loc, stack, extra = '', placeholder = '') {
    const cls = ['islot', extra];
    let inner = '';
    if (stack) {
      const icon = this._iconFor(stack.id);
      inner = icon ? `<img src="${icon}" alt="">` : `<span class="letter">${ITEMS[stack.id].name[0]}</span>`;
      if (stack.count > 1) inner += `<span class="count">${stack.count}</span>`;
      cls.push('filled', 'k-' + ITEMS[stack.id].kind, 'q-' + itemView(stack).quality);
    } else if (placeholder) {
      inner = `<span class="ph">${placeholder}</span>`;
    }
    if (this.carry === loc) cls.push('carried');
    return `<div class="${cls.join(' ')}" data-loc="${loc}">${inner}</div>`;
  }

  render() {
    const inv = this.game.inventory;
    // bag sockets on the bottom bar (backpack last, as in WoW: right-most)
    let sockets = '';
    for (let i = BAG_SOCKETS - 1; i >= 1; i--) {
      const s = inv.sockets[i];
      sockets += this._slotHTML(`s:${i}`, s ? { id: s.id, count: 1 } : null, 'socket', '');
    }
    // a bag whose socket was emptied closes with it
    for (const i of [...this.openBags]) if (!inv.sockets[i]) this.openBags.delete(i);
    for (let i = 1; i < BAG_SOCKETS; i++) if (this.openBags.has(i)) sockets = sockets.replace(`data-loc="s:${i}"`, `data-loc="s:${i}" data-lit="1"`);
    sockets += `<div class="islot socket backpack filled${this.openBags.has(0) ? ' lit' : ''}" data-loc="s:0" title="Backpack (B)"><span class="bp-icon"></span><span class="key" data-kbm="B" data-pad="Start"></span></div>`;
    this.el.sockets.innerHTML = sockets;

    // bags window: one frame per bag
    this.el.bags.hidden = !this.bagsOpen;
    if (this.bagsOpen) {
      let html = '';
      inv.sockets.forEach((s, i) => {
        if (!s || !this.openBags.has(i)) return;
        const name = i === 0 ? 'Backpack' : ITEMS[s.id].name;
        const used = s.slots.filter(Boolean).length;
        html += `<div class="bag-frame panel"><div class="window-head"><h3>${name}</h3><span class="dim">${used}/${s.slots.length}</span><button class="btn small" data-close-bag="${i}" title="Close this bag">&times;</button></div><div class="bag-grid">`;
        s.slots.forEach((st, j) => (html += this._slotHTML(`b:${i}:${j}`, st)));
        html += '</div>';
        if (i === 0) html += `<div class="bag-foot"><span class="coin-dot"></span><b>${inv.coins}</b> coins</div>`;
        html += '</div>';
      });
      this.el.frames.innerHTML = html;
    }

    // character window
    this.el.character.hidden = !this.open.character;
    if (this.open.character) {
      const half = Math.ceil(EQUIP_SLOTS.length / 2);
      const col = (list) => list.map((s) => `<div class="equip-row">${this._slotHTML(`e:${s.id}`, inv.equipment[s.id], 'equip', s.label)}</div>`).join('');
      this.el.left.innerHTML = col(EQUIP_SLOTS.slice(0, half));
      this.el.right.innerHTML = col(EQUIP_SLOTS.slice(half));
      const { player, progression, stats } = this.game;
      const t = stats.totals;
      const range = (m) => stats.abilityRange(m).join('–');
      // stats that rose at the last level-up keep a green "+n" for a while
      const lg = progression.lastGains;
      const gain = (id) => {
        const g = lg && lg.gains.find((x) => x.id === id);
        return g ? ` <span class="gain">+${g.diff}</span>` : '';
      };
      const row = (label, value, tip = '', id = '') => `<div${tip ? ` title="${tip}"` : ''}${id ? ` data-stat="${id}"` : ''}><span>${label}</span><b>${value}${id ? gain(id) : ''}</b></div>`;
      const lvl = progression.level;
      const arch = stats.archetype;
      const wears = arch.armourTypes.map((k) => CONFIG.armourTypes[k].name).join(', ') + (arch.shields ? ', shields' : '');
      this.el.stats.innerHTML = [
        row('Level', `${lvl} ${arch.name}`),
        row('Health', `${Math.ceil(player.health)} / ${player.maxHealth}`, '', 'health'),
        '<div class="stat-gap"></div>',
        row('Might', t.might, arch.mainStat === 'might' ? 'Main attribute: +1 damage per point' : '', 'might'),
        row('Finesse', t.finesse, '+0.5% critical chance per point', 'finesse'),
        row('Intellect', t.intellect, 'Spell power, and mana for casters', 'intellect'),
        row('Vitality', t.vitality, '+6 health per point', 'vitality'),
        '<div class="stat-gap"></div>',
        row('Weapon', `${inv.weapon.name} (${stats.weaponRange.join('–')})`),
        row('Strike', range(1), '', 'strike'),
        row('Shield Break', range(CONFIG.shieldBreak.damageMultiplier)),
        row('Lunge', range(CONFIG.lunge.damageMultiplier)),
        row('Critical chance', `${stats.critChance.toFixed(1)}%`, `Critical hits do ${CONFIG.stats.critMultiplier * 100}% damage`, 'crit'),
        row('Haste', `${stats.haste}% (swing ${stats.attackCooldown.toFixed(2)}s, GCD ${stats.globalCooldown.toFixed(2)}s)`, 'Shortens swings, windups, casts and the global cooldown', 'haste'),
        '<div class="stat-gap"></div>',
        row('Armour', `${t.armour} (−${mitigation(t.armour, lvl).toFixed(0)}%)`, `Physical damage taken from a level ${lvl} foe; higher-level foes get through more`),
        row('Block', stats.blockChance ? `${stats.blockChance}%, stops ${CONFIG.stats.blockReduction}%` : 'no shield', 'Chance to block a melee blow (shield block chance + block rating / 10)', 'block'),
        row('Block rating', t.blockRating || 0, `${CONFIG.stats.blockRatingPerPercent} rating = +1% block chance`),
        row('Resistance', `${t.resistance || 0} (−${mitigation(t.resistance || 0, lvl).toFixed(0)}%)`, 'Reduces magical damage taken'),
        row('Wears', wears),
      ].join('');
      this.el.hint.textContent = this.hud.padMode
        ? 'A: pick up / place   X: equip or use   Y: drop   B: back'
        : 'Drag items between your bags and here. Right-click to equip. Drag out of a window to drop.';
    }

    // merchant window: stock, buyback, and whatever the merchant has to say
    const m = this.game.merchant;
    this.el.shop.hidden = !m.current;
    this.el.shop.classList.toggle('beside-character', this.open.character);
    if (m.current) {
      const def = m.def;
      this.el.shopName.textContent = def.name;
      this.el.shopTitle.textContent = def.title;
      const talk = m.dialogue;
      this.el.shopTalk.textContent = talk.text;
      this.el.shopHandIn.hidden = !talk.handIn;
      this.el.shopHandIn.textContent = talk.handIn ? talk.handIn.action : '';
      this.el.shopHandIn.dataset.loc = talk.handIn ? 'q:' + talk.handIn.quest : 'q:';
      this.el.shopHandIn.classList.toggle('focus', !!talk.handIn && this.focus === 'q:' + talk.handIn.quest && this.hud.padMode);
      this.el.shopStock.innerHTML = m.stock
        .map((id) => {
          const price = m.priceOf(id);
          const poor = price > inv.coins;
          return `<div class="shop-row${poor ? ' poor' : ''}">${this._slotHTML('m:' + id, { id, count: 1 })}<div><div class="shop-item q-${ITEMS[id].quality}">${ITEMS[id].name}</div><div class="shop-price"><span class="coin-dot"></span>${price}</div></div></div>`;
        })
        .join('');
      const bb = m.buyback;
      this.el.shopBuyback.innerHTML = bb.length
        ? bb.map((b, i) => this._slotHTML('y:' + i, { id: b.id, count: b.count })).join('')
        : '<span class="dim small">Nothing sold yet.</span>';
      this.el.shopCoins.textContent = inv.coins;
      this.el.shopHint.textContent = this.hud.padMode
        ? 'A: buy   Y on a bag item: sell   B: leave'
        : 'Click to buy. Right-click (or drag here) anything in your bags to sell it.';
    }

    // spellbook: every ability, ready to drag onto the bar
    this.el.spellbook.hidden = !this.open.spellbook;
    if (this.open.spellbook) {
      const bar = this.game.actionBar;
      const icons = this.hud.abilityIcons;
      this.el.spellList.innerHTML = Object.entries(ABILITIES)
        .map(([id, a]) => {
          const at = bar.slots.indexOf(id);
          return `<div class="spell-row"><div class="islot spell filled${this.carry === 'k:' + id ? ' carried' : ''}" data-loc="k:${id}"><img src="${icons[id] || ''}" alt=""></div><div><div class="spell-name">${a.name}</div><div class="dim spell-where">${at >= 0 ? 'On the bar' : 'Not on the bar'}</div></div></div>`;
        })
        .join('');
      this.el.spellHint.textContent = this.hud.padMode
        ? 'A: pick up / place on the bar   Y: remove from the bar   B: back'
        : 'Drag a spell onto the bar. Drag spells along the bar to rearrange them, or off it to remove them.';
    }
    // a carried bar slot is shown faded
    this.hud.barSlots?.forEach((el) => el.classList.toggle('carried', this.carry === el.dataset.loc));
    this._paintFocus();
  }

  // ------------------------------------------------------------- tooltip
  _tooltip(loc, anchor) {
    const tip = this.el.tooltip;
    if (loc && (loc.startsWith('a:') || loc.startsWith('k:'))) {
      const id = loc.startsWith('a:') ? this.game.actionBar.slots[+loc.slice(2)] : loc.slice(2);
      if (!id) {
        tip.hidden = true;
        return;
      }
      tip.innerHTML = `<div class="tt-name">${ABILITIES[id].name}</div><div class="tt-desc">${ABILITIES[id].desc}</div>`;
      return this._placeTip(anchor);
    }
    let stack = loc && this.game.inventory.get(loc);
    let shop = null;
    if (loc && loc.startsWith('m:')) {
      stack = { id: loc.slice(2), count: 1 };
      shop = { buy: this.game.merchant.priceOf(stack.id) };
    } else if (loc && loc.startsWith('y:')) {
      const b = this.game.merchant.buyback[+loc.slice(2)];
      stack = b || null;
      shop = b ? { buy: b.paid } : null;
    }
    if (!stack || loc === 's:0') {
      tip.hidden = true;
      return;
    }
    const def = itemView(stack);
    const lines = [`<div class="tt-name k-${def.kind} q-${def.quality}">${def.name}</div>`, `<div class="tt-kind">${KIND_LABEL[def.kind]}${def.slot ? ' &middot; ' + EQUIP_SLOTS.find((s) => s.id === def.slot).label : ''}</div>`];
    if (def.armourType) {
      const ok = this.game.inventory.canWear(def);
      lines.push(`<div class="${ok ? '' : 'down'}">${CONFIG.armourTypes[def.armourType].name}${ok ? '' : ` (a ${this.game.stats.archetype.name} cannot wear this)`}</div>`);
    }
    if (def.damage) {
      const avg = (d) => (d[0] + d[1]) / 2;
      const diff = avg(def.damage) - avg(this.game.stats.weaponRange);
      const cmp = loc.startsWith('e:') || diff === 0 ? '' : ` <span class="${diff > 0 ? 'up' : 'down'}">(${diff > 0 ? '+' : ''}${diff} average)</span>`;
      lines.push(`<div>${def.damage[0]}–${def.damage[1]} damage${cmp}</div>`);
    }
    for (const [k, v] of Object.entries(def.stats || {})) lines.push(`<div class="up">+${v} ${STAT_LABEL[k] || k}</div>`);
    if (def.bagSlots) lines.push(`<div>${def.bagSlots} slots</div>`);
    if (stack.count > 1) lines.push(`<div>${stack.count} carried</div>`);
    lines.push(`<div class="tt-desc">${def.description}</div>`);
    const sell = sellPrice(stack, CONFIG.shop.sellFraction);
    if (shop) lines.push(`<div class="tt-price">Price: ${shop.buy} coin${shop.buy === 1 ? '' : 's'}</div>`);
    else lines.push(def.quest ? '<div class="tt-sell">Quest item</div>' : `<div class="tt-sell">Sells for ${sell * stack.count} coin${sell * stack.count === 1 ? '' : 's'}${stack.count > 1 ? ` (${sell} each)` : ''}</div>`);
    if (shop) {
      if (!this.hud.padMode) lines.push('<div class="tt-hint">Click to buy</div>');
      tip.innerHTML = lines.join('');
      return this._placeTip(anchor);
    }
    if (this.game.merchant.current && !def.quest && !loc.startsWith('s:') && !this.hud.padMode) {
      lines.push('<div class="tt-hint">Right-click to sell</div>');
      tip.innerHTML = lines.join('');
      return this._placeTip(anchor);
    }
    const action = loc.startsWith('e:') || loc.startsWith('s:') ? 'Right-click to unequip' : def.slot ? 'Right-click to equip' : def.kind === 'consumable' ? 'Right-click to drink' : def.kind === 'document' ? 'Right-click to read' : def.kind === 'bag' ? 'Right-click to place in a bag slot' : '';
    if (action && !this.hud.padMode) lines.push(`<div class="tt-hint">${action}</div>`);
    tip.innerHTML = lines.join('');
    this._placeTip(anchor);
  }

  _placeTip(anchor) {
    const tip = this.el.tooltip;
    tip.hidden = false;
    const r = anchor.getBoundingClientRect();
    const tw = tip.offsetWidth;
    const th = tip.offsetHeight;
    let x = r.left - tw - 8;
    if (x < 8) x = r.right + 8;
    let y = Math.min(window.innerHeight - th - 8, Math.max(8, r.top));
    if (anchor.classList.contains('aslot')) {
      // spell bar: above the slot
      x = Math.min(window.innerWidth - tw - 8, Math.max(8, r.left + r.width / 2 - tw / 2));
      y = r.top - th - 8;
    }
    tip.style.transform = `translate(${x}px, ${y}px)`;
  }

  // ------------------------------------------------------------- mouse drag
  _iconForLoc(loc) {
    if (loc.startsWith('a:')) return this.hud.abilityIcons[this.game.actionBar.slots[+loc.slice(2)]];
    if (loc.startsWith('k:')) return this.hud.abilityIcons[loc.slice(2)];
    const stack = this.game.inventory.get(loc);
    return stack && this._iconFor(stack.id);
  }

  _down(e) {
    if (e.button !== 0) return;
    const slot = e.target.closest && e.target.closest('.islot, .aslot');
    if (!slot) return;
    const loc = slot.dataset.loc;
    if (loc.startsWith('a:')) {
      e.preventDefault();
      if (this.game.actionBar.slots[+loc.slice(2)]) this.drag = { from: loc, x0: e.clientX, y0: e.clientY, moved: false };
      return;
    }
    if (loc.startsWith('k:')) {
      e.preventDefault();
      this.drag = { from: loc, x0: e.clientX, y0: e.clientY, moved: false };
      return;
    }
    if (loc === 's:0') {
      this.toggleBag(0);
      return;
    }
    if (loc.startsWith('m:') || loc.startsWith('y:') || loc.startsWith('q:')) {
      e.preventDefault();
      this._shopClick(loc);
      return;
    }
    if (!this.game.inventory.get(loc)) {
      if (loc.startsWith('s:')) this.toggleBag(+loc.slice(2));
      return;
    }
    e.preventDefault();
    this.drag = { from: loc, x0: e.clientX, y0: e.clientY, moved: false };
  }

  _move(e) {
    if (!this.drag) return;
    if (!this.drag.moved && Math.hypot(e.clientX - this.drag.x0, e.clientY - this.drag.y0) < 4) return;
    if (!this.drag.moved) {
      this.drag.moved = true;
      this.el.ghost.querySelector('img').src = this._iconForLoc(this.drag.from) || '';
      this.el.ghost.hidden = false;
      this.el.tooltip.hidden = true;
      document.body.classList.add('dragging');
    }
    this.el.ghost.style.transform = `translate(${e.clientX - 20}px, ${e.clientY - 20}px)`;
  }

  _up(e) {
    if (!this.drag) return;
    const d = this.drag;
    this.drag = null;
    this.el.ghost.hidden = true;
    document.body.classList.remove('dragging');
    const bar = this.game.actionBar;
    if (!d.moved) {
      // a plain click: a bag in its socket opens that bag; a spell is cast
      if (d.from.startsWith('s:')) this.toggleBag(+d.from.slice(2));
      if (d.from.startsWith('a:')) bar.clicked.add(bar.slots[+d.from.slice(2)]);
      return;
    }
    const under = document.elementFromPoint(e.clientX, e.clientY);
    if (under && under.closest('#shop-window') && this.game.merchant.current && !d.from.startsWith('a:') && !d.from.startsWith('k:')) {
      this.game.merchant.sell(d.from);
      return;
    }
    const target = under && under.closest('.islot, .aslot');
    const to = target && target.dataset.loc;
    this.dropOn(d.from, to, !!(under && under.closest('#action-bar')), !!(under && under.closest('.window, .modal, #bottom-bar, #objective, #char-panel')));
  }

  // Shared by mouse and gamepad: put whatever is at `from` onto `to`.
  dropOn(from, to, overBar = false, overWindow = false) {
    const bar = this.game.actionBar;
    const inv = this.game.inventory;
    if (from.startsWith('a:') || from.startsWith('k:')) {
      const ability = from.startsWith('a:') ? bar.slots[+from.slice(2)] : from.slice(2);
      if (to && to.startsWith('a:')) {
        if (from.startsWith('a:')) bar.move(+from.slice(2), +to.slice(2));
        else bar.place(ability, +to.slice(2));
      } else if (from.startsWith('a:') && !overBar) {
        bar.remove(+from.slice(2)); // dragged off the bar
        this.game.events.emit('log', { text: `${ABILITIES[ability].name} removed from the bar. Open the spellbook (P) to put it back.`, kind: 'muted', throttle: 'bar-removed' });
      }
      return;
    }
    if (to && to.startsWith('a:')) {
      // a draught dragged from the bags onto the bar
      const stack = inv.get(from);
      if (stack && stack.id === ABILITIES.draught.item) bar.place('draught', +to.slice(2));
      return;
    }
    if (to && !to.startsWith('k:')) {
      if (to !== 's:0') inv.move(from, to);
      return;
    }
    // released over the world rather than a window: drop it on the ground
    if (!overWindow) this.game.loot.dropFromInventory(from);
  }

  // ------------------------------------------------------------- gamepad
  _visibleLocs() {
    return [...document.querySelectorAll('#shop-window .islot, #bags-window .islot, #character-window .islot, #spellbook-window .islot, #bag-sockets .islot, #action-bar .aslot')]
      .filter((el) => el.offsetParent !== null && el.dataset.loc !== 's:0')
      .map((el) => el.dataset.loc);
  }

  _defaultFocus(which) {
    const locs = this._visibleLocs();
    const pick = (prefix) => locs.find((l) => l.startsWith(prefix));
    if (which === 'character' && this.open.character) return 'e:mainHand';
    if (which === 'spellbook' && this.open.spellbook) return pick('k:');
    if (which === 'shop' && this.game.merchant.current) return pick('q:') || pick('m:');
    return pick('b:') || (this.open.character && 'e:mainHand') || pick('k:') || pick('a:') || null;
  }

  _paintFocus() {
    document.querySelectorAll('.islot.focus').forEach((el) => el.classList.remove('focus'));
    if (!this.focus || !this.hud.padMode) return;
    const el = document.querySelector(`[data-loc="${this.focus}"]`);
    if (el) {
      el.classList.add('focus');
      this._tooltip(this.focus, el);
    }
  }

  _step(dir) {
    const current = document.querySelector(`[data-loc="${this.focus}"]`);
    const locs = this._visibleLocs();
    if (!current) {
      this.focus = locs[0] || null;
      return;
    }
    const r0 = current.getBoundingClientRect();
    const c0 = { x: r0.left + r0.width / 2, y: r0.top + r0.height / 2 };
    const v = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }[dir];
    let best = null;
    let bestScore = Infinity;
    for (const loc of locs) {
      if (loc === this.focus) continue;
      const r = document.querySelector(`[data-loc="${loc}"]`).getBoundingClientRect();
      const dx = r.left + r.width / 2 - c0.x;
      const dy = r.top + r.height / 2 - c0.y;
      const along = dx * v[0] + dy * v[1];
      if (along <= 4) continue;
      const across = Math.abs(dx * v[1] - dy * v[0]);
      const score = along + across * 2.5;
      if (score < bestScore) {
        bestScore = score;
        best = loc;
      }
    }
    if (best) this.focus = best;
  }

  // Called each frame while a panel is open and a gamepad is in use.
  gamepad(pad, dt) {
    const inv = this.game.inventory;
    const dir = pad.navDirection(dt);
    if (dir) this._step(dir);
    if (pad.pressed(BUTTONS.LB) || pad.pressed(BUTTONS.RB)) {
      // cycle the highlight between the open windows and the spell bar
      const groups = ['m:', 'b:', 'e:', 'k:', 'a:'].filter((p) => this._visibleLocs().some((l) => l.startsWith(p)));
      const cur = groups.findIndex((p) => this.focus && this.focus.startsWith(p));
      const next = groups[(cur + (pad.pressed(BUTTONS.LB) ? groups.length - 1 : 1)) % groups.length];
      if (next) this.focus = next === 'e:' ? 'e:mainHand' : this._visibleLocs().find((l) => l.startsWith(next));
    }
    const bar = this.game.actionBar;
    const isSpell = (l) => l && (l.startsWith('a:') || l.startsWith('k:'));
    const hasThing = (l) => (l.startsWith('a:') ? !!bar.slots[+l.slice(2)] : l.startsWith('k:') ? true : !!inv.get(l));
    const shopLoc = (l) => l && (l.startsWith('m:') || l.startsWith('y:') || l.startsWith('q:'));
    if (pad.pressed(BUTTONS.A) && shopLoc(this.focus) && !this.carry) {
      this._shopClick(this.focus);
    } else if (pad.pressed(BUTTONS.A) && this.focus && !shopLoc(this.focus)) {
      if (this.carry) {
        if (this.carry !== this.focus) this.dropOn(this.carry, this.focus, isSpell(this.focus) && this.focus.startsWith('a:'), true);
        this.carry = null;
      } else if (hasThing(this.focus)) {
        this.carry = this.focus;
      }
      this.render();
    }
    if (pad.pressed(BUTTONS.X) && this.focus && !isSpell(this.focus) && !shopLoc(this.focus)) {
      this.carry = null;
      inv.use(this.focus);
    }
    if (pad.pressed(BUTTONS.Y)) {
      const loc = this.carry || this.focus;
      this.carry = null;
      if (loc && loc.startsWith('a:')) bar.remove(+loc.slice(2));
      else if (loc && !isSpell(loc) && inv.get(loc) && this.game.merchant.current) this.game.merchant.sell(loc);
      else if (loc && !isSpell(loc) && inv.get(loc)) this.game.loot.dropFromInventory(loc);
      this.render();
    }
    if (pad.pressed(BUTTONS.B)) {
      if (this.carry) {
        this.carry = null;
        this.render();
      } else this.closeAll();
    }
    this._paintFocus();
  }
}
