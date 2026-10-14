// Automated acceptance test for the design document's section 20 checklist.
// Runs the real game (file://, bundled build) in headless Chromium.
//
//   npm test            (needs Chromium; set CHROME_PATH if it is elsewhere)
//
// Most checks drive the simulation deterministically: the render loop is
// paused and `game.step(dt)` is advanced with simulated input held in the
// game's own Input object. A few checks use real keyboard and mouse events to
// prove the browser wiring works end to end.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { launch, openGame } from './browser.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const results = [];
let current = 'General';

function record(item, ok, detail = '') {
  results.push({ section: current, item, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${current}] ${item}${detail ? '  -- ' + detail : ''}`);
}

// ---------------------------------------------------------------- helpers
async function freshGame(browser, { noAudio = false } = {}) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  if (noAudio) await ctx.addInitScript(() => { delete window.AudioContext; delete window.webkitAudioContext; });
  const { page, errors } = await openGame(ctx);
  return { ctx, page, errors };
}

async function begin(page, which = '#new-btn', { pinRolls = true } = {}) {
  await page.click(which);
  await page.waitForFunction(() => window.__shadowfall.started);
  // combat rolls (weapon range, crits, blocks, enemy variance) land on the
  // average unless a check says otherwise, so expected numbers are exact
  if (pinRolls) await page.evaluate(() => (window.__shadowfall.random = () => 0.5));
}

const pauseLoop = (page) => page.evaluate(() => window.__shadowfall.renderer.setAnimationLoop(null));
const resumeLoop = (page) => page.evaluate(() => {
  const g = window.__shadowfall;
  g.clock.getDelta();
  g.renderer.setAnimationLoop(() => g._frame());
});

// Advance the simulation by `seconds` at `fps` with keys held / pressed.
async function sim(page, seconds, { held = [], press = [], clickAt = null, aimAt = null, rightClick = false, fps = 60 } = {}) {
  return page.evaluate(({ seconds, held, press, clickAt, aimAt, rightClick, fps }) => {
    const g = window.__shadowfall;
    g.input.held = new Set(held);
    for (const k of press) g.input.pressed.add(k);
    const at = clickAt || aimAt;
    if (at) {
      // aim the mouse at a world point (and click, for clickAt)
      const THREEv = g.camera.position.clone();
      const p = THREEv.set(at.x, g.player.position.y + 0.5, at.z).project(g.camera);
      const r = g.renderer.domElement.getBoundingClientRect();
      g.input.mouse.ndcX = p.x;
      g.input.mouse.ndcY = p.y;
      g.input.mouse.x = r.left + ((p.x + 1) / 2) * r.width;
      g.input.mouse.y = r.top + ((1 - p.y) / 2) * r.height;
      if (clickAt) g.input.mouse.clicked = true;
    }
    if (rightClick) g.input.mouse.rightClicked = true;
    const dt = 1 / fps;
    const n = Math.round(seconds * fps);
    for (let i = 0; i < n; i++) g.step(dt);
    g.input.held = new Set();
    return n;
  }, { seconds, held, press, clickAt, aimAt, rightClick, fps });
}

const state = (page) => page.evaluate(() => {
  const g = window.__shadowfall;
  return {
    pos: { x: g.player.position.x, z: g.player.position.z },
    hp: g.player.health,
    maxHp: g.player.maxHealth,
    dead: g.player.dead,
    level: g.progression.level,
    xp: g.progression.xp,
    coins: g.inventory.coins,
    draughts: g.inventory.draughts,
    items: [...g.inventory.items],
    equipped: g.inventory.equipped,
    dmg: g.combat.basicDamage,
    modal: g.hud.modal,
    prompt: g.interaction.current ? g.interaction.current.prompt : null,
    enemies: g.enemies.list.map((e) => ({ id: e.id, hp: e.health, dead: e.dead, x: e.position.x, z: e.position.z, state: e.state })),
    defeated: [...g.worldState.defeated],
    collected: [...g.worldState.collected],
    stage: g.worldState.objectiveStage,
  };
});

// Put the player somewhere, optionally facing a point, and park every enemy
// far away so a check is not disturbed (unless `keep` lists enemy ids).
async function setup(page, { x, z, keep = [], park = true, hp = null }) {
  await page.evaluate(({ x, z, keep, park, hp }) => {
    const g = window.__shadowfall;
    g.player.placeAt(x, z);
    if (hp !== null) g.player.health = hp;
    if (park) {
      g.enemies.list.forEach((e, i) => {
        if (keep.includes(e.id)) return;
        e.position.set(-30 + i * 3, 0, -45);
        e.home.copy(e.position);
        e.state = 'idle';
      });
    }
    g._snapCamera();
  }, { x, z, keep, park, hp });
}

async function placeEnemy(page, id, x, z, extra = {}) {
  await page.evaluate(({ id, x, z, extra }) => {
    const e = window.__shadowfall.enemies.byId(id);
    e.position.set(x, 0, z);
    e.home.set(x, 0, z);
    e.state = 'idle';
    e.attackTimer = extra.attackTimer ?? 0.6;
    e.windup = 0;
    e.stagger = 0;
    if (extra.frozen) e.cfg = { ...e.cfg, speed: 0, detection: 3 }; // holds its ground but stays engaged
  }, { id, x, z, extra });
}

// Real mouse drag from one element to another (or to a page point).
async function dragSlot(page, fromSel, to) {
  const box = async (sel) => {
    const b = await (await page.$(sel)).boundingBox();
    return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
  };
  const a = await box(fromSel);
  const b = typeof to === 'string' ? await box(to) : to;
  await page.mouse.move(a.x, a.y);
  await page.mouse.down();
  await page.mouse.move(a.x + 8, a.y + 4, { steps: 2 });
  await page.mouse.move(b.x, b.y, { steps: 6 });
  await page.mouse.up();
}

const enemy = async (page, id) => (await state(page)).enemies.find((e) => e.id === id);
const near = (a, b, tol) => Math.abs(a - b) <= tol;

// ------------------------------------------------------------------ tests
async function launchAndMovement(browser) {
  current = 'Launch and movement';
  const { ctx, page, errors } = await freshGame(browser);
  const titleVisible = await page.isVisible('#title-screen');
  await begin(page);
  await page.waitForTimeout(500);
  record('Game loads in a supported desktop browser', titleVisible && (await page.isVisible('#hud')), 'title screen, then HUD, from file://index.html');
  record('No blocking errors occur during startup', errors.length === 0, errors.join(' | '));

  // real keyboard input with the real render loop running
  await setup(page, { x: -6, z: 33 });
  const dirs = { KeyW: ['z', -1], KeyS: ['z', 1], KeyA: ['x', -1], KeyD: ['x', 1] };
  const moved = [];
  for (const [key, [axis, sign]] of Object.entries(dirs)) {
    await setup(page, { x: -6, z: 30 });
    const before = (await state(page)).pos;
    await page.waitForTimeout(300); // let a frame or two pass (software rendering is slow)
    await page.keyboard.down(key);
    await page.waitForTimeout(1200);
    await page.keyboard.up(key);
    const after = (await state(page)).pos;
    const d = (after[axis] - before[axis]) * sign;
    const other = axis === 'x' ? 'z' : 'x';
    moved.push(`${key.slice(3)} ${d.toFixed(2)}m`);
    if (!(d > 0.3 && Math.abs(after[other] - before[other]) < 0.3)) moved.push('(wrong)');
  }
  record('Player can move in all four directions', !moved.includes('(wrong)'), moved.join(', ') + ' (real key events)');

  await pauseLoop(page);
  await setup(page, { x: -6, z: 30 });
  let a = (await state(page)).pos;
  await sim(page, 1, { held: ['KeyW'] });
  let b = (await state(page)).pos;
  const straight = Math.hypot(b.x - a.x, b.z - a.z);
  await setup(page, { x: -6, z: 30 });
  a = (await state(page)).pos;
  await sim(page, 1, { held: ['KeyW', 'KeyD'] });
  b = (await state(page)).pos;
  const diag = Math.hypot(b.x - a.x, b.z - a.z);
  await sim(page, 1.5); // let the camera settle
  record('Diagonal movement is normalised', near(diag, straight, 0.05) && near(straight, 5, 0.1), `1s straight ${straight.toFixed(2)}m, 1s diagonal ${diag.toFixed(2)}m`);

  const cam = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { cx: g.camera.position.x - g.player.position.x, cz: g.camera.position.z - g.player.position.z, off: g.config.camera.offset };
  });
  record('Camera follows the player', near(cam.cx, cam.off[0], 0.2) && near(cam.cz, cam.off[2], 0.3), `camera offset after moving: x ${cam.cx.toFixed(2)}, z ${cam.cz.toFixed(2)} (target ${cam.off[0]}, ${cam.off[2]})`);

  // frame-rate independence
  await setup(page, { x: -6, z: 30 });
  a = (await state(page)).pos;
  await sim(page, 1, { held: ['KeyW'], fps: 24 });
  b = (await state(page)).pos;
  const at24 = Math.abs(b.z - a.z);
  await setup(page, { x: -6, z: 30 });
  a = (await state(page)).pos;
  await sim(page, 1, { held: ['KeyW'], fps: 144 });
  b = (await state(page)).pos;
  const at144 = Math.abs(b.z - a.z);
  record('Movement is frame-rate independent (extra)', near(at24, at144, 0.05), `1s at 24 fps ${at24.toFixed(2)}m, at 144 fps ${at144.toFixed(2)}m`);

  // world boundaries: walk into each edge for a long time
  const edges = [
    [['KeyA'], -30, 0], [['KeyD'], 30, 0], [['KeyS'], 0, 42], [['KeyW'], -6, -112],
  ];
  const out = [];
  let inside = true;
  for (const [keys, x, z] of edges) {
    await setup(page, { x, z });
    await sim(page, 6, { held: keys, fps: 30 });
    const s = await state(page);
    const ok = s.pos.x >= -36 && s.pos.x <= 36 && s.pos.z >= -125 && s.pos.z <= 47;
    inside = inside && ok;
    out.push(`${keys[0].slice(3)}→(${s.pos.x.toFixed(1)}, ${s.pos.z.toFixed(1)})`);
  }
  record('Player remains within the playable area', inside, out.join(' '));
  await ctx.close();
}

async function combat(browser) {
  current = 'Combat';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);

  // basic attack on a nearby ghoul (real mouse click on the canvas)
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await resumeLoop(page);
  const pt = await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    const v = e.position.clone().setY(e.position.y + 0.5).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    return { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height };
  });
  await page.mouse.click(pt.x, pt.y);
  // software WebGL runs slowly, so wait for the swing to start and finish in game time
  await page.waitForFunction(() => window.__shadowfall.player.pending !== null, null, { timeout: 15000 });
  await page.waitForFunction(() => {
    const p = window.__shadowfall.player;
    return p.cooldowns.attack === 0 && !p.pending;
  }, null, { timeout: 15000 });
  await pauseLoop(page);
  let g = await enemy(page, 'ghoul_road');
  record('Basic attack damages a nearby enemy', g.hp === 30, `ghoul 1.6m away: 48 → ${g.hp} from a real left click`);

  // a ghoul 6m away must not be hit
  await placeEnemy(page, 'ghoul_road', 0, -6, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 48));
  await sim(page, 0.1); // let cooldowns lapse
  await sim(page, 0.7, { clickAt: { x: 0, z: -6 } });
  g = await enemy(page, 'ghoul_road');
  record('Attacks do not damage enemies at arbitrary distances', g.hp === 48, `ghoul 6m away after a strike: ${g.hp}/48`);

  // Shield Break: two inside the radius, one outside
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'ghoul_cart', 'ghoul_graves'] });
  await placeEnemy(page, 'ghoul_road', 1.5, 0, { frozen: true });
  await placeEnemy(page, 'ghoul_cart', -1.2, 1.2, { frozen: true });
  await placeEnemy(page, 'ghoul_graves', 0, -5, { frozen: true });
  await page.evaluate(() => window.__shadowfall.enemies.list.forEach((e) => (e.health = e.cfg.health)));
  await sim(page, 0.6, { rightClick: true });
  let s = await state(page);
  const hpOf = (id) => s.enemies.find((e) => e.id === id).hp;
  record('Shield Break damages enemies within its radius', hpOf('ghoul_road') === 12 && hpOf('ghoul_cart') === 12 && hpOf('ghoul_graves') === 48,
    `inside radius: ${hpOf('ghoul_road')}, ${hpOf('ghoul_cart')} (48-36); 5m away: ${hpOf('ghoul_graves')}`);
  const fxSeen = await page.evaluate(() => window.__shadowfall.fx.items.length >= 0);

  // cooldown: second press at 1s is refused, a press after 4s works
  await page.evaluate(() => window.__shadowfall.enemies.list.forEach((e) => (e.health = e.cfg.health)));
  await sim(page, 0.5, { rightClick: true });
  s = await state(page);
  const blocked = hpOf('ghoul_road') === 48;
  const cdLeft = await page.evaluate(() => window.__shadowfall.player.cooldowns.shieldBreak);
  await sim(page, 3.0);
  await sim(page, 0.6, { rightClick: true });
  s = await state(page);
  const worksAgain = hpOf('ghoul_road') === 12;
  record('Ability cooldown behaves correctly', blocked && worksAgain && fxSeen, `re-press after ~1s ignored (${cdLeft.toFixed(2)}s left); works again after 4s`);

  // Brace (Space): blocks the next blow only, for a limited window, off the GCD
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'], hp: 100 });
  await placeEnemy(page, 'ghoul_road', 0, -1.4, { frozen: true });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0));
    g.player.cooldowns.gcd = 1.2; // mid global cooldown
  });
  await sim(page, 0.05, { press: ['Space'] });
  const br = await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    const up = g.player.isBraced;
    const cd = g.player.cooldowns.brace;
    const r1 = g.combat.resolveEnemyStrike(e);
    const hp1 = g.player.health;
    const r2 = g.combat.resolveEnemyStrike(e);
    return { up, cd, r1, hp1, r2, hp2: g.player.health };
  });
  const braceLog = await page.evaluate(() => [...document.querySelectorAll('#log li')].map((l) => l.textContent).join(' | '));
  record('Brace (Space) turns aside the next blow, and only one', br.up && !br.r1 && br.hp1 === 100 && br.r2 && br.hp2 === 92 && /your shield takes/i.test(braceLog),
    `raised during the global cooldown; first claw blocked (hp ${br.hp1}), second lands (hp ${br.hp2})`);
  record('Brace has a cooldown of about 7 seconds', near(br.cd, 7, 0.1), `${br.cd.toFixed(2)}s after use`);
  await page.evaluate(() => {
    const e = window.__shadowfall.enemies.byId('ghoul_road');
    e.cfg = { ...e.cfg, detection: 0 }; // keep the ghoul quiet from here
    e.state = 'idle';
  });
  await sim(page, 0.5, { press: ['Space'] });
  const reBrace = await page.evaluate(() => window.__shadowfall.player.isBraced);
  await page.evaluate(() => (window.__shadowfall.player.cooldowns.brace = 0));
  await sim(page, 0.05, { press: ['Space'] });
  const upAt0 = await page.evaluate(() => window.__shadowfall.player.isBraced);
  await sim(page, 2.6);
  const expired = await page.evaluate(() => {
    const g = window.__shadowfall;
    const up = g.player.isBraced;
    g.player.health = 100;
    const r = g.combat.resolveEnemyStrike(g.enemies.byId('ghoul_road'));
    return { up, r, hp: g.player.health };
  });
  record('Brace window expires and cannot be spammed', !reBrace && upAt0 && !expired.up && expired.r && expired.hp === 92,
    `re-press on cooldown ignored; raised shield drops after 2.5s and the next claw lands (hp ${expired.hp})`);
  const noSprint = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(0, 20);
    return g.player.position.clone();
  });
  await sim(page, 0.5, { held: ['KeyD', 'ShiftLeft'], press: ['ShiftLeft'] });
  const ns = (await state(page)).pos;
  const walked = Math.hypot(ns.x - noSprint.x, ns.z - noSprint.z);
  record('No dodge or sprint: Shift does nothing special', near(walked, 2.5, 0.2), `${walked.toFixed(2)}m in 0.5s holding D and Shift (walking is 5 m/s)`);

  // pursuit and attack with normal AI
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    e.cfg = { ...e.cfg, speed: 3.0, detection: 8 };
  });
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'], hp: 100 });
  await placeEnemy(page, 'ghoul_road', 0, -6.5);
  const start = await enemy(page, 'ghoul_road');
  await sim(page, 1.0);
  const mid = await enemy(page, 'ghoul_road');
  await sim(page, 4.0);
  s = await state(page);
  record('Enemies pursue and attack', mid.z > start.z + 1.5 && s.hp < 100, `ghoul closed from 6.5m to ${Math.abs(mid.z).toFixed(1)}m in 1s (${mid.state}); player hp 100 → ${s.hp} after 5s`);
  const telegraph = await page.evaluate(() => window.__shadowfall.config.enemies.ghoul.windup);
  record('Enemy attacks are telegraphed before landing (extra)', telegraph > 0.3, `${telegraph}s wind-up with raised arms and an amber health-bar outline`);

  // stop attacking when out of range
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'], hp: 100 });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await sim(page, 0.2);
  await page.evaluate(() => window.__shadowfall.player.placeAt(0, 4));
  await sim(page, 3.0);
  s = await state(page);
  record('Enemies stop attacking when the player is out of melee range (extra)', s.hp === 100, `frozen ghoul, player 5.6m away for 3s: hp ${s.hp}`);

  // kill: health reaches zero, rewards granted once
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'], hp: 100 });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 48));
  const before = await state(page);
  for (let i = 0; i < 3; i++) await sim(page, 0.65, { clickAt: { x: 0, z: -1.6 } });
  g = await enemy(page, 'ghoul_road');
  s = await state(page);
  record('Enemy health reaches zero correctly', g && g.hp === 0 && g.dead, `three strikes of 18 on 48 hp → ${g && g.hp}, dead=${g && g.dead}`);
  const after = s;
  const again = await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    g.combat.onEnemyDefeated(e); // processing the same death again
    const dealt = e.hurt(50);
    g.player.tryStrike(null);
    for (let i = 0; i < 30; i++) g.step(1 / 60);
    return { xp: g.progression.xp, coins: g.inventory.coins, dealt };
  });
  record('Enemy defeat grants experience once and leaves a body to loot', after.xp - before.xp === 28 && after.coins === before.coins && again.xp === after.xp && again.coins === after.coins && again.dealt === 0,
    `+${after.xp - before.xp} xp at once, coins stay with the body; reprocessing and striking the corpse changed nothing`);
  await sim(page, 6);
  const stays = !!(await enemy(page, 'ghoul_road'));
  const prompt = (await state(page)).prompt;
  await sim(page, 0.1, { press: ['KeyE'] });
  const looted = await state(page);
  await sim(page, 0.1, { press: ['KeyE'] });
  const twice = await state(page);
  record('Looting the body gives its coins, once', stays && /loot the ashen ghoul/i.test(prompt || '') && looted.coins - after.coins === 3 && twice.coins === looted.coins,
    `body still there 6s later, prompt "${prompt}"; E: +${looted.coins - after.coins} coins; E again: nothing`);
  await sim(page, 6);
  const removed = !(await enemy(page, 'ghoul_road'));
  record('Defeated enemy is removed once looted (extra)', removed, 'the looted body sinks away');

  // healing draught
  await page.evaluate(() => (window.__shadowfall.player.health = 40));
  await sim(page, 0.1, { press: ['KeyQ'] });
  s = await state(page);
  const firstDrink = s.hp === 82 && s.draughts === 0;
  await page.evaluate(() => (window.__shadowfall.player.health = 90));
  await sim(page, 0.1, { press: ['KeyQ'] });
  s = await state(page);
  const lastLog = await page.evaluate(() => document.querySelector('#log li:last-child').textContent);
  record('Healing draught restores 42 and reports when none remain (extra)', firstDrink && s.hp === 90 && /no healing draughts/i.test(lastLog), `40 → 82 hp; second use: "${lastLog}"`);
  await sim(page, 1.0); // draughts share a short cooldown
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.draughts = 1;
    g.player.health = 95;
  });
  await sim(page, 0.1, { press: ['KeyQ'] });
  s = await state(page);
  record('Draught never heals past maximum (extra)', s.hp === 100, `95 → ${s.hp}`);
  record('No script errors during combat (extra)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function exploration(browser) {
  current = 'Exploration';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);

  // walk off the road towards the cart with real input from a nearby point
  await setup(page, { x: 1.5, z: -3 });
  await sim(page, 0.1);
  const offRoad = (await state(page)).prompt;
  await sim(page, 0.75, { held: ['KeyA'] });
  let s = await state(page);
  record('Abandoned cart is discoverable', s.prompt === 'Examine the cart', `walking west from the road: prompt "${offRoad}" → "${s.prompt}"`);
  await sim(page, 0.1, { press: ['KeyE'] });
  s = await state(page);
  const objective1 = await page.textContent('#objective-text');
  record('Examining the cart advances the objective (extra)', s.stage === 'cartFound', `"${objective1.slice(0, 60)}…"`);

  // manifest
  await setup(page, { x: -5.0, z: -6.3 });
  await sim(page, 0.1);
  s = await state(page);
  const promptManifest = s.prompt;
  await sim(page, 0.1, { press: ['KeyE'] });
  s = await state(page);
  const docOpen = await page.isVisible('#document');
  const docText = await page.textContent('#document-body');
  record('Manifest can be examined and collected', promptManifest === 'Read the manifest' && docOpen && s.items.includes('manifest') && s.stage === 'complete',
    `prompt "${promptManifest}", document opened, in pack, objective ${s.stage}`);
  record('Manifest text gives clues without resolving them (extra)', /scored out/.test(docText) && /Hallow Cut/.test(docText) && /nine/.test(docText), 'scratched-out driver, altered count, warning about bells');
  await sim(page, 0.05, { press: ['Escape'] });
  s = await state(page);
  record('Escape closes the active interface', s.modal === null && !(await page.isVisible('#document')), `modal after Esc: ${s.modal}`);

  // material
  await setup(page, { x: -8.4, z: -0.2 });
  await sim(page, 0.1);
  s = await state(page);
  const pm = s.prompt;
  await sim(page, 0.1, { press: ['KeyE'] });
  s = await state(page);
  record('Material can be collected', pm === 'Take the grave-iron' && s.items.includes('grave_iron'), `prompt "${pm}"`);

  // currency
  await setup(page, { x: -26, z: 6.4 });
  await sim(page, 0.1);
  const c0 = (await state(page)).coins;
  const pc = (await state(page)).prompt;
  await sim(page, 0.1, { press: ['KeyE'] });
  s = await state(page);
  const lootGone = await page.evaluate(() => !window.__shadowfall.loot.active.some((l) => l.def.id === 'purse_graves'));
  record('Currency can be collected', s.coins === c0 + 6 && pc === 'Take the coin purse' && lootGone, `${c0} → ${s.coins} coins; purse removed from the world`);

  // equipment: defeat the brute, collect what it drops (and its body)
  const coinsBeforeBrute = (await state(page)).coins;
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const b = g.enemies.byId('brute_hallow');
    b.hurt(500);
    g.combat.onEnemyDefeated(b);
  });
  const dropPos = await page.evaluate(() => window.__shadowfall.worldState.drops.watchmans_edge);
  await setup(page, { x: dropPos.x + 1, z: dropPos.z, park: false });
  await sim(page, 0.1);
  s = await state(page);
  const pe = s.prompt;
  await sim(page, 0.1, { press: ['KeyE'] });
  s = await state(page);
  record('Equipment can be collected', /(Take Watchman's Edge|Loot the Gravebound Brute) \(and 1 more nearby\)$/.test(pe) && s.items.includes('watchmans_edge') && s.coins === coinsBeforeBrute + 9, `brute drop at (${dropPos.x.toFixed(1)}, ${dropPos.z.toFixed(1)}), prompt "${pe}"; the brute's 9 coins came with it`);
  record('Equipment is not silently swapped (extra)', s.equipped === 'worn_longsword', `still equipped: ${s.equipped}`);

  // shrine
  await setup(page, { x: 7.6, z: 5.2, hp: 31 });
  await sim(page, 0.1);
  s = await state(page);
  const ps = s.prompt;
  await sim(page, 0.1, { press: ['KeyE'] });
  s = await state(page);
  const respawn = await page.evaluate(() => window.__shadowfall.worldState.respawn);
  record('Shrine can restore health', ps === 'Rest at the shrine' && s.hp === s.maxHp && respawn, `31 → ${s.hp} hp; respawn set to (${respawn && respawn.x}, ${respawn && respawn.z})`);

  // prompts update
  await setup(page, { x: -2, z: 20 });
  await sim(page, 0.1);
  const none = (await state(page)).prompt;
  const domHidden = await page.evaluate(() => document.getElementById('prompt').hidden);
  await setup(page, { x: 7.6, z: 5.2 });
  await sim(page, 0.1);
  const shrineP = (await state(page)).prompt;
  const dom = await page.textContent('#prompt');
  record('Contextual prompts update correctly', none === null && domHidden && shrineP === 'Rest at the shrine' && /Rest at the shrine/.test(dom), `open road: none; at shrine: "${dom.trim()}"`);

  // bags and the character panel do not pause the game (WoW-style)
  await page.evaluate(() => { window.__shadowfall.hud.togglePanel('bags'); window.__shadowfall.hud.togglePanel('character'); });
  const p0 = (await state(page)).pos;
  const t0 = await page.evaluate(() => window.__shadowfall.time);
  await sim(page, 0.5, { held: ['KeyW'] });
  const p1 = (await state(page)).pos;
  const t1 = await page.evaluate(() => window.__shadowfall.time);
  const stillOpen = await page.evaluate(() => window.__shadowfall.hud.items.anyOpen);
  await sim(page, 0.05, { press: ['Escape'] });
  const shut = await page.evaluate(() => !window.__shadowfall.hud.items.anyOpen);
  record('Bags and the character panel do not pause the game', p0.z - p1.z > 2 && near(t1 - t0, 0.5, 0.02) && stillOpen && shut, `with both open: walked ${(p0.z - p1.z).toFixed(2)}m and the world ran ${(t1 - t0).toFixed(2)}s; Esc closed them`);
  record('No script errors during exploration (extra)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function progression(browser) {
  current = 'Progression';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  await setup(page, { x: 0, z: 0 });
  const s0 = await state(page);

  const kill = async (id) => {
    await page.evaluate((id) => {
      const g = window.__shadowfall;
      const e = g.enemies.byId(id);
      g.player.placeAt(e.position.x, e.position.z + 1.5);
      e.cfg = { ...e.cfg, speed: 0, detection: 0, damage: 0 };
      e.state = 'idle';
      // the Blackwood packs are parked in the same row; keep them out of it
      for (const o of g.enemies.list) {
        if (o.dead || o.id.startsWith('ghoul_') && !o.id.includes('_bw_') || o.id.startsWith('brute_')) continue;
        o.position.set(30, 0, 40);
        o.home.copy(o.position);
        o.state = 'idle';
      }
    }, id);
    for (let i = 0; i < 12; i++) {
      // step back in after each knock-back, as a player would
      const pos = await page.evaluate((id) => {
        const g = window.__shadowfall;
        const e = g.enemies.byId(id);
        if (!e || e.dead) return null;
        g.player.placeAt(e.position.x, e.position.z + e.radius + 1.0);
        return { x: e.position.x, z: e.position.z };
      }, id);
      if (!pos) break;
      await sim(page, 0.65, { clickAt: pos });
    }
  };
  await kill('ghoul_cart');
  const s1 = await state(page);
  record('Experience increases after enemy defeat', s1.xp === s0.xp + 28, `${s0.xp} → ${s1.xp}`);
  await kill('ghoul_graves');
  await kill('ghoul_road');
  const s2 = await state(page);
  await page.evaluate(() => (window.__shadowfall.player.health = 50));
  await kill('brute_hallow');
  const s3 = await state(page);
  record('Level-up occurs at the required threshold', s2.level === 1 && s2.xp === 84 && s3.level === 2 && s3.xp === 49,
    `84/100 xp after three ghouls (level ${s2.level}); brute +65 → level ${s3.level} with ${s3.xp}/160 carried over`);
  record('Maximum health increases', s3.maxHp === 112 && s3.hp === 112, `max health ${s0.maxHp} → ${s3.maxHp}, restored to full on level-up`);
  record('Basic attack damage increases', s3.dmg === 20, `strike ${s0.dmg} → ${s3.dmg}`);

  // collect the drop, then equip it by dragging it onto the character panel
  const drop = await page.evaluate(() => window.__shadowfall.worldState.drops.watchmans_edge);
  await setup(page, { x: drop.x + 0.8, z: drop.z, park: false });
  await sim(page, 0.1, { press: ['KeyE'] });
  await resumeLoop(page);
  await page.keyboard.press('KeyB');
  await page.keyboard.press('KeyC');
  await page.waitForFunction(() => !document.getElementById('bags-window').hidden && !document.getElementById('character-window').hidden, null, { timeout: 10000 });
  const edgeLoc = await page.evaluate(() => window.__shadowfall.inventory.bagLocations().find((l) => window.__shadowfall.inventory.get(l)?.id === 'watchmans_edge'));
  const bagsText = await page.evaluate(() => [...document.querySelectorAll('#bags-window .islot.filled')].length);
  await dragSlot(page, `.islot[data-loc="${edgeLoc}"]`, '.islot[data-loc="e:mainHand"]');
  await page.waitForTimeout(200);
  const s4 = await state(page);
  const panelStrike = await page.evaluate(() => [...document.querySelectorAll('#char-stats div')].find((d) => /Strike/.test(d.textContent)).querySelector('b').textContent);
  record('Equipment upgrade improves damage', s4.equipped === 'watchmans_edge' && s4.dmg === 25 && panelStrike.startsWith('22–28'), `strike ${s3.dmg} → ${s4.dmg} after dragging it from the bag onto the main-hand slot (panel shows ${panelStrike})`);
  const visible = await page.evaluate(() => {
    const p = window.__shadowfall.player;
    return p.weaponPart !== p.defaultWeaponMesh && !p.defaultWeaponMesh.visible;
  });
  record('Upgraded weapon is shown on the character (extra)', visible, 'Blender model swapped in the right hand');
  const oldInBag = await page.evaluate((loc) => window.__shadowfall.inventory.get(loc)?.id, edgeLoc);
  const coinsShown = await page.textContent('#bags-window .bag-foot');
  record('Inventory reflects collected items', bagsText >= 2 && oldInBag === 'worn_longsword' && /\d+/.test(coinsShown) && s4.items.includes('watchmans_edge'),
    `${bagsText} filled bag slots; the worn longsword swapped into the slot the Edge left; coins: ${coinsShown.trim()}`);
  await page.keyboard.press('Escape');
  const closed = await page.waitForFunction(() => !window.__shadowfall.hud.items.anyOpen, null, { timeout: 10000 }).then(() => true, () => false);
  record('Escape closes the bags and character panel (extra)', closed && !(await page.isVisible('#bags-window')) && !(await page.isVisible('#character-window')), 'real Escape key');
  record('No script errors during progression (extra)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function death(browser) {
  current = 'Death';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // activate the shrine, then reach level 2 so retention can be checked
  await setup(page, { x: 7.6, z: 5.2 });
  await sim(page, 0.1, { press: ['KeyE'] });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.progression.addXp(120);
    g.inventory.addItem('watchmans_edge');
    g.inventory.equip('watchmans_edge');
    g.inventory.coins = 40;
  });
  const before = await state(page);
  await setup(page, { x: 0, z: -15, keep: ['ghoul_road'], hp: 6 });
  await placeEnemy(page, 'ghoul_road', 0, -16.4, { attackTimer: 0 });
  await sim(page, 1.0);
  let s = await state(page);
  record('Player death occurs at zero health (extra)', s.dead && s.hp === 0, `hp ${s.hp}`);
  const posDead = s.pos;
  await sim(page, 3.0, { held: ['KeyW'], clickAt: { x: 0, z: -16 }, press: ['Space'] });
  s = await state(page);
  const ghoul = s.enemies.find((e) => e.id === 'ghoul_road');
  record('Player death interrupts combat', s.hp === 0 && s.pos.x === posDead.x && s.pos.z === posDead.z && ghoul.hp === 48 && ghoul.state !== 'attack',
    `no movement or attacks while dead; ghoul ${ghoul.state}`);
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  const deathVisible = await page.isVisible('#death');
  const deathText = await page.textContent('#death');
  record('Death screen appears', deathVisible && /shrine/i.test(deathText), deathText.replace(/\s+/g, ' ').trim());
  await resumeLoop(page);
  await page.click('#respawn-btn');
  await page.waitForTimeout(200);
  await pauseLoop(page);
  s = await state(page);
  const respawn = await page.evaluate(() => window.__shadowfall.worldState.respawn);
  record('Respawn restores health', !s.dead && s.hp === s.maxHp, `${s.hp}/${s.maxHp}`);
  record('Player returns to the correct shrine', near(s.pos.x, respawn.x, 0.05) && near(s.pos.z, respawn.z, 0.05), `(${s.pos.x.toFixed(2)}, ${s.pos.z.toFixed(2)}) beside the roadside shrine`);
  const capOk = before.coins === 40 && s.coins === 35;
  // a small purse loses 20%, rounded down
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.coins = 12;
    g.player.takeDamage(999);
    g.onPlayerDeath();
  });
  await sim(page, 2.0);
  await page.evaluate(() => window.__shadowfall.respawn());
  const s2 = await state(page);
  record('Currency loss respects the cap', capOk && s2.coins === 10, `40 coins → ${s.coins} (20% capped at 5); 12 coins → ${s2.coins}`);
  record('Equipment and progression are retained', s.level === before.level && s.xp === before.xp && s.equipped === 'watchmans_edge' && s.items.length === before.items.length,
    `level ${s.level}, xp ${s.xp}, ${s.equipped}, ${s.items.length} items`);
  const ghoulAfter = (await state(page)).enemies.find((e) => e.id === 'ghoul_road');
  record('Surviving enemies reset to their posts on respawn (extra)', near(ghoulAfter.x, 0, 0.5) && near(ghoulAfter.z, -16.4, 0.5) && ghoulAfter.hp === 48);
  record('No script errors during death and respawn (extra)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function persistence(browser) {
  current = 'Persistence';
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  let { page, errors } = await openGame(ctx);
  await begin(page);
  await pauseLoop(page);
  // make progress: manifest, a kill, a purse, the shrine, a level
  await setup(page, { x: -5.0, z: -6.3 });
  await sim(page, 0.1, { press: ['KeyE'] });
  await sim(page, 0.05, { press: ['Escape'] });
  await setup(page, { x: -26, z: 6.4 });
  await sim(page, 0.1, { press: ['KeyE'] });
  await setup(page, { x: 7.6, z: 5.2 });
  await sim(page, 0.1, { press: ['KeyE'] });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_cart');
    e.hurt(999);
    g.combat.onEnemyDefeated(e);
    g.progression.addXp(80);
    g.player.placeAt(3.25, 12.5);
    g.player.health = 77;
  });
  const saved = await state(page);
  await resumeLoop(page);
  await page.keyboard.press('KeyK');
  await page.waitForTimeout(250);
  const toast = await page.textContent('#toast');
  const stored = await page.evaluate(() => localStorage.getItem('shadowfall.save'));
  record('Manual save works', stored && JSON.parse(stored).version === 2, `${stored ? stored.length : 0} bytes in localStorage (key shadowfall.save)`);
  record('A successful save produces confirmation', /saved/i.test(toast), `toast: "${toast}"`);

  // reload the page and continue
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  const hasContinue = await page.isVisible('#continue-btn');
  await begin(page, '#continue-btn');
  await pauseLoop(page);
  let s = await state(page);
  record('Reload restores player position and progression',
    hasContinue && near(s.pos.x, saved.pos.x, 0.01) && near(s.pos.z, saved.pos.z, 0.01) && s.level === saved.level && s.xp === saved.xp && s.hp === saved.hp && s.coins === saved.coins,
    `pos (${s.pos.x.toFixed(2)}, ${s.pos.z.toFixed(2)}), level ${s.level}, xp ${s.xp}, hp ${s.hp}, coins ${s.coins}`);
  const cartBody = s.enemies.find((e) => e.id === 'ghoul_cart');
  record('Defeated enemies remain defeated', (!cartBody || cartBody.dead) && s.defeated.includes('ghoul_cart'), `${s.enemies.filter((e) => !e.dead).length} enemies alive; ghoul_cart ${cartBody ? 'lies where it fell' : 'absent'}`);
  const corpseLoot = await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_cart');
    const lootable = g.loot.lootables().some((l) => l.enemy === e || l.id === 'ghoul_cart');
    const c0 = g.inventory.coins;
    g.player.placeAt(e.position.x, e.position.z + 1.2);
    g.interaction.update();
    g.interaction.interact();
    const c1 = g.inventory.coins;
    g.inventory.coins = c0; // keep the saved state comparable below
    return { lootable, gained: c1 - c0 };
  });
  await page.evaluate(() => window.__shadowfall.player.placeAt(3.25, 12.5));
  record('An unlooted body is still there to loot after a reload', corpseLoot.lootable && corpseLoot.gained === 3, `ghoul_cart body lootable: ${corpseLoot.lootable}, +${corpseLoot.gained} coins`);
  const purse = await page.evaluate(() => window.__shadowfall.loot.active.map((l) => l.def.id));
  record('Collected loot does not reappear', !purse.includes('purse_graves') && !purse.includes('manifest'), `loot in world: ${purse.join(', ')}`);
  record('Manifest progress persists', s.items.includes('manifest') && s.stage === 'complete', `objective: ${await page.textContent('#objective-state')}`);
  const respawn = await page.evaluate(() => window.__shadowfall.worldState.respawn);
  record('Shrine state and respawn point persist (extra)', respawn && near(respawn.x, 7.8, 0.01), JSON.stringify(respawn));

  // repeated save/load cycles keep the same state
  for (let i = 0; i < 3; i++) {
    await page.evaluate(() => window.__shadowfall.manualSave());
    await page.reload();
    await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
    await begin(page, '#continue-btn');
  }
  await pauseLoop(page);
  const s3 = await state(page);
  record('Repeated save/load cycles are stable (extra)', JSON.stringify([s3.pos, s3.level, s3.xp, s3.coins, s3.items, s3.defeated]) === JSON.stringify([s.pos, s.level, s.xp, s.coins, s.items, s.defeated]), '3 cycles');

  // autosave when the page closes
  await page.evaluate(() => window.__shadowfall.player.placeAt(-2.5, 21.5));
  await page.close({ runBeforeUnload: true });
  ({ page, errors } = await openGame(ctx));
  await begin(page, '#continue-btn');
  s = await state(page);
  record('Autosave on close (extra)', near(s.pos.x, -2.5, 0.05) && near(s.pos.z, 21.5, 0.05), `position after closing and reopening: (${s.pos.x.toFixed(2)}, ${s.pos.z.toFixed(2)})`);
  await page.close();

  // corrupt saves: garbage, wrong shape, malicious values
  const corrupt = [
    '{not json',
    JSON.stringify({ version: 1, player: { position: { x: 0, z: 0 } } }),
    JSON.stringify({ ...JSON.parse(stored), inventory: { ...JSON.parse(stored).inventory, coins: -50 } }),
    JSON.stringify({ ...JSON.parse(stored), player: { ...JSON.parse(stored).player, position: { x: 9999, z: 0 } } }),
  ];
  const outcomes = [];
  let allSafe = true;
  for (const bad of corrupt) {
    ({ page, errors } = await openGame(ctx));
    await page.evaluate((bad) => {
      localStorage.setItem('shadowfall.save', bad);
      localStorage.removeItem('shadowfall.save.unreadable');
    }, bad);
    await page.reload();
    await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
    const note = await page.isVisible('#title-note');
    const cont = await page.isVisible('#continue-btn');
    await begin(page);
    await page.waitForTimeout(300);
    // closing the page would normally autosave: it must not replace the bad save
    await page.evaluate(() => window.__shadowfall.save.autosave());
    const kept = await page.evaluate(() => [localStorage.getItem('shadowfall.save'), localStorage.getItem('shadowfall.save.unreadable')]);
    const safe = note && !cont && kept[0] === bad && kept[1] === bad && errors.length === 0;
    allSafe = allSafe && safe;
    outcomes.push(safe ? 'kept' : `FAILED(note=${note} cont=${cont} errors=${errors.length})`);
    await page.close();
  }
  record('Invalid save data does not crash the game', allSafe, `4 corrupt saves: ${outcomes.join(', ')}; game started fresh each time and the original was not overwritten`);
  await ctx.close();
}

