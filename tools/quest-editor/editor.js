// Quest editor: lists every quest in data/quests.json, edits one at a time
// with dropdowns built from the other data files (npcs, enemies, items,
// examine points, locations, factions), draws the quest chains, and runs the
// same checks as `npm run validate` on every change. Save writes
// data/quests.json through tools/server.mjs; without the server it downloads
// the file instead.
import { validateGameData } from '../../src/data/schema.js';

const $ = (sel, root = document) => root.querySelector(sel);
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === false) continue;
    if (k === 'class') n.className = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else if (k === 'value') n.value = v;
    else n.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) if (kid !== null && kid !== undefined && kid !== false) n.append(kid.nodeType ? kid : String(kid));
  return n;
};

let raw = {};
let quests = [];
let ref = {};
let selected = null;
let view = 'edit';
let dirty = false;
let errors = [];
const unsaved = new Set(); // ids of quests created since the last save: only these can be renamed
let canSave = true;

// ---------- loading

async function load() {
  let texts;
  try {
    const res = await fetch('/api/data');
    if (!res.ok) throw new Error();
    texts = await res.json();
  } catch {
    // opened without tools/server.mjs: read the files directly, save by download
    canSave = false;
    const names = ['abilities', 'archetypes', 'dialogue', 'enemies', 'factions', 'items', 'loot_tables', 'npcs', 'quests', 'rarities', 'recipes', 'scenery', 'shops', 'skills', 'text', 'world'];
    texts = {};
    await Promise.all(names.map(async (n) => (texts[`${n}.json`] = await (await fetch(`../../data/${n}.json`)).text())));
  }
  raw = Object.fromEntries(Object.entries(texts).map(([f, t]) => [f, JSON.parse(t)]));
  quests = raw['quests.json'].quests;
  buildRefs();
  selected = quests[0]?.id || null;
  validate();
  render();
}

function buildRefs() {
  const list = (arr, label = (r) => r.name || r.id) => (arr || []).map((r) => ({ v: r.id, l: label(r) }));
  const rarity = Object.fromEntries((raw['rarities.json'].rarities || []).map((r) => [r.id, r.colour]));
  ref = {
    npcs: list(raw['npcs.json'].npcs, (n) => `${n.name}${n.title ? ' (' + n.title + ')' : ''}`),
    enemies: list(raw['enemies.json'].enemies, (e) => `${e.name} (lvl ${e.level})`),
    items: list(raw['items.json'].items, (i) => `${i.name}${i.quest ? ' [quest]' : ''}`),
    examine: Object.keys(raw['text.json'].examine || {}).map((k) => ({ v: k, l: k })),
    locations: list(raw['world.json'].locations),
    factions: list(raw['factions.json'].factions),
    itemColour: Object.fromEntries((raw['items.json'].items || []).map((i) => [i.id, rarity[i.rarity] || '#ccc'])),
  };
}

const nameOf = (kind, id) => ref[kind].find((o) => o.v === id)?.l || id;
const questById = (id) => quests.find((q) => q.id === id);
const current = () => questById(selected);

// ---------- checks

function validate() {
  errors = validateGameData(raw);
  const badge = $('#checks-badge');
  badge.textContent = errors.length ? `${errors.length} problem${errors.length > 1 ? 's' : ''}` : 'All checks pass';
  badge.className = 'badge ' + (errors.length ? 'bad' : 'ok');
}
const questErrors = (id) => errors.filter((e) => e.startsWith(`quests.json ${id}:`) || e.startsWith(`quests.json ${id} `));

function changed() {
  dirty = true;
  $('#dirty').textContent = 'Unsaved changes';
  validate();
  renderList();
  renderSide();
}

// ---------- list

