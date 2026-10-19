// Captures reference screenshots of build 2 features into tests/screens/.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { launch, openGame } from './browser.mjs';

const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'screens');
fs.mkdirSync(OUT, { recursive: true });
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const { page, errors } = await openGame(ctx);
await page.click('#new-btn');
await page.waitForFunction(() => window.__shadowfall.started);
await page.waitForTimeout(800);
const shot = (name) => page.screenshot({ path: path.join(OUT, name + '.png') });
await shot('01-road-fog');

// bags + character open, with satchel and helm in the bags
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.inventory.addItem('travellers_satchel', 1, { quiet: true });
  g.inventory.addItem('watch_helm', 1, { quiet: true });
  g.inventory.addItem('grave_iron', 2, { quiet: true });
  g.inventory.addItem('watchmans_edge', 1, { quiet: true });
  g.inventory.use('b:0:1');
  g.hud.togglePanel('bags');
  g.hud.togglePanel('character');
  g.hud.togglePanel('spellbook');
  g.actionBar.move(0, 2);
});
await page.waitForTimeout(400);
const slot = await page.$('#bags-window .islot[data-loc="b:0:2"]');
if (slot) await slot.hover();
await page.waitForTimeout(300);
await shot('02-bags-and-character');
await page.evaluate(() => window.__shadowfall.hud.closeModal());

// brute winding up Grave Slam
await page.evaluate(() => {
  const g = window.__shadowfall;
  const e = g.enemies.list.find((x) => x.cfg.elite);
  g.player.placeAt(e.position.x, e.position.z + 3.0);
  g._snapCamera();
  e.state = 'chase';
  e.specialTimer = 0;
  e.engaged = 5;
});
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(40);
  const casting = await page.evaluate(() => window.__shadowfall.enemies.list.some((e) => e.casting && e.casting.kind === 'special'));
  if (casting) break;
}
await page.waitForTimeout(500);
await shot('03-grave-slam-telegraph');

// watch post braziers in the fog
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.enemies.list.forEach((e) => { e.position.set(-30, 0, 40); e.home.copy(e.position); e.state = 'idle'; });
  g.player.placeAt(23.5, -34);
  g.player.health = g.player.maxHealth;
  g._snapCamera();
});
await page.waitForTimeout(600);
await shot('04-watch-post-braziers');

// after a fight: two bodies to loot, a third ghoul hard-locked, Brace up
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.enemies.list.forEach((e) => { e.position.set(-30, 0, 40); e.home.copy(e.position); e.state = 'idle'; });
  g.player.placeAt(0, 9.4);
  g.player.facing = Math.PI;
  for (const [id, x, z] of [['ghoul_road', -1.2, 8], ['ghoul_cart', 1.4, 8.2]]) {
    const e = g.enemies.byId(id);
    e.position.set(x, 0, z);
    e.hurt(999);
    g.combat.onEnemyDefeated(e);
  }
  const live = g.enemies.byId('ghoul_graves');
  live.position.set(0.5, 0, 5.2);
  live.home.copy(live.position);
  live.cfg = { ...live.cfg, speed: 0, detection: 0 };
  g.targeting.select(live);
  g.spells.tryCast('brace');
  g._snapCamera();
});
await page.waitForTimeout(2500);
await shot('05-lock-and-loot');

// damage numbers mid-fight, with the target frame and character stats
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.enemies.list.forEach((e) => { if (e.alive) { e.position.set(-30, 0, 40); e.home.copy(e.position); e.state = 'idle'; } });
  g.targeting.clear();
  g.player.placeAt(-6, 24);
  g.player.facing = Math.PI;
  const e = g.enemies.list.find((x) => x.alive && x.type === 'brute');
  e.position.set(-6, 0, 22.2);
  e.home.copy(e.position);
  e.cfg = { ...e.cfg, speed: 0, detection: 0 };
  const seq = [0.5, 0.99, 0.9, 0.01, 0.3, 0.99];
  g.random = () => (seq.length ? seq.shift() : 0.5);
  g.combat.resolvePlayerStrike(null);
  g.hud.numbers.items.forEach((n) => (n.t = 0.35));
  g.combat.resolvePlayerStrike(null);
  g.hud.numbers.items.at(-1).t = 0.15;
  g.combat.resolveEnemyStrike(e);
  g.progression.addXp(100);
  g.hud.togglePanel('character');
  g._snapCamera();
});
await page.waitForTimeout(250);
await shot('06-damage-numbers');
console.log(errors.length ? errors.join('\n') : 'no errors');
await browser.close();
