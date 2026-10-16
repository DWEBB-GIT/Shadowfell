// Mouse cursors drawn as small SVGs (see Game._cursorFor). The hotspot is
// the tip at the top left. Grey versions mean "too far away".

const svg = (body, hot = '2 2') => `url("data:image/svg+xml;utf8,${encodeURIComponent(`<svg xmlns='http://www.w3.org/2000/svg' width='28' height='28' viewBox='0 0 28 28'>${body}</svg>`)}") ${hot}, auto`;

const sword = (blade, hilt) => svg(`<path d='M2 2 L6 2 L19 15 L15 19 L2 6 Z' fill='${blade}' stroke='#000' stroke-width='1.2'/><path d='M13 21 L21 13 L23 15 L15 23 Z' fill='${hilt}' stroke='#000'/><path d='M18 20 L24 26 L26 24 L20 18 Z' fill='${hilt}' stroke='#000'/>`);
const speech = (fill) => svg(`<path d='M3 3 H25 V18 H12 L6 24 V18 H3 Z' fill='${fill}' stroke='#000' stroke-width='1.5'/><circle cx='9' cy='10.5' r='1.6'/><circle cx='14' cy='10.5' r='1.6'/><circle cx='19' cy='10.5' r='1.6'/>`);
const hand = (fill) => svg(`<path d='M8 13 V5 a2 2 0 0 1 4 0 V12 V4 a2 2 0 0 1 4 0 V12 V5 a2 2 0 0 1 4 0 V13 V8 a2 2 0 0 1 4 0 V17 c0 5 -3 8 -8 8 h-2 c-4 0 -6 -3 -8 -6 l-3 -5 a2 2 0 0 1 3 -2 Z' fill='${fill}' stroke='#000' stroke-width='1.2'/>`);

// a fishing hook (over the bob): the hotspot is its point
const hook = svg(`<g fill='none' stroke-linecap='round'><path d='M19 6 V18 a6 6 0 0 1 -12 0 V12 L4 15' stroke='#000' stroke-width='4.5'/><path d='M19 6 V18 a6 6 0 0 1 -12 0 V12 L4 15' stroke='#d8dce0' stroke-width='2.2'/><circle cx='19' cy='4' r='2.4' stroke='#000' stroke-width='3.5'/><circle cx='19' cy='4' r='2.4' stroke='#d8dce0' stroke-width='1.6'/></g>`, '7 11');

export const CURSORS = {
  fish: hook,
  attack: sword('#e8e8f0', '#c89a3a'),
  talk: speech('#f0e4c8'),
  talkFar: speech('#7a7a7a'),
  loot: hand('#f0d070'),
  lootFar: hand('#7a7a7a'),
};