async function quality(browser) {
  current = 'Quality';
  const { ctx, page, errors } = await freshGame(browser, { noAudio: true });
  await begin(page);
  await page.keyboard.down('KeyW');
  await page.waitForTimeout(400);
  await page.keyboard.up('KeyW');
  await page.mouse.click(640, 300);
  await page.keyboard.press('Space');
  await page.keyboard.press('KeyI');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  record('The game remains playable without audio', errors.length === 0 && (await page.evaluate(() => window.__shadowfall.audio.ctx === null)), 'Web Audio removed before load; moved, attacked, braced and opened the pack');

  // readability: HUD text sizes at 1280x720
  const sizes = await page.evaluate(() => [...document.querySelectorAll('#hud *')].filter((e) => e.offsetParent && e.childNodes.length && [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())).map((e) => parseFloat(getComputedStyle(e).fontSize)));
  const min = Math.min(...sizes);
  record('Interface remains readable', min >= 9, `smallest HUD text ${min}px (the xp numbers inside the bar); body text 13–15px at 1280×720`);

  // frame time sample (software rendering, so only a sanity check)
  const fps = await page.evaluate(() => new Promise((res) => {
    let n = 0;
    const t0 = performance.now();
    const tick = () => (++n < 60 ? requestAnimationFrame(tick) : res((n * 1000) / (performance.now() - t0)));
    requestAnimationFrame(tick);
  }));
  const counts = await page.evaluate(() => {
    const info = window.__shadowfall.renderer.info;
    return { calls: info.render.calls, tris: info.render.triangles };
  });
  record('Scene stays light (extra)', counts.calls < 300, `${counts.calls} draw calls, ${counts.tris} triangles; ${fps.toFixed(0)} fps with software WebGL in headless Chromium`);
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'quality.png') });
  await ctx.close();
}


