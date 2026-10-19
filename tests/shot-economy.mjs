// One screenshot of the money, durability and slot changes (not a test).
import { launch, openGame } from './browser.mjs';
const out = process.argv[2] || 'economy.png';
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const { page } = await openGame(ctx);
await page.click('#new-btn');
await page.waitForFunction(() => window.__shadowfall.started);
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.inventory.coins = 247;
  g.inventory.equipment.chest.dur = 0;
  g.inventory.equipment.mainHand.dur = 20;
  g.inventory.addItem('watchmans_edge', 1);
  const loc = g.inventory.bagLocations().find((l) => g.inventory.get(l)?.id === 'watchmans_edge');
  g.loot.dropFromInventory(loc);
  g.inventory.addItem('hob_boots', 1);
  g.hud.togglePanel('character');
  g.hud.togglePanel('bags');
});
await page.waitForTimeout(1500);
await page.screenshot({ path: out });
await browser.close();
