// Screenshot of the spell bar with the utility slots in use (not a test).
import { launch, openGame } from './browser.mjs';
const out = process.argv[2] || 'bar.png';
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const { page } = await openGame(ctx);
await page.click('#new-btn');
await page.waitForFunction(() => window.__shadowfall.started);
await page.evaluate(() => {
  const g = window.__shadowfall;
  g.skills.ranks.set('fishing', 1);
  g.skills.ranks.set('camping', 1);
  g.actionBar.place('fish', 6);
  g.actionBar.place('setCamp', 8);
  g.inventory.addItem('torch', 1);
  g.inventory.addItem('lockpicks', 1);
  g.actionBar.placeItem('torch', 7);
  g.actionBar.placeItem('lockpicks', 9);
  g.inventory.useFromBar('torch');
});
await page.waitForTimeout(1500);
await page.screenshot({ path: out, clip: { x: 0, y: 600, width: 1280, height: 120 } });
await browser.close();
