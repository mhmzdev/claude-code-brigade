#!/usr/bin/env node
// The Window's server. Serves the page, streams the kitchen's state over SSE,
// and runs either the demo scenario or the live sources.
//
//   node server/index.js [--demo [--stations N]] [--port 4747] [--root <repo>]

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createState } from './state.js';
import { runDemo } from './demo.js';
import { startLive } from './live/index.js';
import { createControl } from './control.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const webDir = path.join(here, '..', 'web');

const args = process.argv.slice(2);
const flag = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const DEMO = args.includes('--demo');
const PORT = Number(flag('--port', process.env.PORT || 4747));
const ROOT = path.resolve(flag('--root', process.cwd()));

const store = createState({ repo: path.basename(ROOT), root: ROOT });
const control = createControl(store, { demo: DEMO });
// Re-described every few seconds: tmux installed mid-service changes what the panel says.
const describe = () => control.describe().then((d) => { if (d.control !== store.state.kitchen.control) store.setKitchen(d); });
describe(); setInterval(describe, 5000).unref();

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.map': 'application/json', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png' };

function serveFile(res, file) {
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
    res.end(data);
  });
}

const clients = new Set();
function send(res, type, payload) {
  res.write(`event: ${type}\ndata: ${JSON.stringify(payload)}\n\n`);
}
store.subscribe((ev) => {
  const { type, ...payload } = ev;
  for (const res of clients) send(res, type, type === 'snapshot' ? payload.state : payload);
});
// Keep SSE connections alive through proxies and sleepy laptops.
setInterval(() => { for (const res of clients) res.write(': ping\n\n'); }, 25000).unref();

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
    res.write('retry: 1500\n\n');
    send(res, 'snapshot', store.snapshot());
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }
  if (url.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  if (url.pathname === '/api/control' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => { body += c; if (body.length > 8192) req.destroy(); });
    req.on('end', async () => {
      let out;
      try { out = await control.handle(JSON.parse(body)); } catch (e) { out = { ok: false, via: 'none', reason: String(e.message || e) }; }
      res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(out));
    });
    return;
  }
  if (url.pathname === '/api/state') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(store.snapshot()));
    return;
  }
  const rel = url.pathname === '/' ? 'index.html' : url.pathname === '/ledger' ? 'ledger.html' : url.pathname.slice(1);
  const file = path.normalize(path.join(webDir, rel));
  if (!file.startsWith(webDir)) { res.writeHead(403); res.end(); return; }
  serveFile(res, file);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`The Window  http://localhost:${PORT}  (${DEMO ? 'demo service' : 'live: ' + ROOT})`);
  if (DEMO) runDemo(store, { stations: Number(flag('--stations', 2)) }); else startLive(store, ROOT, control);
});