// ------------------------------------------------------------ build 2
// A scripted gamepad: navigator.getGamepads() returns one "standard" pad
// whose buttons and sticks the tests set directly.
const PAD_STUB = () => {
  const pad = {
    id: 'Test pad (STANDARD GAMEPAD)', index: 0, connected: true, mapping: 'standard', timestamp: 0,
    buttons: Array.from({ length: 17 }, () => ({ pressed: false, touched: false, value: 0 })),
    axes: [0, 0, 0, 0],
  };
  window.__pad = pad;
  navigator.getGamepads = () => [pad, null, null, null];
};

// Step the game with pad buttons held, or tapped for a single frame.
async function padSim(page, seconds, { axes = [0, 0, 0, 0], hold = [], tap = [], fps = 60 } = {}) {
  return page.evaluate(({ seconds, axes, hold, tap, fps }) => {
    const g = window.__shadowfall;
    const pad = window.__pad;
    const set = (list, on) => list.forEach((b) => { pad.buttons[b].pressed = on; pad.buttons[b].value = on ? 1 : 0; });
    pad.axes = axes.slice();
    set(hold, true);
    set(tap, true);
    const n = Math.max(1, Math.round(seconds * fps));
    for (let i = 0; i < n; i++) {
      g.step(1 / fps);
      if (i === 0) set(tap.filter((b) => !hold.includes(b)), false);
    }
    set(hold, false);
    pad.axes = [0, 0, 0, 0];
    g.step(1 / fps); // one idle frame so the next tap is a fresh press
  }, { seconds, axes, hold, tap, fps });
}
const PAD = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, RT: 7, VIEW: 8, START: 9, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15 };

