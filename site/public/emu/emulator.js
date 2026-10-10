// TI-Nspire CX II screen for the website: draws the toolkit's paint buffers
// (core.js) on a 318×212 canvas under a document tab bar, keeps the
// calculator's proportions at any size, and turns keys, clicks and the
// on-screen keypad into calculator events.
(function () {
  'use strict';

  const W = 318;
  const H = 212;
  const RS = '\x1e';
  const US = '\x1f';

  const SCRIPT_URL = (document.currentScript && document.currentScript.src) || location.href;
  const BASE = new URL('.', SCRIPT_URL).href;
  const VERSION = new URL(SCRIPT_URL).searchParams.get('v') || '';

  const FONTS = {
    sansserif: '"Helvetica Neue", Helvetica, Arial, "Noto Sans", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", sans-serif',
    serif: 'Georgia, "Times New Roman", "Songti SC", "Noto Serif CJK SC", serif',
  };
  // TI font size → CSS pixels (same metrics as tools/screens.lua)
  function fontCss(fam, st, size) {
    const px = (Number(size) || 11) * 1.33;
    return (st && st.indexOf('i') >= 0 ? 'italic ' : '') + (st && st.indexOf('b') >= 0 ? 'bold ' : '') +
      px.toFixed(2) + 'px ' + (FONTS[fam] || FONTS.sansserif);
  }

  const measureCtx = document.createElement('canvas').getContext('2d');
  function measure(s, fam, st, size) {
    measureCtx.font = fontCss(fam, st, size);
    return measureCtx.measureText(s).width;
  }

  let shared = null;
  function loadShared() {
    if (!shared) {
      shared = (async function () {
        const q = VERSION ? '?v=' + VERSION : '';
        const get = (name) => fetch(BASE + name + q).then((r) => {
          if (!r.ok) throw new Error(name + ': HTTP ' + r.status);
          return r.text();
        });
        const [host, app] = await Promise.all([get('host.txt'), get('vce_web.txt')]);
        const factory = new window.wasmoon.LuaFactory(new URL('../vendor/glue.wasm', BASE).href);
        return { factory, sources: { host, app } };
      })();
      shared.catch(() => { shared = null; });
    }
    return shared;
  }

  function hex(c) {
    return '#' + ('000000' + (Number(c) >>> 0).toString(16)).slice(-6);
  }

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  const KEYPAD = [
    ['esc', 'esc', 'esc'], ['menu', 'menu', 'menu'], ['tab', 'tab', 'tab'],
    ['left', '◀', 'left'], ['up', '▲', 'up'], ['down', '▼', 'down'], ['right', '▶', 'right'],
    ['del', 'del', 'backspace'], ['enter', 'enter', 'enter'], ['kbd', '⌨', 'kbd'],
  ];

  class Calc {
    // opts: lang 'en' | 'bi', doc (tab name), keypad (bool), label (aria)
    constructor(root, opts) {
      this.root = root;
      this.opts = Object.assign({ lang: 'en', doc: 'vce', keypad: true }, opts || {});
      this.core = null;
      this.last = '';
      this.menuState = null;
      this.playing = 0;
      this.build();
    }

    build() {
      const r = this.root;
      r.classList.add('nspire');
      r.textContent = '';
      const screen = el('div', 'nspire-screen');
      const bar = el('div', 'nspire-bar');
      bar.append(el('span', 'nspire-tab', '1.1'), el('span', 'nspire-doc', '*' + this.opts.doc + ' ▾'),
        el('span', 'nspire-mode', 'RAD'), el('span', 'nspire-batt'));
      const canvas = el('canvas', 'nspire-canvas');
      canvas.width = W * 2;
      canvas.height = H * 2;
      canvas.tabIndex = 0;
      canvas.setAttribute('role', 'application');
      canvas.setAttribute('aria-label', this.opts.label || 'TI-Nspire');
      const overlay = el('div', 'nspire-menu');
      overlay.hidden = true;
      const status = el('div', 'nspire-status', '…');
      const input = el('input', 'nspire-input');
      input.type = 'text';
      input.autocomplete = 'off';
      input.autocapitalize = 'off';
      input.spellcheck = false;
      input.setAttribute('aria-label', 'keyboard');
      screen.append(bar, canvas, overlay, status, input);
      r.append(screen);
      if (this.opts.keypad) {
        const pad = el('div', 'nspire-keys');
        for (const [cls, label, ev] of KEYPAD) {
          const b = el('button', 'nspire-key k-' + cls, label);
          b.type = 'button';
          b.tabIndex = -1;
          b.setAttribute('aria-label', cls);
          b.addEventListener('click', (e) => {
            e.preventDefault();
            this.stopPlaying();
            if (ev === 'menu') this.toggleMenu();
            else if (ev === 'kbd') this.showKeyboard();
            else if (this.menuState) this.menuKey(ev);
            else this.send(ev);
            if (ev !== 'kbd') this.canvas.focus({ preventScroll: true });
          });
          pad.append(b);
        }
        r.append(pad);
      }
      this.screenEl = screen;
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.overlay = overlay;
      this.statusEl = status;
      this.input = input;

      canvas.addEventListener('keydown', (e) => this.onKey(e));
      canvas.addEventListener('mousedown', (e) => {
        if (!this.core || e.button !== 0) return;
        this.stopPlaying();
        const p = this.toLogical(e);
        this.send('mouse', p.x, p.y);
      });
      canvas.addEventListener('wheel', (e) => {
        if (document.activeElement !== canvas || !this.core) return;
        e.preventDefault();
        this.wheel = (this.wheel || 0) + e.deltaY;
        while (Math.abs(this.wheel) >= 40) {
          this.send(this.wheel > 0 ? 'down' : 'up');
          this.wheel -= Math.sign(this.wheel) * 40;
        }
      }, { passive: false });
      input.addEventListener('input', () => {
        const v = input.value;
        input.value = '';
        for (const ch of v) this.send('char', ch);
      });
      input.addEventListener('keydown', (e) => {
        const map = { Enter: 'enter', Backspace: 'backspace', Tab: 'tab', Escape: 'esc' };
        if (map[e.key] && !input.value) {
          e.preventDefault();
          this.send(map[e.key]);
        }
      });
      input.addEventListener('blur', () => { this.screenEl.classList.remove('typing'); });
      if (window.ResizeObserver) {
        new ResizeObserver(() => this.redraw()).observe(canvas);
      } else {
        window.addEventListener('resize', () => this.redraw());
      }
    }

    setStatus(text) {
      this.statusEl.textContent = text || '';
      this.statusEl.hidden = !text;
    }

    async start() {
      if (this.core) return;
      if (this.starting) return this.starting;
      this.setStatus('…');
      this.starting = (async () => {
        try {
          const s = await loadShared();
          const core = new window.NspireCore(s.factory, s.sources, {
            lang: this.opts.lang,
            measure,
            copy: (t) => { if (navigator.clipboard) navigator.clipboard.writeText(t).catch(() => {}); },
          });
          const buf = await core.boot();
          this.core = core;
          this.setStatus('');
          this.draw(buf);
        } catch (err) {
          console.error(err);
          this.setStatus('⚠ ' + (err && err.message ? err.message : err));
          throw err;
        } finally {
          this.starting = null;
        }
      })();
      return this.starting;
    }

    // Back to a freshly opened document
    async reset(lang) {
      this.stopPlaying();
      this.closeMenu();
      if (lang) this.opts.lang = lang;
      if (this.core) this.core.close();
      this.core = null;
      await this.start();
    }

    toLogical(e) {
      const b = this.canvas.getBoundingClientRect();
      return {
        x: Math.max(0, Math.min(W - 1, Math.floor((e.clientX - b.left) / b.width * W))),
        y: Math.max(0, Math.min(H - 1, Math.floor((e.clientY - b.top) / b.height * H))),
      };
    }

    send(name, a, b) {
      if (!this.core) return;
      let buf = null;
      try {
        buf = this.core.event(name, a, b);
      } catch (err) {
        console.error(err);
      }
      if (buf !== null) this.draw(buf);
    }

    onKey(e) {
      if (!this.core) return;
      this.stopPlaying();
      if (this.menuState) {
        const k = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', Enter: 'enter', Escape: 'esc', Backspace: 'esc' }[e.key];
        if (k) { e.preventDefault(); this.menuKey(k); return; }
        if (/^[0-9a-z]$/i.test(e.key)) { e.preventDefault(); this.menuKey('char', e.key); return; }
        return;
      }
      const ctrl = e.ctrlKey || e.metaKey;
      if (ctrl && (e.key === 'c' || e.key === 'C')) { e.preventDefault(); this.send('copy'); return; }
      if (ctrl && (e.key === 'x' || e.key === 'X')) { e.preventDefault(); this.send('cut'); return; }
      if (ctrl && (e.key === 'v' || e.key === 'V')) {
        e.preventDefault();
        if (navigator.clipboard && navigator.clipboard.readText) {
          navigator.clipboard.readText().then((t) => { this.core.setClipboard(t); this.send('paste'); }).catch(() => this.send('paste'));
        } else {
          this.send('paste');
        }
        return;
      }
      const map = {
        Enter: e.shiftKey ? 'return' : 'enter', Tab: e.shiftKey ? 'backtab' : 'tab', Escape: 'esc',
        ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
        Backspace: 'backspace', Delete: 'clear', F1: 'help', F3: 'ctx',
      };
      if (e.key === 'F2' || e.key === 'ContextMenu') { e.preventDefault(); this.toggleMenu(); return; }
      const ev = map[e.key];
      if (ev) { e.preventDefault(); this.send(ev); return; }
      if (!ctrl && !e.altKey && [...e.key].length === 1) {
        e.preventDefault();
        this.send('char', e.key);
      }
    }

    showKeyboard() {
      this.screenEl.classList.add('typing');
      this.input.value = '';
      this.input.focus();
    }

    // Toolpalette (menu key) ------------------------------------------------

    toggleMenu() {
      if (this.menuState) this.closeMenu();
      else this.openMenu();
    }

    openMenu() {
      if (!this.core) return;
      const menus = this.core.menu();
      if (!menus.length) return;
      this.menuState = { menus, top: 0, sub: -1, item: 0 };
      this.renderMenu();
    }

    closeMenu() {
      this.menuState = null;
      this.overlay.hidden = true;
      this.overlay.textContent = '';
    }

    menuKey(k, ch) {
      const m = this.menuState;
      if (!m) return;
      const open = m.sub >= 0;
      const list = open ? m.menus[m.sub].items : m.menus;
      const n = list.length;
      if (k === 'char') {
        const idx = parseInt(ch, 36) - 1;
        if (idx >= 0 && idx < n) {
          if (open) { m.item = idx; return this.chooseItem(); }
          m.top = idx; m.sub = idx; m.item = 0;
        }
      } else if (k === 'up') {
        if (open) m.item = (m.item + n - 1) % n; else m.top = (m.top + n - 1) % n;
      } else if (k === 'down') {
        if (open) m.item = (m.item + 1) % n; else m.top = (m.top + 1) % n;
      } else if (k === 'right' || k === 'enter') {
        if (open) return this.chooseItem();
        m.sub = m.top; m.item = 0;
      } else if (k === 'left' || k === 'esc' || k === 'backspace') {
        if (open) m.sub = -1; else return this.closeMenu();
      }
      this.renderMenu();
    }

    chooseItem() {
      const m = this.menuState;
      const sub = m.sub;
      const item = m.item;
      this.closeMenu();
      let buf = null;
      try { buf = this.core.menuSelect(sub, item); } catch (err) { console.error(err); }
      if (buf !== null) this.draw(buf);
    }

    renderMenu() {
      const m = this.menuState;
      const o = this.overlay;
      o.textContent = '';
      o.hidden = false;
      const col = (items, sel, isTop) => {
        const ul = el('ul', 'nspire-menu-list' + (isTop ? ' top' : ' sub'));
        items.forEach((t, i) => {
          const li = el('li', i === sel ? 'sel' : '');
          li.append(el('span', 'num', (i + 1).toString(36).toUpperCase()), el('span', 'txt', t));
          if (isTop) li.append(el('span', 'arr', '▸'));
          li.addEventListener('mousedown', (e) => {
            e.preventDefault();
            if (isTop) { m.top = i; m.sub = i; m.item = 0; this.renderMenu(); } else { m.item = i; this.chooseItem(); }
            this.canvas.focus({ preventScroll: true });
          });
          ul.append(li);
        });
        return ul;
      };
      o.append(col(m.menus.map((x) => x.title), m.sub >= 0 ? m.sub : m.top, true));
      if (m.sub >= 0) o.append(col(m.menus[m.sub].items, m.item, false));
      o.classList.toggle('open-sub', m.sub >= 0);
    }

    // Drawing ----------------------------------------------------------------

    redraw() {
      if (this.last) this.draw(this.last);
      const w = this.canvas.clientWidth;
      if (w) this.root.style.setProperty('--k', String(w / W));
    }

    draw(buf) {
      this.last = buf;
      const c = this.canvas;
      const dpr = window.devicePixelRatio || 1;
      const cw = Math.max(W, Math.round((c.clientWidth || W * 2) * dpr));
      const ch = Math.round(cw * H / W);
      if (c.width !== cw || c.height !== ch) { c.width = cw; c.height = ch; }
      const g = this.ctx;
      const kx = cw / W;
      const ky = ch / H;
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.fillStyle = '#ffffff';
      g.fillRect(0, 0, cw, ch);
      g.setTransform(kx, 0, 0, ky, 0, 0);
      g.save();
      const st = { color: '#000000', font: fontCss('sansserif', 'r', 11), size: 11, width: 1, dash: [] };
      const apply = () => {
        g.fillStyle = st.color;
        g.strokeStyle = st.color;
        g.font = st.font;
        g.lineWidth = st.width;
        g.setLineDash(st.dash);
      };
      apply();
      const recs = buf.split(RS);
      for (let i = 0; i < recs.length; i++) {
        const a = recs[i].split(US);
        const op = a[0];
        const n = (k) => parseFloat(a[k]);
        switch (op) {
          case 'F':
            st.size = n(3) || 11;
            st.font = fontCss(a[1], a[2], st.size);
            g.font = st.font;
            break;
          case 'C':
            st.color = hex(a[1]);
            g.fillStyle = st.color;
            g.strokeStyle = st.color;
            break;
          case 'P':
            st.width = a[1] === 'thick' ? 3 : a[1] === 'medium' ? 2 : 1;
            st.dash = a[2] === 'dotted' ? [1, 2] : a[2] === 'dashed' ? [4, 3] : [];
            g.lineWidth = st.width;
            g.setLineDash(st.dash);
            break;
          case 'R':
            g.fillRect(n(1), n(2), n(3), n(4));
            break;
          case 'r':
            g.strokeRect(n(1) + 0.5, n(2) + 0.5, n(3), n(4));
            break;
          case 'L':
            g.beginPath();
            g.moveTo(n(1) + 0.5, n(2) + 0.5);
            g.lineTo(n(3) + 0.5, n(4) + 0.5);
            g.stroke();
            break;
          case 'A':
          case 'a': {
            const w = n(3);
            const h = n(4);
            const a0 = (n(5) || 0) * Math.PI / 180;
            const d = (isNaN(n(6)) ? 360 : n(6)) * Math.PI / 180;
            g.beginPath();
            if (op === 'A' && Math.abs(d) < 2 * Math.PI - 1e-6) g.moveTo(n(1) + w / 2, n(2) + h / 2);
            g.ellipse(n(1) + w / 2, n(2) + h / 2, Math.max(w / 2, 0.01), Math.max(h / 2, 0.01), 0, -a0, -a0 - d, d > 0);
            if (op === 'A') g.fill(); else g.stroke();
            break;
          }
          case 'G':
          case 'g': {
            g.beginPath();
            for (let k = 1; k + 1 < a.length; k += 2) {
              const x = parseFloat(a[k]) + (op === 'g' ? 0.5 : 0);
              const y = parseFloat(a[k + 1]) + (op === 'g' ? 0.5 : 0);
              if (k === 1) g.moveTo(x, y); else g.lineTo(x, y);
            }
            if (op === 'G') { g.closePath(); g.fill(); } else g.stroke();
            break;
          }
          case 'S': {
            const text = window.NspireCore.tiText(a.slice(4).join(US));
            const x = n(1);
            let y = n(2);
            const align = a[3];
            if (align === 'baseline') g.textBaseline = 'alphabetic';
            else if (align === 'middle') g.textBaseline = 'middle';
            else if (align === 'bottom') g.textBaseline = 'bottom';
            else { g.textBaseline = 'alphabetic'; y += st.size * 1.12; }
            g.fillText(text, x, y);
            break;
          }
          case 'k':
            g.restore();
            g.save();
            g.beginPath();
            g.rect(n(1), n(2), n(3), n(4));
            g.clip();
            apply();
            break;
          case 'K':
            g.restore();
            g.save();
            apply();
            break;
          default:
            break;
        }
      }
      g.restore();
    }

    // Tutorials --------------------------------------------------------------

    stopPlaying() {
      this.playing++;
      this.root.classList.remove('playing');
    }

    // Play a key script ("50{enter}{down*3}") with a typing rhythm; resolves
    // false when interrupted (the user pressed a key, or another play began)
    async play(script, opts) {
      opts = opts || {};
      if (!this.core) await this.start();
      const id = ++this.playing;
      this.root.classList.add('playing');
      const keys = window.NspireCore.parseScript(script);
      const charDelay = opts.charDelay || 70;
      const keyDelay = opts.keyDelay || 260;
      for (const [name, arg] of keys) {
        if (id !== this.playing) return false;
        if (name === 'wait') { await sleep(600); continue; }
        if (name === 'menu') { this.openMenu(); await sleep(keyDelay); continue; }
        if (this.menuState) this.menuKey(name, arg);
        else this.send(name, arg);
        await sleep(name === 'char' ? charDelay : keyDelay);
      }
      if (id === this.playing) this.root.classList.remove('playing');
      return id === this.playing;
    }

    // Run a key script at once (no animation)
    run(script) {
      for (const [name, arg] of window.NspireCore.parseScript(script)) {
        if (name === 'wait') continue;
        if (name === 'menu') { this.openMenu(); continue; }
        if (this.menuState) this.menuKey(name, arg);
        else if (this.core) {
          try { this.core.event(name, arg); } catch (err) { console.error(err); }
        }
      }
      if (this.core) this.draw(this.core.paint());
    }
  }

  window.NspireCalc = Calc;
})();
