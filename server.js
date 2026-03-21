const http = require('http');
const { WebSocketServer } = require('ws');
const pty = require('node-pty');
const fs = require('fs');
const path = require('path');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

const server = http.createServer((req, res) => {
  if (req.url === '/vendor/xterm.css') {
    try {
      res.writeHead(200, { 'Content-Type': 'text/css' });
      res.end(fs.readFileSync(path.join(__dirname, 'node_modules/@xterm/xterm/css/xterm.css'), 'utf-8'));
    } catch { res.writeHead(404); res.end(); }
    return;
  }

  const filePath = path.join(__dirname, 'public', req.url === '/' ? 'index.html' : req.url);
  try {
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(fs.readFileSync(filePath));
  } catch { res.writeHead(404); res.end('Not found'); }
});

const wss = new WebSocketServer({ server });
const terminals = new Map();
let nextId = 1;

wss.on('connection', (ws) => {
  const owned = new Set();

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }

    switch (msg.type) {
      case 'create': {
        const id = nextId++;
        const term = pty.spawn(process.env.SHELL || '/bin/zsh', [], {
          name: 'xterm-256color',
          cols: msg.cols || 80,
          rows: msg.rows || 24,
          cwd: msg.cwd || process.env.HOME,
          env: { ...process.env, TERM: 'xterm-256color', COLORTERM: 'truecolor' },
        });

        terminals.set(id, term);
        owned.add(id);

        term.onData((data) => {
          if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'output', id, data }));
        });

        term.onExit(({ exitCode }) => {
          terminals.delete(id);
          owned.delete(id);
          if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'exit', id, exitCode }));
        });

        ws.send(JSON.stringify({ type: 'created', id }));

        if (msg.command) {
          setTimeout(() => { if (terminals.has(id)) term.write(msg.command + '\r'); }, 80);
        }
        break;
      }
      case 'input': {
        const t = terminals.get(msg.id);
        if (t) t.write(msg.data);
        break;
      }
      case 'resize': {
        const t = terminals.get(msg.id);
        if (t && msg.cols > 0 && msg.rows > 0) t.resize(msg.cols, msg.rows);
        break;
      }
      case 'kill': {
        const t = terminals.get(msg.id);
        if (t) { t.kill(); terminals.delete(msg.id); owned.delete(msg.id); }
        break;
      }
    }
  });

  ws.on('close', () => {
    for (const id of owned) { const t = terminals.get(id); if (t) t.kill(); terminals.delete(id); }
  });
});

const PORT = parseInt(process.env.PORT) || 7681;
server.listen(PORT, () => {
  console.log(`\n  flock · http://localhost:${PORT}\n`);
});