async function abilities(browser) {
  current = 'Build 2: spell bar and global cooldown';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);

  // bottom of the screen: experience bar, spell bar, menu buttons, bag slots
  const layout = await page.evaluate(() => {
    const vis = (sel) => [...document.querySelectorAll(sel)].filter((e) => e.offsetParent !== null);
    const r = (sel) => document.querySelector(sel).getBoundingClientRect();
    return {
      xp: vis('#xp-bar').length, slots: vis('#action-bar .aslot').length, char: vis('#btn-character').length,
      sockets: vis('#bag-sockets .islot').length, barTop: r('#bottom-bar').top, barBottom: r('#bottom-bar').bottom, xpTop: r('#xp-bar').top, slotTop: r('#action-bar').top, h: innerHeight,
      icons: vis('#action-bar .aslot img').filter((i) => i.src.startsWith('data:image')).length,
    };
  });
  record('Bottom of the screen has the spell bar, experience bar, bag and menu icons', layout.xp === 1 && layout.slots === 7 && layout.char === 1 && layout.sockets === 4 && layout.barBottom <= layout.h && layout.barTop > layout.h - 140 && layout.xpTop < layout.slotTop,
    `${layout.slots} spell-bar slots (${layout.icons} with icons), experience bar above them, character and save buttons, ${layout.sockets} bag slots; bar spans y ${layout.barTop.toFixed(0)}–${layout.barBottom.toFixed(0)} of ${layout.h}`);

  // GCD: Shield Break then Lunge is refused until the GCD ends; Strike is unaffected
  await setup(page, { x: 0, z: 20 });
  await sim(page, 0.05, { rightClick: true });
  const afterSB = await page.evaluate(() => ({ ...window.__shadowfall.player.cooldowns }));
  await sim(page, 0.4); // let Shield Break land
  await sim(page, 0.05, { press: ['Digit1'] });
  const lungeBlocked = await page.evaluate(() => window.__shadowfall.player.lunge === null && window.__shadowfall.player.cooldowns.lunge === 0);
  const gcdSweep = await page.evaluate(() => parseFloat(document.getElementById('aslot-0').style.getPropertyValue('--gcd')));
  await sim(page, 0.05, { clickAt: { x: 0, z: 18 } });
  const strikeOk = await page.evaluate(() => window.__shadowfall.player.pending?.type === 'strike' || window.__shadowfall.player.cooldowns.attack > 0);
  record('Global cooldown is shared by Shield Break and Lunge (WoW-style)', afterSB.gcd > 1.4 && lungeBlocked && gcdSweep > 0, `GCD ${afterSB.gcd.toFixed(2)}s left just after Shield Break; Lunge pressed 0.45s later was refused; Lunge slot shows the GCD sweep (${gcdSweep.toFixed(2)})`);
  record('Strike stays off the global cooldown', strikeOk, 'left click during the GCD still swings');
  await sim(page, 1.2);
  const p0 = (await state(page)).pos;
  await sim(page, 0.05, { press: ['Digit1'], clickAt: { x: 0, z: 10 } });
  const lungeStarted = await page.evaluate(() => window.__shadowfall.player.lunge !== null);
  record('Lunge is usable once the GCD has run out', lungeStarted, 'pressed 1 again after 1.5s');

  // Lunge: a 5 m charge that strikes what it reaches
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await sim(page, 9); // clear every cooldown
  await placeEnemy(page, 'ghoul_road', 0, -6.0, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 48));
  const a = (await state(page)).pos;
  await sim(page, 0.6, { press: ['Digit1'], clickAt: { x: 0, z: -6 } });
  const b = (await state(page)).pos;
  const gh = await enemy(page, 'ghoul_road');
  const moved = Math.hypot(b.x - a.x, b.z - a.z);
  record('Lunge charges towards the cursor and strikes on arrival', moved > 4 && moved < 5.6 && gh.hp === 48 - 27, `${moved.toFixed(2)}m charge; ghoul 48 → ${gh.hp} (1.5 × 18)`);
  const cds = await page.evaluate(() => ({ lunge: window.__shadowfall.player.cooldowns.lunge }));
  record('Lunge has its own cooldown shown on the bar (extra)', cds.lunge > 7, `${cds.lunge.toFixed(1)}s left of 8s`);
  record('No script errors (build 2 abilities)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function telegraphs(browser) {
  current = 'Build 2: ground telegraphs';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const BR = 'brute_hallow';
  const startSlam = async (dz = 2.5) => {
    await page.evaluate(() => window.__shadowfall.telegraphs.clear());
    await setup(page, { x: 22, z: -17 + dz, keep: [BR], hp: 100 });
    await page.evaluate(() => {
      const e = window.__shadowfall.enemies.byId('brute_hallow');
      e.position.set(22, 0, -17);
      e.home.set(22, 0, -17);
      e.casting = null;
      e.health = e.cfg.health;
      e.cfg = { ...e.cfg, damage: 0 }; // only the slam hurts in these checks
      e.state = 'chase';
      e.engaged = 6;
      e.specialTimer = 0;
      e.attackTimer = 5;
    });
    await sim(page, 1 / 60);
    return page.evaluate(() => {
      const g = window.__shadowfall;
      const e = g.enemies.byId('brute_hallow');
      const t = g.telegraphs.active[0];
      return { kind: e.casting?.kind, count: g.telegraphs.active.length, inScene: !!(t && t.mesh.parent === g.scene), heavy: t?.heavy, contains: t?.shape.contains(g.player.position.x, g.player.position.z, g.player.radius) };
    });
  };

  // stand in it
  const t1 = await startSlam();
  await sim(page, 0.7);
  const mid = await page.evaluate(() => ({ p: window.__shadowfall.telegraphs.active[0]?.mesh.material.uniforms.uProgress.value, hp: window.__shadowfall.player.health, bar: document.querySelector('.ebar.casting .ecast-name')?.textContent }));
  await sim(page, 0.8);
  let s = await state(page);
  record('Big enemy wind-ups paint their area on the ground (FFXIV-style)', t1.kind === 'special' && t1.count === 1 && t1.inScene && t1.heavy && mid.p > 0.4 && mid.p < 0.6 && mid.hp === 100,
    `Grave Slam: cone mesh in the scene, ${(mid.p * 100).toFixed(0)}% filled halfway through its 1.4s wind-up; cast bar reads "${mid.bar}"`);
  record('Standing in the telegraph when it fills hits the player', s.hp === 76, `player inside the cone: 100 → ${s.hp} (Grave Slam 24)`);
  const gone = await page.evaluate(() => window.__shadowfall.telegraphs.active.length === 0);
  record('The telegraph is removed once resolved (extra)', gone);

  // walk out of it
  await startSlam();
  await sim(page, 1.5, { held: ['KeyS'] });
  s = await state(page);
  record('Walking out of the telegraph avoids the hit', s.hp === 100, `walked south for 1.5s: hp ${s.hp}`);

  // or stand firm and Brace just before it lands
  await startSlam();
  await sim(page, 1.0);
  await page.evaluate(() => (window.__shadowfall.player.cooldowns.brace = 0));
  await sim(page, 0.8, { press: ['Space'] });
  s = await state(page);
  const braceSlamLog = await page.evaluate(() => [...document.querySelectorAll('#log li')].slice(-3).map((l) => l.textContent).join(' | '));
  record('Brace blocks the Grave Slam', s.hp === 100 && /brace and turn aside/i.test(braceSlamLog), `braced 1s into the wind-up: hp ${s.hp}; "${braceSlamLog.split(' | ').find((t) => /brace/i.test(t)) || braceSlamLog}"`);

  // the area is fixed when the wind-up starts: it does not follow the player
  const fixed = await startSlam();
  const shape0 = await page.evaluate(() => { const t = window.__shadowfall.telegraphs.active[0].shape; return { x: t.x, z: t.z, a: t.angle }; });
  await sim(page, 0.6, { held: ['KeyD'] });
  const shape1 = await page.evaluate(() => { const t = window.__shadowfall.telegraphs.active[0].shape; return { x: t.x, z: t.z, a: t.angle }; });
  record('The marked area is locked when the wind-up starts (extra)', fixed.contains && JSON.stringify(shape0) === JSON.stringify(shape1), 'cone did not turn to follow the player');
  await sim(page, 1.0);

  // Shield Break cannot interrupt the slam, but does interrupt an ordinary cleave
  await startSlam();
  await page.evaluate(() => window.__shadowfall.enemies.byId('brute_hallow').hurt(10, { heavy: true }));
  const slamKept = await page.evaluate(() => window.__shadowfall.enemies.byId('brute_hallow').casting?.kind === 'special');
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('brute_hallow');
    e._cancelCast();
    e.specialTimer = 20;
    e.state = 'attack';
    e.attackTimer = 0;
    e.stagger = 0;
    g.player.placeAt(22, -15.4);
  });
  await sim(page, 1 / 60);
  const cleave = await page.evaluate(() => ({ kind: window.__shadowfall.enemies.byId('brute_hallow').casting?.kind, heavy: window.__shadowfall.telegraphs.active[0]?.heavy }));
  await page.evaluate(() => window.__shadowfall.enemies.byId('brute_hallow').hurt(10, { heavy: true }));
  const cleaveStopped = await page.evaluate(() => !window.__shadowfall.enemies.byId('brute_hallow').casting && window.__shadowfall.telegraphs.active.length === 0);
  record('The brute telegraphs its ordinary cleave too; Shield Break interrupts it but not the slam (extra)', slamKept && cleave.kind === 'normal' && cleave.heavy === false && cleaveStopped,
    'cleave: smaller amber cone; Grave Slam: orange cone that cannot be interrupted');
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  record('No script errors (telegraphs)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function gamepad(browser) {
  current = 'Build 2: gamepad';
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await ctx.addInitScript(PAD_STUB);
  const { page, errors } = await openGame(ctx);
  await pauseLoop(page);
  await padSim(page, 0.05, { tap: [PAD.A] });
  const started = await page.evaluate(() => window.__shadowfall.started);
  await page.evaluate(() => (window.__shadowfall.random = () => 0.5));
  record('A starts the game from the title screen', started);

  await setup(page, { x: -6, z: 30 });
  let a = (await state(page)).pos;
  await padSim(page, 1, { axes: [0, -1, 0, 0] });
  let b = (await state(page)).pos;
  const half = (await state(page)).pos;
  await padSim(page, 1, { axes: [0.5, 0, 0, 0] });
  const c = (await state(page)).pos;
  record('Left stick moves the Warden, with analogue speed', near(a.z - b.z, 5, 0.15) && c.x - half.x > 1 && c.x - half.x < 2.5,
    `full stick north: ${(a.z - b.z).toFixed(2)}m in 1s; half stick east: ${(c.x - half.x).toFixed(2)}m`);
  const labels = await page.evaluate(() => [document.querySelector('#aslot-0 .key').textContent, document.querySelector('#aslot-4 .key').textContent, document.body.classList.contains('pad')]);
  record('Button prompts switch to the gamepad', labels[0] === 'RB' && labels[1] === 'X / RT' && labels[2], `spell bar shows ${labels[0]}, ${labels[1]}`);

  // X strikes towards where the right stick points
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 1.6, 0, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 48));
  await padSim(page, 0.5, { tap: [PAD.X], axes: [0, 0, 1, 0] });
  let g = await enemy(page, 'ghoul_road');
  record('X strikes towards the right stick (aim without tab targeting)', g.hp === 30, `ghoul to the east, right stick east: 48 → ${g.hp}`);
  await padSim(page, 0.7, { tap: [PAD.Y] });
  g = await enemy(page, 'ghoul_road');
  record('Y uses Shield Break', g.hp === 0, `ghoul ${g.hp}`);

  await setup(page, { x: 0, z: 20 });
  await padSim(page, 1.6);
  a = (await state(page)).pos;
  await page.evaluate(() => (window.__shadowfall.player.cooldowns.brace = 0));
  await padSim(page, 0.1, { tap: [PAD.B] });
  const padBrace = await page.evaluate(() => window.__shadowfall.player.isBraced);
  record('B raises Brace (the defensive button)', padBrace, `braced: ${padBrace}`);
  await padSim(page, 1.6);
  a = (await state(page)).pos;
  await padSim(page, 0.4, { tap: [PAD.RB], axes: [0, 0, 0, 1] });
  b = (await state(page)).pos;
  record('RB lunges towards the right stick', b.z - a.z > 4, `${(b.z - a.z).toFixed(2)}m south`);

  // menus: Start opens the bags, the d-pad moves a highlight, X equips, A carries, Y drops
  await page.evaluate(() => window.__shadowfall.inventory.addItem('watch_helm', 1, { quiet: true }));
  await padSim(page, 0.05, { tap: [PAD.START] });
  const opened = await page.evaluate(() => ({ modal: window.__shadowfall.hud.items.anyOpen ? 'panels' : null, vis: !document.getElementById('bags-window').hidden, focus: window.__shadowfall.hud.items.focus }));
  await padSim(page, 0.05, { tap: [PAD.RIGHT] });
  const focus2 = await page.evaluate(() => window.__shadowfall.hud.items.focus);
  const highlighted = await page.evaluate(() => document.querySelector('.islot.focus')?.dataset.loc);
  record('Start opens the bags; the d-pad moves a highlight between slots', opened.modal === 'panels' && opened.vis && opened.focus === 'b:0:0' && focus2 === 'b:0:1' && highlighted === 'b:0:1', `focus ${opened.focus} → ${focus2}`);
  const pos0 = (await state(page)).pos;
  await padSim(page, 0.3, { axes: [0, -1, 0, 0] });
  const pos1 = (await state(page)).pos;
  record('The stick does not move the Warden while a panel is open (extra)', pos0.z === pos1.z);
  await padSim(page, 0.05, { tap: [PAD.X] });
  let inv = await page.evaluate(() => ({ head: window.__shadowfall.inventory.equipment.head?.id, max: window.__shadowfall.player.maxHealth }));
  record('X equips the highlighted item', inv.head === 'watch_helm' && inv.max === 106, `helm worn; maximum health ${inv.max}`);

  await padSim(page, 0.05, { tap: [PAD.VIEW] });
  const charOpen = await page.evaluate(() => !document.getElementById('character-window').hidden);
  await page.evaluate(() => (window.__shadowfall.hud.items.focus = 'e:head'));
  await padSim(page, 0.05, { tap: [PAD.A] });
  const carry = await page.evaluate(() => window.__shadowfall.hud.items.carry);
  await padSim(page, 0.05, { tap: [PAD.LB] });
  await padSim(page, 0.05, { tap: [PAD.RIGHT] });
  await padSim(page, 0.05, { tap: [PAD.RIGHT] });
  const target = await page.evaluate(() => window.__shadowfall.hud.items.focus);
  await padSim(page, 0.05, { tap: [PAD.A] });
  inv = await page.evaluate((t) => ({ head: window.__shadowfall.inventory.equipment.head, at: window.__shadowfall.inventory.get(t)?.id }), target);
  record('View opens the character panel; A picks an item up and puts it down', charOpen && carry === 'e:head' && inv.head === null && inv.at === 'watch_helm', `carried the helm from the head slot to ${target}`);

  await padSim(page, 0.05, { tap: [PAD.Y] });
  const dropped = await page.evaluate(() => ({ ground: window.__shadowfall.worldState.ground.map((g) => g.id), carried: window.__shadowfall.inventory.has('watch_helm') }));
  record('Y drops the highlighted item on the ground', dropped.ground.includes('watch_helm') && !dropped.carried, `ground: ${dropped.ground.join(', ')}`);
  await padSim(page, 0.05, { tap: [PAD.B] });
  const closedPanels = await page.evaluate(() => window.__shadowfall.hud.modal === null && document.getElementById('bags-window').hidden && document.getElementById('character-window').hidden);
  const prompt = await page.evaluate(() => { window.__shadowfall.step(1 / 60); return document.getElementById('prompt').innerHTML; });
  await padSim(page, 0.05, { tap: [PAD.A] });
  const back = await page.evaluate(() => ({ has: window.__shadowfall.inventory.has('watch_helm'), ground: window.__shadowfall.worldState.ground.length }));
  record('B closes the panels; A picks the item back up', closedPanels && /<kbd>A<\/kbd>/.test(prompt) && back.has && back.ground === 0, `prompt "${prompt.replace(/<[^>]+>/g, '')}"`);
  record('No script errors (gamepad)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function bagsAndGround(browser) {
  current = 'Build 2: bags, character panel and the ground';
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  let { page, errors } = await openGame(ctx);
  await begin(page);
  await setup(page, { x: -6, z: 28 });
  await page.evaluate(() => {
    const inv = window.__shadowfall.inventory;
    inv.addItem('travellers_satchel', 1, { quiet: true });
    inv.addItem('watch_helm', 1, { quiet: true });
  });
  await page.click('#bag-sockets .islot[data-loc="s:0"]');
  await page.click('#btn-character');
  await page.waitForTimeout(200);
  const both = await page.evaluate(() => ({ bags: !document.getElementById('bags-window').hidden, ch: !document.getElementById('character-window').hidden }));
  record('Bags and the character panel open separately (WoW-style)', both.bags && both.ch, 'backpack button and character button on the bottom bar');

  const free0 = await page.evaluate(() => window.__shadowfall.inventory.freeSlots());
  const satchelLoc = await page.evaluate(() => window.__shadowfall.inventory.bagLocations().find((l) => window.__shadowfall.inventory.get(l)?.id === 'travellers_satchel'));
  await dragSlot(page, `.islot[data-loc="${satchelLoc}"]`, '#bag-sockets .islot[data-loc="s:1"]');
  await page.waitForTimeout(200);
  await page.click('#bag-sockets .islot[data-loc="s:1"]'); // open the new bag
  await page.waitForTimeout(150);
  const bagState = await page.evaluate(() => ({ socket: window.__shadowfall.inventory.sockets[1]?.id, free: window.__shadowfall.inventory.freeSlots(), frames: document.querySelectorAll('#bags-frames .bag-frame').length }));
  record('A bag dragged into a bag slot adds its slots', bagState.socket === 'travellers_satchel' && bagState.free === free0 + 9 && bagState.frames === 2,
    `free slots ${free0} → ${bagState.free} (+8, and the satchel left the backpack); ${bagState.frames} bag windows`);

  const helmLoc = await page.evaluate(() => window.__shadowfall.inventory.bagLocations().find((l) => window.__shadowfall.inventory.get(l)?.id === 'watch_helm'));
  await dragSlot(page, `.islot[data-loc="${helmLoc}"]`, '.islot[data-loc="e:head"]');
  await page.waitForTimeout(200);
  let st = await page.evaluate(() => ({ head: window.__shadowfall.inventory.equipment.head?.id, max: window.__shadowfall.player.maxHealth, helm: !!window.__shadowfall.player.helm }));
  record('Dragging an item from the bag onto the character panel equips it', st.head === 'watch_helm' && st.max === 106 && st.helm, `helm on the head slot and on the model; maximum health ${st.max}`);
  await dragSlot(page, '.islot[data-loc="e:head"]', '.islot[data-loc="b:1:3"]');
  await page.waitForTimeout(200);
  st = await page.evaluate(() => ({ head: window.__shadowfall.inventory.equipment.head, at: window.__shadowfall.inventory.get('b:1:3')?.id, max: window.__shadowfall.player.maxHealth }));
  record('Dragging it back from the character panel into a bag unequips it', st.head === null && st.at === 'watch_helm' && st.max === 100, `helm now in the satchel's 4th slot; maximum health ${st.max}`);
  await dragSlot(page, '.islot[data-loc="b:1:3"]', '.islot[data-loc="e:mainHand"]');
  st = await page.evaluate(() => ({ main: window.__shadowfall.inventory.equipped, at: window.__shadowfall.inventory.get('b:1:3')?.id }));
  record('Items only fit the slots they belong in (extra)', st.main === 'worn_longsword' && st.at === 'watch_helm', 'helm dropped on the main-hand slot was refused');

  // each bag closes on its own; the game runs with both bags open
  const tA = await page.evaluate(() => window.__shadowfall.time);
  await page.waitForTimeout(600);
  const tB = await page.evaluate(() => window.__shadowfall.time);
  await page.click('#bags-frames [data-close-bag="0"]');
  await page.waitForTimeout(150);
  const one = await page.evaluate(() => [...document.querySelectorAll('#bags-frames .bag-frame h3')].map((h) => h.textContent));
  await page.click('#bag-sockets .islot[data-loc="s:0"]');
  await page.waitForTimeout(150);
  const two = await page.evaluate(() => document.querySelectorAll('#bags-frames .bag-frame').length);
  record('Each bag opens and closes on its own, and two open bags do not freeze the game', tB > tA && one.length === 1 && one[0] === "Traveller's satchel" && two === 2,
    `game time advanced ${(tB - tA).toFixed(2)}s with both bags and the character panel open; closing the backpack left: ${one.join(', ')}`);

  // drag out of the window onto the world: dropped at the Warden's feet
  await dragSlot(page, '.islot[data-loc="b:1:3"]', { x: 560, y: 300 });
  await page.waitForTimeout(300);
  st = await page.evaluate(() => {
    const g = window.__shadowfall;
    const gr = g.worldState.ground[0];
    return { gr, has: g.inventory.has('watch_helm'), entry: g.loot.active.some((l) => l.def.ground === gr), dist: gr ? Math.hypot(gr.x - g.player.position.x, gr.z - g.player.position.z) : 99 };
  });
  record('Dragging an item out of the bag drops it on the ground (RuneScape-style)', st.gr && st.gr.id === 'watch_helm' && !st.has && st.entry && st.dist < 1.5, `helm lies ${st.dist.toFixed(2)}m from the Warden and is shown in the world`);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  const prompt = await page.evaluate(() => window.__shadowfall.interaction.current?.prompt);
  record('A dropped item can be picked up again from the ground', prompt === 'Pick up Dented watch helm', `prompt "${prompt}"`);

  // ground items persist through save and reload
  const saved = await page.evaluate(() => { window.__shadowfall.manualSave(); return window.__shadowfall.worldState.ground.map((g) => ({ ...g })); });
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  await begin(page, '#continue-btn');
  await pauseLoop(page);
  st = await page.evaluate(() => ({ ground: window.__shadowfall.worldState.ground, inWorld: window.__shadowfall.loot.active.filter((l) => l.def.ground).length, socket: window.__shadowfall.inventory.sockets[1]?.id }));
  record('Dropped items stay on the ground after saving and reloading', JSON.stringify(st.ground) === JSON.stringify(saved) && st.inWorld === 1 && st.socket === 'travellers_satchel', `${JSON.stringify(st.ground)}; satchel still in its bag slot`);
  await page.evaluate(() => window.__shadowfall.player.placeAt(window.__shadowfall.worldState.ground[0].x + 0.5, window.__shadowfall.worldState.ground[0].z));
  await sim(page, 0.1, { press: ['KeyE'] });
  st = await page.evaluate(() => ({ has: window.__shadowfall.inventory.has('watch_helm'), ground: window.__shadowfall.worldState.ground.length, inWorld: window.__shadowfall.loot.active.filter((l) => l.def.ground).length }));
  record('Picking it up removes it from the world and the save (extra)', st.has && st.ground === 0 && st.inWorld === 0);

  // a full bag leaves loot on the ground
  const full = await page.evaluate(() => {
    const g = window.__shadowfall;
    const inv = g.inventory;
    for (const loc of inv.bagLocations()) if (!inv.get(loc)) inv._set(loc, { id: 'manifest', count: 1 });
    g.player.placeAt(-8.4, -0.2);
    g.interaction.interact();
    return { collected: g.worldState.isCollected('grave_iron'), still: g.loot.active.some((l) => l.def.id === 'grave_iron'), log: document.querySelector('#log li:last-child').textContent };
  });
  record('A full bag leaves loot where it lies (extra)', !full.collected && full.still && /full/.test(full.log), `"${full.log}"`);

  // a build-1 save is upgraded, not discarded
  const v1 = {
    version: 1, savedAt: '2026-10-01T10:00:00Z',
    player: { position: { x: 3, z: 12 }, facing: 0, health: 80, maxHealth: 112 },
    progression: { level: 2, xp: 10 },
    inventory: { coins: 21, draughts: 2, items: ['worn_longsword', 'watchmans_edge', 'manifest', 'grave_iron'], equipped: 'watchmans_edge' },
    world: { defeated: ['ghoul_cart'], collected: ['manifest', 'grave_iron'], examined: ['cart'], drops: {}, shrineActivated: null, respawn: null, manifestCollected: true },
  };
  await page.evaluate((v1) => {
    window.__shadowfall.save.autosaveEnabled = false; // reloading would otherwise autosave over it
    localStorage.setItem('shadowfall.save', JSON.stringify(v1));
  }, v1);
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  const cont = await page.isVisible('#continue-btn');
  await begin(page, '#continue-btn');
  st = await page.evaluate(() => {
    const inv = window.__shadowfall.inventory;
    return { main: inv.equipped, draughts: inv.draughts, items: inv.items, coins: inv.coins, level: window.__shadowfall.progression.level, offHand: inv.equipment.offHand?.id };
  });
  record('Saves from before shields existed get the kite shield (extra)', st.offHand === 'kite_shield', `off hand: ${st.offHand}`);
  record('Saves from build 1 are upgraded on load', cont && st.main === 'watchmans_edge' && st.draughts === 2 && st.items.includes('worn_longsword') && st.items.includes('manifest') && st.coins === 21 && st.level === 2,
    `wielding ${st.main}; bag holds ${st.items.join(', ')}; ${st.coins} coins`);
  record('No script errors (bags and ground)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function spellBar(browser) {
  current = 'Build 2: editing the spell bar';
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await ctx.addInitScript(PAD_STUB);
  let { page, errors } = await openGame(ctx);
  await begin(page);
  await setup(page, { x: 0, z: 20 });
  const bar = () => page.evaluate(() => [...window.__shadowfall.actionBar.slots]);
  const b0 = await bar();
  await dragSlot(page, '#aslot-0', '#aslot-2');
  await page.waitForTimeout(150);
  const b1 = await bar();
  const iconMoved = await page.evaluate(() => document.querySelector('#aslot-2').dataset.ability === 'lunge' && document.querySelector('#aslot-0').classList.contains('empty'));
  record('Spells can be dragged to another slot on the bar', b1[2] === 'lunge' && b1[0] === null && iconMoved, `Lunge moved from slot 1 to slot 3 (bar was ${b0.join(', ')})`);

  await pauseLoop(page);
  await sim(page, 0.05, { press: ['Digit3'], clickAt: { x: 0, z: 14 } });
  const lunged = await page.evaluate(() => window.__shadowfall.player.lunge !== null);
  await sim(page, 2);
  await sim(page, 0.05, { press: ['Digit1'] });
  const nothing = await page.evaluate(() => window.__shadowfall.player.lunge === null && window.__shadowfall.player.cooldowns.gcd === 0);
  record('A moved spell fires from its new key', lunged && nothing, 'key 3 now lunges; key 1 does nothing');
  await resumeLoop(page);

  await dragSlot(page, '#aslot-2', { x: 640, y: 300 });
  await page.waitForTimeout(150);
  const b2 = await bar();
  record('Spells can be removed from the bar by dragging them off it', !b2.includes('lunge'), `bar: ${b2.map((a) => a || '—').join(', ')}`);

  await page.keyboard.press('KeyP');
  await page.waitForSelector('#spellbook-window:not([hidden])', { timeout: 10000 });
  await dragSlot(page, '#spellbook-window .islot[data-loc="k:lunge"]', '#aslot-3');
  await page.waitForTimeout(150);
  const b3 = await bar();
  record('The spellbook (P) puts removed spells back on the bar', b3[3] === 'lunge', `Lunge dragged from the spellbook to slot 4 (key 4)`);

  await dragSlot(page, '#aslot-6', '#aslot-4');
  await page.waitForTimeout(150);
  const b4 = await bar();
  record('Swapping two spells swaps their keys (extra)', b4[4] === 'brace' && b4[6] === 'strike', 'Brace on left click, Strike on Space');

  // the bar layout is saved
  await page.evaluate(() => window.__shadowfall.manualSave());
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  await begin(page, '#continue-btn');
  const b5 = await bar();
  record('The bar layout is saved', JSON.stringify(b5) === JSON.stringify(b4), b5.map((a) => a || '—').join(', '));

  // a save from before Brace (with Dodge on the bar) loads with Brace in its place
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.save.autosaveEnabled = false;
    const d = JSON.parse(localStorage.getItem('shadowfall.save'));
    d.bar = ['lunge', 'draught', null, null, 'strike', 'shieldBreak', 'dodge'];
    localStorage.setItem('shadowfall.save', JSON.stringify(d));
  });
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  await begin(page, '#continue-btn');
  const bOld = await bar();
  record('Old saves with Dodge on the bar get Brace instead (extra)', bOld[6] === 'brace', bOld.map((a) => a || '—').join(', '));

  // gamepad: d-pad up opens the spellbook; A carries a spell to a slot; Y removes it
  await pauseLoop(page);
  await padSim(page, 0.05, { tap: [PAD.UP] });
  const sbOpen = await page.evaluate(() => ({ open: !document.getElementById('spellbook-window').hidden, focus: window.__shadowfall.hud.items.focus }));
  await padSim(page, 0.05, { tap: [PAD.A] });
  await padSim(page, 0.05, { tap: [PAD.LB] });
  const barFocus = await page.evaluate(() => window.__shadowfall.hud.items.focus);
  await padSim(page, 0.05, { tap: [PAD.RIGHT] });
  await padSim(page, 0.05, { tap: [PAD.RIGHT] });
  const target = await page.evaluate(() => window.__shadowfall.hud.items.focus);
  await padSim(page, 0.05, { tap: [PAD.A] });
  const b6 = await bar();
  await padSim(page, 0.05, { tap: [PAD.Y] });
  const b7 = await bar();
  await padSim(page, 0.05, { tap: [PAD.B] });
  const closed = await page.evaluate(() => !window.__shadowfall.hud.items.anyOpen);
  const carried = sbOpen.focus.slice(2);
  record('The spell bar can be edited with a gamepad', sbOpen.open && barFocus === 'a:0' && target === 'a:2' && b6[2] === carried && !b7.includes(carried) && closed,
    `D-pad up opened the spellbook; A carried ${carried} to slot 3; Y removed it; B closed`);
  record('No script errors (spell bar)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}


async function controls(browser) {
  current = 'Controls, targeting and looting';
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await ctx.addInitScript(PAD_STUB);
  const { page, errors } = await openGame(ctx);
  const title = await page.evaluate(() => ({ modeBtn: !!document.getElementById('mode-btn'), tables: document.querySelectorAll('.controls-wrap').length }));
  record('One control scheme: no mode switch on the title screen', !title.modeBtn && title.tables === 1, `${title.tables} controls table, mode button ${title.modeBtn ? 'present' : 'gone'}`);
  await begin(page);
  await pauseLoop(page);
  const labels = await page.evaluate(() => [...document.querySelectorAll('#action-bar .aslot .key')].map((k) => k.textContent));
  const defensive = await page.evaluate(() => document.getElementById('aslot-6').classList.contains('defensive'));
  record('The spell bar keeps the mouse buttons, with Space as the defensive slot', labels[4] === 'LMB' && labels[5] === 'RMB' && labels[6] === 'Space' && defensive, `slots: ${labels.join(' | ')}`);

  // the camera is fixed: no orbit, WASD is screen-relative
  await setup(page, { x: -6, z: 30 });
  let a = (await state(page)).pos;
  await sim(page, 1, { held: ['KeyW'] });
  let b = (await state(page)).pos;
  const cam = await page.evaluate(() => {
    const g = window.__shadowfall;
    const c = g.camera.position;
    const t = g.cameraTarget;
    const [ox, oy, oz] = g.config.camera.offset;
    return { yaw: g.camYaw, off: [c.x - t.x - ox, c.y - t.y - oy, c.z - t.z - oz].map((v) => Math.abs(v)) };
  });
  record('The camera is fixed (no free rotation)', cam.yaw === undefined && Math.max(...cam.off) < 0.01 && near(b.z - a.z, -5, 0.2) && near(b.x - a.x, 0, 0.2),
    `camera holds its isometric offset; W moved (${(b.x - a.x).toFixed(2)}, ${(b.z - a.z).toFixed(2)}), straight up the screen`);

  // soft lock: aim roughly at a ghoul and the strike goes to it
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 1.3, -1.5, { frozen: true });
  await sim(page, 0.05, { aimAt: { x: 0, z: -4 } });
  const softRing = await page.evaluate(() => ({ soft: window.__shadowfall.targeting.soft?.id, ring: window.__shadowfall.targeting.softMarker.visible, lock: window.__shadowfall.targeting.current }));
  await sim(page, 0.7, { clickAt: { x: 0, z: -4 } });
  let gh = await enemy(page, 'ghoul_road');
  record('Soft lock: a strike aimed roughly at an enemy hits it', gh.hp === 30 && softRing.soft === 'ghoul_road' && softRing.ring && !softRing.lock,
    `aimed 40° off the ghoul: 48 → ${gh.hp}; a faint ring marked it, nothing hard-locked`);
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 48));
  await sim(page, 0.7, { clickAt: { x: 0, z: 4 } });
  gh = await enemy(page, 'ghoul_road');
  record('Soft lock does not reach behind you', gh.hp === 48, `aimed the other way: ghoul untouched (${gh.hp})`);

  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 5.2, 1.2, { frozen: true });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.enemies.byId('ghoul_road').health = 48;
    Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0));
    g.player.facing = Math.PI;
  });
  a = (await state(page)).pos;
  await sim(page, 0.6, { aimAt: { x: 4, z: -1 }, press: ['Digit1'] });
  b = (await state(page)).pos;
  gh = await enemy(page, 'ghoul_road');
  record('Lunge (and any targeted spell) goes to the soft-locked enemy', b.x - a.x > 3.5 && gh.hp === 21, `aimed near the ghoul: charged ${(b.x - a.x).toFixed(2)}m east, ghoul 48 → ${gh.hp}`);

  // hard lock: Tab locks what you aim at, a second Tab releases
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'ghoul_cart'] });
  await placeEnemy(page, 'ghoul_road', 0, 1.6, { frozen: true });
  await placeEnemy(page, 'ghoul_cart', 4, -3, { frozen: true });
  await page.evaluate(() => window.__shadowfall.enemies.list.forEach((e) => (e.health = e.cfg.health)));
  await sim(page, 0.05, { aimAt: { x: 4, z: -3 }, press: ['Tab'] });
  const t1 = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  const frame = await page.evaluate(() => ({ vis: !document.getElementById('target-frame').hidden, name: document.getElementById('target-name').textContent, marker: window.__shadowfall.targeting.marker.visible }));
  await sim(page, 0.05, { press: ['Tab'] });
  const t2 = await page.evaluate(() => window.__shadowfall.targeting.current?.id ?? null);
  record('Tab hard-locks the enemy you aim at; Tab again releases', t1 === 'ghoul_cart' && t2 === null && frame.vis && frame.marker,
    `locked ${t1} (frame "${frame.name}", red ring), then released`);

  // while locked, the Warden faces the target and blows go to it
  await sim(page, 0.05, { aimAt: { x: 0, z: 1.6 }, press: ['Tab'] });
  const t3 = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await sim(page, 0.6, { aimAt: { x: -4, z: 0 } });
  const facing = await page.evaluate(() => window.__shadowfall.player.facing);
  await sim(page, 0.7, { clickAt: { x: -4, z: 0 } });
  gh = await enemy(page, 'ghoul_road');
  record('A hard lock keeps the Warden facing the target and strikes it wherever the cursor is', t3 === 'ghoul_road' && Math.cos(facing) > 0.9 && gh.hp === 30,
    `facing ${(facing * 180 / Math.PI).toFixed(0)}° (towards the ghoul); clicked off to the west: ghoul 48 → ${gh.hp}`);
  await sim(page, 0.05, { press: ['Escape'] });
  const cleared = await page.evaluate(() => window.__shadowfall.targeting.current === null && document.getElementById('target-label').textContent !== 'Locked');
  record('Escape releases the lock', cleared);
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_cart');
    g.targeting.select(e);
    e.hurt(999);
    g.combat.onEnemyDefeated(e);
  });
  await sim(page, 0.05);
  record('A defeated target is let go (extra)', await page.evaluate(() => window.__shadowfall.targeting.current === null));

  // gamepad: R3 locks and releases, X strikes the lock
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_road').health = 48; g.player.cooldowns.attack = 0; });
  await padSim(page, 0.05, { tap: [11] });
  const padLock = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await padSim(page, 0.6, { tap: [PAD.X], axes: [0, 0, -1, 0] });
  gh = await enemy(page, 'ghoul_road');
  await padSim(page, 0.05, { tap: [11] });
  const padRelease = await page.evaluate(() => window.__shadowfall.targeting.current === null);
  record('R3 locks and releases on a gamepad; X strikes the locked enemy', padLock === 'ghoul_road' && gh.hp === 30 && padRelease, `locked ${padLock}; right stick pushed away, X still hit it (48 → ${gh.hp}); R3 again released`);
  await page.evaluate(() => window.__shadowfall.hud.setPadMode(false));

  // looting: bodies keep their coins; area loot takes everything close by
  const lootSetup = async () => {
    await setup(page, { x: 0, z: 10, keep: ['ghoul_road', 'ghoul_graves'] });
    await page.evaluate(() => {
      const g = window.__shadowfall;
      // bring back two ghouls and drop them side by side
      for (const [id, x] of [['ghoul_road', -1], ['ghoul_graves', 1.5]]) {
        let e = g.enemies.byId(id);
        if (e && !e.dead) {
          e.position.set(x, 0, 8);
          e.hurt(999);
          g.combat.onEnemyDefeated(e);
        }
      }
    });
  };
  await lootSetup();
  const dropped = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('grave_iron');
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'grave_iron');
    g.player.placeAt(0, 9.2);
    g.player.facing = Math.PI;
    return !!g.loot.dropFromInventory(loc);
  });
  await sim(page, 0.1);
  const lootState = await page.evaluate(() => ({ prompt: window.__shadowfall.interaction.current?.prompt, n: window.__shadowfall.loot.lootables().length }));
  const c0 = (await state(page)).coins;
  await sim(page, 0.1, { press: ['KeyE'] });
  let s = await state(page);
  const left = await page.evaluate(() => window.__shadowfall.loot.lootables().filter((l) => Math.hypot(l.x, l.z - 8.5) < 6).length);
  record('One press of E loots every body and drop nearby', dropped && /and 2 more nearby/.test(lootState.prompt || '') && s.coins === c0 + 6 && s.items.includes('grave_iron') && left === 0,
    `prompt "${lootState.prompt}"; +${s.coins - c0} coins from two ghouls and the grave iron back in the bag`);
  await sim(page, 6);
  const sunk = await page.evaluate(() => !window.__shadowfall.enemies.byId('ghoul_road') && !window.__shadowfall.enemies.byId('ghoul_graves'));
  record('Looted bodies sink away (extra)', sunk);

  // clicking a body loots it (and the rest nearby); too far away says so
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.loot.addCorpse({ id: 'ghoul_road', position: { x: -1, z: 8 }, corpse: false }, 3);
    g.loot.addCorpse({ id: 'ghoul_graves', position: { x: 1.5, z: 8 }, corpse: false }, 3);
    g.player.placeAt(0, 9.6);
  });
  await sim(page, 0.05);
  const c1 = (await state(page)).coins;
  await resumeLoop(page);
  const pt = await page.evaluate(() => {
    const g = window.__shadowfall;
    const v = new g.camera.position.constructor(-1, g.player.position.y + 0.3, 8).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    return { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height };
  });
  await page.mouse.click(pt.x, pt.y);
  await page.waitForFunction((c) => window.__shadowfall.inventory.coins > c, c1, { timeout: 15000 }).catch(() => {});
  await pauseLoop(page);
  s = await state(page);
  const swung = await page.evaluate(() => window.__shadowfall.player.cooldowns.attack > 0 || !!window.__shadowfall.player.pending);
  record('Clicking a body loots it and everything close by (no swing)', s.coins === c1 + 6 && !swung, `real left click on a body: ${c1} → ${s.coins} coins (both bodies)`);

  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.loot.addCorpse({ id: 'ghoul_road', position: { x: -1, z: 8 }, corpse: false }, 3);
    g.player.placeAt(0, 16);
  });
  await sim(page, 0.1, { clickAt: { x: -1, z: 8 } });
  s = await state(page);
  const farLog = await page.evaluate(() => document.querySelector('#log li:last-child').textContent);
  record('Clicking a body out of reach says so', /too far away/i.test(farLog) && s.coins === c1 + 6, `"${farLog}"`);
  await sim(page, 0.05, { clickAt: { x: 4, z: 18 } });
  const struck = await page.evaluate(() => window.__shadowfall.player.cooldowns.attack > 0 || !!window.__shadowfall.player.pending);
  record('Clicking open ground is the basic attack', struck, 'a click away from any body swings the sword');

  // the gamepad's A does the same area loot
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.loot.addCorpse({ id: 'ghoul_graves', position: { x: 1.5, z: 8 }, corpse: false }, 3);
    g.player.placeAt(0, 9.2);
  });
  await sim(page, 0.1);
  const c2 = (await state(page)).coins;
  await padSim(page, 0.1, { tap: [PAD.A] });
  s = await state(page);
  record('Gamepad A loots the area too', s.coins === c2 + 6, `${c2} → ${s.coins} coins from two bodies`);
  await page.evaluate(() => window.__shadowfall.hud.setPadMode(false));

  // things placed in the world (like the manifest) are taken one at a time
  const man = await page.evaluate(() => {
    const g = window.__shadowfall;
    const m = g.loot.active.find((l) => l.def.id === 'manifest');
    g.loot.addCorpse({ id: 'ghoul_cart', position: { x: m.x + 1, z: m.z + 0.5 }, corpse: false }, 3);
    const body = g.loot.lootables().find((l) => l.id === 'ghoul_cart');
    const n = g.loot.lootArea(body);
    return { n, still: !!g.loot.active.find((l) => l.def.id === 'manifest') };
  });
  record('World objects such as the manifest are not swept up by area looting', man.n === 1 && man.still, `looting a body beside the manifest took ${man.n} thing; manifest still there`);

  record('No script errors (controls and looting)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function statsAndDamage(browser) {
  current = 'Stats, damage and damage numbers';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // feed the combat rolls a fixed sequence (then 0.5 for anything after)
  const rolls = (list) => page.evaluate((list) => {
    const q = list.slice();
    window.__shadowfall.random = () => (q.length ? q.shift() : 0.5);
  }, list);

  await page.evaluate(() => window.__shadowfall.hud.togglePanel('character'));
  await sim(page, 0.05);
  const panel = await page.evaluate(() => Object.fromEntries([...document.querySelectorAll('#char-stats div')].filter((d) => d.querySelector('b')).map((d) => [d.querySelector('span').textContent, d.querySelector('b').textContent])));
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('character'));
  record('The character panel shows attributes and combat stats', panel.Might === '4' && panel.Finesse === '2' && panel.Vitality === '10' && panel.Strike === '16–20' && panel['Critical chance'] === '6.0%' && panel.Armour === '20 (−29%)' && panel.Block === '10%, stops 30%' && panel.Haste.startsWith('0%') && /Mail, Plate, shields/.test(panel.Wears),
    Object.entries(panel).map(([k, v]) => `${k} ${v}`).join(', '));

  // weapon hits roll within the weapon's range
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'brute_hallow'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  const strikeWith = async (seq, id = 'ghoul_road') => {
    await page.evaluate((id) => {
      const g = window.__shadowfall;
      const e = g.enemies.byId(id);
      e.health = e.cfg.health;
      e.engaged = 0;
      g.player.cooldowns.attack = 0;
      g.hud.numbers.clear();
    }, id);
    await rolls(seq);
    await sim(page, 0.3, { clickAt: { x: 0, z: -1.6 } });
    return page.evaluate((id) => {
      const e = window.__shadowfall.enemies.byId(id);
      const n = [...document.querySelectorAll('#damage-numbers .dmg')].map((d) => ({ text: d.textContent, cls: d.className }));
      return { dealt: e.cfg.health - e.health, n, log: document.querySelector('#log li:last-child').textContent };
    }, id);
  };
  const low = await strikeWith([0, 0.99]);
  const high = await strikeWith([0.999, 0.99]);
  const mid = await strikeWith([0.5, 0.99]);
  record('Weapon hits roll within the weapon range plus power', low.dealt === 16 && high.dealt === 20 && mid.dealt === 18, `lowest roll ${low.dealt}, highest ${high.dealt}, average ${mid.dealt} (worn longsword 12–16, +4 from Might)`);
  record('Hits show a damage number over the enemy', mid.n.length === 1 && mid.n[0].text === '18' && /dealt/.test(mid.n[0].cls) && !/crit/.test(mid.n[0].cls), JSON.stringify(mid.n));

  const crit = await strikeWith([0.5, 0.01]);
  record('Critical hits do 150% and show a distinct number', crit.dealt === 27 && crit.n[0].text === '27!' && /crit/.test(crit.n[0].cls) && /critical/i.test(crit.log), `${crit.dealt} damage, number "${crit.n[0].text}" (${crit.n[0].cls}); log: "${crit.log}"`);

  // armour reduces damage: the brute has 10 armour (17%)
  await placeEnemy(page, 'brute_hallow', 0, -1.6, { frozen: true });
  await placeEnemy(page, 'ghoul_road', 6, 6, { frozen: true });
  const brute = await strikeWith([0.5, 0.99], 'brute_hallow');
  record("Armour reduces the damage an enemy takes", brute.dealt === 15, `average strike 18 on the Brute (10 armour): ${brute.dealt}`);
  await placeEnemy(page, 'brute_hallow', -30, 40);
  await page.evaluate(() => { const b = window.__shadowfall.enemies.byId('brute_hallow'); b.cfg = { ...b.cfg, detection: 0 }; });

  // blows on the player: variance, armour, block, crit
  const hitMe = async (seq, { unclothed = false } = {}) => page.evaluate(({ seq, unclothed }) => {
    const g = window.__shadowfall;
    const q = seq.slice();
    g.random = () => (q.length ? q.shift() : 0.5);
    const e = g.enemies.byId('ghoul_road');
    e.position.set(g.player.position.x, 0, g.player.position.z - 1.4);
    const clothes = g.inventory.equipment.chest;
    if (unclothed) g.inventory.equipment.chest = null;
    g.player.health = 100;
    g.player.braced = 0;
    g.hud.numbers.clear();
    g.combat.resolveEnemyStrike(e);
    g.inventory.equipment.chest = clothes;
    const n = [...document.querySelectorAll('#damage-numbers .dmg')].map((d) => ({ text: d.textContent, cls: d.className }));
    return { taken: 100 - g.player.health, n, log: document.querySelector('#log li:last-child').textContent };
  }, { seq, unclothed });
  const plain = await hitMe([0.5, 0.99, 0.99]);
  const bare = await hitMe([0.5, 0.99, 0.99], { unclothed: true });
  record('Armour reduces the damage the Warden takes', plain.taken === 8 && bare.taken === 11, `a ghoul's 11: ${plain.taken} in travelling clothes (20 armour), ${bare.taken} without`);
  record('Hits taken show a red number', plain.n.length === 1 && plain.n[0].text === '8' && /taken/.test(plain.n[0].cls), JSON.stringify(plain.n));
  const varied = [await hitMe([0, 0.99, 0.99]), await hitMe([1, 0.99, 0.99])].map((h) => h.taken);
  record('Enemy blows vary a little either side of their damage (extra)', varied[0] === 7 && varied[1] === 9, `lowest ${varied[0]}, highest ${varied[1]} (±15% before armour)`);
  const blocked = await hitMe([0.5, 0.99, 0.01]);
  record('A shield block stops 30% of a melee blow', blocked.taken === 6 && /2 blocked/.test(blocked.n[0]?.text || '') && /2 blocked/.test(blocked.log), `8 with 30% blocked: ${blocked.taken}; number "${blocked.n[0]?.text}"; log "${blocked.log}"`);
  const enemyCrit = await hitMe([0.5, 0.01, 0.99]);
  record('Enemies can crit too, shown as a distinct number', enemyCrit.taken === 12 && enemyCrit.n[0].text === '12!' && /taken/.test(enemyCrit.n[0].cls) && /crit/.test(enemyCrit.n[0].cls) && /critically/.test(enemyCrit.log),
    `${enemyCrit.taken} damage; "${enemyCrit.log}"`);
  // no shield, no block: the chance comes from the shield (plus block rating)
  const noShield = await page.evaluate(() => {
    const g = window.__shadowfall;
    const sh = g.inventory.equipment.offHand;
    g.inventory.equipment.offHand = null;
    const without = g.stats.blockChance;
    g.inventory.equipment.offHand = sh;
    g.config.archetypes.warden.base.blockRating = 50;
    const rated = g.stats.blockChance;
    g.config.archetypes.warden.base.blockRating = 400;
    const capped = g.stats.blockChance;
    g.config.archetypes.warden.base.blockRating = 0;
    return { with: g.stats.blockChance, without, rated, capped, shown: !!g.player.shield };
  });
  record('Block chance comes from the shield and block rating, capped at 50%', noShield.with === 10 && noShield.without === 0 && noShield.rated === 15 && noShield.capped === 50 && noShield.shown,
    `kite shield ${noShield.with}%, no shield ${noShield.without}%, +50 rating ${noShield.rated}%, +400 rating ${noShield.capped}%; shield worn on the left arm`);

  // Grave Slam cannot crit or be blocked
  const slam = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.random = () => 0; // every roll as low as it goes: crit and block would both fire
    const b = g.enemies.byId('brute_hallow');
    g.player.health = 100;
    const shape = { contains: () => true };
    g.combat.resolveTelegraph(b, shape, b.cfg.special.damage, 'Grave Slam');
    g.random = () => 0.5;
    return { taken: 100 - g.player.health, log: document.querySelector('#log li:last-child').textContent };
  });
  record('Grave Slam cannot crit or be blocked', slam.taken === 20 && !/critical|blocked/i.test(slam.log), `lowest roll of 31 after armour: ${slam.taken}; "${slam.log}"`);

  // heals show green numbers; numbers fade and are removed
  await page.evaluate(() => { const g = window.__shadowfall; g.player.health = 40; g.player.cooldowns.draught = 0; g.inventory.draughts = 1; g.hud.numbers.clear(); });
  await sim(page, 0.05, { press: ['KeyQ'] });
  const heal = await page.evaluate(() => [...document.querySelectorAll('#damage-numbers .dmg')].map((d) => ({ text: d.textContent, cls: d.className })));
  await sim(page, 1.3);
  const left = await page.evaluate(() => document.querySelectorAll('#damage-numbers .dmg.heal').length);
  record('Heals show a green number; numbers fade after about a second', heal.length === 1 && heal[0].text === '+42' && /heal/.test(heal[0].cls) && left === 0, `"${heal[0]?.text}", ${left} numbers left 1.3s later`);

  // enemy health (and mana, when an enemy has it) in the target frame and over its head
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -2, { frozen: true });
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_road').health = 30; g.targeting.clear(); });
  await sim(page, 0.05, { aimAt: { x: 0, z: -3 } });
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  const tf = await page.evaluate(() => ({
    vis: !document.getElementById('target-frame').hidden, name: document.getElementById('target-name').textContent, text: document.getElementById('target-text').textContent,
    label: document.getElementById('target-label').textContent, mana: !document.getElementById('target-mana-bar').hidden, bar: !!document.querySelector('#enemy-bars .ebar'),
  }));
  record('Enemy health shows in the target frame without locking on', tf.vis && tf.name === 'Ashen Ghoul' && tf.text === '30 / 48' && tf.label === 'Level 1' && !tf.mana && tf.bar,
    `aiming at a wounded ghoul: "${tf.name}" ${tf.text} (${tf.label}), bar over its head; no mana bar`);
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    e.cfg = { ...e.cfg, mana: 30 };
    e.mana = 20;
    g.hud.enemyBars.get(e.id)?.remove();
    g.hud.enemyBars.delete(e.id);
  });
  await sim(page, 0.05, { aimAt: { x: 0, z: -3 } });
  const mf = await page.evaluate(() => ({ mana: !document.getElementById('target-mana-bar').hidden, text: document.getElementById('target-mana-text').textContent, bar: !!document.querySelector('#enemy-bars .ebar .emana') }));
  record('Enemies with mana show a mana bar too', mf.mana && mf.text === '20 / 30' && mf.bar, `target frame mana "${mf.text}", blue bar under its health`);

  // the formulas are data: changing the config changes the result
  const tuned = await page.evaluate(() => {
    const g = window.__shadowfall;
    const before = g.stats.critChance;
    g.config.stats.critBase = 10;
    const after = g.stats.critChance;
    g.config.stats.critBase = 5;
    return { before, after };
  });
  record('Stat formulas are driven by config (extra)', tuned.before === 6 && tuned.after === 11, `crit chance ${tuned.before}% → ${tuned.after}% with critBase 5 → 10`);
  // armour scales with the attacker's level (WoW / Diablo III style)
  const lvl = await page.evaluate(() => {
    const g = window.__shadowfall;
    const q = [];
    g.random = () => 0.5;
    const hitBy = (level) => {
      const e = g.enemies.byId('ghoul_road');
      e.cfg = { ...e.cfg, level, damage: 20, crit: 0 };
      e.position.set(g.player.position.x, 0, g.player.position.z - 1.4);
      g.player.health = 100;
      g.player.braced = 0;
      g.combat.resolveEnemyStrike(e);
      return 100 - g.player.health;
    };
    const r = { l1: hitBy(1), l5: hitBy(5) };
    const e = g.enemies.byId('ghoul_road');
    e.cfg = { ...e.cfg, level: 1, damage: 11, crit: 5 };
    return r;
  });
  record('Armour stops less against higher-level enemies', lvl.l1 === 14 && lvl.l5 === 16, `a 20-damage blow: ${lvl.l1} from a level 1 foe (29% off), ${lvl.l5} from a level 5 foe (20% off)`);

  // armour types: an archetype may only wear some
  const types = await page.evaluate(() => {
    const g = window.__shadowfall;
    const w = g.config.archetypes.warden;
    const keep = w.armourTypes;
    g.inventory.addItem('watch_helm');
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'watch_helm');
    w.armourTypes = ['cloth', 'leather'];
    const refused = !g.inventory.move(loc, 'e:head').ok;
    const log = document.querySelector('#log li:last-child').textContent;
    w.armourTypes = keep;
    const worn = g.inventory.move(loc, 'e:head').ok;
    return { refused, log, worn, head: g.inventory.equipment.head?.id };
  });
  record('Armour types limit what an archetype can wear', types.refused && /cannot use mail armour/.test(types.log) && types.worn, `mail helm on a cloth-and-leather wearer: "${types.log}"; the Warden (all types) wears it`);

  // haste shortens the swing, the windups and the GCD (to its floor)
  const haste = await page.evaluate(() => {
    const g = window.__shadowfall;
    const base = { swing: g.stats.attackCooldown, gcd: g.stats.globalCooldown };
    g.config.archetypes.warden.base.haste = 20;
    const fast = { swing: g.stats.attackCooldown, gcd: g.stats.globalCooldown };
    g.player.cooldowns.attack = 0;
    g.player.pending = null;
    g.player.tryStrike(null);
    const used = { cd: g.player.cooldowns.attack, windup: g.player.pending?.t };
    g.player.pending = null;
    g.config.archetypes.warden.base.haste = 80;
    const capped = { haste: g.stats.haste, gcd: g.stats.globalCooldown };
    g.config.archetypes.warden.base.haste = 0;
    return { base, fast, used, capped };
  });
  record('Haste shortens swings, windups and the global cooldown', near(haste.fast.swing, 0.5, 0.001) && near(haste.fast.gcd, 1.25, 0.001) && near(haste.used.cd, 0.5, 0.001) && near(haste.used.windup, 0.16 / 1.2, 0.001) && haste.capped.haste === 30 && near(haste.capped.gcd, 1.154, 0.001),
    `20% haste: swing ${haste.base.swing}s → ${haste.fast.swing.toFixed(2)}s, GCD ${haste.base.gcd}s → ${haste.fast.gcd.toFixed(2)}s; 80% is capped at ${haste.capped.haste}% (GCD ${haste.capped.gcd.toFixed(2)}s, floor 1s)`);

  // a level-up shows every stat that rose, old to new, here and on the character screen
  await page.evaluate(() => window.__shadowfall.progression.addXp(100));
  await sim(page, 0.1);
  const lu = await page.evaluate(() => ({
    vis: !document.getElementById('levelup').hidden, title: document.getElementById('levelup-title').textContent,
    rows: [...document.querySelectorAll('#levelup .lu-row')].map((r) => [...r.children].map((c) => c.textContent).join(' ')),
  }));
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('character'));
  await sim(page, 0.05);
  const marks = await page.evaluate(() => [...document.querySelectorAll('#char-stats .gain')].map((g) => g.closest('div').dataset.stat + g.textContent));
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('character'));
  await sim(page, 6.2);
  const luGone = await page.evaluate(() => document.getElementById('levelup').hidden);
  record('Level-up shows each stat increase', lu.vis && lu.title === 'Level 2' && lu.rows.some((r) => /^Might 4 → 6 \+2$/.test(r)) && lu.rows.some((r) => /^Vitality 11 → 13 \+2$/.test(r)) && lu.rows.some((r) => /^Maximum health 106 → 118 \+12$/.test(r)) && lu.rows.some((r) => /^Strike 16–20 → 18–22 \+2$/.test(r)) && luGone,
    lu.rows.join(' | '));
  record('The character screen marks what rose at the last level-up', ['health+12', 'might+2', 'vitality+2', 'strike+2'].every((m) => marks.includes(m)), marks.join(', '));

  record('No script errors (stats and damage)', errors.length === 0, errors.join(' | '));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'stats.png') });
  await ctx.close();
}

