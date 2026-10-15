// Screenshot of the mana bar, Resolve gauge, a dimmed slot and a cost tooltip (not a test).
import { launch, openGame } from './browser.mjs';
const dir = process.argv[2] || '.';
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const { page } = await openGame(ctx);
await page.click('#new-btn');
await page.waitForFunction(() => window.__shadowfall.started);
await page.evaluate(() => {
  const g = window.__shadowfall;
  const e = g.enemies.byId('ghoul_road');
  g.player.placeAt(e.position.x, e.position.z + 1.6);
  e.health = 999;
  g.targeting.engage(e);
  g.resources.gauge = 20;
  g.resources.mana = 74;
});
await page.waitForTimeout(800);
await page.hover('.aslot[data-ability="shieldBreak"]');
await page.waitForTimeout(400);
await page.screenshot({ path: `${dir}/screens-resources.png` });
await browser.close();
