// Runs the VCE toolkit (host.lua + the vce_web bundle) in Lua 5.4 compiled to
// WebAssembly (wasmoon). No DOM here: emulator.js draws the paint buffers on
// a canvas, and site/test/emu.test.mjs runs the same core in Node.
(function (root) {
  'use strict';

  const RS = '\x1e';
  const US = '\x1f';

  // TI private-use characters → what the calculator shows
  const TI_CHARS = {
    '': 'e', '': 'E', '': '⁻¹', '': 'i',
    '': 'ʳ', '': 'ᵍ', '': 'ᵀ',
  };
  const TI_RE = new RegExp('[' + Object.keys(TI_CHARS).join('') + ']', 'g');
  function tiText(s) {
    return s.replace(TI_RE, (c) => TI_CHARS[c]);
  }

  // Key names in tutorial scripts: "{enter}", "{down*3}", plain text is typed
  function parseScript(script) {
    const out = [];
    const re = /\{([a-z]+)(?:\*(\d+))?\}|([\s\S])/gu;
    let m;
    while ((m = re.exec(script))) {
      if (m[1]) {
        const n = m[2] ? parseInt(m[2], 10) : 1;
        for (let i = 0; i < n; i++) out.push([m[1]]);
      } else {
        out.push(['char', m[3]]);
      }
    }
    return out;
  }

  class NspireCore {
    // sources: { host, app } Lua source text; opts: { lang, measure(text, fam, style, size), copy(text) }
    constructor(factory, sources, opts) {
      this.factory = factory;
      this.sources = sources;
      this.opts = opts || {};
      this.lua = null;
    }

    async boot() {
      const lua = await this.factory.createEngine({ injectObjects: false, enableProxy: false });
      this.lua = lua;
      const measure = this.opts.measure || ((s, fam, st, size) => s.length * size * 0.7);
      lua.global.set('js_measure', (s, fam, st, size) => measure(tiText(String(s)), fam, st, size));
      lua.global.set('js_copy', (s) => { if (this.opts.copy) this.opts.copy(tiText(String(s))); });
      lua.global.set('WEB_LANG', this.opts.lang === 'bi' ? 'bi' : 'en');
      lua.doStringSync(this.sources.host);
      lua.doStringSync(this.sources.app);
      this.fn = {
        start: lua.global.get('host_start'),
        event: lua.global.get('host_event'),
        paint: lua.global.get('host_paint'),
        menu: lua.global.get('host_menu'),
        select: lua.global.get('host_menu_select'),
        setClip: lua.global.get('host_set_clip'),
        results: lua.global.get('host_results'),
        screen: lua.global.get('host_screen'),
      };
      return this.fn.start();
    }

    // Returns a paint buffer when the screen changed (else null)
    event(name, a, b) {
      // wasmoon cannot pass null: leave missing arguments out
      const args = [name];
      if (a !== undefined && a !== null) args.push(a);
      if (b !== undefined && b !== null) args.push(b);
      const res = this.fn.event(...args);
      return typeof res === 'string' ? res : null;
    }

    paint() {
      return this.fn.paint();
    }

    menu() {
      const s = this.fn.menu();
      if (!s) return [];
      return s.split(RS).map((m) => {
        const parts = m.split(US);
        return { title: tiText(parts[0]), items: parts.slice(1).map(tiText) };
      });
    }

    menuSelect(i, j) {
      const res = this.fn.select(i + 1, j + 1);
      return typeof res === 'string' ? res : null;
    }

    setClipboard(text) {
      this.fn.setClip(text);
    }

    // Answer rows of the open problem, "key=value" (tests)
    results() {
      return this.fn.results ? String(this.fn.results() || '') : '';
    }

    screen() {
      return this.fn.screen ? String(this.fn.screen() || '') : '';
    }

    close() {
      if (this.lua) {
        try { this.lua.global.close(); } catch (e) { /* already closed */ }
        this.lua = null;
      }
    }
  }

  NspireCore.parseScript = parseScript;
  NspireCore.tiText = tiText;
  NspireCore.RS = RS;
  NspireCore.US = US;

  if (typeof module !== 'undefined' && module.exports) module.exports = NspireCore;
  else root.NspireCore = NspireCore;
})(typeof globalThis !== 'undefined' ? globalThis : this);