function renderList() {
  const box = $('#quest-list');
  const term = $('#search').value.trim().toLowerCase();
  const match = (q) => !term || JSON.stringify(q).toLowerCase().includes(term) || nameOf('npcs', q.giver).toLowerCase().includes(term);
  const groups = {};
  for (const q of quests.filter(match)) (groups[q.giver] ||= []).push(q);
  box.replaceChildren(
    ...Object.entries(groups).flatMap(([giver, qs]) => [
      el('div', { class: 'group-head' }, nameOf('npcs', giver)),
      ...qs.map((q) =>
        el('div', { class: 'qitem' + (q.id === selected ? ' sel' : ''), onclick: () => select(q.id) },
          el('span', { class: 'dot' + (questErrors(q.id).length ? ' bad' : '') }),
          el('span', {}, q.name || q.id),
          unsaved.has(q.id) && el('span', { class: 'new' }, 'new'),
        ),
      ),
    ]),
  );
  if (!box.children.length) box.append(el('div', { class: 'hint' }, 'No quest matches.'));
}

function select(id) {
  selected = id;
  setView('edit');
  render();
}

// ---------- form helpers. Each writes straight into the quest object; an
// empty optional field removes its key so the JSON stays tidy.

function setOrDelete(obj, key, v, keepEmpty) {
  if ((v === '' || v === undefined || v === null || v === false) && !keepEmpty) delete obj[key];
  else obj[key] = v;
}
function textField(label, obj, key, { multiline, wide, required, hint, readonly, oninput } = {}) {
  const input = el(multiline ? 'textarea' : 'input', { value: obj[key] ?? '', readonly, rows: multiline ? 3 : undefined });
  input.addEventListener('input', () => {
    setOrDelete(obj, key, input.value, required);
    oninput?.(input.value);
    changed();
  });
  return el('label', { class: 'field' + (wide || multiline ? ' wide' : '') }, el('span', {}, label), input, hint && el('div', { class: 'hint' }, hint));
}
function numberField(label, obj, key, { min = 0, keepEmpty } = {}) {
  const input = el('input', { type: 'number', min, step: 1, value: obj[key] ?? '' });
  input.addEventListener('input', () => {
    setOrDelete(obj, key, input.value === '' ? '' : Math.round(Number(input.value)), keepEmpty);
    changed();
  });
  return el('label', { class: 'field' }, el('span', {}, label), input);
}
function selectInput(options, value, onchange, { empty } = {}) {
  const s = el('select', {}, empty !== undefined && el('option', { value: '' }, empty), ...options.map((o) => el('option', { value: o.v }, o.l)));
  if (value !== undefined && !options.some((o) => o.v === value) && value !== '') s.prepend(el('option', { value }, `${value} (missing!)`));
  s.value = value ?? '';
  s.addEventListener('change', () => onchange(s.value));
  return s;
}
function selectField(label, obj, key, options, { empty, rerender } = {}) {
  return el('label', { class: 'field' }, el('span', {}, label),
    selectInput(options, obj[key], (v) => {
      setOrDelete(obj, key, v, empty === undefined);
      changed();
      if (rerender) renderEdit();
    }, { empty }));
}
function checkField(label, obj, key, { rerender } = {}) {
  const box = el('input', { type: 'checkbox' });
  box.checked = !!obj[key];
  box.addEventListener('change', () => {
    setOrDelete(obj, key, box.checked);
    changed();
    if (rerender) renderEdit();
  });
  return el('label', { class: 'field check' }, box, el('span', {}, label));
}

// ---------- edit view

const TARGETS = { kill: 'enemies', collect: 'items', examine: 'examine' };
const TARGET_LABEL = { kill: 'Enemy type', collect: 'Item', examine: 'Examine point' };

