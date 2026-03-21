import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';

const THEME = {
  background: '#FFFFFF',
  foreground: '#1A1917',
  cursor: '#E2603C',
  cursorAccent: '#FFFFFF',
  selectionBackground: 'rgba(59, 130, 246, 0.14)',
  selectionForeground: undefined,
  black: '#1A1917',
  red: '#D93025',
  green: '#188038',
  yellow: '#B06000',
  blue: '#1967D2',
  magenta: '#9334E6',
  cyan: '#007B83',
  white: '#6E6B65',
  brightBlack: '#6E6B65',
  brightRed: '#E94235',
  brightGreen: '#34A853',
  brightYellow: '#EA8600',
  brightBlue: '#4285F4',
  brightMagenta: '#AF5CF7',
  brightCyan: '#24969B',
  brightWhite: '#A8A49E',
};

class Flock {
  constructor() {
    this.panes = new Map();
    this.pending = [];
    this.activePaneId = null;
    this.order = [];
    this.maximized = false;
    this.ws = null;

    this.grid = document.getElementById('grid');
    this.countNum = document.querySelector('.count-num');
    this.countLabel = document.querySelector('.count-label');
    this.countDot = document.querySelector('.count-dot');

    this.showEmpty();
    this.connect();
    this.bindUI();
    this.bindKeys();
    this.bindResize();
  }

  // ─── Connection ───

  connect() {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    this.ws = new WebSocket(`${proto}//${location.host}`);
    this.ws.onopen = () => this.addPane('claude');
    this.ws.onmessage = (e) => this.handle(JSON.parse(e.data));
    this.ws.onclose = () => setTimeout(() => this.connect(), 2000);
  }

  handle(msg) {
    switch (msg.type) {
      case 'created': {
        const pane = this.pending.shift();
        if (!pane) return;
        pane.sid = msg.id;
        this.panes.set(msg.id, pane);
        this.order.push(msg.id);
        this.hideEmpty();
        this.setActive(msg.id);
        this.layout();
        this.updateCount();
        requestAnimationFrame(() => {
          requestAnimationFrame(() => pane.fit.fit());
        });
        break;
      }
      case 'output': {
        const p = this.panes.get(msg.id);
        if (p) p.term.write(msg.data);
        break;
      }
      case 'exit':
        this.removePane(msg.id);
        break;
    }
  }

  // ─── Pane Management ───