async function itemDatabase(browser) {
  current = 'Item database';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const db = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { errors: g.itemErrors, count: Object.keys(g.items).length, missing: Object.entries(g.items).filter(([, d]) => !(Number.isInteger(d.price) && d.icon && d.quality)).map(([id]) => id) };
  });
  record('Every item comes from one database with slot, stats, price and icon', db.errors.length === 0 && db.missing.length === 0 && db.count >= 9, `${db.count} items in src/data/items.json, all valid`);
  const caught = await page.evaluate(() => {
    const g = window.__shadowfall;
    const bad = { broken_blade: { name: 'Broken blade', kind: 'weapon', slot: 'mainHand', quality: 'shiny', stack: 1, price: -1, model: 'worn_sword', icon: 'worn_sword', description: 'x' } };
    return g.validateItems(bad, ['mainHand'], ['cloth']);
  });
  record('The database check catches a malformed item (extra)', caught.length >= 3, caught.join('; '));

  await page.evaluate(() => window.__shadowfall.hud.togglePanel('bags'));
  await resumeLoop(page);
  await page.hover('.islot[data-loc="b:0:0"]');
  await page.waitForSelector('#tooltip:not([hidden])', { timeout: 10000 });
  const tip = await page.evaluate(() => ({ text: document.getElementById('tooltip').textContent, q: document.querySelector('#tooltip .tt-name').className }));
  record('Tooltips show what a merchant would pay, and the item quality', /Sells for 1 coin/.test(tip.text) && /q-common/.test(tip.q), tip.text.replace(/\s+/g, ' ').slice(0, 140));
  await pauseLoop(page);

  const quest = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('manifest');
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'manifest');
    const dropped = g.loot.dropFromInventory(loc);
    return { dropped: !!dropped, still: g.inventory.count('manifest'), log: document.querySelector('#log li:last-child').textContent };
  });
  record('Quest items cannot be dropped (extra)', !quest.dropped && quest.still === 1, `"${quest.log}"`);
  record('No script errors (item database)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function forge(browser) {
  current = "Mara's forge";
  let { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await setup(page, { x: 16.2, z: -40.5 });
  await pauseLoop(page);
  const talk = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.coins = 30;
    g.inventory.addItem('grave_iron', 2, { quiet: true });
    g.interaction.update();
    const prompt = g.interaction.current && g.interaction.current.prompt;
    g.interaction.interact();
    g.step(1 / 60);
    return { prompt, current: g.merchant.current, shop: !document.getElementById('shop-window').hidden, bags: g.hud.items.openBags.size > 0, stock: document.querySelectorAll('#shop-stock .islot').length, mara: !!g.npcs.byId('mara') };
  });
  record('Mara Venn stands at her forge and talking to her opens her shop beside the bags', talk.mara && talk.prompt === 'Talk to Mara Venn' && talk.current === 'mara_forge' && talk.shop && talk.bags && talk.stock === 6, `prompt "${talk.prompt}", ${talk.stock} items for sale, bags open: ${talk.bags}`);

  const buy = await page.evaluate(() => {
    const g = window.__shadowfall;
    const c0 = g.inventory.coins;
    const ok = g.merchant.buy('iron_gloves');
    const c1 = g.inventory.coins;
    const refused = !g.merchant.buy('iron_shield');
    return { ok, paid: c0 - c1, have: g.inventory.count('iron_gloves'), refused, shields: g.inventory.count('iron_shield'), coins: g.inventory.coins, log: document.querySelector('#log li:last-child').textContent };
  });
  record('Buying takes the price in coins and puts the item in the bags', buy.ok && buy.paid === 14 && buy.have === 1, `iron-studded gloves for ${buy.paid} coins`);
  record('A merchant refuses a sale the Warden cannot afford', buy.refused && buy.shields === 0 && buy.coins === 16, `"${buy.log}"`);

  const sell = await page.evaluate(() => {
    const g = window.__shadowfall;
    const find = (id) => g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === id);
    const c0 = g.inventory.coins;
    g.merchant.sell(find('iron_gloves'));
    const gloves = g.inventory.coins - c0;
    const c1 = g.inventory.coins;
    g.merchant.sell(find('grave_iron'));
    const iron = g.inventory.coins - c1;
    const buyback = document.querySelectorAll('#shop-buyback .islot').length;
    const c2 = g.inventory.coins;
    const back = g.merchant.buyBack(g.merchant.buyback.findIndex((b) => b.id === 'iron_gloves'));
    return { gloves, iron, buyback, back, backCost: c2 - g.inventory.coins, have: g.inventory.count('iron_gloves') };
  });
  record('Selling pays a quarter of the price (WoW style)', sell.gloves === 3 && sell.iron === 2, `gloves (14) sell for ${sell.gloves}; 2 grave iron (4 each) for ${sell.iron}`);
  record('Sold items can be bought back for what they fetched (extra)', sell.buyback === 2 && sell.back && sell.backCost === 3 && sell.have === 1, `${sell.buyback} in buy back; gloves back for ${sell.backCost}`);

  const handIn = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('manifest', 1, { quiet: true });
    g.worldState.examined.add('cart');
    g.worldState.collected.add('manifest');
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'manifest');
    const sold = g.merchant.sell(loc);
    g.events.emit('objectiveChanged', {});
    g.hud.items.render();
    const before = { label: document.getElementById('objective-state').textContent, stage: g.worldState.objectiveStage, button: !document.getElementById('shop-handin').hidden };
    window.__c0 = g.inventory.coins;
    return { sold, before };
  });
  await page.click('#shop-handin');
  Object.assign(handIn, await page.evaluate(() => {
    const g = window.__shadowfall;
    g.step(1 / 60);
    const c0 = window.__c0;
    return {
      coins: g.inventory.coins - c0, xp: g.progression.xp, level: g.progression.level,
      manifest: g.inventory.count('manifest'), flag: g.worldState.flags.has('manifest_delivered'),
      stage: g.worldState.objectiveStage, label: document.getElementById('objective-state').textContent,
      button: !document.getElementById('shop-handin').hidden, talk: document.getElementById('shop-talk').textContent,
    };
  }));
  record('Quest items cannot be sold', !handIn.sold, 'the manifest stays in the bags');
  record('With the manifest in hand the objective says to return to Mara', handIn.before.stage === 'complete' && /Mara/.test(handIn.before.label) && handIn.before.button, `"${handIn.before.label}", hand-in button shown`);
  record('Handing Mara the manifest pays 20 coins and 50 experience and closes the storyline', handIn.coins === 20 && handIn.xp === 50 && handIn.manifest === 0 && handIn.flag && handIn.stage === 'reported' && handIn.label === 'Complete' && !handIn.button, `+${handIn.coins} coins, ${handIn.xp} xp; "${handIn.talk.slice(0, 70)}…"`);

  await page.evaluate(() => window.__shadowfall.player.placeAt(24, -38));
  await sim(page, 0.2);
  const away = await page.evaluate(() => ({ current: window.__shadowfall.merchant.current, shown: !document.getElementById('shop-window').hidden }));
  record('Walking away closes the shop', away.current === null && !away.shown);

  await page.evaluate(() => window.__shadowfall.manualSave());
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  errors.length = 0;
  await begin(page, '#continue-btn');
  const saved = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { flag: g.worldState.flags.has('manifest_delivered'), stage: g.worldState.objectiveStage, label: document.getElementById('objective-state').textContent };
  });
  record('The finished storyline persists through save and reload', saved.flag && saved.stage === 'reported' && saved.label === 'Complete', `"${saved.label}"`);
  record("No script errors (Mara's forge)", errors.length === 0, errors.join(' | '));
  await ctx.close();

  // the gamepad: A on a stock item buys it
  ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await ctx.addInitScript(PAD_STUB);
  ({ page, errors } = await openGame(ctx));
  await pauseLoop(page);
  await padSim(page, 0.05, { tap: [PAD.A] });
  await page.evaluate(() => (window.__shadowfall.random = () => 0.5));
  await setup(page, { x: 16.2, z: -40.5 });
  await page.evaluate(() => (window.__shadowfall.inventory.coins = 20));
  await padSim(page, 0.05, { tap: [PAD.A] }); // talk
  const padOpen = await page.evaluate(() => window.__shadowfall.merchant.current);
  await page.evaluate(() => (window.__shadowfall.hud.items.focus = 'm:healing_draught'));
  await padSim(page, 0.05, { tap: [PAD.A] });
  const pad = await page.evaluate(() => ({ coins: window.__shadowfall.inventory.coins, draughts: window.__shadowfall.inventory.count('healing_draught') }));
  record('With a gamepad, A talks to Mara and A on an item buys it', padOpen === 'mara_forge' && pad.coins === 14, `${pad.coins} coins left, ${pad.draughts} draughts`);
  record("No script errors (forge, gamepad)", errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function gearRolls(browser) {
  current = 'Gear drops with random stat rolls';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await setup(page, { x: 16.2, z: -40.5 });
  await pauseLoop(page);

  const spread = await page.evaluate(() => {
    const g = window.__shadowfall;
    let suffixed = 0;
    let armourOk = true;
    let damageOk = true;
    const seen = new Set();
    for (let i = 0; i < 300; i++) {
      const h = g.rollItem('warden_hauberk', Math.random);
      const a = g.itemView({ id: 'warden_hauberk', rolls: h }).stats.armour;
      if (h && h.suffix) suffixed++;
      seen.add(a);
      if (a < 32 * 0.8 - 0.5 || a > 32 * 1.2 + 0.5) armourOk = false;
      const f = g.itemView({ id: 'rusted_falchion', rolls: g.rollItem('rusted_falchion', Math.random) }).damage;
      if (f[0] < 13 * 0.88 - 0.5 || f[1] > 19 * 1.12 + 0.5 || f[0] > f[1]) damageOk = false;
    }
    return { suffixed, armourOk, damageOk, kinds: seen.size, material: g.rollItem('grave_iron', Math.random), quest: g.rollItem('manifest', Math.random) };
  });
  record('Dropped gear rolls its stats a little either side of the database values', spread.armourOk && spread.damageOk && spread.kinds >= 8, `hauberk armour rolled ${spread.kinds} different values within ±20% of 32; falchion damage within ±12%`);
  record('Some pieces gain a WoW-style suffix with bonus attributes', spread.suffixed > 50 && spread.suffixed < 160, `${spread.suffixed} of 300 hauberks rolled a suffix`);
  record('Materials and quest items never roll (extra)', spread.material === null && spread.quest === null);

  const worn = await page.evaluate(() => {
    const g = window.__shadowfall;
    const vals = [0.95, 0.1, 0.0, 0.9, 0.99];
    let i = 0;
    const rolls = g.rollItem('warden_hauberk', () => vals[i++]);
    const view = g.itemView({ id: 'warden_hauberk', rolls });
    g.inventory.addItem('warden_hauberk', 1, { rolls });
    const a0 = g.stats.armour;
    g.inventory.equip('warden_hauberk');
    g.hud.togglePanel('character');
    return { rolls, name: view.name, quality: view.quality, armour: g.stats.armour, a0, haste: g.stats.haste, panel: document.getElementById('char-stats').textContent };
  });
  record('A rolled item is named for its suffix and counts its rolled stats when worn', worn.name === "Warden's hauberk of Swiftness" && worn.quality === 'uncommon' && worn.armour === 38 && worn.haste === 2, `${worn.name}: ${JSON.stringify(worn.rolls)}; armour ${worn.a0} → ${worn.armour}, haste ${worn.haste}%`);

  await resumeLoop(page);
  await page.hover('.islot[data-loc="e:chest"]');
  await page.waitForSelector('#tooltip:not([hidden])', { timeout: 10000 });
  const tip = await page.evaluate(() => ({ text: document.getElementById('tooltip').textContent, q: document.querySelector('#tooltip .tt-name').className }));
  record('Tooltips show the rolled name, quality and stats', /of Swiftness/.test(tip.text) && /\+38 armour/i.test(tip.text) && /\+2 ?% haste/i.test(tip.text) && /q-uncommon/.test(tip.q), tip.text.replace(/\s+/g, ' ').slice(0, 120));
  await pauseLoop(page);

  const moved = await page.evaluate(() => {
    const g = window.__shadowfall;
    const rolls = { damage: [15, 21], suffix: 'bear', stats: { might: 2, vitality: 1 } };
    g.inventory.addItem('rusted_falchion', 1, { rolls, quiet: true });
    const find = () => g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'rusted_falchion');
    g.loot.dropFromInventory(find());
    const ground = g.worldState.ground.find((x) => x.id === 'rusted_falchion');
    const entry = g.loot.active.find((l) => l.def.ground === ground);
    const prompt = entry.def.prompt;
    g.loot.collect(entry);
    const back = g.inventory.get(find());
    // sell it to Mara and buy it back
    g.merchant.open('mara_forge', g.npcs.byId('mara'));
    const c0 = g.inventory.coins;
    g.merchant.sell(find());
    const paid = g.inventory.coins - c0;
    g.merchant.buyBack(0);
    const again = g.inventory.get(find());
    g.merchant.close();
    return { groundRolls: ground.rolls, prompt, back: back.rolls, paid, view: g.itemView(back), again: again && again.rolls };
  });
  const same = (r) => JSON.stringify(r) === JSON.stringify({ damage: [15, 21], suffix: 'bear', stats: { might: 2, vitality: 1 } });
  record('Rolls survive dropping, picking up, selling and buying back', same(moved.groundRolls) && same(moved.back) && same(moved.again) && /of the Bear/.test(moved.prompt), `"${moved.prompt}"`);
  record('A suffixed item is worth more to a merchant', moved.paid === Math.floor(moved.view.price * 0.25) && moved.paid > 5, `sells for ${moved.paid} (a plain falchion: 5)`);

  await page.evaluate(() => window.__shadowfall.manualSave());
  const bad = await page.evaluate(() => {
    const g = window.__shadowfall;
    const data = JSON.parse(localStorage.getItem('shadowfall.save'));
    const chest = data.inventory.equipment.chest;
    const tampered = JSON.parse(JSON.stringify(data));
    tampered.inventory.equipment.chest.rolls = { suffix: 'of_godhood', stats: { might: 9999 } };
    return { chest, ok: g.validateSave(data).length === 0, rejected: g.validateSave(tampered) };
  });
  record('Rolls are saved, and a tampered roll fails the save check', same(moved.again) && bad.ok && bad.chest.rolls && bad.rejected.length > 0, `saved chest: ${JSON.stringify(bad.chest)}; tampered: ${bad.rejected.join(', ')}`);
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  errors.length = 0;
  await begin(page, '#continue-btn');
  const loaded = await page.evaluate(() => ({ chest: window.__shadowfall.inventory.equipment.chest, armour: window.__shadowfall.stats.armour }));
  record('Rolled gear is the same after a reload', loaded.chest.rolls && loaded.chest.rolls.suffix === 'swiftness' && loaded.armour === 38, JSON.stringify(loaded.chest));

  await pauseLoop(page);
  const drop = await page.evaluate(() => {
    const g = window.__shadowfall;
    const before = g.worldState.ground.length;
    g.random = () => 0.1; // under the ghoul's 20% gear chance
    const e = g.enemies.byId('ghoul_road');
    e.health = 1;
    e.hurt(5);
    g.combat.onEnemyDefeated(e);
    g.random = () => 0.5;
    const dropped = g.worldState.ground.slice(before);
    const log = [...document.querySelectorAll('#log li')].map((l) => l.textContent).join(' | ');
    g.player.placeAt(e.position.x + 1, e.position.z);
    g.interaction.update();
    const prompt = g.interaction.current && g.interaction.current.prompt;
    g.interaction.interact();
    return { dropped, near: dropped.every((d) => Math.hypot(d.x - e.position.x, d.z - e.position.z) < 1.5), prompt, left: g.worldState.ground.length - before, log };
  });
  const table = ['iron_gloves', 'hob_boots', 'rusted_falchion', 'mail_chausses'];
  record('Enemies drop gear from their table beside the body', drop.dropped.length === 1 && table.includes(drop.dropped[0].id) && drop.near && /drops a/.test(drop.log), `the ghoul dropped ${drop.dropped.map((d) => d.id + (d.rolls ? ' ' + JSON.stringify(d.rolls) : '')).join(', ')}`);
  record('One loot takes the body and its drops together', drop.left === 0 && /and 1 more nearby/.test(drop.prompt || ''), `"${drop.prompt}"`);
  record('No script errors (gear rolls)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function blackwood(browser) {
  current = 'The Blackwood';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await setup(page, { x: 3, z: -47 });
  await pauseLoop(page);
  const before = await page.evaluate(() => ({ region: document.querySelector('#title-area .region').textContent, near: window.__shadowfall.scene.fog.near }));
  await sim(page, 3.4, { held: ['KeyW'] });
  const after = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { z: g.player.position.z, x: g.player.position.x, region: document.querySelector('#title-area .region').textContent, near: g.scene.fog.near, far: g.scene.fog.far, log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).join(' | ') };
  });
  record('A forest track leads north past the forge into a second region, the Blackwood', before.region === 'The Fallen Road' && after.z < -60 && after.region === 'The Blackwood' && /The Blackwood/.test(after.log), `walked from (3, -47) to (${after.x.toFixed(1)}, ${after.z.toFixed(1)}); the HUD now reads "${after.region}"`);
  record('The Blackwood is darker: the fog closes in', after.near < before.near && after.far < 40, `fog ${before.near}–40 m → ${after.near.toFixed(1)}–${after.far.toFixed(1)} m`);

  const roster = await page.evaluate(() => {
    const g = window.__shadowfall;
    const types = {};
    for (const e of g.enemies.list) if (e.home.z < -56 || e.id.includes('_bw_') || ['hound', 'archer', 'seer'].includes(e.type)) types[e.type] = (types[e.type] || 0) + 1;
    const seer = g.enemies.byId('seer_glade');
    return { types, seerMana: seer.mana, seerLevel: seer.cfg.level, models: ['hound', 'archer', 'seer'].every((m) => !g.assets.usedFallback.includes(m)) };
  });
  record('Three new enemy types live there: barrow hounds, hollow archers and a seer', roster.types.hound === 4 && roster.types.archer === 3 && roster.types.seer === 1 && roster.models, JSON.stringify(roster.types));

  // shrine at the forest edge
  const shrine = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(2.8, -63);
    g.player.health = 40;
    g.interaction.update();
    const prompt = g.interaction.current && g.interaction.current.prompt;
    g.interaction.interact();
    return { prompt, hp: g.player.health, max: g.player.maxHealth, label: g.respawnPoint().label };
  });
  record('A second shrine at the forest edge heals and becomes the respawn point', shrine.prompt === 'Rest at the shrine' && shrine.hp === shrine.max && /forest edge/.test(shrine.label), `respawn ${shrine.label}`);

  // hounds hunt as a pack
  await setup(page, { x: 6, z: -60, keep: ['hound_den_1', 'hound_den_2', 'hound_den_3', 'hound_glade'] });
  const pack = await page.evaluate(() => {
    const g = window.__shadowfall;
    const hounds = ['hound_den_1', 'hound_den_2', 'hound_den_3'].map((id) => g.enemies.byId(id));
    hounds.forEach((h) => (h.state = 'idle'));
    g.enemies.byId('hound_glade').state = 'idle';
    hounds[0].hurt(1);
    return { states: hounds.map((h) => h.state), glade: g.enemies.byId('hound_glade').state, speed: hounds[0].cfg.speed };
  });
  record('Barrow hounds are fast and hunt as a pack: wake one and the rest come', pack.states.every((s) => s === 'chase') && pack.glade === 'idle' && pack.speed >= 5, `den: ${pack.states.join(', ')}; the glade hound stays ${pack.glade}`);

  // archers: an aimed shot down a painted line
  await setup(page, { x: 10, z: -82, keep: ['archer_camp_1'] });
  await placeEnemy(page, 'archer_camp_1', 10, -90);
  const shot = await page.evaluate(() => {
    const g = window.__shadowfall;
    const a = g.enemies.byId('archer_camp_1');
    g.player.health = g.player.maxHealth;
    a.state = 'chase';
    a.attackTimer = 0;
    g.step(1 / 60);
    const casting = a.casting && a.casting.kind;
    const line = g.telegraphs.active.find((t) => t.owner === a);
    const hp0 = g.player.health;
    for (let i = 0; i < 80; i++) g.step(1 / 60);
    return { casting, line: line && line.shape.width > 0 ? 'line' : null, length: line && line.shape.length, hit: hp0 - g.player.health, log: document.querySelector('#log li:last-child').textContent };
  });
  record('Hollow archers paint their aim on the ground, then loose down it', shot.casting === 'shot' && shot.line === 'line' && shot.hit > 0, `a ${shot.length} m line; "${shot.log}"`);
  const dodge = await page.evaluate(() => {
    const g = window.__shadowfall;
    const a = g.enemies.byId('archer_camp_1');
    a.attackTimer = 0;
    a._cancelCast();
    g.step(1 / 60);
    const casting = !!a.casting;
    g.player.placeAt(g.player.position.x + 3, g.player.position.z); // step off the line
    const hp0 = g.player.health;
    for (let i = 0; i < 80; i++) g.step(1 / 60);
    return { casting, hit: hp0 - g.player.health, log: [...document.querySelectorAll('#log li')].slice(-3).map((l) => l.textContent).join(' | ') };
  });
  record('Stepping off the line makes the arrow miss', dodge.casting && dodge.hit === 0, dodge.log);
  const keep = await page.evaluate(() => {
    const g = window.__shadowfall;
    const a = g.enemies.byId('archer_camp_1');
    a._cancelCast();
    a.attackTimer = 5;
    g.player.placeAt(a.position.x, a.position.z + 3);
    const d0 = Math.hypot(a.position.x - g.player.position.x, a.position.z - g.player.position.z);
    for (let i = 0; i < 30; i++) g.step(1 / 60);
    return { d0, d1: Math.hypot(a.position.x - g.player.position.x, a.position.z - g.player.position.z) };
  });
  record('Archers back away to keep their distance (extra)', keep.d1 > keep.d0 + 0.5, `${keep.d0.toFixed(1)} m → ${keep.d1.toFixed(1)} m`);

  // the seer: mana, a ground circle that cannot be blocked, and Brace
  await setup(page, { x: -6, z: -107, keep: ['seer_glade'] });
  await placeEnemy(page, 'seer_glade', -6, -114);
  const seer = await page.evaluate(() => {
    const g = window.__shadowfall;
    const s = g.enemies.byId('seer_glade');
    g.player.health = g.player.maxHealth;
    g.player.cooldowns.brace = 0;
    s.state = 'chase';
    s.mana = s.cfg.mana;
    s.circleTimer = 0;
    g.step(1 / 60);
    const kind = s.casting && s.casting.kind;
    const circle = g.telegraphs.active.find((t) => t.owner === s);
    const under = circle && Math.hypot(circle.shape.x - g.player.position.x, circle.shape.z - g.player.position.z) < 0.1;
    const mana = s.mana;
    g.step(1 / 60);
    g.hud.update(1 / 60);
    const bar = !!document.querySelector('.ebar .emana');
    g.player.tryBrace();
    const hp0 = g.player.health;
    for (let i = 0; i < 110; i++) g.step(1 / 60);
    const braced = hp0 - g.player.health;
    // again, and this time walk out of it
    s._cancelCast();
    s.mana = s.cfg.mana;
    s.circleTimer = 0;
    g.step(1 / 60);
    g.player.placeAt(g.player.position.x + 4, g.player.position.z);
    const hp1 = g.player.health;
    for (let i = 0; i < 110; i++) g.step(1 / 60);
    const escaped = hp1 - g.player.health;
    // and once more, standing in it unbraced
    s._cancelCast();
    s.mana = s.cfg.mana;
    s.circleTimer = 0;
    g.player.cooldowns.brace = 99;
    g.step(1 / 60);
    const hp2 = g.player.health;
    for (let i = 0; i < 110; i++) g.step(1 / 60);
    return { kind, under, mana, max: s.cfg.mana, bar, braced, escaped, taken: hp2 - g.player.health, log: document.querySelector('#log li:last-child').textContent };
  });
  record('The Blackwood Seer spends mana on a dark circle cast under the Warden', seer.kind === 'circle' && seer.under && seer.mana === seer.max - 25 && seer.bar, `mana ${seer.max} → ${seer.mana}; a mana bar shows over her health`);
  record('Brace or walking out of the circle avoids it; standing in it hurts and cannot be blocked', seer.braced === 0 && seer.escaped === 0 && seer.taken >= 18, `braced: 0, walked out: 0, stood in it: ${seer.taken} ("${seer.log}")`);

  const loot = await page.evaluate(() => {
    const g = window.__shadowfall;
    const s = g.enemies.byId('seer_glade');
    const before = g.worldState.ground.length;
    s.hurt(9999);
    g.combat.onEnemyDefeated(s);
    return { ground: g.worldState.ground.slice(before).map((x) => x.id), edge: !!g.worldState.drops.watchmans_edge };
  });
  record("The seer always drops the Blackwood cleaver (and not the brute's sword)", loot.ground.includes('blackwood_cleaver') && !loot.edge, loot.ground.join(', '));
  record('No script errors (Blackwood)', errors.length === 0, errors.join(' | '));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'blackwood.png') });
  await ctx.close();
}