function renderEdit() {
  const pane = $('#edit-view');
  const q = current();
  if (!q) return pane.replaceChildren(el('p', { class: 'hint' }, 'No quest selected. Press New quest to write one.'));
  const isNew = unsaved.has(q.id);
  const others = quests.filter((o) => o.id !== q.id).map((o) => ({ v: o.id, l: o.name || o.id }));
  q.objectives ||= [];
  q.reward ||= {};

  pane.replaceChildren(
    el('h2', {}, q.name || q.id),
    el('div', { class: 'sub' }, `Given by ${nameOf('npcs', q.giver)} · handed in to ${nameOf('npcs', q.turnIn)}`),

    el('h3', {}, 'Basics'),
    el('div', { class: 'grid' },
      textField('Name', q, 'name', { required: true, oninput: (v) => ($('#edit-view h2').textContent = v || q.id) }),
      textField('Id', q, 'id', {
        required: true,
        readonly: !isNew,
        hint: isNew ? 'lower_snake_case. Locked once saved, because saves store it.' : 'Locked: saves store quest ids.',
        oninput: (v) => {
          unsaved.delete(selected);
          unsaved.add(v);
          selected = v;
        },
      }),
      selectField('Giver', q, 'giver', ref.npcs, { rerender: true }),
      selectField('Hand in to', q, 'turnIn', ref.npcs, { rerender: true }),
      checkField('Auto accept (starts without an offer)', q, 'autoAccept'),
    ),
    el('div', { class: 'field wide', style: 'margin-top:10px' }, el('span', { class: 'hint' }, 'Requires (offered once all of these are done)'),
      el('div', { class: 'chips' }, ...(q.requires || []).map((r) =>
        el('span', { class: 'chip' }, el('a', { class: 'qlink', onclick: () => select(r) }, questById(r)?.name || `${r} (missing!)`),
          el('button', { title: 'Remove', onclick: () => { q.requires = q.requires.filter((x) => x !== r); if (!q.requires.length) delete q.requires; changed(); renderEdit(); } }, '×')))),
      selectInput(others.filter((o) => !(q.requires || []).includes(o.v)), '', (v) => { if (!v) return; (q.requires ||= []).push(v); changed(); renderEdit(); }, { empty: '+ add a required quest' }),
    ),

    el('h3', {}, 'What they say'),
    el('div', { class: 'grid' },
      textField('Summary (quest log)', q, 'summary', { multiline: true, required: true }),
      textField('Offer (when giving the quest)', q, 'offer', { multiline: true }),
      textField('Progress (while it is active)', q, 'progress', { multiline: true, required: true }),
      textField('Complete (on hand-in)', q, 'complete', { multiline: true, required: true }),
      textField('Hand-in log line (optional)', q, 'turnInLog', { wide: true }),
    ),

    el('h3', {}, 'Objectives'),
    ...q.objectives.map((o, i) => objectiveCard(q, o, i)),
    el('div', { class: 'actions' }, el('button', { onclick: () => { q.objectives.push({ id: `objective_${q.objectives.length + 1}`, type: 'kill', target: ref.enemies[0]?.v, count: 1, label: '' }); changed(); renderEdit(); } }, '+ Add objective')),

    el('h3', {}, 'Reward'),
    el('div', { class: 'grid' }, numberField('Coins', q.reward, 'coins', { keepEmpty: true }), numberField('XP', q.reward, 'xp', { keepEmpty: true })),
    el('div', { class: 'hint', style: 'margin:10px 0 4px' }, 'Items'),
    ...(q.reward.items || []).map((it, i) => el('div', { class: 'inline-row' },
      selectInput(ref.items, it.item, (v) => { it.item = v; changed(); }),
      (() => { const n = el('input', { type: 'number', min: 1, value: it.count ?? 1 }); n.addEventListener('input', () => { it.count = Math.max(1, Math.round(+n.value || 1)); changed(); }); return n; })(),
      el('button', { class: 'small danger', onclick: () => { q.reward.items.splice(i, 1); if (!q.reward.items.length) delete q.reward.items; changed(); renderEdit(); } }, 'Remove'),
    )),
    el('button', { class: 'small', onclick: () => { (q.reward.items ||= []).push({ item: ref.items[0]?.v, count: 1 }); changed(); renderEdit(); } }, '+ Add item'),
    el('div', { class: 'hint', style: 'margin:12px 0 4px' }, 'Reputation'),
    ...Object.entries(q.reward.reputation || {}).map(([f, n]) => el('div', { class: 'inline-row' },
      selectInput(ref.factions, f, (v) => { const rep = q.reward.reputation; const val = rep[f]; delete rep[f]; rep[v] = val; changed(); renderEdit(); }),
      (() => { const inp = el('input', { type: 'number', step: 50, value: n }); inp.addEventListener('input', () => { q.reward.reputation[f] = Math.round(+inp.value || 0); changed(); }); return inp; })(),
      el('button', { class: 'small danger', onclick: () => { delete q.reward.reputation[f]; if (!Object.keys(q.reward.reputation).length) delete q.reward.reputation; changed(); renderEdit(); } }, 'Remove'),
    )),
    el('button', { class: 'small', onclick: () => { const rep = (q.reward.reputation ||= {}); const free = ref.factions.find((f) => !(f.v in rep)); if (free) rep[free.v] = 250; changed(); renderEdit(); } }, '+ Add reputation'),

    el('h3', {}, 'After hand-in'),
    el('div', { class: 'grid' }, textField('Sets flag (optional)', q, 'setsFlag', { hint: 'A name dialogue and the world can check, e.g. manifest_delivered.' })),

    el('div', { class: 'actions', style: 'margin-top:28px' },
      el('button', { onclick: () => newQuest({ requires: [q.id], giver: q.giver, turnIn: q.turnIn }) }, '+ Follow-up quest'),
      el('button', { onclick: duplicateQuest }, 'Duplicate'),
      el('button', { class: 'danger', onclick: deleteQuest }, 'Delete quest'),
    ),
  );
}

