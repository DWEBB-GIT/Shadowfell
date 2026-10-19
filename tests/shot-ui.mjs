// Screenshots of the reworked HUD: swing timer, centred bar, right dock, Settings with key bindings (not a test).
import { launch, openGame } from './browser.mjs';
const dir = process.argv[2] || '.';
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const { page } = await openGame(ctx);
await page.click('#new-btn');
await page.waitForFunction(() => window.__shadowfall.started);
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.inventory.coins = 247;
  const e = g.enemies.byId('ghoul_road');
  g.player.placeAt(e.position.x, e.position.z + 1.6);
  e.health = 999;
  g.targeting.engage(e);
});
await page.waitForTimeout(1200);
await page.screenshot({ path: `${dir}/screens-swing.png` });
await page.evaluate(() => window.__shadowfall.hud.togglePanel('settings'));
await page.waitForTimeout(500);
await page.screenshot({ path: `${dir}/screens-settings.png` });
await browser.close();