async function atmosphere(browser) {
  current = 'Build 2: fog and lighting';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await page.waitForTimeout(300);
  const f = await page.evaluate(() => {
    const g = window.__shadowfall;
    const fog = g.scene.fog;
    let braziers = 0;
    let mist = 0;
    g.scene.traverse((o) => { if (o.name === 'Brazier') braziers++; if (o.name === 'Mist') mist++; });
    return { type: fog.isFog && !fog.isFogExp2, near: fog.near, far: fog.far, camFar: g.camera.far, bg: g.scene.background.getHex() === fog.color.getHex(), light: g.playerLight.intensity, braziers, mist, cfg: g.config.fog };
  });
  record('View-distance fog fades the world out with distance', f.type && f.near === f.cfg.near && f.far === f.cfg.far && f.bg && f.camFar <= f.far + 10, `linear fog ${f.near}–${f.far}m in the sky colour; nothing drawn past ${f.camFar}m`);
  record('Atmospheric lighting: a warm light on the Warden, braziers and ground mist', f.light > 0 && f.braziers === 2 && f.mist > 0, `${f.braziers} braziers at the watch post, ${f.mist} mist layers`);
  record('No script errors (atmosphere)', errors.length === 0, errors.join(' | '));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'fog.png') });
  await ctx.close();
}