function objectiveCard(q, o, i) {
  const kind = TARGETS[o.type] || 'enemies';
  return el('div', { class: 'row-card' },
    el('div', { class: 'row-head' }, `Objective ${i + 1}`,
      el('button', { class: 'small danger', onclick: () => { q.objectives.splice(i, 1); changed(); renderEdit(); } }, 'Remove')),
    el('div', { class: 'grid' },
      el('label', { class: 'field' }, el('span', {}, 'Type'),
        selectInput([{ v: 'kill', l: 'Kill' }, { v: 'collect', l: 'Collect' }, { v: 'examine', l: 'Examine' }], o.type, (v) => {
          o.type = v;
          o.target = ref[TARGETS[v]][0]?.v;
          if (v === 'examine') delete o.count;
          if (v !== 'collect') delete o.keep;
          changed();
          renderEdit();
        })),
      selectField(TARGET_LABEL[o.type] || 'Target', o, 'target', ref[kind]),
      o.type !== 'examine' && numberField('Count', o, 'count', { min: 1 }),
      selectField('Map area (optional)', o, 'location', ref.locations, { empty: 'none' }),
      textField('Label (shown in the tracker)', o, 'label', { wide: true, required: true }),
      textField('Objective id', o, 'id', { required: true }),
      o.type === 'collect' && checkField('Player keeps the item on hand-in', o, 'keep'),
    ),
  );
}

// ---------- side panel: checks, connections, reward preview

function dialogueMentions(id) {
  const out = [];
  for (const d of raw['dialogue.json'].dialogues || []) {
    const walk = (node) => {
      if (Array.isArray(node)) return node.forEach(walk);
      if (!node || typeof node !== 'object') return;
      if (node.when?.quest === id) out.push({ npc: d.id, text: node.text || node.prompt || node.id, status: node.when.status });
      for (const [k, v] of Object.entries(node)) if (k !== 'when') walk(v);
    };
    walk(d);
  }
  return out;
}

