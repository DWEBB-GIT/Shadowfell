// Money, WoW style: the purse holds silver, shown as gold and silver
// (100 silver = 1 gold, converted automatically). Prices in the data are
// in silver too. Other currencies (reputation tokens and the like) will
// sit beside this later.

export const SILVER_PER_GOLD = 100;

export const splitMoney = (n) => ({ gold: Math.floor(Math.max(0, n) / SILVER_PER_GOLD), silver: Math.max(0, n) % SILVER_PER_GOLD });

// "1 gold 20 silver", "35 silver" (for the log and plain text)
export function moneyText(n) {
  const { gold, silver } = splitMoney(n);
  const parts = [];
  if (gold) parts.push(`${gold} gold`);
  if (silver || !gold) parts.push(`${silver} silver`);
  return parts.join(' ');
}

// "1 (gold coin) 20 (silver coin)" with coin icons, for the UI
export function moneyHTML(n) {
  const { gold, silver } = splitMoney(n);
  let html = '';
  if (gold) html += `<span class="money"><b>${gold}</b><span class="coin gold" title="Gold"></span></span>`;
  if (silver || !gold) html += `<span class="money"><b>${silver}</b><span class="coin silver" title="Silver"></span></span>`;
  return `<span class="purse">${html}</span>`;
}

// Coins in the data are a whole number, or a range { min, max } rolled
// when they are handed over (a chest holding 0 to 150 silver).
export const coinRange = (c) => (typeof c === 'object' && c ? [c.min ?? 0, c.max ?? c.min ?? 0] : [c || 0, c || 0]);

export function rollCoins(c, rand = Math.random) {
  const [lo, hi] = coinRange(c);
  return hi > lo ? lo + Math.floor(rand() * (hi - lo + 1)) : lo;
}

// moneyHTML for a fixed amount or "min � max"
export function coinsHTML(c) {
  const [lo, hi] = coinRange(c);
  return lo === hi ? moneyHTML(lo) : `${moneyHTML(lo)} � ${moneyHTML(hi)}`;
}
