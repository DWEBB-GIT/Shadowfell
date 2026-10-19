// Local server for the content editors in /tools. Serves the repo as static
// files and lets an editor save one data file back to /data, so you can open
// the quest editor, change quests and save without touching JSON by hand.
//
//   npm run editor      then open http://localhost:5180/tools/quest-editor/
//
// Only files that already exist in /data can be written, and a save is
// refused unless it parses as JSON. DATA_DIR overrides the folder (tests).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const DATA = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(ROOT, 'data');
const PORT = Number(process.env.PORT) || 5180;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };

const send = (res, code, body, type = 'text/plain') => {
  res.writeHead(code, { 'content-type': `${type}; charset=utf-8`, 'cache-control': 'no-store' });
  res.end(body);
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const save = url.pathname.match(/^\/api\/data\/([a-z_]+\.json)$/);
  if (save && req.method === 'PUT') {
    const file = path.join(DATA, save[1]);
    if (!fs.existsSync(file)) return send(res, 404, `no data file ${save[1]}`);
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      try {
        JSON.parse(body);
      } catch (err) {
        return send(res, 400, `not valid JSON: ${err.message}`);
      }
      fs.writeFileSync(file, body);
      console.log(`saved ${save[1]}`);
      send(res, 200, 'saved');
    });
    return;
  }
  if (url.pathname === '/api/data' && req.method === 'GET') {
    const out = {};
    for (const f of fs.readdirSync(DATA).filter((f) => f.endsWith('.json'))) out[f] = fs.readFileSync(path.join(DATA, f), 'utf8');
    return send(res, 200, JSON.stringify(out), 'application/json');
  }
  if (req.method !== 'GET') return send(res, 405, 'method not allowed');
  let rel = decodeURIComponent(url.pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(ROOT, rel);
  if (!file.startsWith(ROOT + path.sep) || rel.includes('/.git') || rel.includes('/node_modules')) return send(res, 403, 'forbidden');
  fs.readFile(file, (err, buf) => {
    if (err) return send(res, 404, 'not found');
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
    res.end(buf);
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Shadowfell editors running. Quest editor: http://localhost:${PORT}/tools/quest-editor/`);
  console.log(`Saving to ${DATA}. Press Ctrl+C to stop.`);
});
