// Bundles src/main.js into dist/shadowfall.js and stamps the build (package
// version, commit, date) into the bundle as __BUILD__, so the title screen and
// HUD show exactly which build is running. `node scripts/build.mjs --watch`
// is the dev build: unminified and rebuilt on save.
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import * as esbuild from 'esbuild';

const watch = process.argv.includes('--watch');
const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

const git = (cmd) => { try { return execSync(`git ${cmd}`, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { return ''; } };
// In GitHub Actions the commit is GITHUB_SHA; locally it is HEAD, marked '+'
// when src or data has uncommitted edits (the bundle is then newer than HEAD).
let commit = (process.env.GITHUB_SHA || git('rev-parse HEAD')).slice(0, 7) || 'unknown';
if (!process.env.GITHUB_SHA && git('status --porcelain -- src data')) commit += '+';

const build = { version: pkg.version, commit, date: new Date().toISOString().slice(0, 16).replace('T', ' ') + ' UTC' };

const options = {
  entryPoints: ['src/main.js'],
  bundle: true,
  format: 'iife',
  target: 'chrome110',
  loader: { '.glb': 'binary' },
  minify: !watch,
  sourcemap: true,
  outfile: 'dist/shadowfall.js',
  define: { __BUILD__: JSON.stringify(build) },
  logLevel: 'info',
};

if (watch) {
  await (await esbuild.context(options)).watch();
} else {
  await esbuild.build(options);
  console.log(`build v${build.version} ${build.commit} ${build.date}`);
}
