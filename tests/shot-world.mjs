// Screenshots of nameplates, a sparkling chest and the reputation list (not a test).
import { launch, openGame } from './browser.mjs';
const dir = process.argv[2] || '.';
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const { page } = await openGame(ctx);
await page.click('#new-btn');
await page.waitForFunction(() => window.__shadowfall.started);
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.player.placeAt(-7, 8);
  g._snapCamera();
});
await page.waitForTimeout(2500);
await page.screenshot({ path: `${dir}/screens-world.png` });
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.reputation.add('road_wardens', 1400);
  g.hud.togglePanel('character');
});
await page.waitForTimeout(800);
await page.screenshot({ path: `${dir}/screens-reputation.png` });
await browser.close();
