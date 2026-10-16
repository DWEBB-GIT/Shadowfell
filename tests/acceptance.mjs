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

// '#new-btn' makes a new character (with the random name the create screen
// offers) and enters the world; '#continue-btn' plays the last character.
async function begin(page, which = '#new-btn', { pinRolls = true } = {}) {
  await page.click(which);
  if (which === '#new-btn') await page.click('#create-confirm');
  await page.waitForFunction(() => window.__shadowfall.started);
  // combat rolls (weapon range, crits, blocks, enemy variance) land on the
  // average unless a check says otherwise, so expected numbers are exact
  if (pinRolls) await page.evaluate(() => (window.__shadowfall.random = () => 0.5));
  // older checks were written before abilities cost mana or Resolve; the
  // resources section turns costs back on
  await page.evaluate(() => (window.__shadowfall.resources.unlimited = true));
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
      // clickAt is one blow: right-click the enemy there (auto attack), and
      // stop again once the swing has started
      if (clickAt) g.input.mouse.rightClicked = true;
    }
    // rightClick: Shield Break, which now sits in spell-bar slot 2
    if (rightClick) g.input.pressed.add('Digit2');
    let oneSwing = !!clickAt;
    let cd = g.player.cooldowns.attack;
    const dt = 1 / fps;
    const n = Math.round(seconds * fps);
    for (let i = 0; i < n; i++) {
      g.step(dt);
      // rightClick tests Shield Break on its own: the auto attack it starts is stopped
      if (rightClick) g.targeting.stopAttack();
      if (oneSwing && g.player.cooldowns.attack > cd) {
        g.targeting.stopAttack();
        oneSwing = false;
      }
      cd = g.player.cooldowns.attack;
    }
    if (oneSwing) g.targeting.stopAttack();
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
    // where the story quest has got to, in the words these checks have always used
    stage: (() => {
      const st = g.quests.status('missing_delivery');
      if (st === 'done') return 'reported';
      if (st === 'ready') return 'complete';
      return g.worldState.examined.has('cart') ? 'cartFound' : 'start';
    })(),
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
  record('Diagonal movement is normalised', near(diag, straight, 0.05) && near(straight, 5.6, 0.1), `1s straight ${straight.toFixed(2)}m, 1s diagonal ${diag.toFixed(2)}m`);

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
    [['KeyA'], -30, 0], [['KeyD'], 30, 0], [['KeyS'], 0, 96], [['KeyW'], -6, -112],
  ];
  const out = [];
  let inside = true;
  for (const [keys, x, z] of edges) {
    await setup(page, { x, z });
    await sim(page, 6, { held: keys, fps: 30 });
    const s = await state(page);
    const ok = s.pos.x >= -36 && s.pos.x <= 36 && s.pos.z >= -125 && s.pos.z <= 100;
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
  // a left click only selects: no swing
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(300);
  const selected = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { target: g.targeting.current && g.targeting.current.id, attacking: g.targeting.attacking, hp: g.enemies.byId('ghoul_road').health, swung: g.player.cooldowns.attack > 0 || !!g.player.pending };
  });
  record('Left click selects an enemy without attacking (WoW style)', selected.target === 'ghoul_road' && !selected.attacking && selected.hp === 18 && !selected.swung, `target ${selected.target}, ghoul at ${selected.hp}/18`);
  // a right click starts auto attack; stop it after the first swing (the
  // ghoul is given health enough to survive one, for the later checks)
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 400));
  await page.mouse.click(pt.x, pt.y, { button: 'right' });
  // software WebGL runs slowly, so wait for the swing to start and finish in game time
  // (a blow lands when the swing clock runs out; stopping before then calls it off)
  await page.waitForFunction(() => window.__shadowfall.enemies.byId('ghoul_road').health < 400, null, { timeout: 15000 });
  await page.evaluate(() => window.__shadowfall.targeting.stopAttack());
  await pauseLoop(page);
  let g = await enemy(page, 'ghoul_road');
  // one auto attack swing: the worn longsword's 44–59 plus swing power, less the ghoul's armour
  const swingHit = await page.evaluate(() => window.__shadowfall.stats.swingRange);
  record('Basic attack damages a nearby enemy', g.hp <= 400 - swingHit[0] * 0.6 && g.hp > 400 - swingHit[1] * 1.6, `ghoul 1.6m away: 400 → ${g.hp} from one swing of ${swingHit.join('–')} (a real right click, auto attack)`);

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
  await page.evaluate(() => window.__shadowfall.enemies.list.forEach((e) => (e.health = e.maxHealth)));
  await sim(page, 0.6, { rightClick: true });
  let s = await state(page);
  const hpOf = (id) => s.enemies.find((e) => e.id === id).hp;
  // each spawn point's ghoul has its own health: road 18, cart 17, graves 19
  record('Shield Break damages enemies within its radius', hpOf('ghoul_road') === 13 && hpOf('ghoul_cart') === 12 && hpOf('ghoul_graves') === 19,
    `inside radius: ${hpOf('ghoul_road')} (18-5), ${hpOf('ghoul_cart')} (17-5); 5m away: ${hpOf('ghoul_graves')} (19)`);
  const fxSeen = await page.evaluate(() => window.__shadowfall.fx.items.length >= 0);

  // cooldown: second press at 1s is refused, a press after 4s works
  await page.evaluate(() => window.__shadowfall.enemies.list.forEach((e) => (e.health = e.maxHealth)));
  await sim(page, 0.5, { rightClick: true });
  s = await state(page);
  const blocked = hpOf('ghoul_road') === 18;
  const cdLeft = await page.evaluate(() => window.__shadowfall.player.cooldowns.shieldBreak);
  await sim(page, 3.0);
  await sim(page, 0.6, { rightClick: true });
  s = await state(page);
  const worksAgain = hpOf('ghoul_road') === 13;
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
  record('Brace (Space) turns aside the next blow, and only one', br.up && !br.r1 && br.hp1 === 100 && br.r2 && br.hp2 === 95 && /your shield takes/i.test(braceLog),
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
  record('Brace window expires and cannot be spammed', !reBrace && upAt0 && !expired.up && expired.r && expired.hp === 95,
    `re-press on cooldown ignored; raised shield drops after 2.5s and the next claw lands (hp ${expired.hp})`);
  const noSprint = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(0, 20);
    return g.player.position.clone();
  });
  await sim(page, 0.5, { held: ['KeyD', 'ShiftLeft'], press: ['ShiftLeft'] });
  const ns = (await state(page)).pos;
  const walked = Math.hypot(ns.x - noSprint.x, ns.z - noSprint.z);
  record('No dodge or sprint: Shift does nothing special', near(walked, 2.8, 0.2), `${walked.toFixed(2)}m in 0.5s holding D and Shift (running is 5.6 m/s)`);

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
  await page.evaluate(() => { const e = window.__shadowfall.enemies.byId('ghoul_road'); e.health = e.maxHealth; });
  const before = await state(page);
  // one right click: auto attack swings until the ghoul falls (a further
  // right click on the body would loot it)
  await sim(page, 0.05, { aimAt: { x: 0, z: -1.6 } });
  await page.evaluate(() => window.__shadowfall.targeting.engage(window.__shadowfall.enemies.byId('ghoul_road')));
  await sim(page, 7.3); // the first swing waits 2.2 s; two swings fell it
  g = await enemy(page, 'ghoul_road');
  s = await state(page);
  record('Enemy health reaches zero correctly', g && g.hp === 0 && g.dead, `auto attack swings on 18 hp → ${g && g.hp}, dead=${g && g.dead}`);
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
  const objective1 = await page.textContent('#objective');
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
  await setup(page, { x: 0, z: -15, keep: ['ghoul_road'], hp: 3 });
  await placeEnemy(page, 'ghoul_road', 0, -16.4, { attackTimer: 0 });
  await sim(page, 1.0);
  let s = await state(page);
  record('Player death occurs at zero health (extra)', s.dead && s.hp === 0, `hp ${s.hp}`);
  const posDead = s.pos;
  await sim(page, 3.0, { held: ['KeyW'], clickAt: { x: 0, z: -16 }, press: ['Space'] });
  s = await state(page);
  const ghoul = s.enemies.find((e) => e.id === 'ghoul_road');
  record('Player death interrupts combat', s.hp === 0 && s.pos.x === posDead.x && s.pos.z === posDead.z && ghoul.hp === 18 && ghoul.state !== 'attack',
    `no movement or attacks while dead; ghoul ${ghoul.state}`);
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  const deathVisible = await page.isVisible('#death');
  const deathText = await page.textContent('#death');
  record('Death screen appears', deathVisible && /shrine/i.test(deathText), deathText.replace(/\s+/g, ' ').trim());
  await resumeLoop(page);
  await page.click('#respawn-btn');
  await page.waitForTimeout(200);
  await pauseLoop(page);
  // the spirit rises at the shrine; returning to life there costs the coins
  await sim(page, 0.1, { press: ['KeyE'] });
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
  record('Surviving enemies reset to their posts on respawn (extra)', near(ghoulAfter.x, 0, 0.5) && near(ghoulAfter.z, -16.4, 0.5) && ghoulAfter.hp === 18);
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
  record('Manifest progress persists', s.items.includes('manifest') && s.stage === 'complete', `tracker: ${(await page.textContent('#objective')).trim()}`);
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
    // Continue may offer another character, never the one whose save is bad
    const cont = await page.evaluate(() => {
      const c = window.__shadowfall.roster.list.find((x) => x.key === 'shadowfall.save');
      return !document.getElementById('continue-btn').hidden && (!c || document.getElementById('continue-who').textContent.startsWith(c.name + ' ·'));
    });
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
  record('Bottom of the screen has the spell bar, experience bar, bag and menu icons', layout.xp === 1 && layout.slots === 10 && layout.char === 1 && layout.sockets === 4 && layout.barBottom <= layout.h && layout.barTop > layout.h - 140 && layout.xpTop < layout.slotTop,
    `${layout.slots} spell-bar slots (${layout.icons} with icons), experience bar above them, character and save buttons, ${layout.sockets} bag slots; bar spans y ${layout.barTop.toFixed(0)}–${layout.barBottom.toFixed(0)} of ${layout.h}`);

  // GCD: Shield Break then Lunge is refused until the GCD ends; Strike is unaffected
  await setup(page, { x: 0, z: 20 });
  await sim(page, 0.05, { rightClick: true });
  const afterSB = await page.evaluate(() => ({ ...window.__shadowfall.player.cooldowns }));
  await sim(page, 0.4); // let Shield Break land
  await sim(page, 0.05, { press: ['Digit1'] });
  const lungeBlocked = await page.evaluate(() => window.__shadowfall.player.lunge === null && window.__shadowfall.player.cooldowns.lunge === 0);
  const gcdSweep = await page.evaluate(() => parseFloat(document.getElementById('aslot-0').style.getPropertyValue('--gcd')));
  await placeEnemy(page, 'ghoul_road', 0, 18.4, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 500)); // survives the swing
  await sim(page, 0.05, { clickAt: { x: 0, z: 18.4 } });
  const strikeOk = await page.evaluate(() => window.__shadowfall.player.pending?.type === 'strike' || window.__shadowfall.player.cooldowns.attack > 0);
  record('Global cooldown is shared by Shield Break and Lunge (WoW-style)', afterSB.gcd > 1.4 && lungeBlocked && gcdSweep > 0, `GCD ${afterSB.gcd.toFixed(2)}s left just after Shield Break; Lunge pressed 0.45s later was refused; Lunge slot shows the GCD sweep (${gcdSweep.toFixed(2)})`);
  record('Auto attack stays off the global cooldown', strikeOk, 'right-clicking a ghoul during the GCD still swings');
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
  record('Lunge charges towards the cursor and strikes on arrival', moved > 4 && moved < 5.6 && gh.hp < 48, `${moved.toFixed(2)}m charge; ghoul 48 → ${gh.hp}`);
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
      e.health = e.maxHealth;
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
  record('Standing in the telegraph when it fills hits the player', s.hp === 65, `player inside the cone: 100 → ${s.hp} (Grave Slam 31, x1.44 from two levels up, less armour)`);
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
  await padSim(page, 0.05, { tap: [PAD.A] }); // New character
  await padSim(page, 0.05, { tap: [PAD.A] }); // Create and enter
  const started = await page.evaluate(() => window.__shadowfall.started);
  await page.evaluate(() => (window.__shadowfall.random = () => 0.5));
  record('A starts the game from the title screen (new character, then create)', started);

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
  record('Button prompts switch to the gamepad', labels[0] === 'X' && labels[1] === 'LT' && labels[2], `spell bar shows ${labels[0]}, ${labels[1]}`);

  // RT engages the enemy the right stick points at: auto attack
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 1.6, 0, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 48));
  await padSim(page, 0.5, { tap: [PAD.RT], axes: [0, 0, 1, 0] });
  const engaged = await page.evaluate(() => ({ target: window.__shadowfall.targeting.current?.id, attacking: window.__shadowfall.targeting.attacking }));
  await page.evaluate(() => window.__shadowfall.targeting.stopAttack());
  let g = await enemy(page, 'ghoul_road');
  record('RT targets the enemy the right stick points at and auto attacks it', engaged.target === 'ghoul_road' && engaged.attacking && g.hp === 30, `ghoul to the east, right stick east: targeted ${engaged.target}, 48 → ${g.hp}`);
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
  await page.evaluate(() => window.__shadowfall.targeting.clear());
  await padSim(page, 0.4, { tap: [PAD.X], axes: [0, 0, 0, 1] });
  b = (await state(page)).pos;
  record('X (spell-bar slot 1) lunges towards the right stick', b.z - a.z > 4, `${(b.z - a.z).toFixed(2)}m south`);

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
  record('Dragging an item from the bag onto the character panel equips it', st.head === 'watch_helm' && st.max === 100 && st.helm, `helm on the head slot and on the model; maximum health ${st.max}`);
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
  await dragSlot(page, '#aslot-0', '#aslot-3');
  await page.waitForTimeout(150);
  const b1 = await bar();
  const iconMoved = await page.evaluate(() => document.querySelector('#aslot-3').dataset.ability === 'lunge' && document.querySelector('#aslot-0').dataset.ability === 'hallowedBolt');
  record('Spells can be dragged to another slot on the bar', b1[3] === 'lunge' && b1[0] === 'hallowedBolt' && iconMoved, `Lunge and Hallowed Bolt swapped slots 1 and 4 (bar was ${b0.map((a) => a || '—').join(', ')})`);

  await pauseLoop(page);
  await sim(page, 0.05, { press: ['Digit4'], aimAt: { x: 0, z: 14 } });
  const lunged = await page.evaluate(() => window.__shadowfall.player.lunge !== null);
  await sim(page, 2);
  await sim(page, 0.05, { press: ['Digit1'] });
  const nothing = await page.evaluate(() => window.__shadowfall.player.lunge === null && window.__shadowfall.player.cooldowns.gcd === 0);
  record('A moved spell fires from its new key', lunged && nothing, 'key 4 now lunges; key 1 no longer does (Hallowed Bolt, with no target in range)');
  await resumeLoop(page);

  await dragSlot(page, '#aslot-3', { x: 640, y: 300 });
  await page.waitForTimeout(150);
  const b2 = await bar();
  record('Spells can be removed from the bar by dragging them off it', !b2.includes('lunge'), `bar: ${b2.map((a) => a || '—').join(', ')}`);

  await page.keyboard.press('KeyP');
  await page.waitForSelector('#spellbook-window:not([hidden])', { timeout: 10000 });
  await dragSlot(page, '#spellbook-window .islot[data-loc="k:lunge"]', '#aslot-3');
  await page.waitForTimeout(150);
  const b3 = await bar();
  record('The spellbook (P) puts removed spells back on the bar', b3[3] === 'lunge', `Lunge dragged from the spellbook to slot 4 (key 4)`);

  await dragSlot(page, '#aslot-5', '#aslot-4');
  await page.waitForTimeout(150);
  const b4 = await bar();
  record('Swapping two spells swaps their keys (extra)', b4[4] === 'brace' && b4[5] === 'rebuke', 'Brace on 5, Rebuke on 6');

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
  record('Old saves with Dodge on the bar get Brace instead (extra)', bOld[5] === 'brace', bOld.map((a) => a || '—').join(', '));
  record('Old bars keep Shield Break from the mouse buttons, on number keys, and drop Attack (auto attack is off the bar)', bOld.length === 10 && bOld.includes('shieldBreak') && !bOld.includes('strike') && bOld[0] === 'lunge' && bOld[1] === 'draught', bOld.map((a) => a || '—').join(', '));
  const noAttack = await page.evaluate(() => { const g = window.__shadowfall; g.actionBar.place('strike', 2); return g.actionBar.slots.includes('strike'); });
  record('Attack cannot be put on the bar', !noAttack);

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
  const defensive = await page.evaluate(() => document.getElementById('aslot-5').classList.contains('defensive'));
  record('The spell bar is on number keys (the mouse selects and attacks), with Space as the defensive slot', labels.join() === '1,2,3 / Q,4,5,Space,6,7,8,9' && defensive, `slots: ${labels.join(' | ')}`);

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
  record('The camera is fixed (no free rotation)', cam.yaw === undefined && Math.max(...cam.off) < 0.01 && near(b.z - a.z, -5.6, 0.2) && near(b.x - a.x, 0, 0.2),
    `camera holds its isometric offset; W moved (${(b.x - a.x).toFixed(2)}, ${(b.z - a.z).toFixed(2)}), straight up the screen`);

  // nothing selected: a faint ring shows who an ability would go to
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 1.3, -1.5, { frozen: true });
  await sim(page, 0.05, { aimAt: { x: 0, z: -4 } });
  const softRing = await page.evaluate(() => ({ soft: window.__shadowfall.targeting.soft?.id, ring: window.__shadowfall.targeting.softMarker.visible, lock: window.__shadowfall.targeting.current }));
  record('With nothing selected, a faint ring marks the enemy an ability would go to', softRing.soft === 'ghoul_road' && softRing.ring && !softRing.lock, 'aimed 40° off the ghoul: it is marked, nothing selected');
  await sim(page, 0.05, { aimAt: { x: 0, z: 4 } });
  const behind = await page.evaluate(() => window.__shadowfall.targeting.soft);
  let gh = await enemy(page, 'ghoul_road');
  record('That fallback does not reach behind you', !behind, 'aimed the other way: no enemy marked');

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
  record('Lunge (and any targeted spell) goes to the soft-locked enemy', b.x - a.x > 3.5 && gh.hp < 48, `aimed near the ghoul: charged ${(b.x - a.x).toFixed(2)}m east, ghoul 48 → ${gh.hp}`);

  // hard lock: Tab locks what you aim at, a second Tab releases
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'ghoul_cart'] });
  await placeEnemy(page, 'ghoul_road', 0, 1.6, { frozen: true });
  await placeEnemy(page, 'ghoul_cart', 4, -3, { frozen: true });
  await page.evaluate(() => window.__shadowfall.enemies.list.forEach((e) => (e.health = e.maxHealth)));
  await sim(page, 0.05, { aimAt: { x: 4, z: -3 }, press: ['Tab'] });
  const t1 = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  const frame = await page.evaluate(() => ({ vis: !document.getElementById('target-frame').hidden, name: document.getElementById('target-name').textContent, marker: window.__shadowfall.targeting.marker.visible }));
  await sim(page, 0.05, { press: ['Tab'] });
  const t2 = await page.evaluate(() => window.__shadowfall.targeting.current?.id ?? null);
  record('Tab targets the enemy you aim at; Tab again moves to the next', t1 === 'ghoul_cart' && t2 === 'ghoul_road' && frame.vis && frame.marker,
    `targeted ${t1} (frame "${frame.name}", red ring), then ${t2}`);

  // auto attacking, the Warden faces the target and blows go to it
  const t3 = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.engage(g.targeting.current); g.player.cooldowns.attack = 0; });
  await sim(page, 0.55, { aimAt: { x: -4, z: 0 } });
  await page.evaluate(() => window.__shadowfall.targeting.stopAttack());
  const facing = await page.evaluate(() => window.__shadowfall.player.facing);
  gh = await enemy(page, 'ghoul_road');
  record('Auto attack keeps the Warden facing the target and hits it wherever the cursor is', t3 === 'ghoul_road' && Math.cos(facing) > 0.9 && gh.hp < 22,
    `facing ${(facing * 180 / Math.PI).toFixed(0)}° (towards the ghoul); cursor off to the west: ghoul 22 → ${gh.hp}`);
  await sim(page, 0.05, { press: ['Escape'] });
  const cleared = await page.evaluate(() => window.__shadowfall.targeting.current === null && document.getElementById('target-label').textContent !== 'Locked');
  record('Escape clears the target', cleared);
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_cart');
    g.targeting.select(e);
    e.hurt(999);
    g.combat.onEnemyDefeated(e);
  });
  await sim(page, 0.05);
  record('A defeated target is let go (extra)', await page.evaluate(() => window.__shadowfall.targeting.current === null));

  // gamepad: R3 picks a target, RT auto attacks it wherever the stick points
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_road').health = 48; g.player.cooldowns.attack = 0; });
  await padSim(page, 0.05, { tap: [11] });
  const padLock = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await padSim(page, 0.05, { tap: [PAD.RT], axes: [0, 0, -1, 0] });
  await page.evaluate(() => (window.__shadowfall.player.cooldowns.attack = 0)); // skip the first-swing wait
  await padSim(page, 0.5, { axes: [0, 0, -1, 0] });
  await page.evaluate(() => window.__shadowfall.targeting.stopAttack());
  gh = await enemy(page, 'ghoul_road');
  record('R3 picks a target on a gamepad; RT auto attacks it wherever the stick points', padLock === 'ghoul_road' && gh.hp < 48, `targeted ${padLock}; right stick pushed away, RT still hit it (48 → ${gh.hp})`);
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
  await sim(page, 0.02, { aimAt: { x: 4, z: 18 } });
  await page.evaluate(() => { const g = window.__shadowfall; g.input.mouse.clicked = true; g.input.mouse.rightClicked = true; });
  await sim(page, 0.05);
  const struck = await page.evaluate(() => window.__shadowfall.player.cooldowns.attack > 0 || !!window.__shadowfall.player.pending);
  record('Clicking open ground does nothing: no wasted swing', !struck, 'left and right clicks away from anything: no swing');

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
  record('The character panel shows attributes and combat stats', panel.Strength === '4' && panel.Agility === '2' && panel.Stamina === '10' && panel.Weapon === '7–11 / 2.2s' && panel['Damage per second'] === '4.1' && panel.Crit === '6.0%' && panel.Armour === '130 (−21%)' && panel.Block === '10%' && panel.Haste === '0%' && /Mail, Plate, shields/.test(panel.Wears),
    Object.entries(panel).map(([k, v]) => `${k} ${v}`).join(', '));

  // weapon hits roll within the weapon's range
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'brute_hallow'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  const strikeWith = async (seq, id = 'ghoul_road') => {
    await page.evaluate((id) => {
      const g = window.__shadowfall;
      const e = g.enemies.byId(id);
      e.health = 1000; // enough to take any one swing
      e.engaged = 0;
      g.player.cooldowns.attack = 0;
      g.hud.numbers.clear();
    }, id);
    // engaging waits one full swing before the first hit; skip that wait here
    await page.evaluate((id) => { const g = window.__shadowfall; g.targeting.engage(g.enemies.byId(id)); g.player.cooldowns.attack = 0; }, id);
    await rolls(seq);
    await sim(page, 0.45, { clickAt: { x: 0, z: -1.6 } });
    return page.evaluate((id) => {
      const e = window.__shadowfall.enemies.byId(id);
      const n = [...document.querySelectorAll('#damage-numbers .dmg')].map((d) => ({ text: d.textContent, cls: d.className }));
      const dealt = 1000 - e.health;
      e.health = e.maxHealth;
      return { dealt, n, log: document.querySelector('#log li:last-child').textContent };
    }, id);
  };
  const low = await strikeWith([0, 0.99]);
  const high = await strikeWith([0.999, 0.99]);
  const mid = await strikeWith([0.5, 0.99]);
  record('Auto attack swings roll within the weapon range plus power', low.dealt === 7 && high.dealt === 11 && mid.dealt === 9, `lowest roll ${low.dealt}, highest ${high.dealt}, average ${mid.dealt} (worn longsword 3–7 per swing, +1 power × 2.2 s / 0.6 s)`);
  record('Hits show a damage number over the enemy', mid.n.length === 1 && mid.n[0].text === '9' && /dealt/.test(mid.n[0].cls) && !/crit/.test(mid.n[0].cls), JSON.stringify(mid.n));

  const crit = await strikeWith([0.5, 0.01]);
  record('Critical hits do 150% and show a distinct number', crit.dealt === 13 && crit.n[0].text === '13!' && /crit/.test(crit.n[0].cls) && /critical/i.test(crit.log), `${crit.dealt} damage, number "${crit.n[0].text}" (${crit.n[0].cls}); log: "${crit.log}"`);

  // armour reduces damage: the brute (an elite) has 20% of K at its level, 140 armour (17%)
  await placeEnemy(page, 'brute_hallow', 0, -1.6, { frozen: true });
  await placeEnemy(page, 'ghoul_road', 6, 6, { frozen: true });
  const brute = await strikeWith([0.5, 0.99], 'brute_hallow');
  const bruteArmour = await page.evaluate(() => window.__shadowfall.enemies.byId('brute_hallow').cfg.armour);
  record("Armour reduces the damage an enemy takes", brute.dealt === 5 && bruteArmour === 140, `average swing 9 on the level 3 Brute: /1.44 for being two levels above you, then −17% for its ${bruteArmour} armour: ${brute.dealt} (6 without armour)`);
  await placeEnemy(page, 'brute_hallow', -30, 40);
  await page.evaluate(() => { const b = window.__shadowfall.enemies.byId('brute_hallow'); b.cfg = { ...b.cfg, detection: 0 }; });

  // blows on the player: variance, armour, block, crit (a 20-damage blow, so the steps show)
  const hitMe = async (seq, { unclothed = false } = {}) => page.evaluate(({ seq, unclothed }) => {
    const g = window.__shadowfall;
    const q = seq.slice();
    g.random = () => (q.length ? q.shift() : 0.5);
    const e = g.enemies.byId('ghoul_road');
    const cfg = e.cfg;
    e.cfg = { ...cfg, damage: 20 };
    e.position.set(g.player.position.x, 0, g.player.position.z - 1.4);
    const { chest, offHand } = g.inventory.equipment;
    if (unclothed) Object.assign(g.inventory.equipment, { chest: null, offHand: null });
    g.player.health = 100;
    g.player.braced = 0;
    g.hud.numbers.clear();
    g.combat.resolveEnemyStrike(e);
    Object.assign(g.inventory.equipment, { chest, offHand });
    e.cfg = cfg;
    const n = [...document.querySelectorAll('#damage-numbers .dmg')].map((d) => ({ text: d.textContent, cls: d.className }));
    return { taken: 100 - g.player.health, n, log: document.querySelector('#log li:last-child').textContent };
  }, { seq, unclothed });
  const plain = await hitMe([0.5, 0.99, 0.99]);
  const bare = await hitMe([0.5, 0.99, 0.99], { unclothed: true });
  record('Armour reduces the damage the Warden takes', plain.taken === 16 && bare.taken === 20, `a 20-damage blow: ${plain.taken} in travelling clothes and kite shield (130 armour, 21% at level 1), ${bare.taken} with neither`);
  record('Hits taken show a red number', plain.n.length === 1 && plain.n[0].text === '16' && /taken/.test(plain.n[0].cls), JSON.stringify(plain.n));
  const varied = [await hitMe([0, 0.99, 0.99]), await hitMe([1, 0.99, 0.99])].map((h) => h.taken);
  record('Enemy blows vary a little either side of their damage (extra)', varied[0] === 13 && varied[1] === 18, `lowest ${varied[0]}, highest ${varied[1]} (±15% before armour)`);
  const blocked = await hitMe([0.5, 0.99, 0.01]);
  record('A shield block stops 30% of a melee blow', blocked.taken === 11 && /5 blocked/.test(blocked.n[0]?.text || '') && /5 blocked/.test(blocked.log), `16 after armour with 30% blocked: ${blocked.taken}; number "${blocked.n[0]?.text}"; log "${blocked.log}"`);
  const enemyCrit = await hitMe([0.5, 0.01, 0.99]);
  record('Enemies can crit too, shown as a distinct number', enemyCrit.taken === 24 && enemyCrit.n[0].text === '24!' && /taken/.test(enemyCrit.n[0].cls) && /crit/.test(enemyCrit.n[0].cls) && /critically/.test(enemyCrit.log),
    `${enemyCrit.taken} damage; "${enemyCrit.log}"`);
  // no shield, no block: the chance is the shield's own plus block chance from gear
  const noShield = await page.evaluate(() => {
    const g = window.__shadowfall;
    const sh = g.inventory.equipment.offHand;
    g.inventory.equipment.offHand = null;
    const without = g.stats.blockChance;
    g.inventory.equipment.offHand = sh;
    g.config.archetypes.warden.base.block = 5;
    const geared = g.stats.blockChance;
    g.config.archetypes.warden.base.block = 500;
    const capped = g.stats.blockChance;
    g.config.archetypes.warden.base.block = 0;
    return { with: g.stats.blockChance, without, geared, capped, shown: !!g.player.shield };
  });
  record('Block chance comes from the shield and gear, capped at 50%', noShield.with === 10 && noShield.without === 0 && noShield.geared === 15 && noShield.capped === 50 && noShield.shown,
    `kite shield ${noShield.with}%, no shield ${noShield.without}%, +5% from gear ${noShield.geared}%, +500% ${noShield.capped}%; shield worn on the left arm`);

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
  record('Grave Slam cannot crit or be blocked', slam.taken === 30 && !/critical|blocked/i.test(slam.log), `lowest roll of 31 (a quarter of par health at level 3), x1.44 for two levels up, after armour: ${slam.taken}; "${slam.log}"`);

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
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_road').health = 15; g.targeting.clear(); });
  await sim(page, 0.05, { aimAt: { x: 0, z: -3 } });
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  const tf = await page.evaluate(() => ({
    vis: !document.getElementById('target-frame').hidden, name: document.getElementById('target-name').textContent, text: document.getElementById('target-text').textContent,
    label: document.getElementById('target-label').textContent, level: document.getElementById('target-level').textContent, mana: !document.getElementById('target-mana-bar').hidden, bar: !!document.querySelector('#enemy-bars .ebar'),
  }));
  record('Enemy health shows in the target frame without locking on', tf.vis && tf.name === 'Ashen Ghoul' && tf.text === '15 / 18' && tf.level === '1' && !tf.mana && tf.bar,
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
  // level gaps: every hit x1.2 for each level the attacker is above its target;
  // armour works by the defender's own level, so it stops 21% against both
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
    e.cfg = { ...e.cfg, level: 1, damage: 8, crit: 5 };
    return r;
  });
  record('Higher-level enemies hit harder: x1.2 a level', lvl.l1 === 16 && lvl.l5 === 33, `a 20-damage blow: ${lvl.l1} from a level 1 foe, ${lvl.l5} from a level 5 foe (x1.2^4; armour stops 21% of both)`);

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
  record('Haste shortens the time between swings (not the swing itself) and the global cooldown', near(haste.fast.swing, 2.2 / 1.2, 0.001) && near(haste.fast.gcd, 1.25, 0.001) && near(haste.used.cd, 2.2 / 1.2, 0.001) && near(haste.used.windup, 0.32, 0.001) && haste.capped.haste === 30 && near(haste.capped.gcd, 1.154, 0.001),
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
  record('Level-up shows each stat increase', lu.vis && lu.title === 'Level 2' && lu.rows.some((r) => /^Strength 4 → 6 \+2$/.test(r)) && lu.rows.some((r) => /^Stamina 10 → 12 \+2$/.test(r)) && lu.rows.some((r) => /^Maximum health 100 → 112 \+12$/.test(r)) && lu.rows.some((r) => /^Auto attack 4.1 per second → 5.0 per second \+0.9$/.test(r)) && luGone,
    lu.rows.join(' | '));
  record('The character screen marks what rose at the last level-up', ['health+12', 'strength+2', 'stamina+2', 'dps+0.9'].every((m) => marks.includes(m)), marks.join(', '));

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
    return { errors: g.itemErrors, count: Object.keys(g.items).length, missing: Object.entries(g.items).filter(([, d]) => !(Number.isInteger(d.price) && d.icon && d.rarity)).map(([id]) => id) };
  });
  record('Every item comes from one database with slot, stats, price and icon', db.errors.length === 0 && db.missing.length === 0 && db.count >= 9, `${db.count} items in src/data/items.json, all valid`);
  const caught = await page.evaluate(() => {
    const g = window.__shadowfall;
    const bad = { broken_blade: { name: 'Broken blade', kind: 'weapon', slot: 'mainHand', rarity: 'shiny', stack: 1, price: -1, model: 'worn_sword', icon: 'worn_sword', description: 'x' } };
    return g.validateItems(bad, ['mainHand'], ['cloth']);
  });
  record('The database check catches a malformed item (extra)', caught.length >= 3, caught.join('; '));

  await page.evaluate(() => window.__shadowfall.hud.togglePanel('bags'));
  await resumeLoop(page);
  await page.hover('.islot[data-loc="b:0:0"]');
  await page.waitForSelector('#tooltip:not([hidden])', { timeout: 10000 });
  const tip = await page.evaluate(() => ({ text: document.getElementById('tooltip').textContent, q: document.querySelector('#tooltip .tt-name').className }));
  record('Tooltips show what a merchant would pay, and the item rarity', /Sells for 1 coin/.test(tip.text) && /q-common/.test(tip.q), tip.text.replace(/\s+/g, ' ').slice(0, 140));
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
    const options = [...document.querySelectorAll('#dlg-options [data-option]')].map((b) => b.dataset.option);
    return { prompt, talking: g.dialogue.isOpen && !document.getElementById('dialogue-window').hidden, options, mara: !!g.npcs.byId('mara') };
  });
  await page.click('#dlg-options [data-option="shop"]');
  Object.assign(talk, await page.evaluate(() => {
    const g = window.__shadowfall;
    g.step(1 / 60);
    return { current: g.merchant.current, shop: !document.getElementById('shop-window').hidden, bags: g.hud.items.openBags.size > 0, stock: document.querySelectorAll('#shop-stock .islot').length, talking: g.dialogue.isOpen };
  }));
  const maraStock = await page.evaluate(() => window.__shadowfall.db.shops.mara_forge.stock.length); // (from data/shops.json)
  record('Mara Venn stands at her forge; talking to her offers her wares, which open beside the bags', talk.mara && talk.prompt === 'Talk to Mara Venn' && talk.options.includes('shop') && talk.current === 'mara_forge' && talk.shop && talk.bags && talk.stock === maraStock && !talk.talking, `prompt "${talk.prompt}", choices: ${talk.options.join(', ')}; ${talk.stock} items for sale, bags open: ${talk.bags}`);

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

  // the manifest goes to Mara through the conversation, not the shop
  const handIn = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('manifest', 1, { quiet: true });
    g.worldState.examined.add('cart');
    g.worldState.collected.add('manifest');
    g.events.emit('examined', { id: 'cart' });
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'manifest');
    const sold = g.merchant.sell(loc);
    g.merchant.close();
    g.npcs.talk(g.npcs.byId('mara'));
    g.step(1 / 60);
    const first = document.querySelector('#dlg-options [data-option]');
    const before = { stage: g.quests.status('missing_delivery'), tracker: document.getElementById('objective').textContent, first: first.dataset.option, firstClass: first.className, mark: g.quests.markerFor('mara') };
    window.__c0 = g.inventory.coins;
    return { sold, before };
  });
  await page.click('#dlg-options [data-option="quest:missing_delivery"]');
  const page2 = await page.evaluate(() => ({ head: document.getElementById('dlg-qhead').textContent, options: [...document.querySelectorAll('#dlg-options [data-option]')].map((b) => b.dataset.option) }));
  await page.click('#dlg-options [data-option="complete"]');
  Object.assign(handIn, await page.evaluate(() => {
    const g = window.__shadowfall;
    g.step(1 / 60);
    return {
      coins: g.inventory.coins - window.__c0, xp: g.progression.xp, level: g.progression.level,
      manifest: g.inventory.count('manifest'), flag: g.worldState.flags.has('manifest_delivered'),
      status: g.quests.status('missing_delivery'), mark: g.quests.markerFor('mara'),
      options: [...document.querySelectorAll('#dlg-options [data-option]')].map((b) => b.dataset.option),
    };
  }));
  record('Quest items cannot be sold', !handIn.sold, 'the manifest stays in the bags');
  record('With the manifest in hand Mara shows a ? and the quest is first in her conversation', handIn.before.stage === 'ready' && handIn.before.mark === 'ready' && /Return to Mara/.test(handIn.before.tracker) && handIn.before.first === 'quest:missing_delivery' && /ready/.test(handIn.before.firstClass) && /Ready to hand in/.test(page2.head) && page2.options.includes('complete'),
    `tracker: "${handIn.before.tracker.trim()}"; quest page: "${page2.head}"`);
  record('Handing Mara the manifest pays 20 coins and 50 experience, and she offers the next quests', handIn.coins === 20 && handIn.xp === 50 && handIn.manifest === 0 && handIn.flag && handIn.status === 'done' && handIn.mark === 'available' && handIn.options.includes('quest:bells_at_hallow_cut') && handIn.options.includes('quest:the_hound_den'),
    `+${handIn.coins} coins, ${handIn.xp} xp; Mara now shows ${handIn.mark === 'available' ? '!' : handIn.mark}; choices: ${handIn.options.join(', ')}`);

  await page.evaluate(() => window.__shadowfall.player.placeAt(24, -38));
  await sim(page, 0.2);
  const away = await page.evaluate(() => ({ talking: window.__shadowfall.dialogue.isOpen, shown: !document.getElementById('dialogue-window').hidden }));
  record('Walking away ends the conversation', !away.talking && !away.shown);

  await page.evaluate(() => window.__shadowfall.manualSave());
  await page.reload();
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  errors.length = 0;
  await begin(page, '#continue-btn');
  const saved = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { flag: g.worldState.flags.has('manifest_delivered'), status: g.quests.status('missing_delivery'), mark: g.quests.markerFor('mara') };
  });
  record('The finished quest persists through save and reload', saved.flag && saved.status === 'done' && saved.mark === 'available', `story quest ${saved.status}; Mara shows ${saved.mark === 'available' ? '!' : saved.mark}`);
  record("No script errors (Mara's forge)", errors.length === 0, errors.join(' | '));
  await ctx.close();

  // the gamepad: A talks, A on "Let me see your wares", A on a stock item buys it
  ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await ctx.addInitScript(PAD_STUB);
  ({ page, errors } = await openGame(ctx));
  await pauseLoop(page);
  await padSim(page, 0.05, { tap: [PAD.A] }); // New character
  await padSim(page, 0.05, { tap: [PAD.A] }); // Create and enter
  await page.evaluate(() => (window.__shadowfall.random = () => 0.5));
  await setup(page, { x: 16.2, z: -40.5 });
  await page.evaluate(() => (window.__shadowfall.inventory.coins = 20));
  await padSim(page, 0.05, { tap: [PAD.A] }); // talk
  const talking = await page.evaluate(() => window.__shadowfall.dialogue.isOpen);
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.hud.quests.choice = g.dialogue.page.options.findIndex((o) => o.id === 'shop');
  });
  await padSim(page, 0.05, { tap: [PAD.A] }); // wares
  const padOpen = await page.evaluate(() => window.__shadowfall.merchant.current);
  await page.evaluate(() => (window.__shadowfall.hud.items.focus = 'm:healing_draught'));
  await padSim(page, 0.05, { tap: [PAD.A] });
  const pad = await page.evaluate(() => ({ coins: window.__shadowfall.inventory.coins, draughts: window.__shadowfall.inventory.count('healing_draught') }));
  record('With a gamepad, A talks to Mara, picks her wares, and buys', talking && padOpen === 'mara_forge' && pad.coins === 14, `${pad.coins} coins left, ${pad.draughts} draughts`);
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
      // common gear dropping at enhanced gains a suffix; at common it never does
      const h = g.rollItem('warden_hauberk', Math.random, i % 2 ? 'enhanced' : 'common');
      if (!(i % 2) && h && h.suffix) suffixed = -999;
      const a = g.itemView({ id: 'warden_hauberk', rolls: h }).stats.armour;
      if (h && h.suffix) suffixed++;
      seen.add(a);
      if (a < 63 * 0.8 - 0.5 || a > 63 * 1.2 + 0.5) armourOk = false;
      const f = g.itemView({ id: 'rusted_falchion', rolls: g.rollItem('rusted_falchion', Math.random) }).damage;
      if (f[0] < 4 * 0.88 - 0.5 || f[1] > 10 * 1.12 + 0.5 || f[0] > f[1]) damageOk = false;
    }
    return { suffixed, armourOk, damageOk, kinds: seen.size, material: g.rollItem('grave_iron', Math.random), quest: g.rollItem('manifest', Math.random) };
  });
  record('Dropped gear rolls its stats a little either side of the database values', spread.armourOk && spread.damageOk && spread.kinds >= 4, `hauberk armour rolled ${spread.kinds} different values within ±20% of 63; falchion damage within ±12%`);
  record('Gear dropping as Enhanced (green) always gains a WoW-style suffix; Common (white) never does', spread.suffixed === 150, `${spread.suffixed} of 150 enhanced hauberks rolled a suffix, none of 150 common ones`);
  record('Materials and quest items never roll (extra)', spread.material === null && spread.quest === null);

  const worn = await page.evaluate(() => {
    const g = window.__shadowfall;
    const vals = [0.95, 0.9, 0.99]; // armour +11, the Swiftness suffix, its haste at the top of its roll
    let i = 0;
    const rolls = g.rollItem('warden_hauberk', () => vals[i++], 'enhanced');
    const view = g.itemView({ id: 'warden_hauberk', rolls });
    g.inventory.addItem('warden_hauberk', 1, { rolls });
    const a0 = g.stats.armour;
    g.inventory.equip('warden_hauberk');
    g.hud.togglePanel('character');
    return { rolls, name: view.name, rarity: view.rarity, armour: g.stats.armour, a0, haste: g.stats.haste, panel: document.getElementById('char-stats').textContent };
  });
  // the suffix spends the green budget of a level 3 chest: 2.8 points, 6% haste (+-20%)
  record('A rolled item is named for its suffix and counts its rolled stats when worn', worn.name === "Warden's hauberk of Swiftness" && worn.rarity === 'enhanced' && worn.armour === 174 && worn.haste === 7, `${worn.name}: ${JSON.stringify(worn.rolls)}; armour ${worn.a0} → ${worn.armour} (hauberk 63 + 11, kite shield 100), haste ${worn.haste}%`);

  await resumeLoop(page);
  await page.hover('.islot[data-loc="e:chest"]');
  await page.waitForSelector('#tooltip:not([hidden])', { timeout: 10000 });
  const tip = await page.evaluate(() => ({ text: document.getElementById('tooltip').textContent, q: document.querySelector('#tooltip .tt-name').className }));
  record('Tooltips show the rolled name, rarity and stats', /of Swiftness/.test(tip.text) && /\+74 armour/i.test(tip.text) && /\+7 ?% haste/i.test(tip.text) && /Item level 3/.test(tip.text) && /q-enhanced/.test(tip.q), tip.text.replace(/\s+/g, ' ').slice(0, 120));
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
  record('Rolled gear is the same after a reload', loaded.chest.rolls && loaded.chest.rolls.suffix === 'swiftness' && loaded.armour === 174, JSON.stringify(loaded.chest));

  await pauseLoop(page);
  const drop = await page.evaluate(() => {
    const g = window.__shadowfall;
    const before = g.worldState.ground.length;
    const seq = [0.1, 0.6, 0.1]; // under the ghoul's drop chance, then the common rarity, then the first item
    g.random = () => (seq.length ? seq.shift() : 0.5);
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
    g.spells.tryCast('brace');
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
async function questsAndMap(browser) {
  current = 'Quests, dialogue, quest log and minimap';
  let { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const shots = path.join(HERE, '..', 'docs', 'screens');
  fs.mkdirSync(shots, { recursive: true });

  // a new game starts with the story quest in hand and tracked
  await setup(page, { x: 16.2, z: -38.8 });
  await sim(page, 0.1);
  const start = await page.evaluate(() => {
    const g = window.__shadowfall;
    const mark = document.querySelector('.npc-mark');
    return {
      status: g.quests.status('missing_delivery'), tracked: g.quests.tracked.has('missing_delivery'),
      tracker: document.getElementById('objective').textContent, mara: g.quests.markerFor('mara'),
      markText: mark && mark.textContent, markShown: mark && mark.style.display !== 'none', markClass: mark && mark.className,
    };
  });
  record('A new game starts with the story quest in hand, tracked under the map', start.status === 'active' && start.tracked && /Recover the cart's manifest/.test(start.tracker), `tracker: "${start.tracker.trim()}"`);
  record('Mara shows a grey ? while her quest is in hand', start.mara === 'active' && start.markText === '?' && start.markShown && /active/.test(start.markClass), `${start.markText} (${start.markClass})`);

  // the story quest, done quickly
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.interaction.examine('cart');
    g.inventory.addItem('manifest', 1, { quiet: true });
    g.npcs.talk(g.npcs.byId('mara'));
    g.dialogue.choose('quest:missing_delivery');
    g.dialogue.choose('complete');
  });
  const after = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.step(1 / 60);
    const mark = document.querySelector('.npc-mark');
    return { mara: g.quests.markerFor('mara'), markText: mark.textContent, markClass: mark.className, options: g.dialogue.page.options.map((o) => o.id) };
  });
  record('Mara shows a gold ! when she has a quest to give', after.mara === 'available' && after.markText === '!' && /available/.test(after.markClass), `${after.markText} (${after.markClass})`);

  // a quest is offered with its objectives and rewards, and accepted by clicking
  await page.click('#dlg-options [data-option="quest:the_hound_den"]');
  const offer = await page.evaluate(() => ({
    head: document.getElementById('dlg-qhead').textContent, text: document.getElementById('dlg-text').textContent,
    quest: document.getElementById('dlg-quest').textContent, options: [...document.querySelectorAll('#dlg-options [data-option]')].map((b) => b.textContent.trim()),
  }));
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  await page.screenshot({ path: path.join(shots, 'quest-offer.png') });
  record('A quest offer shows what to do and what it pays, with Accept and Decline', /New quest/.test(offer.head) && /Barrow Hounds slain: 0\/3/.test(offer.quest) && /25/.test(offer.quest) && /70 experience/.test(offer.quest) && /Healing draught ×2/.test(offer.quest) && offer.options.some((o) => /Accept/.test(o)) && offer.options.some((o) => /Decline/.test(o)),
    `"${offer.text.slice(0, 60)}…" / ${offer.quest.replace(/\s+/g, ' ').slice(0, 120)}`);
  await page.click('#dlg-options [data-option="accept"]');
  const took = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.step(1 / 60);
    return { status: g.quests.status('the_hound_den'), tracked: g.quests.tracked.has('the_hound_den'), log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).join(' | '), tracker: document.getElementById('objective').textContent, back: g.dialogue.view.kind };
  });
  record('Accepting puts the quest in the log, tracks it, and returns to the conversation', took.status === 'active' && took.tracked && /Quest accepted: The Hound Den/.test(took.log) && /Barrow Hounds slain: 0\/3/.test(took.tracker) && took.back === 'menu', `tracker: "${took.tracker.trim().replace(/\s+/g, ' ')}"`);

  // the seer's quest waits on the two before it
  const locked = await page.evaluate(() => ({ seer: window.__shadowfall.quests.status('the_glade_seer'), offered: window.__shadowfall.dialogue.page.options.map((o) => o.id) }));
  record('A quest that needs others done first is not offered yet', locked.seer === 'locked' && !locked.offered.includes('quest:the_glade_seer'), `The Seer in the Glade: ${locked.seer}`);

  // a dialogue tree
  const tree = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.dialogue.choose('node:mara_who');
    const a = { text: g.dialogue.page.text, replies: g.dialogue.page.options.map((o) => o.text) };
    g.dialogue.choose('node:mara_watch');
    const b = g.dialogue.page.text;
    g.dialogue.choose('menu');
    return { a, b, back: g.dialogue.view.kind, blackwood: g.dialogue.page.options.some((o) => o.id === 'node:mara_blackwood') };
  });
  record('Topics open a small dialogue tree and lead back to the greeting', /Mara Venn. I keep the forge/.test(tree.a.text) && tree.a.replies.includes('What happened to the watch?') && /Gone quiet/.test(tree.b) && tree.back === 'menu', `"${tree.a.text.slice(0, 50)}…" → "${tree.b.slice(0, 40)}…"`);
  record('Some topics only open up as the story moves on (extra)', tree.blackwood, 'Tell me about the Blackwood: offered once the manifest is delivered');

  // kills count, even ones made before the quest was taken
  const hounds = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.dialogue.close();
    const kill = (id) => g.combat.onEnemyDefeated(g.enemies.byId(id));
    kill('hound_den_1');
    kill('hound_den_2');
    const two = g.quests.objectives('the_hound_den')[1].have;
    const log = [...document.querySelectorAll('#log li')].map((l) => l.textContent);
    kill('hound_den_3');
    g.interaction.examine('hound_den');
    return { two, log: log.join(' | '), status: g.quests.status('the_hound_den'), mark: g.quests.markerFor('mara'), tracker: document.getElementById('objective').textContent };
  });
  record('Kills move the objective on, with a line in the log', hounds.two === 2 && /Barrow Hounds slain: 2\/3/.test(hounds.log), `"${hounds.log.split(' | ').filter((l) => /slain/.test(l)).join('", "')}"`);
  record('When every objective is met the tracker says to return, and Mara shows a gold ?', hounds.status === 'ready' && hounds.mark === 'ready' && /Return to Mara Venn/.test(hounds.tracker), `tracker: "${hounds.tracker.trim().replace(/\s+/g, ' ')}"`);
  const bells = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.combat.onEnemyDefeated(g.enemies.byId('brute_hallow'));
    g.npcs.talk(g.npcs.byId('mara'));
    g.dialogue.choose('quest:bells_at_hallow_cut');
    g.dialogue.choose('accept');
    return { objectives: g.quests.objectives('bells_at_hallow_cut').map((o) => `${o.have}/${o.need}`), status: g.quests.status('bells_at_hallow_cut') };
  });
  record('An enemy slain before the quest was taken still counts (enemies do not return)', bells.objectives[1] === '1/1' && bells.status === 'active', `Bells at Hallow Cut: ${bells.objectives.join(', ')}`);

  // hand-in with an item reward
  const hand = await page.evaluate(() => {
    const g = window.__shadowfall;
    const d0 = g.inventory.count('healing_draught');
    const c0 = g.inventory.coins;
    g.dialogue.choose('quest:the_hound_den');
    const ok = g.dialogue.choose('complete');
    return { ok, draughts: g.inventory.count('healing_draught') - d0, coins: g.inventory.coins - c0, status: g.quests.status('the_hound_den') };
  });
  record('Handing in pays coins and puts item rewards in the bags', hand.ok && hand.draughts === 2 && hand.coins === 25 && hand.status === 'done', `+${hand.coins} coins, +${hand.draughts} healing draughts`);

  // the quest log: L, tracking, abandoning
  await page.evaluate(() => window.__shadowfall.dialogue.close());
  await sim(page, 0.05, { press: ['KeyL'] });
  await page.evaluate(() => window.__shadowfall.hud.quests.select('bells_at_hallow_cut'));
  const log1 = await page.evaluate(() => ({ open: !document.getElementById('questlog-window').hidden, rows: [...document.querySelectorAll('.ql-row')].map((r) => r.textContent), detail: document.getElementById('ql-detail').textContent }));
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  await page.screenshot({ path: path.join(shots, 'quest-log.png') });
  record('L opens the quest log: quests in hand on the left, the chosen one in full on the right', log1.open && log1.rows.length === 1 && /Bells at Hallow Cut/.test(log1.rows[0]) && /Look over the graves/.test(log1.detail) && /Gravebound Brute slain: 1\/1/.test(log1.detail) && /Hand in to Mara Venn/.test(log1.detail), `rows: ${log1.rows.join(', ')}`);
  await page.click('#ql-detail [data-act="track"]');
  const untracked = await page.evaluate(() => ({ tracked: window.__shadowfall.quests.tracked.has('bells_at_hallow_cut'), tracker: document.getElementById('objective').hidden }));
  await page.click('#ql-detail [data-act="abandon"]');
  const asked = await page.evaluate(() => ({ status: window.__shadowfall.quests.status('bells_at_hallow_cut'), button: document.querySelector('#ql-detail [data-act="abandon"]').textContent }));
  await page.click('#ql-detail [data-act="abandon"]');
  const gone = await page.evaluate(() => ({ status: window.__shadowfall.quests.status('bells_at_hallow_cut'), rows: document.querySelectorAll('.ql-row').length }));
  record('Quests can be untracked, and abandoned after a second click to confirm', !untracked.tracked && untracked.tracker && asked.status === 'active' && /Really/.test(asked.button) && gone.status === 'available' && gone.rows === 0, `untracked (tracker hidden: ${untracked.tracker}); first click: "${asked.button}"; then ${gone.status}`);
  await sim(page, 0.05, { press: ['KeyL'] });
  const closed = await page.evaluate(() => document.getElementById('questlog-window').hidden);
  record('L closes the quest log again', closed);

  // the minimap
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.quests.accept('bells_at_hallow_cut');
  });
  const map = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(14, -30);
    g.step(1 / 60);
    g.player.facing = Math.PI / 2; // east
    g.hud.minimap.draw();
    const c = document.getElementById('minimap');
    const r = c.getBoundingClientRect();
    const ctx = c.getContext('2d');
    const k = c.width / c.clientWidth;
    const px = (x, y) => [...ctx.getImageData(Math.round(x * k), Math.round(y * k), 1, 1).data];
    // the arrow points east: its white body runs right of the centre, and nothing points north
    const R = c.clientWidth / 2;
    const east = px(R + 2, R);
    const north = px(R, R - 6);
    const marks = g.hud.minimap.markers();
    return {
      box: { right: window.innerWidth - r.right, top: r.top, w: r.width },
      east, north,
      mara: marks.find((m) => m.label === 'Mara Venn'),
      maraMark: g.quests.markerFor('mara'),
      areas: marks.filter((m) => m.kind === 'area').map((m) => m.label),
      shrines: marks.filter((m) => m.kind === 'shrine').length,
    };
  });
  const white = (p) => p[0] > 200 && p[1] > 200 && p[2] > 200;
  record('A round minimap sits in the top-right corner', map.box.right < 30 && map.box.top < 30 && map.box.w > 120, `${map.box.w}px across, ${map.box.right.toFixed(0)}px from the right`);
  record('The Warden is an arrow pointing the way they face (north up)', white(map.east) && !white(map.north), `facing east: right of centre ${map.east.slice(0, 3)}, above centre ${map.north.slice(0, 3)}`);
  record('Quest markers on the map: ! and ? on quest givers, and the places objectives point to', map.mara && map.mara.kind === map.maraMark && map.mara.kind === 'active' && map.areas.includes('Hallow Cut') && map.shrines === 2,
    `Mara: ${map.mara && map.mara.kind}; objective areas: ${map.areas.join(', ')}`);
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(16.5, -38.5);
    g.player.facing = Math.PI * 0.8;
    g.npcs.talk(g.npcs.byId('mara'));
    g._snapCamera();
    g.step(1 / 60);
  });
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  await page.screenshot({ path: path.join(shots, 'quest-dialogue-minimap.png') });

  // the gamepad: D-pad right opens the log, X tracks, B closes; in a conversation up/down and A
  await ctx.close();
  ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  await ctx.addInitScript(PAD_STUB);
  ({ page, errors } = await openGame(ctx));
  await pauseLoop(page);
  await padSim(page, 0.05, { tap: [PAD.A] }); // New character
  await padSim(page, 0.05, { tap: [PAD.A] }); // Create and enter
  await setup(page, { x: 0, z: 20 });
  await padSim(page, 0.05, { tap: [PAD.RIGHT] });
  const padLog = await page.evaluate(() => ({ open: window.__shadowfall.hud.quests.logOpen, sel: window.__shadowfall.hud.quests.selected }));
  await padSim(page, 0.05, { tap: [PAD.X] });
  const padTrack = await page.evaluate(() => window.__shadowfall.quests.tracked.has('missing_delivery'));
  await padSim(page, 0.05, { tap: [PAD.B] });
  const padClosed = await page.evaluate(() => !window.__shadowfall.hud.quests.logOpen);
  await setup(page, { x: 16.2, z: -40.5 });
  await padSim(page, 0.05, { tap: [PAD.A] });
  await padSim(page, 0.3, { tap: [PAD.DOWN] });
  const padChoice = await page.evaluate(() => window.__shadowfall.hud.quests.choice);
  await padSim(page, 0.05, { tap: [PAD.A] });
  const padNode = await page.evaluate(() => window.__shadowfall.dialogue.view);
  await padSim(page, 0.05, { tap: [PAD.B] });
  const padBack = await page.evaluate(() => window.__shadowfall.dialogue.view && window.__shadowfall.dialogue.view.kind);
  record('With a gamepad: D-pad right opens the log, X tracks, B closes; up/down and A pick in a conversation, B goes back', padLog.open && padLog.sel === 'missing_delivery' && !padTrack && padClosed && padChoice === 1 && padNode.kind === 'node' && padBack === 'menu',
    `log ${padLog.open ? 'opened' : 'shut'} on ${padLog.sel}; tracked after X: ${padTrack}; picked choice ${padChoice} → ${padNode.kind} ${padNode.id || ''}; B → ${padBack}`);
  record('No script errors (quests, gamepad)', errors.length === 0, errors.join(' | '));
  await ctx.close();

  // saves: the log persists; old saves start from the story flag; bad ids are refused
  ({ ctx, page, errors } = await freshGame(browser));
  await begin(page);
  const saves = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.quests.done.add('missing_delivery');
    g.quests.accepted = ['missing_delivery', 'the_hound_den'];
    g.quests.tracked = new Set(['the_hound_den']);
    const data = g.save.serialize();
    const old = JSON.parse(JSON.stringify(data));
    delete old.quests;
    old.world.flags = ['manifest_delivered'];
    const bad = JSON.parse(JSON.stringify(data));
    bad.quests.accepted.push('slay_the_dragon');
    g.save.apply(old);
    const migrated = { done: [...g.quests.done], active: g.quests.active };
    old.world.flags = [];
    g.save.apply(old);
    const fresh = g.quests.active;
    g.save.apply(data);
    return { migrated, fresh, restored: g.quests.serialize(), badErrors: g.validateSave(bad), goodErrors: g.validateSave(data) };
  });
  record('The quest log is saved and restored', saves.restored.done.includes('missing_delivery') && saves.restored.accepted.includes('the_hound_den') && saves.restored.tracked.join() === 'the_hound_den' && saves.goodErrors.length === 0, JSON.stringify(saves.restored));
  record('Saves from before the quest log carry on where the story was', saves.migrated.done.includes('missing_delivery') && saves.migrated.active.length === 0 && saves.fresh.join() === 'missing_delivery', `flag set: done ${saves.migrated.done}; no flag: in hand ${saves.fresh}`);
  record('A save naming a quest that does not exist is refused', saves.badErrors.includes('quest log'), saves.badErrors.join(', '));
  record('No script errors (quests)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function clickTargeting(browser) {
  current = 'Click to target and auto attack';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const rightClickOn = (id) => page.evaluate((id) => {
    const g = window.__shadowfall;
    const e = g.enemies.byId(id) || g.npcs.byId(id);
    const v = e.position.clone().setY(e.position.y + 1).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    g.input.mouse.x = r.left + ((v.x + 1) / 2) * r.width;
    g.input.mouse.y = r.top + ((1 - v.y) / 2) * r.height;
    g.input.mouse.ndcX = v.x;
    g.input.mouse.ndcY = v.y;
    g.input.mouse.rightClicked = true;
  }, id);

  // auto attack keeps swinging until the target falls, then stops
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'ghoul_cart'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await placeEnemy(page, 'ghoul_cart', 2.5, 1, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 20));
  await rightClickOn('ghoul_road');
  // the first blow lands as soon as you are in reach (WoW), then every T
  const TT = await page.evaluate(() => window.__shadowfall.stats.attackCooldown);
  await sim(page, 0.3);
  const mid = await page.evaluate(() => ({ hp: window.__shadowfall.enemies.byId('ghoul_road').health, attacking: window.__shadowfall.targeting.attacking, label: document.getElementById('target-label').textContent, cd: window.__shadowfall.player.cooldowns.attack }));
  await sim(page, TT);
  const second = await page.evaluate(() => window.__shadowfall.enemies.byId('ghoul_road').health);
  await sim(page, TT + 0.3);
  const end = await page.evaluate(() => ({ dead: window.__shadowfall.enemies.byId('ghoul_road').dead, attacking: window.__shadowfall.targeting.attacking, target: window.__shadowfall.targeting.current }));
  record('Right click starts auto attack, which swings on the weapon speed until the target falls', mid.hp < 20 && mid.hp - second === 20 - mid.hp && mid.attacking && mid.label === 'Attacking' && end.dead && !end.attacking && !end.target,
    `20 → ${mid.hp} at once (next in ${mid.cd.toFixed(2)}s of ${TT}s) → ${second} a swing later (frame: "${mid.label}"); then it fell and auto attack stopped`);

  // right-clicking does not snap the Warden round: moving, he faces where he
  // walks and holds his swing; standing still, he turns to the target
  await setup(page, { x: 0, z: 0, keep: ['ghoul_cart'] });
  await placeEnemy(page, 'ghoul_cart', 0, -1.6, { frozen: true });
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_cart').health = 500; g.player.facing = 0; g.player.cooldowns.attack = 0; });
  await rightClickOn('ghoul_cart');
  await sim(page, 0.05);
  const snap = await page.evaluate(() => ({ facing: window.__shadowfall.player.facing, swung: !!window.__shadowfall.player.pending || window.__shadowfall.player.cooldowns.attack > 0 }));
  await sim(page, 0.1);
  const turning = await page.evaluate(() => window.__shadowfall.player.facing);
  await sim(page, 1.0);
  const faced = await page.evaluate(() => ({ facing: window.__shadowfall.player.facing, hp: window.__shadowfall.enemies.byId('ghoul_cart').health }));
  const off = (a) => Math.abs(Math.atan2(Math.sin(a - Math.PI), Math.cos(a - Math.PI)));
  record('Right-clicking an enemy behind you does not snap you round; standing still you turn to it and swing', off(snap.facing) > 2.8 && !snap.swung && off(turning) > 1.5 && off(faced.facing) < 0.6 && faced.hp < 500,
    `facing ${(off(snap.facing) * 57.3).toFixed(0)}° from it on the click, ${(off(turning) * 57.3).toFixed(0)}° 0.15s later, ${(off(faced.facing) * 57.3).toFixed(0)}° after 1.15s; ghoul 500 → ${faced.hp}`);
  await page.evaluate(() => window.__shadowfall.targeting.clear());

  // picking another target stops auto attack; Tab cycles; Esc clears
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_cart').health = 48));
  await rightClickOn('ghoul_cart');
  await sim(page, 0.05);
  const before = await page.evaluate(() => window.__shadowfall.targeting.attacking);
  await setup(page, { x: 0, z: 0, keep: ['ghoul_cart', 'ghoul_graves'], park: false });
  await placeEnemy(page, 'ghoul_graves', -2, -2, { frozen: true });
  await sim(page, 0.05, { press: ['Tab'] });
  const afterTab = await page.evaluate(() => ({ target: window.__shadowfall.targeting.current?.id, attacking: window.__shadowfall.targeting.attacking }));
  await sim(page, 0.05, { press: ['Tab'] });
  const tab2 = await page.evaluate(() => window.__shadowfall.targeting.current?.id);
  await sim(page, 0.05, { press: ['Escape'] });
  const cleared = await page.evaluate(() => window.__shadowfall.targeting.current);
  record('Picking another target stops auto attack; Tab cycles targets; Esc clears', before && afterTab.target && afterTab.target !== 'ghoul_cart' && !afterTab.attacking && tab2 && tab2 !== afterTab.target && !cleared,
    `Tab: ghoul_cart → ${afterTab.target} → ${tab2}; Esc cleared it`);

  // auto attack is not a spell: it is not on the bar or in the spellbook
  const offBar = await page.evaluate(() => ({ bar: window.__shadowfall.actionBar.slots }));
  record('Auto attack is not on the bar (key 5 is Rebuke)', !offBar.bar.includes('strike') && offBar.bar[4] === 'rebuke', offBar.bar.map((a) => a || '—').join(', '));

  // abilities go to the target wherever the cursor is
  await setup(page, { x: 0, z: 0, keep: ['ghoul_graves'] });
  await placeEnemy(page, 'ghoul_graves', 0, 5.5, { frozen: true });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.cooldowns.lunge = 0;
    g.player.cooldowns.gcd = 0;
    g.targeting.select(g.enemies.byId('ghoul_graves'));
  });
  await sim(page, 0.5, { press: ['Digit1'], aimAt: { x: 0, z: -6 } });
  const lunge = await page.evaluate(() => ({ z: window.__shadowfall.player.position.z, hp: window.__shadowfall.enemies.byId('ghoul_graves').health }));
  record('Abilities go to the selected target, not the cursor', lunge.z > 3 && lunge.hp < 48, `cursor north, target south: lunged to z ${lunge.z.toFixed(1)}, ghoul ${lunge.hp}/48`);

  // townsfolk: left click selects, right click talks
  await setup(page, { x: 16.2, z: -40.5 });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const n = g.npcs.byId('mara');
    const v = n.position.clone().setY(n.position.y + 1).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    g.input.mouse.x = r.left + ((v.x + 1) / 2) * r.width;
    g.input.mouse.y = r.top + ((1 - v.y) / 2) * r.height;
    g.input.mouse.clicked = true;
  });
  await sim(page, 0.05);
  const friend = await page.evaluate(() => ({ f: window.__shadowfall.targeting.friendly?.id, frame: document.getElementById('target-name').textContent, talking: window.__shadowfall.dialogue.isOpen }));
  await rightClickOn('mara');
  await sim(page, 0.05);
  const talking = await page.evaluate(() => window.__shadowfall.dialogue.isOpen);
  // (either button selects a townsperson and talks to them, as src/main.js _click says)
  record('Clicking a townsperson selects and talks to them, with either button', friend.f === 'mara' && friend.frame === 'Mara Venn' && friend.talking && talking, `target frame "${friend.frame}"; left click talking: ${friend.talking}, right click talking: ${talking}`);
  record('No script errors (click targeting)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function spells(browser) {
  current = 'Example spells';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // tough, rooted ghouls so nothing dies and nothing wanders
  const ready = (list) => page.evaluate((list) => {
    const g = window.__shadowfall;
    g.player.health = 5000;
    for (const k of Object.keys(g.player.cooldowns)) g.player.cooldowns[k] = 0;
    g.spells.reset();
    g.targeting.clear();
    g.enemies.list.forEach((e, i) => {
      const at = list.find((l) => l[0] === e.id);
      e.cfg = { ...e.cfg, health: 500, speed: 0, detection: 3, damage: 0.01 };
      e.health = 500;
      e.position.set(at ? at[1] : -30 + i * 3, 0, at ? at[2] : -45);
      e.home.copy(e.position);
      e.state = 'idle';
      e.stagger = 0;
    });
    g.player.placeAt(0, 0, 0);
  }, list);
  const hp = (id) => page.evaluate((id) => window.__shadowfall.enemies.byId(id).health, id);
  const slot = (id) => page.evaluate((id) => window.__shadowfall.actionBar.place(id, 3), id);
  const select = (id) => page.evaluate((id) => window.__shadowfall.targeting.select(window.__shadowfall.enemies.byId(id)), id);

  const book = await page.evaluate(() => {
    const g = window.__shadowfall;
    const ids = ['hallowedBolt', 'rend', 'smite', 'hallowedGround', 'cleave', 'battleCry'];
    return { ids: ids.filter((id) => g.hud.abilityIcons[id] && g.player.cooldowns[id] === 0), bar: g.actionBar.slots[3] };
  });
  record('Six example spells exist, with icons, cooldowns, and Hallowed Bolt on key 4 by default', book.ids.length === 6 && book.bar === 'hallowedBolt', book.ids.join(', '));

  // ranged cast: a cast bar, then a bolt
  await ready([['ghoul_road', 0, 12]]);
  await select('ghoul_road');
  await slot('hallowedBolt');
  await sim(page, 0.6, { press: ['Digit4'] });
  const mid = await page.evaluate(() => ({ casting: !!window.__shadowfall.player.casting, bar: !document.getElementById('cast-bar').hidden, text: document.getElementById('cast-text').textContent, gcd: window.__shadowfall.player.cooldowns.gcd }));
  const hpMid = await hp('ghoul_road');
  await sim(page, 1.8);
  const bolt = 500 - (await hp('ghoul_road'));
  record('Hallowed Bolt: a 1.6s cast with a cast bar, then a bolt hits the target 12 m away', mid.casting && mid.bar && mid.gcd > 0 && hpMid === 500 && bolt > 0, `cast bar "${mid.text}"; bolt hit for ${bolt}`);
  await sim(page, 0.05, { press: ['Digit4'] });
  await sim(page, 0.4, { held: ['KeyS'] });
  const broke = await page.evaluate(() => !window.__shadowfall.player.casting);
  await sim(page, 1.5);
  record('Moving interrupts a cast', broke && (await hp('ghoul_road')) === 500 - bolt, 'walked away mid-cast: no bolt');

  // instant
  await ready([['ghoul_road', 0, 8]]);
  await select('ghoul_road');
  await slot('smite');
  await sim(page, 0.05, { press: ['Digit4'] });
  const smite = 500 - (await hp('ghoul_road'));
  const smiteCd = await page.evaluate(() => [window.__shadowfall.player.cooldowns.smite, window.__shadowfall.player.cooldowns.gcd]);
  const engaged = await page.evaluate(() => window.__shadowfall.targeting.attacking && window.__shadowfall.targeting.current?.id === 'ghoul_road');
  record('A spell on an enemy engages it: auto attack follows (WoW)', engaged);
  record('Smite: instant damage on the target, its own 6s cooldown and the GCD', smite > 0 && smiteCd[0] > 5.5 && smiteCd[1] > 1, `hit for ${smite}; cooldown ${smiteCd[0].toFixed(1)}s, GCD ${smiteCd[1].toFixed(1)}s`);
  await slot('rend');
  await sim(page, 0.05, { press: ['Digit4'] });
  const blocked = await page.evaluate(() => window.__shadowfall.spells.dots.length === 0);
  record('The GCD stops a second spell straight after the first', blocked, 'Rend pressed during Smite\'s GCD: nothing');

  // the bleed and burn numbers below are the spells' own: auto attack is held off
  await page.evaluate(() => { const t = window.__shadowfall.targeting; t.stopAttack(); t._engage = t.engage; t.engage = () => false; });
  // bleed
  await ready([['ghoul_road', 0, 1.6]]);
  await select('ghoul_road');
  await slot('rend');
  await sim(page, 0.05, { press: ['Digit4'] });
  const auras = await page.evaluate(() => document.querySelectorAll('#target-auras .aura').length);
  await sim(page, 2.0);
  const tick = 500 - (await hp('ghoul_road'));
  await sim(page, 8.5);
  const total = 500 - (await hp('ghoul_road'));
  const gone = await page.evaluate(() => window.__shadowfall.spells.dots.length === 0);
  record('Rend: a bleed that ticks 5 times over 10s, shown on the target frame', auras === 1 && tick > 0 && total === tick * 5 && gone, `${tick} per tick, ${total} in all`);

  // local AoE
  await ready([['ghoul_road', 2, 0], ['ghoul_cart', -2, 1], ['ghoul_graves', 0, 8]]);
  await slot('hallowedGround');
  await sim(page, 0.05, { press: ['Digit4'] });
  await sim(page, 6.5);
  const ground = [500 - (await hp('ghoul_road')), 500 - (await hp('ghoul_cart')), 500 - (await hp('ghoul_graves'))];
  const zoneGone = await page.evaluate(() => window.__shadowfall.spells.zones.length === 0);
  await page.evaluate(() => { const t = window.__shadowfall.targeting; t.engage = t._engage; });
  record('Hallowed Ground: burns every enemy inside it each second for 6s, not those outside', ground[0] > 0 && ground[1] === ground[0] && ground[2] === 0 && zoneGone, `inside ${ground[0]} and ${ground[1]}, outside ${ground[2]}`);

  // cleave
  await ready([['ghoul_road', 1, 1.8], ['ghoul_cart', -1, 1.8], ['ghoul_graves', 0, -2]]);
  await slot('cleave');
  await sim(page, 0.5, { press: ['Digit4'] });
  const cl = [500 - (await hp('ghoul_road')), 500 - (await hp('ghoul_cart')), 500 - (await hp('ghoul_graves'))];
  record('Cleave: hits every enemy in the arc in front, not the one behind', cl[0] > 0 && cl[1] > 0 && cl[2] === 0, `front ${cl[0]} and ${cl[1]}, behind ${cl[2]}`);

  // buff
  await ready([['ghoul_road', 0, 8]]);
  await select('ghoul_road');
  await slot('battleCry');
  await sim(page, 0.05, { press: ['Digit4'] });
  const buffed = await page.evaluate(() => ({ n: document.querySelectorAll('#buffs .aura').length, scale: window.__shadowfall.spells.damageScale }));
  await page.evaluate(() => { const c = window.__shadowfall.player.cooldowns; c.gcd = 0; c.smite = 0; });
  await slot('smite');
  await sim(page, 0.05, { press: ['Digit4'] });
  const smite2 = 500 - (await hp('ghoul_road'));
  if (process.env.SHOTS) {
    // a picture of the cast bar, the buff and a bleed on the target
    await page.evaluate(() => { const g = window.__shadowfall; g.player.cooldowns.gcd = 0; g.spells.dots.push({ enemy: g.enemies.byId('ghoul_road'), id: 'rend', left: 7, next: 2 }); });
    await slot('hallowedBolt');
    await sim(page, 0.8, { press: ['Digit4'] });
    await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
    await page.screenshot({ path: process.env.SHOTS + '/spells.png' });
    await sim(page, 1.5);
  }
  await sim(page, 15.5);
  const after = await page.evaluate(() => ({ n: document.querySelectorAll('#buffs .aura').length, scale: window.__shadowfall.spells.damageScale }));
  record('Battle Cry: +20% damage for 15s, shown under the health bar', buffed.n === 1 && Math.abs(buffed.scale - 1.2) < 1e-9 && Math.abs(smite2 - smite * 1.2) <= 1 && after.n === 0 && after.scale === 1, `Smite ${smite} → ${smite2} while it lasts; gone after 15s`);

  record('No script errors (spells)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function lootRarity(browser) {
  current = 'Loot rarity';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await setup(page, { x: 16.2, z: -40.5 });
  await pauseLoop(page);

  // many rolls of each table: rarity first, then an item from that rarity's list
  const stats = await page.evaluate(() => {
    const g = window.__shadowfall;
    const N = 20000;
    const count = (table) => {
      const out = { rarity: {}, items: {} };
      for (let i = 0; i < N; i++) {
        for (const d of g.rollLoot(g.db.lootTables[table], Math.random)) {
          const r = g.itemView({ id: d.id, rolls: g.rollItem(d.id, Math.random, d.rarity) }).rarity;
          out.rarity[r] = (out.rarity[r] || 0) + 1;
          out.items[d.id] = (out.items[d.id] || 0) + 1;
        }
      }
      return out;
    };
    return { ghoul: count('ghoul'), hound: count('hound'), seer: count('seer'), N };
  });
  const pct = (n) => (100 * (n || 0)) / stats.N;
  const near = (n, want, tol) => Math.abs(pct(n) - want) <= tol;
  const gh = stats.ghoul.rarity;
  record('A drop rolls its rarity first: a ghoul drops junk, common, enhanced and rarely rare', near(gh.junk, 22.5, 1.5) && near(gh.common, 14.4, 1.2) && near(gh.enhanced, 6.75, 1) && near(gh.rare, 1.35, 0.5) && !gh.epic,
    `per ghoul: junk ${pct(gh.junk).toFixed(1)}%, common ${pct(gh.common).toFixed(1)}%, enhanced ${pct(gh.enhanced).toFixed(1)}%, rare ${pct(gh.rare).toFixed(2)}%, epic 0`);
  record('Items reserved for a boss drop only from that boss', !stats.ghoul.items.witchbane && !stats.hound.items.witchbane && near(stats.seer.items.witchbane, 15, 1.5), `Witchbane: seer ${pct(stats.seer.items.witchbane).toFixed(1)}%, ghouls and hounds never`);
  record('Hounds always drop their own meat, and often a pelt', stats.hound.items.hound_meat === stats.N && near(stats.hound.items.hound_pelt, 50, 2), `meat ${pct(stats.hound.items.hound_meat)}%, pelt ${pct(stats.hound.items.hound_pelt).toFixed(1)}%`);

  // the seer falls and drops her epic blade: purple name, glint and log line
  const epic = await page.evaluate(() => {
    const g = window.__shadowfall;
    const before = g.worldState.ground.length;
    const seq = [0.1, 0.1, 0.99]; // one grave-iron, the drop roll, then the top of the rarity roll: epic
    g.random = () => (seq.length ? seq.shift() : 0.5);
    const e = g.enemies.byId('seer_glade') || g.enemies.list.find((x) => x.type === 'seer');
    e.position.set(16.2, 0, -38);
    e.health = 1;
    e.hurt(5);
    g.combat.onEnemyDefeated(e);
    g.random = () => 0.5;
    const dropped = g.worldState.ground.slice(before).map((d) => d.id);
    const blade = g.loot.active.find((l) => l.def.ground && l.def.ground.id === 'witchbane');
    const log = [...document.querySelectorAll('#log li')].find((l) => /Witchbane/.test(l.textContent));
    return { dropped, glint: blade && '#' + blade.glint.material.color.getHexString(), log: log && log.textContent, logColour: log && getComputedStyle(log).color };
  });
  record('An epic drop shows purple: its glint on the ground and its line in the log', epic.dropped.includes('witchbane') && epic.glint === '#b06cf0' && /\(Epic\)/.test(epic.log || '') && epic.logColour === 'rgb(176, 108, 240)',
    `dropped ${epic.dropped.join(', ')}; glint ${epic.glint}; "${epic.log}" in ${epic.logColour}`);

  // tooltip and slot border carry the rarity
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('witchbane', 1, { quiet: true });
    g.inventory.addItem('cracked_bone', 3, { quiet: true });
    g.hud.togglePanel('bags');
  });
  await resumeLoop(page);
  const loc = await page.evaluate(() => window.__shadowfall.inventory.bagLocations().find((l) => window.__shadowfall.inventory.get(l)?.id === 'witchbane'));
  await page.hover(`.islot[data-loc="${loc}"]`);
  await page.waitForSelector('#tooltip:not([hidden])', { timeout: 10000 });
  const tip = await page.evaluate((loc) => ({ text: document.getElementById('tooltip').textContent, colour: getComputedStyle(document.querySelector('#tooltip .tt-name')).color, border: getComputedStyle(document.querySelector(`.islot[data-loc="${loc}"]`)).borderTopColor }), loc);
  record('Tooltips and bag slots show the rarity colour; the tooltip names Epic', /Epic weapon/.test(tip.text) && tip.colour === 'rgb(176, 108, 240)' && /176, 108, 240/.test(tip.border), `${tip.text.replace(/\s+/g, ' ').slice(0, 60)} (${tip.colour}, border ${tip.border})`);
  await pauseLoop(page);

  const junk = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.merchant.open('mara_forge', g.npcs.byId('mara'));
    const c0 = g.inventory.coins;
    g.merchant.sell(g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'cracked_bone'));
    const paid = g.inventory.coins - c0;
    g.merchant.close();
    return paid;
  });
  record('Junk (grey) is worth a little to a merchant', junk >= 1, `3 cracked bones sold for ${junk}`);
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'loot-rarity.png') });
  record('No script errors (loot rarity)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function ghostAndCamp(browser) {
  current = 'Ghost run, killer and camp';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // rest at the roadside shrine, then fall to a ghoul far from it
  await setup(page, { x: 7.6, z: 5.2 });
  await sim(page, 0.1, { press: ['KeyE'] });
  await page.evaluate(() => (window.__shadowfall.inventory.coins = 20));
  await setup(page, { x: 0, z: -15, keep: ['ghoul_road'], hp: 4 });
  await placeEnemy(page, 'ghoul_road', 0, -16.4, { attackTimer: 0 });
  await sim(page, 3.0);
  const fell = await page.evaluate(() => ({ dead: window.__shadowfall.player.dead, nemesis: window.__shadowfall.worldState.nemesis, text: document.getElementById('death-text').textContent, btn: document.getElementById('respawn-btn').textContent }));
  record('Death offers to release your spirit, and remembers your killer', fell.dead && fell.nemesis === 'ghoul_road' && fell.btn === 'Release spirit' && /walk back to your body/i.test(fell.text), `"${fell.text}"`);

  await sim(page, 0.05, { press: ['Enter'] });
  const ghost = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { ghost: g.player.ghost, x: g.player.position.x, z: g.player.position.z, corpse: !!g.scene.getObjectByName('Corpse'), grey: g.renderer.domElement.style.filter, prompt: g.interaction.current && g.interaction.current.prompt, marks: g.hud.minimap.markers().map((m) => m.kind) };
  });
  record('The spirit rises at the shrine; the body stays where it fell; the world turns grey', ghost.ghost && Math.hypot(ghost.x - 7.8, ghost.z - 5.2) < 1 && ghost.corpse && /grayscale/.test(ghost.grey) && /Return to life here \(lose 4 silver\)/.test(ghost.prompt || '') && ghost.marks.includes('corpse') && ghost.marks.includes('nemesis'),
    `ghost at (${ghost.x.toFixed(1)}, ${ghost.z.toFixed(1)}); prompt "${ghost.prompt}"; minimap: body and skull`);

  // the ghost walks past the ghoul untouched, faster than the living
  const t0 = await page.evaluate(() => window.__shadowfall.player.position.clone());
  await sim(page, 1, { held: ['KeyS'] });
  const t1 = await page.evaluate(() => window.__shadowfall.player.position.clone());
  await page.evaluate(() => window.__shadowfall.player.placeAt(0.8, -15.2));
  await sim(page, 2);
  const run = await page.evaluate(() => ({ hp: window.__shadowfall.player.health, prompt: window.__shadowfall.interaction.current && window.__shadowfall.interaction.current.prompt }));
  record('A spirit moves faster and enemies ignore it', Math.hypot(t1.x - t0.x, t1.z - t0.z) > 6.5 && run.hp === 0, `covered ${Math.hypot(t1.x - t0.x, t1.z - t0.z).toFixed(1)} m in 1 s (alive: 5); stood by the ghoul untouched`);
  await sim(page, 0.05, { press: ['KeyE'] });
  const back = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { alive: !g.player.dead && !g.player.ghost, hp: g.player.health, max: g.player.maxHealth, coins: g.inventory.coins, grey: g.renderer.domElement.style.filter, corpse: !!g.scene.getObjectByName('Corpse') };
  });
  record('Returning to your body revives you there at half health, nothing lost', run.prompt === 'Return to your body' && back.alive && back.hp === Math.round(back.max / 2) && back.coins === 20 && !back.grey && !back.corpse, `${back.hp}/${back.max} health, ${back.coins} coins kept`);

  // the killer: a skull over it, extra damage, and revenge
  const skull = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.health = 500;
    g.hud.update(0);
    const bar = [...document.querySelectorAll('.ebar.nemesis')];
    return { bars: bar.length, scale: g.afterlife.damageScaleAgainst(g.enemies.byId('ghoul_road')) };
  });
  const xp0 = await page.evaluate(() => window.__shadowfall.progression.xp);
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    e.health = 1;
    e.hurt(5);
    g.combat.onEnemyDefeated(e);
  });
  const rev = await page.evaluate(() => ({ xp: window.__shadowfall.progression.xp, nemesis: window.__shadowfall.worldState.nemesis, log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).join(' | ') }));
  record('Your killer wears a skull, takes 25% more damage from you, and pays a revenge bonus', skull.bars === 1 && skull.scale === 1.25 && rev.nemesis === null && /Revenge/.test(rev.log) && rev.xp - xp0 > 0, `+${rev.xp - xp0} experience including the revenge bonus`);

  // camping: learned from Old Tam, pitched away from enemies, rested by the fire
  const learn = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.coins = 30;
    g.player.placeAt(-18.2, -14.2);
    g.npcs.talk(g.npcs.byId('tam'));
    g.dialogue.choose('train');
    const opts = g.dialogue.page.options.map((o) => o.id);
    const before = g.skills.knowsAbility('setCamp');
    g.dialogue.choose('train:camping');
    g.dialogue.close();
    return { opts, before, after: g.skills.knowsAbility('setCamp'), coins: g.inventory.coins, bar: g.actionBar.slots.includes('setCamp'), book: (g.hud.togglePanel('skills'), !!document.querySelector('#skills-window [data-loc="k:setCamp"]')) };
  });
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('skills'));
  record('Old Tam teaches Camping for coins (in his trainer window); Set Camp then appears under Professions', learn.opts.includes('train:camping') && learn.opts.includes('train:fishing') && !learn.before && learn.after && learn.coins === 20 && learn.book, `options: ${learn.opts.join(', ')}; 30 → ${learn.coins} coins`);
  await setup(page, { x: -10, z: 22 });
  await page.evaluate(() => { const g = window.__shadowfall; g.actionBar.place('setCamp', 3); g.player.cooldowns.gcd = 0; });
  await sim(page, 0.05, { press: ['Digit4'] });
  await sim(page, 3.2);
  const camp = await page.evaluate(() => ({ camp: window.__shadowfall.worldState.camp, rest: window.__shadowfall.worldState.restPoint, mesh: !!window.__shadowfall.scene.getObjectByName('Camp') }));
  await sim(page, 20);
  const rested = await page.evaluate(() => ({ r: window.__shadowfall.progression.rested, need: window.__shadowfall.progression.xpToNext, band: document.getElementById('xp-rested').style.width }));
  record('Set Camp: a 3 s cast pitches a camp, which becomes where you rise', camp.camp && Math.hypot(camp.camp.x + 10, camp.camp.z - 22) < 0.1 && camp.rest === 'camp' && camp.mesh, JSON.stringify(camp.camp));
  record('Resting by the fire builds rested experience, shown on the bar', rested.r > rested.need * 0.15 && parseFloat(rested.band) > 10, `${rested.r.toFixed(1)} rested after 20 s (band ${rested.band})`);
  const kill = await page.evaluate(() => {
    const g = window.__shadowfall;
    const x0 = g.progression.xp + g.progression.level * 1000;
    const e = g.enemies.byId('ghoul_cart');
    e.health = 1;
    e.hurt(5);
    g.combat.onEnemyDefeated(e);
    return { gained: g.progression.xp + g.progression.level * 1000 - x0, log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).find((t) => /rested bonus/.test(t)) };
  });
  record('Rested experience doubles kill experience until spent', !!kill.log, kill.log || '');

  // a camp near enemies is refused
  await setup(page, { x: 0, z: -15, keep: ['ghoul_graves'], park: true });
  await placeEnemy(page, 'ghoul_graves', 0, -20);
  await page.evaluate(() => (window.__shadowfall.player.cooldowns.setCamp = 0));
  await sim(page, 0.05, { press: ['Digit4'] });
  const refused = await page.evaluate(() => !window.__shadowfall.player.casting && /enemies close by/.test(window.__shadowfall.hud.lastError || ''));
  record('No camp with enemies close by', refused);

  // the next death rises at the camp, and the camp survives a save
  await page.evaluate(() => { const g = window.__shadowfall; g.player.takeDamage(9999); g.onPlayerDeath(null); });
  await sim(page, 2);
  await sim(page, 0.05, { press: ['Enter'] });
  const atCamp = await page.evaluate(() => ({ x: window.__shadowfall.player.position.x, z: window.__shadowfall.player.position.z }));
  record('After a death the spirit rises by your camp', Math.hypot(atCamp.x + 8.6, atCamp.z - 22) < 1, `(${atCamp.x.toFixed(1)}, ${atCamp.z.toFixed(1)})`);
  record('No script errors (ghost and camp)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function targetAndUi(browser) {
  current = 'Targets, tooltips, stats and skills';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const screenOf = (id) => page.evaluate((id) => {
    const g = window.__shadowfall;
    const e = g.enemies.byId(id) || g.npcs.byId(id);
    const v = e.position.clone().setY(e.position.y + 1).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    return { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height };
  }, id);
  const ring = () => page.evaluate(() => {
    const g = window.__shadowfall;
    const m = g.targeting.marker;
    return { visible: m.visible, color: m.material.color.getHexString(), target: g.targeting.current?.id || g.targeting.friendly?.id || null };
  });
  const clickAtScreen = (pt, button) => page.evaluate(({ pt, button }) => {
    const g = window.__shadowfall;
    const r = g.renderer.domElement.getBoundingClientRect();
    g.input.mouse.x = pt.x;
    g.input.mouse.y = pt.y;
    g.input.mouse.ndcX = ((pt.x - r.left) / r.width) * 2 - 1;
    g.input.mouse.ndcY = -((pt.y - r.top) / r.height) * 2 + 1;
    if (button === 'right') g.input.mouse.rightClicked = true;
    else g.input.mouse.clicked = true;
  }, { pt, button });

  // left click: yellow ring on anyone; right click on an enemy: red
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -5, { frozen: true });
  await page.evaluate(() => (window.__shadowfall.enemies.byId('ghoul_road').health = 500));
  await clickAtScreen(await screenOf('ghoul_road'), 'left');
  await sim(page, 0.05);
  const yellow = await ring();
  await clickAtScreen(await screenOf('ghoul_road'), 'right');
  await sim(page, 0.05);
  const red = await ring();
  const err = await page.evaluate(() => ({ text: document.getElementById('ui-error').textContent, shown: document.getElementById('ui-error').classList.contains('show') }));
  record('Left-clicking an enemy rings it yellow; right-clicking rings it red', yellow.visible && yellow.color === 'ffd040' && yellow.target === 'ghoul_road' && red.visible && red.color === 'ff4a30', `left: #${yellow.color}, right: #${red.color}`);
  record('Engaging an enemy out of reach shows "Out of range" in red mid-screen', err.shown && err.text === 'Out of range', `"${err.text}"`);
  // right click on the ground keeps the target; left click lets it go
  const ground = { x: 200, y: 300 };
  await clickAtScreen(ground, 'right');
  await sim(page, 0.05);
  const kept = await ring();
  await clickAtScreen(ground, 'left');
  await sim(page, 0.05);
  const gone = await ring();
  record('Right-clicking the ground keeps the target; left-clicking it deselects', kept.target === 'ghoul_road' && !gone.target && !gone.visible, `after right: ${kept.target}; after left: ${gone.target}`);

  // townsfolk: yellow ring, a level on the portrait
  await setup(page, { x: 0, z: 0 });
  const mara = await page.evaluate(() => { const n = window.__shadowfall.npcs.byId('mara'); return { x: n.position.x, z: n.position.z }; });
  await page.evaluate(({ x, z }) => window.__shadowfall.player.placeAt(x, z + 4), mara);
  await page.evaluate(() => window.__shadowfall._snapCamera());
  await clickAtScreen(await screenOf('mara'), 'left');
  await sim(page, 0.05);
  const friend = await ring();
  const portrait = await page.evaluate(() => ({ level: document.getElementById('target-level').textContent, img: document.getElementById('target-img').src.length }));
  record('Left-clicking a townsperson rings them yellow; the portrait shows their level', friend.target === 'mara' && friend.color === 'ffd040' && portrait.level === '12' && portrait.img > 500, `Mara Venn: level ${portrait.level}, portrait ${portrait.img} bytes`);
  // an enemy's level on its portrait
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -3, { frozen: true });
  await page.evaluate(() => window.__shadowfall.targeting.select(window.__shadowfall.enemies.byId('ghoul_road')));
  await sim(page, 0.05);
  const elevel = await page.evaluate(() => document.getElementById('target-level').textContent);
  record('Enemy portraits show just their level', elevel === '1', `ghoul: ${elevel}`);

  // hovering anyone: a tooltip in the bottom-right corner
  const pt = await screenOf('ghoul_road');
  await page.mouse.move(pt.x, pt.y);
  await sim(page, 0.05);
  const hover = await page.evaluate(() => {
    const t = document.getElementById('tooltip');
    const r = t.getBoundingClientRect();
    return { shown: !t.hidden, text: t.textContent, right: window.innerWidth - r.right, bottom: window.innerHeight - r.bottom };
  });
  record('Hovering an enemy shows its tooltip in the bottom-right corner', hover.shown && /Ashen Ghoul/.test(hover.text) && /Level 1/.test(hover.text) && hover.right < 40 && hover.bottom < 160, `"${hover.text}" at ${hover.right.toFixed(0)}px from the right, ${hover.bottom.toFixed(0)}px from the bottom`);
  await page.mouse.move(5, 5);
  await sim(page, 0.05);
  // a spell on the bar and a menu button: the same corner
  const slot = await page.evaluate(() => { const r = document.getElementById('aslot-1').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  await page.mouse.move(slot.x, slot.y);
  await page.waitForTimeout(100);
  const spellTip = await page.evaluate(() => { const t = document.getElementById('tooltip'); const r = t.getBoundingClientRect(); return { shown: !t.hidden, text: t.textContent, right: window.innerWidth - r.right }; });
  const btn = await page.evaluate(() => { const r = document.getElementById('btn-character').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  await page.mouse.move(btn.x, btn.y);
  await page.waitForTimeout(100);
  const btnTip = await page.evaluate(() => { const t = document.getElementById('tooltip'); const r = t.getBoundingClientRect(); return { shown: !t.hidden, text: t.textContent, right: window.innerWidth - r.right, title: document.getElementById('btn-character').getAttribute('title') }; });
  record('Spell and menu tooltips show in the same corner', spellTip.shown && /Shield Break/.test(spellTip.text) && spellTip.right < 40 && btnTip.shown && /Character/.test(btnTip.text) && btnTip.right < 40 && !btnTip.title, `"${spellTip.text.slice(0, 30)}…", "${btnTip.text}"`);
  await page.mouse.move(5, 5);

  // no hit-stop; Shield Break and Lunge are spells
  const spells = await page.evaluate(() => {
    const g = window.__shadowfall;
    return { freeze: typeof g.player.rig.freeze, sb: g.config.abilities?.shieldBreak?.kind || null, kinds: ['shieldBreak', 'lunge'].map((id) => window.__shadowfall.spells && Object.keys(window.__shadowfall.player.cooldowns).includes(id)) };
  });
  record('No hit-stop: nothing freezes when a blow lands', spells.freeze === 'undefined');

  // stats panel: the new names; no Shield Break or Lunge rows
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('character'));
  const panel = await page.evaluate(() => [...document.querySelectorAll('#char-stats div')].filter((d) => d.querySelector('b')).map((d) => d.querySelector('span').textContent));
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('character'));
  const want = ['Stamina', 'Strength', 'Agility', 'Intellect', 'Haste', 'Armour', 'Block', 'Crit'];
  record('The character panel uses Stamina, Strength, Agility, Intellect, Haste, Armour, Block and Crit, without Shield Break or Lunge', want.every((w) => panel.includes(w)) && !panel.includes('Shield Break') && !panel.includes('Lunge') && !panel.includes('Might'), panel.join(', '));

  // experience %, bag space
  const xp = await page.evaluate(() => { const g = window.__shadowfall; g.progression.xp = 37; g.hud.update(0.016); return document.getElementById('xp-text').textContent; });
  record('The experience bar shows a percentage', /\(37%\)/.test(xp), xp);
  const bag = await page.evaluate(() => ({ shown: document.querySelector('#bag-sockets .bag-free')?.textContent, free: window.__shadowfall.inventory.freeSlots() }));
  record('The backpack shows how many bag slots are free', bag.shown === String(bag.free), `${bag.shown} free`);

  // skills panel
  await page.evaluate(() => { const g = window.__shadowfall; g.skills.ranks.set('fishing', 7); g.events.emit('skillsChanged', {}); });
  await sim(page, 0.05, { press: ['KeyU'] });
  const skills = await page.evaluate(() => [...document.querySelectorAll('#skills-list .skill-tile')].map((t) => t.textContent));
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'skills-and-target.png') });
  await sim(page, 0.05, { press: ['KeyU'] });
  record('The skills panel (U) shows each skill and its level', skills.some((t) => /Fishing7 \/ 50/.test(t)) && skills.some((t) => /CampingNot learned/.test(t)), skills.join(' | '));
  record('No script errors (targets, tooltips, stats and skills)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function torchAndFishing(browser) {
  current = 'Torch, dark places and fishing';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // the Barrow Hollow keeps out anyone without a light
  await setup(page, { x: -27, z: -82 });
  await sim(page, 2.5, { held: ['KeyW'] });
  const dark = await page.evaluate(() => {
    const g = window.__shadowfall;
    const p = g.player.position;
    return { d: Math.hypot(p.x + 27, p.z + 90), log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).find((t) => /too dark/.test(t)) };
  });
  record('An obscured area cannot be entered without a light', dark.d >= 6 && !!dark.log, `stopped ${dark.d.toFixed(1)} m from its heart: "${dark.log}"`);
  const torch = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('torch', 1, { quiet: true });
    g.inventory.equip('torch');
    return { off: g.inventory.equipment.offHand && g.inventory.equipment.offHand.id, light: g.player.lightRadius, block: g.stats.blockChance };
  });
  await sim(page, 1.5, { held: ['KeyW'] });
  const lit = await page.evaluate(() => {
    const g = window.__shadowfall;
    const p = g.player.position;
    const chest = g.loot.active.find((l) => l.def.id === 'hollow_chest');
    return { d: Math.hypot(p.x + 27, p.z + 90), dome: g.scene.getObjectByName('Obscured_barrow_hollow').material.opacity, chest: !!chest };
  });
  record('A torch in the off hand lights the way in (and gives up the shield)', torch.off === 'torch' && torch.light === 9 && torch.block === 0 && lit.d < 4 && lit.dome < 0.5 && lit.chest, `torch light ${torch.light} m; walked to ${lit.d.toFixed(1)} m from the heart; the dark thinned to ${lit.dome.toFixed(2)}; the strongbox waits inside`);
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'barrow-hollow.png') });

  // fishing: learn it, buy a rod, cast, wait for the bite, strike
  const setupFish = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.coins = 40;
    g.player.placeAt(-18.4, -14.4);
    g.npcs.talk(g.npcs.byId('tam'));
    g.dialogue.choose('train:fishing');
    g.dialogue.choose('shop');
    g.merchant.buy('fishing_rod');
    g.merchant.close();
    return { skill: g.skills.rank('fishing'), rod: g.inventory.count('fishing_rod'), coins: g.inventory.coins };
  });
  record('Old Tam teaches Fishing and sells a rod', setupFish.skill === 1 && setupFish.rod === 1, `rank ${setupFish.skill}, ${setupFish.coins} coins left`);
  await setup(page, { x: -16.8, z: -14 });
  await page.evaluate(() => { const g = window.__shadowfall; g.player.facing = -Math.PI / 2; g.actionBar.place('fish', 3); });
  await sim(page, 0.05, { press: ['Digit4'], aimAt: { x: -22, z: -14 } });
  await sim(page, 1.0);
  const waiting = await page.evaluate(() => ({ phase: window.__shadowfall.fishing.state && window.__shadowfall.fishing.state.phase, bob: window.__shadowfall.fishing.bobPosition && window.__shadowfall.fishing.bobPosition.x }));
  await page.evaluate(() => Object.assign(window.__shadowfall.fishing.state, { wait: 6, skill: 60 })); // this cast gets a bite, 6 s after the bob lands, and lands it
  await sim(page, 6.0);
  const biting = await page.evaluate(() => window.__shadowfall.fishing.biting);
  await page.evaluate(() => window.__shadowfall.renderer.render(window.__shadowfall.scene, window.__shadowfall.camera));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'fishing.png') });
  await sim(page, 0.05, { press: ['KeyE'] });
  const caught = await page.evaluate(() => {
    const g = window.__shadowfall;
    const fish = ['gloomwater_perch', 'silver_dace', 'barrow_eel', 'old_boot'].filter((f) => g.inventory.count(f) > 0);
    return { fish, rank: g.skills.rank('fishing'), active: g.fishing.active };
  });
  record('Cast into the mere, wait for the bob to dip, strike: a fish', waiting.phase === 'wait' && waiting.bob < -19 && biting && caught.fish.length === 1 && caught.rank === 2 && !caught.active, `caught ${caught.fish.join(', ')}; Fishing rank 1 → ${caught.rank}`);
  await sim(page, 0.05, { press: ['Digit4'], aimAt: { x: -22, z: -14 } });
  await sim(page, 2);
  await sim(page, 0.05, { press: ['KeyE'] });
  const early = await page.evaluate(() => ({ active: window.__shadowfall.fishing.active, log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).find((t) => /too soon/.test(t)) }));
  record('Striking before the bite loses the fish', !early.active && !!early.log, early.log || '');
  const noWater = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(0, 20, 0);
    return g.fishing.cast({ x: 0, z: 24 });
  });
  record('You can only fish facing water', noWater === false);

  // the fishing bar, and casts where nothing bites
  await setup(page, { x: -16.8, z: -14 });
  await page.evaluate(() => { const g = window.__shadowfall; g.player.facing = -Math.PI / 2; g.player.cooldowns.gcd = 0; });
  await sim(page, 0.05, { press: ['Digit4'], aimAt: { x: -22, z: -14 } });
  const barNow = await page.evaluate(() => { const g = window.__shadowfall; g.fishing.state.wait = Infinity; return { hidden: document.getElementById('cast-bar').hidden, text: document.getElementById('cast-text').textContent }; });
  await sim(page, 0.5);
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'fishing-bar.png') });
  await sim(page, 20);
  const nothing = await page.evaluate(() => ({ active: window.__shadowfall.fishing.active, log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).find((t) => /Nothing is biting/.test(t)) }));
  record('Each cast runs a fishing bar; if it runs out with no bite, nothing was biting', !barNow.hidden && /Fishing/.test(barNow.text) && !nothing.active && !!nothing.log, `bar "${barNow.text}"; ${nothing.log}`);
  const odds = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.removeAll('cut_bait');
    const at = () => +g.fishing.biteChanceFor().toFixed(1);
    const rank = g.skills.rank('fishing');
    const base = at();
    g.inventory.addItem('yew_fishing_rod', 1, { quiet: true });
    const rod = at();
    g.inventory.addItem('cut_bait', 3, { quiet: true });
    const bait = at();
    g.fishing.cast({ x: -22, z: -14 });
    const used = 3 - g.inventory.count('cut_bait');
    g.fishing.stop();
    g.skills.raise('fishing');
    g.inventory.removeAll('cut_bait');
    g.inventory.removeAll('yew_fishing_rod');
    return { rank, base, rod, bait, used, ranked: at() };
  });
  record('The chance of a bite rises with Fishing rank, a better rod and bait (used one per cast)', odds.rod > odds.base && odds.bait > odds.rod && odds.ranked > odds.base && odds.used === 1, `rank ${odds.rank}: ${odds.base}%; Tam's yew rod ${odds.rod}%; with bait ${odds.bait}% (${odds.used} used); one rank higher ${odds.ranked}%`);
  record('No script errors (torch and fishing)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function combatFixes(browser) {
  current = 'Combat and targeting fixes';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const err = () => page.evaluate(() => { const g = window.__shadowfall; const t = g.hud.lastError; g.hud.lastError = null; return t; });

  // the first swing waits a full weapon swing after engaging
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await page.evaluate(() => { const g = window.__shadowfall; const e = g.enemies.byId('ghoul_road'); e.health = 1000; g.player.cooldowns.attack = 0; g.targeting.engage(e); });
  await sim(page, 1.0);
  const early = await page.evaluate(() => 1000 - window.__shadowfall.enemies.byId('ghoul_road').health);
  await sim(page, 2.0);
  const later = await page.evaluate(() => 1000 - window.__shadowfall.enemies.byId('ghoul_road').health);
  record('The first auto attack waits one weapon swing (2.2 s)', early === 0 && later > 0, `after 1 s: ${early} damage; after 2.5 s: ${later}`);

  // no auto attack swings while casting
  const casting = await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    e.health = 1000;
    g.player.pending = null;
    g.player.cooldowns.attack = 0;
    g.player.cooldowns.gcd = 0;
    g.spells.tryCast('hallowedBolt');
    return { casting: !!g.player.casting };
  });
  await sim(page, 0.5);
  const midCast = await page.evaluate(() => ({ dealt: 1000 - window.__shadowfall.enemies.byId('ghoul_road').health, casting: !!window.__shadowfall.player.casting }));
  record('No auto attack while casting a spell', casting.casting && midCast.casting && midCast.dealt === 0, `0.5 s into Hallowed Bolt: ${midCast.dealt} damage`);
  await sim(page, 2);

  // Brace is a spell now
  const brace = await page.evaluate(() => { const g = window.__shadowfall; g.player.cooldowns.gcd = 0; const ok = g.spells.tryCast('brace'); return { ok: ok !== false, braced: g.player.braced > 0, gcd: g.player.cooldowns.gcd }; });
  record('Brace is cast as a spell, off the global cooldown', brace.braced, JSON.stringify(brace));

  // Rebuke interrupts an archer's shot, but not Grave Slam
  await placeEnemy(page, 'archer_camp_1', 0, -6, { frozen: true });
  const kick = await page.evaluate(() => {
    const g = window.__shadowfall;
    const a = g.enemies.byId('archer_camp_1');
    g.targeting.select(a);
    a._startShot(g.player);
    g.player.cooldowns.gcd = 0;
    g.player.cooldowns.rebuke = 0;
    g.spells.tryCast('rebuke');
    const first = { casting: !!a.casting, log: document.querySelector('#log li:last-child').textContent };
    a.casting = { kind: 'slam', label: 'Grave Slam', interruptible: false };
    const slam = a.interrupt(3);
    a.casting = null;
    return { ...first, slam };
  });
  record('Rebuke interrupts a cast; Grave Slam cannot be interrupted', !kick.casting && /interrupt/i.test(kick.log) && kick.slam === false, `log: "${kick.log}"`);

  // abilities that need a target say so in red
  await setup(page, { x: 0, z: 0 });
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.clear(); g.player.cooldowns.gcd = 0; g.player.cooldowns.rebuke = 0; g.hud.lastError = null; g.spells.tryCast('rebuke'); });
  const noTarget = await err();
  record('An ability with no target says "You have no target."', noTarget === 'You have no target.', noTarget || '');

  // a friendly NPC out of reach: grey cursor and a red message; close up it talks
  const at = async (id) => page.evaluate((id) => {
    const g = window.__shadowfall;
    const n = g.npcs.byId(id);
    const v = n.position.clone().setY(n.position.y + 1).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    g.input.mouse.x = r.left + ((v.x + 1) / 2) * r.width;
    g.input.mouse.y = r.top + ((1 - v.y) / 2) * r.height;
    g.input.mouse.ndcX = v.x;
    g.input.mouse.ndcY = v.y;
    g.input.mouse.onCanvas = true;
    return { x: n.position.x, z: n.position.z };
  }, id);
  const mara = await page.evaluate(() => { const p = window.__shadowfall.npcs.byId('mara').position; return { x: p.x, z: p.z }; });
  await setup(page, { x: mara.x + 9, z: mara.z + 9 });
  await at('mara');
  await sim(page, 0.05);
  const farCursor = await page.evaluate(() => window.__shadowfall.renderer.domElement.style.cursor);
  await page.evaluate(() => { window.__shadowfall.input.mouse.rightClicked = true; });
  await sim(page, 0.05);
  const far = await page.evaluate(() => ({ err: window.__shadowfall.hud.lastError, friendly: window.__shadowfall.targeting.friendly?.id, open: !document.getElementById('dialogue-window').hidden }));
  await setup(page, { x: mara.x + 1.2, z: mara.z + 1.2 });
  await at('mara');
  await sim(page, 0.05);
  const nearCursor = await page.evaluate(() => window.__shadowfall.renderer.domElement.style.cursor);
  record('A far NPC greys the cursor and says to come closer; right click selects it', far.err === 'You need to be closer to interact with that target.' && far.friendly === 'mara' && /url/.test(farCursor) && /url/.test(nearCursor) && farCursor !== nearCursor, `message: "${far.err}"`);

  // an enemy under the mouse shows the attack cursor
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -3, { frozen: true });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    const v = e.position.clone().setY(1).project(g.camera);
    const r = g.renderer.domElement.getBoundingClientRect();
    g.input.mouse.x = r.left + ((v.x + 1) / 2) * r.width;
    g.input.mouse.y = r.top + ((1 - v.y) / 2) * r.height;
    g.input.mouse.ndcX = v.x;
    g.input.mouse.ndcY = v.y;
    g.input.mouse.onCanvas = true;
  });
  await sim(page, 0.05);
  const attackCursor = await page.evaluate(() => window.__shadowfall.renderer.domElement.style.cursor);
  record('Hovering an enemy shows the attack cursor', /url/.test(attackCursor) && attackCursor !== nearCursor && attackCursor !== farCursor);
  record('No script errors (combat fixes)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function economy(browser) {
  current = 'Money, durability and gear';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);

  // silver and gold: 100 silver is a gold, shown with coin icons
  const money = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.coins = 120;
    g.hud.togglePanel('bags');
    g.hud.items.render();
    const foot = document.querySelector('.bag-foot');
    const amounts = (el) => [...el.querySelectorAll('.money b')].map((b) => b.textContent).join(' ');
    const shown = amounts(foot);
    const icons = foot.querySelectorAll('.coin.gold').length + foot.querySelectorAll('.coin.silver').length;
    g.inventory.coins = 100;
    g.inventory.coins -= 1;
    g.hud.items.render();
    const after = amounts(document.querySelector('.bag-foot'));
    g.hud.togglePanel('bags');
    return { shown, icons, after };
  });
  record('Money shows as gold and silver with coin icons (120 silver = 1 gold 20 silver)', money.shown === '1 20' && money.icons === 2 && money.after === '99', `120 → "${money.shown}" (${money.icons} icons); 100 − 1 → "${money.after}"`);

  // sell price on the tooltip
  await page.evaluate(() => { const g = window.__shadowfall; g.inventory.coins = 50; g.inventory.addItem('hob_boots', 1); g.hud.togglePanel('bags'); g.hud.items.render(); });
  const bootLoc = await page.evaluate(() => window.__shadowfall.inventory.bagLocations().find((l) => window.__shadowfall.inventory.get(l)?.id === 'hob_boots'));
  await page.hover(`#bags-frames .islot[data-loc="${bootLoc}"]`);
  await page.waitForSelector('#tooltip:not([hidden])', { timeout: 10000 });
  const sellTip = await page.evaluate(() => ({ html: document.querySelector('#tooltip .tt-sell')?.innerHTML || '', text: document.querySelector('#tooltip .tt-sell')?.textContent || '' }));
  record('Item tooltips show "Sell for" with a coin icon', /^Sell for \d+/.test(sellTip.text) && /coin silver/.test(sellTip.html), sellTip.text);

  // the character panel has every slot
  const panel = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.hud.togglePanel('character');
    g.hud.items.render();
    const n = document.querySelectorAll('#character-window .islot[data-loc^="e:"]').length;
    g.hud.togglePanel('character');
    return n;
  });
  record('The character panel has all 16 equipment slots', panel === 16, `${panel} slots`);

  // starting gear is much weaker now
  const start = await page.evaluate(() => { const g = window.__shadowfall; return { w: g.inventory.weapon.damage, speed: g.stats.weaponSpeed, armour: g.stats.armour, swing: g.stats.swingRange }; });
  record('The starting sword does 3–7 at 2.2 s; starting armour is 130 (21% at level 1)', start.w[0] === 3 && start.w[1] === 7 && start.speed === 2.2 && start.armour === 130, JSON.stringify(start));

  // dying wears gear; at 0% it breaks and gives nothing; a smith repairs it
  const wear = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.afterlife.onDeath(null, 0);
    const after = g.inventory.equipment.chest.dur;
    g.inventory.equipment.chest.dur = 10;
    g.inventory.equipment.mainHand.dur = 10;
    g.afterlife.onDeath(null, 0);
    return { after, chest: g.inventory.equipment.chest.dur, armour: g.stats.armour, weapon: g.inventory.weapon.damage, name: g.inventory.weapon.name };
  });
  record('Dying takes 10% durability; at 0% gear is broken and gives nothing', wear.after === 90 && wear.chest === 0 && wear.armour === 100 && wear.weapon[1] === 2, JSON.stringify(wear));
  const repair = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.coins = 500;
    const cost = g.inventory.repairAllCost;
    g.player.placeAt(g.npcs.byId('mara').position.x + 1, g.npcs.byId('mara').position.z + 1);
    g.merchant.open('mara_forge', g.npcs.byId('mara'));
    g.hud.items.render();
    const btn = document.getElementById('shop-repair');
    const shown = !btn.hidden && /Repair all/.test(btn.textContent);
    btn.click();
    g.merchant.close();
    return { cost, shown, coins: g.inventory.coins, dur: g.inventory.equipment.chest.dur, armour: g.stats.armour };
  });
  record("Mara's forge repairs everything for silver", repair.shown && repair.cost > 0 && repair.coins === 500 - repair.cost && repair.dur === undefined && repair.armour === 130, JSON.stringify(repair));

  // loot on the ground shows its name in its rarity colour
  const label = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addItem('watchmans_edge', 1);
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'watchmans_edge');
    g.loot.dropFromInventory(loc);
    g._snapCamera();
    g.renderer.render(g.scene, g.camera);
    g.hud.labels.update();
    const el = [...document.querySelectorAll('#world-labels .loot-label')].find((e) => !e.hidden && /Watchman/.test(e.textContent));
    return el ? { text: el.textContent, colour: el.style.color } : null;
  });
  record('Ground loot shows its name in its rarity colour', !!label && /108, 192, 90|6cc05a/i.test(label.colour), JSON.stringify(label));
  record('No script errors (economy)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function worldBatch(browser) {
  current = 'Respawns, nameplates, chests and reputation';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);

  // a killed ghoul comes back after its respawn time; XP each time (grinding)
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  const grind = await page.evaluate(() => {
    const g = window.__shadowfall;
    const kill = () => { const e = g.enemies.byId('ghoul_road'); e.hurt(999); g.combat.onEnemyDefeated(e); };
    const xp0 = g.progression.xp;
    kill();
    const xp1 = g.progression.xp;
    const due = g.worldState.respawnAt.ghoul_road - g.worldState.time;
    for (let i = 0; i < 60; i++) g.step(1 / 60);
    const stillDead = !g.enemies.list.some((e) => e.id === 'ghoul_road' && e.alive);
    g.worldState.time += due;
    g.step(1 / 60);
    const back = g.enemies.list.find((e) => e.id === 'ghoul_road' && e.alive);
    const backAt = back && [Math.round(back.position.x), Math.round(back.position.z)];
    kill();
    return { xp: [xp0, xp1, g.progression.xp], due, stillDead, backAt, rep: g.reputation.get('road_wardens') };
  });
  record('Enemies respawn after their type\'s timer and give XP again', Math.round(grind.due) === 90 && grind.stillDead && !!grind.backAt && grind.xp[2] > grind.xp[1] && grind.xp[1] > grind.xp[0], JSON.stringify(grind));
  record('Kills in an area raise that faction\'s reputation', grind.rep === 20, `Road Wardens +${grind.rep} for two ghouls`);
  const never = await page.evaluate(() => window.__shadowfall.config.enemies.seer.respawn);
  record('A respawn of 0 means never (the seer)', never === 0);

  // nameplates over NPCs and enemies; hidden from Settings
  const names = await page.evaluate(() => {
    const g = window.__shadowfall;
    const m = g.npcs.byId('mara').position;
    g.player.placeAt(m.x + 3, m.z + 3);
    g._snapCamera();
    g.hud.labels.update();
    const shown = [...document.querySelectorAll('#world-labels .name-label')].filter((e) => !e.hidden).map((e) => e.textContent);
    g.settings.set('names', false);
    g.hud.labels.update();
    const off = [...document.querySelectorAll('#world-labels .name-label')].filter((e) => !e.hidden).length;
    g.settings.set('names', true);
    return { shown, off };
  });
  record('Names show over NPCs by default and Settings can hide them', names.shown.some((t) => /Mara Venn/.test(t) && /Smith/.test(t)) && names.off === 0, JSON.stringify(names));

  // chests: open, locked, key, lockpicking
  const chests = await page.evaluate(() => {
    const g = window.__shadowfall;
    const c = (id) => g.chests.list.find((x) => x.def.id === id);
    const sparkBefore = g.sparkles.spots().length;
    const coins0 = g.inventory.coins;
    const opened = g.chests.open(c('roadside_chest'));
    const sparkAfter = g.sparkles.spots().length;
    const got = { coins: g.inventory.coins - coins0, draughts: g.inventory.count('healing_draught') };
    g.hud.lastError = null;
    const lockedTry = g.chests.open(c('watch_coffer'));
    const lockedMsg = g.hud.lastError;
    g.inventory.addItem('watch_key', 1);
    const keyed = g.chests.open(c('watch_coffer'));
    const gloves = g.inventory.count('iron_gloves');
    g.inventory.coins = 100;
    g.skills.ranks.set('lockpicking', 2);
    g.inventory.addItem('lockpicks', 1);
    g.hud.lastError = null;
    const lowPick = g.chests.open(c('blackwood_cache'));
    const lowMsg = g.hud.lastError;
    g.skills.ranks.set('lockpicking', 3);
    const picked = g.chests.open(c('blackwood_cache'));
    return { opened, got, sparkBefore, sparkAfter, lockedTry, lockedMsg, keyed, gloves, lowPick, lowMsg, picked, rank: g.skills.rank('lockpicking'), again: g.chests.open(c('roadside_chest')) };
  });
  record('A chest opens once and gives its silver and items', chests.opened && chests.got.coins === 15 && chests.got.draughts === 2 && chests.again === false, JSON.stringify(chests.got));
  record('Unopened chests sparkle; opening one stops it', chests.sparkAfter === chests.sparkBefore - 1, `${chests.sparkBefore} → ${chests.sparkAfter}`);
  record('A locked chest needs its key or enough Lockpicking', !chests.lockedTry && /locked/i.test(chests.lockedMsg) && chests.keyed && chests.gloves === 1 && !chests.lowPick && chests.picked && chests.rank === 4, `"${chests.lockedMsg}"; key opened it; Lockpicking 2 refused, 3 picked it (now ${chests.rank})`);

  // quest reputation and vendor discount at Friendly
  const disc = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.reputation.points.road_wardens = 0;
    g.merchant.open('mara_forge', g.npcs.byId('mara'));
    const before = g.merchant.priceOf('mail_chausses');
    g.reputation.add('road_wardens', 1000);
    const after = g.merchant.priceOf('mail_chausses');
    g.merchant.close();
    g.hud.togglePanel('character');
    g.hud.items.render();
    const bars = [...document.querySelectorAll('#char-rep .rep-row')].map((r) => r.textContent);
    g.hud.togglePanel('character');
    return { before, after, standing: g.reputation.standing('road_wardens').name, bars };
  });
  record('Friendly with a faction takes 5% off its vendors; the character window lists reputation', disc.standing === 'Friendly' && disc.before === 24 && disc.after === 22 && disc.bars.length === 2 && /Friendly/.test(disc.bars[0]), JSON.stringify(disc));
  record('No script errors (world)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function utilityBar(browser) {
  current = 'Utility bar';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const r = await page.evaluate(() => {
    const g = window.__shadowfall;
    const slots = g.actionBar.slots.length;
    // learning Fishing puts it on the first free utility slot
    g.inventory.coins = 100;
    g.dialogue.open(g.npcs.byId('tam'));
    g.dialogue.choose('train:fishing');
    g.dialogue.close();
    const fishAt = g.actionBar.slots.indexOf('fish');
    // a torch dragged from the bags sits on the bar as an item; key 7 lights it, 7 again puts it away
    g.inventory.addItem('torch', 1);
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'torch');
    g.hud.items.dropOn(loc, 'a:7', true);
    const torchSlot = g.actionBar.slots[7];
    g.input.pressed.add('Digit7');
    g.step(1 / 60);
    const lit = g.inventory.equipment.offHand?.id;
    g.input.pressed.add('Digit7');
    g.step(1 / 60);
    const back = g.inventory.equipment.offHand?.id;
    // a bar saved before the utility slots (six slots, Fishing on 4)
    g.actionBar.apply(['lunge', 'shieldBreak', 'draught', 'fish', 'rebuke', 'brace']);
    const old = [...g.actionBar.slots];
    g.actionBar.reset();
    return { slots, fishAt, torchSlot, lit, back, old };
  });
  record('The bar has 4 utility slots (keys 6–9); new utility skills land there', r.slots === 10 && r.fishAt >= 6, `Fishing in slot ${r.fishAt + 1}`);
  record('A torch on the utility bar lights and puts away with one key', r.torchSlot === 'item:torch' && r.lit === 'torch' && r.back === 'kite_shield', `key 7: ${r.torchSlot}; press: ${r.lit}; again: ${r.back}`);
  record('Old six-slot bars move Fishing to a utility slot', r.old.length === 10 && r.old[3] === null && r.old.indexOf('fish') >= 6, r.old.map((a) => a || '—').join(', '));
  record('No script errors (utility bar)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function uiLayout(browser) {
  current = 'Swing timer, menus and key bindings';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_road').health = 999; g.targeting.engage(g.enemies.byId('ghoul_road')); });
  await sim(page, 0.5);
  const w1 = await page.evaluate(() => ({ shown: !document.getElementById('swing-bar').hidden, fill: parseFloat(document.getElementById('swing-fill').style.width) }));
  await sim(page, 1.0);
  const w2 = await page.evaluate(() => parseFloat(document.getElementById('swing-fill').style.width));
  const castBelow = await page.evaluate(() => getComputedStyle(document.getElementById('swing-bar')).bottom === '112px');
  record('A swing timer fills toward the next blow, where the cast bar sits', w1.shown && w2 > w1.fill && castBelow, `${w1.fill.toFixed(0)}% → ${w2.toFixed(0)}%`);

  const layout = await page.evaluate(() => {
    const r = (id) => document.getElementById(id).getBoundingClientRect();
    const bar = r('action-bar');
    const coins = document.querySelector('#right-dock .coins').getBoundingClientRect();
    return {
      menus: [...document.querySelectorAll('#micro-bar .micro')].map((b) => b.dataset.tip),
      centred: Math.abs((bar.left + bar.right) / 2 - innerWidth / 2) < 2,
      coinsRight: innerWidth - coins.right < 20,
      overlap: bar.right > r('right-dock').left,
    };
  });
  record('The spell bar is centred; money sits on the far right; the menu is Character, Spells, Talents, Quest Log, Settings', layout.centred && layout.coinsRight && !layout.overlap && layout.menus.map((t) => t.replace(/ \(.*\)$/, '')).join(',') === 'Character,Spells,Talents,Quest Log,Settings', JSON.stringify(layout));

  // rebinding: slot 1 to Z, then Z casts what is in slot 1
  const rebind = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.keys.bind('bar0', 'KeyZ');
    const label = document.querySelector('#aslot-0 .key').textContent;
    const fired = g.actionBar.actions([g.keys.pressed('bar0')]);
    g.input.pressed.add('KeyZ');
    const hit = g.keys.pressed('bar0');
    g.input.pressed.add('Digit1');
    const old = g.keys.pressed('bar0');
    g.input.pressed.clear();
    return { label, hit, old };
  });
  record('Settings can rebind a key; the bar shows the new key', rebind.label === 'Z' && rebind.hit && !rebind.old, JSON.stringify(rebind));

  // quick bind: hover a utility slot and press a key
  await resumeLoop(page);
  await page.evaluate(() => window.__shadowfall.hud.togglePanel('settings'));
  await page.click('#quick-bind');
  await page.hover('#aslot-6');
  await page.keyboard.press('KeyF');
  await page.keyboard.press('Escape');
  const quick = await page.evaluate(() => ({ keys: window.__shadowfall.keys.keys('bar6'), label: document.querySelector('#aslot-6 .key').textContent, banner: document.getElementById('quick-bind-banner').hidden }));
  record('Quick bind: hover a utility slot and press a key', quick.keys.join() === 'KeyF' && quick.label === 'F' && quick.banner, JSON.stringify(quick));
  await page.evaluate(() => window.__shadowfall.keys.resetAll());
  record('No script errors (UI layout)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

// `node tests/acceptance.mjs gamepad telegraphs` runs only those sections
async function resources(browser) {
  current = 'Mana and Resolve';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  await page.evaluate(() => (window.__shadowfall.resources.unlimited = false));
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  const start = await page.evaluate(() => {
    const r = window.__shadowfall.resources;
    return { mana: r.mana, max: r.maxMana, gauge: r.gauge, mpShown: !document.getElementById('mp-bar').hidden, gText: document.getElementById('gauge-text').textContent };
  });
  record('The Warden starts with full mana (100 + 10 per Intellect) and no Resolve', start.mana === start.max && start.max === 110 && start.gauge === 0 && start.mpShown, `${start.mana}/${start.max} mana, "${start.gText}"`);

  // Shield Break costs 25 Resolve: refused at 0, slot dimmed
  await page.evaluate(() => { const g = window.__shadowfall; g.enemies.byId('ghoul_road').health = 999; g.targeting.select(g.enemies.byId('ghoul_road')); });
  await sim(page, 0.05);
  const dim = await page.evaluate(() => document.querySelector('.aslot[data-ability="shieldBreak"]')?.classList.contains('nores'));
  const refused = await page.evaluate(() => !window.__shadowfall.spells.tryCast('shieldBreak') && window.__shadowfall.hud.lastError);
  record('A Resolve ability is refused without enough Resolve, and its slot is dimmed', refused !== false && dim, `Shield Break at 0 Resolve: refused ("${refused}"), slot dimmed ${dim}`);

  // auto attack builds Resolve: 12 a landed swing
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.engage(g.enemies.byId('ghoul_road')); g.player.cooldowns.attack = 0; });
  await sim(page, 0.6);
  const afterSwing = await page.evaluate(() => window.__shadowfall.resources.gauge);
  record('Each landed weapon swing builds 12 Resolve', afterSwing === 12, `${afterSwing} Resolve after one swing`);

  // hits taken build Resolve
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); g.resources.gauge = 0; g.combat._enemyHit(g.enemies.byId('ghoul_road'), 4, { canBlock: false }); g.events.emit('playerHurt', { damage: 4 }); });
  const afterHurt = await page.evaluate(() => window.__shadowfall.resources.gauge);
  record('Taking a hit builds Resolve', afterHurt === 6, `${afterHurt} Resolve after one hit`);

  // with 30 Resolve, Shield Break goes and spends 25
  await page.evaluate(() => { const g = window.__shadowfall; g.resources.gauge = 30; g.player.cooldowns.gcd = 0; g.player.pending = null; });
  const sb = await page.evaluate(() => { const g = window.__shadowfall; return { ok: g.spells.tryCast('shieldBreak'), left: g.resources.gauge }; });
  record('Shield Break spends 25 Resolve', sb.ok && sb.left === 5, `cast: ${sb.ok}, ${sb.left} Resolve left`);

  // Lunge gives Resolve (an opener)
  await sim(page, 2);
  await page.evaluate(() => { const g = window.__shadowfall; g.resources.gauge = 0; Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0)); g.player.pending = null; g.player.placeAt(0, 4); g.enemies.byId('ghoul_road').position.set(0, 0, 0); });
  const lunge = await page.evaluate(() => { const g = window.__shadowfall; return { ok: g.spells.tryCast('lunge'), r: g.resources.gauge }; });
  record('Lunge is free and gives 15 Resolve to open a fight', lunge.ok && lunge.r === 15, `cast: ${lunge.ok}, ${lunge.r} Resolve`);

  // Hallowed Bolt costs 20 mana, paid when the cast finishes
  await sim(page, 2);
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0)); g.player.pending = null; g.player.lunge = null; g.resources.mana = 50; });
  const castOk = await page.evaluate(() => window.__shadowfall.spells.tryCast('hallowedBolt'));
  const midCast = await page.evaluate(() => window.__shadowfall.resources.mana);
  await sim(page, 1.8);
  const afterCast = await page.evaluate(() => window.__shadowfall.resources.mana);
  record('Hallowed Bolt costs 20 mana, paid when the cast finishes', castOk && midCast >= 50 && afterCast > 29 && afterCast < 34, `mana 50 → ${midCast.toFixed(1)} while casting → ${afterCast.toFixed(1)} after (regen 1.5/s in combat)`);
  await page.evaluate(() => { const g = window.__shadowfall; g.player.cooldowns.gcd = 0; g.player.cooldowns.hallowedBolt = 0; g.resources.mana = 5; });
  const noMana = await page.evaluate(() => !window.__shadowfall.spells.tryCast('hallowedBolt') && window.__shadowfall.hud.lastError);
  record('A spell is refused without enough mana', !!noMana && /mana/.test(noMana), `"${noMana}"`);

  // out of combat: mana refills fast, Resolve fades
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); const e = g.enemies.byId('ghoul_road'); e.position.set(-30, 0, -45); e.home.copy(e.position); e.state = 'idle'; g.resources.sinceCombat = 99; g.resources.gauge = 40; g.resources.mana = 10; });
  await sim(page, 2);
  const ooc = await page.evaluate(() => ({ m: window.__shadowfall.resources.mana, g: window.__shadowfall.resources.gauge }));
  record('Out of combat mana refills at 10 a second and Resolve fades at 8 a second', near(ooc.m, 30, 1) && near(ooc.g, 24, 1), `2 s later: ${ooc.m.toFixed(1)} mana, ${ooc.g.toFixed(1)} Resolve`);

  // tooltips show the cost
  await page.hover('.aslot[data-ability="shieldBreak"]');
  const tipCost = await page.evaluate(() => document.querySelector('.tt-cost')?.textContent);
  record('Ability tooltips show the cost', tipCost === '25 Resolve', `"${tipCost}"`);
  record('No script errors (resources)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function swingTimer(browser) {
  current = 'Swing timer formula';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // T = W / (1 + H), with Dan's table for a 2.5 s weapon
  const table = await page.evaluate(() => {
    const st = window.__shadowfall.stats;
    const keep = { haste: Object.getOwnPropertyDescriptor(Object.getPrototypeOf(st), 'haste'), speed: Object.getOwnPropertyDescriptor(Object.getPrototypeOf(st), 'weaponSpeed') };
    st.handSpeed = () => 2.5;
    const out = [0, 10, 20, 30].map((h) => {
      Object.defineProperty(st, 'haste', { get: () => h, configurable: true });
      return { h, t: +st.attackCooldown.toFixed(3), windup: st.swingWindup, anim: st.swingAnimation };
    });
    delete st.haste;
    delete st.handSpeed;
    return out;
  });
  record('Time between swings = weapon speed ÷ (1 + haste)', table.map((r) => r.t).join() === '2.5,2.273,2.083,1.923', table.map((r) => `${r.h}% ${r.t}s`).join(', '));
  record('Haste shortens the interval, not the swing animation', table.every((r) => r.windup === table[0].windup && r.anim === table[0].anim), `impact at ${table[0].windup}s, animation ${table[0].anim}s at every haste`);

  // the rhythm is the same at 30, 60 and 144 fps, and through a long frame
  const swingsAt = async (fps) => {
    await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
    await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
    await page.evaluate(() => {
      const g = window.__shadowfall;
      g.player.lastSwingAt = undefined;
      g.player.cooldowns.attack = 0;
      g.player.pending = null;
      g.enemies.byId('ghoul_road').health = 9999;
      g.__swings = [];
      if (!g.__swingHook) { g.__swingHook = true; g.events.on('enemyHit', (e) => e.swing && g.__swings.push(+g.time.toFixed(3))); }
      g.targeting.stopAttack();
      g.targeting.engage(g.enemies.byId('ghoul_road'));
    });
    await sim(page, 11.2, { fps });
    await page.evaluate(() => window.__shadowfall.targeting.stopAttack());
    return page.evaluate(() => { const s = window.__shadowfall.__swings; return s.map((t) => +(t - s[0]).toFixed(2)); });
  };
  const at30 = await swingsAt(30);
  const at60 = await swingsAt(60);
  const at144 = await swingsAt(144);
  const at4 = await swingsAt(4);
  const T = await page.evaluate(() => window.__shadowfall.stats.attackCooldown);
  const steady = (s) => s.length >= 4 && s.every((t, i) => near(t, i * T, 0.05));
  record('The swing rhythm is the same at 30, 60 and 144 fps (delta time)', steady(at30) && steady(at60) && steady(at144) && at30.length === at144.length, `${T}s weapon: 30 fps ${at30.join(', ')} | 60 fps ${at60.join(', ')} | 144 fps ${at144.join(', ')}`);
  record('A long frame does not lose the rhythm or cause a burst', at4.length === at60.length && at4.every((t, i) => near(t, i * T, 0.3)), `at 4 fps: ${at4.join(', ')}`);

  // the animation's impact frame, the hit and the bar filling are one moment
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.__sync = [];
    g.enemies.byId('ghoul_road').health = 9999;
    g.events.on('playerSwing', (e) => { if (!e.hand) g.__sync.push({ start: g.time, impactIn: g.player.pending.t, clock: g.player.cooldowns.attack, frac: g.player.rig.action.impact * g.player.rig.action.duration }); });
    g.events.on('enemyHit', (e) => { if (e.swing && g.__sync.length) Object.assign(g.__sync[g.__sync.length - 1], { hit: g.time, bar: document.getElementById('swing-fill').style.width }); });
    g.targeting.engage(g.enemies.byId('ghoul_road'));
  });
  await sim(page, 0.1);
  await sim(page, 3 * T);
  const sync = await page.evaluate(() => window.__shadowfall.__sync.filter((x) => x.hit).map((x) => ({ lead: +(x.hit - x.start).toFixed(3), impactIn: +x.impactIn.toFixed(3), clock: +x.clock.toFixed(3), frac: +x.frac.toFixed(3), bar: x.bar })));
  await page.evaluate(() => window.__shadowfall.targeting.stopAttack());
  record('The blow lands on the animation\'s impact frame, exactly when the swing clock runs out', sync.length >= 2 && sync.every((x) => near(x.lead, x.impactIn, 1 / 60 + 0.001) && near(x.impactIn, Math.max(x.clock, 0.12), 0.005) && near(x.frac, x.impactIn, 0.001)), sync.map((x) => `swing began ${x.impactIn}s before the clock ran out (impact frame ${x.frac}s in), hit ${x.lead}s after`).join('; '));

  // out of reach: the clock waits at zero; back in reach it swings once, then a full interval
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -6, { frozen: true });
  // first, the opening: the clock does not run while you close in
  await page.evaluate(() => { const g = window.__shadowfall; g.player.lastSwingAt = undefined; g.__swings = []; g.player.cooldowns.attack = 0; g.targeting.engage(g.enemies.byId('ghoul_road')); });
  await sim(page, 4);
  const closing = await page.evaluate(() => ({ clock: window.__shadowfall.player.cooldowns.attack, hits: window.__shadowfall.__swings.length }));
  await page.evaluate(() => { const g = window.__shadowfall; g.__reachedAt = g.time; g.enemies.byId('ghoul_road').position.set(0, 0, -1.6); g.enemies.byId('ghoul_road').health = 9999; });
  await sim(page, T + 0.3);
  const opener = await page.evaluate(() => { const g = window.__shadowfall; return g.__swings.map((t) => +(t - g.__reachedAt).toFixed(2)); });
  record('A new fight opens with an instant blow the moment you reach the target (WoW); nothing runs while you close in', closing.clock === 0 && closing.hits === 0 && opener.length === 2 && opener[0] <= 0.15 && near(opener[1] - opener[0], T, 0.05), `4 s closing in: clock ${closing.clock}, no swings; blows ${opener.join(', ')}s after reaching it (T ${T}s)`);
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); g.enemies.byId('ghoul_road').position.set(0, 0, -6); });
  await sim(page, 3);
  // mid-fight: a clock that runs out with the target out of reach waits at zero
  await page.evaluate(() => { const g = window.__shadowfall; g.player.health = g.player.maxHealth; g.player.lastSwingAt = undefined; g.__swings = []; g.targeting.engage(g.enemies.byId('ghoul_road')); g.player.cooldowns.attack = 0; });
  await sim(page, 4);
  await page.evaluate(() => { const e = window.__shadowfall.enemies.byId('ghoul_road'); e.position.set(0, 0, -1.6); e.health = 9999; });
  await sim(page, 3);
  const back = await page.evaluate(() => { const s = window.__shadowfall.__swings; return s.map((t) => +(t - s[0]).toFixed(2)); });
  record('Out of reach the swing waits; back in reach it swings once, then a full interval later (no burst)', back.length === 2 && near(back[1], T, 0.05), `swings after stepping back in: ${back.join(', ')}`);

  // the damage checks reach at the impact frame
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); g.__swings = []; });
  await sim(page, 3);
  await page.evaluate(() => { const g = window.__shadowfall; g.player.health = g.player.maxHealth; g.enemies.byId('ghoul_road').health = 9999; g.player.cooldowns.attack = 0; g.targeting.engage(g.enemies.byId('ghoul_road')); g.player.cooldowns.attack = 0; });
  await sim(page, 0.05);
  const started = await page.evaluate(() => window.__shadowfall.player.pending?.type === 'strike');
  await page.evaluate(() => { const e = window.__shadowfall.enemies.byId('ghoul_road'); e.position.set(0, 0, -8); });
  await sim(page, 0.4);
  const landed = await page.evaluate(() => window.__shadowfall.__swings.length);
  record('Damage resolves at the impact frame and checks reach then', started && landed === 0, `swing started in reach, target stepped away before impact: ${landed} hits`);

  // switching target mid-fight keeps the running clock
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road', 'ghoul_cart'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await placeEnemy(page, 'ghoul_cart', 1.2, -1.2, { frozen: true });
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); g.enemies.list.forEach((e) => (e.health = 9999)); g.player.lastSwingAt = undefined; g.player.cooldowns.attack = 0; g.targeting.engage(g.enemies.byId('ghoul_road')); g.player.cooldowns.attack = 0; });
  await sim(page, 0.8);
  const before = await page.evaluate(() => window.__shadowfall.player.cooldowns.attack);
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.engage(g.enemies.byId('ghoul_cart')); });
  const after = await page.evaluate(() => window.__shadowfall.player.cooldowns.attack);
  record('Switching target mid-fight keeps the swing clock', near(before, after, 0.001) && before < T - 0.5, `${before.toFixed(2)}s left before, ${after.toFixed(2)}s after switching`);

  record('No script errors (swing timer)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function dualWield(browser) {
  current = 'Dual wielding';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // a sword in the main hand, a dirk in the off hand (the shield goes back in the bag)
  const eq = await page.evaluate(() => {
    const g = window.__shadowfall;
    const inv = g.inventory;
    inv.addItem('arming_sword', 1, { quiet: true });
    inv.addItem('rusty_dirk', 1, { quiet: true });
    inv.equip('arming_sword');
    const loc = inv.bagLocations().find((l) => inv.get(l)?.id === 'rusty_dirk');
    const ok = inv.move(loc, 'e:offHand').ok;
    return { main: inv.equipment.mainHand?.id, off: inv.equipment.offHand?.id, ok, dual: g.stats.dualWielding, shieldInBag: inv.count('kite_shield') };
  });
  record('One-handed weapons go in either hand; a dirk can be dual wielded', eq.ok && eq.main === 'arming_sword' && eq.off === 'rusty_dirk' && eq.dual && eq.shieldInBag === 1, JSON.stringify(eq));
  const refuse = await page.evaluate(() => {
    const g = window.__shadowfall;
    const a = g.stats.archetype;
    a.dualWield = false;
    const ok = g.inventory.canWear(g.items.rusty_dirk, 'offHand');
    a.dualWield = true;
    return ok;
  });
  record('A class without dual wielding cannot put a weapon in the off hand', refuse === false);

  const nums = await page.evaluate(() => {
    const st = window.__shadowfall.stats;
    return { main: st.swingRangeFor('main'), off: st.swingRangeFor('off'), tMain: st.attackCooldownFor('main'), tOff: st.attackCooldownFor('off'), dirk: window.__shadowfall.items.rusty_dirk.damage, sword: window.__shadowfall.items.arming_sword.damage };
  });
  const offFull = await page.evaluate(() => { const st = window.__shadowfall.stats; const [lo, hi] = st.weaponRangeFor('off'); const p = st.swingPowerFor('off'); return [Math.round(lo + p), Math.round(hi + p)]; });
  record('Off-hand blows do half damage', near(nums.off[0], offFull[0] / 2, 0.6) && near(nums.off[1], offFull[1] / 2, 0.6), `sword ${nums.sword.join('–')} @ ${nums.tMain}s → ${nums.main.join('–')} a swing; dirk ${nums.dirk.join('–')} @ ${nums.tOff}s → ${nums.off.join('–')} in the off hand (full ${offFull.join('–')})`);

  // each hand swings on its own clock, staggered
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -1.6, { frozen: true });
  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.enemies.byId('ghoul_road').health = 99999;
    g.__hits = [];
    // a frozen ghoul does not walk back after knockback, so hold it in place
    g.events.on('enemyHit', (e) => { if (!e.swing) return; g.__hits.push({ hand: e.hand || 'main', t: +g.time.toFixed(3), dmg: e.damage }); e.enemy.knock.set(0, 0, 0); e.enemy.position.set(0, 0, -1.6); });
    g.player.lastSwingAt = undefined;
    g.player.cooldowns.attack = 0;
    g.player.cooldowns.attackOff = 0;
    g.targeting.engage(g.enemies.byId('ghoul_road'));
  });
  await sim(page, 0.6);
  const bars = await page.evaluate(() => ({ main: !document.getElementById('swing-bar').hidden, off: !document.getElementById('swing-bar-off').hidden, offText: document.getElementById('swing-text-off').textContent }));
  await sim(page, 12);
  const hits = await page.evaluate(() => window.__shadowfall.__hits);
  const main = hits.filter((h) => h.hand === 'main').map((h) => h.t);
  const off = hits.filter((h) => h.hand === 'off').map((h) => h.t);
  const gaps = (a) => a.slice(1).map((t, i) => +(t - a[i]).toFixed(2));
  const closest = Math.min(...off.map((t) => Math.min(...main.map((m) => Math.abs(m - t)))));
  record('Each hand swings on its own clock at its own weapon speed', main.length >= 4 && off.length >= 5 && gaps(main).every((d) => near(d, nums.tMain, 0.05)) && gaps(off).every((d) => d >= nums.tOff - 0.05) && gaps(off).filter((d) => near(d, nums.tOff, 0.05)).length >= gaps(off).length / 2,
    `main hand every ${gaps(main).join(', ')}s; off hand every ${gaps(off).join(', ')}s`);
  record('The two hands are staggered: never within 0.2 s of each other', closest >= 0.19, `closest main/off blows ${closest.toFixed(2)}s apart; main ${main.join(', ')} · off ${off.join(', ')}`);
  record('Both swing timers show while dual wielding', bars.main && bars.off && /off hand/.test(bars.offText), JSON.stringify(bars));
  const offDmg = hits.filter((h) => h.hand === 'off').map((h) => h.dmg);
  const mainDmg = hits.filter((h) => h.hand === 'main').map((h) => h.dmg);
  record('Off-hand hits land for less', Math.max(...offDmg) < Math.min(...mainDmg), `main ${mainDmg.join(',')} · off ${offDmg.join(',')}`);

  // off-hand swings build half the Resolve
  await page.evaluate(() => { const g = window.__shadowfall; g.resources.gauge = 0; g.events.emit('enemyHit', { enemy: g.enemies.byId('ghoul_road'), damage: 1, kind: 'strike', swing: true, hand: 'off' }); });
  const rOff = await page.evaluate(() => window.__shadowfall.resources.gauge);
  record('Off-hand swings build half the Resolve', rOff === 6, `${rOff} Resolve from one off-hand blow`);

  // tooltip: One-hand dagger
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); g.inventory.addItem('ghoulbone_knife', 1, { quiet: true }); g.hud.togglePanel('bags'); });
  await sim(page, 0.1);
  const loc = await page.evaluate(() => window.__shadowfall.inventory.bagLocations().find((l) => window.__shadowfall.inventory.get(l)?.id === 'ghoulbone_knife'));
  await page.hover(`[data-loc="${loc}"]`);
  const tipKind = await page.evaluate(() => document.querySelector('.tt-kind')?.textContent);
  record('Tooltips name one-handed weapons', /One-hand dagger/.test(tipKind || ''), `"${tipKind}"`);

  record('No script errors (dual wielding)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function townAndCooking(browser) {
  current = 'Town, inn and cooking';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  // Hester teaches Cooking, then a recipe that needs rank 10
  const learn = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addCoins(500);
    g.dialogue.open(g.npcs.byId('hester'));
    const menu = g.dialogue.page.options.map((o) => o.id);
    g.dialogue.choose('train');
    const opts = [...menu, ...g.dialogue.page.options.map((o) => o.id)];
    const ok = g.dialogue.choose('train:cooking');
    const after = g.dialogue.page.options.map((o) => o.id);
    const early = g.cooking.learnRecipe('hound_steak');
    g.dialogue.close();
    return { opts, ok, after, early, rank: g.skills.rank('cooking'), known: g.cooking.known().map((r) => r.id) };
  });
  record('Hester, the innkeeper, teaches Cooking; the starter recipes come with it', learn.opts.includes('train:cooking') && learn.opts.includes('home') && learn.ok && learn.rank === 1 && learn.known.join() === 'grilled_perch,roast_dace', JSON.stringify(learn));
  record('She offers taught recipes once you can cook, but not before your rank allows', learn.after.includes('recipe:hound_steak') && learn.early === false, learn.after.join(', '));

  // cook at the hearth: needs a fire, takes a cast, raises the skill (orange)
  await setup(page, { x: 30, z: 60 });
  await page.evaluate(() => window.__shadowfall.inventory.addItem('gloomwater_perch', 3, { quiet: true }));
  const noFire = await page.evaluate(() => ({ ok: window.__shadowfall.cooking.start('grilled_perch'), why: window.__shadowfall.cooking.blocked(window.__shadowfall.db.recipes.grilled_perch) }));
  await setup(page, { x: 4.6, z: 69.6 });
  await sim(page, 0.2);
  const prompt = await page.evaluate(() => { const g = window.__shadowfall; g.interaction.update(); return g.interaction.current?.prompt; });
  await page.evaluate(() => window.__shadowfall.interaction.interact());
  await sim(page, 0.1);
  const winOpen = await page.evaluate(() => !document.getElementById('cooking-window').hidden && document.querySelectorAll('#cooking-list .recipe').length);
  record('Cooking needs a fire; E at the inn hearth opens the cooking window', noFire.ok === false && /fire/.test(noFire.why) && /hearth/.test(prompt || '') && winOpen === 2, `away: "${noFire.why}"; prompt "${prompt}"; ${winOpen} recipes listed`);
  await page.click('#cooking-list [data-cook="grilled_perch"][data-all]');
  await sim(page, 1.2);
  const mid = await page.evaluate(() => ({ cast: !document.getElementById('cast-bar').hidden, text: document.getElementById('cast-text').textContent, made: window.__shadowfall.inventory.count('grilled_perch') }));
  await sim(page, 7);
  const done = await page.evaluate(() => ({ made: window.__shadowfall.inventory.count('grilled_perch'), raw: window.__shadowfall.inventory.count('gloomwater_perch'), rank: window.__shadowfall.skills.rank('cooking') }));
  record('Cook all makes each dish after a 2.5 s cast, shown on the cast bar', mid.cast && /Cooking Grilled perch/i.test(mid.text) && mid.made === 0 && done.made === 3 && done.raw === 0, `${mid.text}; then ${done.made} cooked, ${done.raw} raw left`);
  record('Orange recipes always raise the skill', done.rank === 4, `Cooking ${done.rank}`);
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'cooking.png') });
  // moving stops cooking
  await page.evaluate(() => { const g = window.__shadowfall; g.inventory.addItem('silver_dace', 2, { quiet: true }); g.cooking.start('roast_dace', Infinity); });
  await sim(page, 0.8, { held: ['KeyD'] });
  const stopped = await page.evaluate(() => ({ c: window.__shadowfall.cooking.crafting, n: window.__shadowfall.inventory.count('roast_dace') }));
  record('Moving stops cooking', !stopped.c && stopped.n === 0, JSON.stringify(stopped));

  // cook one, then the next from the same window, without reopening it
  await setup(page, { x: 4.6, z: 69.6 });
  await page.evaluate(() => { const g = window.__shadowfall; g.inventory.addItem('gloomwater_perch', 2, { quiet: true }); g.hud.items.closeAll(); g.hud.items.toggle('cooking'); });
  await sim(page, 0.1);
  await page.click('#cooking-list [data-cook="grilled_perch"]:not([data-all])');
  await sim(page, 2.8);
  const again = await page.evaluate(() => { const b = document.querySelector('#cooking-list [data-cook="grilled_perch"]:not([data-all])'); return { disabled: b.disabled, busy: !!window.__shadowfall.cooking.crafting }; });
  if (!again.disabled) await page.click('#cooking-list [data-cook="grilled_perch"]:not([data-all])');
  await sim(page, 2.8);
  const twice = await page.evaluate(() => window.__shadowfall.inventory.count('gloomwater_perch'));
  record('Cooking: after one dish the window offers the next at once (no closing and reopening)', !again.disabled && !again.busy && twice === 0, `Cook button enabled after the first: ${!again.disabled}; raw perch left ${twice}`);
  await page.evaluate(() => window.__shadowfall.hud.items.closeAll());

  // eat: sit, heal over time, stop on moving; refused in a fight
  const eat = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.health = 20;
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'grilled_perch');
    g.inventory.use(loc);
    return { eating: !!g.player.eating, pose: g.player.rig.pose, hp: g.player.health };
  });
  await sim(page, 5);
  const ate = await page.evaluate(() => ({ hp: window.__shadowfall.player.health, eating: !!window.__shadowfall.player.eating }));
  await sim(page, 0.4, { held: ['KeyW'] });
  const moved = await page.evaluate(() => ({ eating: !!window.__shadowfall.player.eating, pose: window.__shadowfall.player.rig.pose }));
  record('Eating sits you down and heals over time; moving stops it', eat.eating && eat.pose === 'sit' && ate.hp > 30 && ate.eating && !moved.eating && moved.pose !== 'sit', `${eat.hp} → ${ate.hp} hp in 5 s; after moving: ${JSON.stringify(moved)}`);
  const fight = await page.evaluate(() => {
    const g = window.__shadowfall;
    Object.defineProperty(g.resources, 'inCombat', { value: true, configurable: true });
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'grilled_perch');
    const ok = g.cooking.eat(loc);
    delete g.resources.inCombat;
    return ok;
  });
  record("You can't eat in a fight", fight === false);

  // Well Fed: eat for 10 seconds, even at full health
  const fed0 = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.health = g.player.maxHealth;
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'grilled_perch');
    return { ok: g.cooking.eat(loc), hp: g.player.maxHealth, stam: g.stats.totals.stamina };
  });
  await sim(page, 9.5);
  const fed1 = await page.evaluate(() => !!window.__shadowfall.cooking.wellFedAura);
  await sim(page, 0.7);
  const fed2 = await page.evaluate(() => { const g = window.__shadowfall; return { aura: g.cooking.wellFedAura, eating: !!g.player.eating, hp: g.player.maxHealth, stam: g.stats.totals.stamina, buffs: document.querySelectorAll('#buffs .aura').length }; });
  record('Eating for 10 seconds makes you Well Fed: a little Stamina for 15 minutes (shown with your buffs)', fed0.ok && !fed1 && fed2.aura && fed2.stam === fed0.stam + 2 && fed2.hp > fed0.hp && !fed2.eating && fed2.buffs >= 1, `Stamina ${fed0.stam} → ${fed2.stam}, health ${fed0.hp} → ${fed2.hp}; ${Math.round(fed2.aura?.left)} s left`);

  // indoors: walls block, the roof and front wall fade, the camera comes in
  await page.evaluate(() => { window.__shadowfall.hud.items.closeAll(); document.getElementById('ui-error').classList.remove('show'); });
  await setup(page, { x: -7, z: 74 });
  await sim(page, 1.5);
  const out = await page.evaluate(() => { const g = window.__shadowfall; return { cam: g.camera.position.distanceTo(g.player.position), blend: g.world.indoorBlend }; });
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'town.png') });
  await setup(page, { x: 8, z: 70 });
  await sim(page, 1.5);
  const inn = await page.evaluate(() => { const g = window.__shadowfall; const b = g.world.indoors; return { cam: g.camera.position.distanceTo(g.player.position), blend: g.world.indoorBlend, name: b?.def.name, roof: b?.fade[1].mats[0].opacity, front: b?.fade[0].mats[0].opacity, roofVis: b?.fade[1].obj.visible }; });
  record('Inside the inn the roof hides, the front wall fades and the camera comes closer', inn.name && inn.blend > 0.95 && out.blend < 0.05 && inn.roofVis === false && inn.front < 0.3 && inn.cam < out.cam * 0.85, `outside ${out.cam.toFixed(1)} m, inside ${inn.cam.toFixed(1)} m; roof ${inn.roof?.toFixed(2)}, front ${inn.front?.toFixed(2)}`);
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'inn.png') });
  // walls are solid: walk north into the north wall
  await sim(page, 3, { held: ['KeyW'] });
  const z = await page.evaluate(() => window.__shadowfall.player.position.z);
  record('The inn walls are solid', z > 67.6, `stopped at z ${z.toFixed(2)} (north wall at 67.5)`);
  // resting at the inn builds rested XP
  await page.evaluate(() => { window.__shadowfall.progression.rested = 0; });
  await sim(page, 2);
  const rested = await page.evaluate(() => ({ r: window.__shadowfall.progression.rested, where: window.__shadowfall.camp.resting }));
  record('Resting inside the inn builds rested experience', rested.r > 0 && rested.where === 'inn', JSON.stringify(rested));
  // make it your home: you wake here after a death, and it saves
  const home = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.dialogue.open(g.npcs.byId('hester'));
    g.dialogue.choose('home');
    g.dialogue.close();
    const rp = g.afterlife.restPoint();
    const saved = JSON.parse(JSON.stringify(g.worldState.serialize()));
    g.worldState.apply(saved);
    return { point: g.worldState.restPoint, rp, again: g.worldState.restPoint };
  });
  record('Make this inn your home: you wake by its hearth, and it is saved', home.point === 'inn:hester' && home.rp.kind === 'inn' && home.again === 'inn:hester', JSON.stringify(home));

  record('No script errors (town and cooking)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function wowCombat(browser) {
  current = 'WoW combat feel';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  const T = await page.evaluate(() => window.__shadowfall.stats.attackCooldown);
  const fresh = async (z = -1.6) => {
    await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
    await placeEnemy(page, 'ghoul_road', 0, z, { frozen: true });
    await page.evaluate(() => {
      const g = window.__shadowfall;
      g.targeting.stopAttack();
      g.player.health = g.player.maxHealth;
      g.player.lastSwingAt = undefined;
      g.player.pending = null;
      g.player.casting = null;
      g.spells.queued = null;
      Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0));
      const e = g.enemies.byId('ghoul_road');
      e.health = 99999;
      g.__hits = [];
      if (!g.__hook) {
        g.__hook = true;
        g.events.on('enemyHit', (x) => {
          g.__hits.push({ t: +g.time.toFixed(3), hand: x.hand || null, swing: !!x.swing, kind: x.kind });
          if (x.enemy.alive) x.enemy.health = 99999; // (a reset to full health on leashing would let it die)
        });
        g.events.on('playerShot', () => (g.__shots = (g.__shots || []).concat(+g.time.toFixed(3))));
      }
      g.__shots = [];
    });
  };

  // an ability is never eaten by a swing on its way
  await fresh();
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.engage(g.enemies.byId('ghoul_road')); });
  await sim(page, 0.05);
  const mid = await page.evaluate(() => ({ swing: window.__shadowfall.player.pending?.type === 'strike', ok: window.__shadowfall.spells.tryCast('smite'), cd: window.__shadowfall.player.cooldowns.smite }));
  record('An ability goes off even while a swing is on its way (no animation lock)', mid.swing && mid.ok && mid.cd > 0, JSON.stringify(mid));

  // moving at full speed while swinging and after an ability
  await fresh(-1.4);
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.engage(g.enemies.byId('ghoul_road')); g.spells.tryCast('smite'); });
  const x0 = await page.evaluate(() => window.__shadowfall.player.position.x);
  await sim(page, 0.3, { held: ['KeyD'] });
  const moved = await page.evaluate(() => window.__shadowfall.player.position.x);
  const full = await page.evaluate(() => window.__shadowfall.config.player.speed * 0.3);
  record('Swinging and using abilities never slow you down', (moved - x0) > full * 0.9, `${(moved - x0).toFixed(2)} m in 0.3 s (full speed ${full.toFixed(2)} m)`);

  // the spell queue window
  await fresh();
  const q = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.targeting.engage(g.enemies.byId('ghoul_road'));
    g.player.cooldowns.gcd = 0.3;
    const early = g.spells.tryCast('smite');
    return { early, queued: g.spells.queued?.id };
  });
  await sim(page, 0.35);
  const qd = await page.evaluate(() => ({ cd: window.__shadowfall.player.cooldowns.smite, queued: window.__shadowfall.spells.queued }));
  await page.evaluate(() => { const g = window.__shadowfall; g.player.cooldowns.smite = 0; g.player.cooldowns.gcd = 0.9; g.spells.tryCast('smite'); });
  const far = await page.evaluate(() => window.__shadowfall.spells.queued);
  record('Spell queue: pressed in the last 0.4 s of the global cooldown, a spell goes off the moment it ends', q.early === false && q.queued === 'smite' && qd.cd > 5 && !qd.queued && !far, `queued ${q.queued}; went off when the GCD ended (cooldown ${qd.cd.toFixed(1)}s); 0.9 s early is not queued`);

  // pushback
  await fresh(-6);
  const pb = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.targeting.select(g.enemies.byId('ghoul_road'));
    g.spells.tryCast('hallowedBolt');
    const c = g.player.casting;
    c.t = 1.0;
    const out = [];
    for (let i = 0; i < 3; i++) {
      g.events.emit('playerHurt', { enemy: g.enemies.byId('ghoul_road'), damage: 5 });
      out.push(+c.t.toFixed(2));
    }
    return out;
  });
  record('Pushback: each hit taken while casting sets the cast back 0.5 s, at most twice', pb.join() === '0.5,0,0', `cast at 1.0 s, after three hits: ${pb.join(', ')}`);

  // the bow: Auto Shot beyond melee reach, arrows in flight, on the move
  await fresh(-10);
  const eq = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.casting = null;
    g.inventory.addItem('hunting_bow', 1, { quiet: true });
    const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'hunting_bow');
    const r = g.inventory.move(loc, 'e:ranged');
    return { ok: r.ok, bow: g.inventory.rangedWeapon?.name, T: g.stats.attackCooldownFor('ranged') };
  });
  // no arrows, no shots
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.engage(g.enemies.byId('ghoul_road')); });
  await sim(page, 1);
  const dry = await page.evaluate(() => ({ shots: window.__shadowfall.__shots.length, text: document.getElementById('swing-text').textContent, log: [...document.querySelectorAll('#log li')].map((l) => l.textContent).filter((t) => /no arrows/.test(t)).length }));
  record('Auto Shot needs arrows: with none it does not fire, and says so', dry.shots === 0 && /no arrows/.test(dry.text) && dry.log > 0, `${dry.shots} shots; bar "${dry.text}"`);
  await page.evaluate(() => { const g = window.__shadowfall; g.targeting.stopAttack(); g.inventory.addItem('rough_arrow', 100, { quiet: true }); g.player.cooldowns.ranged = 0; g.targeting.engage(g.enemies.byId('ghoul_road')); });
  await sim(page, 0.3);
  const bar = await page.evaluate(() => ({ text: document.getElementById('swing-text').textContent, inHand: window.__shadowfall.player.bowInHand }));
  await sim(page, 0.4);
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'auto-shot.png') });
  // moving holds Auto Shot (WoW Classic): no arrow leaves while you walk
  const walkFrom = await page.evaluate(() => window.__shadowfall.__shots.length);
  await sim(page, (eq.T + 0.4) / 2, { held: ['ArrowLeft'] });
  await sim(page, (eq.T + 0.4) / 2, { held: ['ArrowRight'] });
  const walkShots = (await page.evaluate(() => window.__shadowfall.__shots.length)) - walkFrom;
  await sim(page, 2 * eq.T + 0.6);
  const bow = await page.evaluate(() => ({ shots: window.__shadowfall.__shots, hits: window.__shadowfall.__hits.filter((h) => h.hand === 'ranged').map((h) => h.t) }));
  const flight = bow.hits.length ? +(bow.hits[0] - bow.shots[0]).toFixed(2) : null;
  const left = await page.evaluate(() => window.__shadowfall.inventory.count('rough_arrow'));
  record('Each shot uses one arrow', left === 100 - bow.shots.length, `${bow.shots.length} shots, ${left} of 100 arrows left`);
  const gap = bow.shots.length > 2 ? +(bow.shots.at(-1) - bow.shots.at(-2)).toFixed(2) : null;
  record('A bow goes in the ranged slot; with the target beyond melee reach, Auto Shot fires on the bow\'s own timer', eq.ok && bow.shots.length >= 3 && near(gap, eq.T, 0.05) && /Auto Shot/.test(bar.text) && bar.inHand, `${eq.bow}: shots at ${bow.shots.join(', ')} (every ${eq.T.toFixed(1)} s); bar "${bar.text}"`);
  record('Arrows fly to the target and hit on arrival', flight !== null && flight > 0.2 && flight < 0.45 && bow.hits.length >= 2, `first arrow took ${flight}s to land; ${bow.hits.length} hits`);
  record('Auto Shot needs you to stand still: walking (arrow keys) holds it, and it resumes when you stop', walkShots === 0 && bow.shots.length >= walkFrom + 2, `${walkShots} shots while walking ${(eq.T + 0.4).toFixed(1)} s; ${bow.shots.length} shots in all`);

  // the target comes into reach: the sword takes over
  await page.evaluate(() => { const g = window.__shadowfall; const p = g.player.position; g.enemies.byId('ghoul_road').position.set(p.x, 0, p.z - 1.6); g.__hits = []; });
  await sim(page, T + 0.4);
  const melee = await page.evaluate(() => window.__shadowfall.__hits.map((h) => h.hand));
  record('In melee reach the sword takes over from the bow', melee.includes('main') && !melee.slice(1).includes('ranged'), melee.join(', '));

  // arrows by the hundred from a vendor, and a quiver
  const shop = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.targeting.stopAttack();
    g.inventory.removeAll('rough_arrow');
    g.inventory.addCoins(500);
    const before = g.inventory.coins;
    g.merchant.open('tam_outfitters', g.npcs.byId('tam'));
    g.merchant.buy('rough_arrow');
    const arrows = g.inventory.count('rough_arrow');
    const paid = before - g.inventory.coins;
    const T0 = g.stats.attackCooldownFor('ranged');
    g.merchant.buy('leather_quiver');
    const qloc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'leather_quiver');
    const socket = [1, 2, 3].find((i) => !g.inventory.sockets[i]);
    const placed = g.inventory.move(qloc, `s:${socket}`).ok;
    const T1 = g.stats.attackCooldownFor('ranged');
    g.inventory.removeAll('rough_arrow');
    g.merchant.buy('rough_arrow');
    const inQuiver = g.inventory.sockets[socket].slots.filter((x) => x?.id === 'rough_arrow').reduce((n, x) => n + x.count, 0);
    // anything else is refused
    g.inventory.addItem('healing_draught', 1, { quiet: true });
    const dloc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'healing_draught' && !l.startsWith(`b:${socket}:`));
    const refused = !g.inventory.move(dloc, `b:${socket}:5`).ok;
    g.merchant.close();
    return { arrows, paid, placed, T0: +T0.toFixed(3), T1: +T1.toFixed(3), inQuiver, refused };
  });
  record('Arrows are sold by the hundred (1 silver)', shop.arrows === 100 && shop.paid === 1, `${shop.arrows} arrows for ${shop.paid} silver`);
  record('A quiver goes in a bag slot, holds only arrows (new arrows go there first) and makes Auto Shot 10% faster', shop.placed && shop.inQuiver >= 100 && shop.refused && near(shop.T1, shop.T0 / 1.1, 0.002), `quiver holds ${shop.inQuiver} arrows; a draught refused: ${shop.refused}; Auto Shot ${shop.T0}s → ${shop.T1}s`);
  const dmg = await page.evaluate(() => {
    const g = window.__shadowfall;
    const e = g.enemies.byId('ghoul_road');
    let got = 0;
    g.events.on('enemyHit', (x) => { if (x.hand === 'ranged') got = x.damage; });
    const hit = (ammo) => { g.combat.arrows.push({ target: e, t: 0, ammo }); g.combat.updateArrows(0.01); return got; };
    return { rough: hit('rough_arrow'), barbed: hit('barbed_arrow') };
  });
  record('Better arrows hit harder', dmg.barbed > dmg.rough, `rough ${dmg.rough}, barbed ${dmg.barbed}`);
  const dps = await page.evaluate(() => {
    const g = window.__shadowfall;
    const per = (h) => { const [lo, hi] = g.stats.swingRangeFor(h); return +((lo + hi) / 2 / g.stats.attackCooldownFor(h)).toFixed(1); };
    return { sword: per('main'), bow: per('ranged'), ghoul: g.enemies.byId('ghoul_road').maxHealth };
  });
  record("A Warden's bow is for pulling: well under half the sword's damage a second (Agility, not Strength, powers it)", dps.bow < dps.sword * 0.5, `sword ${dps.sword}/s, bow ${dps.bow}/s (ghoul health ${dps.ghoul})`);

  // bow abilities: Quick Shot (instant) and Venom Arrow (instant poison)
  const onBar = await page.evaluate(() => ['quickShot', 'venomArrow'].map((a) => window.__shadowfall.actionBar.slots.indexOf(a)));
  record('Equipping a bow puts Quick Shot and Venom Arrow on the bar', onBar.every((i) => i >= 0), `slots ${onBar.join(', ')}`);
  const shot = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.targeting.stopAttack();
    const p = g.player.position;
    const e = g.enemies.byId('ghoul_road');
    e.position.set(p.x, 0, p.z - 15);
    Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0));
    g.resources.add?.('mana', 1000);
    g.__bowHits = [];
    g.events.on('enemyHit', (x) => { if (!x.hand && x.damage > 0) g.__bowHits.push({ t: +g.time.toFixed(3), kind: x.kind, n: x.damage }); });
    const arrows = g.inventory.count('rough_arrow');
    g.player.cooldowns.ranged = 1.5;
    const ok = g.spells.tryCast('quickShot');
    return { ok, t0: +g.time.toFixed(3), used: arrows - g.inventory.count('rough_arrow'), ranged: g.player.cooldowns.ranged, cd: g.player.cooldowns.quickShot };
  });
  await sim(page, 0.7);
  const qs = await page.evaluate(() => window.__shadowfall.__bowHits.slice());
  record('Quick Shot: an instant arrow at range that uses one arrow, hits on arrival and leaves Auto Shot alone', shot.ok && shot.used === 1 && shot.ranged === 1.5 && shot.cd === 6 && qs.length === 1 && qs[0].t - shot.t0 > 0.2, `${JSON.stringify(shot)}; hits ${JSON.stringify(qs)}`);
  const venom = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.targeting.stopAttack();
    g.player.cooldowns.gcd = 0;
    g.__bowHits = [];
    const ok = g.spells.tryCast('venomArrow');
    g.targeting.stopAttack();
    return { ok, t0: +g.time.toFixed(3) };
  });
  await sim(page, 16);
  const ticks = await page.evaluate(() => ({ hits: window.__shadowfall.__bowHits.slice(), dots: window.__shadowfall.spells.dots.length }));
  record('Venom Arrow: an instant poisoned arrow, 5 nature ticks over 15 seconds', venom.ok && ticks.hits.length === 5 && ticks.hits.every((h) => h.kind === 'spell') && ticks.dots === 0, `ticks at ${ticks.hits.map((h) => (h.t - venom.t0).toFixed(1)).join(', ')} for ${ticks.hits.map((h) => h.n).join(', ')}`);
  const noArrows = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.removeAll('rough_arrow');
    g.inventory.removeAll('barbed_arrow');
    Object.keys(g.player.cooldowns).forEach((k) => (g.player.cooldowns[k] = 0));
    return g.spells.tryCast('quickShot');
  });
  record('Bow abilities need arrows', noArrows === false, `cast with no arrows: ${noArrows}`);

  record('No script errors (WoW combat)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function titleAndCharacters(browser) {
  current = 'Title screen and characters';
  const reopen = async (page) => {
    await page.reload();
    await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden);
  };
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  let { page, errors } = await openGame(ctx);
  const first = await page.evaluate(() => ({
    cont: !document.getElementById('continue-btn').hidden,
    chars: !document.getElementById('chars-btn').hidden,
    build: document.getElementById('title-build').textContent,
  }));
  record('A fresh browser offers New character only', !first.cont && !first.chars && /Alpha/.test(first.build), JSON.stringify(first));

  await page.click('#new-btn');
  const create = await page.evaluate(() => ({
    view: !document.getElementById('title-create').hidden,
    name: document.getElementById('char-name').value,
    classes: [...document.querySelectorAll('.class-card')].map((c) => c.textContent.replace(/\s+/g, ' ').trim()),
    locked: document.querySelectorAll('.class-card.locked').length,
  }));
  record('Create screen: a random name, Warden playable, other classes shown as coming later', create.view && /^[A-Z][a-z]+ [A-Z][a-z]+$/.test(create.name) && create.locked === 2 && /Warden/.test(create.classes[0]), `${create.name}; ${create.classes.join(' / ')}`);

  const bad = [];
  for (const n of ['', 'x', 'R2D2', 'a very long name indeed']) {
    await page.fill('#char-name', n);
    await page.click('#create-confirm');
    bad.push(await page.textContent('#create-error'));
  }
  const stillTitle = await page.evaluate(() => !window.__shadowfall.started);
  record('Bad names are refused with a reason', stillTitle && bad.every((t) => t.length > 5), bad.join(' | '));

  // typing a game key into the name field must not move or open anything
  await page.fill('#char-name', '');
  await page.click('#char-name');
  await page.keyboard.type('mara bcm');
  const typed = await page.inputValue('#char-name');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => window.__shadowfall.started);
  const inWorld = await page.evaluate(() => ({ label: document.getElementById('char-name-label').textContent, key: window.__shadowfall.save.key, bags: !document.getElementById('bags-window').hidden }));
  record('Typing a name and pressing Enter creates the character and enters the world', typed === 'mara bcm' && inWorld.label === 'Mara Bcm' && inWorld.key === 'shadowfall.save' && !inWorld.bags, `typed "${typed}", HUD shows ${inWorld.label}, saves to ${inWorld.key}`);

  await page.evaluate(() => {
    const g = window.__shadowfall;
    g.player.placeAt(-2, 20);
    g.progression.apply({ level: 3, xp: 0 });
    g.manualSave();
  });
  await reopen(page);
  const back = await page.evaluate(() => ({ cont: document.getElementById('continue-who').textContent, chars: !document.getElementById('chars-btn').hidden }));
  record('Continue names the last character and their level', /Mara Bcm · level 3 Warden/.test(back.cont) && back.chars, back.cont);

  // a second character, then the list
  await page.click('#new-btn');
  await page.fill('#char-name', 'Mara Bcm');
  await page.click('#create-confirm');
  const dup = await page.textContent('#create-error');
  await page.fill('#char-name', 'Osric');
  await page.click('#create-confirm');
  await page.waitForFunction(() => window.__shadowfall.started);
  const second = await page.evaluate(() => ({ key: window.__shadowfall.save.key, lvl: window.__shadowfall.progression.level }));
  record('Names are unique; a second character gets its own save and starts fresh', /already/.test(dup) && second.key !== 'shadowfall.save' && second.lvl === 1, `"${dup}", ${second.key}, level ${second.lvl}`);
  await page.evaluate(() => window.__shadowfall.manualSave());

  // log out goes to the select screen
  await page.evaluate(() => document.getElementById('btn-logout').click());
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden && !document.getElementById('title-select').hidden);
  const sel = await page.evaluate(() => ({
    cards: [...document.querySelectorAll('.char-card .cc-name')].map((c) => c.textContent),
    name: document.getElementById('sel-name').textContent,
    showcase: document.getElementById('title-screen').classList.contains('showcase'),
  }));
  record('Logging out returns to character select, latest character first', sel.cards.join() === 'Osric,Mara Bcm' && sel.name === 'Osric' && sel.showcase, JSON.stringify(sel));

  // keyboard: down to Mara, Enter plays her where she was
  await page.keyboard.press('ArrowDown');
  await page.waitForFunction(() => document.getElementById('sel-name').textContent === 'Mara Bcm', null, { timeout: 5000 }).catch(() => {});
  const picked = await page.textContent('#sel-name');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => window.__shadowfall.started);
  const mara = await page.evaluate(() => ({ lvl: window.__shadowfall.progression.level, x: window.__shadowfall.player.position.x, z: window.__shadowfall.player.position.z }));
  record('Arrow keys and Enter pick a character and resume their save', picked === 'Mara Bcm' && mara.lvl === 3 && Math.abs(mara.x + 2) < 0.01 && Math.abs(mara.z - 20) < 0.01, `picked ${picked}: level ${mara.lvl} at (${mara.x}, ${mara.z})`);

  // delete Osric (with the confirm step)
  await page.evaluate(() => document.getElementById('btn-logout').click());
  await page.waitForFunction(() => window.__shadowfall && document.getElementById('loading').hidden && !document.getElementById('title-select').hidden);
  await page.click('.char-card:has-text("Osric")');
  await page.click('#delete-btn');
  const asked = await page.isVisible('#delete-yes');
  await page.click('#delete-yes');
  const after = await page.evaluate(() => ({
    cards: [...document.querySelectorAll('.char-card .cc-name')].map((c) => c.textContent),
    keys: Object.keys(localStorage).filter((k) => k.startsWith('shadowfall.save')).sort(),
  }));
  record('Delete asks first, then removes the character and their save', asked && after.cards.join() === 'Mara Bcm' && after.keys.join() === 'shadowfall.save', JSON.stringify(after));
  await page.close();

  // a save from before the roster becomes a character
  ({ page, errors: errors } = await openGame(ctx));
  const legacy = await page.evaluate(() => {
    const save = localStorage.getItem('shadowfall.save');
    localStorage.clear();
    localStorage.setItem('shadowfall.save', save);
    return !!save;
  });
  await reopen(page);
  const adopted = await page.evaluate(() => document.getElementById('continue-who').textContent);
  record('A save from before characters existed shows up as a character', legacy && /^Warden · level 3/.test(adopted), adopted);
  record('No script errors (title and characters)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

async function playtest3(browser) {
  current = 'Playtest batch 3';
  const { ctx, page, errors } = await freshGame(browser);
  await begin(page);
  await pauseLoop(page);
  await setup(page, { x: 0, z: 0, keep: ['ghoul_road'] });
  await placeEnemy(page, 'ghoul_road', 0, -4, { frozen: true });
  const heads = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.targeting.select(g.enemies.byId('ghoul_road'));
    g.events.emit('damageNumber', { target: g.player, amount: 7, kind: 'taken' });
    g.events.emit('damageNumber', { target: g.enemies.byId('ghoul_road'), amount: 5, kind: 'dealt' });
    return true;
  });
  await sim(page, 0.1);
  const ui = await page.evaluate(() => {
    const g = window.__shadowfall;
    const hp = [...document.querySelectorAll('.ebar.targeted .ehp')].map((e) => e.textContent);
    const taken = [...document.querySelectorAll('#damage-numbers .dmg.taken')].map((e) => e.textContent);
    const dealt = [...document.querySelectorAll('#damage-numbers .dmg.dealt')].map((e) => e.textContent);
    const name = [...document.querySelectorAll('.wlabel.player')].filter((e) => !e.hidden).map((e) => e.textContent);
    g.settings.set('playerName', false);
    return { hp, taken, dealt, name, who: g.character?.name };
  });
  await sim(page, 0.05);
  const off = await page.evaluate(() => { const n = [...document.querySelectorAll('.wlabel.player')].filter((e) => !e.hidden).length; window.__shadowfall.settings.set('playerName', true); return n; });
  record('The selected enemy shows its health in numbers on its bar', ui.hp.length === 1 && /^\d+ \/ \d+$/.test(ui.hp[0]), JSON.stringify(ui.hp));
  record('Damage you take shows with a minus sign; damage you deal does not', ui.taken.includes('-7') && ui.dealt.includes('5'), `taken ${ui.taken}, dealt ${ui.dealt}`);
  record('Your name shows over your character, and Settings turns it off', ui.name.length === 1 && ui.name[0] === ui.who && off === 0, `${JSON.stringify(ui.name)} (character ${ui.who}); with the setting off: ${off}`);
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'names-and-health.png') });

  // a fishing hook cursor over the bob
  await setup(page, { x: -16.8, z: -14 });
  const hook = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.skills.ranks.set('fishing', 1);
    g.inventory.addItem('fishing_rod', 1, { quiet: true });
    g.player.facing = -Math.PI / 2;
    return g.fishing.cast({ x: -22, z: -14 });
  });
  await sim(page, 1);
  const cur = await page.evaluate(() => {
    const g = window.__shadowfall;
    const r = g.renderer.domElement.getBoundingClientRect();
    const v = g.fishing.bobPosition.clone().project(g.camera);
    Object.assign(g.input.mouse, { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height, onCanvas: true });
    g._cursorFor(null);
    const over = g.renderer.domElement.style.cursor;
    g.input.mouse.x += 200;
    g._cursorFor(null);
    return { over, away: g.renderer.domElement.style.cursor };
  });
  record('Hovering over the fishing bob shows a fishing hook cursor', hook && /7 11/.test(cur.over) && !/7 11/.test(cur.away), `over the bob: ${cur.over.slice(-12)}; away: "${cur.away.slice(-12)}"`);
  await page.evaluate(() => window.__shadowfall.fishing.stop());

  // signposts: hover for where they point, E to read them
  await setup(page, { x: -4.6, z: 56 });
  await sim(page, 0.2);
  const sign = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.interaction.update();
    const prompt = g.interaction.current?.prompt;
    g.interaction.interact();
    const card = document.getElementById('signpost-card');
    const r = g.renderer.domElement.getBoundingClientRect();
    const v = g.player.position.clone().set(-4.6, g.player.position.y + 1.5, 54).project(g.camera);
    Object.assign(g.input.mouse, { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height, onCanvas: true });
    const pick = g._pickUnderCursor();
    g.hud.items.worldTip(pick);
    return { prompt, card: card && !card.hidden ? card.innerText : null, pick: pick?.kind, tip: document.getElementById('tooltip')?.innerText || '' };
  });
  await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'signpost.png') });
  await sim(page, 1.6, { held: ['KeyS'] });
  const gone = await page.evaluate(() => document.getElementById('signpost-card').hidden);
  record('Signposts by the road: hovering shows where each arm points, and E reads it on screen until you walk on', sign.prompt === 'Read the signpost' && /Brackenford/.test(sign.card || '') && /Stillwater Mere/.test(sign.card || '') && sign.pick === 'sign' && /Signpost/.test(sign.tip) && gone, `prompt "${sign.prompt}"; card: ${(sign.card || '').replace(/\n/g, ' | ')}; hover: ${sign.pick}`);

  // talking to townsfolk: each kind of choice marked, training in its own
  // window, Back from the shop and the trainer to the conversation
  await setup(page, { x: 8, z: 70 });
  const talk = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.inventory.addCoins(500);
    g.npcs.talk(g.npcs.byId('hester'));
    const heads = [...document.querySelectorAll('#dlg-options .dlg-head')].map((e) => e.textContent);
    const kinds = [...document.querySelectorAll('#dlg-options .dlg-option')].map((e) => e.className.replace('dlg-option ', ''));
    g.dialogue.choose('train');
    const trainOpen = !document.getElementById('trainer-window').hidden && document.getElementById('dialogue-window').hidden;
    const rows = [...document.querySelectorAll('#train-list .train-row')].map((e) => e.querySelector('.train-name').textContent + ':' + e.className.split(' ').pop());
    document.querySelector('#train-list [data-option="train:cooking"]').click();
    const learned = g.skills.has('cooking');
    const after = [...document.querySelectorAll('#train-list .train-row')].map((e) => e.className.split(' ').pop());
    document.getElementById('train-back').click();
    const backToTalk = !document.getElementById('dialogue-window').hidden && document.getElementById('trainer-window').hidden;
    g.dialogue.close();
    g.npcs.talk(g.npcs.byId('tam'));
    g.dialogue.choose('shop');
    const shopBack = !document.getElementById('shop-back').hidden;
    document.getElementById('shop-back').click();
    const fromShop = !g.merchant.current && g.dialogue.isOpen && g.dialogue.npc.id === 'tam';
    g.dialogue.close();
    return { heads, kinds, trainOpen, rows, learned, after, backToTalk, shopBack, fromShop };
  });
  record('Talking to someone: quests, things to ask and services each have a heading and their own badge', talk.heads.includes('Services') && talk.kinds.includes('train') && talk.kinds.includes('home') && talk.kinds.includes('bye'), `headings ${talk.heads.join(', ')}; badges ${talk.kinds.join(', ')}`);
  record('Train opens a trainer window like the shop: each skill and recipe, its cost and Learn', talk.trainOpen && talk.rows.length >= 4 && talk.learned && talk.after.includes('known'), talk.rows.join(', '));
  record('Back takes you from the trainer window or the shop to the conversation', talk.backToTalk && talk.shopBack && talk.fromShop, JSON.stringify({ trainer: talk.backToTalk, shop: talk.fromShop }));
  await page.evaluate(() => { const g = window.__shadowfall; g.npcs.talk(g.npcs.byId('hester')); g.dialogue.choose('train'); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'trainer-window.png') });
  await page.evaluate(() => { const g = window.__shadowfall; g.dialogue.back(); });
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'npc-talk.png') });
  const prof = await page.evaluate(() => {
    const g = window.__shadowfall;
    g.dialogue.close();
    g.skills.learn('fishing');
    g.hud.items.show('skills');
    const rows = [...document.querySelectorAll('#skills-list .prof-row')].map((e) => e.dataset.skill);
    const drag = [...document.querySelectorAll('#skills-list .islot')].map((e) => e.dataset.loc);
    g.hud.items.show('spellbook');
    const book = [...document.querySelectorAll('#spellbook-list .islot')].map((e) => e.dataset.loc);
    return { rows, drag, book };
  });
  record('Professions (U) has its own window with ranks and abilities; the spellbook keeps to spells', prof.rows.includes('cooking') && prof.drag.includes('k:fish') && prof.drag.includes('k:cook') && !prof.book.includes('k:fish') && !prof.book.includes('k:cook') && prof.book.includes('k:lunge'), `professions ${prof.rows.join(', ')} (${prof.drag.join(', ')}); spellbook ${prof.book.join(', ')}`);
  await page.evaluate(() => window.__shadowfall.hud.items.show('skills'));
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'professions.png') });
  await page.evaluate(() => window.__shadowfall.hud.items.closeAll());

  // the bottom right: menus, then bags, then money in the corner, clear of the spell bar
  const dock = async () => page.evaluate(() => {
    const r = (sel) => document.querySelector(sel).getBoundingClientRect();
    const micro = r('#micro-bar'), bags = r('#bag-dock'), coins = r('#right-dock .coins'), bar = r('#bottom-bar');
    return { inline: Math.abs(micro.bottom - bags.bottom) < 2 && micro.right <= bags.left && bags.right <= coins.left, corner: window.innerWidth - coins.right < 20 && window.innerHeight - coins.bottom < 20, clear: bar.right <= micro.left, bar: [Math.round(bar.left), Math.round(bar.right)], micro: Math.round(micro.left), w: window.innerWidth };
  });
  const d1 = await dock();
  await page.setViewportSize({ width: 1920, height: 1080 });
  await sim(page, 0.05);
  const d2 = await dock();
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'hud-1080p.png') });
  await page.setViewportSize({ width: 1280, height: 720 });
  await sim(page, 0.05);
  await page.screenshot({ path: path.join(HERE, 'screenshots', 'hud-720p.png') });
  record('Menu buttons sit in a row with the bag slots, money in the bottom-right corner, clear of the spell bar (720p and 1080p)', d1.inline && d1.corner && d1.clear && d2.inline && d2.corner && d2.clear, JSON.stringify([d1, d2]));

  // doors and signs: a look at the town
  for (const [x, z, name] of [[-1, 72, 'inn-west'], [-4, 80, 'town-south']]) {
    await setup(page, { x, z });
    await sim(page, 0.3);
    await page.evaluate(() => { const g = window.__shadowfall; g.renderer.render(g.scene, g.camera); });
    await page.screenshot({ path: path.join(HERE, 'screenshots', `${name}.png`) });
  }

  record('No script errors (playtest batch 3)', errors.length === 0, errors.join(' | '));
  await ctx.close();
}

const SECTIONS = { titleAndCharacters, launchAndMovement, combat, exploration, progression, death, persistence, quality, abilities, telegraphs, gamepad, bagsAndGround, spellBar, controls, statsAndDamage, itemDatabase, forge, questsAndMap, clickTargeting, spells, lootRarity, ghostAndCamp, torchAndFishing, targetAndUi, combatFixes, economy, worldBatch, utilityBar, uiLayout, resources, swingTimer, dualWield, townAndCooking, wowCombat, playtest3, gearRolls, blackwood, atmosphere };
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