function renderSide() {
  const pane = $('#side-pane');
  const q = current();
  if (!q) return pane.replaceChildren();
  const mine = questErrors(q.id);
  const elsewhere = errors.filter((e) => !mine.includes(e));
  const leadsTo = quests.filter((o) => (o.requires || []).includes(q.id));
  const talk = dialogueMentions(q.id);
  const nodes = (raw['world.json'].placedLoot || []).filter((p) => p.quest === q.id);
  const r = q.reward || {};
  pane.replaceChildren(el('div', { class: 'side' },
    el('h4', {}, 'Checks'),
    mine.length ? el('ul', {}, ...mine.map((e) => el('li', { class: 'err' }, e.replace(`quests.json ${q.id}`, '').replace(/^[: ]+/, '')))) : el('div', { class: 'ok' }, 'This quest passes every check.'),
    elsewhere.length > 0 && el('details', {}, el('summary', { class: 'err' }, `${elsewhere.length} problem(s) elsewhere`), el('ul', {}, ...elsewhere.map((e) => el('li', { class: 'err' }, e)))),

    el('h4', {}, 'Reward preview'),
    el('div', { class: 'reward-card' },
      el('div', {}, el('span', { class: 'coins' }, `${typeof r.coins === 'object' && r.coins ? `${r.coins.min}–${r.coins.max}` : r.coins || 0} coins`), ` · ${r.xp || 0} XP`),
      ...(r.items || []).map((it) => el('div', { style: `color:${ref.itemColour[it.item] || '#ccc'}` }, `${it.count > 1 ? it.count + ' × ' : ''}${nameOf('items', it.item)}`)),
      ...Object.entries(r.reputation || {}).map(([f, n]) => el('div', { class: 'hint' }, `+${n} ${nameOf('factions', f)}`)),
    ),

    el('h4', {}, 'Needs first'),
    (q.requires || []).length ? el('ul', {}, ...q.requires.map((id) => el('li', {}, el('a', { class: 'qlink', onclick: () => select(id) }, questById(id)?.name || id)))) : el('div', { class: 'hint' }, 'Nothing: offered from the start.'),
    el('h4', {}, 'Unlocks'),
    leadsTo.length ? el('ul', {}, ...leadsTo.map((o) => el('li', {}, el('a', { class: 'qlink', onclick: () => select(o.id) }, o.name)))) : el('div', { class: 'hint' }, 'No quest follows this one yet.'),
    el('h4', {}, 'Mentioned in dialogue'),
    talk.length ? el('ul', {}, ...talk.map((t) => el('li', {}, `${nameOf('npcs', t.npc)}${t.status ? ' (' + t.status + ')' : ''}: `, el('span', { class: 'quote' }, `"${t.text}"`)))) : el('div', { class: 'hint' }, 'No dialogue line checks this quest.'),
    nodes.length > 0 && el('h4', {}, 'Gathering nodes in the world'),
    nodes.length > 0 && el('div', { class: 'hint' }, `${nodes.length} × ${nameOf('items', nodes[0].item)} (${nodes.map((n) => n.id).join(', ')})`),
  ));
}

// ---------- chain map: each quest chain on its own band, prerequisites to
// the left, the quests they unlock to the right.

