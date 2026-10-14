// Shared helper: launch Chromium with software WebGL and open the game from file://
import { chromium } from 'playwright-core';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const GAME_URL = 'file://' + path.join(ROOT, 'index.html');

export async function launch() {
  const executablePath = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
  const browser = await chromium.launch({
    executablePath,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'],
  });
  return browser;
}

export async function openGame(context) {
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto(GAME_URL);
  await page.waitForFunction(() => window.__shadowfall && window.__shadowfall.hud && document.getElementById('loading').hidden, null, { timeout: 60000 });
  return { page, errors };
}