  addPane(command) {
    const el = document.createElement('div');
    el.className = 'pane';

    const idx = this.order.length + this.pending.length + 1;
    const label = command || 'shell';

    el.innerHTML = `
      <div class="pane-header">
        <div class="pane-meta">
          <div class="pane-index">${idx}</div>
          <div class="pane-label">${label}</div>
        </div>
        <div class="pane-actions">
          <button class="pane-btn maximize" title="Maximize (⌘⏎)">
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><rect x="2" y="2" width="8" height="8" rx="1.5" stroke="currentColor" stroke-width="1.2"/></svg>
          </button>
          <button class="pane-btn close" title="Close (⌘W)">
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>
          </button>
        </div>
      </div>
      <div class="pane-body"></div>
    `;

    this.grid.appendChild(el);

    const body = el.querySelector('.pane-body');
    const term = new Terminal({
      fontSize: 13,
      fontFamily: "'SF Mono', 'Berkeley Mono', Menlo, Monaco, 'Cascadia Code', monospace",
      fontWeight: '450',
      fontWeightBold: '600',
      lineHeight: 1.25,
      letterSpacing: 0,
      cursorBlink: true,
      cursorStyle: 'bar',
      cursorWidth: 2,
      scrollback: 10000,
      theme: THEME,
      allowProposedApi: true,
      drawBoldTextInBrightColors: false,
    });

    term.attachCustomKeyEventHandler((e) => {
      if (e.type !== 'keydown') return true;
      if (e.metaKey) {
        const k = e.key.toLowerCase();
        if ('tw'.includes(k) || k === 'enter') return false;
        if (e.key >= '1' && e.key <= '9') return false;
        if (['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)) return false;
      }
      return true;
    });

    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(body);

    const pane = { el, term, fit, sid: null, command: label };

    el.addEventListener('mousedown', () => { if (pane.sid) this.setActive(pane.sid); });
    el.querySelector('.close').addEventListener('click', (e) => {
      e.stopPropagation();
      if (pane.sid) { this.send('kill', pane.sid); this.removePane(pane.sid); }
    });
    el.querySelector('.maximize').addEventListener('click', (e) => {
      e.stopPropagation();
      this.toggleMax();
    });

    term.onData((data) => { if (pane.sid) this.send('input', pane.sid, data); });
    term.onResize(({ cols, rows }) => {
      if (pane.sid) this.ws.send(JSON.stringify({ type: 'resize', id: pane.sid, cols, rows }));
    });

    this.pending.push(pane);
    this.ws.send(JSON.stringify({
      type: 'create',
      cols: term.cols,
      rows: term.rows,
      command: command || undefined,
    }));
  }

  send(type, id, data) {
    this.ws.send(JSON.stringify(data ? { type, id, data } : { type, id }));
  }

  removePane(id) {
    const pane = this.panes.get(id);
    if (!pane) return;
    pane.term.dispose();
    pane.el.remove();
    this.panes.delete(id);
    this.order = this.order.filter(x => x !== id);
    this.reindex();

    if (this.activePaneId === id) {
      this.activePaneId = null;
      const last = this.order[this.order.length - 1];
      if (last) this.setActive(last);
    }
    if (this.maximized && this.panes.size <= 1) this.maximized = false;
    if (this.panes.size === 0) this.showEmpty();
    this.layout();
    this.updateCount();
  }

  setActive(id) {
    if (this.activePaneId === id) return;
    const prev = this.panes.get(this.activePaneId);
    if (prev) prev.el.classList.remove('focused');

    this.activePaneId = id;
    const pane = this.panes.get(id);
    if (!pane) return;
    pane.el.classList.add('focused');
    pane.term.focus();

    if (this.maximized) {
      for (const [pid, p] of this.panes) {
        p.el.style.display = pid === id ? '' : 'none';
      }
      requestAnimationFrame(() => pane.fit.fit());
    }
  }

  reindex() {
    this.order.forEach((id, i) => {
      const p = this.panes.get(id);
      if (p) p.el.querySelector('.pane-index').textContent = i + 1;
    });
  }

  updateCount() {
    const n = this.panes.size;
    this.countNum.textContent = n;
    this.countLabel.textContent = n === 1 ? 'session' : 'sessions';
    this.countDot.classList.toggle('inactive', n === 0);
  }

  // ─── Layout ───

  layout() {
    const n = this.panes.size;
    if (n === 0) return;

    if (this.maximized) {
      this.grid.style.gridTemplateColumns = '1fr';
      this.grid.style.gridTemplateRows = '1fr';
    } else {
      const [c, r] = this.gridDims(n);
      this.grid.style.gridTemplateColumns = `repeat(${c}, 1fr)`;
      this.grid.style.gridTemplateRows = `repeat(${r}, 1fr)`;
      for (const p of this.panes.values()) p.el.style.display = '';
    }

    requestAnimationFrame(() => {
      for (const p of this.panes.values()) {
        if (p.el.style.display !== 'none') p.fit.fit();
      }
    });
  }

  gridDims(n) {
    if (n <= 1) return [1, 1];
    if (n <= 2) return [2, 1];
    if (n <= 4) return [2, 2];
    if (n <= 6) return [3, 2];
    if (n <= 9) return [3, 3];
    const c = Math.ceil(Math.sqrt(n));
    return [c, Math.ceil(n / c)];
  }

  toggleMax() {
    if (this.panes.size === 0) return;
    this.maximized = !this.maximized;

    if (this.maximized) {
      for (const [id, p] of this.panes) {
        p.el.style.display = id === this.activePaneId ? '' : 'none';
        if (id === this.activePaneId) p.el.classList.add('maximized');
      }
    } else {
      for (const p of this.panes.values()) {
        p.el.style.display = '';
        p.el.classList.remove('maximized');
      }
    }
    this.layout();
  }

  // ─── Empty State ───

  showEmpty() {
    if (document.getElementById('empty-state')) return;
    const el = document.createElement('div');
    el.id = 'empty-state';
    el.innerHTML = `
      <div class="empty-brand">flock</div>
      <div class="empty-sub">parallel claude code sessions</div>
      <div class="shortcut-grid">
        <span class="shortcut-key">⌘ T</span><span class="shortcut-desc">new claude instance</span>
        <span class="shortcut-key">⌘ ⇧ T</span><span class="shortcut-desc">new shell</span>
        <span class="shortcut-key">⌘ 1–9</span><span class="shortcut-desc">switch pane</span>
        <span class="shortcut-key">⌘ ⏎</span><span class="shortcut-desc">maximize / restore</span>
        <span class="shortcut-key">⌘ W</span><span class="shortcut-desc">close pane</span>
        <span class="shortcut-key">⌘ ←→↑↓</span><span class="shortcut-desc">navigate panes</span>
      </div>
    `;
    this.grid.appendChild(el);
  }

  hideEmpty() {
    document.getElementById('empty-state')?.remove();
  }

  // ─── Bindings ───

  bindUI() {
    document.getElementById('btn-claude').addEventListener('click', () => this.addPane('claude'));
    document.getElementById('btn-shell').addEventListener('click', () => this.addPane(null));
  }

  bindKeys() {
    document.addEventListener('keydown', (e) => {
      if (e.metaKey && !e.shiftKey && e.key === 't') { e.preventDefault(); this.addPane('claude'); return; }
      if (e.metaKey && e.shiftKey && e.key.toLowerCase() === 't') { e.preventDefault(); this.addPane(null); return; }
      if (e.metaKey && !e.shiftKey && e.key === 'w') { e.preventDefault(); if (this.activePaneId) { this.send('kill', this.activePaneId); this.removePane(this.activePaneId); } return; }
      if (e.metaKey && e.key === 'Enter') { e.preventDefault(); this.toggleMax(); return; }
      if (e.metaKey && !e.shiftKey && e.key >= '1' && e.key <= '9') {
        e.preventDefault();
        const i = parseInt(e.key) - 1;
        if (i < this.order.length) this.setActive(this.order[i]);
        return;
      }
      if (e.metaKey && ['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)) {
        e.preventDefault();
        this.navigate(e.key.replace('Arrow', '').toLowerCase());
      }
    });
  }

  navigate(dir) {
    if (!this.activePaneId || this.order.length <= 1) return;
    const cur = this.order.indexOf(this.activePaneId);
    const n = this.order.length;
    const [cols] = this.gridDims(n);
    let next = cur;
    if (dir === 'left') next = cur > 0 ? cur - 1 : n - 1;
    else if (dir === 'right') next = (cur + 1) % n;
    else if (dir === 'up') next = cur - cols >= 0 ? cur - cols : cur;
    else if (dir === 'down') next = cur + cols < n ? cur + cols : cur;
    if (next !== cur) this.setActive(this.order[next]);
  }

  bindResize() {
    let t;
    window.addEventListener('resize', () => {
      clearTimeout(t);
      t = setTimeout(() => {
        for (const p of this.panes.values()) {
          if (p.el.style.display !== 'none') p.fit.fit();
        }
      }, 80);
    });
  }
}

document.addEventListener('DOMContentLoaded', () => new Flock());