function renderMap() {
  const pane = $('#map-view');
  const W = 200, H = 52, GX = 70, GY = 18, PAD = 20;
  const byId = Object.fromEntries(quests.map((q) => [q.id, q]));
  const depth = {};
  const depthOf = (id, seen = []) => {
    if (depth[id] !== undefined) return depth[id];
    if (seen.includes(id)) return 0;
    const reqs = (byId[id]?.requires || []).filter((r) => byId[r]);
    return (depth[id] = reqs.length ? 1 + Math.max(...reqs.map((r) => depthOf(r, [...seen, id]))) : 0);
  };
  quests.forEach((q) => depthOf(q.id));
  // connected chains
  const parent = Object.fromEntries(quests.map((q) => [q.id, q.id]));
  const find = (x) => (parent[x] === x ? x : (parent[x] = find(parent[x])));
  quests.forEach((q) => (q.requires || []).filter((r) => byId[r]).forEach((r) => (parent[find(r)] = find(q.id))));
  const chains = {};
  quests.forEach((q) => (chains[find(q.id)] ||= []).push(q));
  const linked = Object.values(chains).filter((c) => c.length > 1);
  const single = Object.values(chains).filter((c) => c.length === 1).map((c) => c[0]);

  const pos = {};
  const bands = [];
  let y = PAD;
  for (const chain of linked) {
    bands.push({ y, label: `${nameOf('npcs', chain[0].giver)} chain` });
    y += 22;
    const cols = {};
    chain.forEach((q) => (cols[depth[q.id]] ||= []).push(q));
    const rows = Math.max(...Object.values(cols).map((c) => c.length));
    for (const [d, qs] of Object.entries(cols)) qs.forEach((q, i) => (pos[q.id] = { x: PAD + d * (W + GX), y: y + i * (H + GY) }));
    y += rows * (H + GY) + 18;
  }
  if (single.length) {
    bands.push({ y, label: 'Standalone quests' });
    y += 22;
    const perRow = 3;
    single.forEach((q, i) => (pos[q.id] = { x: PAD + (i % perRow) * (W + GX), y: y + Math.floor(i / perRow) * (H + GY) }));
    y += Math.ceil(single.length / perRow) * (H + GY);
  }
  const width = Math.max(...Object.values(pos).map((p) => p.x + W), 600) + PAD;
  const NS = 'http://www.w3.org/2000/svg';
  const s = (tag, attrs, ...kids) => {
    const n = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
    kids.forEach((k) => n.append(k));
    return n;
  };
  const svg = s('svg', { width, height: y + PAD, viewBox: `0 0 ${width} ${y + PAD}` });
  svg.append(s('defs', {}, s('marker', { id: 'arrow', viewBox: '0 0 10 10', refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: 'auto' }, s('path', { d: 'M0,0 L10,5 L0,10 z', fill: '#6d6250' }))));
  bands.forEach((b) => svg.append(s('text', { class: 'band', x: PAD, y: b.y + 12 }, b.label)));
  for (const q of quests) for (const r of q.requires || []) {
    const a = pos[r], b = pos[q.id];
    if (!a || !b) continue;
    const x1 = a.x + W, y1 = a.y + H / 2, x2 = b.x - 2, y2 = b.y + H / 2, mx = (x1 + x2) / 2;
    svg.append(s('path', { class: 'edge', d: `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`, 'marker-end': 'url(#arrow)' }));
  }
  for (const q of quests) {
    const p = pos[q.id];
    const trim = (t, n) => (t.length > n ? t.slice(0, n - 1) + '…' : t);
    const g = s('g', { class: 'node' + (q.id === selected ? ' sel' : '') + (questErrors(q.id).length ? ' bad' : ''), transform: `translate(${p.x},${p.y})` },
      s('rect', { width: W, height: H }),
      s('text', { class: 't', x: 10, y: 21 }, trim(q.name || q.id, 26)),
      s('text', { class: 's', x: 10, y: 39 }, trim(`${nameOf('npcs', q.giver)} · ${q.objectives?.length || 0} objective(s) · ${q.reward?.xp || 0} XP`, 34)));
    g.addEventListener('click', () => select(q.id));
    svg.append(g);
  }
  pane.replaceChildren(el('div', { class: 'hint', style: 'margin-bottom:10px' }, 'Arrows run from a quest to the quests it unlocks. Click a quest to edit it.'), svg);
}

// ---------- actions

function newQuest(base = {}) {
  let n = 1;
  while (questById(`new_quest_${n}`)) n++;
  const id = `new_quest_${n}`;
  const q = {
    id,
    name: 'New quest',
    giver: base.giver || ref.npcs[0]?.v,
    turnIn: base.turnIn || base.giver || ref.npcs[0]?.v,
    ...(base.requires ? { requires: base.requires } : {}),
    summary: '',
    offer: '',
    progress: '',
    complete: '',
    objectives: [{ id: 'objective_1', type: 'kill', target: ref.enemies[0]?.v, count: 1, label: '' }],
    reward: { coins: 0, xp: 0 },
  };
  quests.push(q);
  unsaved.add(id);
  changed();
  select(id);
}

function duplicateQuest() {
  const src = current();
  let n = 2;
  while (questById(`${src.id}_${n}`)) n++;
  const copy = JSON.parse(JSON.stringify(src));
  copy.id = `${src.id}_${n}`;
  copy.name = `${src.name} (copy)`;
  quests.splice(quests.indexOf(src) + 1, 0, copy);
  unsaved.add(copy.id);
  changed();
  select(copy.id);
}