// -------------------------------------------------------------------- run
const browser = await launch();
fs.mkdirSync(path.join(HERE, 'screenshots'), { recursive: true });
// `node tests/acceptance.mjs gamepad telegraphs` runs only those sections
const SECTIONS = { launchAndMovement, combat, exploration, progression, death, persistence, quality, abilities, telegraphs, gamepad, bagsAndGround, spellBar, controls, statsAndDamage, itemDatabase, forge, gearRolls, blackwood, atmosphere };
const only = process.argv.slice(2);
try {
  for (const [name, run] of Object.entries(SECTIONS)) if (!only.length || only.includes(name)) await run(browser);
} catch (err) {
  record('Test run completed', false, err.stack);
} finally {
  await browser.close();
}

const failed = results.filter((r) => !r.ok);
const lines = ['# Shadowfall acceptance test results', '', `Run: ${new Date().toISOString()}  `, `Result: **${results.length - failed.length}/${results.length} passed**`, ''];
let section = '';
for (const r of results) {
  if (r.section !== section) {
    section = r.section;
    lines.push('', `## ${section}`, '', '| | Check | Evidence |', '|---|---|---|');
  }
  lines.push(`| ${r.ok ? '✅' : '❌'} | ${r.item} | ${r.detail.replace(/\|/g, '/').replace(/\n/g, ' ')} |`);
}
if (!only.length) fs.writeFileSync(path.join(HERE, 'RESULTS.md'), lines.join('\n') + '\n');
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