function deleteQuest() {
  const q = current();
  const warn = unsaved.has(q.id) ? '' : '\n\nThis quest has been saved before, so players may have it in their saves. The usual rule is to stop offering a shipped quest rather than delete it.';
  if (!confirm(`Delete "${q.name}"?${warn}`)) return;
  quests.splice(quests.indexOf(q), 1);
  unsaved.delete(q.id);
  selected = quests[0]?.id || null;
  changed();
  render();
}

// JSON.stringify with 2-space indents, keeping short lists and objects of
// plain values on one line, as the hand-written files do.
function pretty(value, indent = '') {
  const inner = indent + '  ';
  if (Array.isArray(value) || (value && typeof value === 'object')) {
    const entries = Array.isArray(value) ? value.map((v) => [null, v]) : Object.entries(value);
    if (!entries.length) return Array.isArray(value) ? '[]' : '{}';
    const depth = (v) => (v && typeof v === 'object' ? 1 + Math.max(0, ...Object.values(v).map(depth)) : 0);
    const leaf = depth(value) <= 1 || (Array.isArray(value) && depth(value) <= 2);
    const inline = (v) => (Array.isArray(v) ? `[${v.map(inline).join(', ')}]` : v && typeof v === 'object' ? `{ ${Object.entries(v).map(([k, x]) => JSON.stringify(k) + ': ' + inline(x)).join(', ')} }` : JSON.stringify(v));
    const one = inline(value);
    if (leaf && one.length + indent.length < 90 && !one.includes('\\n')) return one;
    const body = entries.map(([k, v]) => inner + (k === null ? '' : JSON.stringify(k) + ': ') + pretty(v, inner));
    return Array.isArray(value) ? `[\n${body.join(',\n')}\n${indent}]` : `{\n${body.join(',\n')}\n${indent}}`;
  }
  return JSON.stringify(value);
}

async function save() {
  const bad = errors.length;
  if (bad && !confirm(`${bad} check(s) fail. The game build will refuse this data until they are fixed. Save anyway?`)) return;
  const text = pretty(raw['quests.json']) + '\n';
  if (canSave) {
    const res = await fetch('/api/data/quests.json', { method: 'PUT', body: text }).catch(() => null);
    if (res?.ok) {
      unsaved.clear();
      dirty = false;
      $('#dirty').textContent = '';
      renderList();
      if (current()) renderEdit();
      return toast('Saved data/quests.json');
    }
    toast('Could not reach the editor server, downloading instead');
  }
  const a = el('a', { href: URL.createObjectURL(new Blob([text], { type: 'application/json' })), download: 'quests.json' });
  a.click();
  dirty = false;
  $('#dirty').textContent = '';
  toast('Downloaded quests.json: put it in the data folder');
}

function toast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 2600);
}

function setView(v) {
  view = v;
  document.querySelectorAll('.views button').forEach((b) => b.classList.toggle('on', b.dataset.view === v));
  $('#edit-view').hidden = v !== 'edit';
  $('#map-view').hidden = v !== 'map';
  if (v === 'map') renderMap();
}

function render() {
  renderList();
  renderEdit();
  renderSide();
  if (view === 'map') renderMap();
}

document.querySelectorAll('.views button').forEach((b) => b.addEventListener('click', () => setView(b.dataset.view)));
$('#search').addEventListener('input', renderList);
$('#new-quest').addEventListener('click', () => newQuest());
$('#save').addEventListener('click', save);
$('#checks-badge').addEventListener('click', () => errors.length && document.querySelector('#side-pane details')?.setAttribute('open', ''));
addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === 's') {
    e.preventDefault();
    save();
  }
});
addEventListener('beforeunload', (e) => {
  if (dirty) e.preventDefault();
});

load().catch((err) => {
  $('#edit-view').replaceChildren(el('p', { class: 'err' }, `Could not load the data: ${err.message}`), el('p', { class: 'hint' }, 'Start the editor with `npm run editor` in the Shadowfell folder, then open the address it prints.'));
});
